#!/usr/bin/env bash
# probe.sh: run INSIDE a guest after a real install and print a state manifest.
#
#   VIBE_REAL_DIR=/tmp/vibe-real tests/real/probe.sh > manifest
#
# It gathers and normalises; it judges NOTHING. That split is what lets judge.sh be
# pure and unit-tested over fixtures, and it means "is this state correct" changes in
# one place while "what is the state" changes here.
#
# The manifest is `key<TAB>value`, one line per fact, values single-line and
# tab-free, with `$HOME` normalised out — because the host driver compares manifests
# ACROSS runs (idempotence), across entry points (apply.sh vs the real paste) and
# across distros, and a raw home path would make every comparison fail for the wrong
# reason. The guest's hostname is pinned by the adapter rather than normalised here:
# substituting a short container id out of every value would also rewrite it out of
# the middle of a sha256.
#
# Two kinds of key, deliberately:
#   the state subset  (path.* rc.* tool.*.runs shell.* app.* npmrc.* mise.* pnpm.*
#                      instructions.*) — stable across runs, so the differential
#                      can compare it byte for byte
#   the record        (transcript.* warn.* info.* error.* tool.*.version_raw) —
#                      legitimately differs between runs, excluded from the diff
#
# The lane runner hands us what only it knows, in $VIBE_REAL_DIR:
#   lane.tsv      lane / adapter / guest / axis / mode / run / blocks
#   precheck.tsv  facts measured BEFORE the run (curl absent, no vibe marker, …)
#   transcript.log  the run's combined stdout AND stderr — warn() writes to stderr
#                   only, and lib/apply.sh exits 0 even when steps warned, so the
#                   verdict has to come from the text, not the status
#   exit          the run's exit status
#   askpass.log   one line per sudo password prompt (password axis only)
#
# bash-3.2-clean (the macOS guest's /bin/bash): no associative arrays, no mapfile,
# no ${v,,}. Deliberately NOT `set -e`: a probe that dies half-way would emit a
# partial manifest, and the judge would then report "no key" for everything after
# the failure instead of one honest error. It reports what it can and says what it
# could not measure.

STATE="${VIBE_REAL_DIR:-/tmp/vibe-real}"

# ── Emitters ──────────────────────────────────────────────────────────────────

# Home is normalised to the literal string $HOME. sed's replacement needs the
# dollar escaped inside double quotes; the delimiter is | because a home path
# never contains one.
_norm() {
  printf '%s' "$1" \
    | tr '\t\n\r' '   ' \
    | sed -e "s|$HOME|\\\$HOME|g" \
    | sed -e 's/[[:space:]]*$//'
}

emit() { printf '%s\t%s\n' "$1" "$(_norm "$2")"; }

# ── What only the runner knows ────────────────────────────────────────────────

printf '# vibe real-install state manifest\n'
emit manifest_version 1

for _pass in lane precheck; do
  if [ -f "$STATE/$_pass.tsv" ]; then
    while IFS= read -r _line; do
      [ -n "$_line" ] || continue
      case "$_line" in \#*) continue ;; esac
      printf '%s\n' "$_line"
    done < "$STATE/$_pass.tsv"
  else
    emit "probe.missing.$_pass" 1
  fi
done

# ── The machine ───────────────────────────────────────────────────────────────
#
# os is MEASURED here rather than taken from lane.tsv: a lane that mislabelled its
# own guest would otherwise pick the wrong half of the judge's OS branches.

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *)      OS=other ;;
esac
emit os "$OS"

if [ "$(id -u)" -eq 0 ]; then emit env.root 1; else emit env.root 0; fi

WHOAMI="$(id -un)"
LOGIN_SHELL="${SHELL:-/bin/sh}"
SHELL_KIND="$(basename "$LOGIN_SHELL")"
emit env.login_shell "$SHELL_KIND"

for _pm in apt-get dnf pacman zypper; do
  _key="$(printf '%s' "$_pm" | sed 's/-get$//')"
  if command -v "$_pm" >/dev/null 2>&1; then emit "env.pkg.$_key" 1; else emit "env.pkg.$_key" 0; fi
done

