# build.ps1: the author-facing wizard, the pwsh mirror of build.sh. Assembles a
# valid bundle interactively - one question per AXIS - previews the exact plan
# the novice will see, and emits the shareable one-paste commands: BOTH the mac
# curl line and the Windows irm line, so an author on either OS can share the
# right paste for their audience. (build.sh emits only the mac line - an
# asymmetry that predates the axes and is left alone here.) Read-only. Depends
# on meta.ps1 + resolve.ps1 + plan.ps1 + common.ps1. 5.1-safe.
#
# The wizard asks nothing it isn't told. Each dir under <root>/axes declares a
# question: LABEL (the wording), ORDER (when it is asked), SELECT (one = a
# required numbered pick, multi = per-row y/N) and, for a single-select, DEFAULT
# (the pre-selected id). A block or preset joins a question by declaring AXIS.

$script:VibeRepo = 'connorads/vibe-setup'

# Show-PasteCommands <ids...> - print the README one-liners for these ids (mac +
# Windows) and copy the Windows one to the clipboard. Inherits the run's ref.
function Show-PasteCommands {
  param([string[]]$Ids)
  $ref = if ($env:VIBE_REF) { $env:VIBE_REF } else { 'main' }
  $prefix = if ($ref -ne 'main') { "VIBE_REF=$ref " } else { '' }
  $idstr = ($Ids -join ' ')

  $mac = "${prefix}/bin/bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$script:VibeRepo/main/vibe)`" _ $idstr"
  $winRef = if ($ref -ne 'main') { "`$env:VIBE_REF='$ref'; " } else { '' }
  $win = "${winRef}irm https://raw.githubusercontent.com/$script:VibeRepo/main/vibe.ps1 | iex"
  if ($idstr) { $win = "${winRef}& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$script:VibeRepo/main/vibe.ps1))) $idstr" }

  Write-Host "`n  Share the paste for your audience:`n"
  Write-Host "  macOS:"
  Write-Host "    $mac`n"
  Write-Host "  Windows (PowerShell):"
  Write-Host "    $win`n"
  if (Copy-ToClipboard $win) { Info 'Copied the Windows command to your clipboard.' }
}

# Get-VibeAxisMembers <root> <axis> - the ids that declare this AXIS, presets
# first (the coarse, ready-made choice leads) then alphabetically.
function Get-VibeAxisMembers {
  param([string]$Root, [string]$Axis)
  $rows = @()
  foreach ($sub in 'blocks', 'presets') {
    $path = Join-Path $Root $sub
    if (-not (Test-Path -LiteralPath $path)) { continue }
    foreach ($d in (Get-ChildItem -LiteralPath $path -Directory)) {
      if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'meta'))) { continue }
      if ((Get-Meta $d.FullName 'AXIS') -ne $Axis) { continue }
      $rank = 1
      if ((Get-Meta $d.FullName 'KIND') -eq 'preset') { $rank = 0 }
      $rows += [pscustomobject]@{ Rank = $rank; Id = $d.Name }
    }
  }
  return @($rows | Sort-Object Rank, Id | ForEach-Object { $_.Id })
}

# Get-VibeAxes <root> - the axes that have at least one member, by their declared
# ORDER. An axis nothing declares is not a question worth asking.
function Get-VibeAxes {
  param([string]$Root)
  $path = Join-Path $Root 'axes'
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  $rows = @()
  foreach ($d in (Get-ChildItem -LiteralPath $path -Directory)) {
    if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'meta'))) { continue }
    if ((Get-VibeAxisMembers $Root $d.Name).Count -eq 0) { continue }
    $order = Get-Meta $d.FullName 'ORDER'
    if (-not $order) { $order = '99' }
    $rows += [pscustomobject]@{ Order = [int]$order; Id = $d.Name; Dir = $d.FullName }
  }
  return @($rows | Sort-Object Order, Id)
}

