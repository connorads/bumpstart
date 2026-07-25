#!/usr/bin/env bats
#
# common.sh UI helpers. Focus: the spin() passthrough contract in plain mode
# (no UI_FANCY), which every install block now depends on — run the command,
# propagate its exit status, and stream the command's stdout through. Runs under
# the same NO_COLOR + non-tty conditions as the whole suite, so UI_FANCY is
# empty and spin is a transparent passthrough.

load helpers/common

setup() { setup_isolated_env; }

# Source common.sh and invoke spin in a fresh /bin/bash (the support contract):
# $1 = common.sh path (sourced then shifted away), the rest are spin's args.
spin_run() {
  run bash -c '. "$1"; shift; spin "$@"' _ "$REPO_ROOT/lib/common.sh" "$@"
}

@test "spin runs the wrapped command (plain mode)" {
  make_fake brew
  spin_run "Installing brew" brew install something
  [ "$status" -eq 0 ]
  fake_logged "brew install something"
}

@test "spin propagates a zero exit status" {
  spin_run "ok" true
  [ "$status" -eq 0 ]
}

@test "spin propagates a non-zero exit status" {
  spin_run "boom" false
  [ "$status" -eq 1 ]
}

@test "spin streams the command's stdout through" {
  spin_run "print" printf 'hello-from-cmd\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-from-cmd"* ]]
}
