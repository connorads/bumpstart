#!/usr/bin/env bats
# bats file_tags=integration
#
# Applier end-to-end with everything faked. Exercises composition, instructions
# landing where each agent actually reads them, idempotence, and plan-time
# failure. Targets lib/apply.sh directly — the `vibe` bootstrap's network fetch
# is covered by a manual VM smoke, not here.

load helpers/common

setup() {
  setup_isolated_env
  make_fake brew
  make_fake_curl
  make_fake_gh
  make_fake claude
  make_fake codex
  make_fake mise
  make_fake node
  # Log what gets copied instead of touching the real clipboard.
  make_fake pbcopy 'cat >> "$VIBE_FAKE_LOG"'
  # Point the *-desktop app checks at an empty dir so the cask install path is
  # reachable regardless of what is installed on the machine running the tests.
  export VIBE_APPS_DIR="$BATS_TEST_TMPDIR/apps"
  mkdir -p "$VIBE_APPS_DIR"
}

apply() { run bash "$REPO_ROOT/lib/apply.sh" "$@"; }

@test "vibe claude codex: installs both, launches the last (codex)" {
  apply claude codex --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  [[ "$output" == *"Setup complete"* ]]
}

@test "the claude bundle installs the desktop cask; claude-cli does not" {
  # the bundle pulls in claude-desktop, which installs the cask (app dir empty)
  apply claude --yes --no-launch
  [ "$status" -eq 0 ]
  fake_logged "brew install --cask claude"
  # CLI-only: no app block, so the cask is never touched
  : > "$VIBE_FAKE_LOG"
  apply claude-cli --yes --no-launch
  [ "$status" -eq 0 ]
  refute_fake_logged "brew install --cask claude"
}

@test "instructions land in the canonical file; Claude's path links to it" {
  apply claude concise --yes --no-launch
  [ "$status" -eq 0 ]
  canon="$HOME/.agents/AGENTS.md"
  grep -Fq "## Be concise" "$canon"
  ! grep -Fq "<!-- vibe" "$canon"
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$canon" ]
}

@test "Codex's path links to the same canonical file" {
  apply codex concise --yes --no-launch
  [ "$status" -eq 0 ]
  canon="$HOME/.agents/AGENTS.md"
  grep -Fq "## Be concise" "$canon"
  [ -L "$HOME/.codex/AGENTS.md" ]
  [ "$(readlink "$HOME/.codex/AGENTS.md")" = "$canon" ]
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
}

@test "a tool block's guidance lands in the canonical file" {
  apply claude node --yes --no-launch
  [ "$status" -eq 0 ]
  canon="$HOME/.agents/AGENTS.md"
  grep -Fq "## Node.js" "$canon"
  grep -Fq "## Installing tools (mise)" "$canon"
  [ -L "$HOME/.claude/CLAUDE.md" ]
}

@test "second run leaves the canonical byte-identical and the link intact" {
  apply claude concise --yes --no-launch
  canon="$HOME/.agents/AGENTS.md"
  once="$(cat "$canon")"
  apply claude concise --yes --no-launch
  [ "$status" -eq 0 ]
  twice="$(cat "$canon")"
  [ "$once" = "$twice" ]
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$canon" ]
  [[ "$output" == *"already installed"* ]]
}

@test "codex run pre-trusts the starter dir in ~/.codex/config.toml" {
  apply codex --yes --no-launch
  [ "$status" -eq 0 ]
  starter="$(cd "$HOME/git/first-project" && pwd -P)"
  grep -Fq "[projects.\"$starter\"]" "$HOME/.codex/config.toml"
  grep -Fq 'trust_level = "trusted"' "$HOME/.codex/config.toml"
}

@test "claude starter applies the whole stack for Claude" {
  apply claude starter --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: claude"* ]]
  # node (via mise dep) is in the plan, and instructions land in the canonical file
  [[ "$output" == *"Node.js"* ]]
  grep -Fq "## Be concise" "$HOME/.agents/AGENTS.md"
  # the git block is in the plan, so the starter dir is a real git repo
  [ -d "$HOME/git/first-project/.git" ]
}

@test "codex starter is the same handout on the other agent, with no claude block" {
  apply codex starter --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  # the same stack + habits land...
  [[ "$output" == *"Node.js"* ]]
  grep -Fq "## Be concise" "$HOME/.agents/AGENTS.md"
  [ -d "$HOME/git/first-project/.git" ]
  # ...and nothing Claude is installed or linked: the agent axis is the only
  # thing the id swap changed
  refute_fake_logged "brew install --cask claude"
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
}

@test "claude codex starter installs both agents and launches codex" {
  apply claude codex starter --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  canon="$HOME/.agents/AGENTS.md"
  # both harnesses are present, so both native paths link at the one canonical file
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$canon" ]
  [ "$(readlink "$HOME/.codex/AGENTS.md")" = "$canon" ]
}

@test "codex web is the stack without the beginner habits" {
  apply codex web --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  [[ "$output" == *"Node.js"* ]]
  # the stack ships no instruction blocks, so the tools axis stays steering-free
  canon="$HOME/.agents/AGENTS.md"
  ! grep -Fq "## Working with a beginner" "$canon"
  ! grep -Fq "## Be concise" "$canon"
  ! grep -Fq "## Check it works" "$canon"
  ! grep -Fq "## Keys and passwords" "$canon"
}

@test "a claude-only run (no git block) leaves the starter dir un-versioned" {
  apply claude --yes --no-launch
  [ "$status" -eq 0 ]
  [ -d "$HOME/git/first-project" ]
  [ ! -d "$HOME/git/first-project/.git" ]
}

