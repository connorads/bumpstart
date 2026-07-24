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
  make_fake pbcopy 'cat >> "$VIBE_FAKE_LOG"'  # log copies, spare the real clipboard
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

@test "copy_starter_prompt copies the repo's starter-prompt.txt to the clipboard" {
  trust copy_starter_prompt "$REPO_ROOT"
  [ "$status" -eq 0 ]
  # the file's text reached pbcopy
  fake_logged "build it together"
}

@test "copy_starter_prompt is a no-op when the file is missing" {
  root="$BATS_TEST_TMPDIR/noprompt"
  mkdir -p "$root"
  trust copy_starter_prompt "$root"
  [ "$status" -eq 0 ]
  refute_fake_logged "pbcopy"
}
