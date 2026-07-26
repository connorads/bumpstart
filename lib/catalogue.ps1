# catalogue.ps1: author-facing discovery, the pwsh mirror of catalogue.sh.
# Show-Catalogue lists every block + preset grouped by kind; Show-Block zooms in
# on one. Pure reads via Get-Meta + Get-KindRank. Depends on common.ps1 + meta.ps1
# + resolve.ps1 (Get-KindRank). 5.1-safe.

# Show-Catalogue <root> - every block then preset, grouped by kind, ordered by
# Get-KindRank (presets last). Non-preset rows show their INCLUDE inline.
function Show-Catalogue {
  param([string]$Root)
  $rows = @()
  foreach ($base in @('blocks', 'presets')) {
    $dir = Join-Path $Root $base
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name)) {
      if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'meta'))) { continue }
      $kind = Get-Meta $d.FullName 'KIND'
      $rows += [pscustomobject]@{ Rank = Get-KindRank $kind; Id = $d.Name; Kind = $kind }
    }
  }

  Write-Host ("`n  Blocks you can compose - paste {0}vibe _ <id>...{1}" -f $script:Bold, $script:Reset)

  $last = ''
  foreach ($r in ($rows | Sort-Object Rank, Id)) {
    $dir = Get-BlockDir $Root $r.Id
    $desc = Get-Meta $dir 'DESC'
    $inc = Get-Meta $dir 'INCLUDE'
    if ($r.Kind -ne $last) {
      Write-Host ("`n  {0}{1}{2}" -f $script:Bold, $r.Kind, $script:Reset)
      $last = $r.Kind
    }
    $idcol = $r.Id.PadRight(12)
    if ($r.Kind -eq 'preset') {
      Write-Host ("    {0}{1}{2} {3}" -f $script:Bold, $idcol, $script:Reset, $desc)
      Write-Host ("    {0}expands to: {1}{2}" -f $script:Dim, $inc, $script:Reset)
    } elseif ($inc) {
      Write-Host ("    {0}{1}{2} {3} {4}(pulls in: {5}){2}" -f $script:Bold, $idcol, $script:Reset, $desc, $script:Dim, $inc)
    } else {
      Write-Host ("    {0}{1}{2} {3}" -f $script:Bold, $idcol, $script:Reset, $desc)
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
  $desc = Get-Meta $dir 'DESC'
  $inc = Get-Meta $dir 'INCLUDE'
  $target = Get-Meta $dir ("TARGET_" + (Get-VibeOsKey))
  if (-not $target) { $target = Get-Meta $dir 'TARGET' }

  Write-Host ("`n  {0}{1}{2}  {3}[{4}]{2}" -f $script:Bold, $Id, $script:Reset, $script:Dim, $kind)
  Write-Host ("    {0}" -f $desc)
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
  if ((Test-Path -LiteralPath (Join-Path $dir 'content.md')) -or
      (Test-Path -LiteralPath (Join-Path $dir ("content." + (Get-VibeOs) + '.md')))) {
    Write-Host ("    {0}adds agent guidance{1}" -f $script:Dim, $script:Reset)
  }
  Write-Host ''
  return $true
}
