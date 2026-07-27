#!/usr/bin/env bash
set -euo pipefail
# Test driver: source the trust lib and call one of its functions under the PATH
# `bash` (/bin/bash 3.2 in the isolated test env).
#
#   trust_driver.sh <lib_dir> <function> [args...]
# shellcheck source=lib/common.sh
. "$1/common.sh"
# shellcheck source=lib/os.sh
. "$1/os.sh"
# shellcheck source=lib/trust.sh
. "$1/trust.sh"
fn="$2"; shift 2
"$fn" "$@"
