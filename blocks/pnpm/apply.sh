#!/usr/bin/env bash
set -euo pipefail
#
# pnpm (tool): install pnpm globally via mise (pulled in by INCLUDE).
# Check-then-act: skip if pnpm is already resolvable, directly or through mise.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"
# shellcheck source=lib/merge.sh
. "$VIBE_LIB/merge.sh"

if command -v pnpm >/dev/null 2>&1 || mise which pnpm >/dev/null 2>&1; then
  success "pnpm already installed"
else
  info "Installing pnpm via mise..."
  mise use -g pnpm@latest && success "pnpm installed"
fi

# Teach the agent to reach for pnpm (merged iff this block is planned).
merge_content_to_targets
