#!/usr/bin/env bash
set -euo pipefail
#
# codex-desktop app: install the ChatGPT app (which hosts Codex since the July
# 2026 Codex/ChatGPT merge) via Homebrew cask. Check-then-act. Best-effort — a
# cask failure warns and continues.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

# The apps dir is overridable so the install branch is reachable in tests without
# the real app present (default is the real path).
_apps="${VIBE_APPS_DIR:-/Applications}"

if [ -d "$_apps/ChatGPT.app" ]; then
  success "ChatGPT app already installed"
else
  info "Installing the ChatGPT app (hosts Codex)..."
  spin "Installing the ChatGPT app" brew install --cask chatgpt \
    || warn "Couldn't install the ChatGPT app — skipping (later: brew install --cask chatgpt)"
fi
