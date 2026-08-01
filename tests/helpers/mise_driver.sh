#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the mise lib and call ensure_mise under the PATH `bash`
# (/bin/bash 3.2 in the isolated test env). BUMP_MISE_BIN points the
# already-installed probe at a path the test controls, so both branches are
# reachable hermetically. PATH is printed last so the "on PATH for this run" half
# of the contract is observable.
#
#   mise_driver.sh <lib_dir>
# shellcheck source=lib/common.sh
. "$1/common.sh"
# shellcheck source=lib/mise.sh
. "$1/mise.sh"
ensure_mise
printf 'PATH=%s\n' "$PATH"
