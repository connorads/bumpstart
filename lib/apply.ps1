#!/usr/bin/env pwsh
# apply.ps1: the applier, the pwsh mirror of apply.sh. Resolve an id list to a
# Plan (pure core), print the plan, gate on a single confirm, apply each block,
# link instructions, pre-seed trust, launch the agent.
#
#   pwsh -File lib/apply.ps1 [-Plan] [-Yes] [-NoLaunch] [-List] [-Show <id>]
#                            [-Build] [-Force] <id>...
#
# $env:BUMP_ROOT overrides the repo root (the test seam). Windows-only at run
# time (guarded below); the pure core above ran cross-platform. Structured as a
# function + a run-only-when-executed guard so the tests can dot-source it and
# drive Invoke-BumpSetup in-process with shadowed installers. 5.1-safe.

# PositionalBinding off so the mode flags (-Show <id>, etc.) never swallow a bare
# id: only -Ids is positional, and it collects every remaining bare arg.
[CmdletBinding(PositionalBinding = $false)]
param(
  [switch]$Plan,
  [switch]$Yes,
  [switch]$NoLaunch,
  [switch]$List,
  [string]$Show,
  [switch]$Build,
  [switch]$Force,
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)] [string[]]$Ids
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
. "$PSScriptRoot/shellpath.ps1"

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
#
# BUMP_YES carries -Yes into the block. Without it a block can only ask "is stdin
# redirected", which on a real console is no - so -Yes, whose whole promise is that
# nothing stops to ask, would still stop at a block's prompt. Mirrors apply.sh.
function Invoke-BlockTail {
  param([string]$Root, [string]$Id, [bool]$Yes)
  $dir = Get-BlockDir $Root $Id
  $tail = Join-Path $dir 'apply.ps1'
  if (-not (Test-Path -LiteralPath $tail)) { return }
  $env:BUMP_LIB = $PSScriptRoot
  $env:BUMP_ROOT = $Root
  $env:BUMP_BLOCK_DIR = $dir
  $env:BUMP_BLOCK_ID = $Id
  if ($Yes) { $env:BUMP_YES = '1' } else { Remove-Item Env:BUMP_YES -ErrorAction SilentlyContinue }
  try { & $tail } catch {
    Warn "block '$Id' failed - continuing"
    Add-BumpWarning (Get-BlockLabel $Root $Id)
  }
}

# Required preparation uses terminating filesystem errors and contributes to the
# final verdict. Output is retained for steps such as creating the project folder.
function Invoke-BumpPreparation {
  param([string]$Label, [scriptblock]$Action)
  $ErrorActionPreference = 'Stop'
  try { & $Action } catch {
    Warn "$Label failed - $($_.Exception.Message)"
    Add-BumpWarning $Label
  }
}

