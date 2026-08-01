#!/usr/bin/env bats
#
# Declarative install blocks, driven through the generic runner (run_cell) with
# the block contract in the env. Check-then-act: sentinel present -> "already
# installed"; absent -> the INSTALL_<os> cell runs once. The harness (*-cli) and
# app (*-desktop) blocks are separate; BUMP_APPS_DIR points the app blocks' check
# at an empty dir so the cask install path is reachable without the real app
# present. Escape-hatch blocks (gh-auth) split: run_cell installs, the trimmed
# apply.sh owns the interactive login tail.

load helpers/common

setup() {
  setup_isolated_env
  export BUMP_APPS_DIR="$BATS_TEST_TMPDIR/apps"
  mkdir -p "$BUMP_APPS_DIR"
}

# run_cell <id> — drive the generic runner's declarative install for a block's MAC
# cells. BUMP_OS is pinned rather than inherited: run on Linux, these cases would
# read the LINUX cells and quietly assert nothing about the mac lane.
run_cell() {
  run env BUMP_OS=mac BUMP_APPS_DIR="$BUMP_APPS_DIR" \
    bash "$REPO_ROOT/tests/helpers/run_driver.sh" \
    "$REPO_ROOT/lib" run_cell "$REPO_ROOT" "$1"
}

# run_cell_linux <id> — the same, with the LINUX cells selected. BUMP_OS is the
# cross-spine seam, so this asserts the real Linux data on any host. bump_fetch is
# exported because the applier exports it before the block loop and the Linux
# install cells call it.
run_cell_linux() {
  run env BUMP_OS=linux BUMP_APPS_DIR="$BUMP_APPS_DIR" \
    bash "$REPO_ROOT/tests/helpers/run_driver.sh" \
    "$REPO_ROOT/lib" run_cell "$REPO_ROOT" "$1"
}

# run_block <id> — drive a block's interactive apply.sh tail directly.
run_block() {
  id="$1"; shift
  run env BUMP_LIB="$REPO_ROOT/lib" BUMP_ROOT="$REPO_ROOT" \
    BUMP_BLOCK_DIR="$REPO_ROOT/blocks/$id" BUMP_BLOCK_ID="$id" \
    bash "$REPO_ROOT/blocks/$id/apply.sh" "$@"
}

@test "claude-cli block installs the CLI once when absent" {
  make_fake_curl
  run_cell claude-cli
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL claude' "$BUMP_FAKE_LOG")"
  [ "$count" -eq 1 ]
  # the CLI harness never touches the cask
  refute_fake_logged "brew install --cask claude"
}

@test "claude-cli block installs nothing when the CLI is present" {
  make_fake_curl
  make_fake claude
  run_cell claude-cli
  [ "$status" -eq 0 ]
  refute_fake_logged "INSTALL claude"
  [[ "$output" == *"already installed"* ]]
}

@test "claude-desktop block installs the cask once when the app is absent" {
  make_fake brew
  run_cell claude-desktop
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'brew install --cask claude' "$BUMP_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "claude-desktop block installs nothing when the app is present" {
  make_fake brew
  mkdir -p "$BUMP_APPS_DIR/Claude.app"
  run_cell claude-desktop
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install --cask claude"
  [[ "$output" == *"already installed"* ]]
}

@test "codex-cli block installs the CLI once when absent" {
  make_fake_curl
  run_cell codex-cli
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL codex' "$BUMP_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "codex-cli tells the installer not to prompt" {
  # Codex's installer prompts on /dev/tty, which bypasses spin's log redirect: the
  # question is written over the spinner and a keystroke meant for the setup can be
  # eaten by it. CODEX_NON_INTERACTIVE has to reach `sh`, not `curl`, or it is inert.
  make_fake_curl
  run_cell codex-cli
  [ "$status" -eq 0 ]
  fake_logged "INSTALL codex 1"
}

@test "codex-desktop block installs the ChatGPT cask once when the app is absent" {
  make_fake brew
  run_cell codex-desktop
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'brew install --cask chatgpt' "$BUMP_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "github-desktop block installs the cask once when the app is absent" {
  make_fake brew
  run_cell github-desktop
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'brew install --cask github' "$BUMP_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "github-desktop block installs nothing when the app is present" {
  make_fake brew
  mkdir -p "$BUMP_APPS_DIR/GitHub Desktop.app"
  run_cell github-desktop
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install --cask github"
  [[ "$output" == *"already installed"* ]]
}

@test "mise block installs via brew when absent" {
  make_fake brew
  run_cell mise
  [ "$status" -eq 0 ]
  fake_logged "brew install mise"
}

