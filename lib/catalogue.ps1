# catalogue.ps1: author-facing discovery, the pwsh mirror of catalogue.sh.
# Show-Catalogue lists every block + preset grouped by AXIS - the same grouping,
# in the same order, that -Build asks its questions in. Show-Block zooms in on
# one. Pure reads via Get-Meta. Depends on common.ps1 + meta.ps1. 5.1-safe.

# Show-Catalogue <root> - every block and preset under a heading per axis, in the
# axes' declared ORDER, presets first inside each (the coarse choice leads). KIND
# drops to a dim tag: it is how the applier orders work, not a question a human
# answers. Blocks with no AXIS are never offered on their own, so they get a
# final group that says exactly that.
function Show-Catalogue {
  param([string]$Root)
  $rows = @()
  foreach ($base in @('blocks', 'presets')) {
    $dir = Join-Path $Root $base
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory)) {
      if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'meta'))) { continue }
      $kind = Get-Meta $d.FullName 'KIND'
      $axis = Get-Meta $d.FullName 'AXIS'
      $axisDir = Join-Path (Join-Path $Root 'axes') $axis
      $order = 999
      if ($axis -and (Test-Path -LiteralPath (Join-Path $axisDir 'meta'))) {
        $declared = Get-Meta $axisDir 'ORDER'
        if ($declared) { $order = [int]$declared } else { $order = 99 }
      } else {
        $axis = '-'
      }
      $rank = 1
      if ($kind -eq 'preset') { $rank = 0 }
      $rows += [pscustomobject]@{ Order = $order; Axis = $axis; Rank = $rank; Id = $d.Name; Kind = $kind }
    }
  }

  Write-Host ("`n  Blocks you can compose - paste {0}vibe _ <id>...{1}" -f $script:Bold, $script:Reset)

  $last = ''
  foreach ($r in ($rows | Sort-Object Order, Axis, Rank, Id)) {
    $dir = Get-BlockDir $Root $r.Id
    $desc = Get-Meta $dir 'DESC'
    $inc = Get-Meta $dir 'INCLUDE'
    if ($r.Axis -ne $last) {
      if ($r.Axis -eq '-') {
        Write-Host ("`n  {0}dependencies{1} {2}- pulled in by the blocks above, never asked about{1}" -f $script:Bold, $script:Reset, $script:Dim)
      } else {
        $label = Get-Meta (Join-Path (Join-Path $Root 'axes') $r.Axis) 'LABEL'
        Write-Host ("`n  {0}{1}{2} {3}- {4}{2}" -f $script:Bold, $r.Axis, $script:Reset, $script:Dim, $label)
      }
      $last = $r.Axis
    }
    $idcol = $r.Id.PadRight(14)
    if ($r.Kind -eq 'preset') {
      Write-Host ("    {0}{1}{2} {3}[{4}]{2} {5}" -f $script:Bold, $idcol, $script:Reset, $script:Dim, $r.Kind, $desc)
      Write-Host ("    {0}expands to: {1}{2}" -f $script:Dim, $inc, $script:Reset)
    } elseif ($inc) {
      Write-Host ("    {0}{1}{2} {3}[{4}]{2} {5} {3}(pulls in: {6}){2}" -f $script:Bold, $idcol, $script:Reset, $script:Dim, $r.Kind, $desc, $inc)
    } else {
      Write-Host ("    {0}{1}{2} {3}[{4}]{2} {5}" -f $script:Bold, $idcol, $script:Reset, $script:Dim, $r.Kind, $desc)
    }
  }
  Write-Host ''
}

# Show-Block <root> <id> - one block's detail. Unknown id -> error + $false.
function Show-Block {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) { Err "unknown block: $Id"; return $false }
  $kind = Get-Meta $dir 'KIND'
  $axis = Get-Meta $dir 'AXIS'
  $desc = Get-Meta $dir 'DESC'
  $inc = Get-Meta $dir 'INCLUDE'
  $target = Get-Meta $dir ("TARGET_" + (Get-VibeOsKey))
  if (-not $target) { $target = Get-Meta $dir 'TARGET' }

  Write-Host ("`n  {0}{1}{2}  {3}[{4}]{2}" -f $script:Bold, $Id, $script:Reset, $script:Dim, $kind)
  Write-Host ("    {0}" -f $desc)
  # Which question this block answers in -Build (and under which -List heading).
  if ($axis) {
    Write-Host ("    {0}axis:{1} {2}" -f $script:Dim, $script:Reset, $axis)
  } else {
    Write-Host ("    {0}no axis - pulled in as a dependency, never offered on its own{1}" -f $script:Dim, $script:Reset)
  }
  if ($inc) {
    if ($kind -eq 'preset') {
      Write-Host ("    {0}expands to:{1} {2}" -f $script:Dim, $script:Reset, $inc)
    } else {
      Write-Host ("    {0}pulls in:{1} {2}" -f $script:Dim, $script:Reset, $inc)
    }
  }
  if ($target) {
    Write-Host ("    {0}instructions written to:{1} {2}" -f $script:Dim, $script:Reset, (Expand-VibeHome $target))
  }
  if (Test-BlockHasContent $dir) {
    Write-Host ("    {0}adds agent guidance{1}" -f $script:Dim, $script:Reset)
  }
  Write-Host ''
  return $true
}
