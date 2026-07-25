#!/usr/bin/env bats
#
# The author-facing wizard (build.sh) driven through the applier's --build flag.
# Answers are piped on stdin; PATH-shadow fakes (incl. pbcopy) prove that even
# the run-now fall-through reaches resolve without performing a real install or
# touching the real clipboard.

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
  run env VIBE_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"--list"* ]]
}

@test "--build: happy path emits the one-paste command for the chosen ids" {
  # optional blocks, in kind-rank order: claude-desktop codex-desktop gh-auth
  # cyc-a cyc-b mise node context7 react concise. Pick node (#7) + concise (#10).
  run env VIBE_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
1
n
n
n
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
  # claude-cli (harness) + node + concise; mise is a dep, not a chosen id.
  [[ "$output" == *'_ claude-cli node concise'* ]]
  # Read-only: run-now declined, so nothing installed.
  refute_fake_logged "brew"
  refute_fake_logged "INSTALL claude"
}

@test "--build: VIBE_REF pins the emitted command with a ref prefix" {
  # pick only node (#7); decline the rest and run-now.
  run env VIBE_REF=abc123 VIBE_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
1
n
n
n
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
  [[ "$output" == *'VIBE_REF=abc123 /bin/bash -c'* ]]
  [[ "$output" == *'_ claude-cli node'* ]]
}

@test "--build: run-now=yes falls through to resolve but never installs (non-tty confirm aborts)" {
  # pick node (#7), then answer run-now with y.
  run env VIBE_ROOT="$FIX" bash "$REPO_ROOT/lib/apply.sh" --build <<'ANS'
1
n
n
n
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
