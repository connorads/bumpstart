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

bumpstart() { run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" "$@"; }

# index of the first output line containing $1 (or empty if absent)
line_of() { printf '%s\n' "$output" | grep -n -F -- "$1" | head -1 | cut -d: -f1; }

@test "--list: exits 0 and shows each block's description" {
  bumpstart --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Install Claude Code"* ]]
  [[ "$output" == *"Install mise"* ]]
  [[ "$output" == *"Install Node.js"* ]]
  [[ "$output" == *"concise output"* ]]
}

@test "--list: groups by axis, in the axes' declared ORDER" {
  bumpstart --list
  [ "$status" -eq 0 ]
  r="$(line_of 'recipe —')"
  a="$(line_of 'agent —')"
  t="$(line_of 'tools —')"
  s="$(line_of 'steering —')"
  [ "$r" -lt "$a" ]
  [ "$a" -lt "$t" ]
  [ "$t" -lt "$s" ]
  # each heading carries the wizard's own question, so the two speak one vocabulary
  [[ "$output" == *"Which agent should launch?"* ]]
}

@test "--list: an axis-less block lands in the dependencies group, last" {
  bumpstart --list
  [ "$status" -eq 0 ]
  d="$(line_of 'dependencies')"
  m="$(line_of 'Install mise')"
  s="$(line_of 'steering —')"
  [ "$s" -lt "$d" ]
  [ "$d" -lt "$m" ]
  [[ "$output" == *"never asked about"* ]]
}

@test "--list: kind survives as a tag, not a heading" {
  bumpstart --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[harness]"*"Install Claude Code"* ]]
  [[ "$output" == *"[instructions]"* ]]
}

@test "--list: node row shows its mise dep inline" {
  bumpstart --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Install Node.js"*"(pulls in: mise)"* ]]
}

@test "--list: preset shows its expansion" {
  bumpstart --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"starter"* ]]
  [[ "$output" == *"expands to:"*"web beginner"* ]]
}

@test "--show node: kind tool and dep mise" {
  bumpstart --show node
  [ "$status" -eq 0 ]
  [[ "$output" == *"[tool]"* ]]
  [[ "$output" == *"pulls in:"*"mise"* ]]
}

@test "--show claude-cli: reports its instruction TARGET" {
  bumpstart --show claude-cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"[harness]"* ]]
  [[ "$output" == *".claude/CLAUDE.md"* ]]
}

@test "--show claude-desktop: is an app block" {
  bumpstart --show claude-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"[app]"* ]]
  [[ "$output" == *"desktop app"* ]]
}

@test "--show claude: is a bundle expanding to cli + desktop" {
  bumpstart --show claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"[preset]"* ]]
  [[ "$output" == *"expands to:"*"claude-cli"*"claude-desktop"* ]]
}

@test "--show node: names the axis it is offered on" {
  bumpstart --show node
  [ "$status" -eq 0 ]
  [[ "$output" == *"axis:"*"tools"* ]]
}

@test "--show mise: says plainly that it is never offered on its own" {
  bumpstart --show mise
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulled in as a dependency"* ]]
}

@test "--show mise: notes it adds agent guidance" {
  bumpstart --show mise
  [ "$status" -eq 0 ]
  [[ "$output" == *"adds agent guidance"* ]]
}

@test "--show: a block whose only content is per-OS still reports its guidance" {
  # os-guidance ships content.mac.md and no neutral content.md — the case a
  # plain content.md test misses, and the case --plan and the resolver both count.
  run env BUMP_ROOT="$FIX" BUMP_OS=mac bash "$REPO_ROOT/lib/apply.sh" --show os-guidance
  [ "$status" -eq 0 ]
  [[ "$output" == *"adds agent guidance"* ]]
}

@test "--list / --show emit no shell noise on stderr" {
  # Every assertion here is a positive substring match, so a set -u failure inside
  # meta_get (an unlisted field name, e.g. a per-OS variant nobody pre-declared)
  # would print to stderr, leave status 0, and go unnoticed.
  bumpstart --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" != *"meta.sh: line"* ]]
  bumpstart --show claude-cli
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" != *"meta.sh: line"* ]]
}

@test "--show nope: unknown block is a non-zero error" {
  bumpstart --show nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: nope"* ]]
}
