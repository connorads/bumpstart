#!/usr/bin/env bats
#
# The manifest DIFFERENTIALS - the half of the oracle that needs no hand-written
# expectations at all. The judge asserts only what a fake cannot reach; everything
# else is proved by making two runs that OUGHT to agree produce an identical
# normalised state.
#
# Which keys are compared is the load-bearing choice - too strict and every version
# bump is a red, too loose and the differential proves nothing - so it is pinned down
# here rather than discovered on a lane.
#
# The case that earns this file its own name: two manifests sharing no keys used to
# produce two empty subsets, `diff` succeeded, and manifest_diff returned 0. "The
# OS-invariant subset agrees" for every lane pair in the matrix, while measuring
# nothing.
#
# Pure: fixture files in, an exit status out. No guest, no network.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  FIX="$REPO_ROOT/tests/fixtures/real"
  M="$BATS_TEST_TMPDIR/manifest"
  # shellcheck source=tests/real/lib/manifest.sh
  . "$REAL/lib/manifest.sh"
}

# mani <fixture> - copy a fixture manifest in as the mutable subject.
mani() { cp "$FIX/$1" "$M"; }

# mset <key> <value> - set (or add) a key.
mset() {
  awk -F'\t' -v k="$1" -v v="$2" 'BEGIN { OFS = "\t" }
    $1 == k { print k, v; seen = 1; next }
    { print }
    END { if (!seen) print k, v }' "$M" > "$M.new"
  mv "$M.new" "$M"
}

# ── The differentials: the half of the oracle with no hand-written expectations ─
#
# The judge asserts only what a fake cannot reach; everything else is proved by
# making two runs that OUGHT to agree produce an identical normalised state. Which
# keys are compared is the load-bearing choice - too strict and every version bump is
# a red, too loose and the differential proves nothing - so it is pinned down here.

@test "the state subset ignores what identifies a run, and what a run narrates" {
  mani linux-ubuntu-base.manifest
  run manifest_state_subset "$M"
  [ "$status" -eq 0 ]
  for k in lane adapter guest axis mode run manifest_version; do
    printf '%s\n' "$output" | grep -q "^$k	" && { echo "$k should not be compared"; false; }
  done
  for p in 'transcript\.' 'warn\.' 'info\.' 'error\.' 'askpass\.' '\.version_raw'; do
    printf '%s\n' "$output" | grep -q "$p" && { echo "$p should not be compared"; false; }
  done
  # And it DOES carry the state.
  printf '%s\n' "$output" | grep -q '^rc.marker_count	1$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^path.agents	file:' || { echo "$output"; false; }
  true
}

@test "two runs of the same lane differing only in the run number are identical" {
  mani linux-ubuntu-base.manifest
  cp "$M" "$BATS_TEST_TMPDIR/run1"
  mset run 2
  mset transcript.warn_count 1
  mset warn.0001 'the Claude desktop app already installed'
  mset tool.node.version_raw 'v24.9.0'
  run manifest_diff 'run 1' "$BATS_TEST_TMPDIR/run1" 'run 2' "$M" manifest_state_subset
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a file that changed between runs breaks idempotence, and is named" {
  mani linux-ubuntu-base.manifest
  cp "$M" "$BATS_TEST_TMPDIR/run1"
  mset path.npmrc 'file:deadbeef'
  run manifest_diff 'run 1' "$BATS_TEST_TMPDIR/run1" 'run 2' "$M" manifest_state_subset
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'path.npmrc' || { echo "$output"; false; }
}

@test "the invariant subset holds across every POSIX lane, whatever the paste" {
  local base="$FIX/linux-ubuntu-base.manifest"
  for other in linux-debian-codex linux-fedora-nodesktop linux-ubuntu-password mac-casks; do
    run manifest_diff ubuntu "$base" "$other" "$FIX/$other.manifest" manifest_invariant_subset
    [ "$status" -eq 0 ] || { echo "$other diverges: $output"; false; }
  done
}

@test "a distro-specific PATH line breaks the invariant subset" {
  mani linux-fedora-nodesktop.manifest
  mset rc.block 'export PATH="$HOME/.local/bin:$PATH"'
  run manifest_diff ubuntu "$FIX/linux-ubuntu-base.manifest" fedora "$M" manifest_invariant_subset
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'rc.block' || { echo "$output"; false; }
}

# ── A subset that measures nothing is not an agreement ────────────────────────

