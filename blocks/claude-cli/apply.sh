#!/usr/bin/env bash
set -euo pipefail
#
# claude-cli harness: install the Claude Code CLI (the stable spine).
# Check-then-act, so re-runs skip what is already present. The desktop app is a
# separate block (claude-desktop); the `claude` preset bundles both.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

if command -v claude >/dev/null 2>&1; then
  success "Claude Code CLI already installed"
else
  info "Installing Claude Code CLI..."
  if spin "Installing Claude Code CLI" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'; then
    success "Claude Code CLI installed"
  else
    error "Couldn't install the Claude Code CLI — try again or install by hand."
    exit 1
  fi
fi