# The unprivileged-userns knob, read the same way blocks/codex-cli/apply.sh reads it
# — so the judge can expect the MATCHING warning and fix rather than tolerating any
# warning at all.
USERNS=none
if [ "$OS" = linux ]; then
  _apparmor=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
  _clone=/proc/sys/kernel/unprivileged_userns_clone
  if [ -r "$_apparmor" ] && [ "$(cat "$_apparmor" 2>/dev/null)" = 1 ]; then
    USERNS=apparmor
  elif [ -r "$_clone" ] && [ "$(cat "$_clone" 2>/dev/null)" = 0 ]; then
    USERNS=clone
  elif command -v bwrap >/dev/null 2>&1 &&
       ! bwrap --dev-bind / / --unshare-net true >/dev/null 2>&1; then
    USERNS=other
  fi
fi
emit env.userns.restricted "$USERNS"

# ── The transcript: the verdict, and every warning behind it ──────────────────

if [ -f "$STATE/exit" ]; then
  emit transcript.exit "$(cat "$STATE/exit" 2>/dev/null)"
else
  emit probe.missing.exit 1
fi

LOG="$STATE/transcript.log"
if [ -f "$LOG" ]; then
  # Three outcomes, not two. `ensure_brew` has no failure handling, so under set -e a
  # failed Homebrew install aborts the applier with NO verdict line at all — that is
  # its own outcome, not a variant of "warned".
  if grep -Fq 'Setup complete.' "$LOG"; then
    emit transcript.verdict clean
  elif grep -Fq 'Setup finished, but' "$LOG"; then
    emit transcript.verdict warned
  else
    emit transcript.verdict aborted
  fi

  # The UI glyphs are the channel marker: warn() is "  ! ", info() "  › ",
  # error() "  ✗ ". NO_COLOR is set by the runner, so these are plain.
  _n=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _n=$((_n + 1))
    emit "$(printf 'warn.%04d' "$_n")" "$_line"
  done <<EOF
$(sed -n 's/^  ! //p' "$LOG")
EOF
  emit transcript.warn_count "$_n"

  _n=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _n=$((_n + 1))
    emit "$(printf 'info.%04d' "$_n")" "$_line"
  done <<EOF
$(sed -n 's/^  › //p' "$LOG")
EOF

  _n=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _n=$((_n + 1))
    emit "$(printf 'error.%04d' "$_n")" "$_line"
  done <<EOF
$(sed -n 's/^  ✗ //p' "$LOG")
EOF
else
  emit probe.missing.transcript 1
fi

# ── Every installed tool's binary really RUNS ────────────────────────────────
#
# On vibe's own PATH, not a fresh shell's: this asks "did acquisition work", which
# is a different question from "does a new terminal find it" below. `--version`
# rather than `command -v`, because the faked suite's `claude` IS a stub — a binary
# that executes is the whole point here, and it catches a wrong-arch install too.

PROBE_PATH="$HOME/.local/bin:$HOME/.codex/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
[ -d /opt/homebrew/bin ] && PROBE_PATH="/opt/homebrew/bin:$PROBE_PATH"
[ -d /usr/local/bin ] && PROBE_PATH="$PROBE_PATH:/usr/local/bin"

for _t in claude codex gh git node pnpm mise; do
  if _out="$(PATH="$PROBE_PATH" "$_t" --version 2>&1)"; then
    emit "tool.$_t.runs" 1
    emit "tool.$_t.version_raw" "$_out"
  else
    emit "tool.$_t.runs" 0
    emit "tool.$_t.version_raw" absent
  fi
done

# ── A FRESH shell finds them ─────────────────────────────────────────────────
#
# The single most valuable measurement here: the installing shell is green either
# way, because fixup_path put the dirs on PATH for the run. `env -i` so the guest's
# own startup files are the ONLY source of PATH — inheriting ours would make this
# vacuous.
#
# Three invocations, because they source three different things and one assertion
# cannot see all three:
#   -lic  login + interactive  → ~/.profile, which sources ~/.bashrc
#   -ic   interactive          → ~/.bashrc
#   -lc   login only           → ~/.profile, and Debian/Ubuntu's ~/.bashrc returns
#                                early for a non-interactive shell, so vibe's line
#                                is invisible here. Reported, not fixed.

emit shell.kind "$SHELL_KIND"
case "$SHELL_KIND" in
  bash|zsh) emit shell.supported 1 ;;
  *)        emit shell.supported 0 ;;
esac

