#!/usr/bin/env bash
set -euo pipefail
#
# codex-cli harness: install the Codex CLI (the stable spine). Check-then-act.
# The desktop experience lives in the ChatGPT app (codex-desktop block); the
# `codex` preset bundles both.

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
