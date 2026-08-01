#!/usr/bin/env bash
set -uo pipefail
#
# verdicts.sh: did the suite prove anything?
#
#   tests/real/verdicts.sh <dir> <lane>...
#
# Every lane writes a `lane.verdict`; this reads all of them under <dir>, at any
# depth, and answers the one question no single lane can: did ANY assertion run.
#
# Three independent routes led to a permanently green, permanently useless suite,
# and each is invisible from inside a lane:
#
#   - a renamed adapter token makes the matrix `awk` print nothing, `jq -sc .`
#     yields `[]`, and eight lanes' worth of coverage vanishes into a green tick
#   - class 2 is a ::warning BY DESIGN, so a stopped docker daemon, a registry rate
#     limit or a guest that will not boot turns EVERY leg green with an annotation
#     nobody reads on a weekly schedule
#   - a lane that dies before the judge reports class 2 and asserts nothing
#
# judge.sh already refuses to pass a lane that planned no checks. This is the same
# rule one level up, and the reason it has to live here rather than in a lane: a
# lane cannot see that it was the only one, or that it was one of eight identical
# infrastructure failures.
#
# It also REPORTS how long each lane took, and names an outlier. Same argument, one
# axis over: a lane cannot see that it took forty times as long as its siblings, and
# `ubuntu-no-curl` taking 22 minutes against roughly 30 seconds for the same image with
# curl is either the wget path or one slow runner. Reported, never asserted - a timing
# assertion in CI is a flake generator, and this is a pointer to a transcript.
#
# Exit: 0 the suite reached a judgement · 3 it did not, or a declared lane vanished.
# Never 1: nothing here is a claim about bumpstart, only about the harness.
#
# bash-3.2-clean. Deliberately not `set -e`: every missing lane is reported, not just
# the first.

HERE="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/real/lib/class.sh
. "$HERE/lib/class.sh"

DIR="${1:-}"
[ $# -ge 1 ] && shift
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  printf 'verdicts: no such directory: %s\n' "${DIR:-<none>}" >&2
  printf 'usage: verdicts.sh <dir> <lane>...\n' >&2
  exit "$CLASS_HARNESS"
fi
if [ $# -eq 0 ]; then
  printf 'verdicts: no lanes were declared — there is nothing to check against\n' >&2
  printf 'usage: verdicts.sh <dir> <lane>...\n' >&2
  exit "$CLASS_HARNESS"
fi

EXPECTED="$*"

# vget <file> <key> — one value out of a lane.verdict.
vget() { awk -F'\t' -v k="$2" '$1 == k { print $2; exit }' "$1"; }

TOTAL_ASSERTIONS=0
TOTAL_FAILED=0
JUDGED_LANES=0
MISSING=""
SUMMARY=""
# "<lane> <seconds>" per line: the slowest single apply each lane reported. The
# comparison is between lanes, so it cannot be made inside one.
SLOWEST=""

# slowest_apply <space-separated seconds> — the largest, 0 for nothing usable. A lane
# written by an older runner carries no durations at all, and that is not an error.
slowest_apply() {
  _sa_max=0
  for _sa in $1; do
    case "$_sa" in ''|*[!0-9]*) continue ;; esac
    [ "$_sa" -gt "$_sa_max" ] && _sa_max="$_sa"
  done
  printf '%s' "$_sa_max"
}

# Every lane.verdict under <dir>, at any depth, matched on the `lane` key INSIDE it
# rather than on its path: an artifact download lays each one out under its own
# folder, and that layout is the downloader's business, not this file's contract.
VERDICT_FILES="$(find "$DIR" -name lane.verdict -type f 2>/dev/null)"

printf '\n  === lane verdicts ===\n'
# shellcheck disable=SC2086  # the declared lane list is deliberately word-split
for _lane in $EXPECTED; do
  _v=""
  _oifs="$IFS"
  IFS='
'
  # shellcheck disable=SC2086  # deliberate split of the newline-separated file list
  set -- $VERDICT_FILES
  IFS="$_oifs"
  for _cand in "$@"; do
    [ "$(vget "$_cand" lane)" = "$_lane" ] || continue
    _v="$_cand"
    break
  done
  if [ -z "$_v" ]; then
    MISSING="$MISSING $_lane"
    SUMMARY="$SUMMARY
  $(printf '%-22s NO VERDICT — the lane never reported' "$_lane")"
    continue
  fi

  _class="$(vget "$_v" class)"
  _asserts="$(vget "$_v" assertions)"
  _failed="$(vget "$_v" failed)"
  [ -n "$_asserts" ] || _asserts=0
  [ -n "$_failed" ] || _failed=0
  TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + _asserts))
  TOTAL_FAILED=$((TOTAL_FAILED + _failed))
  [ "$_asserts" -gt 0 ] && JUDGED_LANES=$((JUDGED_LANES + 1))

  _lane_s="$(vget "$_v" duration_lane_s)"
  _apply_s="$(vget "$_v" duration_apply_s)"
  _slow="$(slowest_apply "$_apply_s")"
  [ "$_slow" = 0 ] || SLOWEST="$SLOWEST
$_lane $_slow"
  SUMMARY="$SUMMARY
  $(printf '%-22s class %-2s %4s assertions  %s failed  %5ss lane  apply %s' \
      "$_lane" "${_class:-?}" "$_asserts" "$_failed" "${_lane_s:-?}" "${_apply_s:-?}")"
done
printf '%s\n' "$SUMMARY"

# shellcheck disable=SC2086  # the declared lane list is deliberately word-split
EXPECTED_N="$(printf '%s\n' $EXPECTED | grep -c '')"
printf '\n  %s of %s lanes reached a judgement · %s assertions · %s failed\n' \
  "$JUDGED_LANES" "$EXPECTED_N" "$TOTAL_ASSERTIONS" "$TOTAL_FAILED"

# ── The slow lane, named ─────────────────────────────────────────────────────
#
# Against the MEDIAN of the other lanes rather than a fixed budget: what "normal" costs
# depends on the runner and on how many vendor URLs are cold, and a fixed number would
# either be noise or would go stale silently. Two conditions, because a proportional
# rule alone fires on a fast matrix where one lane took 3 seconds and another 1.
if [ -n "$SLOWEST" ]; then
  MEDIAN="$(printf '%s\n' "$SLOWEST" | awk 'NF == 2 { print $2 }' | sort -n \
    | awk '{ v[NR] = $1 } END { if (NR) { print v[int((NR + 1) / 2)] } }')"
  if [ -n "$MEDIAN" ] && [ "$MEDIAN" -gt 0 ]; then
    printf '%s\n' "$SLOWEST" | awk -v m="$MEDIAN" '
      NF == 2 && $2 >= 120 && $2 > 3 * m {
        printf "\n  SLOW: %s spent %ss in one apply, against a %ss median.\n", $1, $2, m
        printf "        Read its transcript before treating that as normal.\n"
      }'
  fi
fi

RC=0
if [ -n "$MISSING" ]; then
  printf '\n  HARNESS: lanes declared in lanes.tsv that never reported:%s\n' "$MISSING" >&2
  printf '           A lane that vanishes from the matrix is coverage lost silently.\n' >&2
  RC="$CLASS_HARNESS"
fi
if [ "$JUDGED_LANES" -eq 0 ]; then
  printf '\n  HARNESS: NOT ONE lane reached a judgement, so nothing was proved.\n' >&2
  printf '           Every leg failing the same way reads as green when class 2 is a\n' >&2
  printf '           warning; it is the one shape a per-lane exit status cannot show.\n' >&2
  RC="$CLASS_HARNESS"
fi
exit "$RC"
