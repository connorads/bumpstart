#!/usr/bin/env bats
#
# The `bumpstart` bootstrap — the script a pasting user hits FIRST, and until now the
# only executable in the repo that nothing ran (catalogue.bats' `bumpstart()` helper
# calls lib/apply.sh; the real bootstrap was shellcheck'd and no more).
#
# It matters because its platform guard is deliberately duplicated from
# lib/apply.sh: the guard has to answer before the tarball fetch, so lib/os.sh
# does not exist yet. Duplication with no test is how two guards drift apart, so
# the last case here holds them to the same verdict for the same machine.
#
# No network: curl/wget are fakes, and `tar` is a fake that materialises the
# layout the bootstrap expects, including a stub lib/apply.sh which logs and
# exits — so the final `exec` is observable rather than inferred.

load helpers/common

setup() {
  setup_isolated_env
  # Keep the bootstrap's mktemp -d inside the test's own tmp tree: on success it
  # execs and deliberately leaves the dir behind for the applier to use.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
}

# A tar fake that extracts the layout `bumpstart` globs for: <-C dir>/bumpstart-main/
# with lib/apply.sh inside. BUMP_TAR_BAD=1 omits the apply.sh, which is the
# unexpected-layout path. It drains stdin so the fetcher upstream of the pipe
# never takes a SIGPIPE.
make_fake_tar() {
  cat > "$FAKES/tar" <<'TAR'
#!/bin/bash
printf '%s\n' "tar $*" >> "$BUMP_FAKE_LOG"
dest="."; prev=""
for a in "$@"; do
  [ "$prev" = "-C" ] && dest="$a"
  prev="$a"
done
cat >/dev/null
mkdir -p "$dest/bumpstart-main/lib"
if [ -z "${BUMP_TAR_BAD:-}" ]; then
  printf '%s\n%s\n' '#!/bin/bash' 'printf "APPLY %s\n" "$*" >> "$BUMP_FAKE_LOG"' \
    > "$dest/bumpstart-main/lib/apply.sh"
fi
exit 0
TAR
  chmod +x "$FAKES/tar"
}

boot() { run bash "$REPO_ROOT/bumpstart" "$@"; }

# boot_curlless <id>... — run the bootstrap with ONLY the fakes dir on PATH, so
# "curl absent" is real rather than shadowed by /usr/bin/curl. The few real
# binaries needed are symlinked in; PATH is restored before the assertions, which
# use grep. Call it after the fakes are written — make_fake needs chmod.
boot_curlless() {
  ln -sf /bin/bash "$FAKES/bash"
  # mktemp/rm for the bootstrap itself; cat/mkdir for the tar fake's own body.
  for _b in mktemp rm cat mkdir; do ln -sf "$(command -v "$_b")" "$FAKES/$_b"; done
  _wide_path="$PATH"
  PATH="$FAKES" run bash "$REPO_ROOT/bumpstart" "$@"
  export PATH="$_wide_path"
}

@test "on a Mac it fetches the tarball and hands the ids to the applier" {
  make_fake uname 'printf "Darwin\n"'
  make_fake curl
  make_fake_tar
  boot claude starter
  [ "$status" -eq 0 ]
  fake_logged "curl -fsSL https://codeload.github.com/connorads/bumpstart/tar.gz/main"
  fake_logged "APPLY claude starter"
}

@test "BUMP_REF pins the fetched ref" {
  make_fake uname 'printf "Darwin\n"'
  make_fake curl
  make_fake_tar
  BUMP_REF=abc123 boot claude
  [ "$status" -eq 0 ]
  fake_logged "tar.gz/abc123"
}

@test "native Windows is redirected to the PowerShell paste, before any fetch" {
  make_fake uname 'printf "MINGW64_NT-10.0\n"'
  make_fake curl
  make_fake_tar
  boot claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"On Windows, open PowerShell"* ]]
  [[ "$output" == *"bumpstart.ps1"* ]]
  # the redirect is the point: nothing was downloaded and nothing was applied
  refute_fake_logged "curl"
  refute_fake_logged "APPLY"
}

@test "on Linux it fetches and hands the ids to the applier, same as a Mac" {
  make_fake uname 'printf "Linux\n"'
  make_fake curl
  make_fake_tar
  boot claude starter
  [ "$status" -eq 0 ]
  fake_logged "APPLY claude starter"
}

@test "WSL 1 is refused with the one command that fixes it, before any fetch" {
  make_fake uname 'printf "Linux\n"'
  make_fake curl
  make_fake_tar
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '4.4.0-19041-Microsoft\n' > "$BUMP_OSRELEASE_FILE"
  WSL_DISTRO_NAME=Ubuntu boot claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"WSL 1"* ]]
  # the actionable bit, with their own distro named
  [[ "$output" == *"wsl --set-version Ubuntu 2"* ]]
  refute_fake_logged "curl"
  refute_fake_logged "APPLY"
}

@test "WSL 2 is not caught by the WSL 1 refusal" {
  make_fake uname 'printf "Linux\n"'
  make_fake curl
  make_fake_tar
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '5.15.153.1-microsoft-standard-WSL2\n' > "$BUMP_OSRELEASE_FILE"
  boot claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"WSL 1"* ]]
}

@test "with no curl it fetches via wget instead" {
  make_fake uname 'printf "Darwin\n"'
  make_fake wget
  make_fake_tar
  boot_curlless claude
  [ "$status" -eq 0 ]
  fake_logged "wget -qO- https://codeload.github.com/connorads/bumpstart/tar.gz/main"
  fake_logged "APPLY claude"
}

@test "with neither curl nor wget it says so instead of failing silently" {
  make_fake uname 'printf "Darwin\n"'
  make_fake_tar
  boot_curlless claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"need curl or wget"* ]]
  refute_fake_logged "APPLY"
}

@test "a failed fetch names the ref and the connection, and applies nothing" {
  make_fake uname 'printf "Darwin\n"'
  make_fake curl 'exit 1'
  make_fake_tar
  boot claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch"* ]]
  refute_fake_logged "APPLY"
}

@test "an unexpected tarball layout is an error, not a silent exec" {
  make_fake uname 'printf "Darwin\n"'
  make_fake curl
  make_fake_tar
  export BUMP_TAR_BAD=1
  boot claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected tarball layout"* ]]
  refute_fake_logged "APPLY"
}

@test "the bootstrap and the applier reach the same verdict for the same machine" {
  # The drift guard. bumpstart's guard cannot call bump_os() (it must answer before the
  # fetch that delivers lib/os.sh), so the two are hand-kept in step — and a
  # supported OS still refused at the paste is invisible to every test that drives
  # lib/apply.sh directly.
  make_fake curl
  make_fake_tar
  for _sys in Darwin Linux MINGW64_NT-10.0; do
    make_fake uname "printf '$_sys\n'"

    : > "$BUMP_FAKE_LOG"
    run bash "$REPO_ROOT/bumpstart" claude --plan
    if fake_logged "APPLY"; then _boot=proceed; else _boot=refuse; fi

    # --plan is after the guard and has no effects, so this asks the applier the
    # same question without applying anything. Keyed on the plan actually being
    # rendered, not on the refusal's wording, so a copy edit can't fake agreement.
    run bash "$REPO_ROOT/lib/apply.sh" claude --plan
    case "$output" in
      *"This will set up"*) _appl=proceed ;;
      *)                    _appl=refuse ;;
    esac

    if [ "$_boot" != "$_appl" ]; then
      printf 'guard drift on %s: bootstrap=%s applier=%s\n' "$_sys" "$_boot" "$_appl" >&2
      return 1
    fi
  done
}
