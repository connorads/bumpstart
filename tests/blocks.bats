#!/usr/bin/env bats
#
# Block apply.sh adapters, driven directly with the block contract in the env.
# Check-then-act: sentinel present -> nothing; absent -> installer once.
# VIBE_DESKTOP=false keeps these to the CLI path (no cask / /Applications).

load helpers/common

setup() { setup_isolated_env; }

run_block() {
  id="$1"; shift
  run env VIBE_LIB="$REPO_ROOT/lib" VIBE_ROOT="$REPO_ROOT" \
    VIBE_BLOCK_DIR="$REPO_ROOT/blocks/$id" VIBE_BLOCK_ID="$id" \
    VIBE_TARGETS="${VIBE_TARGETS:-}" VIBE_DESKTOP=false \
    bash "$REPO_ROOT/blocks/$id/apply.sh" "$@"
}

@test "claude block installs the CLI once when absent" {
  make_fake_curl
  run_block claude
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL claude' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "claude block installs nothing when the CLI is present" {
  make_fake_curl
  make_fake claude
  run_block claude
  [ "$status" -eq 0 ]
  refute_fake_logged "INSTALL claude"
  [[ "$output" == *"already installed"* ]]
}

@test "codex block installs the CLI once when absent" {
  make_fake_curl
  run_block codex
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL codex' "$VIBE_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "mise block merges its guidance into the instruction target" {
  make_fake mise
  export VIBE_TARGETS="$HOME/.claude/CLAUDE.md"
  run_block mise
  [ "$status" -eq 0 ]
  grep -Fq "<!-- vibe:mise start -->" "$HOME/.claude/CLAUDE.md"
}

@test "node block merges its guidance into the instruction target" {
  make_fake node
  export VIBE_TARGETS="$HOME/.claude/CLAUDE.md"
  run_block node
  [ "$status" -eq 0 ]
  grep -Fq "<!-- vibe:node start -->" "$HOME/.claude/CLAUDE.md"
}

@test "pnpm block installs via mise when absent" {
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi'
  export VIBE_TARGETS="$HOME/.claude/CLAUDE.md"
  run_block pnpm
  [ "$status" -eq 0 ]
  fake_logged "mise use -g pnpm"
}

@test "pnpm block merges its guidance into the instruction target" {
  make_fake pnpm
  export VIBE_TARGETS="$HOME/.claude/CLAUDE.md"
  run_block pnpm
  [ "$status" -eq 0 ]
  grep -Fq "<!-- vibe:pnpm start -->" "$HOME/.claude/CLAUDE.md"
}

@test "gh-auth block installs gh via brew when absent" {
  make_fake brew
  run_block gh-auth
  [ "$status" -eq 0 ]
  fake_logged "brew install gh"
}

@test "gh-auth block does not attempt login when already authenticated" {
  make_fake brew
  make_fake_gh          # auth status -> 0
  run_block gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "gh auth login"
  [[ "$output" == *"already installed"* ]]
}

@test "gh-auth block skips login without a terminal when unauthenticated" {
  make_fake brew
  make_fake_gh_unauth   # auth status -> 1
  run_block gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "gh auth login"
  [[ "$output" == *"Not a terminal"* ]]
}
