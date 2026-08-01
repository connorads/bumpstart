#!/usr/bin/env bats
#
# _step_satisfied (plan.sh) — the consent gate's per-step probe, which had no test
# at all. It is where a leaking CHECK cell was first seen, because unlike
# block_check it evals the probe INLINE while rendering the gate: whatever the
# cell prints lands between two rows of the one screen the whole design asks a
# beginner to read.
#
# Covers the field preference (SATISFIED_<os> over CHECK_<os>), the 0/1/2 status
# contract, and the silence. Synthetic blocks in a temp root, so each cell is
# exact and hermetic; driven under /bin/bash 3.2 via the isolated PATH.

load helpers/common

setup() {
  setup_isolated_env
  # The synthetic cells below are *_MAC, so the probe is exercised through the mac
  # lane. Pinned, not inherited from the host.
  export VIBE_OS=mac
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/blocks"
}

# mk_block <id> <meta-line>... — write a synthetic block's meta from the lines.
mk_block() {
  id="$1"; shift
  mkdir -p "$ROOT/blocks/$id"
  printf '%s\n' "$@" > "$ROOT/blocks/$id/meta"
}

probe() { run bash "$REPO_ROOT/tests/helpers/plan_driver.sh" "$REPO_ROOT/lib" "$ROOT" "$1"; }

@test "a satisfied CHECK cell reports done (0)" {
  mk_block done_ 'KIND=tool' "CHECK_MAC='true'"
  probe done_
  [ "$status" -eq 0 ]
}

@test "an unsatisfied CHECK cell reports actionable (1)" {
  mk_block todo 'KIND=tool' "CHECK_MAC='false'"
  probe todo
  [ "$status" -eq 1 ]
}

@test "a block with no cell for this OS is unmapped (2), rendered as a neutral row" {
  # Instruction blocks land here deliberately: "is this guidance already present"
  # is a question about the canonical file, not about this step. A wrong ✓ is
  # worse than a neutral row.
  mk_block note 'KIND=instructions' 'DESC=x'
  probe note
  [ "$status" -eq 2 ]
}

@test "an unknown id is unmapped (2), not a crash" {
  probe nosuchblock
  [ "$status" -eq 2 ]
}

@test "SATISFIED_<os> wins over CHECK_<os> when both are present" {
  # The gate-only escape hatch, for a block whose "done" differs from "the binary
  # is present" — gh signed in, git identity set. Its answer must win, or the row
  # overclaims.
  mk_block gate 'KIND=auth' "SATISFIED_MAC='false'" "CHECK_MAC='true'"
  probe gate
  [ "$status" -eq 1 ]
}

@test "CHECK_<os> is the fallback when there is no SATISFIED cell" {
  mk_block plain 'KIND=tool' "CHECK_MAC='true'"
  probe plain
  [ "$status" -eq 0 ]
}

@test "a CHECK cell that prints does not leak into the consent gate" {
  # Seen for real: a cell missing its own >/dev/null printed between two rows of
  # the gate. The caller enforces the silence now, so a cell that forgets cannot
  # deface the one screen a beginner is asked to read.
  mk_block noisy 'KIND=tool' "CHECK_MAC='echo LEAK-STDOUT'"
  probe noisy
  [ "$status" -eq 0 ]
  [[ "$output" != *"LEAK-STDOUT"* ]]
}

@test "a CHECK cell that prints to stderr does not leak either" {
  mk_block noisyerr 'KIND=tool' "CHECK_MAC='echo LEAK-STDERR >&2; false'"
  probe noisyerr
  [ "$status" -eq 1 ]
  [[ "$output" != *"LEAK-STDERR"* ]]
}

@test "a SATISFIED cell that prints does not leak either" {
  mk_block noisysat 'KIND=auth' "SATISFIED_MAC='echo LEAK-SAT'"
  probe noisysat
  [ "$status" -eq 0 ]
  [[ "$output" != *"LEAK-SAT"* ]]
}
