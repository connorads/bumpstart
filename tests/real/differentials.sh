#!/usr/bin/env bash
set -uo pipefail
#
# differentials.sh: the cross-lane half of the oracle.
#
#   tests/real/differentials.sh <dir> [lane...]
#
# The judge asserts only what a PATH-shadow fake structurally cannot reach.
# Everything else is proved by making runs that OUGHT to agree produce an identical
# normalised state — no second copy of the expectations, so a new block is covered
# automatically.
#
# ONE owner, because until now this was executed by no CI job at all: CI invokes
# lanes/run.sh per lane in separate matrix jobs on separate runners, so "the half of
# the oracle that needs no hand-written expectations" was local-only, run by hand,
# on one machine. drive.sh calls this after its lanes; a CI job calls it over the
# manifests every lane uploaded.
#
# The layout is <dir>/<lane>/run1.manifest, which is what run.sh writes and what the
# CI job reconstructs from its artifacts. A lane with no manifest did not run — that
# is data, not a failure here; verdicts.sh is what refuses a suite where nothing did.
#
# Exit: 0 they agree · 1 a differential disagrees (vibe is wrong) · 3 there was
# nothing to compare at all, which is not the same thing as agreement.
#
# bash-3.2-clean. Deliberately not `set -e`: every differential is taken, not just
# the ones before the first failure.

HERE="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/real/lib/manifest.sh
. "$HERE/lib/manifest.sh"
# shellcheck source=tests/real/lib/class.sh
. "$HERE/lib/class.sh"
# shellcheck source=tests/real/lib/lanes.sh
. "$HERE/lib/lanes.sh"

DIR="${1:-}"
[ $# -ge 1 ] && shift
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  printf 'differentials: no such directory: %s\n' "${DIR:-<none>}" >&2
  printf 'usage: differentials.sh <dir> [lane...]\n' >&2
  exit "$CLASS_HARNESS"
fi

LANES_TSV="$HERE/lanes.tsv"
CANDIDATES="$*"
if [ -z "$CANDIDATES" ]; then
  CANDIDATES="$(lane_names "$LANES_TSV" container tart runner)"
fi

# Only the lanes that really produced a manifest, so `--group linux` cannot diff
# last week's macOS run against today's.
RAN=""
for _l in $CANDIDATES; do
  [ -f "$DIR/$_l/run1.manifest" ] && RAN="$RAN $_l"
done

WORST=0
bump() { WORST="$(class_worse "$WORST" "$1")"; }

printf '\n  === differentials ===\n'

if [ -z "$RAN" ]; then
  printf '  no lane produced a manifest, so nothing was compared\n' >&2
  exit "$CLASS_HARNESS"
fi

# 1. The design claim that must hold on every POSIX lane whatever the distro and
#    whatever the paste: one PATH line, written once, identical everywhere, and one
#    canonical instructions path. Windows carries none of those keys (the PowerShell
#    spine persists no PATH), and manifest_invariant_subset refuses it by name.
BASE=""
COMPARED=0
for _l in $RAN; do
  _m="$DIR/$_l/run1.manifest"
  [ "$(awk -F'\t' '$1 == "os" { print $2; exit }' "$_m")" = win ] && continue
  if [ -z "$BASE" ]; then
    BASE="$_l"
    continue
  fi
  COMPARED=$((COMPARED + 1))
  if manifest_diff "$BASE" "$DIR/$BASE/run1.manifest" "$_l" "$_m" manifest_invariant_subset; then
    printf '  %s vs %s: the OS-invariant subset agrees\n' "$BASE" "$_l"
  else
    bump "$CLASS_ASSERT"
  fi
done
if [ "$COMPARED" -eq 0 ]; then
  printf '  only one POSIX lane produced a manifest, so there is nothing to compare across lanes\n'
fi

# 2. The entry-point differential: lib/apply.sh from a clone and the real paste must
#    leave the same machine.
#
#    The pairing is DERIVED from lanes.tsv — a paste lane pairs with the apply lane
#    on the same image and the same ids — rather than being a hardcoded lane name.
#    That is what lets a new paste row join both the local driver and CI with no code
#    change, which is the whole reason the matrix is data.
ran_lane() { case " $RAN " in *" $1 "*) return 0 ;; esac; return 1; }

PAIRED=0
for _paste in $(lane_names "$LANES_TSV" container tart runner); do
  lane_row "$LANES_TSV" "$_paste" || continue
  [ "$LANE_ENTRY" = paste ] || continue
  ran_lane "$_paste" || continue
  _want_image="$LANE_IMAGE"
  _want_ids="$LANE_PASTE"
  for _apply in $RAN; do
    lane_row "$LANES_TSV" "$_apply" || continue
    [ "$LANE_ENTRY" = apply ] || continue
    [ "$LANE_IMAGE" = "$_want_image" ] || continue
    [ "$LANE_PASTE" = "$_want_ids" ] || continue
    PAIRED=$((PAIRED + 1))
    # manifest_entry_subset, not manifest_state_subset: these are two different
    # GUESTS, and Claude Code's installer seeds ~/.claude.json with a machineID and
    # a userID before vibe ever looks at it. Comparing that hash across machines is
    # a class-1 report of a vendor's randomness. Idempotence still compares it, on
    # the one guest where it is stable.
    if manifest_diff "$_apply (apply.sh)" "$DIR/$_apply/run1.manifest" \
                     "$_paste (the paste)" "$DIR/$_paste/run1.manifest" manifest_entry_subset; then
      printf '  %s vs %s: apply.sh and the real paste left identical state\n' "$_apply" "$_paste"
    else
      bump "$CLASS_ASSERT"
    fi
    break
  done
done
if [ "$PAIRED" -eq 0 ]; then
  printf '  no apply/paste pair ran, so the entry-point differential was not taken\n'
fi

exit "$WORST"
