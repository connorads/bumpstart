#!/usr/bin/env pwsh
# lint-automatic-os-vars.ps1: the greppable-invariant layer of the Windows
# PowerShell 5.1 floor. The PSUseCompatible* rules flag 7-only cmdlets/types/
# syntax but NOT the $IsWindows/$IsMacOS/$IsLinux automatic variables — under 5.1
# those are $null, so an unguarded use silently misbehaves. Fail on any use
# outside the allow-list.
#
# Every SHIPPED .ps1 is scanned, not just lib/ — a block tail and the bootstrap
# run on the same 5.1 as the spine, so scoping this to one directory left the
# invariant true only where someone happened to look.
#
# Allow-listed, both because they read the automatics ONLY after a
# $PSVersionTable.PSEdition test (which is the correct 5.1-safe order):
#   lib/os.ps1  the OS decision itself, the seam every other module reads
#   vibe.ps1    the bootstrap's Windows guard, before anything is fetched
#
# Written in pwsh (not shell grep) so it runs identically on macOS and
# windows-latest.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pattern = '\$IsWindows|\$IsMacOS|\$IsLinux'
$allowed = @('os.ps1', 'vibe.ps1')
# tests/ and scripts/ are excluded: neither ships to a Windows 5.1 machine.
$scanDirs = @('lib', 'blocks') | ForEach-Object { Join-Path $root $_ }
$scanFiles = @('vibe.ps1', 'install.ps1', 'bootstrap.ps1') | ForEach-Object { Join-Path $root $_ }

$hits = @(
  (Get-ChildItem -LiteralPath $scanDirs -Filter '*.ps1' -Recurse)
  (Get-Item -LiteralPath $scanFiles)
) | Where-Object { $allowed -notcontains $_.Name } |
  Select-String -Pattern $pattern

if ($hits) {
  Write-Host ('OS automatic variables used outside {0} (they are $null under Windows PowerShell 5.1):' -f ($allowed -join ', '))
  foreach ($h in $hits) {
    Write-Host ("  {0}:{1}: {2}" -f $h.Path, $h.LineNumber, $h.Line.Trim())
  }
  exit 1
}

Write-Host ('OK: no OS automatic variables outside {0}' -f ($allowed -join ', '))
exit 0
