#!/usr/bin/env bats
#
# lib/run.sh: the generic declarative runner, unit-tested against synthetic blocks
# written into a temp root so each cell is exact and hermetic. Covers skip
# (CHECK passes), install (CHECK fails), unmapped (no INSTALL cell), non-fatal
# (INSTALL fails -> warn, still 0), block_check's 0/1/2 contract, and the
# _block_runs step-counting predicate.

load helpers/common

setup() {
  setup_isolated_env
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/blocks"
}

# mk_block <id> <meta-line>... — write a synthetic block's meta from the lines.
mk_block() {
  id="$1"; shift
  mkdir -p "$ROOT/blocks/$id"
  printf '%s\n' "$@" > "$ROOT/blocks/$id/meta"
}

# drive <fn> <root> <id> — run a run.sh function via the driver; $status is fn's.
drive() { run bash "$REPO_ROOT/tests/helpers/run_driver.sh" "$REPO_ROOT/lib" "$@"; }

@test "block_check returns 0 when the CHECK cell passes" {
  mk_block present 'KIND=tool' "CHECK_MAC='true'"
  drive block_check "$ROOT" present
  [ "$status" -eq 0 ]
}

@test "block_check returns 1 when the CHECK cell fails" {
  mk_block absent 'KIND=tool' "CHECK_MAC='false'"
  drive block_check "$ROOT" absent
  [ "$status" -eq 1 ]
}

@test "block_check returns 2 when there is no CHECK cell" {
  mk_block bare 'KIND=instructions' 'DESC=x'
  drive block_check "$ROOT" bare
  [ "$status" -eq 2 ]
}

@test "run_cell skips the install when the block is already satisfied" {
  make_fake brew
  mk_block sat 'KIND=tool' 'LABEL=thing' "CHECK_MAC='true'" "INSTALL_MAC='brew install thing'"
  drive run_cell "$ROOT" sat
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_fake_logged "brew install thing"
}

@test "run_cell runs the install when the block is not satisfied" {
  make_fake brew
  mk_block act 'KIND=tool' 'LABEL=thing' "CHECK_MAC='false'" "INSTALL_MAC='brew install thing'"
  drive run_cell "$ROOT" act
  [ "$status" -eq 0 ]
  fake_logged "brew install thing"
}

@test "run_cell is a silent no-op for an unmapped block (no INSTALL cell)" {
  mk_block note 'KIND=instructions' 'DESC=x'
  drive run_cell "$ROOT" note
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "run_cell warns but returns 0 when the install fails (non-fatal)" {
  mk_block boom 'KIND=tool' 'LABEL=thing' "CHECK_MAC='false'" "INSTALL_MAC='false'"
  drive run_cell "$ROOT" boom
  [ "$status" -eq 0 ]
  [[ "$output" == *"Couldn't install"* ]]
}

@test "run_cell falls back to DESC for the label when LABEL is unset" {
  make_fake brew
  mk_block desc 'KIND=tool' 'DESC="the widget"' "CHECK_MAC='true'" "INSTALL_MAC='brew install widget'"
  drive run_cell "$ROOT" desc
  [ "$status" -eq 0 ]
  [[ "$output" == *"the widget already installed"* ]]
}

@test "_block_runs is true for a block with an INSTALL cell" {
  mk_block cell 'KIND=tool' "INSTALL_MAC='brew install x'"
  drive _block_runs "$ROOT" cell
  [ "$status" -eq 0 ]
}

@test "_block_runs is true for a block with an apply.sh (escape hatch)" {
  mk_block script 'KIND=auth' 'DESC=x'
  printf '#!/usr/bin/env bash\n' > "$ROOT/blocks/script/apply.sh"
  drive _block_runs "$ROOT" script
  [ "$status" -eq 0 ]
}

@test "_block_runs is false for an instruction-only block" {
  mk_block only 'KIND=instructions' 'DESC=x'
  drive _block_runs "$ROOT" only
  [ "$status" -eq 1 ]
}
