# Shared bats helpers: isolated HOME/PATH + PATH-shadow fakes.
#
# Fakes log every invocation to $VIBE_FAKE_LOG so tests assert against real
# command lookup + args, with no network or installs. bash-3.2-clean.

# shellcheck disable=SC2034  # consumed by test files that `load` this helper
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"

# Isolated HOME + a hermetic PATH whose first entry is our fakes dir.
# We deliberately exclude the real ~/.local/bin and brew bin so the only
# claude/codex/gh/curl/mise/node reachable are the fakes we opt into.
setup_isolated_env() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export FAKES="$BATS_TEST_TMPDIR/bin"
  export VIBE_FAKE_LOG="$BATS_TEST_TMPDIR/fake.log"
  mkdir -p "$HOME" "$FAKES"
  : > "$VIBE_FAKE_LOG"
  export PATH="$FAKES:/usr/bin:/bin:/usr/sbin:/sbin"
  # Deterministic, colourless output regardless of the invoking terminal.
  export NO_COLOR=1
}

# Fake bodies below are built as literal strings; $-expansions in them are
# deliberately deferred to the fake's run time, so single quotes are correct.
# shellcheck disable=SC2016
#
# make_fake <name> [body...] — writes an executable that logs "<name> <args>"
# to $VIBE_FAKE_LOG. Extra lines are appended as the fake's body (they may read
# "$@" and write to "$VIBE_FAKE_LOG", both inherited at run time).
make_fake() {
  name="$1"; shift
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'printf "%s\n" "'"$name"' $*" >> "$VIBE_FAKE_LOG"'
    [ $# -gt 0 ] && printf '%s\n' "$@"
    printf '%s\n' 'exit 0'
  } > "$FAKES/$name"
  chmod +x "$FAKES/$name"
}

# shellcheck disable=SC2016
# A curl fake that, for the vendor CLI installer URLs, emits a one-line script
# (consumed by the `curl … | bash` pipe) that records the install in the log.
make_fake_curl() {
  make_fake curl \
    'for a in "$@"; do url="$a"; done' \
    'case "$url" in' \
    '  *claude.ai/install.sh*)       printf "%s\n" '\''printf "INSTALL claude\n" >> "$VIBE_FAKE_LOG"'\'' ;;' \
    '  *chatgpt.com/codex/install.sh*) printf "%s\n" '\''printf "INSTALL codex %s\n" "${CODEX_NON_INTERACTIVE:-unset}" >> "$VIBE_FAKE_LOG"'\'' ;;' \
    '  *mise.run*)                   printf "%s\n" '\''printf "INSTALL mise %s\n" "${MISE_INSTALL_HELP:-unset}" >> "$VIBE_FAKE_LOG"'\'' ;;' \
    'esac'
}

# gh fake: pretends the user is already authenticated (auth status -> 0).
make_fake_gh() {
  make_fake gh
}

# gh fake that reports NOT authenticated (auth status -> non-zero).
make_fake_gh_unauth() {
  make_fake gh 'if [ "$1 ${2:-}" = "auth status" ]; then exit 1; fi'
}

# require_git — skip a test that asserts REAL git behaviour when git is absent.
# A few cases check that the starter dir became a genuine repo, which cannot be
# faked without asserting the fake instead. macOS always has git and the CI Linux
# images install it; a bare image without it should say so rather than fail.
require_git() {
  command -v git >/dev/null 2>&1 || skip "git not available"
}

# --- tiny assertions (avoid a bats-assert dependency) ---------------------------

# fake_logged <pattern> — grep -F the invocation log.
fake_logged() {
  grep -Fq -- "$1" "$VIBE_FAKE_LOG"
}

refute_fake_logged() {
  ! grep -Fq -- "$1" "$VIBE_FAKE_LOG"
}
