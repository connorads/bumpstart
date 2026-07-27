#!/usr/bin/env bats
#
# instructions.sh — the canonical-file assembler + harness symlinker that
# replaced the marker merge. Driven through /bin/bash (via the isolated PATH)
# against temp files in an isolated HOME. Fixtures supply the content.md blocks.

load helpers/common

setup() {
  setup_isolated_env
  # assemble_instructions drops a non-instruction block that does no work on the
  # current OS, and the fixtures' cells are INSTALL_MAC — so the suite means the mac
  # lane. Pinned, not inherited from the host: on Linux the tool sections would
  # silently vanish from the canonical file instead of the test failing.
  export VIBE_OS=mac
  FIX="$REPO_ROOT/tests/fixtures"
  DRIVER="$REPO_ROOT/tests/helpers/instructions_driver.sh"
  CANON="$HOME/.agents/AGENTS.md"
}

assemble() { run bash "$DRIVER" "$REPO_ROOT/lib" assemble "$FIX" "$@"; }
link()     { run bash "$DRIVER" "$REPO_ROOT/lib" link "$@"; }

# --- assemble -----------------------------------------------------------------

@test "assemble stacks sections with no markers or preamble" {
  assemble false concise mise
  [ "$status" -eq 0 ]
  [ -f "$CANON" ]
  grep -Fq "## Be concise" "$CANON"
  grep -Fq "## Tools via mise" "$CANON"
  # no vibe markers, no novice scaffold/preamble
  ! grep -Fq "<!-- vibe" "$CANON"
  ! grep -Fq "coding-agent instructions" "$CANON"
}

@test "instruction sections lead the file, whatever the plan's step order" {
  # mise is a [tool] (kind rank 30), concise an [instructions] block (rank 60), so
  # the plan runs mise first — but the behavioural frame belongs above the
  # reference material, so section order must NOT follow the step order.
  assemble false mise concise
  [ "$status" -eq 0 ]
  cline="$(grep -n -F '## Be concise' "$CANON" | head -1 | cut -d: -f1)"
  mline="$(grep -n -F '## Tools via mise' "$CANON" | head -1 | cut -d: -f1)"
  [ "$cline" -lt "$mline" ]
}

@test "the real welcome block stacks its guidance in plan order (before concise)" {
  run bash "$DRIVER" "$REPO_ROOT/lib" assemble "$REPO_ROOT" false welcome concise
  [ "$status" -eq 0 ]
  grep -Fq "## Working with a beginner" "$CANON"
  wline="$(grep -n -F '## Working with a beginner' "$CANON" | head -1 | cut -d: -f1)"
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

@test "assemble --force rewrites an existing canonical, keeping a .bak of it" {
  mkdir -p "$(dirname "$CANON")"
  printf 'MY OWN NOTES\n' > "$CANON"
  assemble true concise
  [ "$status" -eq 0 ]
  grep -Fq "## Be concise" "$CANON"
  ! grep -Fq "MY OWN NOTES" "$CANON"
  # the gate promises a .bak, so --force must not be a lossy clobber
  [ "$(cat "$CANON.bak")" = "MY OWN NOTES" ]
}

@test "assemble --force twice keeps both backups (timestamp-suffixed)" {
  mkdir -p "$(dirname "$CANON")"
  printf 'MY OWN NOTES\n' > "$CANON"
  assemble true concise
  assemble true mise
  [ "$status" -eq 0 ]
  [ "$(cat "$CANON.bak")" = "MY OWN NOTES" ]
  # the second run's .bak is suffixed rather than overwriting the first
  run bash -c 'ls "$1".bak.* | wc -l' _ "$CANON"
  [ "$output" -ge 1 ]
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
