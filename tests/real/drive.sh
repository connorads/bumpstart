#!/usr/bin/env bash
set -uo pipefail
#
# drive.sh: run the real-install lanes, aggregate their TAP, run the cross-lane
# differentials, and return ONE exit class.
#
#   tests/real/drive.sh [--group linux|macos|all] [--keep] [--ref SHA] [lane...]
#
# Serially, always. One macOS guest at 6 GB plus colima's own VM does not fit twice
# on 16 GB, and a lane that swaps is a lane that times out for a reason unrelated to
# vibe.
#
# The exit class is the worst thing that happened, ordered by how much it should
# bother a reader rather than numerically:
#   1  an assertion failed   — vibe is wrong. Never tolerable.
#   3  a harness bug         — fix the harness, then you learn nothing until you do.
#   2  infrastructure        — upstream moved. Reportable without going red.
#
# Deliberately not `set -e`: a lane failing is data, not a reason to stop.

REAL="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$REAL/.." && pwd -P)"
REPO="$(cd "$REPO/.." && pwd -P)"

# shellcheck source=tests/real/lib/manifest.sh
. "$REAL/lib/manifest.sh"

GROUP=all
KEEP=""
REF=""
LANES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --group) GROUP="${2:-all}"; shift ;;
    --keep)  KEEP="--keep" ;;
    --ref)   REF="${2:-}"; shift ;;
    -*)      printf 'drive.sh: unknown option %s\n' "$1" >&2; exit 3 ;;
    *)       LANES="$LANES $1" ;;
  esac
  shift
done

OUT="$REPO/.vibe-real"
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
    linux) LANES="$(awk -F'\t' 'NR > 1 && $2 == "container" { print $1 }' "$REAL/lanes.tsv")" ;;
    macos) LANES="$(awk -F'\t' 'NR > 1 && $2 == "tart" { print $1 }' "$REAL/lanes.tsv")" ;;
    all)   LANES="$(awk -F'\t' 'NR > 1 && ($2 == "container" || $2 == "tart") { print $1 }' "$REAL/lanes.tsv")" ;;
    *)     printf 'drive.sh: unknown group %s\n' "$GROUP" >&2; exit 3 ;;
  esac
fi

# The paste entry point cannot see an unpushed tree, and it must fetch `vibe` itself
# from the commit under test rather than from main — so HEAD is the default ref, and a
# ref that is not on a remote is called out rather than silently testing main.
if [ -z "$REF" ]; then
  REF="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
fi
NEEDS_REF=0
for _l in $LANES; do
  if [ "$(awk -F'\t' -v l="$_l" '$1 == l { print $5 }' "$REAL/lanes.tsv")" = paste ]; then
    NEEDS_REF=1
  fi
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
fi

# ── Run them ─────────────────────────────────────────────────────────────────

WORST=0
SUMMARY=""
RAN=""

bump_class() {
  # 1 beats 3 beats 2 beats 0 — severity order, not numeric order.
  case "$1:$WORST" in
    1:*)   WORST=1 ;;
    3:1)   : ;;
    3:*)   WORST=3 ;;
    2:1|2:3) : ;;
    2:*)   WORST=2 ;;
  esac
}

for LANE in $LANES; do
  # shellcheck disable=SC2086  # KEEP is either empty or one flag
  bash "$REAL/lanes/run.sh" "$LANE" $KEEP --ref "$REF"
  _rc=$?
  bump_class "$_rc"
  _tap="$OUT/$LANE/run1.tap"
  _ok=0
  _bad=0
  if [ -f "$_tap" ]; then
    _ok="$(grep -c '^ok ' "$_tap" 2>/dev/null)"
    # `not ok … # TODO` is an ACCEPTED gap, not a failure — counting it as one would
    # make every lane look permanently broken.
    _bad="$(grep '^not ok ' "$_tap" 2>/dev/null | grep -vc '# TODO')"
  fi
  SUMMARY="$SUMMARY
  $(printf '%-22s class %s  %s ok  %s failed' "$LANE" "$_rc" "$_ok" "$_bad")"
  [ -f "$OUT/$LANE/run1.manifest" ] && RAN="$RAN $LANE"
done

# ── Cross-lane differentials ────────────────────────────────────────────────

printf '\n  === differentials ===\n'

# 1. The design claim that must hold on every POSIX lane whatever the distro and
#    whatever the paste: one PATH line, written once, identical everywhere, and one
#    canonical instructions path.
_base=""
for LANE in $RAN; do
  _m="$OUT/$LANE/run1.manifest"
  [ "$(awk -F'\t' '$1 == "os" { print $2 }' "$_m")" = win ] && continue
  if [ -z "$_base" ]; then
    _base="$LANE"
    continue
  fi
  if manifest_diff "$_base" "$OUT/$_base/run1.manifest" "$LANE" "$_m" manifest_invariant_subset; then
    printf '  %s vs %s: the OS-invariant subset agrees\n' "$_base" "$LANE"
  else
    bump_class 1
  fi
done
[ -n "$_base" ] || printf '  (no manifests to compare)\n'

# 2. The entry-point differential: lib/apply.sh from a clone and the real paste must
#    leave the same machine. Same lane, same expected manifest — which is why the
#    macOS rows exist twice.
if [ -f "$OUT/macos-vanilla/run1.manifest" ] && [ -f "$OUT/macos-vanilla-paste/run1.manifest" ]; then
  if manifest_diff "apply.sh" "$OUT/macos-vanilla/run1.manifest" \
                   "the paste" "$OUT/macos-vanilla-paste/run1.manifest" manifest_state_subset; then
    printf '  apply.sh vs the real paste: identical state\n'
  else
    bump_class 1
  fi
fi

# ── Report ──────────────────────────────────────────────────────────────────

printf '\n  === lanes ===%s\n' "$SUMMARY"

case "$WORST" in
  0) printf '\n  all lanes passed\n' ;;
  1) printf '\n  FAILED: an assertion failed — vibe is wrong. Log bundles under %s\n' "$OUT" >&2 ;;
  2) printf '\n  COULD NOT RUN: infrastructure (a guest, an image, or a vendor URL). Not a vibe failure.\n' >&2 ;;
  3) printf '\n  HARNESS BUG: the harness itself is broken, so the lanes proved nothing.\n' >&2 ;;
esac
exit "$WORST"
