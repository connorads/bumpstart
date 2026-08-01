#!/usr/bin/env pwsh
# bootstrap.ps1: install the pinned PowerShell test/lint modules (Pester +
# PSScriptAnalyzer) to the CurrentUser scope. Idempotent - a module already at
# the pinned version is left untouched. Run once locally before the pwsh tasks;
# CI runs the identical command, so local green means CI green.
#
# ASCII only, like every lib/*.ps1 (which encode their glyphs as [char]0x203A):
# non-ASCII bytes without a BOM are what PSUseBOMForUnicodeEncodedFile flags, and
# a BOM is the worse fix - 5.1 and pwsh 7 disagree about writing them.
#
# Versions are pinned here (queried from PSGallery at authoring time, not
# hardcoded from memory). Bump deliberately.

$ErrorActionPreference = 'Stop'

$Modules = @(
  @{ Name = 'Pester';           Version = '5.9.0' },
  @{ Name = 'PSScriptAnalyzer'; Version = '1.25.0' }
)

# Ensure the NuGet package provider + a trusted PSGallery so Install-Module never
# prompts in a non-interactive shell (CI, agent).
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}

foreach ($m in $Modules) {
  $name = $m.Name
  $version = $m.Version
  $have = Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -eq [version]$version }
  if ($have) {
    Write-Host "$name $version already installed"
    continue
  }
  Write-Host "Installing $name $version ..."
  Install-Module -Name $name -RequiredVersion $version -Repository PSGallery `
    -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
  Write-Host "$name $version installed"
}
