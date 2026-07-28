#!/usr/bin/env bash
set -uo pipefail
#
# run.sh: ONE lane, on a pristine machine, for real.
#
#   tests/real/lanes/run.sh <lane> [--keep] [--out DIR] [--ref SHA]
#
# One runner for every lane, parameterised by the guest adapter, because a Linux
# script and a near-identical macOS one would drift the moment either was touched.
# The lane matrix is DATA (tests/real/lanes.tsv), read by this runner and by CI, so
# "local and CI run the same thing" is true rather than aspirational.
#
# The rule that keeps a real lane real: it sets NO `VIBE_*` test seam except
# VIBE_REF. The codebase is generously seamed for the faked suite — VIBE_ROOT,
# VIBE_OS, VIBE_APPS_DIR, VIBE_PROC_DIR, VIBE_MISE_BIN, VIBE_OSRELEASE_FILE,
# VIBE_CLAUDE_KEY_URL — and any one of them used here would quietly turn a real
# install back into a simulated one. XDG_CONFIG_HOME counts too: it moves where
# safer-installs writes pnpm's config. The read-only repo mount is the one exception,
# and only for the entry points that are meant to run from a clone.
#
# THREE exit classes, not pass/fail. This is the structural answer to "the lane will
# get muted": a class 2 can be reported without going red, a class 1 never can.
#   1  an assertion failed          — vibe is wrong. The interesting case.
#   2  infrastructure failed        — the guest would not boot, a vendor URL 404'd,
#                                     the tarball would not fetch. Upstream moved.
#   3  harness bug                  — the probe crashed, the block list disagrees,
#                                     the TAP count is wrong.
# NO RETRIES anywhere: re-running until green hides exactly the nondeterminism these
# classes exist to name.
#
# Deliberately not `set -e`: the exit class is decided explicitly at every step, and
# errexit would collapse all three into one.

REAL="$(cd "$(dirname "$0")/.." && pwd -P)"
REPO="$(cd "$REAL/../.." && pwd -P)"

# shellcheck source=tests/real/lib/tap.sh
. "$REAL/lib/tap.sh"
# shellcheck source=tests/real/lib/manifest.sh
. "$REAL/lib/manifest.sh"
# shellcheck source=tests/real/lib/class.sh
. "$REAL/lib/class.sh"
# shellcheck source=tests/real/lib/triage.sh
. "$REAL/lib/triage.sh"
# shellcheck source=tests/real/lib/lanes.sh
. "$REAL/lib/lanes.sh"

LANE=""
KEEP=false
OUT=""
REF=""
RUNS=2

while [ $# -gt 0 ]; do
  case "$1" in
    --keep)  KEEP=true ;;
    --out)   OUT="${2:-}"; shift ;;
    --ref)   REF="${2:-}"; shift ;;
    --runs)  RUNS="${2:-2}"; shift ;;
    -*)      printf 'run.sh: unknown option %s\n' "$1" >&2; exit "$CLASS_HARNESS" ;;
    *)       LANE="$1" ;;
  esac
  shift
done

if [ -z "$LANE" ]; then
  printf 'usage: run.sh <lane> [--keep] [--out DIR] [--ref SHA] [--runs N]\n' >&2
  exit "$CLASS_HARNESS"
fi

[ -n "$OUT" ] || OUT="$REPO/.vibe-real/$LANE"
mkdir -p "$OUT" || exit "$CLASS_HARNESS"

# Cleared, not merely created. do_run writes run$n.manifest only on success, and the
# differentials below and in drive.sh key on the files being there — so a lane that
# now dies during run 2 would otherwise diff this run's run1 against LAST week's
# run2, from a different guest, and report the disagreement as a vibe failure.
# Named artefacts rather than `rm -rf "$OUT"`, because --out points wherever the
# caller says.
rm -f "$OUT"/run[0-9]*.transcript "$OUT"/run[0-9]*.manifest "$OUT"/run[0-9]*.tap \
      "$OUT"/run[0-9]*.probe.err "$OUT/lane.verdict" "$OUT/askpass.log" "$OUT/guest.env" \
      2>/dev/null

note()  { printf '  %s\n' "$1"; }
fail_infra()   { printf '\n  INFRASTRUCTURE: %s\n' "$1" >&2; }
fail_harness() { printf '\n  HARNESS BUG: %s\n' "$1" >&2; }

