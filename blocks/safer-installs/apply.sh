#!/usr/bin/env bash
set -euo pipefail
#
# safer-installs: turn on the package managers' own release-age gates, so a
# freshly published (possibly hijacked) version has to wait before it can reach
# this machine. Every recent npm worm was caught within days of publication, so a
# few days of patience is most of the defence a beginner can get for free.
#
# A script tail rather than an INSTALL_MAC cell for two reasons: a meta cell is
# single-quoted, so it cannot contain a single quote at all, and idempotent
# multi-line config editing needs real control flow. Precedent: blocks/git/apply.sh.
#
# What is deliberately NOT here:
#   ignore-scripts=true — it removes a trigger, not a capability, and the
#     native-module build failure it causes ("gyp ERR!") is unreadable to a
#     beginner. The content.md teaches what to do when a gate fires instead.
#   osv-scanner — the detective layer. It answers "is this known-bad now", which
#     needs re-running over time, not a one-shot setup step.
#
# Check-then-act throughout: a key the user already set is never rewritten, and a
# file they own is only ever appended to. Non-fatal — a config we can't write
# warns and the setup continues.

# shellcheck source=lib/common.sh
. "$BUMP_LIB/common.sh"
# os.sh for bump_os: pnpm's global config dir is platform-dependent, and reading
# the OS through the seam (rather than uname) is what makes that branch testable.
# shellcheck source=lib/os.sh
. "$BUMP_LIB/os.sh"

# The one wait, spelled once per tool in each tool's own unit. Kept adjacent so a
# drift test can normalise them (tests/safer_installs.bats).
DAYS=4
NPM_AGE=4          # npm: days
MISE_AGE='4d'      # mise: duration string
PNPM_AGE=5760      # pnpm: minutes (4 * 24 * 60)

# _append_line <file> <line> — append, first making sure the file ends in a
# newline so we never concatenate onto a line the user wrote.
_append_line() {
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then
    printf '\n' >> "$1"
  fi
  printf '%s\n' "$2" >> "$1"
}

# ── npm ───────────────────────────────────────────────────────────────────────
# node@lts is Node 24, which bundles npm 11.16 — npm 12's hardened defaults do
# not apply, so every key is set explicitly. min-release-age is the age gate;
# allow-git and allow-remote close the two dependency routes that can execute
# code even with lifecycle scripts off.
NPMRC="$HOME/.npmrc"

_npmrc_set() {
  if grep -qs "^$1=" "$NPMRC"; then
    success "npm already sets $1"
    return 0
  fi
  if _append_line "$NPMRC" "$1=$2"; then
    success "$3"
  else
    warn "couldn't write $NPMRC — continuing"
  fi
  return 0
}

_npmrc_set min-release-age "$NPM_AGE" \
  "npm waits $DAYS days before installing a brand-new package version"
_npmrc_set allow-git none \
  "npm won't install a dependency straight from a git repo"
_npmrc_set allow-remote none \
  "npm won't install a dependency from a bare tarball URL"

# ── mise ──────────────────────────────────────────────────────────────────────
# The same wait for the tools mise installs. Edited by hand rather than via
# `mise settings set`, which round-trips the whole file; an insert under the
# existing [settings] header leaves every other line byte-identical.
MISE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"

if grep -qs '^[[:space:]]*minimum_release_age' "$MISE_CFG"; then
  success "mise already waits before installing a new tool release"
elif [ ! -f "$MISE_CFG" ]; then
  mkdir -p "$(dirname "$MISE_CFG")"
  printf '[settings]\nminimum_release_age = "%s"\n' "$MISE_AGE" > "$MISE_CFG"
  success "mise waits $DAYS days before installing a brand-new tool release"
elif grep -qs '^[[:space:]]*\[settings\]' "$MISE_CFG"; then
  awk -v val="$MISE_AGE" '
    { print }
    /^[[:space:]]*\[settings\][[:space:]]*$/ && !seen {
      printf "minimum_release_age = \"%s\"\n", val
      seen = 1
    }' "$MISE_CFG" > "$MISE_CFG.bumpstart-new"
  mv "$MISE_CFG.bumpstart-new" "$MISE_CFG"
  success "mise waits $DAYS days before installing a brand-new tool release"
else
  _append_line "$MISE_CFG" '[settings]'
  _append_line "$MISE_CFG" "minimum_release_age = \"$MISE_AGE\""
  success "mise waits $DAYS days before installing a brand-new tool release"
fi

# ── pnpm ──────────────────────────────────────────────────────────────────────
# Only when pnpm is actually here (it arrives with the pnpm block, not this one).
# Strict matters: pnpm's default is advisory, silently falling back to the
# next-oldest satisfying version rather than refusing.
#
# pnpm resolves its global config dir in this order, on every platform:
#   1. $XDG_CONFIG_HOME/pnpm   — when the variable is set, whatever the OS
#   2. ~/Library/Preferences/pnpm  — macOS default (NOT ~/.config/pnpm)
#   3. ~/.config/pnpm          — everywhere else
# Writing the wrong one is worse than writing nothing: the gate exists, looks set,
# and pnpm never reads it. So resolve it the way pnpm does rather than hardcoding
# the mac path, which was also wrong on a Mac with XDG_CONFIG_HOME set.
if command -v pnpm >/dev/null 2>&1 ||
   { command -v mise >/dev/null 2>&1 && mise which pnpm >/dev/null 2>&1; }; then
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    PNPM_CFG="$XDG_CONFIG_HOME/pnpm/config.yaml"
  elif [ "$(bump_os)" = mac ]; then
    PNPM_CFG="$HOME/Library/Preferences/pnpm/config.yaml"
  else
    PNPM_CFG="$HOME/.config/pnpm/config.yaml"
  fi
  mkdir -p "$(dirname "$PNPM_CFG")"
  if grep -qs '^minimumReleaseAge:' "$PNPM_CFG"; then
    success "pnpm already waits before installing a new package version"
  else
    _append_line "$PNPM_CFG" "minimumReleaseAge: $PNPM_AGE"
    success "pnpm waits $DAYS days before installing a brand-new package version"
  fi
  if ! grep -qs '^minimumReleaseAgeStrict:' "$PNPM_CFG"; then
    _append_line "$PNPM_CFG" 'minimumReleaseAgeStrict: true'
  fi
fi

# TODO(win): no apply.ps1 yet, so this block is a no-op on Windows —
# Test-BlockRuns checks apply.sh only, so the row and its guidance both drop out
# of the plan there. The Windows equivalents are the same keys: min-release-age /
# allow-git / allow-remote in %USERPROFILE%\.npmrc, minimum_release_age in mise's
# config.toml, and minimumReleaseAge{,Strict} in pnpm's global config.yaml.
