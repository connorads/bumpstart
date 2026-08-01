# shellcheck shell=bash
# class.sh: the three exit classes, and the ONE ordering over them.
#
#   1  an assertion failed   — bumpstart is wrong. Never tolerable.
#   3  a harness bug         — the lanes proved nothing until it is fixed.
#   2  infrastructure        — upstream moved. Reportable without going red.
#
# Severity order, NOT numeric order: 1 beats 3 beats 2 beats 0. The numbers are exit
# statuses, chosen so 1 is the familiar "it failed"; they carry no ordering of their
# own, and taking a numeric max over them is silently wrong in the direction that
# matters. Run 1 fails an assertion (1) and run 2 hits a transient DNS failure (2):
# a max reports 2, CI's `case 2` prints a ::warning, the job stays GREEN, and the
# log bundle that would have shown the regression is never written.
#
# One owner, because the runner and the driver both aggregate and a second copy is
# a second chance to get it backwards.
#
# bash-3.2-clean. Sourced, not executed.

CLASS_ASSERT=1
CLASS_INFRA=2
CLASS_HARNESS=3

# class_worse <current> <candidate> — the more severe of the two, on stdout.
# A candidate of 0 (or anything unrecognised) leaves the current class alone.
class_worse() {
  case "$2:$1" in
    1:*)     printf '1' ;;
    3:1)     printf '%s' "$1" ;;
    3:*)     printf '3' ;;
    2:1|2:3) printf '%s' "$1" ;;
    2:*)     printf '2' ;;
    *)       printf '%s' "$1" ;;
  esac
}
