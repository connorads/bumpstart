#!/usr/bin/env pwsh
# lint-automatic-os-vars.ps1: the greppable-invariant layer of the Windows
# PowerShell 5.1 floor. The PSUseCompatible* rules flag 7-only cmdlets/types/
# syntax but NOT the $IsWindows/$IsMacOS/$IsLinux automatic variables — under 5.1
# those are $null, so an unguarded use silently misbehaves. Only lib/os.ps1 is
# allowed to reference them (behind its PSEdition-first guard). Fail otherwise.
#
# Written in pwsh (not shell grep) so it runs identically on macOS and
# windows-latest.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$libDir = Join-Path $root 'lib'
$pattern = '\$IsWindows|\$IsMacOS|\$IsLinux'

$hits = Get-ChildItem -LiteralPath $libDir -Filter '*.ps1' -Recurse |
  Where-Object { $_.Name -ne 'os.ps1' } |
  Select-String -Pattern $pattern

if ($hits) {
  Write-Host 'OS automatic variables used outside lib/os.ps1 (they are $null under Windows PowerShell 5.1):'
  foreach ($h in $hits) {
    Write-Host ("  {0}:{1}: {2}" -f $h.Path, $h.LineNumber, $h.Line.Trim())
  }
  exit 1
}

Write-Host 'OK: no OS automatic variables outside lib/os.ps1'
exit 0
