#!/usr/bin/env bash
set -euo pipefail
#
# apply.sh: the applier. Resolve an id list to a Plan (pure core), print the
# plan, gate on a single confirm, then apply each block and launch the agent.
#
#   bash lib/apply.sh [--plan] [--yes] [--no-launch] <id>...
#
# VIBE_ROOT overrides the repo root (the dir containing blocks/ and presets/) —
# the seam the tests use to point at a fixture tree.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/meta.sh
. "$LIB/meta.sh"
# shellcheck source=lib/os.sh
. "$LIB/os.sh"
# shellcheck source=lib/run.sh
. "$LIB/run.sh"
# shellcheck source=lib/resolve.sh
. "$LIB/resolve.sh"
# shellcheck source=lib/instructions.sh
. "$LIB/instructions.sh"
# shellcheck source=lib/plan.sh
. "$LIB/plan.sh"
# shellcheck source=lib/catalogue.sh
. "$LIB/catalogue.sh"
# shellcheck source=lib/build.sh
. "$LIB/build.sh"
# shellcheck source=lib/brew.sh
. "$LIB/brew.sh"
# shellcheck source=lib/trust.sh
. "$LIB/trust.sh"

ROOT="${VIBE_ROOT:-$(cd "$LIB/.." && pwd -P)}"

die() { error "$1"; exit 1; }

# ── Parse flags + id list ─────────────────────────────────────────────────────

IDS=()
PLAN_ONLY=false
ASSUME_YES=false
LIST_ONLY=false
SHOW=false
SHOW_ID=""
BUILD=false
FORCE=false
# Bare paste (no ids) → the full beginner setup, not a bare agent or an error.
# One id per axis: which agent (an account choice) and which stack+habits. A
# reader picking a different agent swaps exactly one word.
DEFAULT_IDS=(claude starter)
# Desktop-ness is a composition choice too: the `claude`/`codex` bundles pull in
# their *-desktop app block; CLI-only = list `claude-cli`/`codex-cli` instead.
LAUNCH=true

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)       PLAN_ONLY=true ;;
    --yes|-y)     ASSUME_YES=true ;;
    --list)       LIST_ONLY=true ;;
    --show)       SHOW=true; SHOW_ID="${2:-}"; [ $# -gt 1 ] && shift ;;
    --build)      BUILD=true ;;
    --force)      FORCE=true ;;
    --no-launch)  LAUNCH=false ;;
    --) shift; while [ $# -gt 0 ]; do IDS+=("$1"); shift; done; break ;;
    -*) die "Unknown option: $1" ;;
    *)  IDS+=("$1") ;;
  esac
  shift
done

# ── Author-facing discovery + wizard (read-only; short-circuit before resolve) ─
#
# resolve errors on an empty/harness-less id list, so these must answer BEFORE it.
# --build with run-now=yes is the exception: it hands its ids to IDS and falls
# through into the normal resolve→confirm→apply→launch path below.

if [ "$LIST_ONLY" = true ]; then
  render_catalogue "$ROOT"
  exit 0
fi

if [ "$SHOW" = true ]; then
  render_block "$ROOT" "$SHOW_ID" && exit 0
  exit 1
fi

if [ "$BUILD" = true ]; then
  run_wizard "$ROOT" || exit $?
  if [ "$WIZARD_RUN_NOW" = true ]; then
    IDS=("${WIZARD_IDS[@]}")
  else
    exit 0
  fi
fi

# ── Platform guard: fail fast, honestly, before any macOS-specific effect ─────
#
# Everything below (Homebrew, the CLI installers, trust preseed) is
# macOS-only. An honest redirect beats running partway then dying on a
# Mac-specific step. Exit 0 (informational, not an error) — a script wrapping
# this could branch on the message; a non-zero would read as a failure it isn't.
if [ "$(uname -s)" != "Darwin" ]; then
  info "vibe-setup is macOS-only for now."
  exit 0
fi

