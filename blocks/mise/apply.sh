#!/usr/bin/env bash
set -euo pipefail
#
# mise (tool): install the mise runtime version manager via Homebrew.
# Check-then-act.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"
# shellcheck source=lib/merge.sh
. "$VIBE_LIB/merge.sh"

if command -v mise >/dev/null 2>&1; then
  success "mise already installed"
else
  info "Installing mise..."
  brew install mise && success "mise installed"
fi

# Teach the agent how tools get installed here (merged iff this block is planned).
merge_content_to_targets
