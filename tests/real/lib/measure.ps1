#!/usr/bin/env pwsh
# measure.ps1: the measurements taken BOTH before a run (precheck.ps1) and after it
# (probe.ps1) - the Windows twin of lib/measure.sh, and for the same reason: the
# judge asserts a DELTA, and a delta between two subtly different questions is not
# one. Dot-sourced, not executed.
#
# The REGISTRY PATH, never $env:PATH. The PowerShell spine persists no PATH of its
# own (there is no shellpath.ps1), so Windows relies entirely on each installer's own
# registry edit - and the harness's own $GITHUB_PATH additions live in the process
# environment, where they would mask a missing entry.
#
# BOTH scopes, recorded separately as well as combined. "Does a new terminal find it"
# is the union, so that is what the judge asserts a delta on. But the runner images
# ship Git, Node and gh on the MACHINE PATH, so reading the scopes only as a total
# made `shell.regpath.git 1` a fact about the image; keeping the scopes apart is what
# makes a log bundle say which one it was.
#
# Windows PowerShell 5.1-clean: no ternary, no ??, no && / ||, no OS automatic
# variables.

# Functions rather than variables: a dot-sourced script's variables read as
# assigned-but-never-used to PSScriptAnalyzer, and suppressing that rule is worse
# than spelling the accessor.
function Get-VibeMeasureTool { return @('claude', 'codex', 'gh', 'git', 'node', 'pnpm', 'mise') }
function Get-VibeMeasureScope { return @('User', 'Machine') }

function Get-VibeRegPathDir {
  param([string]$Scope)
  $dirs = @()
  $raw = [Environment]::GetEnvironmentVariable('Path', $Scope)
  if ([string]::IsNullOrWhiteSpace($raw)) { return $dirs }
  foreach ($d in ($raw -split ';')) {
    if ([string]::IsNullOrWhiteSpace($d)) { continue }
    $dirs += [Environment]::ExpandEnvironmentVariables($d.Trim())
  }
  return $dirs
}

# Test-VibeRegPathResolves - would a new terminal find <Tool> in these dirs?
#
# $env:PATHEXT rather than a hand-written list, and a FILE rather than any entry: a
# DIRECTORY named `node` on PATH and npm's extensionless MSYS shim (which cmd.exe
# cannot execute) both resolved under the old list, and neither is a working install.
function Test-VibeRegPathResolves {
  param([string]$Tool, [string[]]$Dirs)
  $exts = @()
  if (-not [string]::IsNullOrWhiteSpace($env:PATHEXT)) { $exts = $env:PATHEXT -split ';' }
  if ($exts.Count -eq 0) { $exts = @('.COM', '.EXE', '.BAT', '.CMD') }
  foreach ($d in $Dirs) {
    if ([string]::IsNullOrWhiteSpace($d)) { continue }
    foreach ($e in $exts) {
      if ([string]::IsNullOrWhiteSpace($e)) { continue }
      $p = Join-Path $d ($Tool + $e.Trim())
      if (Test-Path -LiteralPath $p -PathType Leaf) { return $true }
    }
  }
  return $false
}
