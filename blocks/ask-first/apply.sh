#!/usr/bin/env bash
set -euo pipefail
#
# ask-first (instructions): merge content.md into each harness's instructions
# file. Pure preference, no install. Idempotent via merge.sh's managed markers.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"
# shellcheck source=lib/merge.sh
. "$VIBE_LIB/merge.sh"

merge_content_to_targets
