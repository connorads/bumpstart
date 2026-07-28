#!/usr/bin/env bash
# judge.sh: decide whether a real install worked, from a state manifest alone.
#
#   tests/real/judge.sh <manifest> <block-id>...
#
# PURE. It reads one file and prints TAP. It never looks at a machine, runs a
# binary, or touches the network — which is what makes the judgement logic
# unit-testable over fixture manifests in the fast bats suite (tests/real_judge.bats)
# instead of only being exercised by a 40-minute lane run.
#
# Scope, deliberately small: this asserts ONLY what a PATH-shadow fake structurally
# cannot reach — acquisition (a vendor installer really ran, a binary really
# executes), persistence into a fresh shell, real desktop apps, the sudo password
# prompt. Canonical assembly, section ordering, symlink mechanics, trust preseeds
# and the starter repo stay in instructions.bats / shellpath.bats / trust.bats /
# e2e.bats, which already prove them; re-asserting them here would tax every future
# block twice. Everything not asserted here is covered by the manifest
# DIFFERENTIALS the driver runs (run 1 vs run 2, apply.sh vs --paste), which need no
# second copy of the expectations.
#
# Fail closed: a manifest missing a key this lane expects is a FAILURE, never a
# skip. The plan line is emitted first, from a check list built before any check
# runs, so a truncated judgement cannot read as a pass.
#
# Exit: 0 all assertions passed · 1 an assertion failed (vibe is wrong) ·
#       3 harness bug (no manifest, no checks, blocks disagree with the manifest).
#
# bash-3.2-clean: no associative arrays, no mapfile. No `set -e` — every assertion
# is an explicit if/else, because a non-final `[[ ]]` failure does not trip errexit
# under 3.2, so an errexit-dependent assertion would silently pass.

HERE="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/real/lib/tap.sh
. "$HERE/lib/tap.sh"

TAB="$(printf '\t')"
# shellcheck disable=SC2016  # a literal, not an expansion: the probe normalises $HOME
CANON='$HOME/.agents/AGENTS.md'

usage() { printf 'usage: judge.sh <manifest> <block-id>...\n' >&2; }

MANIFEST="${1:-}"
[ $# -ge 1 ] && shift
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  printf 'judge: no such manifest: %s\n' "${MANIFEST:-<none>}" >&2
  usage
  exit 3
fi
if [ $# -eq 0 ]; then
  printf 'judge: no expected blocks given\n' >&2
  usage
  exit 3
fi

BLOCK_LIST="$*"
BLOCKS=" $BLOCK_LIST "

# ── Manifest access ───────────────────────────────────────────────────────────
#
# One in-memory copy, so derived facts can be appended and read back through the
# same lookup as the probe's own keys. Values never contain a tab (the probe
# guarantees it), so field 2 is the whole value.

ALL="$(cat "$MANIFEST")"

_lookup() {
  printf '%s\n' "$ALL" | awk -F'\t' -v k="$1" '$1 == k { print $2; found = 1; exit } END { exit !found }'
}
mget()    { _lookup "$1" || true; }
mhas()    { _lookup "$1" >/dev/null 2>&1; }
mderive() { ALL="$ALL
$1$TAB$2"; }

# ── Harness self-check (exit class 3 — the harness, not vibe) ─────────────────

if mhas blocks; then
  if [ "$(mget blocks)" != "$BLOCK_LIST" ]; then
    printf 'judge: manifest blocks [%s] disagree with the expected list [%s]\n' \
      "$(mget blocks)" "$BLOCK_LIST" >&2
    exit 3
  fi
fi

OS="$(mget os)"
case "$OS" in
  mac|linux|win) : ;;
  *) printf 'judge: manifest has no usable os key (got [%s])\n' "$OS" >&2; exit 3 ;;
esac

AXIS="$(mget axis)"

has_block() {
  case "$BLOCKS" in *" $1 "*) return 0 ;; esac
  return 1
}

