# shellcheck shell=bash
# tap.sh: the TAP-13 emitters the judge reports through. Sourced, not executed.
#
# TAP rather than bats, because the judge's output is aggregated across guests and
# lanes by the host driver, and TAP is the one format a plain shell script can
# emit without installing a test framework into a machine that is the subject of
# the test.
#
# A failure is `not ok`; a KNOWN, accepted gap is `not ok … # TODO <reason>`, which
# a TAP consumer counts separately — so a documented gap stays visible without
# turning the lane red, and the day it starts passing the TODO reads as stale.
#
# bash-3.2-clean (this runs under macOS /bin/bash). No `set -e` reliance: every
# caller decides pass/fail with an explicit if/else, because a non-final `[[ ]]`
# failure does not trip errexit under 3.2 and an errexit-dependent assertion would
# silently pass.

TAP_N=0        # assertions emitted so far (the TAP number)
TAP_FAIL=0     # real failures — the only thing that decides the exit status
TAP_TODO=0     # accepted known gaps

# tap_plan <n> — the plan line. Emitted FIRST, never last: a judge that decided
# three of twelve assertions must not be indistinguishable from a pass.
tap_plan() { printf '1..%s\n' "$1"; }

# diag <text>… — a TAP comment. Not an assertion.
diag() {
  for _d_line in "$@"; do
    printf '# %s\n' "$_d_line"
  done
}

# ok <desc>
ok() {
  TAP_N=$((TAP_N + 1))
  printf 'ok %s - %s\n' "$TAP_N" "$1"
}

# not_ok <desc> [diag…]
not_ok() {
  TAP_N=$((TAP_N + 1))
  TAP_FAIL=$((TAP_FAIL + 1))
  printf 'not ok %s - %s\n' "$TAP_N" "$1"
  shift
  [ $# -gt 0 ] && diag "$@"
  return 0
}

# todo <desc> <reason> [diag…] — a known gap. Counted, reported, never fatal.
todo() {
  TAP_N=$((TAP_N + 1))
  TAP_TODO=$((TAP_TODO + 1))
  printf 'not ok %s - %s # TODO %s\n' "$TAP_N" "$1" "$2"
  shift 2
  [ $# -gt 0 ] && diag "$@"
  return 0
}
