#!/usr/bin/env bash
set -euo pipefail
#
# concise (instructions): merge content.md into each harness's real
# instructions file. Targets arrive as newline-separated VIBE_TARGETS from the
# applier (derived from the harnesses in the plan) — Claude reads
# ~/.claude/CLAUDE.md, Codex reads ~/.codex/AGENTS.md, so we write to whichever
# are present. Idempotent via merge.sh's managed markers.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"
# shellcheck source=lib/merge.sh
. "$VIBE_LIB/merge.sh"

merge_content_to_targets
