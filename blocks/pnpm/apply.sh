#!/usr/bin/env bash
set -euo pipefail
#
# pnpm (tool): install pnpm globally via mise (pulled in by INCLUDE).
# Check-then-act: skip if pnpm is already resolvable, directly or through mise.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

if command -v pnpm >/dev/null 2>&1 || mise which pnpm >/dev/null 2>&1; then
  success "pnpm already installed"
else
  info "Installing pnpm via mise..."
  spin "Installing pnpm" mise use -g pnpm@latest && success "pnpm installed"
fi
