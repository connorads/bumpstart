#!/usr/bin/env bats
# bats file_tags=integration
#
# Applier end-to-end with everything faked. Exercises composition, instructions
# landing where each agent actually reads them, idempotence, and plan-time
# failure. Targets lib/apply.sh directly — the `vibe` bootstrap's network fetch
# is covered by a manual VM smoke, not here.

load helpers/common

setup() {
  setup_isolated_env
  make_fake brew
  make_fake_curl
  make_fake_gh
  make_fake claude
  make_fake codex
}

apply() { run bash "$REPO_ROOT/lib/apply.sh" "$@"; }

@test "vibe claude codex: installs both, launches the last (codex)" {
  apply claude codex --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  [[ "$output" == *"Setup complete"* ]]
}

@test "instructions land where Claude reads them (~/.claude/CLAUDE.md)" {
  apply claude concise --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  grep -Fq "<!-- vibe:concise start -->" "$HOME/.claude/CLAUDE.md"
  [ ! -f "$HOME/.agents/AGENTS.md" ]
}

@test "instructions land where Codex reads them (~/.codex/AGENTS.md)" {
  apply codex concise --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  grep -Fq "<!-- vibe:concise start -->" "$HOME/.codex/AGENTS.md"
  [ ! -f "$HOME/.claude/CLAUDE.md" ]
}

@test "second run all-skips and the target file is byte-identical" {
  apply claude concise --yes --no-launch --no-desktop
  once="$(cat "$HOME/.claude/CLAUDE.md")"
  apply claude concise --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  twice="$(cat "$HOME/.claude/CLAUDE.md")"
  [ "$once" = "$twice" ]
  [[ "$output" == *"already installed"* ]]
}

@test "unknown id fails at plan time and applies nothing" {
  apply bogus --yes --no-launch --no-desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: bogus"* ]]
  [ ! -f "$HOME/.claude/CLAUDE.md" ]
}