# ── Derived: which tools this plan should have really installed ───────────────
#
# Read off the RESOLVED block list, so a preset gaining a tool is covered with no
# edit here. mise is unconditional on Linux (ensure_mise runs pre-loop, ahead of
# the block whose INCLUDE would otherwise pull it in).

EXPECT_TOOLS=""
_want_tool() {
  case " $EXPECT_TOOLS " in *" $1 "*) return 0 ;; esac
  EXPECT_TOOLS="$EXPECT_TOOLS $1"
}
has_block claude-cli && _want_tool claude
has_block codex-cli  && _want_tool codex
has_block gh-auth    && _want_tool gh
has_block git        && _want_tool git
has_block node       && _want_tool node
has_block pnpm       && _want_tool pnpm
# mise has no *_WIN cells, so it is a silent no-op on Windows however it got into the
# plan (node and pnpm both INCLUDE it). Unconditional on Linux, where ensure_mise runs
# pre-loop, ahead of the block whose INCLUDE would otherwise pull it in.
if [ "$OS" != win ]; then
  has_block mise && _want_tool mise
  [ "$OS" = linux ] && _want_tool mise
fi

# ── Derived: which warnings are LEGITIMATE on this machine ────────────────────
#
# Derived from what the probe observed, never a blind allow-list. A lane that
# tolerated "any warning" would be blind to the exact failure mode this assertion
# exists to catch: a block that warns and still `exit 0`s, leaving the run's own
# verdict a green "Setup complete."

WARN_ALLOW=""
_allow_warn() { WARN_ALLOW="$WARN_ALLOW
$1"; }

# claude-desktop ships only from Anthropic's apt repository, so a machine with no
# apt-get warns and skips (Fedora, Arch).
if [ "$OS" = linux ] && has_block claude-desktop && [ "$(mget env.pkg.apt)" != 1 ]; then
  _allow_warn "*only ships for Debian/Ubuntu*"
fi
# Codex's bubblewrap sandbox needs an unprivileged user namespace. Ubuntu 24.04
# ships apparmor_restrict_unprivileged_userns=1, so a non-root lane there warns.
USERNS="$(mget env.userns.restricted)"
USERNS_WARN_DUE=0
if [ "$OS" = linux ] && has_block codex-cli && [ "$(mget env.root)" = 0 ] \
  && [ -n "$USERNS" ] && [ "$USERNS" != none ]; then
  USERNS_WARN_DUE=1
  _allow_warn "*sandbox can't start here*"
fi

warn_allowed() {
  _wa_text="$1"
  _wa_ifs="$IFS"
  IFS='
'
  # shellcheck disable=SC2086  # deliberate word-split of the newline-separated globs
  set -- $WARN_ALLOW
  IFS="$_wa_ifs"
  for _wa_pat in "$@"; do
    [ -n "$_wa_pat" ] || continue
    # shellcheck disable=SC2254  # the allow-list entries ARE globs, deliberately
    case "$_wa_text" in $_wa_pat) return 0 ;; esac
  done
  return 1
}

UNEXPECTED=0
UNEXPECTED_LIST=""
while IFS="$TAB" read -r _k _v; do
  case "$_k" in warn.*) ;; *) continue ;; esac
  if warn_allowed "$_v"; then continue; fi
  UNEXPECTED=$((UNEXPECTED + 1))
  UNEXPECTED_LIST="$UNEXPECTED_LIST
unexpected warning: $_v"
done <<< "$ALL"
mderive derived.unexpected_warnings "$UNEXPECTED"

