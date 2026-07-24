#!/usr/bin/env bash
set -euo pipefail
#
# mise (tool): install the mise runtime version manager via Homebrew.
# Check-then-act.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

if command -v mise >/dev/null 2>&1; then
  success "mise already installed"
else
  info "Installing mise..."
  brew install mise && success "mise installed"
fi
