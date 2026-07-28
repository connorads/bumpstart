#!/usr/bin/env bats
#
# The exit-class ordering, which decides whether CI goes red. Pure: no guest, no
# network — the same reason the judge is unit-tested here rather than only by a
# 40-minute lane run.
#
# The case that earns this file: 1 beats 2. A numeric max reads the pair
# (assertion failed, then a transient DNS failure) as class 2, CI turns that into a
# green ::warning, and the log bundle proving vibe is wrong is never written.

load helpers/common

setup() {
  # shellcheck source=tests/real/lib/class.sh
  . "$REPO_ROOT/tests/real/lib/class.sh"
}

# worse <current> <candidate> <want>
worse() {
  local got
  got="$(class_worse "$1" "$2")"
  [ "$got" = "$3" ] || { echo "class_worse $1 $2 = [$got], want [$3]"; false; }
}

@test "an assertion failure survives anything that follows it" {
  worse "$CLASS_ASSERT" "$CLASS_INFRA"   "$CLASS_ASSERT"
  worse "$CLASS_ASSERT" "$CLASS_HARNESS" "$CLASS_ASSERT"
  worse "$CLASS_ASSERT" 0                "$CLASS_ASSERT"
  worse "$CLASS_ASSERT" "$CLASS_ASSERT"  "$CLASS_ASSERT"
}

@test "an assertion failure overrides anything that preceded it" {
  worse 0                "$CLASS_ASSERT" "$CLASS_ASSERT"
  worse "$CLASS_INFRA"   "$CLASS_ASSERT" "$CLASS_ASSERT"
  worse "$CLASS_HARNESS" "$CLASS_ASSERT" "$CLASS_ASSERT"
}

@test "a harness bug beats infrastructure, because you learn nothing until it is fixed" {
  worse "$CLASS_INFRA"   "$CLASS_HARNESS" "$CLASS_HARNESS"
  worse "$CLASS_HARNESS" "$CLASS_INFRA"   "$CLASS_HARNESS"
}

@test "a pass never downgrades a class already recorded" {
  worse "$CLASS_INFRA"   0 "$CLASS_INFRA"
  worse "$CLASS_HARNESS" 0 "$CLASS_HARNESS"
  worse 0                0 0
}

@test "the first thing that goes wrong is recorded" {
  worse 0 "$CLASS_INFRA"   "$CLASS_INFRA"
  worse 0 "$CLASS_HARNESS" "$CLASS_HARNESS"
}
