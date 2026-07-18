#!/usr/bin/env bats
#
# Characterisation of install.sh BEFORE the lib extraction, so the refactor is
# provably behaviour-preserving. Black-box with PATH-shadow fakes; brew is real
# but only read (shellenv) — none of the faked commands live under its prefix.

load helpers/common

setup() { setup_isolated_env; }

@test "installs the Claude CLI when absent and reports success" {
  make_fake_curl
  make_fake_gh
  # No claude fake on PATH -> command -v claude fails -> installer runs.

  run bash "$REPO_ROOT/install.sh" --agent claude --no-desktop --no-launch

  [ "$status" -eq 0 ]
  fake_logged "INSTALL claude"
  [[ "$output" == *"Setup complete"* ]]
}

@test "skips the Claude CLI install when already present" {
  make_fake_curl
  make_fake_gh
  make_fake claude

  run bash "$REPO_ROOT/install.sh" --agent claude --no-desktop --no-launch

  [ "$status" -eq 0 ]
  refute_fake_logged "INSTALL claude"
  [[ "$output" == *"already installed"* ]]
}

@test "installs the Codex CLI when absent" {
  make_fake_curl
  make_fake_gh

  run bash "$REPO_ROOT/install.sh" --agent codex --no-desktop --no-launch

  [ "$status" -eq 0 ]
  fake_logged "INSTALL codex"
  [[ "$output" == *"Setup complete"* ]]
}

@test "rejects an unknown agent" {
  run bash "$REPO_ROOT/install.sh" --agent bogus --no-desktop --no-launch

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown agent"* ]]
}

@test "rejects an unknown flag" {
  run bash "$REPO_ROOT/install.sh" --frobnicate

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}
