# shellcheck shell=bash
# run.sh: the generic declarative runner. Blocks carry their per-OS install as
# DATA — a CHECK_<os> skip predicate and an INSTALL_<os> command in meta — and
# this runner reads + executes the current-OS cell. "Data by default, script when
# needed": a block that also ships an apply.sh keeps its interactive tail, run
# after the cell. Depends on meta.sh (block_dir, meta_get), os.sh (bump_os_key),
# and common.sh (spin/success/warn). Sourced, not executed. bash-3.2-clean.

# _block_label <root> <id> — the human name for spin/success lines: LABEL if set,
# else DESC. Falls back to the id if the block has neither.
_block_label() {
  _bl_dir="$(block_dir "$1" "$2")" || { printf '%s' "$2"; return 0; }
  _bl="$(meta_get "$_bl_dir" LABEL)"
  [ -n "$_bl" ] || _bl="$(meta_get "$_bl_dir" DESC)"
  [ -n "$_bl" ] || _bl="$2"
  printf '%s' "$_bl"
}

# block_check <root> <id> — eval the current-OS CHECK cell as the check-then-act
# skip predicate. 0 = satisfied (install can be skipped), 1 = not satisfied,
# 2 = no cell (unmapped). ALWAYS via if/else, never a bare eval — a failing
# predicate under the applier's set -e would otherwise abort the caller.
#
# The POSIX contract is the EXIT STATUS, so a cell's output is noise on the way to
# it. Every real cell already ends in >/dev/null 2>&1; redirecting here makes the
# caller enforce the silence rather than trusting each cell to remember. (The
# opposite of the Windows contract, which reads the output's truthiness — see
# Test-BlockCheck in run.ps1.)
block_check() {
  _bc_dir="$(block_dir "$1" "$2")" || return 2
  _bc_cell="$(meta_get "$_bc_dir" "CHECK_$(bump_os_key)")"
  [ -n "$_bc_cell" ] || return 2
  if eval "$_bc_cell" >/dev/null 2>&1; then return 0; else return 1; fi
}

# run_cell <root> <id> — the declarative install for the current OS. Read
# INSTALL_<os>; no cell -> silent no-op (an instruction-only block, or one not
# yet mapped to this OS). If block_check passes -> "already installed". Else spin
# the install and success/warn. Non-fatal: a vendor step that fails warns and the
# setup continues, so it ALWAYS returns 0.
run_cell() {
  _rc_dir="$(block_dir "$1" "$2")" || return 0
  _rc_install="$(meta_get "$_rc_dir" "INSTALL_$(bump_os_key)")"
  [ -n "$_rc_install" ] || return 0
  _rc_label="$(_block_label "$1" "$2")"
  if block_check "$1" "$2"; then
    success "$_rc_label already installed"
    return 0
  fi
  # pipefail, because most install cells are `fetch <url> | sh`: without it the
  # pipeline's status is the SHELL's, and a shell handed an empty stdin (a failed
  # download, an offline machine, a 404) exits 0 — so the cell would report success
  # having installed nothing. Verified offline in a container. The pwsh spine has no
  # pipeline to make fail-safe: a failing Invoke-RestMethod throws, which Invoke-Spin
  # catches. What carries the verdict there is Invoke-Spin's single boolean — which
  # is why it pushes the cell's own output to Write-Host rather than letting it ride
  # back on the success stream beside the flag.
  if spin "Installing $_rc_label" bash -c "set -o pipefail; $_rc_install"; then
    success "$_rc_label installed"
  else
    warn "Couldn't install $_rc_label — continuing"
    # Non-fatal still means "did not happen": recorded so the finish message says so.
    record_warning "$_rc_label"
  fi
  return 0
}

# _block_runs <root> <id> — true when the block does real work in the run loop:
# it has an INSTALL cell for the current OS, or an apply.sh script tail. This is
# the step-counting predicate (instruction-only blocks are silent skips, so they
# neither get a step header nor inflate the total).
_block_runs() {
  _br_dir="$(block_dir "$1" "$2")" || return 1
  [ -n "$(meta_get "$_br_dir" "INSTALL_$(bump_os_key)")" ] && return 0
  [ -f "$_br_dir/apply.sh" ] && return 0
  return 1
}
