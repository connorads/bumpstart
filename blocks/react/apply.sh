#!/usr/bin/env bash
set -euo pipefail
#
# react (skill): install the skill payload into each harness's user skills dir.
# Harness-aware via VIBE_HARNESSES. Check-then-act: skip a harness whose skill
# dir already exists. Claude reads ~/.claude/skills/<name>/SKILL.md; Codex skill
# support lands in a later iteration.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

installed_any=false
for harness in ${VIBE_HARNESSES:-}; do
  case "$harness" in
    claude) dest="$HOME/.claude/skills/react" ;;
    *) info "react skill: no install path for '$harness' yet — skipping."; continue ;;
  esac

  if [ -d "$dest" ]; then
    success "react skill already installed for $harness"
  else
    info "Installing react skill for $harness..."
    mkdir -p "$dest"
    cp -R "$VIBE_BLOCK_DIR/skill/." "$dest/"
    success "Installed react skill for $harness"
  fi
  installed_any=true
done

[ "$installed_any" = true ] || warn "react skill: no supported harness in the plan."
