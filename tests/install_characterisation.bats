#!/usr/bin/env bats
#
# Install parity through the legacy install.sh shim -> applier. The one-paste
# entry still lands the chosen agent's CLI. Black-box with PATH-shadow fakes;
# --yes skips the confirm gate (no tty in bats).

load helpers/common

setup() {
  setup_isolated_env
  make_fake brew   # ensure_brew finds it on PATH -> no install, no shellenv
  make_fake_curl
  make_fake_gh
}

@test "installs the Claude CLI when absent and reports success" {
  run bash "$REPO_ROOT/install.sh" --agent claude --yes --no-desktop --no-launch
  [ "$status" -eq 0 ]
  fake_logged "INSTALL claude"
  [[ "$output" == *"Setup complete"* ]]
}

@test "skips the Claude CLI install when already present" {
  make_fake claude
  run bash "$REPO_ROOT/install.sh" --agent claude --yes --no-desktop --no-launch
  [ "$status" -eq 0 ]
  refute_fake_logged "INSTALL claude"
  [[ "$output" == *"already installed"* ]]
}

@test "installs the Codex CLI when absent" {
  run bash "$REPO_ROOT/install.sh" --agent codex --yes --no-desktop --no-launch
  [ "$status" -eq 0 ]
  fake_logged "INSTALL codex"
  [[ "$output" == *"Setup complete"* ]]
}

@test "no --agent gives the full web-starter setup (not a bare agent)" {
  run bash "$REPO_ROOT/install.sh" --yes --no-desktop --no-launch
  [ "$status" -eq 0 ]
  # web-starter installs the Claude CLI and its instructions land
  fake_logged "INSTALL claude"
  [[ "$output" == *"Agent to launch: claude"* ]]
  grep -Fq "## Be concise" "$HOME/.config/agents/AGENTS.md"
}

@test "rejects an unknown agent at plan time, applying nothing" {
  run bash "$REPO_ROOT/install.sh" --agent bogus --yes --no-desktop --no-launch
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: bogus"* ]]
  refute_fake_logged "INSTALL"
}

@test "rejects an unknown flag" {
  run bash "$REPO_ROOT/install.sh" --frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}
