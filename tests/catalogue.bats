#!/usr/bin/env bats
#
# Author-facing discovery (catalogue.sh) exercised black-box through the
# applier's --list / --show flags against the fixture block tree. Pure reads,
# no I/O, no effects.

load helpers/common

setup() {
  setup_isolated_env
  FIX="$REPO_ROOT/tests/fixtures"
}

vibe() { run env VIBE_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" "$@"; }

# index of the first output line containing $1 (or empty if absent)
line_of() { printf '%s\n' "$output" | grep -n -F -- "$1" | head -1 | cut -d: -f1; }

@test "--list: exits 0 and shows each block's description" {
  vibe --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Install Claude Code"* ]]
  [[ "$output" == *"Install mise"* ]]
  [[ "$output" == *"Install Node.js"* ]]
  [[ "$output" == *"concise output"* ]]
}

@test "--list: groups harness before tool before instructions" {
  vibe --list
  [ "$status" -eq 0 ]
  h="$(line_of 'harness')"
  t="$(line_of 'tool')"
  i="$(line_of 'instructions')"
  [ "$h" -lt "$t" ]
  [ "$t" -lt "$i" ]
}

@test "--list: node row shows its mise dep inline" {
  vibe --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Install Node.js"*"(pulls in: mise)"* ]]
}

@test "--list: preset shows its expansion" {
  vibe --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"web-starter"* ]]
  [[ "$output" == *"expands to:"*"claude"*"concise"* ]]
}

@test "--show node: kind tool and dep mise" {
  vibe --show node
  [ "$status" -eq 0 ]
  [[ "$output" == *"[tool]"* ]]
  [[ "$output" == *"pulls in:"*"mise"* ]]
}

@test "--show claude-cli: reports its instruction TARGET" {
  vibe --show claude-cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"[harness]"* ]]
  [[ "$output" == *".claude/CLAUDE.md"* ]]
}

@test "--show claude-desktop: is an app block" {
  vibe --show claude-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"[app]"* ]]
  [[ "$output" == *"desktop app"* ]]
}

@test "--show claude: is a bundle expanding to cli + desktop" {
  vibe --show claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"[preset]"* ]]
  [[ "$output" == *"expands to:"*"claude-cli"*"claude-desktop"* ]]
}

@test "--list groups the app kind between harness and auth" {
  vibe --list
  [ "$status" -eq 0 ]
  h="$(line_of 'harness')"
  ap="$(line_of 'Install the Claude desktop app')"
  au="$(line_of 'Set up GitHub')"
  [ "$h" -lt "$ap" ]
  [ "$ap" -lt "$au" ]
}

@test "--show mise: notes it adds agent guidance" {
  vibe --show mise
  [ "$status" -eq 0 ]
  [[ "$output" == *"adds agent guidance"* ]]
}

@test "--show nope: unknown block is a non-zero error" {
  vibe --show nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: nope"* ]]
}
