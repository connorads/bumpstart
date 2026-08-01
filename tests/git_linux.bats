#!/usr/bin/env bats
#
# blocks/git/apply.sh on Linux — the one tool with no portable user-space install,
# so the one place a package manager and a sudo password are legitimate. It cannot
# be a cell: run_cell executes cells through spin, which backgrounds the command and
# rewrites the terminal line every 0.1s, erasing a password prompt as it is typed.
#
# The manager is found by capability (is apt-get/dnf/pacman/zypper on PATH), never
# by reading a distro name, so these cases fake each manager in turn and assert the
# right command — which is also the assertion that Mint, Pop!_OS and openSUSE work
# without a row of their own.

load helpers/common

setup() {
  setup_isolated_env
  # Non-root, explicitly: the sudo branch only exists for a non-root user, so
  # inheriting the invoking identity would make these cases vacuous wherever the
  # suite happened to be run as root. The root case overrides this.
  make_fake id 'printf "1000\n"'
}

# A sudo fake that logs and then really runs what it was asked to (so the faked
# package manager is what actually records the install), and answers the tty-gated
# `sudo -v` credential refresh without trying to exec it.
make_fake_sudo() {
  make_fake sudo \
    'if [ "$1" = "-v" ]; then exit 0; fi' \
    'exec "$@"'
}

# apply_git <os> — run the tail with the block contract in the env.
apply_git() {
  run env BUMP_LIB="$REPO_ROOT/lib" BUMP_ROOT="$REPO_ROOT" BUMP_OS="${1:-linux}" \
    BUMP_BLOCK_DIR="$REPO_ROOT/blocks/git" BUMP_BLOCK_ID=git \
    bash "$REPO_ROOT/blocks/git/apply.sh"
}

# apply_git_without_git — the same, with PATH narrowed to the fakes dir ALONE, so
# "git absent" is real rather than shadowed by /usr/bin/git (a fake git would still
# answer `command -v git`). The real binaries the script needs are symlinked in;
# PATH is restored before the assertions, which use grep. Call after the fakes are
# written — make_fake needs chmod.
apply_git_without_git() {
  for _b in env bash id uname cat tr basename dirname mkdir; do
    [ -e "$FAKES/$_b" ] || ln -sf "$(command -v "$_b")" "$FAKES/$_b"
  done
  _wide_path="$PATH"
  PATH="$FAKES" run env BUMP_LIB="$REPO_ROOT/lib" BUMP_ROOT="$REPO_ROOT" BUMP_OS=linux \
    BUMP_BLOCK_DIR="$REPO_ROOT/blocks/git" BUMP_BLOCK_ID=git \
    bash "$REPO_ROOT/blocks/git/apply.sh"
  export PATH="$_wide_path"
}

@test "apt-get: installs git, and narrates the password prompt first" {
  make_fake apt-get
  make_fake_sudo
  apply_git_without_git
  [ "$status" -eq 0 ]
  grep -q "^apt-get install -y -qq git$" "$BUMP_FAKE_LOG"
  # A blank, non-echoing prompt reads as "broken" to a first-timer unless it is
  # named before it fires — the same copy, and the same reason, as lib/brew.sh.
  [[ "$output" == *"Nothing appears as you type"* ]]
}

@test "dnf: installs git" {
  make_fake dnf
  make_fake_sudo
  apply_git_without_git
  [ "$status" -eq 0 ]
  grep -q "^dnf install -y -q git$" "$BUMP_FAKE_LOG"
}

@test "pacman: installs git" {
  make_fake pacman
  make_fake_sudo
  apply_git_without_git
  [ "$status" -eq 0 ]
  grep -q "^pacman -Sy --noconfirm --needed git$" "$BUMP_FAKE_LOG"
}

@test "zypper: installs git" {
  make_fake zypper
  make_fake_sudo
  apply_git_without_git
  [ "$status" -eq 0 ]
  grep -q "^zypper --non-interactive install -y git$" "$BUMP_FAKE_LOG"
}

@test "as root, no sudo is used and none is required" {
  # Containers and Codespaces run as root, where sudo often isn't installed at all.
  make_fake apt-get
  make_fake id 'printf "0\n"'
  apply_git_without_git
  [ "$status" -eq 0 ]
  grep -q "^apt-get install -y -qq git$" "$BUMP_FAKE_LOG"
  refute_fake_logged "sudo"
  [[ "$output" != *"Nothing appears as you type"* ]]
}

@test "no sudo and not root: says so instead of failing with a permission error" {
  make_fake apt-get
  apply_git_without_git
  [ "$status" -eq 0 ]
  [[ "$output" == *"no sudo here"* ]]
  refute_fake_logged "apt-get"
}

@test "no package manager at all: warns and continues, never aborts the setup" {
  make_fake_sudo
  apply_git_without_git
  [ "$status" -eq 0 ]
  [[ "$output" == *"couldn't find a package manager"* ]]
}

@test "git already present: no manager is touched" {
  make_fake git
  make_fake apt-get
  make_fake_gh_unauth
  apply_git linux
  [ "$status" -eq 0 ]
  refute_fake_logged "apt-get"
}

@test "on a Mac the Linux head is skipped entirely" {
  make_fake apt-get
  make_fake git
  make_fake_gh_unauth
  apply_git mac
  [ "$status" -eq 0 ]
  refute_fake_logged "apt-get"
}
