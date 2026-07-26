#!/usr/bin/env bash
set -uo pipefail
# Test driver: source the pure core and print the resolved Plan as one TAB line —
# "<ids>\t<kinds>\t<harness>\t<error>" — so the shared contract (contract.bats +
# Contract.Tests.ps1) can drive resolve.sh and resolve.ps1 off the identical TSV
# and compare. Targets are deliberately omitted: they are OS-specific and asserted
# per-spine, not in the cross-OS contract.
#
#   resolve_driver.sh <lib_dir> <root> <id>...
LIB="$1"; ROOT="$2"; shift 2
# shellcheck source=lib/meta.sh
. "$LIB/meta.sh"
# shellcheck source=lib/os.sh
. "$LIB/os.sh"
# shellcheck source=lib/resolve.sh
. "$LIB/resolve.sh"

if resolve "$ROOT" "$@"; then
  printf '%s\t%s\t%s\t%s\n' \
    "${PLAN_STEP_IDS[*]:-}" "${PLAN_STEP_KINDS[*]:-}" "$PLAN_DEFAULT_HARNESS" ""
else
  printf '%s\t%s\t%s\t%s\n' "" "" "" "$PLAN_ERROR"
fi