# ── The lane row ─────────────────────────────────────────────────────────────

LANES_TSV="$REAL/lanes.tsv"
TAB="$(printf '\t')"
if ! lane_row "$LANES_TSV" "$LANE"; then
  fail_harness "$LANE_ERROR"
  exit "$CLASS_HARNESS"
fi
ADAPTER="$LANE_ADAPTER"
IMAGE="$LANE_IMAGE"
AXIS="$LANE_AXIS"
ENTRY="$LANE_ENTRY"
PASTE="$LANE_PASTE"
DEPS="$LANE_DEPS"

IDS="$PASTE"
# The bare-paste default, spelled the same way lib/apply.sh spells it, so the
# no-ids entry point is judged against what it actually resolves to.
[ "$IDS" = "-" ] && IDS="claude starter"

# ── The expected block list, from the REAL resolver ──────────────────────────
#
# Derived, never a column in the TSV: a hand-maintained expectation would be free to
# disagree with what vibe actually resolves, and nothing would notice. The resolver
# is OS-neutral (tests/fixtures/contract/resolve-cases.tsv already locks it), so the
# host can answer for the guest.

# shellcheck disable=SC2086  # the id list is deliberately word-split
BLOCKS="$(bash "$REPO/tests/helpers/resolve_driver.sh" "$REPO/lib" "$REPO" $IDS | awk -F'\t' '{print $1}')"
if [ -z "$BLOCKS" ]; then
  fail_harness "could not resolve '$IDS' to a block list"
  exit "$CLASS_HARNESS"
fi

printf '\n  === lane %s (%s, %s, axis %s, entry %s) ===\n' "$LANE" "$ADAPTER" "$IMAGE" "$AXIS" "$ENTRY"
note "paste:  $IDS"
note "blocks: $BLOCKS"

# ── The verdict: how many assertions actually ran ───────────────────────────
#
# Written on EVERY exit path, class 0 and class 2 included, because the one thing no
# single lane can see is whether the SUITE proved anything. Three routes led to a
# permanently green, permanently useless matrix - an empty lane list, every leg
# returning class 2 as a green ::warning, and a bundle written only on class 1 - and
# they share one shape: nothing asserted that anything was asserted. tests/real/
# verdicts.sh aggregates these; judge.sh already has the instinct one level down
# ("a lane that asserts nothing cannot pass").
#
# An EXIT trap rather than a call at each exit: a lane that dies in provisioning has
# to say "class 2, nothing asserted" out loud, and there are eight ways out of this
# script.

# shellcheck disable=SC2329  # invoked from the EXIT trap below
write_verdict() {
  _wv_judged=0; _wv_ok=0; _wv_bad=0; _wv_todo=0
  for _wv_tap in "$OUT"/run[0-9]*.tap; do
    [ -f "$_wv_tap" ] || continue
    _wv_judged=$((_wv_judged + 1))
    _wv_ok=$((_wv_ok + $(grep -c '^ok ' "$_wv_tap" 2>/dev/null)))
    # `not ok … # TODO` is an ACCEPTED gap, not a failure; counted apart so neither
    # number lies.
    _wv_bad=$((_wv_bad + $(grep '^not ok ' "$_wv_tap" 2>/dev/null | grep -vc '# TODO ')))
    _wv_todo=$((_wv_todo + $(grep -c '^not ok .* # TODO ' "$_wv_tap" 2>/dev/null)))
  done
  {
    printf 'lane\t%s\n'        "$LANE"
    printf 'adapter\t%s\n'     "$ADAPTER"
    printf 'image\t%s\n'       "$IMAGE"
    printf 'axis\t%s\n'        "$AXIS"
    printf 'entry\t%s\n'       "$ENTRY"
    printf 'paste\t%s\n'       "$IDS"
    printf 'blocks\t%s\n'      "$BLOCKS"
    printf 'class\t%s\n'       "$1"
    printf 'runs_judged\t%s\n' "$_wv_judged"
    printf 'assertions\t%s\n'  "$((_wv_ok + _wv_bad + _wv_todo))"
    printf 'passed\t%s\n'      "$_wv_ok"
    printf 'failed\t%s\n'      "$_wv_bad"
    printf 'todo\t%s\n'        "$_wv_todo"
  } > "$OUT/lane.verdict"
}
trap 'write_verdict "$?"' EXIT

