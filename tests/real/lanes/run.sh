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

CLASS_ASSERT=1
CLASS_INFRA=2
CLASS_HARNESS=3

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

note()  { printf '  %s\n' "$1"; }
fail_infra()   { printf '\n  INFRASTRUCTURE: %s\n' "$1" >&2; }
fail_harness() { printf '\n  HARNESS BUG: %s\n' "$1" >&2; }

# ── The lane row ─────────────────────────────────────────────────────────────

LANES_TSV="$REAL/lanes.tsv"
ROW="$(awk -F'\t' -v l="$LANE" 'NR > 1 && $1 == l { print; exit }' "$LANES_TSV")"
if [ -z "$ROW" ]; then
  fail_harness "no lane '$LANE' in $LANES_TSV"
  exit "$CLASS_HARNESS"
fi
TAB="$(printf '\t')"
IFS="$TAB" read -r _lane ADAPTER IMAGE AXIS ENTRY PASTE DEPS <<< "$ROW"

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

# ── Precheck: measured BEFORE the run, once ─────────────────────────────────
#
# Written once and left in place for both runs, so `precheck.vibe_marker absent`
# keeps meaning "the guest was pristine when we started" rather than "run 2 found
# what run 1 wrote". It is what stops an axis going vacuous: a base image that starts
# shipping curl cannot silently turn the no-curl leg into a second base leg.

note "precheck..."
# The '"$S"' breaks are deliberate: the state dir is interpolated by the HOST, and
# everything else must reach the guest unexpanded.
# shellcheck disable=SC2016
PRECHECK_SCRIPT='
set -u
S='"$S"'
: > "$S/precheck.tsv"
for t in curl wget git gpg brew; do
  if command -v "$t" >/dev/null 2>&1; then v=present; else v=absent; fi
  printf "precheck.%s\t%s\n" "$t" "$v" >> "$S/precheck.tsv"
done
if sudo -n true >/dev/null 2>&1; then n=present; else n=absent; fi
printf "precheck.nopasswd\t%s\n" "$n" >> "$S/precheck.tsv"
rc="$HOME/.bashrc"
case "$(basename "${SHELL:-}")" in zsh) rc="${ZDOTDIR:-$HOME}/.zshrc" ;; esac
if [ -f "$rc" ] && grep -Fq "# >>> vibe-setup >>>" "$rc"; then m=present; else m=absent; fi
printf "precheck.vibe_marker\t%s\n" "$m" >> "$S/precheck.tsv"
'
if ! guest_exec "$PRECHECK_SCRIPT"; then
  fail_harness "the precheck script failed in the guest"
  cleanup
  exit "$CLASS_HARNESS"
fi

# The password file the askpass helper reads. Not an environment variable: sudo runs
# the helper in a context we do not fully control, and a file is one less thing that
# has to survive.
if [ "$GUEST_SUDO" = password ]; then
  guest_exec_root "printf '%s' '$GUEST_PASSWORD' > $S/password && chmod 0644 $S/password"
fi

# ── The entry point ─────────────────────────────────────────────────────────
#
# Four exist across the project (vibe, install.sh, vibe.ps1, install.ps1). `apply`
# and `install` run from the read-only clone; `paste` is the thing people actually
# paste, and it fetches `vibe` itself from the COMMIT UNDER TEST — the README's paste
# and install.sh:47 both hardcode `main` for the bootstrap and let VIBE_REF pin only
# the tarball, so pinning alone would test main's `vibe` and hand back a false green
# on any change to it.

entry_command() {
  case "$ENTRY" in
    apply)   printf 'cd %s && bash lib/apply.sh %s --yes --no-launch' "$GUEST_SRC" "$IDS" ;;
    install) printf 'cd %s && bash install.sh --yes --no-launch' "$GUEST_SRC" ;;
    paste)
      if [ -z "$REF" ]; then return 1; fi
      # shellcheck disable=SC2016  # $(…) must be evaluated in the GUEST, not here
      printf 'VIBE_REF=%s /bin/bash -c "$(curl -fsSL %s || wget -qO- %s)" _ %s --yes --no-launch' \
        "$REF" \
        "https://raw.githubusercontent.com/connorads/vibe-setup/$REF/vibe" \
        "https://raw.githubusercontent.com/connorads/vibe-setup/$REF/vibe" \
        "$IDS" ;;
    *) return 1 ;;
  esac
}

