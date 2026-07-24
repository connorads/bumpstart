#!/usr/bin/env bats
#
# Pure core (resolve.sh) exercised black-box through the applier's --plan
# dry-run against a fixture block tree. Richest logic, no I/O, no effects.

load helpers/common

setup() {
  setup_isolated_env
  FIX="$REPO_ROOT/tests/fixtures"
}

plan() { run env VIBE_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --plan "$@"; }

# index of the first output line containing $1 (or empty if absent)
line_of() { printf '%s\n' "$output" | grep -n -F -- "$1" | head -1 | cut -d: -f1; }

@test "single id: harness resolves and launches" {
  plan claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"[harness]"* ]]
  [[ "$output" == *"Agent to launch: claude"* ]]
}

@test "harness + instructions targets the harness file" {
  plan claude concise
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/CLAUDE.md"* ]]
}

@test "a tool block that ships content.md targets the harness file (no instructions block needed)" {
  plan claude mise
  [ "$status" -eq 0 ]
  [[ "$output" == *"Instructions file"* ]]
  [[ "$output" == *".claude/CLAUDE.md"* ]]
}

@test "preset expands to its included blocks" {
  plan web-starter
  [ "$status" -eq 0 ]
  # web-starter INCLUDEs claude gh-auth node react concise context7
  [[ "$output" == *"[harness]"* ]]
  [[ "$output" == *"[auth]"* ]]
  [[ "$output" == *"[skill]"* ]]
  [[ "$output" == *"[mcp]"* ]]
  [[ "$output" == *"[instructions]"* ]]
  [[ "$output" == *"Agent to launch: claude"* ]]
  # the preset id itself is sugar, never a step
  refute_fake_logged "web-starter"
}

@test "a dependency pulled in twice appears once (node -> mise)" {
  plan claude node node
  [ "$status" -eq 0 ]
  # the dependent itself survives (regression: recursion once clobbered it)...
  [[ "$output" == *"Install Node.js"* ]]
  # ...and its dependency appears exactly once
  count="$(printf '%s\n' "$output" | grep -c -F 'Install mise')"
  [ "$count" -eq 1 ]
}

@test "dep appears before dependent (mise before node)" {
  plan claude node
  [ "$status" -eq 0 ]
  m="$(line_of 'Install mise')"
  n="$(line_of 'Install Node.js')"
  [ "$m" -lt "$n" ]
}

@test "include cycle is a domain error" {
  plan cyc-a
  [ "$status" -ne 0 ]
  [[ "$output" == *"cycle"* ]]
}

@test "unknown id is a domain error" {
  plan bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: bogus"* ]]
}

@test "a plan with no harness is a domain error" {
  plan gh-auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"no harness"* ]]
}

@test "last harness in the list wins (claude codex -> codex)" {
  plan claude codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
}

@test "last harness in the list wins, reversed (codex claude -> claude)" {
  plan codex claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: claude"* ]]
}

@test "steps are ordered by kind regardless of input order" {
  plan concise gh-auth claude
  [ "$status" -eq 0 ]
  h="$(line_of '[harness]')"
  a="$(line_of '[auth]')"
  i="$(line_of '[instructions]')"
  [ "$h" -lt "$a" ]
  [ "$a" -lt "$i" ]
}

@test "instruction target is per-harness: both harnesses -> both files" {
  plan claude codex concise
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/CLAUDE.md"* ]]
  [[ "$output" == *".codex/AGENTS.md"* ]]
}

@test "codex + instructions targets AGENTS.md, not CLAUDE.md" {
  plan codex concise
  [ "$status" -eq 0 ]
  [[ "$output" == *".codex/AGENTS.md"* ]]
  [[ "$output" != *".claude/CLAUDE.md"* ]]
}

@test "a harness with no instructions block shows no instruction target" {
  plan codex
  [ "$status" -eq 0 ]
  [[ "$output" != *"Instructions file"* ]]
}

# --- metamorphic properties (by hand; no bash PBT framework) -------------------

@test "permuting non-harness inputs yields an identical plan" {
  plan claude gh-auth concise
  a="$output"
  plan concise gh-auth claude
  b="$output"
  [ "$a" = "$b" ]
}

@test "dedup is idempotent: repeats collapse to the single-id plan" {
  plan claude node
  a="$output"
  [ "$status" -eq 0 ]
  plan claude node node node
  b="$output"
  [ "$a" = "$b" ]
}
