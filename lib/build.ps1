# build.ps1: the author-facing wizard, the pwsh mirror of build.sh. Assembles a
# valid bundle interactively, previews the exact plan the novice will see, and
# emits the shareable one-paste commands - BOTH the mac curl line and the Windows
# irm line, so an author on either OS can share the right paste for their
# audience. Read-only. Depends on meta.ps1 + resolve.ps1 + plan.ps1 + common.ps1.
# 5.1-safe.

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

# Invoke-VibeWizard <root> - drive the interactive build. Returns an object with
# .Ids (chosen ids, harness first) and .RunNow ($true iff apply-now was asked).
# On no answers (input redirected) or an invalid choice, .Ids is empty + .RunNow
# $false.
function Invoke-VibeWizard {
  param([string]$Root)
  $result = [pscustomobject]@{ Ids = @(); RunNow = $false }

  $harnesses = @()
  foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $Root 'blocks') -Directory | Sort-Object Name)) {
    if ((Get-Meta $d.FullName 'KIND') -eq 'harness') { $harnesses += $d.Name }
  }
  if ($harnesses.Count -eq 0) { Err "no harness blocks found under $Root/blocks"; return $result }

  Write-Host ("`n  Which agent should launch? {0}(required){1}`n" -f $script:Dim, $script:Reset)
  $defaultNum = 1
  for ($i = 0; $i -lt $harnesses.Count; $i++) {
    if ($harnesses[$i] -eq 'claude-cli') { $defaultNum = $i + 1 }
    $dir = Get-BlockDir $Root $harnesses[$i]
    Write-Host ("    {0}{1}){2} {0}{3}{2}  {4}" -f $script:Bold, ($i + 1), $script:Reset, $harnesses[$i], (Get-Meta $dir 'DESC'))
  }

  Write-Host ("`n  Choose {0}[{1}]{2}: " -f $script:Yellow, $defaultNum, $script:Reset) -NoNewline
  if ([Console]::IsInputRedirected) {
    Write-Host ''
    Err "No answers on stdin - the wizard needs a terminal. Run '-List' to browse, then 'vibe _ <id>...'."
    return $result
  }
  $choice = [Console]::ReadLine()
  $num = if ($choice -eq '') { $defaultNum } elseif ($choice -match '^[0-9]+$') { [int]$choice } else { 0 }
  if ($num -lt 1 -or $num -gt $harnesses.Count) { Err "Choose a number between 1 and $($harnesses.Count)."; return $result }
  $ids = @($harnesses[$num - 1])

  # Optional blocks, grouped by kind (harness/preset skipped).
  $rows = @()
  foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $Root 'blocks') -Directory | Sort-Object Name)) {
    $kind = Get-Meta $d.FullName 'KIND'
    if ($kind -eq 'harness' -or $kind -eq 'preset') { continue }
    $rows += [pscustomobject]@{ Rank = Get-KindRank $kind; Id = $d.Name; Kind = $kind }
  }
  Write-Host ("`n  Add optional blocks - {0}y{1} to include, Enter to skip:" -f $script:Bold, $script:Reset)
  $last = ''
  foreach ($r in ($rows | Sort-Object Rank, Id)) {
    if ($r.Kind -ne $last) { Write-Host ("`n  {0}{1}{2}" -f $script:Bold, $r.Kind, $script:Reset); $last = $r.Kind }
    $dir = Get-BlockDir $Root $r.Id
    Write-Host ("    {0}{1}{2}  {3} {4}[y/N]{2} " -f $script:Bold, $r.Id, $script:Reset, (Get-Meta $dir 'DESC'), $script:Yellow) -NoNewline
    $reply = [Console]::ReadLine()
    if ($reply -match '^[Yy]') { $ids += $r.Id }
  }

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