# When the userns warning is legitimate, the FIX printed alongside it has to match
# the knob this kernel actually has — the AppArmor sysctl on a kernel that only has
# unprivileged_userns_clone sends the user to a file that changes nothing.
if [ "$USERNS_WARN_DUE" -eq 1 ]; then
  case "$USERNS" in
    apparmor) _fix_pat="*kernel.apparmor_restrict_unprivileged_userns = 0*" ;;
    clone)    _fix_pat="*kernel.unprivileged_userns_clone = 1*" ;;
    *)        _fix_pat="*blocks unprivileged user namespaces*" ;;
  esac
  _fix_seen=0
  while IFS="$TAB" read -r _k _v; do
    case "$_k" in info.*) ;; *) continue ;; esac
    # shellcheck disable=SC2254  # a glob, deliberately
    case "$_v" in $_fix_pat) _fix_seen=1 ;; esac
  done <<< "$ALL"
  mderive derived.userns_fix_printed "$_fix_seen"
fi

# askpass: the log exists only on a lane that exported SUDO_ASKPASS, so its very
# presence is what says the password axis really ran.
if mhas askpass.count; then
  if [ "$(mget askpass.count)" -ge 1 ] 2>/dev/null; then
    mderive derived.askpass_fired 1
  else
    mderive derived.askpass_fired 0
  fi
fi

# ── The check list. Built in full BEFORE anything is emitted, so 1..N is honest ─
#
# One record per assertion: <op> <key> <expected> <description>.
#   eq       manifest[key] == expected
#   present  key exists with a non-empty value
#   match    manifest[key] matches the glob in expected
#   eq_todo  like eq, but a MISMATCH is an accepted, documented gap (# TODO)
# A key the manifest does not carry at all always fails, eq_todo included: a gap we
# accepted is not the same thing as a measurement that never happened.

CHECKS=""
# The expected value is never empty, even for the ops that ignore it: tab is IFS
# whitespace, so `read` collapses a `\t\t` run and an empty field would silently
# shift the description into it.
add_check() {
  _ac_exp="$3"
  [ -n "$_ac_exp" ] || _ac_exp='-'
  CHECKS="$CHECKS$1$TAB$2$TAB$_ac_exp$TAB$4
"
}

# 1. Pristine, and the axis is not vacuous ------------------------------------
add_check eq precheck.vibe_marker absent \
  "the guest had no vibe PATH marker before the first run"
case "$AXIS" in
  *no-curl*) add_check eq precheck.curl absent \
    "the no-curl axis really has no curl (else the wget fallback is untested)" ;;
esac
case "$AXIS" in
  *no-git*) add_check eq precheck.git absent \
    "the no-git axis really has no git" ;;
esac
if [ "$OS" != win ]; then
  add_check eq env.root 0 \
    "the run was NOT root (root skips every sudo path, making them vacuous)"
fi

# 2. The verdict, and the warnings behind it ----------------------------------
add_check eq transcript.exit 0 "the applier exited 0"
add_check eq transcript.verdict clean \
  "the run's own verdict is a clean 'Setup complete.'"
add_check eq derived.unexpected_warnings 0 \
  "no warning outside the ones this machine legitimately produces"
if [ "$USERNS_WARN_DUE" -eq 1 ]; then
  add_check eq derived.userns_fix_printed 1 \
    "the userns warning printed the fix for the knob this kernel has"
fi

# 3. Every installed tool's binary actually RUNS ------------------------------
# `--version` exiting 0, not `command -v`: the faked suite's claude IS a stub, so
# "a binary that executes" is the whole point here — and it catches a wrong-arch
# install, which a path lookup cannot see.
# shellcheck disable=SC2086  # deliberate word-split of the tool list
set -- $EXPECT_TOOLS
for _t in "$@"; do
  add_check eq "tool.$_t.runs" 1 "$_t --version runs"
done

# 4. A FRESH shell finds them -------------------------------------------------
# The single most valuable assertion in the harness: the installing shell is green
# either way, because fixup_path put the dirs on PATH for the run.
if [ "$OS" = win ]; then
  # The User-scope registry PATH, never $env:PATH — the harness's own $GITHUB_PATH
  # additions would mask a missing entry and make this vacuous.
  for _t in "$@"; do
    add_check eq "shell.regpath.$_t" 1 "$_t resolves from the User registry PATH"
  done
