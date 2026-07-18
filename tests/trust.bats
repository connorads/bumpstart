#!/usr/bin/env bats
#
# trust.sh — starter dir + best-effort trust preseed. Asserts the exact config
# written, driven under /bin/bash (3.2) in an isolated HOME.

load helpers/common

setup() {
  setup_isolated_env
  DRIVER="$REPO_ROOT/tests/helpers/trust_driver.sh"
  DIR="$HOME/code/first-project"
  mkdir -p "$DIR"
}

trust() { run bash "$DRIVER" "$REPO_ROOT/lib" "$@"; }

@test "ensure_starter_dir creates the dir and echoes its realpath" {
  rm -rf "$DIR"
  trust ensure_starter_dir
  [ "$status" -eq 0 ]
  [ -d "$DIR" ]
  # pwd -P output ends with the starter path
  [[ "$output" == *"/code/first-project" ]]
}

@test "codex preseed writes a trusted project section" {
  trust preseed_codex_trust "$DIR"
  [ "$status" -eq 0 ]
  cfg="$HOME/.codex/config.toml"
  grep -Fq "[projects.\"$DIR\"]" "$cfg"
  grep -Fq 'trust_level = "trusted"' "$cfg"
}

@test "codex preseed is idempotent (one section after two runs)" {
  trust preseed_codex_trust "$DIR"
  trust preseed_codex_trust "$DIR"
  [ "$status" -eq 0 ]
  cfg="$HOME/.codex/config.toml"
  [ "$(grep -cF "[projects.\"$DIR\"]" "$cfg")" -eq 1 ]
}

@test "claude preseed seeds onboarding + trust when config is absent" {
  trust preseed_claude_trust "$DIR"
  [ "$status" -eq 0 ]
  json="$HOME/.claude.json"
  grep -Fq '"hasCompletedOnboarding": true' "$json"
  grep -Fq '"hasTrustDialogAccepted": true' "$json"
  grep -Fq "\"$DIR\"" "$json"
}

@test "claude preseed does not clobber an existing config" {
  json="$HOME/.claude.json"
  printf '{"mine":true}\n' > "$json"
  trust preseed_claude_trust "$DIR"
  [ "$status" -eq 0 ]
  [ "$(cat "$json")" = '{"mine":true}' ]
}

@test "preseed_trust dispatches by harness (codex)" {
  trust preseed_trust codex "$DIR"
  [ "$status" -eq 0 ]
  grep -Fq 'trust_level = "trusted"' "$HOME/.codex/config.toml"
}
