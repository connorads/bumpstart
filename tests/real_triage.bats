#!/usr/bin/env bats
#
# Transcript triage: is this a story about vibe, or about the world around it?
#
# Pure - a transcript file in, an exit class out - which is the point of lifting it
# out of the lane runner. The rule decides whether CI goes red, and it used to be
# exercisable only by running a ten-minute lane and hoping the right thing broke.
#
# The case that earns this file: a retried mirror timeout. The patterns match text
# that APPEARED, with no notion of recovery, so one transient line returned class 2
# BEFORE the probe ran - and a genuine regression later in the same run was never
# judged.

load helpers/common

setup() {
  # shellcheck source=tests/real/lib/triage.sh
  . "$REPO_ROOT/tests/real/lib/triage.sh"
  T="$BATS_TEST_TMPDIR/transcript"
}

# log <line>... — write a transcript.
log() { printf '%s\n' "$@" > "$T"; }

# The applier's own clean verdict, byte-identical to lib/ui.sh's.
DONE='  Setup complete.'

@test "an ordinary successful run is nobody's infrastructure problem" {
  log '  > Installing Node.js...' "$DONE"
  triage "$T"
  [ "$TRIAGE_CLASS" = 0 ] || { echo "class $TRIAGE_CLASS: $TRIAGE_REASON"; false; }
}

@test "a DNS failure with no install to judge is infrastructure, not a vibe failure" {
  # The observed case: a lane went red for "Couldn't install Node.js" when one DNS
  # lookup failed inside the container. Reporting that as class 1 is how a lane
  # earns a mute.
  log '  > Installing Node.js...' \
      'curl: (6) Could not resolve host: nodejs.org' \
      "  Couldn't install Node.js - continuing"
  triage "$T"
  [ "$TRIAGE_CLASS" = 2 ] || { echo "class $TRIAGE_CLASS"; false; }
  printf '%s\n' "$TRIAGE_REASON" | grep -q 'could not reach the network' || { echo "$TRIAGE_REASON"; false; }
}

@test "a transport failure the run then RECOVERED from is not infrastructure" {
  # THE fix. A mirror times out, the tool retries, the run finishes clean - and the
  # old rule returned class 2 before the probe ran, so a real regression in the same
  # run was never judged at all. An infrastructure error stops being one when the
  # business outcome changes.
  log '  > Installing Node.js...' \
      'Connection timed out after 30000 milliseconds' \
      '  > retrying...' \
      "$DONE"
  triage "$T"
  [ "$TRIAGE_CLASS" = 0 ] || { echo "a recovered timeout was triaged away as class $TRIAGE_CLASS"; false; }
}

@test "a 404 the run recovered from is likewise judged, not excused" {
  log 'The requested URL returned error: 404' '  > falling back' "$DONE"
  triage "$T"
  [ "$TRIAGE_CLASS" = 0 ] || { echo "class $TRIAGE_CLASS"; false; }
}

@test "an unrecovered 404 says the url might be ours" {
  # A vendor deleting an installer is the single most likely thing these lanes exist
  # to catch. It is also what a wrong url in an INSTALL cell looks like - a class-1
  # bug in a class-2 coat - so the caveat is printed rather than assumed.
  log '  > Installing Claude Code...' \
      'The requested URL returned error: 404' \
      '  x Couldn'"'"'t install Claude Code'
  triage "$T"
  [ "$TRIAGE_CLASS" = 2 ]
  printf '%s\n' "$TRIAGE_HINT" | grep -q "INSTALL cell's url" || { echo "$TRIAGE_HINT"; false; }
}

@test "a bootstrap that could not deliver vibe names the ref" {
  log '  x could not fetch vibe-setup at ref deadbee'
  triage "$T" deadbee
  [ "$TRIAGE_CLASS" = 2 ]
  printf '%s\n' "$TRIAGE_REASON" | grep -q "deadbee" || { echo "$TRIAGE_REASON"; false; }
}

@test "an emulated arch that cannot run a vendor binary is infrastructure" {
  # archlinux:base publishes no arm64 image, so on Apple Silicon that lane runs
  # emulated x86_64 and Claude Code's x64 build dies on missing CPU features.
  log '  > Installing Claude Code...' 'Illegal instruction (core dumped)'
  triage "$T"
  [ "$TRIAGE_CLASS" = 2 ]
  printf '%s\n' "$TRIAGE_REASON" | grep -q 'emulated arch' || { echo "$TRIAGE_REASON"; false; }
}

@test "a run that simply failed is NOT excused as infrastructure" {
  # The direction that matters most: the escape hatches must not be so broad that a
  # real failure finds one. Nothing here is a transport error.
  log '  > Installing Node.js...' \
      '  ! the PATH line was not written' \
      '  Setup finished, but some steps need your attention.'
  triage "$T"
  [ "$TRIAGE_CLASS" = 0 ] || { echo "a vibe failure was excused as class $TRIAGE_CLASS"; false; }
}

@test "no transcript at all is a harness bug, not an infrastructure excuse" {
  triage "$BATS_TEST_TMPDIR/never-written"
  [ "$TRIAGE_CLASS" = 3 ] || { echo "class $TRIAGE_CLASS"; false; }
}

@test "each triage call forgets the last one" {
  # The globals are the interface, so a stale reason from a previous run would be
  # attached to the wrong lane.
  log 'Could not resolve host: example.com'
  triage "$T"
  [ "$TRIAGE_CLASS" = 2 ]
  log "$DONE"
  triage "$T"
  [ "$TRIAGE_CLASS" = 0 ] || { echo "class $TRIAGE_CLASS"; false; }
  [ -z "$TRIAGE_REASON" ] || { echo "stale reason: $TRIAGE_REASON"; false; }
  [ -z "$TRIAGE_HINT" ] || { echo "stale hint: $TRIAGE_HINT"; false; }
}