# Get-VibeAxisDetail <root> <id> - " (pulls in: ...)" for a block that includes
# others, else ''. The same containment detail Show-Catalogue prints: without it
# `starter`, `web` and `gh-auth` read as three unrelated ticks.
function Get-VibeAxisDetail {
  param([string]$Root, [string]$Id)
  $inc = Get-Meta (Get-BlockDir $Root $Id) 'INCLUDE'
  if ($inc) { return " (pulls in: $inc)" }
  return ''
}

# Invoke-VibeWizard <root> - drive the interactive build: one question per axis,
# in the axes' declared ORDER. Returns an object with .Ids (chosen ids, the
# required single-select first) and .RunNow ($true iff apply-now was asked). On
# no answers (input redirected) or an invalid choice, .Ids is empty + .RunNow
# $false.
function Invoke-VibeWizard {
  param([string]$Root)
  $result = [pscustomobject]@{ Ids = @(); RunNow = $false }

  $axes = Get-VibeAxes $Root
  if ($axes.Count -eq 0) { Err "no axis has any members - nothing to ask about under $Root/axes"; return $result }

  # One guard, before the first question: the wizard is interactive throughout,
  # so a redirected stdin can never answer it.
  if ([Console]::IsInputRedirected) {
    Err "No answers on stdin - the wizard needs a terminal. Run '-List' to browse, then 'vibe _ <id>...'."
    return $result
  }

  $one = @()
  $multi = @()
  foreach ($ax in $axes) {
    $ids = Get-VibeAxisMembers $Root $ax.Id
    $label = Get-Meta $ax.Dir 'LABEL'
    if ((Get-Meta $ax.Dir 'SELECT') -eq 'one') {
      Write-Host ("`n  {0} {1}(required){2}`n" -f $label, $script:Dim, $script:Reset)
      $default = Get-Meta $ax.Dir 'DEFAULT'
      $defaultNum = 1
      for ($i = 0; $i -lt $ids.Count; $i++) {
        if ($ids[$i] -eq $default) { $defaultNum = $i + 1 }
        Write-Host ("    {0}{1}){2} {0}{3}{2}  {4}{5}{6}{2}" -f `
            $script:Bold, ($i + 1), $script:Reset, $ids[$i], `
          (Get-Meta (Get-BlockDir $Root $ids[$i]) 'DESC'), $script:Dim, (Get-VibeAxisDetail $Root $ids[$i]))
      }
      Write-Host ("`n  Choose {0}[{1}]{2}: " -f $script:Yellow, $defaultNum, $script:Reset) -NoNewline
      $choice = [Console]::ReadLine()
      $num = if ($choice -eq '') { $defaultNum } elseif ($choice -match '^[0-9]+$') { [int]$choice } else { 0 }
      if ($num -lt 1 -or $num -gt $ids.Count) { Err "Choose a number between 1 and $($ids.Count)."; return $result }
      $one += $ids[$num - 1]
    } else {
      Write-Host ("`n  {0} {1}y to include, Enter to skip{2}`n" -f $label, $script:Dim, $script:Reset)
      foreach ($id in $ids) {
        Write-Host ("    {0}{1}{2}  {3}{4}{5}{2} {6}[y/N]{2} " -f `
            $script:Bold, $id, $script:Reset, `
          (Get-Meta (Get-BlockDir $Root $id) 'DESC'), $script:Dim, (Get-VibeAxisDetail $Root $id), $script:Yellow) -NoNewline
        $reply = [Console]::ReadLine()
        if ($reply -match '^[Yy]') { $multi += $id }
      }
    }
  }

  # The required single choice leads the emitted list: it is what launches, and
  # it keeps the paste in the shape the README documents (`claude starter`), so
  # swapping agent is swapping the first word. The opt-ins follow in axis order.
  $ids = @($one) + @($multi)

  $plan = Resolve-Plan $Root $ids
  if ($plan.Error) { Err $plan.Error; return $result }
  Show-Plan -Plan $plan -Root $Root -Full
  Show-PasteCommands $ids

  Write-Host ("  Run this setup now? {0}[y/N]{1} " -f $script:Yellow, $script:Reset) -NoNewline
  $run = [Console]::ReadLine()
  $result.Ids = $ids
  $result.RunNow = ($run -match '^[Yy]')
  return $result
}
