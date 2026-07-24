#!/usr/bin/env bats
#
# instructions.sh — the canonical-file assembler + harness symlinker that
# replaced the marker merge. Driven through /bin/bash (via the isolated PATH)
# against temp files in an isolated HOME. Fixtures supply the content.md blocks.

load helpers/common

setup() {
  setup_isolated_env
  FIX="$REPO_ROOT/tests/fixtures"
  DRIVER="$REPO_ROOT/tests/helpers/instructions_driver.sh"
  CANON="$HOME/.config/agents/AGENTS.md"
}

assemble() { run bash "$DRIVER" "$REPO_ROOT/lib" assemble "$FIX" "$@"; }
link()     { run bash "$DRIVER" "$REPO_ROOT/lib" link "$@"; }

# --- assemble -----------------------------------------------------------------

@test "assemble stacks sections in plan order with no markers or preamble" {
  assemble false concise mise
  [ "$status" -eq 0 ]
  [ -f "$CANON" ]
  grep -Fq "## Be concise" "$CANON"
  grep -Fq "## Tools via mise" "$CANON"
  # no vibe markers, no novice scaffold/preamble
  ! grep -Fq "<!-- vibe" "$CANON"
  ! grep -Fq "coding-agent instructions" "$CANON"
  # concise (first in plan) sits above mise
  cline="$(grep -n -F '## Be concise' "$CANON" | head -1 | cut -d: -f1)"
  mline="$(grep -n -F '## Tools via mise' "$CANON" | head -1 | cut -d: -f1)"
  [ "$cline" -lt "$mline" ]
}

@test "the real welcome block stacks its guidance in plan order (before concise)" {
  run bash "$DRIVER" "$REPO_ROOT/lib" assemble "$REPO_ROOT" false welcome concise
  [ "$status" -eq 0 ]
  grep -Fq "## Welcome" "$CANON"
  wline="$(grep -n -F '## Welcome' "$CANON" | head -1 | cut -d: -f1)"
  cline="$(grep -n -F '## Be concise' "$CANON" | head -1 | cut -d: -f1)"
  [ "$wline" -lt "$cline" ]
}

@test "assemble separates sections with a blank line" {
  assemble false concise mise
  [ "$status" -eq 0 ]
  # the section boundary is a blank line, then the next heading
  run grep -A1 -F -- '- Keep replies short and to the point.' "$CANON"
  [[ "${lines[1]}" == "" ]]
}

@test "assemble honours XDG_CONFIG_HOME" {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"
  assemble false concise
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/agents/AGENTS.md" ]
  grep -Fq "## Be concise" "$XDG_CONFIG_HOME/agents/AGENTS.md"
}

@test "assemble is a no-op when no block ships content.md" {
  assemble false claude
  [ "$status" -eq 0 ]
  [ ! -e "$CANON" ]
}

@test "assemble backs off from an existing canonical (leaves it untouched)" {
  mkdir -p "$(dirname "$CANON")"
  printf 'MY OWN NOTES\n' > "$CANON"
  assemble false concise
  [ "$status" -eq 0 ]
  [ "$(cat "$CANON")" = "MY OWN NOTES" ]
}

@test "assemble --force rewrites an existing canonical" {
  mkdir -p "$(dirname "$CANON")"
  printf 'MY OWN NOTES\n' > "$CANON"
  assemble true concise
  [ "$status" -eq 0 ]
  grep -Fq "## Be concise" "$CANON"
  ! grep -Fq "MY OWN NOTES" "$CANON"
}

# --- link ---------------------------------------------------------------------

@test "link creates a symlink to the canonical when the native path is absent" {
  native="$HOME/.claude/CLAUDE.md"
  link "$native" false
  [ "$status" -eq 0 ]
  [ -L "$native" ]
  [ "$(readlink "$native")" = "$CANON" ]
}

@test "link is idempotent: an existing symlink to canonical is left alone" {
  native="$HOME/.claude/CLAUDE.md"
  link "$native" false
  link "$native" false
  [ "$status" -eq 0 ]
  [ -L "$native" ]
  [ "$(readlink "$native")" = "$CANON" ]
  [ ! -e "$native.bak" ]
}

@test "link backs off from a real native file (untouched, no backup) without force" {
  native="$HOME/.claude/CLAUDE.md"
  mkdir -p "$(dirname "$native")"
  printf 'REAL USER FILE\n' > "$native"
  link "$native" false
  [ "$status" -eq 0 ]
  [ ! -L "$native" ]
  [ "$(cat "$native")" = "REAL USER FILE" ]
  [ ! -e "$native.bak" ]
}

@test "link --force backs a real native file up to .bak then symlinks" {
  native="$HOME/.claude/CLAUDE.md"
  mkdir -p "$(dirname "$native")"
  printf 'REAL USER FILE\n' > "$native"
  link "$native" true
  [ "$status" -eq 0 ]
  [ -L "$native" ]
  [ "$(readlink "$native")" = "$CANON" ]
  [ "$(cat "$native.bak")" = "REAL USER FILE" ]
}
