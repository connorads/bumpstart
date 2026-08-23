# Shared bats helpers: isolated HOME/PATH + PATH-shadow fakes.
#
# Fakes log every invocation to $BUMP_FAKE_LOG so tests assert against real
# command lookup + args, with no network or installs. bash-3.2-clean.

# shellcheck disable=SC2034  # consumed by test files that `load` this helper
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"

# Isolated HOME + a hermetic PATH whose first entry is our fakes dir.
# We deliberately exclude the real ~/.local/bin and brew bin so the only
# claude/codex/gh/curl/mise/node reachable are the fakes we opt into.
setup_isolated_env() {
  export HOME="$BATS_TEST_TMPDIR/home"
  # An isolated HOME is not enough: _shell_rc (lib/shellpath.sh) reads ZDOTDIR and
  # XDG_CONFIG_HOME in PREFERENCE to $HOME, so a contributor who exports either gets
  # bumpstart's marker block appended to their own rc file by `mise run test` — once, and
  # then "already knows" forever, so it leaks silently and never says so again.
  # Pinned rather than unset, per this suite's own convention, and pinned to exactly
  # the value each falls back to when unset, so nothing about today's behaviour moves.
  export ZDOTDIR="$HOME"
  export XDG_CONFIG_HOME="$HOME/.config"
  export FAKES="$BATS_TEST_TMPDIR/bin"
  export BUMP_FAKE_LOG="$BATS_TEST_TMPDIR/fake.log"
  mkdir -p "$HOME" "$FAKES"
  : > "$BUMP_FAKE_LOG"
  export PATH="$FAKES:/usr/bin:/bin:/usr/sbin:/sbin"
  # Deterministic, colourless output regardless of the invoking terminal.
  export NO_COLOR=1
}

# Fake bodies below are built as literal strings; $-expansions in them are
# deliberately deferred to the fake's run time, so single quotes are correct.
# shellcheck disable=SC2016
#
# make_fake <name> [body...] — writes an executable that logs "<name> <args>"
# to $BUMP_FAKE_LOG. Extra lines are appended as the fake's body (they may read
# "$@" and write to "$BUMP_FAKE_LOG", both inherited at run time).
make_fake() {
  name="$1"; shift
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'printf "%s\n" "'"$name"' $*" >> "$BUMP_FAKE_LOG"'
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
    '  *claude.ai/install.sh*)       printf "%s\n" '\''printf "INSTALL claude\n" >> "$BUMP_FAKE_LOG"'\'' ;;' \
    '  *chatgpt.com/codex/install.sh*) printf "%s\n" '\''printf "INSTALL codex %s\n" "${CODEX_NON_INTERACTIVE:-unset}" >> "$BUMP_FAKE_LOG"'\'' ;;' \
    '  *mise.run*)                   printf "%s\n" '\''printf "INSTALL mise %s\n" "${MISE_INSTALL_HELP:-unset}" >> "$BUMP_FAKE_LOG"'\'' ;;' \
    '  *Homebrew/install*)           printf "%s\n" '\''printf "INSTALL brew\n" >> "$BUMP_FAKE_LOG"'\'' ;;' \
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

# --- a real terminal, for the prompts that insist on one ------------------------
#
# bats gives every test a redirected stdin, which is exactly the condition an
# `[ -t 0 ]` gate exists to detect — so without a pty the prompt branches in the
# product are unreachable, and the only thing a test could assert about them is
# that they are skipped. script(1) supplies one.
#
# Two facts about script(1) shape tty_run. It closes the pty the instant its own
# stdin closes, so the keystrokes are followed by a pause the program can read
# inside; and macOS's BSD script does not pass the child's exit status back, so the
# command reports its own as `__RC=<n>` and tty_status reads it out of $output. The
# two flavours also spell "run this command" differently — util-linux needs -c,
# BSD takes it as trailing args.

# require_pty — skip a test that needs a real terminal when script(1) is absent.
require_pty() {
  command -v script >/dev/null 2>&1 || skip "script(1) not available"
}

# tty_run <bash-command-string> — run it with stdin on a pty; keystrokes come from
# this function's own stdin. Pair with `run`, then read the status via tty_status.
tty_run() {
  _tty_cmd="$1; printf '__RC=%s\\n' \"\$?\""
  if script --version >/dev/null 2>&1; then
    { cat; sleep 1; } | script -qec "$_tty_cmd" /dev/null 2>&1 | tr -d '\r'
  else
    { cat; sleep 1; } | script -q /dev/null bash -c "$_tty_cmd" 2>&1 | tr -d '\r'
  fi
}

# tty_status — the exit status tty_run's command reported, out of $output.
tty_status() {
  printf '%s\n' "$output" | sed -n 's/^__RC=\([0-9][0-9]*\)$/\1/p' | tail -1
}

# --- tiny assertions (avoid a bats-assert dependency) ---------------------------

# fake_logged <pattern> — grep -F the invocation log.
fake_logged() {
  grep -Fq -- "$1" "$BUMP_FAKE_LOG"
}

refute_fake_logged() {
  ! grep -Fq -- "$1" "$BUMP_FAKE_LOG"
}
