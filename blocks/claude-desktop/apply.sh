#!/usr/bin/env bash
set -euo pipefail
#
# claude-desktop app: install the Claude desktop app via Homebrew cask.
# Check-then-act. Best-effort — a fast-moving vendor cask failure warns and
# continues rather than sinking the setup.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

# The apps dir is overridable so the install branch is reachable in tests without
# the real app present (default is the real path).
_apps="${VIBE_APPS_DIR:-/Applications}"

if [ -d "$_apps/Claude.app" ]; then
  success "Claude desktop app already installed"
else
  info "Installing the Claude desktop app..."
  spin "Installing the Claude desktop app" brew install --cask claude \
    || warn "Couldn't install the desktop app — skipping (later: brew install --cask claude)"
fi