# No ids → the beginner default (claude starter). Kept out of resolve.sh so the
# pure core stays free of a hardcoded preset; resolve's own empty-list error
# remains the last-line guard for any caller that bypasses this.
[ ${#IDS[@]} -eq 0 ] && IDS=("${DEFAULT_IDS[@]}")

# ── Resolve (pure core): all domain errors surface here, before any effect ────

if ! resolve "$ROOT" ${IDS[@]+"${IDS[@]}"}; then
  die "$PLAN_ERROR"
fi

# ── --plan dry-run: print the Plan and stop before any effect ─────────────────

if [ "$PLAN_ONLY" = true ]; then
  render_plan full
  exit 0
fi

# ── Confirm gate ──────────────────────────────────────────────────────────────

render_plan
if [ "$ASSUME_YES" != true ]; then
  confirm_plan || die "Aborted."
fi

# ── Apply ─────────────────────────────────────────────────────────────────────

# A modest branded header as the real work begins (colour-gated via common.sh).
printf "\n  %s✦ vibe-setup%s\n" "$BOLD$CYAN" "$RESET"
printf "  %slet's get you building%s\n" "$DIM" "$RESET"

# Homebrew underpins the auth + desktop/cask installs; get it in place first.
# An un-numbered section marker (non-numeric [·]) so the earliest visible effect
# — installing Homebrew, which prompts for the Mac password — isn't a silent
# surprise. ensure_brew narrates the install (or "already installed") itself.
printf "\n  %s[·]%s %sPreparing your Mac%s\n" "$BOLD$CYAN" "$RESET" "$BOLD" "$RESET"
ensure_brew

# run_block <id> — execute a block's apply.sh (its interactive tail) in a fresh
# bash with the block contract in the environment. A missing apply.sh is a silent
# skip: pure-data blocks install declaratively (via run_cell) and instruction
# blocks (concise, ask-first) ship only meta + content.md, which the applier
# assembles centrally. Best-effort otherwise: a failure warns and continues so
# one fast-moving vendor step can't sink the whole setup.
run_block() {
  _b_dir="$(block_dir "$ROOT" "$1")"
  [ -f "$_b_dir/apply.sh" ] || return 0
  VIBE_LIB="$LIB" VIBE_ROOT="$ROOT" VIBE_BLOCK_DIR="$_b_dir" VIBE_BLOCK_ID="$1" \
    bash "$_b_dir/apply.sh" || warn "block '$1' failed — continuing"
}

_n=${#PLAN_STEP_IDS[@]}

# Count only the blocks that actually do something (a declarative INSTALL cell
# or an apply.sh tail); instruction-only blocks are silent skips, so they neither
# get a step header nor inflate the total. (The whole loop is skipped under
# --plan, so the resolve.bats DESC counts are unaffected.)
_total=0
_i=0
while [ "$_i" -lt "$_n" ]; do
  if _block_runs "$ROOT" "${PLAN_STEP_IDS[$_i]}"; then _total=$((_total + 1)); fi
  _i=$((_i + 1))
done

# Per step: run the declarative install cell (run_cell), then the interactive
# tail (run_block). This reproduces today's order — gh installed then login;
# git ensured then identity — because an escape-hatch block's cell runs before
# its apply.sh.
_cur=0
_i=0
while [ "$_i" -lt "$_n" ]; do
  _bid="${PLAN_STEP_IDS[$_i]}"
  if _block_runs "$ROOT" "$_bid"; then
    _cur=$((_cur + 1))
    step "$_cur" "$_total" "${PLAN_STEP_DESCS[$_i]}"
  fi
  run_cell "$ROOT" "$_bid"
  run_block "$_bid"
  _i=$((_i + 1))
done

echo ""
hrule
success "Setup complete."
printf "  %sYou're all set — the hard part is done.%s\n" "$GREEN" "$RESET"

# ── Instructions: assemble the canonical file, symlink each harness to it ─────
#
# One editable source of truth at canonical_path; each installed harness's own
# path becomes a symlink to it, so today's agents (which read their native path)
# follow the link. Back off from anything the user already owns.
LINK_BACKOFFS=""
assemble_instructions "$ROOT" "$FORCE"
if [ ${#PLAN_TARGETS[@]} -gt 0 ]; then
  for _t in "${PLAN_TARGETS[@]}"; do
    link_harness "$_t" "$FORCE"
  done
fi

CANON="$(canonical_path)"
if [ "$INSTRUCTIONS_WROTE" = true ]; then
  echo ""
  info "Your agent instructions live in one file:"
  printf "    %s\n" "$CANON"
  info "Both Claude and Codex read it (linked from their own config)."
elif [ "$INSTRUCTIONS_BACKED_OFF" = true ]; then
  echo ""
  info "You already have an instructions file here — left as-is:"
  printf "    %s\n" "$CANON"
  info "Re-run with --force to replace it."
fi

if [ -n "$LINK_BACKOFFS" ]; then
  echo ""
  warn "These agent config files already exist and were left untouched:"
  printf '%s' "$LINK_BACKOFFS" | while IFS= read -r _bk; do
    [ -n "$_bk" ] || continue
    printf "    %s\n" "$_bk"
  done
  warn "Point them at $CANON yourself, or re-run with --force to back them up and link."
fi

if [ "$INSTRUCTIONS_WROTE" = true ] || [ "$INSTRUCTIONS_BACKED_OFF" = true ]; then
  echo ""
  info "💡 Edit that file in plain language to steer every future session."
fi

# ── Starter project + trust preseed ───────────────────────────────────────────

# A dedicated dir we create and pre-trust (never blanket-trust $HOME), so the
# only prompt left is the browser login.
STARTER="$(ensure_starter_dir)"
preseed_trust "$PLAN_DEFAULT_HARNESS" "$STARTER"

# Make it a real git repo the agent can commit into — but only when the git
# block is in the plan, so git is installed and an identity is set and the first
# commit is authored, not rejected for a missing name/email.
case " ${PLAN_STEP_IDS[*]} " in
  *" git "*) init_starter_repo "$STARTER" ;;
esac

# ── Launch ────────────────────────────────────────────────────────────────────

# Freshly-installed CLIs may not be on PATH yet.
fixup_path

# Last write to the clipboard before we exec the agent — covers both the launch
# and --no-launch paths, and survives the browser sign-in in between.
copy_starter_prompt "$ROOT"

if [ "$LAUNCH" = true ] && command -v "$PLAN_DEFAULT_HARNESS" >/dev/null 2>&1; then
  frame_login "$PLAN_DEFAULT_HARNESS"
  # Keypress gate so the sign-in instruction stays on screen and they proceed on
  # their own timing (no-op without a keyboard, so headless launch is unaffected).
  press_enter "Press Enter to open $PLAN_DEFAULT_HARNESS and sign in"
  cd "$STARTER"
  exec "$PLAN_DEFAULT_HARNESS"
else
  echo ""
  info "Run '$PLAN_DEFAULT_HARNESS' in $STARTER to start (you'll sign in on first launch)."
  if [ "${STARTER_PROMPT_COPIED:-false}" = true ]; then
    info "A starter message is on your clipboard — press Cmd+V at the agent's prompt, then Enter."
  fi
fi