_fresh() {
  # _fresh <flags> <tool> — 1 when a shell started with <flags> resolves <tool>.
  case "$SHELL_KIND" in bash|zsh) : ;; *) printf '0'; return 0 ;; esac
  if env -i HOME="$HOME" USER="$WHOAMI" SHELL="$LOGIN_SHELL" TERM=dumb \
      "$LOGIN_SHELL" "$1" "command -v $2 >/dev/null 2>&1" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

for _t in claude codex gh git node pnpm mise; do
  emit "shell.lic.$_t" "$(_fresh -lic "$_t")"
  emit "shell.ic.$_t"  "$(_fresh -ic "$_t")"
  emit "shell.lc.$_t"  "$(_fresh -lc "$_t")"
done

# ── vibe is the only thing that wrote to PATH ────────────────────────────────
#
# persist_path keys on `basename $SHELL`, so the rc file is found the same way it
# was written. The marker must appear exactly once, and no VENDOR-authored PATH edit
# may sit beside it: fixup_path runs before the block loop so Codex's installer
# skips its own rc block, and ensure_mise passes MISE_INSTALL_HELP=0 to suppress
# mise's epilogue. A distro's own /etc/skel PATH lines (Fedora's ~/.bashrc has one)
# are NOT vendor edits and must not count — hence signature matching on the dirs
# vibe's tools install into, not on the word PATH.

case "$SHELL_KIND" in
  zsh)  RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash) RC="$HOME/.bashrc" ;;
  fish) RC="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
  *)    RC="" ;;
esac
emit rc.file "${RC:-none}"

if [ -n "$RC" ] && [ -f "$RC" ]; then
  _markers="$(grep -Fc '# >>> vibe-setup >>>' "$RC" 2>/dev/null)"
  [ -n "$_markers" ] || _markers=0
  emit rc.marker_count "$_markers"
  emit rc.block "$(awk '
    /^# >>> vibe-setup >>>$/ { inblock = 1; next }
    /^# <<< vibe-setup <<<$/ { inblock = 0; next }
    inblock && !done { print; done = 1 }' "$RC")"

  _vendor="$(awk '
    /^# >>> vibe-setup >>>$/ { inblock = 1; next }
    /^# <<< vibe-setup <<<$/ { inblock = 0; next }
    inblock { next }
    /mise activate|mise\/shims|\.codex\/bin|\.local\/share\/mise/ { print }' "$RC")"
  _n=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _n=$((_n + 1))
    emit "$(printf 'rc.vendor.%04d' "$_n")" "$_line"
  done <<EOF
$_vendor
EOF
  emit rc.vendor_path_lines "$_n"
else
  emit rc.marker_count 0
  emit rc.block absent
  emit rc.vendor_path_lines 0
fi

# ── Desktop apps, by the same names the CHECK cells use ─────────────────────

case "$OS" in
  mac)
    for _pair in 'claude:Claude.app' 'github-desktop:GitHub Desktop.app' 'chatgpt:ChatGPT.app'; do
      _k="${_pair%%:*}"
      _bundle="${_pair#*:}"
      if [ -d "/Applications/$_bundle" ]; then emit "app.$_k" 1; else emit "app.$_k" 0; fi
    done ;;
  linux)
    if PATH="$PROBE_PATH" command -v claude-desktop >/dev/null 2>&1; then
      emit app.claude-desktop 1
    else
      emit app.claude-desktop 0
    fi ;;
esac

# ── safer-installs, at the paths the tools themselves read ──────────────────
#
# Always emitted, `absent` when unset: "the key is not there" is a far more useful
# diagnostic than a key the judge reports as unmeasured.

# _kv <file> <separator> <key> — the first value for <key>, trimmed and unquoted,
# or the literal `absent`. One reader for all three formats: npm's `k=v`, mise's
# `k = "v"` and pnpm's `k: v`. `absent` rather than an empty value, because "the key
# is not there" is a far better diagnostic than a key the judge calls unmeasured.
_kv() {
  if [ ! -f "$1" ]; then printf 'absent'; return 0; fi
  awk -F"$2" -v k="$3" '
    { key = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", key) }
    key == k {
      v = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v)
      print v; found = 1; exit
    }
    END { if (!found) print "absent" }' "$1"
}

NPMRC="$HOME/.npmrc"
emit npmrc.min-release-age "$(_kv "$NPMRC" = min-release-age)"
emit npmrc.allow-git       "$(_kv "$NPMRC" = allow-git)"
emit npmrc.allow-remote    "$(_kv "$NPMRC" = allow-remote)"

MISE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"
emit mise.minimum_release_age "$(_kv "$MISE_CFG" = minimum_release_age)"

