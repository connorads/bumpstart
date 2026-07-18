#!/usr/bin/env bash
set -euo pipefail
#
# context7 (mcp): register the Context7 docs MCP server with each harness.
# Harness-aware via VIBE_HARNESSES. Check-then-act per harness.
#   Claude: user-scope via `claude mcp add`.
#   Codex:  an [mcp_servers.context7] table in ~/.codex/config.toml.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

for harness in ${VIBE_HARNESSES:-}; do
  case "$harness" in
    claude)
      if claude mcp list 2>/dev/null | grep -q context7; then
        success "Context7 already configured for Claude"
      else
        info "Adding Context7 to Claude..."
        claude mcp add -s user context7 -- npx -y @upstash/context7-mcp \
          && success "Context7 added to Claude"
      fi
      ;;
    codex)
      cfg="$HOME/.codex/config.toml"
      mkdir -p "$(dirname "$cfg")"
      if [ -f "$cfg" ] && grep -Fq "[mcp_servers.context7]" "$cfg"; then
        success "Context7 already configured for Codex"
      else
        info "Adding Context7 to Codex..."
        if [ -f "$cfg" ]; then printf '\n' >> "$cfg"; fi
        {
          printf '[mcp_servers.context7]\n'
          printf 'command = "npx"\n'
          printf 'args = ["-y", "@upstash/context7-mcp"]\n'
        } >> "$cfg"
        success "Context7 added to Codex"
      fi
      ;;
    *)
      info "Context7: no setup path for '$harness' yet — skipping."
      ;;
  esac
done