# ── The guest ────────────────────────────────────────────────────────────────

ADAPTER_FILE="$REAL/guests/$ADAPTER.sh"
if [ ! -f "$ADAPTER_FILE" ]; then
  fail_harness "no guest adapter '$ADAPTER'"
  exit "$CLASS_HARNESS"
fi

GUEST_NAME="vibe-real-$LANE"
GUEST_IMAGE="$IMAGE"
GUEST_REPO="$REPO"
GUEST_STATE=/tmp/vibe-real
GUEST_PASSWORD='vibe-test-not-a-secret'
GUEST_DEPS="$DEPS"
case "$AXIS" in
  *password-sudo*) GUEST_SUDO=password ;;
  *)               GUEST_SUDO=nopasswd ;;
esac
export GUEST_NAME GUEST_IMAGE GUEST_REPO GUEST_STATE GUEST_PASSWORD GUEST_DEPS GUEST_SUDO

# shellcheck source=tests/real/guests/container.sh
. "$ADAPTER_FILE"

S="$GUEST_STATE"

cleanup() {
  if [ "$KEEP" = true ]; then
    guest_keep
  else
    guest_destroy
  fi
}

note "booting the guest..."
if ! guest_start; then
  fail_infra "the guest would not start"
  exit "$CLASS_INFRA"
fi

note "provisioning (the image's bare minimum, plus an unprivileged user)..."
if ! guest_provision; then
  fail_infra "provisioning failed — the image or its package mirror moved"
  cleanup
  exit "$CLASS_INFRA"
fi

# ── The axis: make the guest LACK something, for real ───────────────────────
#
# Keyed on the package manager it HAS, never on a distro name — the same rule the
# product follows, so a derivative works for free.

axis_remove() {
  _ar_pkg="$1"
  if guest_exec_root "command -v apt-get >/dev/null 2>&1"; then
    guest_exec_root "apt-get remove -y -qq $_ar_pkg >/dev/null 2>&1"
  elif guest_exec_root "command -v dnf >/dev/null 2>&1"; then
    guest_exec_root "dnf remove -y -q $_ar_pkg >/dev/null 2>&1"
  elif guest_exec_root "command -v pacman >/dev/null 2>&1"; then
    guest_exec_root "pacman -Rdd --noconfirm $_ar_pkg >/dev/null 2>&1"
  else
    return 1
  fi
}

case "$AXIS" in
  *no-curl*)
    note "axis: removing curl"
    axis_remove curl || { fail_infra "could not remove curl"; cleanup; exit "$CLASS_INFRA"; } ;;
esac
case "$AXIS" in
  *no-git*)
    note "axis: removing git"
    axis_remove git || { fail_infra "could not remove git"; cleanup; exit "$CLASS_INFRA"; } ;;
esac

# ── Precheck: the BASELINE, measured before the run, once ───────────────────
#
# Written once and left in place for both runs, so `precheck.vibe_marker absent`
# keeps meaning "the guest was pristine when we started" rather than "run 2 found
# what run 1 wrote". It stops an axis going vacuous — a base image that starts
# shipping curl cannot silently turn the no-curl leg into a second base leg — and it
# is what the judge's fresh-shell DELTA is measured against: precheck.sh and probe.sh
# take the same reading through the same lib/measure.sh, before and after.
#
# Written in one shot via a .part file, not appended to a truncated one: a precheck
# that dies half-way must not leave a short file that reads as a complete
# measurement.

note "precheck..."
if ! guest_exec "cd \"\$HOME\" && VIBE_REAL_DIR=$S bash $GUEST_SRC/tests/real/precheck.sh > $S/precheck.part && mv $S/precheck.part $S/precheck.tsv"; then
  fail_harness "the precheck script failed in the guest"
  cleanup
  exit "$CLASS_HARNESS"
fi

