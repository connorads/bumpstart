# instructions.ps1: assemble the canonical agent-instructions file and link each
# installed harness's native path to it. The pwsh mirror of instructions.sh, with
# the Windows linking difference: no symlink. Claude uses an @import line, Codex a
# physical copy (Codex has no import). Depends on common.ps1 + meta.ps1 + os.ps1 +
# run.ps1. 5.1-safe.
#
# Outputs consumed by the finish message (apply.ps1), as script-scoped vars:
#   $script:InstructionsWrote      canonical (re)written this run
#   $script:InstructionsBackedOff  a canonical existed and we left it as-is
#   $script:LinkBackoffs           native paths we refused to overwrite

# Get-CanonicalPath - the single editable source of truth: ~/.agents/AGENTS.md,
# the one agents root. No $env:XDG_CONFIG_HOME branch - ~/.agents is not an XDG
# path, so honouring the variable there would be incoherent. Mirrors
# canonical_path in instructions.sh.
function Get-CanonicalPath {
  return (Join-Path (Join-Path $HOME '.agents') 'AGENTS.md')
}

# Assemble-Instructions <plan> <root> <force> - concatenate each in-plan block's
# content (per-OS content.<os>.md preferred over content.md), one blank line
# between sections, and write the canonical file. A non-instruction block that
# does no work on this OS is skipped (its guidance would describe a tool we didn't
# install). No content anywhere -> no-op. Canonical present without force -> back
# off.
#
# Section order is instruction blocks first, then everything else, each group in
# StepIds order. Content order is PRESENTATION, not execution: letting KIND's step
# rank also decide section order put reference material ahead of the behavioural
# frame. Two sequential passes, not a re-sort - relative order within a group
# still follows the plan. Mirrors assemble_instructions in instructions.sh.
function Assemble-Instructions {
  param($Plan, [string]$Root, [bool]$Force)
  $script:InstructionsWrote = $false
  $script:InstructionsBackedOff = $false

  $osTok = Get-VibeOs
  $sections = @()
  foreach ($pass in 1, 2) {
    foreach ($id in $Plan.StepIds) {
      $dir = Get-BlockDir $Root $id
      $kind = Get-Meta $dir 'KIND'
      # Pass 1 takes the instruction blocks, pass 2 the rest.
      if ($pass -eq 1 -and $kind -ne 'instructions') { continue }
      if ($pass -eq 2 -and $kind -eq 'instructions') { continue }
      if ($kind -ne 'instructions' -and -not (Test-BlockRuns $Root $id)) { continue }

      $content = Join-Path $dir "content.$osTok.md"
      if (-not (Test-Path -LiteralPath $content)) { $content = Join-Path $dir 'content.md' }
      if (Test-Path -LiteralPath $content) {
        $sections += ((Get-Content -LiteralPath $content -Raw).TrimEnd("`r", "`n"))
      }
    }
  }

  if ($sections.Count -eq 0) { return }
  $buf = ($sections -join "`n`n")

  $canon = Get-CanonicalPath
  if ((Test-Path -LiteralPath $canon) -and -not $Force) {
    $script:InstructionsBackedOff = $true
    return
  }

  New-Item -ItemType Directory -Path (Split-Path -Parent $canon) -Force | Out-Null
  # Only reachable under -Force (the no-force path backed off above), and the
  # confirm gate promises "backing up any existing one to .bak" - so make good on
  # it before the clobber. The canonical is the file the user edits.
  if (Test-Path -LiteralPath $canon) { Backup-VibeFile $canon }
  Set-Content -LiteralPath $canon -Value $buf -NoNewline
  Add-Content -LiteralPath $canon -Value ''   # trailing newline, matching bash printf '%s\n'
  $script:InstructionsWrote = $true
}

# Link-Harness <targetLiteral> <method> <force> - point a harness at the canonical
# file. Windows has no symlink here:
#   import (Claude) -> ensure TARGET holds a single bare `@<canonical-abs>` line
#   copy   (Codex)  -> write the canonical's contents to TARGET (re-copied each run)
# Idempotent. A foreign real file is backed off (recorded in $script:LinkBackoffs)
# unless -Force, which moves it to .bak first.
function Link-Harness {
  param([string]$TargetLiteral, [string]$Method, [bool]$Force)
  $canon = Get-CanonicalPath
  $target = Expand-VibeHome $TargetLiteral
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null

  if ($Method -eq 'import') {
    # A single bare `@<abs-path>` line, unfenced (a path inside a code fence is
    # NOT imported). Anthropic recommends @import over symlink on Windows.
    $line = "@$canon"
    if (Test-Path -LiteralPath $target) {
      $existing = (Get-Content -LiteralPath $target -Raw)
      if ($existing.Trim() -eq $line) { return }           # already our import line
      if (-not $Force) { $script:LinkBackoffs += $target; return }
      Backup-VibeFile $target
    }
    Set-Content -LiteralPath $target -Value $line
    Success "Pointed $target at your instructions file"
    return
  }

  if ($Method -eq 'copy') {
    # Codex has no import, so a physical copy is required. Re-copy every run
    # (idempotent by content); .bak a foreign file under -Force.
    $content = if (Test-Path -LiteralPath $canon) { Get-Content -LiteralPath $canon -Raw } else { '' }
    if (Test-Path -LiteralPath $target) {
      $existing = (Get-Content -LiteralPath $target -Raw)
      if ($existing -eq $content) { return }               # already a current copy
      if ($Force) { Backup-VibeFile $target }
      elseif (-not (Test-VibeCopyOwned $target)) {          # foreign file, no force
        $script:LinkBackoffs += $target; return
      }
      # else: our own stale copy -> overwrite in place
    }
    Set-Content -LiteralPath $target -Value $content -NoNewline
    Success "Copied your instructions to $target"
    return
  }
}

# Test-VibeCopyOwned <target>: a heuristic - a Codex copy target we own starts
# with one of the canonical section headers ("## "). A truly foreign AGENTS.md is
# left alone unless -Force. Conservative: unknown -> foreign.
function Test-VibeCopyOwned {
  param([string]$Target)
  if (-not (Test-Path -LiteralPath $Target)) { return $true }
  $first = (Get-Content -LiteralPath $Target -TotalCount 1)
  return ($first -like '## *' -or [string]::IsNullOrWhiteSpace($first))
}

# Backup-VibeFile <path>: move a file to <path>.bak (timestamp-suffixed if taken).
# The wall-clock stamp mirrors _backup_file in instructions.sh, so the same
# scenario names the same .bak on both spines.
function Backup-VibeFile {
  param([string]$Path)
  $bak = "$Path.bak"
  if (Test-Path -LiteralPath $bak) {
    $bak = "$Path.bak." + (Get-Date -Format 'yyyyMMddHHmmss')
  }
  Move-Item -LiteralPath $Path -Destination $bak -Force
  Success "Backed up $Path to $bak"
}
