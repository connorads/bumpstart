#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the instructions lib and drive one operation. Invoked via
# the PATH `bash` (which the isolated test env pins to /bin/bash 3.2), so
# instructions.sh is exercised under the real macOS bash rather than the bats
# runner's bash.
#
#   instructions_driver.sh <lib_dir> assemble <root> <force> <id>...
#   instructions_driver.sh <lib_dir> link <native_path> <force>
#   instructions_driver.sh <lib_dir> canonical
LIB="$1"; shift
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/meta.sh
. "$LIB/meta.sh"
# shellcheck source=lib/os.sh
. "$LIB/os.sh"
# shellcheck source=lib/run.sh
. "$LIB/run.sh"
# shellcheck source=lib/instructions.sh
. "$LIB/instructions.sh"

_cmd="$1"; shift
case "$_cmd" in
  assemble)
    _root="$1"; _force="$2"; shift 2
    PLAN_STEP_IDS=("$@")
    assemble_instructions "$_root" "$_force"
    ;;
  link)
    link_harness "$1" "$2"
    ;;
  canonical)
    canonical_path
    ;;
  *)
    echo "unknown driver command: $_cmd" >&2; exit 2 ;;
esac
