#!/usr/bin/env bats
#
# The real-install judge, over fixture manifests. Pure: no guest, no network, no
# installs — which is the whole reason the probe/judge split exists. A wrong
# assertion in the judge is caught here, by `mise run check` on every commit,
# rather than by a 40-minute lane run.
#
# Every case is either "a good manifest passes" or "this specific breakage makes it
# red", because a harness whose failure path is untested is a harness that will one
# day pass over a broken machine.
#
# bash-3.2 note: a non-final `[[ ]]` failure does not trip errexit under /bin/bash
# 3.2, so assertions here are `[ ]` with an explicit `|| false` diagnostic, matching
# the rest of the suite.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  FIX="$REPO_ROOT/tests/fixtures/real"
  M="$BATS_TEST_TMPDIR/manifest"
  export NO_COLOR=1
}

# mani <fixture> — copy a fixture manifest in as the mutable subject.
mani() { cp "$FIX/$1" "$M"; }

# mset <key> <value> — set (or add) a key.
mset() {
  awk -F'\t' -v k="$1" -v v="$2" 'BEGIN { OFS = "\t" }
    $1 == k { print k, v; seen = 1; next }
    { print }
    END { if (!seen) print k, v }' "$M" > "$M.new"
  mv "$M.new" "$M"
}

# mdel <key> — drop a key entirely (the fail-closed case).
mdel() {
  awk -F'\t' -v k="$1" '$1 != k' "$M" > "$M.new"
  mv "$M.new" "$M"
}

mblocks() { awk -F'\t' '$1 == "blocks" { print $2 }' "$M"; }

# judge — run the judge with the block list the manifest itself carries.
judge() {
  run bash "$REAL/judge.sh" "$M" $(mblocks)
}

# The plan line must match the number of assertions emitted: a judge that decided
# three of twelve must not be able to read as a pass.
assert_plan_matches() {
  local planned emitted
  planned="$(printf '%s\n' "$output" | sed -n 's/^1\.\.\([0-9]*\)$/\1/p')"
  emitted="$(printf '%s\n' "$output" | grep -c '^\(ok\|not ok\) ')"
  [ -n "$planned" ] || { echo "no 1..N plan line in output"; false; }
  [ "$planned" = "$emitted" ] || { echo "planned $planned, emitted $emitted"; false; }
}

# ── The good manifests all pass ───────────────────────────────────────────────

