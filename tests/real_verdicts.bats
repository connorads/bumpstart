#!/usr/bin/env bats
#
# The workflow-level oracle: does the suite still prove anything?
#
# Pure - a directory of lane.verdict files in, an exit class out - so the three ways
# the matrix could go permanently green are unit-tested rather than discovered on a
# weekly schedule six months from now. Each case below is one of them.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  D="$BATS_TEST_TMPDIR/verdicts"
  mkdir -p "$D"
}

# verdict <lane> <class> <assertions> <failed> — write one lane's report, in the
# artifact layout CI produces (one folder per lane).
verdict() {
  mkdir -p "$D/real-verdict-$1"
  {
    printf 'lane\t%s\n' "$1"
    printf 'adapter\tcontainer\n'
    printf 'class\t%s\n' "$2"
    printf 'runs_judged\t%s\n' "$([ "$3" -gt 0 ] && echo 2 || echo 0)"
    printf 'assertions\t%s\n' "$3"
    printf 'passed\t%s\n' "$(( $3 - $4 ))"
    printf 'failed\t%s\n' "$4"
    printf 'todo\t0\n'
  } > "$D/real-verdict-$1/lane.verdict"
}

verdicts() { run bash "$REAL/verdicts.sh" "$D" "$@"; }

@test "a matrix where every lane reached a judgement passes" {
  verdict ubuntu-base 0 33 0
  verdict debian-codex 0 33 0
  verdicts ubuntu-base debian-codex
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '2 of 2 lanes reached a judgement' || { echo "$output"; false; }
}

@test "every leg failing as infrastructure is not a pass, however green each one is" {
  # The shape a per-lane exit status structurally cannot show: a stopped docker
  # daemon, a registry rate limit, a guest that will not boot. Class 2 is a
  # ::warning by design, so all eight go green and nobody reads the annotations on
  # a weekly schedule.
  verdict ubuntu-base 2 0 0
  verdict debian-codex 2 0 0
  verdicts ubuntu-base debian-codex
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'NOT ONE lane reached a judgement' || { echo "$output"; false; }
}

@test "one infrastructure failure among lanes that did assert is still a pass" {
  # The class-2 escape hatch has to keep working, or it gets muted for real.
  verdict ubuntu-base 0 33 0
  verdict arch-base 2 0 0
  verdicts ubuntu-base arch-base
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a lane declared in lanes.tsv that never reported is coverage lost silently" {
  verdict ubuntu-base 0 33 0
  verdicts ubuntu-base debian-codex
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'never reported' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'debian-codex' || { echo "$output"; false; }
}

@test "an empty lane list is a harness bug, not a vacuous pass" {
  # The `awk` in the matrix step exits 0 on no match, so a renamed adapter token
  # yields `[]` and the whole matrix covers nothing while staying green.
  run bash "$REAL/verdicts.sh" "$D"
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'no lanes were declared' || { echo "$output"; false; }
}

@test "a directory that is not there is a harness bug" {
  run bash "$REAL/verdicts.sh" "$BATS_TEST_TMPDIR/nope" ubuntu-base
  [ "$status" -eq 3 ]
}

@test "the verdict never reports a lane failure as a vibe failure" {
  # Exit 1 means "vibe is wrong" everywhere else in this harness. Nothing here is a
  # claim about vibe, so nothing here may exit 1 - the per-lane job already went red.
  verdict ubuntu-base 1 33 4
  verdicts ubuntu-base
  [ "$status" -ne 1 ] || { echo "verdicts.sh claimed vibe is wrong"; false; }
  printf '%s\n' "$output" | grep -q '4 failed' || { echo "$output"; false; }
}

# ── The lane runner really writes one ─────────────────────────────────────────

@test "a lane that never reaches the judge still says so out loud" {
  # The exit path that used to leave no record at all: the guest would not start, so
  # the lane reports class 2 and asserts nothing - and class 2 is a green ::warning.
  # A stub docker that answers `info` with a failure is the whole setup; no daemon,
  # no network, no install.
  local bin="$BATS_TEST_TMPDIR/bin" out="$BATS_TEST_TMPDIR/out"
  mkdir -p "$bin"
  printf '#!/bin/sh\nexit 1\n' > "$bin/docker"
  chmod +x "$bin/docker"

  PATH="$bin:$PATH" run bash "$REAL/lanes/run.sh" ubuntu-base --out "$out"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [ -f "$out/lane.verdict" ] || { echo "no verdict was written: $output"; false; }

  run bash "$REAL/verdicts.sh" "$BATS_TEST_TMPDIR" ubuntu-base
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'class 2 ' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'NOT ONE lane reached a judgement' || { echo "$output"; false; }
}
