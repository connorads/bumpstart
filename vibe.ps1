#!/usr/bin/env pwsh
# vibe.ps1: fetch the vibe-setup repo at $env:VIBE_REF and hand the id list to the
# applier. The Windows one-paste bootstrap, the mirror of the `vibe` bash script.
#
#   irm https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe.ps1 | iex
#   & ([scriptblock]::Create((irm .../vibe.ps1))) web-starter   # with ids
#   $env:VIBE_REF='<sha>'; irm .../vibe.ps1 | iex               # pinned workshop
#
# Windows PowerShell 5.1-safe: this is the default shell on a fresh Windows, so
# the bootstrap must run there. It prefers pwsh 7 if already on PATH but never
# requires it.
$ErrorActionPreference = 'Stop'
$ref = if ($env:VIBE_REF) { $env:VIBE_REF } else { 'main' }
$repo = 'connorads/vibe-setup'

# Windows-only - say so before fetching. 5.1 leaves $IsWindows unset and is
# Windows-only, so Desktop edition => Windows. The mirror of the bash Darwin guard.
$isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
if (-not $isWin) {
  Write-Host 'This is the Windows paste. On a Mac, use the macOS one-liner from the README.'
  return
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vibe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$tgz = Join-Path $tmp 'src.tar.gz'
try {
  Invoke-RestMethod -Uri "https://codeload.github.com/$repo/tar.gz/$ref" -OutFile $tgz
  tar -xzf $tgz -C $tmp
} catch {
  Write-Host "vibe: could not fetch $repo@$ref - check the ref and your connection."
  return
}

# The extracted top-level dir is named after the ref (e.g. vibe-setup-main); glob.
$root = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
$apply = if ($root) { Join-Path $root.FullName 'lib/apply.ps1' } else { $null }
if (-not $apply -or -not (Test-Path -LiteralPath $apply)) {
  Write-Host "vibe: unexpected tarball layout under $tmp"
  return
}

# Prefer pwsh 7 if on PATH (nicer UX); otherwise run under the current 5.1.
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) {
  & $pwsh.Source -NoProfile -File $apply @args
} else {
  & $apply @args
}
