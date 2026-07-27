#!/usr/bin/env bats
#
# Declarative install blocks, driven through the generic runner (run_cell) with
# the block contract in the env. Check-then-act: sentinel present -> "already
# installed"; absent -> the INSTALL_<os> cell runs once. The harness (*-cli) and
# app (*-desktop) blocks are separate; VIBE_APPS_DIR points the app blocks' check
# at an empty dir so the cask install path is reachable without the real app
# present. Escape-hatch blocks (gh-auth) split: run_cell installs, the trimmed
# apply.sh owns the interactive login tail.

load helpers/common

setup() {
  setup_isolated_env
  export VIBE_APPS_DIR="$BATS_TEST_TMPDIR/apps"
  mkdir -p "$VIBE_APPS_DIR"
}

# run_cell <id> — drive the generic runner's declarative install for a block.
run_cell() {
  run env VIBE_APPS_DIR="$VIBE_APPS_DIR" \
    bash "$REPO_ROOT/tests/helpers/run_driver.sh" \
    "$REPO_ROOT/lib" run_cell "$REPO_ROOT" "$1"
}

# run_block <id> — drive a block's interactive apply.sh tail directly.
run_block() {
  id="$1"; shift
  run env VIBE_LIB="$REPO_ROOT/lib" VIBE_ROOT="$REPO_ROOT" \
    VIBE_BLOCK_DIR="$REPO_ROOT/blocks/$id" VIBE_BLOCK_ID="$id" \
    bash "$REPO_ROOT/blocks/$id/apply.sh" "$@"
}

@test "claude-cli block installs the CLI once when absent" {
  make_fake_curl
  run_cell claude-cli
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL claude' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
  # the CLI harness never touches the cask
  refute_fake_logged "brew install --cask claude"
}

@test "claude-cli block installs nothing when the CLI is present" {
  make_fake_curl
  make_fake claude
  run_cell claude-cli
  [ "$status" -eq 0 ]
  refute_fake_logged "INSTALL claude"
  [[ "$output" == *"already installed"* ]]
}

@test "claude-desktop block installs the cask once when the app is absent" {
  make_fake brew
  run_cell claude-desktop
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'brew install --cask claude' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "claude-desktop block installs nothing when the app is present" {
  make_fake brew
  mkdir -p "$VIBE_APPS_DIR/Claude.app"
  run_cell claude-desktop
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install --cask claude"
  [[ "$output" == *"already installed"* ]]
}

@test "codex-cli block installs the CLI once when absent" {
  make_fake_curl
  run_cell codex-cli
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL codex' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "codex-desktop block installs the ChatGPT cask once when the app is absent" {
  make_fake brew
  run_cell codex-desktop
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'brew install --cask chatgpt' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "github-desktop block installs the cask once when the app is absent" {
  make_fake brew
  run_cell github-desktop
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'brew install --cask github' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "github-desktop block installs nothing when the app is present" {
  make_fake brew
  mkdir -p "$VIBE_APPS_DIR/GitHub Desktop.app"
  run_cell github-desktop
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install --cask github"
  [[ "$output" == *"already installed"* ]]
}

@test "mise block installs via brew when absent" {
  make_fake brew
  run_cell mise
  [ "$status" -eq 0 ]
  fake_logged "brew install mise"
}

@test "mise block installs nothing when mise is present" {
  make_fake mise
  run_cell mise
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "node block installs via mise when absent" {
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi'
  run_cell node
  [ "$status" -eq 0 ]
  fake_logged "mise use -g node@lts"
}

@test "pnpm block installs via mise when absent" {
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi'
  run_cell pnpm
  [ "$status" -eq 0 ]
  fake_logged "mise use -g pnpm"
}

@test "gh-auth block installs gh via brew when absent" {
  make_fake brew
  run_cell gh-auth
  [ "$status" -eq 0 ]
  fake_logged "brew install gh"
}

@test "gh-auth block installs nothing when gh is present" {
  make_fake brew
  make_fake_gh          # gh present -> CHECK passes
  run_cell gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install gh"
  [[ "$output" == *"already installed"* ]]
}

@test "gh-auth apply.sh does not attempt login when already authenticated" {
  make_fake_gh          # auth status -> 0
  run_block gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "gh auth login"
}

@test "gh-auth apply.sh skips login without a terminal when unauthenticated" {
  make_fake_gh_unauth   # auth status -> 1
  run_block gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "gh auth login"
  [[ "$output" == *"Not a terminal"* ]]
}
