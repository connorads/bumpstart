#!/usr/bin/env bats
#
# The probe's own reporting of what it could NOT measure.
#
# The probe gathers and judges nothing, so most of it is only meaningful inside a
# guest. What is testable anywhere - and what has bitten - is the boundary between
# "this machine does not have that" and "the harness never took the measurement".
# The judge fails closed on an absent key, so getting that boundary wrong turns a
# harness failure into a page of "nothing was measured", which reads as class 1.
#
# Run against a STARVED PATH holding only the text utilities the probe legitimately
# needs, in a throwaway HOME. That keeps it to well under a second, and it stops the
# developer's own machine deciding what the probe finds.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  S="$BATS_TEST_TMPDIR/state"
  H="$BATS_TEST_TMPDIR/home"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$S" "$H" "$BIN"
  local p
  for c in sed tr grep awk cat uname id basename dirname readlink shasum sha256sum bash; do
    p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$BIN/$c"
  done
}

# probe — run it as if inside a guest with nothing installed.
probe() {
  run env -i PATH="$BIN" HOME="$H" SHELL=/bin/false BUMP_REAL_DIR="$S" \
    "$BIN/bash" "$REAL/probe.sh"
}

mval() { printf '%s\n' "$output" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'; }

@test "a precheck that died half-way is reported as missing, not as a measurement" {
  # run.sh writes precheck.tsv through a .part file for exactly this reason, but the
  # probe is the last line: an EMPTY file used to satisfy `[ -f ]`, so the manifest
  # carried no marker and no keys, and the judge blamed bumpstart for it.
  : > "$S/precheck.tsv"
  probe
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mval probe.missing.precheck)" = 1 ] || { echo "an empty precheck read as a complete one"; false; }
}

@test "an absent precheck is reported the same way" {
  probe
  [ "$(mval probe.missing.precheck)" = 1 ] || { echo "$output"; false; }
}

@test "a real precheck is carried into the manifest and not reported missing" {
  printf 'precheck.curl\tpresent\nprecheck.bumpstart_marker\tabsent\n' > "$S/precheck.tsv"
  probe
  [ -z "$(mval probe.missing.precheck)" ] || { echo "a populated precheck read as missing"; false; }
  [ "$(mval precheck.curl)" = present ] || { echo "$output"; false; }
}

@test "an empty lane.tsv is missing too - it is what only the runner knows" {
  # Without lane / axis / run the judge cannot tell a password lane's first run from
  # its second, and an empty file is the shape a truncate-then-fill leaves behind.
  : > "$S/lane.tsv"
  probe
  [ "$(mval probe.missing.lane)" = 1 ] || { echo "$output"; false; }
}

@test "the manifest says which shape it is, so a judge from another era says so" {
  probe
  [ "$(mval manifest_version)" = 2 ] || { echo "$output"; false; }
}