# The password file the askpass helper reads. Not an environment variable: sudo runs
# the helper in a context we do not fully control, and a file is one less thing that
# has to survive.
#
# Plus the one thing the lanes shadow, and only here: a `sudo` ahead of the real one
# that adds -A. Measured on sudo 1.9.15p5, SUDO_ASKPASS alone is NOT consulted when
# there is no terminal, contrary to sudo's own man page, so without this the password
# path cannot be exercised headlessly at all. See bin/sudo-forces-askpass. It is
# never on the probe's PATH, so every measurement is still of the real machine.
if [ "$GUEST_SUDO" = password ]; then
  guest_exec_root "printf '%s' '$GUEST_PASSWORD' > $S/password && chmod 0644 $S/password" || {
    fail_harness "could not write the guest's password file"
    cleanup
    exit "$CLASS_HARNESS"
  }
  guest_exec_root "mkdir -p $S/bin && cp $GUEST_SRC/tests/real/bin/sudo-forces-askpass $S/bin/sudo && chmod 0755 $S/bin/sudo" || {
    fail_harness "could not install the sudo shim"
    cleanup
    exit "$CLASS_HARNESS"
  }
fi

# ── The entry point ─────────────────────────────────────────────────────────
#
# Four exist across the project (vibe, install.sh, vibe.ps1, install.ps1). `apply`
# and `install` run from the read-only clone; `paste` is the thing people actually
# paste, and it fetches `vibe` itself from the COMMIT UNDER TEST — the README's paste
# and install.sh:47 both hardcode `main` for the bootstrap and let VIBE_REF pin only
# the tarball, so pinning alone would test main's `vibe` and hand back a false green
# on any change to it.

#
# Every entry point is invoked from $HOME, by absolute path, NEVER with the mounted
# repo as the working directory. Two reasons, one of them measured the hard way:
# nobody pastes from inside a clone of vibe-setup, and mise refuses to run at all
# under a directory holding an untrusted mise.toml — which this repo's own is, in the
# guest. Running from /src silently broke every mise shim.
# shellcheck disable=SC2016  # "$HOME" and $(…) must be evaluated in the GUEST
entry_command() {
  case "$ENTRY" in
    apply)   printf 'cd "$HOME" && bash %s/lib/apply.sh %s --yes --no-launch' "$GUEST_SRC" "$IDS" ;;
    install) printf 'cd "$HOME" && bash %s/install.sh --yes --no-launch' "$GUEST_SRC" ;;
    paste)
      if [ -z "$REF" ]; then return 1; fi
      printf 'cd "$HOME" && VIBE_REF=%s /bin/bash -c "$(curl -fsSL %s || wget -qO- %s)" _ %s --yes --no-launch' \
        "$REF" \
        "https://raw.githubusercontent.com/connorads/vibe-setup/$REF/vibe" \
        "https://raw.githubusercontent.com/connorads/vibe-setup/$REF/vibe" \
        "$IDS" ;;
    *) return 2 ;;
  esac
}

# 1 and 2 are told apart because they send the reader to different places: a typo in
# the lane row's entry column reported itself as a missing --ref, and a ref has
# nothing to do with it.
ENTRY_CMD="$(entry_command)"
case "$?" in
  0) ;;
  1) fail_harness "entry 'paste' needs --ref <sha> (the paste cannot see an unpushed tree)"
     cleanup
     exit "$CLASS_HARNESS" ;;
  *) fail_harness "lane '$LANE' has an unknown entry kind '$ENTRY' (expected apply, install or paste)"
     cleanup
     exit "$CLASS_HARNESS" ;;
esac

# For the paste, check from the HOST that the ref is fetchable before running anything.
# Not belt-and-braces: `$(curl … || wget …)` around an unreachable url yields an EMPTY
# script, so `bash -c ""` exits 0 having done nothing and the lane would report
# "aborted" - class 1, vibe is wrong - for a ref that was simply never pushed. This is a
# precondition, not a retry.
if [ "$ENTRY" = paste ]; then
  _boot_url="https://raw.githubusercontent.com/connorads/vibe-setup/$REF/vibe"
  if ! curl -fsSL -o /dev/null "$_boot_url" 2>/dev/null; then
    fail_infra "the bootstrap script is not fetchable at ref '$REF' — push the commit first"
    note "$_boot_url"
    cleanup
    exit "$CLASS_INFRA"
  fi
fi

# ── One run, then the probe, then the judge ─────────────────────────────────

RUN_CLASS=0

