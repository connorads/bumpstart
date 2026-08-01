#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the brew lib and call ensure_brew under the PATH `bash`
# (/bin/bash 3.2 in the isolated test env). BUMP_BREW_OPT/USR point the prefix
# probes at nonexistent paths so the install branch is reachable hermetically.
#
#   brew_driver.sh <lib_dir>
. "$1/common.sh"
. "$1/brew.sh"
ensure_brew
