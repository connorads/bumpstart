#!/usr/bin/env bash
set -euo pipefail
#
# apply.sh: the applier. Resolve an id list to a Plan (pure core), print the
# plan, gate on a single confirm, then apply each block and launch the agent.
#
#   bash lib/apply.sh [--plan] [--yes] [--no-launch] [--no-desktop] <id>...
#
# VIBE_ROOT overrides the repo root (the dir containing blocks/ and presets/) —
# the seam the tests use to point at a fixture tree.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/meta.sh
. "$LIB/meta.sh"
# shellcheck source=lib/resolve.sh
. "$LIB/resolve.sh"
# shellcheck source=lib/plan.sh
. "$LIB/plan.sh"
# shellcheck source=lib/brew.sh
. "$LIB/brew.sh"

ROOT="${VIBE_ROOT:-$(cd "$LIB/.." && pwd -P)}"

die() { error "$1"; exit 1; }

# ── Parse flags + id list ─────────────────────────────────────────────────────

IDS=()
PLAN_ONLY=false
ASSUME_YES=false
# LAUNCH / DESKTOP are consumed by the apply loop + launch (wired in later steps).
LAUNCH=true
DESKTOP=true

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)       PLAN_ONLY=true ;;
    --yes|-y)     ASSUME_YES=true ;;
    --no-launch)  LAUNCH=false ;;
    --no-desktop) DESKTOP=false ;;
    --) shift; while [ $# -gt 0 ]; do IDS+=("$1"); shift; done; break ;;
    -*) die "Unknown option: $1" ;;
    *)  IDS+=("$1") ;;
  esac
  shift
done

# ── Resolve (pure core): all domain errors surface here, before any effect ────

if ! resolve "$ROOT" ${IDS[@]+"${IDS[@]}"}; then
  die "$PLAN_ERROR"
fi

# ── --plan dry-run: print the Plan and stop before any effect ─────────────────

if [ "$PLAN_ONLY" = true ]; then
  render_plan
  exit 0
fi

# ── Confirm gate ──────────────────────────────────────────────────────────────

render_plan
if [ "$ASSUME_YES" != true ]; then
  confirm_plan || die "Aborted."
fi

# ── Apply ─────────────────────────────────────────────────────────────────────

# Homebrew underpins the auth + desktop/cask installs; get it in place first.
ensure_brew

# run_block <id> — execute a block's apply.sh in a fresh bash with the block
# contract in the environment. Best-effort: a failure warns and continues so one
# fast-moving vendor step can't sink the whole setup.
run_block() {
  _b_dir="$(block_dir "$ROOT" "$1")"
  if [ ! -f "$_b_dir/apply.sh" ]; then
    warn "block '$1' has no apply.sh — skipping"
    return 0
  fi
  VIBE_LIB="$LIB" VIBE_ROOT="$ROOT" VIBE_BLOCK_DIR="$_b_dir" VIBE_DESKTOP="$DESKTOP" \
    bash "$_b_dir/apply.sh" || warn "block '$1' failed — continuing"
}

_n=${#PLAN_STEP_IDS[@]}
_i=0
while [ "$_i" -lt "$_n" ]; do
  run_block "${PLAN_STEP_IDS[$_i]}"
  _i=$((_i + 1))
done

echo ""
success "Setup complete."

# ── Launch ────────────────────────────────────────────────────────────────────

# Freshly-installed CLIs may not be on PATH yet.
fixup_path

if [ "$LAUNCH" = true ] && command -v "$PLAN_DEFAULT_HARNESS" >/dev/null 2>&1; then
  echo ""
  info "Starting $PLAN_DEFAULT_HARNESS — sign in when prompted..."
  echo ""
  exec "$PLAN_DEFAULT_HARNESS"
else
  echo ""
  info "Run '$PLAN_DEFAULT_HARNESS' to start (you'll sign in on first launch)."
fi