@test "bare paste (no ids) defaults to the full 'claude starter' setup" {
  apply --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: claude"* ]]
  [[ "$output" == *"Node.js"* ]]
  [[ "$output" == *"Setup complete"* ]]
  # not the old bare-agent error path
  [[ "$output" != *"no blocks requested"* ]]
  grep -Fq "## Be concise" "$HOME/.agents/AGENTS.md"
}

@test "the beginner habits all land in the canonical file" {
  apply claude starter --yes --no-launch
  [ "$status" -eq 0 ]
  canon="$HOME/.agents/AGENTS.md"
  grep -Fq "## Working with a beginner" "$canon"
  grep -Fq "## Be concise" "$canon"
  grep -Fq "## Ask first" "$canon"
  grep -Fq "## Check it works" "$canon"
  grep -Fq "## Keys and passwords" "$canon"
}

@test "claude web dev lands the dev habits and not the beginner welcome" {
  apply claude web dev --yes --no-launch
  [ "$status" -eq 0 ]
  canon="$HOME/.agents/AGENTS.md"
  # the safety habits dev shares with beginner...
  grep -Fq "## Ask first" "$canon"
  grep -Fq "## Check it works" "$canon"
  grep -Fq "## Keys and passwords" "$canon"
  # ...plus the four that only matter once you're writing real code
  grep -Fq "## Check, don't recall" "$canon"
  grep -Fq "## Commit as you go" "$canon"
  grep -Fq "## Match the codebase" "$canon"
  grep -Fq "## Write down what you learned" "$canon"
  # dev drops welcome: it exists to explain the basics
  ! grep -Fq "## Working with a beginner" "$canon"
}

@test "an agent id appended to a preset adds a harness and moves the launcher" {
  apply claude starter codex --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent to launch: codex"* ]]
  # the appended agent is added, not swapped in — claude is still installed
  fake_logged "brew install --cask claude"
}

@test "non-macOS exits 0 with an honest redirect, before any effect" {
  make_fake uname 'printf "Linux\n"'
  apply claude --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"This is the macOS setup"* ]]
  # a Linux reader is told where they stand, not left guessing
  [[ "$output" == *"Linux is not supported yet"* ]]
  # guard fires before ensure_brew / any block, so nothing ran
  refute_fake_logged "brew"
  refute_fake_logged "claude"
}

@test "the plain confirm omits the instruction-file paths but keeps expectations" {
  apply claude concise --yes --no-launch
  [ "$status" -eq 0 ]
  # author/debug detail, hidden from the novice confirm (present only in --plan)
  [[ "$output" != *"Instructions file:"* ]]
  [[ "$output" == *"What will happen"* ]]
}

@test "a satisfied step is dimmed and tagged already-set-up at the gate" {
  # claude is faked present on PATH, so the [harness] step reads as done
  apply claude-cli --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"already set up"* ]]
  # every mapped step of a cli-only plan is satisfied, so the reassurance fires
  [[ "$output" == *"Everything installable is already in place"* ]]
}

@test "the instructions back-off is disclosed on a re-run" {
  apply claude concise --yes --no-launch
  [ "$status" -eq 0 ]
  # second run: the canonical file exists, so vibe backs off and says so
  apply claude concise --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaves it as-is"* ]]
  # the pure [instructions] rows tag the skip too, so the row and the bullet agree
  [[ "$output" == *"skipped (file exists)"* ]]
}

@test "a re-run tags a tool row whose guidance won't be merged" {
  apply claude node --yes --no-launch
  [ "$status" -eq 0 ]
  # first run merges node's + mise's guidance, so nothing is skipped yet
  [[ "$output" != *"guidance skipped"* ]]
  # second run: node is installed AND its guidance won't be merged. A bare
  # "already set up" would claim the whole row landed, guidance included.
  apply claude node --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"guidance skipped"* ]]
  [[ "$output" == *"already set up"* ]]
}

@test "the Claude trust back-off is disclosed when a config already exists" {
  : > "$HOME/.claude.json"
  apply claude --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"won't change its trust settings"* ]]
}

@test "the git-config heads-up shows only when the git block is in the plan" {
  # the plain confirm view (shown even with --yes) discloses the git identity write
  apply claude starter --yes --no-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"default branch for new projects"* ]]
  # a claude-only run has no git block, so no git heads-up
  apply claude --yes --no-launch
  [[ "$output" != *"default branch for new projects"* ]]
}

@test "github-desktop pulls in git and discloses its own GitHub sign-in" {
  apply claude github-desktop --plan
  [ "$status" -eq 0 ]
  # the GUI is useless on a non-repo, so the block pulls git (and so gh-auth) in
  [[ "$output" == *"name, email, and default branch"* ]]
  # two credential stores, two sign-ins — the second is disclosed, not hidden
  [[ "$output" == *"GitHub Desktop asks for its own GitHub sign-in"* ]]
  # a plan without the app makes no such promise
  apply claude starter --plan
  [[ "$output" != *"GitHub Desktop asks"* ]]
}

@test "full mode names the .gitconfig path when git is in the plan" {
  apply claude starter --plan
  [ "$status" -eq 0 ]
  [[ "$output" == *".gitconfig"* ]]
}

@test "the starter prompt is copied to the clipboard with paste guidance" {
  apply claude --yes --no-launch
  [ "$status" -eq 0 ]
  # a distinctive phrase from starter-prompt.txt reached pbcopy
  fake_logged "build it together"
  # and the novice is told how to paste it
  [[ "$output" == *"Cmd+V"* ]]
}

@test "unknown id fails at plan time and applies nothing" {
  apply bogus --yes --no-launch
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown block: bogus"* ]]
  [ ! -f "$HOME/.claude/CLAUDE.md" ]
}
