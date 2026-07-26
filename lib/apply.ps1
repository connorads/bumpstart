#!/usr/bin/env pwsh
# apply.ps1: the applier, the pwsh mirror of apply.sh. Resolve an id list to a
# Plan (pure core), print the plan, gate on a single confirm, apply each block,
# link instructions, pre-seed trust, launch the agent.
#
#   pwsh -File lib/apply.ps1 [-Plan] [-Yes] [-NoLaunch] [-List] [-Show <id>]
#                            [-Build] [-Force] <id>...
#
# $env:VIBE_ROOT overrides the repo root (the test seam). Windows-only at run
# time (guarded below); the pure core above ran cross-platform. Structured as a
# function + a run-only-when-executed guard so the tests can dot-source it and
# drive Invoke-VibeSetup in-process with shadowed installers. 5.1-safe.

[CmdletBinding()]
param(
  [switch]$Plan,
  [switch]$Yes,
  [switch]$NoLaunch,
  [switch]$List,
  [string]$Show,
  [switch]$Build,
  [switch]$Force,
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Ids
)

. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/os.ps1"
. "$PSScriptRoot/meta.ps1"
. "$PSScriptRoot/run.ps1"
. "$PSScriptRoot/resolve.ps1"
. "$PSScriptRoot/instructions.ps1"
. "$PSScriptRoot/plan.ps1"
. "$PSScriptRoot/trust.ps1"
. "$PSScriptRoot/catalogue.ps1"
. "$PSScriptRoot/build.ps1"

# Ensure-Winget: a soft check + narration, NOT a hard installer. winget ships on
# Windows 10 1809+/11; when absent the CLI agents' own per-user installers still
# cover the critical path, so we warn and continue rather than block.
function Ensure-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Success 'winget is available'
  } else {
    Warn 'winget not found - the app installs may be skipped, but the CLI agents still install on their own.'
  }
}

# Invoke-BlockTail <root> <id>: run a block's apply.ps1 (its interactive tail) in
# a child scope with the block contract in the environment. Missing tail = a
# silent skip (pure-data blocks install declaratively via Invoke-Cell). Non-fatal.
function Invoke-BlockTail {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  $tail = Join-Path $dir 'apply.ps1'
  if (-not (Test-Path -LiteralPath $tail)) { return }
  $env:VIBE_LIB = $PSScriptRoot
  $env:VIBE_ROOT = $Root
  $env:VIBE_BLOCK_DIR = $dir
  $env:VIBE_BLOCK_ID = $Id
  try { & $tail } catch { Warn "block '$Id' failed - continuing" }
}

