#!/usr/bin/env bash
set -uo pipefail
# Test driver: call plan.sh's _step_satisfied under the PATH `bash` (/bin/bash 3.2
# in the isolated test env). Its 0/1/2 contract becomes the driver's exit status,
# so it is observable as $status, and anything the probe printed lands on the
# driver's stdout — which is the point: the gate must stay silent.
#
# ROOT is set rather than passed, because _step_satisfied reads the global that
# apply.sh assigns rather than taking a root argument.
#
#   plan_driver.sh <lib_dir> <root> <id>
LIB="$1"
# shellcheck disable=SC2034  # read by _step_satisfied, which takes no root arg
ROOT="$2"
ID="$3"
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/meta.sh
. "$LIB/meta.sh"
# shellcheck source=lib/os.sh
. "$LIB/os.sh"
# shellcheck source=lib/run.sh
. "$LIB/run.sh"
# shellcheck source=lib/plan.sh
. "$LIB/plan.sh"

if _step_satisfied "$ID"; then exit 0; else exit $?; fi
