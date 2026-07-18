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

# ── Apply + launch: wired in the following build steps. ───────────────────────
warn "apply loop not yet wired — run with --plan to preview."
