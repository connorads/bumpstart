# shellcheck shell=bash
# common.sh: colour helpers + PATH fixup, shared by the applier and blocks.
#
# Sourced, not executed. No side effects beyond defining vars/functions.
# bash-3.2-clean (macOS /bin/bash): no associative arrays, mapfile, or ${v,,}.

# Colours off when NO_COLOR is set or stdout is not a terminal.
# shellcheck disable=SC2034  # DIM/others are consumed by sourcing scripts
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  GREEN="" BLUE="" RED="" YELLOW="" DIM="" BOLD="" RESET=""
else
  GREEN=$'\033[32m' BLUE=$'\033[34m' RED=$'\033[31m'
  YELLOW=$'\033[33m' DIM=$'\033[2m' BOLD=$'\033[1m' RESET=$'\033[0m'
fi

info()    { printf "  %s>%s %s\n" "$BLUE" "$RESET" "$1"; }
success() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()    { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1" >&2; }
error()   { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1" >&2; }
step()    { printf "\n  %s[%s/%s]%s %s\n" "$BOLD" "$1" "$2" "$RESET" "$3"; }

# fixup_path: freshly-installed CLIs often land in these dirs — make the current
# shell see them without a re-login.
fixup_path() {
  export PATH="$HOME/.local/bin:$HOME/.codex/bin:$PATH"
}
