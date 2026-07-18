#!/usr/bin/env bash
set -euo pipefail
#
# claude harness: install the Claude Code CLI (the stable spine) and, unless
# VIBE_DESKTOP=false, the Claude desktop app. Check-then-act, so re-runs skip
# what is already present. Best-effort desktop install (fast-moving vendor cask).

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

if command -v claude >/dev/null 2>&1; then
  success "Claude Code CLI already installed"
else
  info "Installing Claude Code CLI..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    success "Claude Code CLI installed"
  else
    error "Couldn't install the Claude Code CLI — try again or install by hand."
    exit 1
  fi
fi

if [ "${VIBE_DESKTOP:-true}" = true ]; then
  if [ -d "/Applications/Claude.app" ]; then
    success "Claude desktop app already installed"
  else
    info "Installing the Claude desktop app..."
    brew install --cask claude \
      || warn "Couldn't install the desktop app — skipping (later: brew install --cask claude)"
  fi
fi
