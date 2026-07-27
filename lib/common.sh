# shellcheck shell=bash
# common.sh: colour/UI helpers + PATH fixup, shared by the applier and blocks.
#
# Sourced, not executed. No side effects beyond defining vars/functions.
# bash-3.2-clean (macOS /bin/bash): no associative arrays, mapfile, or ${v,,}.

# Colours off when NO_COLOR is set or stdout is not a terminal. UI_FANCY gates
# the animated/cursor-dependent bits (spinner, cursor hide/show, decorative
# rules) on top of colour, so piped/CI/test output stays plain and
# deterministic. New colour vars are defined empty in the no-colour branch too,
# for set -u safety in sourcing scripts.
# shellcheck disable=SC2034  # several vars are consumed only by sourcing scripts
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  GREEN="" BLUE="" RED="" YELLOW="" DIM="" BOLD="" RESET=""
  CYAN="" MAGENTA=""
  UI_FANCY=""
else
  GREEN=$'\033[32m' BLUE=$'\033[34m' RED=$'\033[31m'
  YELLOW=$'\033[33m' DIM=$'\033[2m' BOLD=$'\033[1m' RESET=$'\033[0m'
  CYAN=$'\033[36m' MAGENTA=$'\033[35m'
  UI_FANCY=1
fi

# One glyph, a two-space gutter, consistent spacing. warn/error stay on stderr.
info()    { printf "  %s›%s %s\n" "$BLUE" "$RESET" "$1"; }
success() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()    { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1" >&2; }
error()   { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1" >&2; }

# Warning ledger. Every non-fatal step failure records the thing that failed, so
# the finish message can name it instead of printing a green "Setup complete." over
# a machine where an install warned 40 lines ago and scrolled away. Kept separate
# from warn() itself: not every warning is a failed step (a deliberate back-off is
# a warning too), and only failures should change the verdict.
VIBE_WARN_COUNT=0
VIBE_WARN_ITEMS=""

# record_warning <label>: count one failed step and remember its human label.
record_warning() {
  VIBE_WARN_COUNT=$((VIBE_WARN_COUNT + 1))
  VIBE_WARN_ITEMS="${VIBE_WARN_ITEMS}$1
"
}

# step <n> <total> <label>: a numbered progress header before each install
# block, so there's always a visible "here's where we are" marker. Bracket in
# bold cyan, e.g. "[2/6] Set up GitHub CLI".
step() { printf "\n  %s[%s/%s]%s %s\n" "$BOLD$CYAN" "$1" "$2" "$RESET" "$3"; }

# hrule: a dim decorative rule. Fancy-only — a no-op in plain/piped/test output,
# so nothing prints escape codes or rule glyphs where they'd be noise.
hrule() {
  [ -n "$UI_FANCY" ] || return 0
  printf "  %s────────────────────────────────────────%s\n" "$DIM" "$RESET"
}

# spin <label> <cmd...>: run a command while showing a calm "it's working"
# indicator, hiding the command's output unless it fails.
#
# Plain mode (no UI_FANCY: pipes, CI, tests) is a transparent passthrough — it
# runs the command with stdout/stderr intact, so PATH-shadow fakes still fire
# and output stays deterministic. Fancy mode animates a braille spinner with an
# elapsed-seconds counter while the command runs in the background with its
# output captured, then reveals the captured log only on failure. Returns the
# command's exit status either way. Never wrap an interactive command.
spin() {
  _sp_label="$1"; shift
  if [ -z "$UI_FANCY" ]; then
    "$@" && return 0 || return $?
  fi

  # Braille frames in an array — indexed with `% count` to avoid multibyte
  # ${var:i:1} byte-slicing under a C locale.
  _sp_frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  _sp_nframes=${#_sp_frames[@]}

  _sp_log="$(mktemp "${TMPDIR:-/tmp}/vibe-spin.XXXXXX" 2>/dev/null)" \
    || _sp_log="${TMPDIR:-/tmp}/vibe-spin.$$"

  "$@" >"$_sp_log" 2>&1 &
  _sp_pid=$!

  _sp_start=$SECONDS
  _sp_i=0
  printf '\033[?25l'  # hide cursor
  while kill -0 "$_sp_pid" 2>/dev/null; do
    printf '\r  %s%s%s %s %s(%ss)%s' \
      "$CYAN" "${_sp_frames[$((_sp_i % _sp_nframes))]}" "$RESET" \
      "$_sp_label" "$DIM" "$((SECONDS - _sp_start))" "$RESET"
    _sp_i=$((_sp_i + 1))
    sleep 0.1
  done
  wait "$_sp_pid" && _sp_status=0 || _sp_status=$?
  printf '\r\033[K\033[?25h'  # clear line, show cursor

  # Nothing is lost on failure: surface the captured output on stderr.
  [ "$_sp_status" -ne 0 ] && cat "$_sp_log" >&2
  rm -f "$_sp_log"
  return "$_sp_status"
}

# press_enter <prompt>: pause until the user presses Enter, so an on-screen
# message can be read before the next action takes over. A no-op without a
# keyboard ([ -t 0 ]), so headless/piped runs never block.
press_enter() {
  [ -t 0 ] || return 0
  printf "\n  %s⏎%s %s " "$CYAN" "$RESET" "$1"
  read -r _pe_reply
}

# vibe_fetch <url>: print a URL's body on stdout using whatever fetcher the
# machine has. curl first (macOS always has it, and it is what every vendor
# one-liner documents), else wget — Ubuntu Desktop 24.04 and 26.04 ship wget but
# NOT curl, so a curl-only install cell is a silent no-op there. Neither present
# is a real failure: return non-zero and say what is missing, so a cell warns
# rather than piping nothing into a shell.
#
# Exported with `export -f` by apply.sh before the block loop, so an INSTALL cell
# (run via `bash -c`) can call it — verified through a `bash -c` child on real
# /bin/bash 3.2.57.
vibe_fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$1"
  else
    printf 'vibe: need curl or wget to fetch %s\n' "$1" >&2
    return 1
  fi
}

# fixup_path: freshly-installed CLIs often land in these dirs — make the current
# shell see them without a re-login.
fixup_path() {
  export PATH="$HOME/.local/bin:$HOME/.codex/bin:$PATH"
}
