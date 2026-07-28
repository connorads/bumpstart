#!/usr/bin/env bats
#
# The lane matrix is DATA, read by the local runner, the local driver and CI. This is
# the one place that turns a row into values, so it is the one place that can refuse
# a malformed one.
#
# The case that earns the file, verified rather than assumed:
#
#   $ printf 'a\tb\t\td\n' | { IFS=$'\t' read -r w x y z; echo "$w $x $y $z"; }
#   a b d
#
# Tab is IFS whitespace, so `read` collapses a `\t\t` run and every later field
# shifts left. An empty `deps` cell put the paste ids in the deps column, and
# guests/container.sh executed them as a root provisioning command - reported as
# class 2, "infrastructure", indefinitely. "Spell every empty cell -" was a
# convention nothing enforced.

load helpers/common

setup() {
  # shellcheck source=tests/real/lib/lanes.sh
  . "$REPO_ROOT/tests/real/lib/lanes.sh"
  TSV="$BATS_TEST_TMPDIR/lanes.tsv"
  printf 'lane\tadapter\timage\taxis\tentry\tpaste\tdeps\n' > "$TSV"
}

# row <cells...> — append one tab-separated row.
row() {
  local out=""
  for c in "$@"; do out="$out$c$(printf '\t')"; done
  printf '%s\n' "${out%$(printf '\t')}" >> "$TSV"
}

@test "a well-formed row yields every column, spaces and all" {
  row ubuntu-base container ubuntu:24.04 base apply 'claude starter' 'apt-get update && apt-get install -y git'
  run lane_row "$TSV" ubuntu-base
  [ "$status" -eq 0 ] || { echo "$LANE_ERROR"; false; }
  lane_row "$TSV" ubuntu-base
  [ "$LANE_ADAPTER" = container ] || { echo "adapter [$LANE_ADAPTER]"; false; }
  [ "$LANE_IMAGE" = "ubuntu:24.04" ] || { echo "image [$LANE_IMAGE]"; false; }
  [ "$LANE_AXIS" = base ] || { echo "axis [$LANE_AXIS]"; false; }
  [ "$LANE_ENTRY" = apply ] || { echo "entry [$LANE_ENTRY]"; false; }
  [ "$LANE_PASTE" = "claude starter" ] || { echo "paste [$LANE_PASTE]"; false; }
  [ "$LANE_DEPS" = "apt-get update && apt-get install -y git" ] || { echo "deps [$LANE_DEPS]"; false; }
}

@test "an empty cell is refused rather than shifting every later column" {
  # THE bug. With `IFS=$'\t' read` this row put 'claude starter' in DEPS, and the
  # container adapter ran it as `{ claude starter ; }` under root.
  row ubuntu-base container ubuntu:24.04 base apply '' 'claude starter'
  run lane_row "$TSV" ubuntu-base
  [ "$status" -ne 0 ] || { echo "a blank cell was accepted"; false; }
  lane_row "$TSV" ubuntu-base || true
  printf '%s\n' "$LANE_ERROR" | grep -q 'empty' || { echo "$LANE_ERROR"; false; }
  printf '%s\n' "$LANE_ERROR" | grep -q 'spell an empty cell' || { echo "$LANE_ERROR"; false; }
}

@test "a row with a column missing is refused, not read short" {
  row ubuntu-base container ubuntu:24.04 base apply 'claude starter'
  run lane_row "$TSV" ubuntu-base
  [ "$status" -ne 0 ] || { echo "a 6-column row was accepted"; false; }
  lane_row "$TSV" ubuntu-base || true
  printf '%s\n' "$LANE_ERROR" | grep -q '6 columns' || { echo "$LANE_ERROR"; false; }
}

@test "a row with a column too many is refused as well" {
  row ubuntu-base container ubuntu:24.04 base apply 'claude starter' deps extra
  run lane_row "$TSV" ubuntu-base
  [ "$status" -ne 0 ] || { echo "an 8-column row was accepted"; false; }
}

@test "the dash is what an empty cell looks like, and it reads through" {
  row macos-drift runner macos-latest debrewed apply 'claude starter' -
  lane_row "$TSV" macos-drift
  [ "$LANE_DEPS" = "-" ] || { echo "deps [$LANE_DEPS]"; false; }
}

@test "a single quote is refused everywhere it would break a guest command" {
  # Columns 1-6 are interpolated into single-quoted guest command strings, so a quote
  # of their own would close that string and run the remainder as shell.
  row odd container "ubuntu'24" base apply 'claude starter' -
  run lane_row "$TSV" odd
  [ "$status" -ne 0 ] || { echo "a quote was accepted into a guest command"; false; }
}

@test "the deps column may hold quotes, because it IS shell" {
  # arch-base really does need `printf 'DisableSandbox\n' >> /etc/pacman.conf`: the
  # deps cell is the image's bare minimum, run as a root provisioning command.
  row arch container archlinux:base no-git apply 'claude-cli node git' \
    "printf 'DisableSandbox\n' >> /etc/pacman.conf && pacman -Sy --noconfirm git"
  run lane_row "$TSV" arch
  [ "$status" -eq 0 ] || { echo "$LANE_ERROR"; false; }
}

@test "a lane that is not in the file says so" {
  row ubuntu-base container ubuntu:24.04 base apply 'claude starter' -
  run lane_row "$TSV" nope
  [ "$status" -ne 0 ]
  lane_row "$TSV" nope || true
  printf '%s\n' "$LANE_ERROR" | grep -q "no lane 'nope'" || { echo "$LANE_ERROR"; false; }
}

@test "the header row is never a lane" {
  run lane_row "$TSV" lane
  [ "$status" -ne 0 ] || { echo "the header parsed as a lane"; false; }
}

@test "a missing matrix is an error, not an empty lane" {
  run lane_row "$BATS_TEST_TMPDIR/nope.tsv" ubuntu-base
  [ "$status" -ne 0 ]
}

# ── The real file ─────────────────────────────────────────────────────────────

@test "every row of the shipped lane matrix parses" {
  # The convention made mechanical: this is what stops a new lane row landing with a
  # blank cell and reporting class 2 forever.
  local real="$REPO_ROOT/tests/real/lanes.tsv"
  local n=0
  while IFS= read -r lane; do
    [ -n "$lane" ] || continue
    case "$lane" in \#*|lane) continue ;; esac
    n=$((n + 1))
    lane_row "$real" "$lane" || { echo "$LANE_ERROR"; false; }
    [ -n "$LANE_ADAPTER" ] || { echo "$lane has no adapter"; false; }
    [ -n "$LANE_ENTRY" ] || { echo "$lane has no entry"; false; }
  done < <(awk -F'\t' 'NR > 1 && $1 !~ /^#/ { print $1 }' "$real")
  [ "$n" -ge 8 ] || { echo "only $n lanes parsed - did the matrix shrink?"; false; }
}

@test "lane_names filters by adapter, so a new row joins the driver with no code change" {
  local real="$REPO_ROOT/tests/real/lanes.tsv"
  run lane_names "$real" container
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^ubuntu-base$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^macos-drift$' && { echo "a runner lane leaked into the container group"; false; }

  run lane_names "$real" container tart
  printf '%s\n' "$output" | grep -q '^macos-vanilla$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^macos-drift$' && { echo "the all group must never select runner"; false; }
  true
}

@test "an adapter nobody uses selects nothing, rather than everything" {
  run lane_names "$REPO_ROOT/tests/real/lanes.tsv" typo
  [ -z "$output" ] || { echo "$output"; false; }
}
