#!/usr/bin/env bats
#
# The lane driver's guards - the checks that run BEFORE any guest boots, and whose
# whole job is to stop a forty-minute run from reporting a failure that is not one.
#
# Every case runs against a throwaway git repo holding a copy of tests/real, with
# lanes/run.sh replaced by a stub. drive.sh's own decisions are the unit under test,
# so nothing here boots a guest, installs anything, or depends on the state of the
# tree the suite happens to be running in.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/tests"
  cp -R "$REAL" "$R/tests/real"
  # The lane runner is stubbed: it announces itself and passes. What matters here is
  # whether drive.sh reached it at all.
  printf '#!/bin/sh\necho "STUB RAN: $*"\nexit 0\n' > "$R/tests/real/lanes/run.sh"
  chmod +x "$R/tests/real/lanes/run.sh"
  git -C "$R" init -q
  # An empty hooksPath: whatever the developer's own repo runs on commit is none of
  # this scratch repo's business, and a machine-local identity guard would otherwise
  # decide whether these cases can run at all.
  mkdir -p "$BATS_TEST_TMPDIR/nohooks"
  git -C "$R" config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  git -C "$R" add tests
  git -C "$R" commit -qm scratch
  DRIVE="$R/tests/real/drive.sh"
}

@test "a paste lane on a dirty tree is refused before anything runs" {
  # macos-vanilla mounts the working tree; macos-vanilla-paste fetches a tarball of
  # the ref. Any uncommitted change to what the blocks assemble makes
  # instructions.canonical.sha256 differ, so the entry-point differential goes class
  # 1 - "vibe is wrong" - on the most expensive lane pair in the matrix, after forty
  # minutes, for a reason that is not a vibe failure.
  : > "$R/uncommitted"
  run bash "$DRIVE" macos-vanilla-paste
  [ "$status" -eq 3 ] || { echo "status $status: $output"; false; }
  printf '%s\n' "$output" | grep -q 'working tree is dirty' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'STUB RAN' && { echo "a lane ran anyway"; false; }
  true
}

@test "a clean tree lets the paste lane through" {
  run bash "$DRIVE" macos-vanilla-paste
  printf '%s\n' "$output" | grep -q 'working tree is dirty' && { echo "refused a clean tree"; false; }
  printf '%s\n' "$output" | grep -q 'STUB RAN: macos-vanilla-paste' || { echo "$output"; false; }
}

@test "--allow-dirty is the escape hatch, and it says so in the refusal" {
  : > "$R/uncommitted"
  run bash "$DRIVE" macos-vanilla-paste
  printf '%s\n' "$output" | grep -q 'allow-dirty' || { echo "$output"; false; }
  run bash "$DRIVE" --allow-dirty macos-vanilla-paste
  printf '%s\n' "$output" | grep -q 'STUB RAN: macos-vanilla-paste' || { echo "$output"; false; }
}

@test "a lane that does not paste is unaffected by a dirty tree" {
  # apply and install run from the mounted tree, so uncommitted changes are exactly
  # what they are meant to be testing. Refusing them would make the local loop
  # unusable, which is its own way of getting a lane muted.
  : > "$R/uncommitted"
  run bash "$DRIVE" ubuntu-base
  printf '%s\n' "$output" | grep -q 'working tree is dirty' && { echo "refused an apply lane"; false; }
  printf '%s\n' "$output" | grep -q 'STUB RAN: ubuntu-base' || { echo "$output"; false; }
}