@test "every fixture manifest is judged a pass" {
  for f in "$FIX"/*.manifest; do
    cp "$f" "$M"
    judge
    [ "$status" -eq 0 ] || { echo "$(basename "$f") should pass:"; echo "$output"; false; }
    assert_plan_matches
  done
}

@test "the plan line comes first, so a truncated judgement can't read as a pass" {
  mani linux-ubuntu-base.manifest
  judge
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1..33" ] || { echo "first line: ${lines[0]}"; false; }
}

@test "a known gap is a TODO, not a failure" {
  mani linux-ubuntu-base.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^not ok .* non-interactive login shell.* # TODO ' \
    || { echo "$output"; false; }
}

@test "the accepted bash -lc gap turning green is reported, not hidden" {
  mani linux-ubuntu-base.manifest
  mset shell.lc.gh 1
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^ok .* gh resolves in a non-interactive login shell, and did not before the run$' \
    || { echo "$output"; false; }
}

# ── Fail closed: an unmeasured key is a failure, never a skip ─────────────────

@test "a manifest missing a key the lane expects fails" {
  mani linux-ubuntu-base.manifest
  mdel app.claude-desktop
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "has no key 'app.claude-desktop'" || { echo "$output"; false; }
}

@test "an unmeasured key fails even where a mismatch would only be a TODO" {
  mani linux-ubuntu-base.manifest
  mdel shell.lc.gh
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "has no key 'shell.lc.gh'" || { echo "$output"; false; }
}

# ── The three verdict outcomes ────────────────────────────────────────────────

@test "a warned verdict fails" {
  mani linux-ubuntu-base.manifest
  mset transcript.verdict warned
  mset transcript.warn_count 1
  mset warn.0001 "Couldn't install Node.js - continuing"
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "^not ok .* clean 'Setup complete.'$" || { echo "$output"; false; }
}

@test "an aborted run fails (a run that ends under set -e prints no verdict line)" {
  mani mac-casks.manifest
  mset transcript.verdict aborted
  mset transcript.exit 1
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* the applier exited 0$' || { echo "$output"; false; }
}

# ── The warning detector, in both directions ──────────────────────────────────

@test "a warning outside this machine's legitimate set fails while the verdict stays green" {
  # Verification step 5: drop gnupg from the ubuntu leg and claude-desktop skips
  # with a warning + exit 0, so the run still prints "Setup complete."
  mani linux-ubuntu-base.manifest
  mset transcript.warn_count 1
  mset warn.0001 "need gpg to check the Claude app's signing key - skipping the desktop app."
  mset app.claude-desktop 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "^ok .* clean 'Setup complete.'$" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^not ok .* no warning outside the ones' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '# unexpected warning: need gpg' || { echo "$output"; false; }
}

@test "the no-apt claude-desktop warning is legitimate on fedora and tolerated" {
  mani linux-fedora-nodesktop.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^ok .* no warning outside the ones' || { echo "$output"; false; }
}

@test "the same warning is NOT tolerated on a machine that does have apt-get" {
  mani linux-fedora-nodesktop.manifest
  mset env.pkg.apt 1
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* no warning outside the ones' || { echo "$output"; false; }
}

@test "the codex sandbox warning is legitimate only where the userns knob is set" {
  mani linux-debian-codex.manifest
  judge
  [ "$status" -eq 0 ]

  mset env.userns.restricted none
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* no warning outside the ones' || { echo "$output"; false; }
}

@test "the userns warning must print the fix for the knob this kernel has" {
  mani linux-debian-codex.manifest
  mset env.userns.restricted clone
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* printed the fix for the knob' || { echo "$output"; false; }
}

@test "a root run makes the sudo paths vacuous, so the codex warning is no longer expected" {
  mani linux-debian-codex.manifest
  mset env.root 1
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* was NOT root' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^not ok .* no warning outside the ones' || { echo "$output"; false; }
}

# ── Acquisition: a binary that resolves but does not run ──────────────────────

@test "a tool that is on PATH but cannot execute fails" {
  mani linux-ubuntu-base.manifest
  mset tool.node.runs 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* node --version runs$' || { echo "$output"; false; }
}

@test "the expected tool set is read off the resolved block list" {
  # No pnpm block -> no pnpm assertions, so a lane cannot silently under-assert by
  # listing fewer blocks than it installed.
  mani linux-ubuntu-base.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'pnpm --version runs' && { echo "asserted pnpm without the block"; false; }
  true
}

# ── Persistence into a fresh shell, as a DELTA ────────────────────────────────
#
# The bug this closes: `env -i "$SHELL" -lc` is not an empty PATH — bash substitutes
# a compiled-in default containing /usr/bin — so `shell.lc.git 1` was true on the
# ubuntu lane whether or not persist_path ever ran, and the judge counted it as a
# pass. Nothing here can be vacuous now without the baseline saying so out loud.

@test "a tool that already resolved before the run is credited to the image, not to bumpstart" {
  # ubuntu:24.04 ships git, so its fresh-shell pass is a fact about the image. The
  # assertion still runs — it just says whose doing it was.
  mani linux-ubuntu-base.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" \
    | grep -q "^ok .* git resolves in a fresh interactive login shell (it did before the run too" \
    || { echo "$output"; false; }
  printf '%s\n' "$output" \
    | grep -q '^ok .* claude resolves in a fresh interactive login shell, and did not before the run$' \
    || { echo "$output"; false; }
}

@test "a tool bumpstart was supposed to install, on a guest that already had it, is not a pass for bumpstart" {
  # The vacuity, made visible: pretend the image shipped claude too. The end state is
  # identical and the old judge could not tell the difference; the delta reports it.
  mani linux-ubuntu-base.manifest
  mset precheck.shell.lic.claude 1
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^ok .* claude resolves in a fresh interactive login shell, and did not before the run$' \
    && { echo "still claiming credit for a preinstalled tool"; false; }
  printf '%s\n' "$output" \
    | grep -q "^ok .* claude resolves in a fresh interactive login shell (it did before the run too" \
    || { echo "$output"; false; }
}

@test "a tool that resolved before the run and does not now is a regression" {
  # The failure mode no end-state assertion could ever see: bumpstart BREAKING a machine.
  mani linux-ubuntu-base.manifest
  mset shell.lic.git 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* git resolves in a fresh interactive login shell' \
    || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'got \[lost\]' || { echo "$output"; false; }
}

@test "a regression is never softened into an accepted gap" {
  # `bash -lc` is a documented TODO, so a tool that never resolves there is tolerated.
  # A tool that STOPPED resolving there is not the same finding, and must go red.
  mani linux-ubuntu-base.manifest
  mset shell.lc.git 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* git resolves in a non-interactive login shell.*# TODO' \
    && { echo "a regression was filed as a known gap"; false; }
  printf '%s\n' "$output" | grep -q 'got \[lost\]' || { echo "$output"; false; }
}

@test "a run with no baseline cannot be credited with a delta" {
  mani linux-ubuntu-base.manifest
  mdel precheck.shell.lic.claude
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "has no key 'precheck.shell.lic.claude'" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'pre-run baseline' || { echo "$output"; false; }
}

@test "windows tells a machine-PATH preinstall apart from something bumpstart installed" {
  # The whole Windows finding in one case: the runner images carry git, node and gh
  # on the Machine PATH, so INSTALL_WIN for those never runs. Only claude is a delta.
  mani win-registry.manifest
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^ok .* claude resolves from the registry PATH, and did not before the run$' \
    || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q "^ok .* git resolves from the registry PATH (it did before the run too" \
    || { echo "$output"; false; }
}



@test "a tool missing from a fresh interactive login shell fails" {
  mani linux-ubuntu-base.manifest
  mset shell.lic.claude 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* claude resolves in a fresh interactive login shell, and did not before the run$' \
    || { echo "$output"; false; }
}

@test "a missing PATH marker fails (this is the persist_path regression)" {
  mani linux-ubuntu-base.manifest
  mset rc.marker_count 0
  mset shell.lic.claude 0
  mset shell.ic.claude 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* marker appears exactly once$' || { echo "$output"; false; }
}

@test "the marker appearing twice fails" {
  mani linux-ubuntu-base.manifest
  mset rc.marker_count 2
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* marker appears exactly once$' || { echo "$output"; false; }
}

@test "a vendor-authored PATH edit beside bumpstart's fails" {
  mani linux-ubuntu-base.manifest
  mset rc.vendor_path_lines 1
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* no vendor-authored PATH edit' || { echo "$output"; false; }
}

@test "windows resolves against the registry PATH, and has no rc assertions" {
  mani win-registry.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'resolves from the registry PATH' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'marker appears exactly once' && { echo "asserted an rc file on win"; false; }
  true
}

@test "a tool missing from the windows registry PATH fails" {
  mani win-registry.manifest
  mset shell.regpath.claude 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* claude resolves from the registry PATH, and did not before the run$' \
    || { echo "$output"; false; }
}

# ── The axes must not be vacuous ──────────────────────────────────────────────

@test "a no-curl axis whose guest still has curl fails" {
  mani linux-ubuntu-base.manifest
  mset axis no-curl
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* really has no curl' || { echo "$output"; false; }
}

@test "a no-curl axis with curl genuinely absent passes" {
  mani linux-ubuntu-base.manifest
  mset axis no-curl
  mset precheck.curl absent
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a no-git axis whose guest still has git fails" {
  mani linux-ubuntu-base.manifest
  mset axis no-git
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* really has no git' || { echo "$output"; false; }
}

@test "a de-brewed lane whose guest still has Homebrew fails" {
  # The macOS drift lane's scrub is best effort by design (`set +e … exit 0`), so if
  # the uninstaller's flags change the lane would test "brew was already installed"
  # instead of ensure_brew. Same rule as no-curl, spelled for a scrub.
  mani mac-casks.manifest
  mset axis debrewed
  mset precheck.brew present
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* really removed Homebrew' || { echo "$output"; false; }
}

@test "a de-brewed lane with Homebrew genuinely gone passes" {
  mani mac-casks.manifest
  mset axis debrewed
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^ok .* really removed Homebrew' || { echo "$output"; false; }
}

@test "a guest that already carried the bumpstart marker is not pristine" {
  mani linux-ubuntu-base.manifest
  mset precheck.bumpstart_marker present
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* no bumpstart PATH marker before' || { echo "$output"; false; }
}

# ── The sudo password prompt ──────────────────────────────────────────────────

@test "a password lane where askpass never fired fails" {
  mani linux-ubuntu-password.manifest
  mset askpass.count 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* sudo really asked for a password' || { echo "$output"; false; }
}

@test "a password lane with no askpass log at all fails" {
  mani linux-ubuntu-password.manifest
  mdel askpass.count
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "has no key 'derived.askpass_fired'" || { echo "$output"; false; }
}

@test "asking twice is a finding, and the count is always reported" {
  mani linux-ubuntu-password.manifest
  mset askpass.count 2
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* asked exactly once' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^# askpass invocations: 2$' || { echo "$output"; false; }
}

# The second run finds git already installed, so it has no privileged work left and
# must NOT ask again — the opposite claim to run 1's, and the reason the runner
# truncates askpass.log per run. Asserting "exactly once" on both is what a shared
# log made look true on a run that never asked at all.
@test "the second password run must not ask again" {
  mani linux-ubuntu-password.manifest
  mset run 2
  mset askpass.count 0
  mdel askpass.0001
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_plan_matches
  printf '%s\n' "$output" | grep -q '^ok .* did not ask again' || { echo "$output"; false; }
}

@test "a second password run that asks again is a finding" {
  mani linux-ubuntu-password.manifest
  mset run 2
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* did not ask again' || { echo "$output"; false; }
}

@test "a manifest with no run number takes the stricter first-run assertion" {
  mani linux-ubuntu-password.manifest
  mdel run
  mset askpass.count 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* sudo really asked for a password' || { echo "$output"; false; }
}

@test "a non-password lane asserts nothing about askpass" {
  mani linux-ubuntu-base.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'asked exactly once' && { echo "askpass asserted off-axis"; false; }
  true
}

# ── Desktop apps ──────────────────────────────────────────────────────────────

@test "the ubuntu leg requires claude-desktop to be really installed" {
  mani linux-ubuntu-base.manifest
  mset app.claude-desktop 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* installed from the apt repository' || { echo "$output"; false; }
}

@test "fedora requires claude-desktop to be ABSENT, so a surprise install is also a finding" {
  mani linux-fedora-nodesktop.manifest
  mset app.claude-desktop 1
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* correctly absent' || { echo "$output"; false; }
}

@test "a missing cask fails on the mac lane" {
  mani mac-casks.manifest
  mset app.github-desktop 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* GitHub Desktop is installed$' || { echo "$output"; false; }
}

# ── safer-installs, and instructions ─────────────────────────────────────────

@test "a safer-installs key at the wrong value fails" {
  mani linux-fedora-nodesktop.manifest
  mset pnpm.minimumReleaseAgeStrict false
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "^not ok .* pnpm's wait fails closed$" || { echo "$output"; false; }
}

@test "safer-installs keys are only asserted where the block is in the plan" {
  mani linux-ubuntu-base.manifest
  judge
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'npm waits 4 days' && { echo "asserted safer-installs without the block"; false; }
  true
}

@test "a harness path pointing somewhere other than the canonical file fails" {
  mani linux-ubuntu-base.manifest
  mset instructions.link.claude 'file:0000'
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "^not ok .* Claude's own path resolves" || { echo "$output"; false; }
}

@test "an empty canonical instructions file fails" {
  mani linux-ubuntu-base.manifest
  mset instructions.canonical.nonempty 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* canonical instructions file is non-empty$' || { echo "$output"; false; }
}

@test "a shipped tool block's guidance missing from the file fails" {
  mani linux-ubuntu-base.manifest
  mset instructions.section.node 0
  judge
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^not ok .* Node.js guidance is in the file$' || { echo "$output"; false; }
}

# ── Harness bugs are exit class 3, never a silent pass or a bumpstart failure ──────

@test "no manifest is a harness bug (class 3)" {
  run bash "$REAL/judge.sh" "$BATS_TEST_TMPDIR/nope" claude-cli
  [ "$status" -eq 3 ]
}

@test "no expected blocks is a harness bug (class 3)" {
  mani linux-ubuntu-base.manifest
  run bash "$REAL/judge.sh" "$M"
  [ "$status" -eq 3 ]
}

@test "blocks that disagree with the manifest are a harness bug (class 3)" {
  mani linux-ubuntu-base.manifest
  run bash "$REAL/judge.sh" "$M" claude-cli node
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'disagree with the expected list' || { echo "$output"; false; }
}

@test "a manifest from an older probe is a harness bug, not a page of bumpstart failures" {
  # Without this, a probe/judge skew fails every delta closed — dozens of "nothing
  # was measured" lines, which read as class 1. The version says "wrong shape".
  mani linux-ubuntu-base.manifest
  mset manifest_version 1
  judge
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'the probe and the judge disagree' || { echo "$output"; false; }
}

@test "a manifest with no usable os is a harness bug (class 3)" {
  mani linux-ubuntu-base.manifest
  mset os plan9
  judge
  [ "$status" -eq 3 ]
}

@test "the judge never reads the machine it is judging" {
  # Purity, proved by starvation rather than by grepping for suspicious words: a
  # PATH holding only the four text utilities the judge legitimately needs. If it
  # ever reaches for curl, ssh, docker, sudo, uname or a package manager, this test
  # is where that shows up.
  local bin="$BATS_TEST_TMPDIR/onlytext"
  mkdir -p "$bin"
  for t in cat awk grep dirname; do
    ln -s "$(command -v "$t")" "$bin/$t"
  done
  mani linux-ubuntu-base.manifest
  run env -i PATH="$bin" HOME="$BATS_TEST_TMPDIR" NO_COLOR=1 \
    "$BASH" "$REAL/judge.sh" "$M" $(mblocks)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── Blocks that do nothing on an OS must not be asserted there ────────────────

@test "mise is not expected on windows, where it has no install cell" {
  mani win-registry.manifest
  # node INCLUDEs mise, so a `claude starter` plan carries it even on Windows.
  mset blocks 'claude-cli claude-desktop gh-auth git mise node welcome concise ask-first verify secrets'
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'mise --version runs' && { echo "asserted mise on win"; false; }
  true
}

@test "mise IS expected on linux even when the plan never names it" {
  mani linux-ubuntu-base.manifest
  mset blocks 'claude-cli claude-desktop gh-auth git node welcome concise ask-first verify secrets'
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'mise --version runs' || { echo "$output"; false; }
}

@test "safer-installs is not asserted on windows, which has no apply.ps1 for it" {
  mani win-registry.manifest
  mset blocks 'claude-cli claude-desktop gh-auth git node safer-installs welcome concise ask-first verify secrets'
  judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'npm waits 4 days' && { echo "asserted safer-installs on win"; false; }
  true
}

# ── The TAP stream itself ─────────────────────────────────────────────────────

@test "a manifest value carrying a newline cannot inject lines into the TAP stream" {
  # The judge feeds manifest values straight to diag(), which prefixed only the
  # FIRST line. A value with an embedded newline would put a bare `not ok` line into
  # the stream, where any consumer counting assertions would believe it. The probe's
  # own normalisation is the first line of defence, and it has had a hole in it.
  mani linux-ubuntu-base.manifest
  # Written past `mset`, because the manifest format cannot carry this and that is
  # exactly the point: the stream has to be safe anyway.
  printf 'warn.0001\tinjected\nnot ok 99 - a failure nobody asserted\n' >> "$M"
  judge
  # Every emitted line is either an assertion the judge planned, a plan line, or a
  # comment. Nothing else may appear.
  local planned emitted
  planned="$(printf '%s\n' "$output" | sed -n 's/^1\.\.\([0-9]*\)$/\1/p')"
  emitted="$(printf '%s\n' "$output" | grep -c '^\(ok\|not ok\) ')"
  [ "$planned" = "$emitted" ] || { echo "planned $planned, emitted $emitted:"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^not ok 99' && { echo "a raw line reached the stream"; false; }
  true
}

@test "diag prefixes every line of a multi-line value" {
  # shellcheck source=tests/real/lib/tap.sh
  . "$REAL/lib/tap.sh"
  run diag "$(printf 'first\nsecond\nthird')"
  [ "${lines[0]}" = "# first" ] || { echo "$output"; false; }
  [ "${lines[1]}" = "# second" ] || { echo "$output"; false; }
  [ "${lines[2]}" = "# third" ] || { echo "$output"; false; }
}
