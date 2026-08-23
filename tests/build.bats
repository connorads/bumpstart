#!/usr/bin/env bats
#
# The author-facing wizard (build.sh) driven through the applier's --build flag.
# Answers are piped on stdin; PATH-shadow fakes (incl. pbcopy) prove that even
# the run-now fall-through reaches resolve without performing a real install or
# touching the real clipboard.
#
# The wizard is a fold over the fixture tree's axes, so every answer script below
# is positional in that order:
#
#   recipe   (multi) starter
#   agent    (one)   1) claude  2) codex  3) claude-cli  4) codex-cli
#   tools    (multi) web  context7  github  node  react
#   steering (multi) beginner  concise
#   run now  (y/N)
#
# Presets lead each group (the coarse choice first), then ids alphabetically.

load helpers/common

setup() {
  setup_isolated_env
  FIX="$REPO_ROOT/tests/fixtures"
  # Never touch the real clipboard from a test run.
  make_fake pbcopy
  # Install fakes: any appearance in the log would prove an unwanted apply.
  make_fake brew
  make_fake_curl
  make_fake_gh
  make_fake claude
  make_fake codex
  make_fake mise
  make_fake node
}

@test "--build: no answers on stdin is a non-zero error pointing at --list" {
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"--list"* ]]
}

@test "--build: one question per axis, asked in the axes' declared ORDER" {
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
n
1
n
n
n
n
n
n
n
n
ANS
  [ "$status" -eq 0 ]
  r="$(printf '%s\n' "$output" | grep -n -F 'Start from a ready-made setup?' | head -1 | cut -d: -f1)"
  a="$(printf '%s\n' "$output" | grep -n -F 'Which agent should launch?' | head -1 | cut -d: -f1)"
  t="$(printf '%s\n' "$output" | grep -n -F 'What should we install?' | head -1 | cut -d: -f1)"
  s="$(printf '%s\n' "$output" | grep -n -F 'How should the agent be steered?' | head -1 | cut -d: -f1)"
  [ "$r" -lt "$a" ]
  [ "$a" -lt "$t" ]
  [ "$t" -lt "$s" ]
}

@test "--build: happy path emits the one-paste command for the chosen ids" {
  # agent = claude-cli (#3), plus node and concise; everything else declined.
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
n
3
n
n
n
y
n
n
y
n
ANS
  [ "$status" -eq 0 ]
  # claude-cli (the agent pick) leads; mise is a dep, not a chosen id
  [[ "$output" == *'_ claude-cli node concise'* ]]
  # Read-only: run-now declined, so nothing installed.
  refute_fake_logged "brew"
  refute_fake_logged "INSTALL claude"
}

@test "--build: the recipe + agent answers emit the handout the README documents" {
  # starter on the recipe axis, the claude bundle (#1, the axis DEFAULT) as agent
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
y
1
n
n
n
n
n
n
n
n
ANS
  [ "$status" -eq 0 ]
  # the wizard now spells the handout exactly as the README hands it out
  [[ "$output" == *'_ claude starter'* ]]
  # the agent axis lists bundles and CLI-only atoms in one question
  [[ "$output" == *"1) claude"* ]]
  [[ "$output" == *"3) claude-cli"* ]]
}

@test "--build: an empty answer takes the agent axis DEFAULT" {
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
y

n
n
n
n
n
n
n
n
ANS
  [ "$status" -eq 0 ]
  [[ "$output" == *'_ claude starter'* ]]
}

@test "--build: rows show what they pull in, so wholes and parts read as nested" {
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
n
1
n
n
n
n
n
n
n
n
ANS
  [ "$status" -eq 0 ]
  [[ "$output" == *"starter"*"(pulls in: web beginner)"* ]]
  [[ "$output" == *"node"*"(pulls in: mise)"* ]]
}

@test "--build: BUMP_REF pins the emitted command with a ref prefix" {
  # default agent, node only
  run env BUMP_REF=abc123 BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
n
1
n
n
n
y
n
n
n
n
ANS
  [ "$status" -eq 0 ]
  [[ "$output" == *'BUMP_REF=abc123 /bin/bash -c'* ]]
  [[ "$output" == *'_ claude node'* ]]
}

@test "--build: run-now=yes falls through to resolve but never installs (non-tty confirm aborts)" {
  run env BUMP_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
n
1
n
n
n
y
n
n
n
y
ANS
  # The wizard previews once, then the fall-through re-renders before the confirm
  # gate aborts (piped stdin is not a tty) — so resolve was reached, twice.
  count="$(printf '%s\n' "$output" | grep -c -F 'This will set up')"
  [ "$count" -ge 2 ]
  refute_fake_logged "brew"
  refute_fake_logged "INSTALL claude"
}
