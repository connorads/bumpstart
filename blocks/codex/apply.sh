#!/usr/bin/env bash
set -euo pipefail
#
# codex harness: install the Codex CLI and, unless VIBE_DESKTOP=false, the
# ChatGPT app (which now hosts Codex since the July 2026 Codex/ChatGPT merge).
# Check-then-act; best-effort desktop install.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

if command -v codex >/dev/null 2>&1; then
  success "Codex CLI already installed"
else
  info "Installing Codex CLI..."
  if spin "Installing Codex CLI" bash -c 'curl -fsSL https://chatgpt.com/codex/install.sh | sh'; then
    success "Codex CLI installed"
  else
    error "Couldn't install the Codex CLI — try again or install by hand."
    exit 1
  fi
fi

if [ "${VIBE_DESKTOP:-true}" = true ]; then
  if [ -d "/Applications/ChatGPT.app" ]; then
    success "ChatGPT app already installed"
  else
    info "Installing the ChatGPT app (hosts Codex)..."
    spin "Installing the ChatGPT app" brew install --cask chatgpt \
      || warn "Couldn't install the ChatGPT app — skipping (later: brew install --cask chatgpt)"
  fi
fi