else
  for _t in "$@"; do
    add_check eq "shell.lic.$_t" 1 "$_t resolves in a fresh interactive login shell"
    add_check eq "shell.ic.$_t" 1 "$_t resolves in a fresh interactive shell"
    add_check eq_todo "shell.lc.$_t" 1 "$_t resolves in a non-interactive login shell"
  done
fi

# 5. vibe is the ONLY thing that wrote to PATH -------------------------------
# A design claim nothing else covers: fixup_path runs before the block loop so
# Codex's installer skips its own rc block, and ensure_mise passes
# MISE_INSTALL_HELP=0 to suppress mise's epilogue. Two tools both claiming the edit
# is how a beginner ends up with the line twice.
if [ "$OS" != win ]; then
  add_check eq rc.marker_count 1 "the vibe PATH marker appears exactly once"
  add_check eq rc.vendor_path_lines 0 \
    "no vendor-authored PATH edit sits beside vibe's"
  add_check match rc.block '*mise/shims*' "the persisted line carries vibe's install dirs"
fi

# 6. The desktop apps are really there ---------------------------------------
if has_block claude-desktop; then
  case "$OS" in
    mac) add_check eq app.claude 1 "/Applications/Claude.app is installed" ;;
    win) add_check eq app.claude 1 "winget lists Anthropic.Claude" ;;
    linux)
      if [ "$(mget env.pkg.apt)" = 1 ]; then
        add_check eq app.claude-desktop 1 "claude-desktop is installed from the apt repository"
      else
        add_check eq app.claude-desktop 0 "claude-desktop is correctly absent (no apt-get here)"
      fi ;;
  esac
fi
if has_block github-desktop; then
  case "$OS" in
    mac|win) add_check eq app.github-desktop 1 "GitHub Desktop is installed" ;;
  esac
fi
if has_block codex-desktop; then
  case "$OS" in
    mac|win) add_check eq app.chatgpt 1 "the ChatGPT app is installed" ;;
  esac
fi

# 7. safer-installs is configured where the tools read it --------------------
# Configured, note — NOT that it protected this run: the gate lands after the tools
# it should gate (ADR 0002).
# Windows excluded: the block ships no apply.ps1, so Test-BlockRuns drops it from the
# plan there and nothing is configured. Asserting the keys would be asserting a
# feature that does not exist yet on that spine.
if has_block safer-installs && [ "$OS" != win ]; then
  add_check eq npmrc.min-release-age 4 "npm waits 4 days on a new release"
  add_check eq npmrc.allow-git none "npm refuses a git dependency"
  add_check eq npmrc.allow-remote none "npm refuses a bare-tarball dependency"
  add_check eq mise.minimum_release_age 4d "mise waits 4 days on a new tool release"
  if has_block pnpm; then
    add_check present pnpm.config - "pnpm's config is at the path pnpm itself resolves"
    add_check eq pnpm.minimumReleaseAge 5760 "pnpm waits 4 days (5760 minutes)"
    add_check eq pnpm.minimumReleaseAgeStrict true "pnpm's wait fails closed"
  fi
fi

# 8. The sudo password prompt -------------------------------------------------
#
# Run-aware, because the promise is "it asks once, and only if git needs installing"
# — so the SECOND run's honest claim is the opposite one. Run 1 installs git and must
# ask exactly once; run 2 finds git present, does no privileged work, and must not
# ask again. Asserting "exactly once" on both is what a shared askpass log made look
# true. An absent or unreadable `run` key takes the stricter branch: a measurement
# that never happened is not a licence to expect nothing.
case "$AXIS" in
  *password-sudo*)
    case "$(mget run)" in
      ''|1)
        add_check eq derived.askpass_fired 1 \
          "sudo really asked for a password (an empty log means NOPASSWD leaked in)"
        add_check eq askpass.count 1 "it asked exactly once, as the README promises" ;;
      *)
        add_check eq askpass.count 0 \
          "the second run had nothing privileged left to do, so it did not ask again" ;;
    esac ;;
