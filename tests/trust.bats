#!/usr/bin/env bats
#
# trust.sh — starter dir + best-effort trust preseed. Asserts the exact config
# written, driven under /bin/bash (3.2) in an isolated HOME.

load helpers/common

setup() {
  setup_isolated_env
  DRIVER="$REPO_ROOT/tests/helpers/trust_driver.sh"
  DIR="$HOME/git/first-project"
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
  [[ "$output" == *"/git/first-project" ]]
}

@test "init_starter_repo makes the dir a git repo, and is a no-op the second time" {
  [ -d "$DIR/.git" ] && rm -rf "$DIR/.git"
  trust init_starter_repo "$DIR"
  [ "$status" -eq 0 ]
  [ -d "$DIR/.git" ]
  [[ "$output" == *"git project"* ]]
  # second call sees the existing .git and does nothing (no success line)
  trust init_starter_repo "$DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"git project"* ]]
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

@test "the starter message is also written to a file, always" {
  # A clipboard survives the browser sign-in but not a reboot, a second terminal, or
  # a clipboard manager that drops it.
  trust copy_starter_prompt "$REPO_ROOT"
  [ "$status" -eq 0 ]
  grep -Fq "build it together" "$DIR/first-message.txt"
}

@test "WSL 2 reaches the Windows clipboard via clip.exe" {
  make_fake pbcopy 'exit 1'   # present but broken: the chain must fall through
  make_fake clip.exe 'cat >> "$VIBE_FAKE_LOG"'
  export VIBE_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '5.15.153.1-microsoft-standard-WSL2\n' > "$VIBE_OSRELEASE_FILE"
  trust copy_starter_prompt "$REPO_ROOT"
  [ "$status" -eq 0 ]
  fake_logged "build it together"
}

@test "Wayland uses wl-copy; X11 falls back to xclip" {
  make_fake pbcopy 'exit 1'
  make_fake wl-copy 'cat >> "$VIBE_FAKE_LOG"'
  trust copy_starter_prompt "$REPO_ROOT"
  [ "$status" -eq 0 ]
  fake_logged "wl-copy"

  make_fake wl-copy 'exit 1'
  : > "$VIBE_FAKE_LOG"
  make_fake xclip 'cat >> "$VIBE_FAKE_LOG"'
  trust copy_starter_prompt "$REPO_ROOT"
  [ "$status" -eq 0 ]
  fake_logged "xclip -selection clipboard"
}

@test "with no clipboard tool it names the file, instead of printing text that gets wiped" {
  # The bug this replaces: the old fallback printed the message and the applier then
  # exec'd the agent, whose full-screen TUI wiped the scrollback — so the text the
  # novice was told to copy was gone before they could.
  make_fake pbcopy 'exit 1'
  trust copy_starter_prompt "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first-message.txt"* ]]
  grep -Fq "build it together" "$DIR/first-message.txt"
}

@test "the paste keystroke matches the platform" {
  # Naming the wrong key is worse than naming none: they press it, nothing happens,
  # and they conclude the message was never copied.
  run env VIBE_OS=mac bash "$DRIVER" "$REPO_ROOT/lib" paste_key
  [ "$output" = "Cmd+V" ]
  run env VIBE_OS=linux bash "$DRIVER" "$REPO_ROOT/lib" paste_key
  # VTE terminals and Windows Terminal agree on this, so WSL needs no branch
  [ "$output" = "Ctrl+Shift+V" ]
}
