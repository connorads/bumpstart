#!/usr/bin/env bats
#
# ensure_mise (mise.sh) — the Linux install substrate, the mirror of ensure_brew.
# It runs pre-loop and unconditionally because block steps run in KIND rank order:
# `auth` (github, 20) comes before `tool` (mise, 30), so a github cell that uses
# mise would otherwise run before mise existed. Driven under /bin/bash (3.2) in an
# isolated HOME with PATH-shadow fakes; BUMP_MISE_BIN points the already-installed
# probe at a path the test owns, so both branches run without a real install.

load helpers/common

setup() {
  setup_isolated_env
  DRIVER="$REPO_ROOT/tests/helpers/mise_driver.sh"
  make_fake_curl    # the mise.run URL emits a script that records the install
  export BUMP_MISE_BIN="$BATS_TEST_TMPDIR/nope/mise"
}

mise_run() { run env BUMP_MISE_BIN="$BUMP_MISE_BIN" bash "$DRIVER" "$REPO_ROOT/lib"; }

@test "installs mise when it is absent" {
  mise_run
  [ "$status" -eq 0 ]
  fake_logged "INSTALL mise"
  [[ "$output" == *"Installing mise"* ]]
}

@test "the install suppresses mise's own PATH advice" {
  # persist_path owns the rc edit. Two tools both writing it is how a beginner ends
  # up with the line twice, and mise's epilogue would contradict ours.
  mise_run
  [ "$status" -eq 0 ]
  fake_logged "INSTALL mise 0"
}

@test "mise already on PATH: no install, no narration" {
  make_fake mise
  mise_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_fake_logged "INSTALL mise"
}

@test "installed but not yet on PATH: no reinstall, and this run can see it" {
  # The shape of a machine where a previous run installed mise into ~/.local/bin
  # but the shell was never restarted.
  mkdir -p "$(dirname "$BUMP_MISE_BIN")"
  printf '#!/bin/bash\nexit 0\n' > "$BUMP_MISE_BIN"
  chmod +x "$BUMP_MISE_BIN"
  mise_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_fake_logged "INSTALL mise"
  # its dir is prepended for the rest of the run, so a later CHECK cell finds it
  [[ "$output" == *"PATH=$(dirname "$BUMP_MISE_BIN"):"* ]]
}

@test "a failed install warns and is recorded, rather than aborting the setup" {
  make_fake curl 'exit 1'
  make_fake wget 'exit 1'
  mise_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"couldn't install mise"* ]]
}
