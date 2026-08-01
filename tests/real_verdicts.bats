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

# verdict <lane> <class> <assertions> <failed> [apply-seconds] — write one lane's
# report, in the artifact layout CI produces (one folder per lane). The durations are
# optional on purpose: they are what a lane MEASURES, not what it is judged on, so a
# report without them still has to read.
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
    if [ -n "${5:-}" ]; then
      printf 'duration_apply_s\t%s\n' "$5"
      printf 'duration_lane_s\t%s\n' "$(( $(slowest "$5") + 20 ))"
    fi
  } > "$D/real-verdict-$1/lane.verdict"
}

# slowest <space-separated> — the largest, for the fixture's own lane total.
slowest() {
  local max=0
  for n in $1; do [ "$n" -gt "$max" ] && max="$n"; done
  printf '%s' "$max"
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

@test "the verdict never reports a lane failure as a bumpstart failure" {
  # Exit 1 means "bumpstart is wrong" everywhere else in this harness. Nothing here is a
  # claim about bumpstart, so nothing here may exit 1 - the per-lane job already went red.
  verdict ubuntu-base 1 33 4
  verdicts ubuntu-base
  [ "$status" -ne 1 ] || { echo "verdicts.sh claimed bumpstart is wrong"; false; }
  printf '%s\n' "$output" | grep -q '4 failed' || { echo "$output"; false; }
}

# ── How long it took: reported, never asserted ────────────────────────────────

@test "each lane's durations are reported beside its assertion counts" {
  verdict ubuntu-base 0 33 0 '31 4'
  verdict debian-codex 0 33 0 '28 3'
  verdicts ubuntu-base debian-codex
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'apply 31 4' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '51s lane' || { echo "$output"; false; }
}

@test "the lane that took forty times as long as its siblings is named" {
  # The finding this exists for: ubuntu-no-curl passed in 22 minutes, its first apply
  # taking 19m37s against roughly 30s for the same image with curl. No lane can see
  # that - it is a comparison between lanes - and the transcript that would say which
  # cell was slow is only worth fetching if something points at it.
  verdict ubuntu-base 0 33 0 '31 4'
  verdict debian-codex 0 33 0 '28 3'
  verdict ubuntu-no-curl 0 33 0 '1177 1'
  verdicts ubuntu-base debian-codex ubuntu-no-curl
  # REPORTED, not asserted: a timing assertion in CI is a flake generator, so the
  # exit status must not move.
  [ "$status" -eq 0 ] || { echo "a duration changed the exit status: $output"; false; }
  printf '%s\n' "$output" | grep -q 'SLOW: ubuntu-no-curl spent 1177s' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'median' || { echo "$output"; false; }
}

@test "a matrix that is merely fast, or merely uniform, is not an outlier" {
  # Proportion alone would fire here (4s is 4x a 1s median) and say nothing. And a
  # slow matrix where every lane is slow has no outlier to name either.
  verdict ubuntu-base 0 33 0 '1 1'
  verdict debian-codex 0 33 0 '4 1'
  verdicts ubuntu-base debian-codex
  printf '%s\n' "$output" | grep -q 'SLOW:' && { echo "a 4-second lane was called slow"; false; }

  verdict ubuntu-base 0 33 0 '600 590'
  verdict debian-codex 0 33 0 '620 600'
  verdicts ubuntu-base debian-codex
  printf '%s\n' "$output" | grep -q 'SLOW:' && { echo "a uniformly slow matrix named an outlier"; false; }
  true
}

@test "a verdict from a runner that measured nothing still reports" {
  # The durations are a measurement a lane adds, not a key the summary depends on: an
  # older lane.verdict, or a lane that died before its first apply, carries none.
  verdict ubuntu-base 0 33 0
  verdicts ubuntu-base
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '33 assertions' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'apply ?' || { echo "$output"; false; }
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