@test "mise block installs nothing when mise is present" {
  make_fake mise
  run_cell mise
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "node block installs via mise when absent, from the home dir" {
  # `mise use -g` writes the GLOBAL config, but it still reads the cwd's mise.toml
  # first and aborts outright when that file is untrusted — verified live: a config
  # carrying [env] or [tasks] fails the whole command, writing nothing. Anyone who
  # runs the setup from inside a checkout (this repo included) would hit it, so the
  # cell moves to $HOME before installing.
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi' \
    'printf "CWD %s\n" "$PWD" >> "$BUMP_FAKE_LOG"'
  run_cell node
  [ "$status" -eq 0 ]
  fake_logged "mise use -g node@lts"
  fake_logged "CWD $HOME"
}

@test "pnpm block installs via mise when absent, from the home dir" {
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi' \
    'printf "CWD %s\n" "$PWD" >> "$BUMP_FAKE_LOG"'
  run_cell pnpm
  [ "$status" -eq 0 ]
  fake_logged "mise use -g pnpm"
  fake_logged "CWD $HOME"
}

@test "gh-auth block installs gh via brew when absent" {
  make_fake brew
  run_cell gh-auth
  [ "$status" -eq 0 ]
  fake_logged "brew install gh"
}

@test "gh-auth block installs nothing when gh is present" {
  make_fake brew
  make_fake_gh          # gh present -> CHECK passes
  run_cell gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install gh"
  [[ "$output" == *"already installed"* ]]
}

# ── The Linux cells ───────────────────────────────────────────────────────────
#
# Same blocks, same runner, BUMP_OS=linux. Vendor one-liners rather than a package
# manager, so no leg of this depends on which distro the test host is: both agent
# vendors resolve arch and libc themselves, and mise supplies gh/node/pnpm.

@test "claude-cli installs via the vendor's Linux one-liner" {
  make_fake_curl
  run_cell_linux claude-cli
  [ "$status" -eq 0 ]
  count="$(grep -c -F 'INSTALL claude' "$BUMP_FAKE_LOG")"
  [ "$count" -eq 1 ]
}

@test "claude-cli on Linux fetches with wget when curl is absent" {
  # The Ubuntu Desktop case: wget present, curl not. A curl-only cell would be a
  # silent no-op on the machine this lane most needs to work.
  make_fake wget 'printf "%s\n" "printf \"INSTALL claude\\n\" >> \"$BUMP_FAKE_LOG\""'
  # PATH is narrowed to the fakes dir ALONE, with only what the cell needs symlinked
  # in. Leaving a system bin dir on PATH would let a real curl answer — and on Fedora
  # and Arch /bin IS /usr/bin, so "curl absent" would be false and the cell would
  # make a real network call.
  ln -sf /bin/bash "$FAKES/bash"
  ln -sf "$(command -v env)" "$FAKES/env"
  _wide_path="$PATH"
  PATH="$FAKES" run env BUMP_OS=linux \
    bash "$REPO_ROOT/tests/helpers/run_driver.sh" \
    "$REPO_ROOT/lib" run_cell "$REPO_ROOT" claude-cli
  export PATH="$_wide_path"
  [ "$status" -eq 0 ]
  fake_logged "INSTALL claude"
}

@test "codex-cli installs via the vendor's Linux one-liner, non-interactively" {
  make_fake_curl
  run_cell_linux codex-cli
  [ "$status" -eq 0 ]
  fake_logged "INSTALL codex 1"
}

@test "mise installs itself on Linux (no Homebrew involved)" {
  make_fake_curl
  make_fake brew
  run_cell_linux mise
  [ "$status" -eq 0 ]
  fake_logged "INSTALL mise"
  refute_fake_logged "brew install mise"
}

@test "gh-auth installs gh via mise on Linux, from the home dir" {
  # A statically linked Go binary on every target, which deletes the signed-repo
  # keyring dance rather than expressing it per distro.
  make_fake brew
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi' \
    'printf "CWD %s\n" "$PWD" >> "$BUMP_FAKE_LOG"'
  run_cell_linux gh-auth
  [ "$status" -eq 0 ]
  fake_logged "mise use -g gh"
  fake_logged "CWD $HOME"
  refute_fake_logged "brew install gh"
}

@test "node installs via mise on Linux" {
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi'
  run_cell_linux node
  [ "$status" -eq 0 ]
  fake_logged "mise use -g node@lts"
}

@test "node on Linux rejects a Windows node leaking in through WSL's PATH" {
  # WSL appends the Windows PATH, so a Windows node is findable AND runnable — a
  # plain `command -v` would report this step satisfied and the agent then fails on
  # it. A real /mnt/c cannot be created on the test host, so the cell is asked
  # directly: a function named `command` beats the builtin in bash's lookup order,
  # which lets the predicate be told what it found.
  cell="$(bash -c '. "'"$REPO_ROOT"'/lib/meta.sh"; meta_get "'"$REPO_ROOT"'/blocks/node" CHECK_LINUX')"
  ask() {
    run bash -c 'p="$2"; command() { printf "%s\n" "$p"; }
      if eval "$1"; then echo SATISFIED; else echo NOT; fi' _ "$cell" "$1"
  }
  ask "/mnt/c/Program Files/nodejs/node"
  [ "$output" = NOT ]
  ask "/mnt/d/nodejs/node"          # not only the C: drive
  [ "$output" = NOT ]
  ask "/usr/bin/node"               # a real Linux node still satisfies it
  [ "$output" = SATISFIED ]
}

@test "pnpm installs via mise on Linux" {
  make_fake mise 'if [ "$1" = "which" ]; then exit 1; fi'
  run_cell_linux pnpm
  [ "$status" -eq 0 ]
  fake_logged "mise use -g pnpm"
}

@test "the desktop app blocks are silent on Linux, not broken" {
  # No official Linux build exists for the ChatGPT app or GitHub Desktop, so they
  # carry no Linux cell: _block_runs drops the row and its guidance rather than
  # pointing a beginner at an unvetted community rebuild.
  make_fake brew
  run_cell_linux codex-desktop
  [ "$status" -eq 0 ]
  refute_fake_logged "brew"
  [ -z "$output" ]
  run_cell_linux github-desktop
  [ "$status" -eq 0 ]
  refute_fake_logged "brew"
  [ -z "$output" ]
}

@test "gh-auth apply.sh does not attempt login when already authenticated" {
  make_fake_gh          # auth status -> 0
  run_block gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "gh auth login"
}

@test "gh-auth apply.sh skips login without a terminal when unauthenticated" {
  make_fake_gh_unauth   # auth status -> 1
  run_block gh-auth
  [ "$status" -eq 0 ]
  refute_fake_logged "gh auth login"
  [[ "$output" == *"Not a terminal"* ]]
}
