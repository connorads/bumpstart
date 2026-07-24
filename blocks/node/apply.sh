#!/usr/bin/env bash
set -euo pipefail
#
# node (tool): install Node.js LTS globally via mise (pulled in by INCLUDE).
# Check-then-act: skip if node is already resolvable, directly or through mise.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

if command -v node >/dev/null 2>&1 || mise which node >/dev/null 2>&1; then
  success "Node.js already installed"
else
  info "Installing Node.js LTS via mise..."
  mise use -g node@lts && success "Node.js installed"
fi
