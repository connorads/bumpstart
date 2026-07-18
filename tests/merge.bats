#!/usr/bin/env bats
#
# merge.sh — highest bug density, most investment. Driven through /bin/bash (via
# the isolated PATH) against temp files in an isolated HOME.

load helpers/common

setup() {
  setup_isolated_env
  TARGET="$HOME/.claude/CLAUDE.md"
  mkdir -p "$(dirname "$TARGET")"
  DRIVER="$REPO_ROOT/tests/helpers/merge_driver.sh"
}

merge() { run bash "$DRIVER" "$REPO_ROOT/lib" "$1" "$2" "$3"; }

@test "absent file: seeds the scaffold and appends the managed block" {
  merge concise $'Be concise.\n' "$TARGET"
  [ "$status" -eq 0 ]
  [ -f "$TARGET" ]
  grep -Fq "Your coding-agent instructions" "$TARGET"   # scaffold heading
  grep -Fq "<!-- vibe:concise start -->" "$TARGET"
  grep -Fq "Be concise." "$TARGET"
  grep -Fq "<!-- vibe:concise end -->" "$TARGET"
}

@test "present, no markers: appends and leaves user text byte-identical" {
  printf '# My notes\n\nKeep my stuff.\n' > "$TARGET"
  before="$(cat "$TARGET")"
  merge concise $'Be concise.\n' "$TARGET"
  [ "$status" -eq 0 ]
  # every original line still present, unchanged, and before our block
  grep -Fq "Keep my stuff." "$TARGET"
  head -3 "$TARGET" | grep -Fq "# My notes"
  [ "$(printf '%s\n' "$before" | head -1)" = "$(head -1 "$TARGET")" ]
}

@test "present with markers: replaces only our region" {
  merge concise $'First version.\n' "$TARGET"
  merge concise $'Second version.\n' "$TARGET"
  [ "$status" -eq 0 ]
  grep -Fq "Second version." "$TARGET"
  ! grep -Fq "First version." "$TARGET"
  # exactly one marker pair
  [ "$(grep -cF '<!-- vibe:concise start -->' "$TARGET")" -eq 1 ]
}

@test "corrupt: start marker without end refuses and leaves file untouched" {
  printf '# notes\n<!-- vibe:concise start -->\nstale\n' > "$TARGET"
  before="$(cat "$TARGET")"
  merge concise $'New.\n' "$TARGET"
  [ "$status" -ne 0 ]
  [ "$(cat "$TARGET")" = "$before" ]
}

@test "id with regex metacharacters is treated literally" {
  merge 'a.b+c' $'Hi.\n' "$TARGET"
  [ "$status" -eq 0 ]
  grep -Fq "<!-- vibe:a.b+c start -->" "$TARGET"
  grep -Fq "Hi." "$TARGET"
}

@test "content without a trailing newline still yields a valid block" {
  merge concise 'No newline here' "$TARGET"
  [ "$status" -eq 0 ]
  # end marker sits on its own line, not glued to the content
  grep -Fxq "<!-- vibe:concise end -->" "$TARGET"
  grep -Fxq "No newline here" "$TARGET"
}

@test "two blocks coexist and are independently replaceable" {
  merge concise $'Concise v1.\n' "$TARGET"
  merge tone    $'Be kind.\n'    "$TARGET"
  merge concise $'Concise v2.\n' "$TARGET"
  [ "$status" -eq 0 ]
  grep -Fq "Concise v2." "$TARGET"
  ! grep -Fq "Concise v1." "$TARGET"
  grep -Fq "Be kind." "$TARGET"        # the other block untouched
  [ "$(grep -cF '<!-- vibe:tone start -->' "$TARGET")" -eq 1 ]
}

@test "apply-twice == apply-once (byte-idempotent)" {
  merge concise $'Be concise.\n' "$TARGET"
  once="$(cat "$TARGET")"
  merge concise $'Be concise.\n' "$TARGET"
  twice="$(cat "$TARGET")"
  [ "$once" = "$twice" ]
}