do_run() {
  _dr_n="$1"

  # lane.tsv: what only the runner knows. Written in ONE truncating printf, so
  # accumulation is unrepresentable rather than merely unlikely.
  #
  # It used to be an unchecked `rm -f` followed by seven unchecked `>>` appends. If
  # the rm no-opped - reachable without exotic failure on the runner adapter, where
  # `sudo -n` follows `sudo -k` - run 2's lane.tsv held BOTH runs' rows, judge.sh
  # takes the first match, so `mget run` returned 1 during run 2 and the run-1
  # askpass branch ran against a correctly-truncated log. Class 1 on a correct
  # install, which is the one outcome this harness must never produce.
  _dr_rows=""
  for _kv in "lane:$LANE" "adapter:$ADAPTER" "guest:$IMAGE" "axis:$AXIS" \
             "mode:$ENTRY" "run:$_dr_n" "blocks:$BLOCKS"; do
    _dr_rows="$_dr_rows '${_kv%%:*}$TAB${_kv#*:}'"
  done
  if ! guest_exec_root "rm -f $S/transcript.log $S/exit $S/manifest && printf '%s\\n'$_dr_rows > $S/lane.tsv"; then
    fail_harness "could not write lane.tsv for run $_dr_n"
    return "$CLASS_HARNESS"
  fi

  # askpass.log is TRUNCATED, not removed, and by the user rather than root: the
  # helper appends as the invoking (unprivileged) user, and the judge reads the
  # file's PRESENCE as "the password axis really ran". Left in place across runs it
  # made run 2's count a re-reading of run 1 — so `it asked exactly once` passed on a
  # run that never asked at all, and would invert the moment the timing shifted.
  if [ "$GUEST_SUDO" = password ]; then
    guest_exec ": > $S/askpass.log" || {
      fail_harness "could not reset the askpass log for run $_dr_n"
      return "$CLASS_HARNESS"
    }
  fi
  # sudo -k first: a cached credential would make the askpass count lie.
  # NO_COLOR so the UI glyphs the probe parses are plain, and 2>&1 because warn()
  # writes to stderr ONLY and lib/apply.sh exits 0 even when steps warned — so the
  # verdict has to come from the text.
  # `export`, NOT a `VAR=x cmd` prefix. Measured the hard way: the entry command
  # begins `cd "$HOME" && bash …`, so an assignment prefix binds to `cd` and the
  # applier ran without it. The password axis reported "couldn't install git" and
  # asserted nothing.
  _dr_env="export NO_COLOR=1;"
  if [ "$GUEST_SUDO" = password ]; then
    # \$PATH stays unexpanded: it is the GUEST's PATH the shim goes in front of.
    _dr_env="$_dr_env export PATH=$S/bin:\$PATH;"
    _dr_env="$_dr_env export SUDO_ASKPASS=$GUEST_SRC/tests/real/bin/askpass;"
    _dr_env="$_dr_env export VIBE_REAL_DIR=$S;"
  fi

  note "run $_dr_n: $ENTRY"
  guest_exec "sudo -k >/dev/null 2>&1 || true"
  guest_exec "{ $_dr_env $ENTRY_CMD ; } > $S/transcript.log 2>&1; printf '%s\\n' \$? > $S/exit"

  if ! guest_fetch "$S/transcript.log" "$OUT/run$_dr_n.transcript"; then
    fail_harness "could not fetch the transcript for run $_dr_n"
    return "$CLASS_HARNESS"
  fi

  # Is this transcript a story about vibe, or about the world around it?
  # lib/triage.sh owns the rule and is unit-tested over transcripts; the one thing
  # worth repeating here is that a run which printed its own clean verdict is NEVER
  # triaged away, however much transport wording it survived on the way.
  triage "$OUT/run$_dr_n.transcript" "$REF"
  if [ "$TRIAGE_CLASS" != 0 ]; then
    case "$TRIAGE_CLASS" in
      "$CLASS_INFRA") fail_infra "$TRIAGE_REASON" ;;
      *)              fail_harness "$TRIAGE_REASON" ;;
    esac
    [ -n "$TRIAGE_HINT" ] && note "$TRIAGE_HINT"
    return "$TRIAGE_CLASS"
  fi

  note "run $_dr_n: probing"
  if ! guest_exec "cd \"\$HOME\" && VIBE_REAL_DIR=$S bash $GUEST_SRC/tests/real/probe.sh > $S/manifest 2> $S/probe.err"; then
    guest_fetch "$S/probe.err" "$OUT/run$_dr_n.probe.err"
    fail_harness "the probe failed in the guest (see run$_dr_n.probe.err)"
    return "$CLASS_HARNESS"
  fi
  if ! guest_fetch "$S/manifest" "$OUT/run$_dr_n.manifest"; then
    fail_harness "could not fetch the manifest for run $_dr_n"
    return "$CLASS_HARNESS"
  fi

  note "run $_dr_n: judging"
  # shellcheck disable=SC2086  # the block list is deliberately word-split
  bash "$REAL/judge.sh" "$OUT/run$_dr_n.manifest" $BLOCKS | tee "$OUT/run$_dr_n.tap"
  _dr_judge="${PIPESTATUS[0]}"
  case "$_dr_judge" in
    0) return 0 ;;
    1) return "$CLASS_ASSERT" ;;
    *) return "$CLASS_HARNESS" ;;
  esac
}