ENTRY_CMD="$(entry_command)"
if [ -z "$ENTRY_CMD" ]; then
  fail_harness "entry '$ENTRY' needs --ref <sha> (the paste cannot see an unpushed tree)"
  cleanup
  exit "$CLASS_HARNESS"
fi

# ── One run, then the probe, then the judge ─────────────────────────────────

RUN_CLASS=0

do_run() {
  _dr_n="$1"

  # lane.tsv: what only the runner knows. Rewritten per run so `run` is honest.
  guest_exec_root "rm -f $S/lane.tsv $S/transcript.log $S/exit $S/manifest"
  for _kv in "lane:$LANE" "adapter:$ADAPTER" "guest:$IMAGE" "axis:$AXIS" \
             "mode:$ENTRY" "run:$_dr_n" "blocks:$BLOCKS"; do
    guest_exec_root "printf '%s\\t%s\\n' '${_kv%%:*}' '${_kv#*:}' >> $S/lane.tsv"
  done

  # sudo -k first: a cached credential would make the askpass count lie.
  # NO_COLOR so the UI glyphs the probe parses are plain, and 2>&1 because warn()
  # writes to stderr ONLY and lib/apply.sh exits 0 even when steps warned — so the
  # verdict has to come from the text.
  _dr_env="NO_COLOR=1"
  if [ "$GUEST_SUDO" = password ]; then
    _dr_env="$_dr_env SUDO_ASKPASS=$GUEST_SRC/tests/real/bin/askpass VIBE_REAL_DIR=$S"
  fi

  note "run $_dr_n: $ENTRY"
  guest_exec "sudo -k >/dev/null 2>&1 || true"
  guest_exec "{ $_dr_env $ENTRY_CMD ; } > $S/transcript.log 2>&1; printf '%s\\n' \$? > $S/exit"

  if ! guest_fetch "$S/transcript.log" "$OUT/run$_dr_n.transcript"; then
    fail_harness "could not fetch the transcript for run $_dr_n"
    return "$CLASS_HARNESS"
  fi

  # The bootstrap failing to DELIVER vibe is infrastructure, not a vibe assertion:
  # there is no install to judge. Narrow on purpose — anything the applier itself
  # warned about stays the judge's business.
  if grep -Fq 'could not fetch' "$OUT/run$_dr_n.transcript" ||
     grep -Fq 'unexpected tarball layout' "$OUT/run$_dr_n.transcript"; then
    fail_infra "the bootstrap could not fetch vibe (ref '$REF')"
    return "$CLASS_INFRA"
  fi

  note "run $_dr_n: probing"
  if ! guest_exec "VIBE_REAL_DIR=$S bash $GUEST_SRC/tests/real/probe.sh > $S/manifest 2> $S/probe.err"; then
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
  if [ "$_rc" -ne 0 ] && [ "$_rc" -gt "$RUN_CLASS" ]; then RUN_CLASS="$_rc"; fi
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
    if [ "$RUN_CLASS" -lt "$CLASS_ASSERT" ]; then RUN_CLASS="$CLASS_ASSERT"; fi
  fi
fi

# ── Keep the corpse when it matters ───────────────────────────────────────

if [ "$RUN_CLASS" = "$CLASS_ASSERT" ]; then
  printf '\n  lane %s FAILED (class 1: an assertion failed)\n' "$LANE" >&2
  {
    printf 'lane\t%s\n' "$LANE"
    printf 'adapter\t%s\n' "$ADAPTER"
    printf 'image\t%s\n' "$IMAGE"
    printf 'axis\t%s\n' "$AXIS"
    printf 'entry\t%s\n' "$ENTRY"
    printf 'paste\t%s\n' "$IDS"
    printf 'blocks\t%s\n' "$BLOCKS"
  } > "$OUT/lane.tsv"
  guest_exec "env" > "$OUT/guest.env" 2>/dev/null
  guest_fetch "$S/askpass.log" "$OUT/askpass.log" 2>/dev/null
  printf '  log bundle: %s\n' "$OUT" >&2
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
