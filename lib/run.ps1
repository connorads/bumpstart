# run.ps1: the generic declarative runner, the pwsh mirror of run.sh. A block
# carries its per-OS install as DATA - a CHECK_<os> skip predicate and an
# INSTALL_<os> command in meta - and this runner reads + Invoke-Expressions the
# current-OS cell. Depends on meta.ps1 (Get-BlockDir, Get-Meta), os.ps1
# (Get-VibeOsKey), common.ps1 (Invoke-Spin, Success, Warn). Dot-sourced. 5.1-safe.
#
# On the pwsh spine every cell is PowerShell (the WIN cells), evaluated with
# Invoke-Expression - the analogue of bash's eval on the MAC cells.

# Get-BlockLabel <root> <id> - the human name for spin/success lines: LABEL if
# set, else DESC, else the id.
function Get-BlockLabel {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) { return $Id }
  $label = Get-Meta $dir 'LABEL'
  if (-not $label) { $label = Get-Meta $dir 'DESC' }
  if (-not $label) { $label = $Id }
  return $label
}

# Test-BlockCheck <root> <id> - the current-OS CHECK cell as the skip predicate.
# $true = satisfied (install can be skipped), $false = not satisfied, $null = no
# cell (unmapped). The 0/1/2 contract of run.sh's block_check, as a tri-state.
function Test-BlockCheck {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) { return $null }
  $cell = Get-Meta $dir ("CHECK_" + (Get-VibeOsKey))
  if (-not $cell) { return $null }
  # The evaluation model is the OPPOSITE of the POSIX one, and the field family is
  # shared, so it is worth spelling out: bash reads a CHECK cell's EXIT STATUS
  # (block_check redirects the output away), and this reads the TRUTHINESS OF WHAT
  # THE CELL RETURNS. So a CHECK_WIN cell must emit something falsy when the thing
  # is absent - `Get-Command x -ErrorAction SilentlyContinue` returns nothing, and
  # `winget list <id>` is piped through Select-String for exactly this reason.
  #
  # The trap: a cell that emits UNCONDITIONALLY is permanently satisfied, so its
  # install never runs and the step reports "already installed" forever.
  #
  # A predicate that errors (e.g. winget absent on Windows 10 pre-1809) reads as
  # "not satisfied" - the bash analogue of a non-zero eval - never a crash.
  try {
    if (Invoke-Expression $cell) { return $true } else { return $false }
  } catch {
    return $false
  }
}

# Invoke-Cell <root> <id> - the declarative install for the current OS. Read
# INSTALL_<os>; no cell -> silent no-op. If Test-BlockCheck is $true ->
# "already installed". Else spin the install and success/warn. Non-fatal: a vendor
# step that fails warns and setup continues.
function Invoke-Cell {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) { return }
  $install = Get-Meta $dir ("INSTALL_" + (Get-VibeOsKey))
  if (-not $install) { return }
  $label = Get-BlockLabel $Root $Id
  if ((Test-BlockCheck $Root $Id) -eq $true) {
    Success "$label already installed"
    return
  }
  $ok = Invoke-Spin "Installing $label" { Invoke-Expression $install }
  # -eq $true, not truthiness: Invoke-Spin's contract is one boolean, and if it
  # ever regresses to returning more than that, this reads the regression as a
  # failure rather than as a success. For a non-fatal step that is the safe
  # direction - a false warning costs a line, a false 'installed' costs trust.
  if ($ok -eq $true) {
    Success "$label installed"
  } else {
    Warn "Couldn't install $label - continuing"
    # Non-fatal still means "did not happen": recorded so the finish message says so.
    Add-VibeWarning $label
  }
}

# Test-BlockRuns <root> <id> - $true when the block does real work in the run
# loop: an INSTALL cell for the current OS, or an apply.ps1 script tail. The
# step-counting predicate (instruction-only blocks are silent skips). The pwsh
# spine looks for apply.ps1, never apply.sh (that is the bash spine's tail).
function Test-BlockRuns {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) { return $false }
  if (Get-Meta $dir ("INSTALL_" + (Get-VibeOsKey))) { return $true }
  if (Test-Path -LiteralPath (Join-Path $dir 'apply.ps1')) { return $true }
  return $false
}
