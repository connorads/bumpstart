#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the runner libs and invoke one of run.sh's functions under
# the PATH `bash` (/bin/bash 3.2 in the isolated test env), so the runner is
# exercised under the real macOS bash rather than the bats runner's bash. The
# invoked function's exit status becomes the driver's, so block_check's 0/1/2 and
# _block_runs' 0/1 are observable as $status.
#
#   run_driver.sh <lib_dir> <fn> <root> <id>
LIB="$1"; shift
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/meta.sh
. "$LIB/meta.sh"
# shellcheck source=lib/os.sh
. "$LIB/os.sh"
# shellcheck source=lib/run.sh
. "$LIB/run.sh"

# Mirrors apply.sh, which exports vibe_fetch before the block loop: an INSTALL cell
# runs in a `bash -c` child, so a cell that fetches needs the function exported.
export -f vibe_fetch

fn="$1"; shift
if "$fn" "$@"; then exit 0; else exit $?; fi
