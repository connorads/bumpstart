#!/usr/bin/env bash
set -euo pipefail
#
# Legacy one-paste entry point. Maps the old --agent flag to a block id and
# delegates to the applier — locally when run from a clone, otherwise via the
# `vibe` bootstrap (which fetches the repo). Keeps the README one-liner working:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/install.sh)"
#
# Any other flags (--no-desktop, --no-launch, --yes, --plan, extra ids) pass
# straight through to the applier.

# No --agent → pass no ids, so the applier's bare-paste default (web-starter)
# gives the full beginner setup rather than a tool-less, sign-in-less bare agent.
AGENT=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --agent)   AGENT="${2:-}"; shift 2 ;;
    --agent=*) AGENT="${1#*=}"; shift ;;
    *)         ARGS+=("$1"); shift ;;
  esac
done

dir=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
fi

if [ -n "$dir" ] && [ -f "$dir/lib/apply.sh" ]; then
  exec bash "$dir/lib/apply.sh" ${AGENT:+"$AGENT"} ${ARGS[@]+"${ARGS[@]}"}
else
  exec /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ ${AGENT:+"$AGENT"} ${ARGS[@]+"${ARGS[@]}"}
fi
