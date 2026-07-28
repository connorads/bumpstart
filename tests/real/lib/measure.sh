# shellcheck shell=bash
# measure.sh: the measurements taken BOTH before a run and after it.
#
# The judge asserts a DELTA, not an end state. "git resolves in a fresh shell" is
# true on a machine that shipped git, so asserting it there is a claim about the
# image rather than about vibe — and `env -i "$SHELL" -lc` is NOT an empty PATH:
# bash and zsh substitute a compiled-in default containing /usr/bin when PATH is
# unset, and -l sources /etc/profile on top. That is why `shell.lc.git` reads 1
# beside `shell.lc.gh 0` on a Debian lane whether or not persist_path ever ran.
#
# The only way to say "vibe did this" is to have measured the same thing before the
# run, which means precheck.sh and probe.sh have to measure it the SAME way. Hence
# one file: a delta between two subtly different questions is not a delta.
#
# Sourced by tests/real/precheck.sh and tests/real/probe.sh, inside the guest.
# bash-3.2-clean: no associative arrays, no mapfile.

# The tools every measurement iterates. ONE list, because a tool the probe measures
# and the precheck does not has no baseline, and the judge fails closed on it.
MEASURE_TOOLS="claude codex gh git node pnpm mise"

# Three fresh-shell invocations, because they source three different files and one
# assertion cannot see all three:
#   lic  login + interactive  → ~/.profile, which sources ~/.bashrc
#   ic   interactive          → ~/.bashrc
#   lc   login only           → ~/.profile, and Debian/Ubuntu's ~/.bashrc returns
#                               early for a non-interactive shell, so vibe's line is
#                               invisible here. Reported, not fixed.
MEASURE_SHELL_MODES="lic ic lc"

# persist_path keys on the LOGIN shell, so everything here does too.
MEASURE_LOGIN_SHELL="${SHELL:-/bin/sh}"
MEASURE_SHELL_KIND="$(basename "$MEASURE_LOGIN_SHELL")"
MEASURE_USER="$(id -un)"

# measure_fresh <mode> <tool> — 1 when a shell started that way resolves <tool>.
#
# `env -i` so the guest's own startup files are the only source of PATH: inheriting
# ours would make the measurement vacuous, since fixup_path put vibe's dirs on PATH
# for the run.
measure_fresh() {
  case "$MEASURE_SHELL_KIND" in bash|zsh) : ;; *) printf '0'; return 0 ;; esac
  case "$1" in
    lic) _mf_flags=-lic ;;
    ic)  _mf_flags=-ic ;;
    lc)  _mf_flags=-lc ;;
    *)   printf '0'; return 0 ;;
  esac
  if env -i HOME="$HOME" USER="$MEASURE_USER" SHELL="$MEASURE_LOGIN_SHELL" TERM=dumb \
      "$MEASURE_LOGIN_SHELL" "$_mf_flags" "command -v $2 >/dev/null 2>&1" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

# measure_rc_file — the rc file persist_path would write, found the same way it
# writes it. Empty for a shell vibe does not persist into.
measure_rc_file() {
  case "$MEASURE_SHELL_KIND" in
    zsh)  printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash) printf '%s' "$HOME/.bashrc" ;;
    fish) printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
    *)    : ;;
  esac
}
