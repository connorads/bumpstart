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
  make_fake mise
  make_fake node
  # Log what gets copied instead of touching the real clipboard.
  make_fake pbcopy 'cat >> "$VIBE_FAKE_LOG"'
}

apply() { run bash "$REPO_ROOT/lib/apply.sh" "$@"; }

@test "vibe claude codex: installs both, launches the last (codex)" {
  apply claude codex --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  [[ "$output" == *"Setup complete"* ]]
}

@test "instructions land in the canonical file; Claude's path links to it" {
  apply claude concise --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  canon="$HOME/.config/agents/AGENTS.md"
  grep -Fq "## Be concise" "$canon"
  ! grep -Fq "<!-- vibe" "$canon"
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$canon" ]
}

@test "Codex's path links to the same canonical file" {
  apply codex concise --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  canon="$HOME/.config/agents/AGENTS.md"
  grep -Fq "## Be concise" "$canon"
  [ -L "$HOME/.codex/AGENTS.md" ]
  [ "$(readlink "$HOME/.codex/AGENTS.md")" = "$canon" ]
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
}

@test "a tool block's guidance lands in the canonical file" {
  apply claude node --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  canon="$HOME/.config/agents/AGENTS.md"
  grep -Fq "## Node.js" "$canon"
  grep -Fq "## Installing tools (mise)" "$canon"
  [ -L "$HOME/.claude/CLAUDE.md" ]
}

@test "second run leaves the canonical byte-identical and the link intact" {
  apply claude concise --yes --no-launch --no-desktop
  canon="$HOME/.config/agents/AGENTS.md"
  once="$(cat "$canon")"
  apply claude concise --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  twice="$(cat "$canon")"
  [ "$once" = "$twice" ]
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$canon" ]
  [[ "$output" == *"already installed"* ]]
}

@test "codex run pre-trusts the starter dir in ~/.codex/config.toml" {
  apply codex --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  starter="$(cd "$HOME/code/first-project" && pwd -P)"
  grep -Fq "[projects.\"$starter\"]" "$HOME/.codex/config.toml"
  grep -Fq 'trust_level = "trusted"' "$HOME/.codex/config.toml"
}

@test "web-starter preset applies the whole stack for Claude" {
  apply web-starter --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: claude"* ]]
  # node (via mise dep) is in the plan, and instructions land in the canonical file
  [[ "$output" == *"Node.js"* ]]
  grep -Fq "## Be concise" "$HOME/.config/agents/AGENTS.md"
}

@test "bare paste (no ids) defaults to the full web-starter setup" {
  apply --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: claude"* ]]
  [[ "$output" == *"Node.js"* ]]
  [[ "$output" == *"Setup complete"* ]]
  # not the old bare-agent error path
  [[ "$output" != *"no blocks requested"* ]]
  grep -Fq "## Be concise" "$HOME/.config/agents/AGENTS.md"
}

@test "web-starter includes the welcome block; its text lands in the canonical file" {
  apply web-starter --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  grep -Fq "## Welcome" "$HOME/.config/agents/AGENTS.md"
}

@test "an id after a preset overrides its harness (web-starter codex -> codex)" {
  apply web-starter codex --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
}

@test "non-macOS exits 0 with an honest redirect, before any effect" {
  make_fake uname 'printf "Linux\n"'
  apply claude --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"macOS-only for now"* ]]
  # guard fires before ensure_brew / any block, so nothing ran
  refute_fake_logged "brew"
  refute_fake_logged "claude"
}

@test "the starter prompt is copied to the clipboard with paste guidance" {
  apply claude --yes --no-launch --no-desktop
  [ "$status" -eq 0 ]
  # a distinctive phrase from starter-prompt.txt reached pbcopy
  fake_logged "build it together"
  # and the novice is told how to paste it
  [[ "$output" == *"Cmd+V"* ]]
}

@test "unknown id fails at plan time and applies nothing" {
  apply bogus --yes --no-launch --no-desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: bogus"* ]]
  [ ! -f "$HOME/.claude/CLAUDE.md" ]
}
