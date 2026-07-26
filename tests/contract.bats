#!/usr/bin/env bats
#
# Shared resolver contract — the bash side. Reads tests/fixtures/contract/
# resolve-cases.tsv (the SAME file Contract.Tests.ps1 reads) and drives resolve.sh
# through resolve_driver.sh, asserting the ids/kinds/harness/error the spine
# produces match the row. Both spines green off one file ⇒ the two resolvers
# cannot diverge on the OS-neutral core.

load helpers/common

setup() {
  setup_isolated_env
  FIX="$REPO_ROOT/tests/fixtures"
  TSV="$FIX/contract/resolve-cases.tsv"
}

@test "resolve.sh matches the shared contract for every case" {
  local first=1 n=0
  while IFS=$'\t' read -r input exp_ids exp_kinds exp_harness exp_err; do
    if [ "$first" = 1 ]; then first=0; continue; fi   # skip header
    [ -z "$input" ] && continue
    n=$((n + 1))

    run bash "$REPO_ROOT/tests/helpers/resolve_driver.sh" "$REPO_ROOT/lib" "$FIX" $input
    [ "$status" -eq 0 ] || { echo "driver failed for [$input]"; false; }

    IFS=$'\t' read -r got_ids got_kinds got_harness got_err <<< "$output"
    [ "$got_ids" = "$exp_ids" ]         || { echo "ids  [$input]: got [$got_ids] want [$exp_ids]"; false; }
    [ "$got_kinds" = "$exp_kinds" ]     || { echo "kinds[$input]: got [$got_kinds] want [$exp_kinds]"; false; }
    [ "$got_harness" = "$exp_harness" ] || { echo "harn [$input]: got [$got_harness] want [$exp_harness]"; false; }
    [ "$got_err" = "$exp_err" ]         || { echo "err  [$input]: got [$got_err] want [$exp_err]"; false; }
  done < "$TSV"

  [ "$n" -gt 0 ] || { echo "no contract rows read"; false; }
}
