#!/usr/bin/env bats
#
# ensure_brew (brew.sh) — the mac install substrate: it narrates the sudo password
# moment, and it is inside the warn-and-record failure policy rather than outside
# it. Driven under /bin/bash (3.2) in an isolated HOME with PATH-shadow fakes; the
# prefix probes are pointed at nonexistent paths so the install branch runs
# without a real Homebrew uninstall.
#
# The `sudo -v` half stays uncovered: bats gives no tty (so the branch is skipped)
# and `script` differs across the four distro legs. A tty seam here would be more
# machinery than the one line is worth.

load helpers/common

setup() {
  setup_isolated_env
  DRIVER="$REPO_ROOT/tests/helpers/brew_driver.sh"
  make_fake_curl   # the Homebrew installer URL emits a script that records the install
  make_fake sudo   # never invoke real sudo (also: no tty, so sudo -v is skipped)
  export BUMP_BREW_OPT="$BATS_TEST_TMPDIR/nope-opt-brew"
  export BUMP_BREW_USR="$BATS_TEST_TMPDIR/nope-usr-brew"
}

brew_run() { run env BUMP_BREW_OPT="$BUMP_BREW_OPT" BUMP_BREW_USR="$BUMP_BREW_USR" \
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

@test "the install actually runs the fetched script, and says so" {
  brew_run
  [ "$status" -eq 0 ]
  fake_logged "INSTALL brew"
  [[ "$output" == *"Homebrew installed"* ]]
}

@test "a failed download warns and is recorded, rather than reporting an install" {
  # `bash -c "$(curl ...)"` hands bash an EMPTY script when the download fails,
  # and bash exits 0 — so the run reported an install that never happened, then
  # every cask step failed for want of brew. The mirror of the mise case.
  make_fake curl 'exit 1'
  make_fake wget 'exit 1'
  brew_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"couldn't install Homebrew"* ]]
  [[ "$output" != *"Homebrew installed"* ]]
}

@test "an empty download is a failure, not an install of nothing" {
  # curl exits 0 with an empty body (a captive portal, a proxy's 200-with-nothing).
  # `bash -c ""` exits 0, which is precisely the silent-success shape.
  make_fake curl   # logs its args, prints nothing, exits 0
  brew_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"couldn't install Homebrew"* ]]
  [[ "$output" != *"Homebrew installed"* ]]
}

@test "ensure_brew always returns 0, so a failure cannot end the setup silently" {
  # It is called bare under the applier's set -e (lib/apply.sh), so the policy has
  # to live here: warn, record, continue — as ensure_mise does on Linux.
  make_fake curl 'exit 1'
  make_fake wget 'exit 1'
  brew_run
  [ "$status" -eq 0 ]
}
