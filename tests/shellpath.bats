#!/usr/bin/env bats
#
# persist_path (shellpath.sh) — the one edit vibe makes to a file the user owns
# outside its own config paths, so it has to be exact: the right file for the login
# shell, written once, marker-wrapped so it can be removed, and never joined onto a
# line the user wrote. Driven under /bin/bash (3.2) in an isolated HOME.

load helpers/common

setup() {
  setup_isolated_env
  DRIVER="$REPO_ROOT/tests/helpers/shellpath_driver.sh"
}

# persist <login-shell> — run persist_path as if the user logs in with that shell.
persist() { run env SHELL="$1" bash "$DRIVER" "$REPO_ROOT/lib"; }

@test "zsh: writes the marker-wrapped PATH line to ~/.zshrc" {
  persist /bin/zsh
  [ "$status" -eq 0 ]
  rc="$HOME/.zshrc"
  grep -Fxq '# >>> vibe-setup >>>' "$rc"
  grep -Fxq '# <<< vibe-setup <<<' "$rc"
  grep -Fq '$HOME/.local/bin' "$rc"
  grep -Fq 'mise/shims' "$rc"
  [[ "$output" == *"New terminals will find your tools"* ]]
}

@test "zsh honours ZDOTDIR rather than writing a file zsh never reads" {
  export ZDOTDIR="$HOME/zdot"
  mkdir -p "$ZDOTDIR"
  persist /bin/zsh
  [ "$status" -eq 0 ]
  grep -Fxq '# >>> vibe-setup >>>' "$ZDOTDIR/.zshrc"
  [ ! -e "$HOME/.zshrc" ]
}

@test "bash: writes to ~/.bashrc" {
  persist /bin/bash
  [ "$status" -eq 0 ]
  grep -Fq 'export PATH=' "$HOME/.bashrc"
  [ ! -e "$HOME/.zshrc" ]
}

@test "fish: writes fish syntax to config.fish, not an export line" {
  persist /usr/local/bin/fish
  [ "$status" -eq 0 ]
  rc="$HOME/.config/fish/config.fish"
  grep -Fq 'fish_add_path' "$rc"
  # `export PATH=…` is not fish syntax; writing it would break every new shell
  ! grep -Fq 'export PATH=' "$rc"
}

@test "a second run leaves the file byte-identical" {
  persist /bin/zsh
  once="$(cat "$HOME/.zshrc")"
  persist /bin/zsh
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc")" = "$once" ]
  [[ "$output" == *"already knows"* ]]
}

@test "the user's own lines survive, and none of them is joined onto" {
  printf 'alias ll="ls -l"\nexport EDITOR=vim' > "$HOME/.zshrc"   # no trailing newline
  persist /bin/zsh
  [ "$status" -eq 0 ]
  grep -Fxq 'alias ll="ls -l"' "$HOME/.zshrc"
  grep -Fxq 'export EDITOR=vim' "$HOME/.zshrc"
  grep -Fxq '# >>> vibe-setup >>>' "$HOME/.zshrc"
}

@test "an unfamiliar login shell is told the line instead of having a file guessed" {
  persist /usr/bin/ksh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Add this to your shell's startup file"* ]]
  [[ "$output" == *'export PATH='* ]]
  # nothing written anywhere we might have guessed
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -e "$HOME/.config/fish/config.fish" ]
}

@test "the persisted line and fixup_path prepend the same dirs" {
  # If they drift, the run sees a binary the next terminal cannot — the exact
  # failure this whole file exists to prevent.
  persist /bin/bash
  line="$(grep -F 'export PATH=' "$HOME/.bashrc")"
  live="$(run env SHELL=/bin/bash bash -c \
    '. "'"$REPO_ROOT"'/lib/common.sh"; fixup_path; printf "%s" "$PATH"'; printf '%s' "$output")"
  for d in ".local/bin" ".codex/bin" "mise/shims"; do
    [[ "$line" == *"$d"* ]]
    [[ "$live" == *"$d"* ]]
  done
}