# pnpm resolves its global config the same three ways the block does, and writing
# the wrong one is worse than writing nothing — so read it the way pnpm would.
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
  PNPM_CFG="$XDG_CONFIG_HOME/pnpm/config.yaml"
elif [ "$OS" = mac ]; then
  PNPM_CFG="$HOME/Library/Preferences/pnpm/config.yaml"
else
  PNPM_CFG="$HOME/.config/pnpm/config.yaml"
fi
if [ -f "$PNPM_CFG" ]; then emit pnpm.config "$PNPM_CFG"; else emit pnpm.config absent; fi
emit pnpm.minimumReleaseAge       "$(_kv "$PNPM_CFG" : minimumReleaseAge)"
emit pnpm.minimumReleaseAgeStrict "$(_kv "$PNPM_CFG" : minimumReleaseAgeStrict)"

# ── The sudo password prompt ────────────────────────────────────────────────
#
# The log exists only where the runner exported SUDO_ASKPASS, so its presence is
# what tells the judge the password axis really ran. Zero entries means sudo never
# consulted it — a NOPASSWD rule leaked in, or the user was root.

if [ -f "$STATE/askpass.log" ]; then
  _n=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _n=$((_n + 1))
    emit "$(printf 'askpass.%04d' "$_n")" "$_line"
  done < "$STATE/askpass.log"
  emit askpass.count "$_n"
fi

# ── Instructions, sampled ───────────────────────────────────────────────────

CANON="$HOME/.agents/AGENTS.md"
emit instructions.canonical "$CANON"
if [ -s "$CANON" ]; then emit instructions.canonical.nonempty 1; else emit instructions.canonical.nonempty 0; fi

_sha() {
  if [ ! -f "$1" ]; then printf 'absent'; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else
    printf 'nosha'
  fi
}
emit instructions.canonical.sha256 "$(_sha "$CANON")"

# _link_state <path> — what a harness's own instructions path actually IS.
# symlink:<target> is the POSIX answer; Windows has no symlink here and is probed by
# probe.ps1 (import line / physical copy) instead.
_link_state() {
  if [ -L "$1" ]; then
    printf 'symlink:%s' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'file:%s' "$(_sha "$1")"
  else
    printf 'absent'
  fi
}
emit instructions.link.claude "$(_link_state "$HOME/.claude/CLAUDE.md")"
emit instructions.link.codex  "$(_link_state "$HOME/.codex/AGENTS.md")"

# One spot-check per shipped tool section: that guidance for what was installed
# reached the file. Ordering and assembly stay instructions.bats territory.
if [ -f "$CANON" ] && grep -Fq '## Saving your work (git)' "$CANON"; then
  emit instructions.section.git 1
else
  emit instructions.section.git 0
fi
if [ -f "$CANON" ] && grep -Fq '## Node.js' "$CANON"; then
  emit instructions.section.node 1
else
  emit instructions.section.node 0
fi

# ── Every vibe-owned path, hashed: the differential's raw material ──────────
#
# Narrow and explicit, not a sweep of $HOME: mise and the agent CLIs write caches
# and state that change on every run, and a differential over those would be red
# forever. These are the paths vibe itself creates or edits.

_path_state() {
  if [ -L "$1" ]; then
    printf 'symlink:%s' "$(readlink "$1")"
  elif [ -d "$1" ]; then
    printf 'dir'
  elif [ -f "$1" ]; then
    printf 'file:%s' "$(_sha "$1")"
  else
    printf 'absent'
  fi
}

emit path.rc           "$(_path_state "${RC:-/nonexistent}")"
emit path.agents       "$(_path_state "$CANON")"
emit path.claude-md    "$(_path_state "$HOME/.claude/CLAUDE.md")"
emit path.claude-json  "$(_path_state "$HOME/.claude.json")"
emit path.codex-agents "$(_path_state "$HOME/.codex/AGENTS.md")"
emit path.codex-config "$(_path_state "$HOME/.codex/config.toml")"
emit path.npmrc        "$(_path_state "$NPMRC")"
emit path.mise-config  "$(_path_state "$MISE_CFG")"
emit path.pnpm-config  "$(_path_state "$PNPM_CFG")"
emit path.starter      "$(_path_state "$HOME/git/first-project")"
emit path.starter-git  "$(_path_state "$HOME/git/first-project/.git")"

exit 0
