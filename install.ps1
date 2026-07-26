#!/usr/bin/env pwsh
# install.ps1: the Windows one-paste entry, the mirror of install.sh. Delegates to
# the applier locally when run from a clone, otherwise bootstraps via vibe.ps1
# (which fetches the repo). No ids -> the applier's bare-paste default
# (web-starter), the full beginner setup. 5.1-safe.
#
#   irm https://raw.githubusercontent.com/connorads/vibe-setup/main/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$repo = 'connorads/vibe-setup'

$here = if ($PSScriptRoot) { $PSScriptRoot } else { '' }
$localApply = if ($here) { Join-Path $here 'lib/apply.ps1' } else { '' }

if ($localApply -and (Test-Path -LiteralPath $localApply)) {
  & $localApply @args
} else {
  $boot = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$repo/main/vibe.ps1"
  & ([scriptblock]::Create($boot)) @args
}