_i=1
while [ "$_i" -le "$RUNS" ]; do
  do_run "$_i"
  _rc=$?
  RUN_CLASS="$(class_worse "$RUN_CLASS" "$_rc")"
  # A harness or infrastructure failure makes every later run meaningless.
  if [ "$_rc" = "$CLASS_HARNESS" ] || [ "$_rc" = "$CLASS_INFRA" ]; then break; fi
  _i=$((_i + 1))
done

# ── Idempotence, as a differential rather than a second set of assertions ──
#
# "No new warnings, no new file changes" — NOT identical output. Unauthenticated
# runs set no git identity, so `git`'s SATISFIED_MAC stays false and the block
# legitimately re-runs; what must not change is the resulting state.

if [ "$RUNS" -ge 2 ] && [ -f "$OUT/run1.manifest" ] && [ -f "$OUT/run2.manifest" ]; then
  note "differential: run 1 vs run 2 (idempotence)"
  if manifest_diff "run 1" "$OUT/run1.manifest" "run 2" "$OUT/run2.manifest" manifest_state_subset; then
    note "  identical state"
  else
    RUN_CLASS="$(class_worse "$RUN_CLASS" "$CLASS_ASSERT")"
  fi
fi

# ── Keep the corpse when it matters ───────────────────────────────────────
#
# The bundle is written for EVERY non-zero class, not only class 1. A class 3 used to
# upload a bundle missing exactly the diagnostics the last round added, and a class 2
# uploaded nothing at all - so "which vendor URL 404'd" lived only in a step log that
# ages out, on the one class whose whole purpose is to say what upstream did.

if [ "$RUN_CLASS" != 0 ]; then
  # The environment the RUN saw, allow-listed — never a raw `env`. On the runner
  # adapter the guest IS the CI job, and .github/workflows/ci.yml uploads this bundle
  # as an artifact on failure: a public repo's artifacts are downloadable by anyone,
  # so a raw dump publishes the job's whole environment, runner-injected tokens
  # included. The allow-list is what a lane failure is actually diagnosed from.
  guest_exec 'env | grep -E "^(VIBE_[A-Z_]*|PATH|HOME|SHELL|USER|LOGNAME|LANG|LC_ALL|TERM|NO_COLOR|SUDO_ASKPASS|CI)=" | sort' \
    > "$OUT/guest.env" 2>/dev/null
  guest_fetch "$S/askpass.log" "$OUT/askpass.log" 2>/dev/null
  printf '  log bundle: %s\n' "$OUT" >&2
fi

# Only an assertion failure keeps the guest: class 2 and 3 say nothing about the
# machine, and a kept guest is a 6 GB VM or a container nobody comes back to.
if [ "$RUN_CLASS" = "$CLASS_ASSERT" ]; then
  printf '\n  lane %s FAILED (class 1: an assertion failed)\n' "$LANE" >&2
  guest_keep
  exit "$CLASS_ASSERT"
fi

cleanup

case "$RUN_CLASS" in
  0) printf '\n  lane %s passed\n' "$LANE" ;;
  "$CLASS_INFRA")   printf '\n  lane %s could not run (class 2: infrastructure)\n' "$LANE" >&2 ;;
  "$CLASS_HARNESS") printf '\n  lane %s is broken (class 3: harness bug)\n' "$LANE" >&2 ;;
esac
exit "$RUN_CLASS"
