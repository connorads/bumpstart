#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the merge lib and apply one managed block. Invoked via the
# PATH `bash` (which the isolated test env pins to /bin/bash 3.2), so merge.sh is
# exercised under the real macOS bash rather than the bats runner's bash.
#
#   merge_driver.sh <lib_dir> <id> <content> <target>
. "$1/common.sh"
. "$1/merge.sh"
merge_managed_block "$2" "$3" "$4"