esac

# 9. Instructions, sampled ---------------------------------------------------
add_check eq instructions.canonical.nonempty 1 "the canonical instructions file is non-empty"
if has_block claude-cli; then
  case "$OS" in
    win) add_check eq instructions.link.claude "import:$CANON" \
      "Claude's own path imports the canonical file" ;;
    *)   add_check eq instructions.link.claude "symlink:$CANON" \
      "Claude's own path resolves to the canonical file" ;;
  esac
fi
if has_block codex-cli; then
  case "$OS" in
    win) add_check eq instructions.link.codex copy:current \
      "Codex's own path is a current copy of the canonical file" ;;
    *)   add_check eq instructions.link.codex "symlink:$CANON" \
      "Codex's own path resolves to the canonical file" ;;
  esac
fi
# One spot-check per shipped tool section — that guidance for what was installed
# reached the file. Ordering and assembly stay instructions.bats territory.
has_block git  && add_check eq instructions.section.git 1 "the git guidance is in the file"
has_block node && add_check eq instructions.section.node 1 "the Node.js guidance is in the file"

# ── Emit ─────────────────────────────────────────────────────────────────────

N=0
if [ -n "$CHECKS" ]; then
  N="$(printf '%s' "$CHECKS" | grep -c '')"
fi
if [ "$N" -eq 0 ]; then
  printf 'judge: no checks were planned — a lane that asserts nothing cannot pass\n' >&2
  exit 3
fi

tap_plan "$N"
diag "lane $(mget lane) · os $OS · axis ${AXIS:-base} · mode $(mget mode) · run $(mget run)"
diag "blocks: $BLOCK_LIST"
diag "verdict: $(mget transcript.verdict) (exit $(mget transcript.exit), $(mget transcript.warn_count) warning lines)"
if mhas askpass.count; then diag "askpass invocations: $(mget askpass.count)"; fi

while IFS="$TAB" read -r op key exp desc; do
  [ -n "$op" ] || continue
  have=0
  got=""
  if mhas "$key"; then have=1; got="$(mget "$key")"; fi

  if [ "$have" -eq 0 ]; then
    not_ok "$desc" "the manifest has no key '$key' — nothing was measured"
    continue
  fi

  case "$op" in
    eq)
      if [ "$got" = "$exp" ]; then ok "$desc"
      else not_ok "$desc" "$key: got [$got] want [$exp]"; fi ;;
    present)
      if [ -n "$got" ]; then ok "$desc"
      else not_ok "$desc" "$key is empty"; fi ;;
    match)
      # shellcheck disable=SC2254  # the `match` op's expected value IS a glob
      case "$got" in
        $exp) ok "$desc" ;;
        *)    not_ok "$desc" "$key: got [$got] want match [$exp]" ;;
      esac ;;
    eq_todo)
      if [ "$got" = "$exp" ]; then ok "$desc"
      else todo "$desc" "known gap: $key is [$got], want [$exp]"; fi ;;
    *)
      not_ok "$desc" "judge bug: unknown op [$op]" ;;
  esac
done <<< "$CHECKS"

if [ "$UNEXPECTED" -gt 0 ]; then
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    diag "$_line"
  done <<< "$UNEXPECTED_LIST"
fi
if [ "$TAP_TODO" -gt 0 ]; then
  diag "$TAP_TODO accepted known gap(s) — see the TODO lines above"
fi

if [ "$TAP_N" -ne "$N" ]; then
  printf 'judge: planned %s assertions but emitted %s\n' "$N" "$TAP_N" >&2
  exit 3
fi
if [ "$TAP_FAIL" -gt 0 ]; then
  diag "$TAP_FAIL assertion(s) failed"
  exit 1
fi
exit 0
