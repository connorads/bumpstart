#!/usr/bin/env pwsh
# bumpstart.ps1: fetch the bumpstart repo at $env:BUMP_REF and hand the id list to the
# applier. The Windows one-paste bootstrap, the mirror of the `bumpstart` bash script.
#
#   irm https://raw.githubusercontent.com/connorads/bumpstart/main/bumpstart.ps1 | iex
#   & ([scriptblock]::Create((irm .../bumpstart.ps1))) claude starter   # with ids
#   $env:BUMP_REF='<sha>'; irm .../bumpstart.ps1 | iex               # pinned workshop
#
# Windows PowerShell 5.1-safe: this is the default shell on a fresh Windows, so
# the bootstrap must run there. It prefers pwsh 7 if already on PATH but never
# requires it.
$ErrorActionPreference = 'Stop'
$ref = if ($env:BUMP_REF) { $env:BUMP_REF } else { 'main' }
$repo = 'connorads/bumpstart'

# Windows-only - say so before fetching. 5.1 leaves $IsWindows unset and is
# Windows-only, so Desktop edition => Windows. The mirror of the bash Darwin guard.
$isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
if (-not $isWin) {
  Write-Host 'This is the Windows paste. On a Mac, use the macOS one-liner from the README.'
  return
}

# PowerShell 7 has separate managed-policy settings. Check the incoming host
# before selecting another one, so a host switch cannot evade its restrictions.
$checkPolicy = {
  foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
    $policy = Get-ExecutionPolicy -Scope $scope
    if ($policy -in @('Restricted', 'AllSigned')) {
      Write-Host "bumpstart: managed execution policy ($scope=$policy) blocks this unsigned setup. Contact your administrator."
      exit 1
    }
    if ($policy -ne 'Undefined') { break }
  }
}
& $checkPolicy

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('bumpstart-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$tgz = Join-Path $tmp 'src.tar.gz'
try {
  Invoke-RestMethod -Uri "https://codeload.github.com/$repo/tar.gz/$ref" -OutFile $tgz
  tar -xzf $tgz -C $tmp
  if ($LASTEXITCODE -ne 0) { throw "archive extraction failed ($LASTEXITCODE)" }
} catch {
  Write-Host "bumpstart: could not fetch $repo@$ref - check the ref and your connection."
  exit 1
}

# The extracted top-level dir is named after the ref (e.g. bumpstart-main); glob.
$root = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
$apply = if ($root) { Join-Path $root.FullName 'lib/apply.ps1' } else { $null }
if (-not $apply -or -not (Test-Path -LiteralPath $apply)) {
  Write-Host "bumpstart: unexpected tarball layout under $tmp"
  exit 1
}

# A child keeps the execution-policy override scoped to setup. The calling
# terminal and registry policy are unchanged; Group Policy still takes precedence.
$pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$hostExe = if ($pwsh) { $pwsh.Source } else { Join-Path $PSHOME 'powershell.exe' }
try {
  # The policy cmdlet's module must load under an inherited Restricted policy.
  # The process override still leaves MachinePolicy and UserPolicy authoritative.
  & $hostExe -NoProfile -ExecutionPolicy Bypass -Command $checkPolicy.ToString()
  if ($LASTEXITCODE -ne 0) { exit 1 }
  & $hostExe -NoProfile -ExecutionPolicy Bypass -File $apply @args
  exit $LASTEXITCODE
} catch {
  Write-Host "bumpstart: could not start setup - $($_.Exception.Message)"
  exit 1
}