@test "two manifests sharing no invariant keys do not silently agree" {
  # The exact regression: a probe that stopped emitting rc.block would make BOTH
  # subsets empty, `diff` succeed, and the driver print "the OS-invariant subset
  # agrees" for every lane pair in the matrix.
  printf 'os\tlinux\n' > "$BATS_TEST_TMPDIR/a"
  printf 'os\tmac\n'   > "$BATS_TEST_TMPDIR/b"
  run manifest_diff a "$BATS_TEST_TMPDIR/a" b "$BATS_TEST_TMPDIR/b" manifest_invariant_subset
  [ "$status" -ne 0 ] || { echo "two empty subsets agreed: $output"; false; }
  printf '%s\n' "$output" | grep -q 'no usable subset' || { echo "$output"; false; }
}

@test "a manifest that cannot be read is not an agreement either" {
  mani linux-ubuntu-base.manifest
  run manifest_diff real "$M" gone "$BATS_TEST_TMPDIR/does-not-exist" manifest_state_subset
  [ "$status" -ne 0 ] || { echo "an unreadable manifest agreed: $output"; false; }
}

@test "a state subset stripped down to a handful of keys is refused" {
  # Not just empty: a probe emitting a fraction of what it used to would otherwise
  # compare that fraction and call the rest identical.
  mani linux-ubuntu-base.manifest
  head -12 "$M" > "$BATS_TEST_TMPDIR/short"
  run manifest_state_subset "$BATS_TEST_TMPDIR/short"
  [ "$status" -ne 0 ] || { echo "a truncated manifest yielded a usable subset"; false; }
  printf '%s\n' "$output" | grep -q 'fewer than' || { echo "$output"; false; }
}

@test "a real manifest clears the minimum with room to spare" {
  # The other direction: the guard must not be so tight that a legitimate lane trips
  # it. Every fixture's state subset, and every POSIX one's invariant subset.
  for f in "$FIX"/*.manifest; do
    run manifest_state_subset "$f"
    [ "$status" -eq 0 ] || { echo "$(basename "$f") state subset: $output"; false; }
    grep -q '^os	win$' "$f" && continue
    run manifest_invariant_subset "$f"
    [ "$status" -eq 0 ] || { echo "$(basename "$f") invariant subset: $output"; false; }
  done
}

@test "the invariant subset refuses a Windows manifest rather than under-measuring it" {
  # The PowerShell spine persists no PATH, so a Windows manifest carries none of the
  # rc keys this subset exists to compare. drive.sh skips them; the function says so
  # itself, because a caller that forgets would get "they agree" over two near-empty
  # sets.
  run manifest_invariant_subset "$FIX/win-registry.manifest"
  [ "$status" -ne 0 ] || { echo "a Windows manifest yielded a POSIX invariant subset"; false; }
  printf '%s\n' "$output" | grep -q 'POSIX' || { echo "$output"; false; }
}

# ── One guest or two: the same question has two right answers ─────────────────

@test "the entry-point subset leaves out what a vendor seeds with per-install randomness" {
  # Claude Code's own installer writes ~/.claude.json before vibe looks at it -
  # firstStartTime, machineID, userID - and vibe's preseed_claude_trust then leaves
  # it alone by design. Its hash therefore differs between any two machines, so the
  # apply-vs-paste differential (two GUESTS) would report a vendor's randomness as
  # class 1, "vibe is wrong", on the most expensive lane pair in the matrix.
  mani linux-ubuntu-base.manifest
  cp "$M" "$BATS_TEST_TMPDIR/other"
  mset path.claude-json 'file:deadbeef'
  run manifest_diff apply "$BATS_TEST_TMPDIR/other" paste "$M" manifest_entry_subset
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "idempotence still compares it, because on ONE guest it is stable" {
  # The other half of the same decision: a second run rewriting Claude's config is a
  # real finding, and preseed_claude_trust explicitly promises not to.
  mani linux-ubuntu-base.manifest
  cp "$M" "$BATS_TEST_TMPDIR/run1"
  mset path.claude-json 'file:deadbeef'
  run manifest_diff 'run 1' "$BATS_TEST_TMPDIR/run1" 'run 2' "$M" manifest_state_subset
  [ "$status" -eq 1 ] || { echo "a rewritten Claude config passed idempotence"; false; }
  printf '%s\n' "$output" | grep -q 'path.claude-json' || { echo "$output"; false; }
}

@test "the entry-point subset still carries everything else" {
  mani linux-ubuntu-base.manifest
  cp "$M" "$BATS_TEST_TMPDIR/other"
  mset path.agents 'file:deadbeef'
  run manifest_diff apply "$BATS_TEST_TMPDIR/other" paste "$M" manifest_entry_subset
  [ "$status" -eq 1 ] || { echo "the entry subset stopped comparing state"; false; }
  printf '%s\n' "$output" | grep -q 'path.agents' || { echo "$output"; false; }
}
