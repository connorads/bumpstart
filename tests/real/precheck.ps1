#!/usr/bin/env pwsh
# precheck.ps1: run INSIDE a Windows guest BEFORE the real run, and write the
# baseline every later assertion is measured against. The pwsh twin of precheck.sh,
# emitting the same `precheck.<key><TAB><value>` shape so the ONE judge decides every
# lane.
#
#   powershell.exe -File tests\real\precheck.ps1 -Baseline precheck.tsv
#
# Why it exists: the runner images ship Git, Node and gh on the Machine PATH, so
# vibe's SATISFIED_WIN cells find them and the INSTALL_WIN cells for Git.Git,
# OpenJS.NodeJS.LTS and GitHub.cli never run - while the probe reported
# `shell.regpath.git 1` and the judge counted that as a pass. Measuring the same
# thing before the run is what tells "vibe installed it" apart from "the image had
# it".
#
# Windows PowerShell 5.1-clean, run under powershell.exe deliberately: the runner's
# default is pwsh 7, which would silently defeat the 5.1 floor these tests protect.

[CmdletBinding()]
param(
  # Write here rather than to stdout: Windows PowerShell's `>` writes UTF-16LE, which
  # the judge's awk reads as binary. Empty means stdout.
  #
  # NOT named -Out: CmdletBinding adds -OutVariable and -OutBuffer, so `-Out` is an
  # ambiguous prefix and binding fails with no file and a zero exit status.
  [string]$Baseline = ''
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'lib\measure.ps1')

$lines = New-Object System.Collections.ArrayList
$tab = [char]9

function Emit-Precheck {
  param([string]$Key, $Value)
  $null = $lines.Add("precheck.$Key$tab" + [string]$Value)
}

function Emit-PrecheckBool {
  param([string]$Key, [bool]$Value)
  if ($Value) { Emit-Precheck $Key 1 } else { Emit-Precheck $Key 0 }
}

# -- What the machine already has ---------------------------------------------
#
# Emitted with the same key names the POSIX precheck uses, so the judge's axis
# assertions are one branch rather than two.

foreach ($t in @('curl', 'wget', 'git', 'gpg', 'brew')) {
  if (Get-Command $t -ErrorAction SilentlyContinue) {
    Emit-Precheck $t 'present'
  } else {
    Emit-Precheck $t 'absent'
  }
}

# No sudo here, and no rc file: persistence on this spine is a registry value, so
# there is no marker to find. Recorded explicitly rather than omitted, because the
# judge fails closed on an absent key and "there is no such thing on Windows" is a
# different fact from "nobody measured it".
Emit-Precheck 'nopasswd' 'absent'
Emit-Precheck 'vibe_marker' 'absent'
Emit-Precheck 'shell.kind' 'registry'

# -- The baseline the registry-PATH assertions are a delta against -------------

$scopeDirs = @{}
$allDirs = @()
foreach ($scope in (Get-BumpMeasureScope)) {
  $d = @(Get-BumpRegPathDir $scope)
  $scopeDirs[$scope] = $d
  $allDirs += $d
}
foreach ($t in (Get-BumpMeasureTool)) {
  foreach ($scope in (Get-BumpMeasureScope)) {
    Emit-PrecheckBool ("shell.regpath." + $scope.ToLower() + ".$t") (Test-BumpRegPathResolves $t $scopeDirs[$scope])
  }
  Emit-PrecheckBool "shell.regpath.$t" (Test-BumpRegPathResolves $t $allDirs)
}

# The User PATH itself, raw, beside those booleans. They say whether a lookup now
# succeeds; this says what the value WAS, so a delta can name what changed rather than
# only that something did - and it is the User scope because that is the one vibe
# writes. Tabs out, because the value lands in a TSV manifest verbatim.
Emit-Precheck 'regpath.user.raw' ((Get-BumpUserRegPathRaw) -replace "`t", ' ')

# -- Write it out --------------------------------------------------------------

$body = ($lines -join "`n") + "`n"
if ([string]::IsNullOrWhiteSpace($Baseline)) {
  Write-Output $body
} else {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Baseline, $body, $enc)
}
exit 0
