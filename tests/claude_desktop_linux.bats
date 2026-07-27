#!/usr/bin/env bats
#
# blocks/claude-desktop/apply.sh — the Claude desktop app on the Debian family,
# which is the one *-desktop app with an official Linux build (an Anthropic apt
# beta). Two things make it a script rather than a cell: it needs a sudo password
# (which spin would erase as it is typed), and registering a third-party repo means
# trusting a signing key — so the fingerprint is checked HERE rather than printed for
# a beginner to eyeball.
#
# The refusal case is the one that matters: a key that is not the expected one must
# stop the install, not warn and carry on into apt.

load helpers/common

setup() {
  # Resolve gpg on the HOST PATH, before setup_isolated_env narrows it: a real
  # fingerprint check needs real gpg, and a faked one would assert nothing about the
  # only thing here worth asserting.
  GPG_BIN="$(command -v gpg || true)"
  GPGCONF_BIN="$(command -v gpgconf || true)"
  setup_isolated_env
  [ -n "$GPG_BIN" ] || skip "gpg not available"
  ln -sf "$GPG_BIN" "$FAKES/gpg"
  [ -n "$GPGCONF_BIN" ] && ln -sf "$GPGCONF_BIN" "$FAKES/gpgconf"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  KEYDIR="$BATS_TEST_TMPDIR/keys"
  mkdir -p "$KEYDIR"
}

# make_key <name> — generate a throwaway key, export it, and echo its fingerprint.
make_key() {
  export GNUPGHOME="$KEYDIR/$1"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  gpg --batch --quiet --passphrase '' --quick-generate-key "$1 <$1@example.test>" \
    default default never >/dev/null 2>&1
  gpg --batch --quiet --armor --export "$1@example.test" > "$KEYDIR/$1.asc"
  gpg --batch --with-colons --fingerprint "$1@example.test" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }'
}

# apply_desktop — run the tail with a faked apt/sudo/install/tee and a key served
# from a file:// URL, so nothing touches the network or the real system.
apply_desktop() {
  run env VIBE_LIB="$REPO_ROOT/lib" VIBE_ROOT="$REPO_ROOT" VIBE_OS=linux \
    VIBE_CLAUDE_KEY_URL="$1" GNUPGHOME="${GNUPGHOME:-}" \
    VIBE_BLOCK_DIR="$REPO_ROOT/blocks/claude-desktop" VIBE_BLOCK_ID=claude-desktop \
    bash "$REPO_ROOT/blocks/claude-desktop/apply.sh"
}

# The system-touching commands, all faked: install/tee would write to /usr and /etc.
fake_system() {
  make_fake apt-get
  make_fake sudo 'if [ "$1" = "-v" ]; then exit 0; fi' 'exec "$@"'
  make_fake install
  make_fake tee 'cat >/dev/null'
  # curl serves the key from the local file the test generated.
  make_fake curl 'for a in "$@"; do url="$a"; done' 'cat "${url#file://}"'
}

@test "the expected key installs the app" {
  fpr="$(make_key good)"
  fake_system
  # Pin the fingerprint the script requires to the throwaway key we just made, so
  # the happy path is exercised without shipping Anthropic's private key.
  sed "s/^KEY_FPR=.*/KEY_FPR=\"$fpr\"/" "$REPO_ROOT/blocks/claude-desktop/apply.sh" \
    > "$BATS_TEST_TMPDIR/apply.sh"
  run env VIBE_LIB="$REPO_ROOT/lib" VIBE_ROOT="$REPO_ROOT" VIBE_OS=linux \
    VIBE_CLAUDE_KEY_URL="file://$KEYDIR/good.asc" \
    VIBE_BLOCK_DIR="$REPO_ROOT/blocks/claude-desktop" VIBE_BLOCK_ID=claude-desktop \
    bash "$BATS_TEST_TMPDIR/apply.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checked the Claude app's signing key"* ]]
  fake_logged "apt-get install -y -qq claude-desktop"
}

@test "a key that is not the expected one refuses, and never reaches apt" {
  make_key evil >/dev/null
  fake_system
  apply_desktop "file://$KEYDIR/evil.asc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not the one we expect"* ]]
  # the whole point: no repo registered, no install attempted
  refute_fake_logged "apt-get"
  refute_fake_logged "install -m 0644"
  # and it says what is unaffected, so the run still makes sense to a beginner
  [[ "$output" == *"terminal one"* ]]
}

@test "a download that yields nothing skips the app instead of trusting it" {
  fake_system
  make_fake curl 'exit 1'
  make_fake wget 'exit 1'
  apply_desktop "file://$KEYDIR/missing.asc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"couldn't download"* ]]
  refute_fake_logged "apt-get"
}

@test "no apt-get: says the app is Debian-only and points at the CLI" {
  make_fake sudo 'exec "$@"'
  make_fake curl
  # PATH narrowed to the fakes dir alone, so "no apt-get" is real: on a Debian-family
  # host (or CI container) /usr/bin/apt-get would otherwise answer, and this case
  # would silently exercise the install path instead.
  for _b in env bash id cat tr basename dirname mkdir mktemp rm; do
    [ -e "$FAKES/$_b" ] || ln -sf "$(command -v "$_b")" "$FAKES/$_b"
  done
  _wide_path="$PATH"
  PATH="$FAKES" run env VIBE_LIB="$REPO_ROOT/lib" VIBE_ROOT="$REPO_ROOT" VIBE_OS=linux \
    VIBE_CLAUDE_KEY_URL="file://$KEYDIR/none.asc" \
    VIBE_BLOCK_DIR="$REPO_ROOT/blocks/claude-desktop" VIBE_BLOCK_ID=claude-desktop \
    bash "$REPO_ROOT/blocks/claude-desktop/apply.sh"
  export PATH="$_wide_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"only ships for Debian/Ubuntu"* ]]
  [[ "$output" == *"terminal one"* ]]
}

@test "already installed: nothing is fetched or registered" {
  make_fake claude-desktop
  fake_system
  apply_desktop "file://$KEYDIR/none.asc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_fake_logged "apt-get"
  refute_fake_logged "curl"
}

@test "on a Mac the Linux installer does not run" {
  fake_system
  run env VIBE_LIB="$REPO_ROOT/lib" VIBE_ROOT="$REPO_ROOT" VIBE_OS=mac \
    VIBE_BLOCK_DIR="$REPO_ROOT/blocks/claude-desktop" VIBE_BLOCK_ID=claude-desktop \
    bash "$REPO_ROOT/blocks/claude-desktop/apply.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  refute_fake_logged "apt-get"
}