function Invoke-BumpSetup {
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

  # Native tools can write diagnostics to stderr without failing. Keep the
  # install loop non-terminating; individual filesystem operations must opt into
  # terminating errors so their failures can be recorded. Function scope keeps
  # this preference out of callers that dot-source the applier.
  $ErrorActionPreference = 'Continue'

  $root = if ($env:BUMP_ROOT) { $env:BUMP_ROOT } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
  if (-not $Ids) { $Ids = @() }

  # Author-facing discovery (read-only; before resolve, which errors on empty).
  if ($List) { Show-Catalogue $root; return 0 }
  if ($Show) { if (Show-Block $root $Show) { return 0 } else { return 1 } }
  if ($Build) {
    $wiz = Invoke-BumpWizard $root
    if (-not $wiz.RunNow) { return 0 }
    $Ids = $wiz.Ids
  }

  # Platform guard: everything below is Windows-specific. An honest redirect (the
  # mirror of apply.sh's Darwin guard). Exit 0 - informational, not a failure.
  if ((Get-BumpOs) -ne 'win') {
    Info 'This is the Windows setup. On a Mac, use the macOS paste from the README instead.'
    return 0
  }

  # Bare paste: one id per axis - which agent (an account choice) and which
  # stack+habits. Swapping agent is one word.
  if ($Ids.Count -eq 0) { $Ids = @('claude', 'starter') }

  $resolved = Resolve-Plan $root $Ids
  if ($resolved.Error) { Err $resolved.Error; return 1 }

  if ($Plan) { Show-Plan -Plan $resolved -Root $root -Full -Force:$Force; return 0 }

  Show-Plan -Plan $resolved -Root $root -Force:$Force
  if (-not $Yes) {
    if (-not (Confirm-Plan)) { Err 'Aborted.'; return 1 }
  }

  Write-Host ("`n  {0}{1}bumpstart{2}" -f $script:Bold, $script:Cyan, $script:Reset)
  Write-Host ("  {0}let's get you building{1}" -f $script:Dim, $script:Reset)

  Write-Host ("`n  {0}{1}[.]{2} {0}Preparing Windows{2}" -f $script:Bold, $script:Cyan, $script:Reset)
  Ensure-Winget

  # Per-run state, reset here rather than at load: the tests dot-source this file
  # once and drive Invoke-BumpSetup repeatedly, so a load-time-only ledger would
  # carry one run's failures into the next.
  $script:BumpWarnCount = 0
  $script:BumpWarnItems = @()
  $script:BumpLaunch = ''
  $script:BumpLaunchDir = ''

  # After confirmation and before the vendor installer, so its PATH diagnostics
  # describe the environment that will also be used to launch the agent.
  Invoke-BumpPreparation 'Account PATH' { Set-BumpPersistedPath; Set-BumpPath }

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
    Invoke-BlockTail $root $id ([bool]$Yes)
  }

  # Instructions: assemble the canonical file, then link each harness to it via
  # its per-OS method (import for Claude, copy for Codex).
  #
  # Straight off the Plan, as apply.sh reads PLAN_TARGETS. Re-walking the steps
  # here instead re-derived the list and lost both of the resolver's rules doing
  # it: the content gate (no content in the plan -> nothing to point at) and the
  # TARGET_<OS>-then-TARGET fallback. Net effect on Windows: `-Ids claude-cli`
  # wrote ~/.claude/CLAUDE.md importing a canonical the assembler had returned
  # early rather than create.
  #
  # Linked only when the canonical actually EXISTS. The resolver gates targets on
  # "some block in the plan carries content"; the assembler additionally drops a
  # non-instruction block that does no work on this OS - so a plan whose only
  # content belongs to a block that doesn't run here resolves a target and writes
  # no file, and Claude's CLAUDE.md became an @import of a path that isn't there.
  #
  # Test-Path on the canonical rather than $script:InstructionsWrote: the back-off
  # branch returns without setting Wrote, and it is only reachable when a
  # canonical already exists. So "exists" covers the fresh write, the back-off,
  # and a canonical left by an earlier run, and excludes exactly the broken case.
  $script:LinkBackoffs = @()
  Invoke-BumpPreparation 'Agent instructions' { Assemble-Instructions -Plan $resolved -Root $root -Force:$Force }
  if (Test-Path -LiteralPath (Get-CanonicalPath)) {
    for ($i = 0; $i -lt $resolved.Targets.Count; $i++) {
      Invoke-BumpPreparation 'Agent instruction link' {
        Link-Harness -TargetLiteral $resolved.Targets[$i] -Method $resolved.TargetMethods[$i] -Force:$Force
      }
    }
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

  $starter = Invoke-BumpPreparation 'Starter project' { New-StarterDir }
  if ($starter) {
    Invoke-BumpPreparation 'Agent trust' { Set-BumpTrust $resolved.DefaultHarness $starter }
    if ($resolved.StepIds -contains 'git') {
      Invoke-BumpPreparation 'Project git repository' { Initialize-StarterRepo $starter }
    }
    Invoke-BumpPreparation 'Starter message' { Copy-StarterPrompt $root }
  }

  if (-not (Test-BumpCommand $resolved.DefaultHarness)) {
    Err "$($resolved.DefaultHarness) isn't installed or cannot run, so there's nothing to open yet."
    $harnessId = $resolved.StepIds | Where-Object {
      (Get-Meta (Get-BlockDir $root $_) 'AGENT') -eq $resolved.DefaultHarness
    } | Select-Object -First 1
    Add-BumpWarning (Get-BlockLabel $root $harnessId)
  }

  Write-Host ''
  Hrule
  if ($script:BumpWarnCount -gt 0) {
    if ($script:BumpWarnCount -eq 1) {
      Warn "Setup finished, but one step didn't work:"
    } else {
      Warn "Setup finished, but $($script:BumpWarnCount) steps didn't work:"
    }
    foreach ($w in $script:BumpWarnItems) { Write-Host "    $w" }
    Info "Read the errors above, then re-run the same paste - it retries only what's missing."
    return 1
  }
  Success 'Setup complete.'
  Write-Host ("  {0}You're all set - the hard part is done.{1}" -f $script:Green, $script:Reset)

  if (-not $NoLaunch) {
    Show-LoginFrame $resolved.DefaultHarness
    Wait-Enter "Press Enter to open $($resolved.DefaultHarness) and sign in"
    # The intent is RECORDED here and carried out at the tail, outside the value
    # this function returns. Two reasons, both fatal to running it here. This
    # function's return value is read as the process exit code, so anything the
    # agent printed would ride back beside the code - and `exit @('chatter', 1)`
    # exits 0, so a printing agent would mask a failure. And a native command
    # inside a captured pipeline is handed a pipe rather than the terminal, so on
    # a real console the agent's TUI would open with no tty.
    $script:BumpLaunch = $resolved.DefaultHarness
    $script:BumpLaunchDir = $starter
  } else {
    Write-Host ''
    Info "Run '$($resolved.DefaultHarness)' in $starter to start (you'll sign in on first launch)."
    if ($script:StarterPromptCopied) {
      Info 'A starter message is on your clipboard - press Ctrl+V at the agent prompt, then Enter.'
    } elseif ($script:StarterPromptFile) {
      Info "A starter message is saved in $($script:StarterPromptFile) - paste it in as your first message."
    }
  }
  return 0
}

# Run only when executed directly (pwsh -File ...), not when dot-sourced by tests.
if ($MyInvocation.InvocationName -ne '.') {
  $rc = Invoke-BumpSetup -Plan:$Plan -Yes:$Yes -NoLaunch:$NoLaunch -List:$List -Show $Show -Build:$Build -Force:$Force -Ids $Ids
  # Outside the assignment above, deliberately - see the launch branch. The exit
  # code stays the setup's verdict; the agent is what the person does next.
  if ($script:BumpLaunch) {
    Set-Location -LiteralPath $script:BumpLaunchDir
    & $script:BumpLaunch
  }
  exit $rc
}
