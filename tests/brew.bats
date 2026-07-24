#!/usr/bin/env bats
#
# ensure_brew (brew.sh) — the install branch narrates the sudo password moment.
# Driven under /bin/bash (3.2) in an isolated HOME with PATH-shadow fakes; the
# prefix probes are pointed at nonexistent paths so the install branch runs
# without a real Homebrew uninstall.

load helpers/common

setup() {
  setup_isolated_env
  DRIVER="$REPO_ROOT/tests/helpers/brew_driver.sh"
  make_fake_curl   # the Homebrew installer URL emits an empty (inert) script
  make_fake sudo   # never invoke real sudo (also: no tty, so sudo -v is skipped)
  export VIBE_BREW_OPT="$BATS_TEST_TMPDIR/nope-opt-brew"
  export VIBE_BREW_USR="$BATS_TEST_TMPDIR/nope-usr-brew"
}

brew_run() { run env VIBE_BREW_OPT="$VIBE_BREW_OPT" VIBE_BREW_USR="$VIBE_BREW_USR" \
  bash "$DRIVER" "$REPO_ROOT/lib"; }

@test "the install branch narrates the invisible-typing sudo prompt" {
  # brew is absent from the isolated PATH and the prefixes don't exist ->
  # the install branch runs. NOTE: the real `sudo -v` is tty-gated, so it is
  # skipped in this non-tty runner; we assert the narration, which is not gated.
  brew_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing appears as you type"* ]]
  [[ "$output" != *"already installed"* ]]
}

@test "brew present on PATH: no install, no narration" {
  make_fake brew
  brew_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [[ "$output" != *"Nothing appears as you type"* ]]
}
