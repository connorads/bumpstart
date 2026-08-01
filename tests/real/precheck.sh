#!/usr/bin/env bash
# precheck.sh: run INSIDE a guest BEFORE the first real run, and print the baseline
# every later assertion is measured against.
#
#   BUMP_REAL_DIR=/tmp/vibe-real tests/real/precheck.sh > precheck.tsv
#
# It gathers and normalises; it judges NOTHING — the same split as probe.sh, for the
# same reason.
#
# Why a baseline exists at all: judge.sh asserts END STATE ("git runs", "git resolves
# in a fresh shell"), and on a machine that shipped git those were already true
# before vibe ran. An assertion with no baseline is not an assertion. So this
# measures the SAME things probe.sh measures afterwards, through the same
# lib/measure.sh, and the judge asserts the difference: a tool that did not resolve
# before and does now resolves BECAUSE OF vibe. Where the delta is empty — git on
# ubuntu-base — the judge says so instead of claiming credit.
#
# Run ONCE, before run 1, and left in place for every later run: `precheck.vibe_marker
# absent` has to keep meaning "the guest was pristine when we started" rather than
# "run 2 found what run 1 wrote". It runs AFTER the axis mutation, so an axis that
# went vacuous (a base image that starts shipping curl) is visible rather than
# assumed.
#
# Output goes to stdout and the runner writes it in one shot: a precheck that dies
# half-way must not leave a short file that reads as a complete measurement.
#
# bash-3.2-clean. Deliberately NOT `set -e`: see probe.sh.

set -u

HERE="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/real/lib/measure.sh
. "$HERE/lib/measure.sh"

emit() { printf 'precheck.%s\t%s\n' "$1" "$2"; }

# ── What the machine already has ─────────────────────────────────────────────
#
# What stops an axis going vacuous: a base image that starts shipping curl cannot
# silently turn the no-curl leg into a second base leg, and a de-brew scrub whose
# uninstaller flags changed cannot silently turn the drift lane into "brew was
# already installed".

for _t in curl wget git gpg brew; do
  if command -v "$_t" >/dev/null 2>&1; then emit "$_t" present; else emit "$_t" absent; fi
done

if sudo -n true >/dev/null 2>&1; then emit nopasswd present; else emit nopasswd absent; fi

_rc="$(measure_rc_file)"
if [ -n "$_rc" ] && [ -f "$_rc" ] && grep -Fq '# >>> vibe-setup >>>' "$_rc"; then
  emit vibe_marker present
else
  emit vibe_marker absent
fi

# ── The baseline the fresh-shell assertions are a delta against ──────────────

emit shell.kind "$MEASURE_SHELL_KIND"
for _m in $MEASURE_SHELL_MODES; do
  for _t in $MEASURE_TOOLS; do
    emit "shell.$_m.$_t" "$(measure_fresh "$_m" "$_t")"
  done
done

exit 0
