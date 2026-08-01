#!/usr/bin/env bash
set -uo pipefail
#
# drive.sh: run the real-install lanes, aggregate their TAP, run the cross-lane
# differentials, and return ONE exit class.
#
#   tests/real/drive.sh [--group linux|macos|all] [--keep] [--ref SHA]
#                       [--allow-dirty] [lane...]
#
# Serially, always. One macOS guest at 6 GB plus colima's own VM does not fit twice
# on 16 GB, and a lane that swaps is a lane that times out for a reason unrelated to
# bumpstart.
#
# The exit class is the worst thing that happened, ordered by how much it should
# bother a reader rather than numerically:
#   1  an assertion failed   — bumpstart is wrong. Never tolerable.
#   3  a harness bug         — fix the harness, then you learn nothing until you do.
#   2  infrastructure        — upstream moved. Reportable without going red.
#
# Deliberately not `set -e`: a lane failing is data, not a reason to stop.

REAL="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$REAL/.." && pwd -P)"
REPO="$(cd "$REPO/.." && pwd -P)"

# shellcheck source=tests/real/lib/class.sh
. "$REAL/lib/class.sh"
# shellcheck source=tests/real/lib/lanes.sh
. "$REAL/lib/lanes.sh"

GROUP=all
KEEP=""
REF=""
LANES=""
ALLOW_DIRTY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --group) GROUP="${2:-all}"; shift ;;
    --keep)  KEEP="--keep" ;;
    --ref)   REF="${2:-}"; shift ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -*)      printf 'drive.sh: unknown option %s\n' "$1" >&2; exit 3 ;;
    *)       LANES="$LANES $1" ;;
  esac
  shift
done

OUT="$REPO/.bumpstart-real"
mkdir -p "$OUT" || exit 3

# ── Which lanes ──────────────────────────────────────────────────────────────
#
# From the same lanes.tsv the runner and CI read, filtered by ADAPTER rather than by a
# hardcoded list — so a new lane row joins `mise run vm-test` with no code change.

# `all` is container + tart, deliberately NOT every row: the `runner` adapter installs
# into the real $HOME of whatever machine it is on, and `mise run vm-test` must never
# be able to select it by accident. CI asks for it by lane name.
if [ -z "$LANES" ]; then
  case "$GROUP" in
    linux) LANES="$(lane_names "$REAL/lanes.tsv" container)" ;;
    macos) LANES="$(lane_names "$REAL/lanes.tsv" tart)" ;;
    all)   LANES="$(lane_names "$REAL/lanes.tsv" container tart)" ;;
    *)     printf 'drive.sh: unknown group %s\n' "$GROUP" >&2; exit 3 ;;
  esac
  if [ -z "$LANES" ]; then
    printf 'drive.sh: no %s lanes in lanes.tsv - the run would cover nothing\n' "$GROUP" >&2
    exit 3
  fi
fi

# The paste entry point cannot see an unpushed tree, and it must fetch `bumpstart` itself
# from the commit under test rather than from main — so HEAD is the default ref, and a
# ref that is not on a remote is called out rather than silently testing main.
if [ -z "$REF" ]; then
  REF="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
fi
NEEDS_REF=0
for _l in $LANES; do
  if ! lane_row "$REAL/lanes.tsv" "$_l"; then
    printf 'drive.sh: %s\n' "$LANE_ERROR" >&2
    exit 3
  fi
  # The group filters exclude the runner adapter, and a NAMED lane bypassed them
  # entirely - mise appends CLI args, so `mise run vm-test-linux macos-drift` arrives
  # here as a positional lane and the group is never consulted. The adapter's own
  # refusal was the only thing left, and it is the one that installs into the real
  # $HOME of whatever machine it is on. CI asks for that lane by invoking
  # lanes/run.sh directly, so nothing legitimate needs this path.
  if [ "$LANE_ADAPTER" = runner ]; then
    printf 'drive.sh: lane %s uses the runner adapter, which installs into %s for real.\n' "$_l" "$HOME" >&2
    printf '          drive.sh never selects it, named or grouped. CI runs it by calling\n' >&2
    printf '          tests/real/lanes/run.sh directly, on a machine that is the throwaway.\n' >&2
    exit 3
  fi
  [ "$LANE_ENTRY" = paste ] && NEEDS_REF=1