function Invoke-VibeSetup {
  [CmdletBinding()]
  param(
    [switch]$Plan,
    [switch]$Yes,
    [switch]$NoLaunch,
    [switch]$List,
    [string]$Show,
    [switch]$Build,
    [switch]$Force,
    [string[]]$Ids
  )

  $root = if ($env:VIBE_ROOT) { $env:VIBE_ROOT } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
  if (-not $Ids) { $Ids = @() }

  # Author-facing discovery (read-only; before resolve, which errors on empty).
  if ($List) { Show-Catalogue $root; return 0 }
  if ($Show) { if (Show-Block $root $Show) { return 0 } else { return 1 } }
  if ($Build) {
    $wiz = Invoke-VibeWizard $root
    if (-not $wiz.RunNow) { return 0 }
    $Ids = $wiz.Ids
  }

  # Platform guard: everything below is Windows-specific. An honest redirect (the
  # mirror of apply.sh's Darwin guard). Exit 0 - informational, not a failure.
  if ((Get-VibeOs) -ne 'win') {
    Info 'This is the Windows setup. On a Mac, use the macOS paste from the README instead.'
    return 0
  }

  if ($Ids.Count -eq 0) { $Ids = @('web-starter') }

  $resolved = Resolve-Plan $root $Ids
  if ($resolved.Error) { Err $resolved.Error; return 1 }

  if ($Plan) { Show-Plan -Plan $resolved -Root $root -Full -Force:$Force; return 0 }

  Show-Plan -Plan $resolved -Root $root -Force:$Force
  if (-not $Yes) {
    if (-not (Confirm-Plan)) { Err 'Aborted.'; return 1 }
  }

  Write-Host ("`n  {0}{1}vibe-setup{2}" -f $script:Bold, $script:Cyan, $script:Reset)
  Write-Host ("  {0}let's get you building{1}" -f $script:Dim, $script:Reset)

  Write-Host ("`n  {0}{1}[.]{2} {0}Preparing Windows{2}" -f $script:Bold, $script:Cyan, $script:Reset)
  Ensure-Winget

  # Count blocks that do real work (declarative cell or apply.ps1 tail).
  $total = 0
  foreach ($id in $resolved.StepIds) { if (Test-BlockRuns $root $id) { $total++ } }

  $cur = 0
  for ($i = 0; $i -lt $resolved.StepIds.Count; $i++) {
    $id = $resolved.StepIds[$i]
    if (Test-BlockRuns $root $id) {
      $cur++
      Step $cur $total $resolved.StepDescs[$i]
    }
    Invoke-Cell $root $id
    Invoke-BlockTail $root $id
  }

  Write-Host ''
  Hrule
  Success 'Setup complete.'
  Write-Host ("  {0}You're all set - the hard part is done.{1}" -f $script:Green, $script:Reset)

  # Instructions: assemble the canonical file, then link each harness to it via
  # its per-OS method (import for Claude, copy for Codex).
  $script:LinkBackoffs = @()
  Assemble-Instructions -Plan $resolved -Root $root -Force:$Force
  $key = Get-VibeOsKey
  $linked = New-Object System.Collections.Generic.HashSet[string]
  for ($i = 0; $i -lt $resolved.StepIds.Count; $i++) {
    if ($resolved.StepKinds[$i] -ne 'harness') { continue }
    $dir = Get-BlockDir $root $resolved.StepIds[$i]
    $target = Get-Meta $dir ("TARGET_" + $key)
    if (-not $target -or -not $linked.Add($target)) { continue }
    $method = Get-Meta $dir ("LINK_" + $key)
    if (-not $method) { $method = 'copy' }
    Link-Harness -TargetLiteral $target -Method $method -Force:$Force
  }

  $canon = Get-CanonicalPath
  if ($script:InstructionsWrote) {
    Write-Host ''
    Info 'Your agent instructions live in one file:'
    Write-Host "    $canon"
    Info 'Both Claude and Codex read it.'
  } elseif ($script:InstructionsBackedOff) {
    Write-Host ''
    Info 'You already have an instructions file here - left as-is:'
    Write-Host "    $canon"
    Info 'Re-run with -Force to replace it.'
  }
  if ($script:LinkBackoffs.Count -gt 0) {
    Write-Host ''
    Warn 'These agent config files already exist and were left untouched:'
    foreach ($b in $script:LinkBackoffs) { Write-Host "    $b" }
    Warn "Point them at $canon yourself, or re-run with -Force."
  }

  # Starter project + trust preseed.
  $starter = New-StarterDir
  Set-VibeTrust $resolved.DefaultHarness $starter
  if ($resolved.StepIds -contains 'git') { Initialize-StarterRepo $starter }

  Set-VibePath
  Copy-StarterPrompt $root

  if (-not $NoLaunch -and (Get-Command $resolved.DefaultHarness -ErrorAction SilentlyContinue)) {
    Show-LoginFrame $resolved.DefaultHarness
    Wait-Enter "Press Enter to open $($resolved.DefaultHarness) and sign in"
    Set-Location -LiteralPath $starter
    & $resolved.DefaultHarness
  } else {
    Write-Host ''
    Info "Run '$($resolved.DefaultHarness)' in $starter to start (you'll sign in on first launch)."
    if ($script:StarterPromptCopied) {
      Info 'A starter message is on your clipboard - press Ctrl+V at the agent prompt, then Enter.'
    }
  }
  return 0
}

# Run only when executed directly (pwsh -File ...), not when dot-sourced by tests.
if ($MyInvocation.InvocationName -ne '.') {
  $rc = Invoke-VibeSetup -Plan:$Plan -Yes:$Yes -NoLaunch:$NoLaunch -List:$List -Show $Show -Build:$Build -Force:$Force -Ids $Ids
  exit $rc
}
