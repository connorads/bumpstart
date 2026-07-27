#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the shellpath lib and persist the PATH line under the PATH
# `bash` (/bin/bash 3.2 in the isolated test env), so the rc edit is exercised
# under the real macOS bash rather than the bats runner's bash.
#
#   shellpath_driver.sh <lib_dir>
# shellcheck source=lib/common.sh
. "$1/common.sh"
# shellcheck source=lib/shellpath.sh
. "$1/shellpath.sh"
persist_path