done
if [ "$NEEDS_REF" = 1 ]; then
  if [ -z "$REF" ]; then
    printf 'drive.sh: a paste lane needs a ref and this is not a git checkout\n' >&2
    exit 3
  fi
  if ! git -C "$REPO" branch -r --contains "$REF" 2>/dev/null | grep -q .; then
    printf '\n  NOTE: %s is not on any remote yet, so the paste lane cannot fetch it.\n' "${REF:0:12}" >&2
    printf '        Push first, or run --group linux.\n' >&2
  fi
  # A pushed ref is not enough: the TREE has to match it too. macos-vanilla mounts
  # the working tree and macos-vanilla-paste fetches a tarball of HEAD, so any
  # uncommitted change to what the blocks assemble makes
  # instructions.canonical.sha256 differ - and the apply-vs-paste differential goes
  # class 1, "bumpstart is wrong", on the most expensive lane pair in the matrix after
  # forty minutes. Refused rather than warned, because that is a false RED, and the
  # remedy is one commit.
  if [ "$ALLOW_DIRTY" != 1 ] && [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
    printf '\ndrive.sh: the working tree is dirty, and a paste lane fetches %s from GitHub.\n' "${REF:0:12}" >&2
    printf '          apply.sh would see your uncommitted changes and the paste would not,\n' >&2
    printf '          so the entry-point differential would disagree about them and report\n' >&2
    printf '          a bumpstart failure that is not one. Commit and push, run --group linux,\n' >&2
    printf '          or pass --allow-dirty if you know why this run is worth it.\n' >&2
    exit 3
  fi
fi

# ── Run them ─────────────────────────────────────────────────────────────────

WORST=0
SUMMARY=""
RAN=""

# 1 beats 3 beats 2 beats 0 — severity order, not numeric order. lib/class.sh owns it.
bump_class() { WORST="$(class_worse "$WORST" "$1")"; }

for LANE in $LANES; do
  # shellcheck disable=SC2086  # KEEP is either empty or one flag
  bash "$REAL/lanes/run.sh" "$LANE" $KEEP --ref "$REF"
  _rc=$?
  bump_class "$_rc"
  # From the lane's own verdict, which counts EVERY run. Reading run1.tap alone made
  # a lane whose SECOND run failed print `class 1  33 ok  0 failed`.
  _v="$OUT/$LANE/lane.verdict"
  _ok=0
  _bad=0
  if [ -f "$_v" ]; then
    _ok="$(awk -F'\t' '$1 == "passed" { print $2; exit }' "$_v")"
    _bad="$(awk -F'\t' '$1 == "failed" { print $2; exit }' "$_v")"
    [ -n "$_ok" ] || _ok=0
    [ -n "$_bad" ] || _bad=0
  fi
  SUMMARY="$SUMMARY
  $(printf '%-22s class %s  %s ok  %s failed' "$LANE" "$_rc" "$_ok" "$_bad")"
  [ -f "$OUT/$LANE/run1.manifest" ] && RAN="$RAN $LANE"
done

# ── Cross-lane differentials ────────────────────────────────────────────────
#
# tests/real/differentials.sh owns them, and CI calls the same script over the
# manifests every lane uploaded — until it existed, this half of the oracle was
# executed by no CI job at all.

# shellcheck disable=SC2086  # the lane list is deliberately word-split
bash "$REAL/differentials.sh" "$OUT" $RAN
bump_class "$?"

# ── Report ──────────────────────────────────────────────────────────────────

printf '\n  === lanes ===%s\n' "$SUMMARY"

case "$WORST" in
  0) printf '\n  all lanes passed\n' ;;
  1) printf '\n  FAILED: an assertion failed — bumpstart is wrong. Log bundles under %s\n' "$OUT" >&2 ;;
  2) printf '\n  COULD NOT RUN: infrastructure (a guest, an image, or a vendor URL). Not a bumpstart failure.\n' >&2 ;;
  3) printf '\n  HARNESS BUG: the harness itself is broken, so the lanes proved nothing.\n' >&2 ;;
esac
exit "$WORST"
