#!/usr/bin/env bats
#
# The cross-lane differentials, over a directory of manifests. Pure - no guest, no
# network - which matters more here than anywhere: this script was executed by NO CI
# job at all, because the lanes each run on their own runner and only somewhere with
# all the manifests can compare them.
#
# The pairing for the entry-point differential is DERIVED from lanes.tsv (a paste
# lane pairs with the apply lane on the same image and the same ids) rather than
# being a hardcoded lane name, so a new paste row joins both the local driver and CI
# with no code change. That derivation is what these cases mostly pin down.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  FIX="$REPO_ROOT/tests/fixtures/real"
  D="$BATS_TEST_TMPDIR/lanes"
  mkdir -p "$D"
}

# lane <name> <fixture> — lay a manifest out the way run.sh does.
lane() {
  mkdir -p "$D/$1"
  cp "$FIX/$2" "$D/$1/run1.manifest"
}

# mset <lane> <key> <value>
mset() {
  local f="$D/$1/run1.manifest"
  awk -F'\t' -v k="$2" -v v="$3" 'BEGIN { OFS = "\t" }
    $1 == k { print k, v; seen = 1; next }
    { print }
    END { if (!seen) print k, v }' "$f" > "$f.new"
  mv "$f.new" "$f"
}

diffs() { run bash "$REAL/differentials.sh" "$D" "$@"; }

@test "lanes that agree on the one PATH line agree" {
  lane ubuntu-base linux-ubuntu-base.manifest
  lane debian-codex linux-debian-codex.manifest
  lane fedora-safer linux-fedora-nodesktop.manifest
  diffs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'the OS-invariant subset agrees' || { echo "$output"; false; }
}

@test "a distro-specific PATH line is a finding, and the key is named" {
  # The design claim the invariant subset exists for: one line, written once, the
  # same everywhere. A distro-specific one is exactly what would break it.
  lane ubuntu-base linux-ubuntu-base.manifest
  lane fedora-safer linux-fedora-nodesktop.manifest
  mset fedora-safer rc.block 'export PATH="$HOME/.local/bin:$PATH"'
  diffs
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  printf '%s\n' "$output" | grep -q 'rc.block' || { echo "$output"; false; }
}

@test "the paste is compared with the apply lane on the same image and ids" {
  # Derived from lanes.tsv, not hardcoded: ubuntu-paste mirrors ubuntu-base cell for
  # cell except the entry point, so any disagreement IS the entry point.
  lane ubuntu-base linux-ubuntu-base.manifest
  lane ubuntu-paste linux-ubuntu-base.manifest
  diffs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'apply.sh and the real paste left identical state' \
    || { echo "$output"; false; }
}

@test "an entry point that leaves a different machine is a finding" {
  lane ubuntu-base linux-ubuntu-base.manifest
  lane ubuntu-paste linux-ubuntu-base.manifest
  mset ubuntu-paste path.npmrc 'file:deadbeef'
  diffs
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  printf '%s\n' "$output" | grep -q 'path.npmrc' || { echo "$output"; false; }
}

@test "a paste lane whose apply partner did not run is not silently skipped over" {
  lane ubuntu-paste linux-ubuntu-base.manifest
  lane debian-codex linux-debian-codex.manifest
  diffs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'no apply/paste pair ran' || { echo "$output"; false; }
}

@test "a Windows manifest is left out of the POSIX invariant claim" {
  # The PowerShell spine persists no PATH, so it carries none of the rc keys this
  # subset compares - and manifest_invariant_subset refuses it by name rather than
  # comparing two near-empty sets and calling them equal.
  lane ubuntu-base linux-ubuntu-base.manifest
  lane debian-codex linux-debian-codex.manifest
  mkdir -p "$D/windows-2025"
  cp "$FIX/win-registry.manifest" "$D/windows-2025/run1.manifest"
  diffs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'windows-2025' && { echo "a Windows lane joined the POSIX claim"; false; }
  true
}

@test "nothing to compare is a harness bug, not an agreement" {
  # The §3 rule at the driver level: two empty subsets used to `diff` clean. An empty
  # directory must not read as "every lane agreed".
  diffs
  [ "$status" -eq 3 ] || { echo "status $status: $output"; false; }
  printf '%s\n' "$output" | grep -q 'nothing was compared' || { echo "$output"; false; }
}

@test "one lane alone says so rather than reporting an agreement" {
  lane ubuntu-base linux-ubuntu-base.manifest
  diffs
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'nothing to compare across lanes' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'subset agrees' && { echo "one lane agreed with itself"; false; }
  true
}

@test "a lane named but never run is not diffed against a stale manifest" {
  # `--group linux` leaves last week's macOS manifests on disk, and diffing those
  # would report a disagreement between two runs nobody made today.
  lane ubuntu-base linux-ubuntu-base.manifest
  diffs ubuntu-base macos-vanilla
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'macos-vanilla' && { echo "a lane that did not run was compared"; false; }
  true
}
