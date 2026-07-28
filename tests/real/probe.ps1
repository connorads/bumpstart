#!/usr/bin/env pwsh
# probe.ps1: run INSIDE a Windows guest after a real install and write the state
# manifest. The pwsh twin of probe.sh, emitting the same key<TAB>value shape so the
# ONE judge (tests/real/judge.sh) decides every lane.
#
#   powershell.exe -File tests\real\probe.ps1 -StateDir C:\vibe-real -Manifest out.tsv
#
# It gathers and normalises; it judges nothing.
#
# Windows PowerShell 5.1-clean, and run under powershell.exe deliberately: the
# runner's default is pwsh 7, which would silently defeat the 5.1 floor these tests
# exist to protect. No ternary, no ??, no && / ||, no OS automatic variables.
#
# Two Windows differences the manifest has to carry, both real:
#   - The PowerShell spine persists NO PATH of its own (there is no shellpath.ps1);
#     Windows relies entirely on each installer's own registry edit. So the
#     fresh-shell measurement reads the registry PATH, NEVER $env:PATH - the
#     harness's own $GITHUB_PATH additions live in the process environment, where
#     they would mask a missing entry. BOTH scopes, kept apart as well as combined:
#     "a new terminal finds it" is the union, but the runner images ship Git, Node
#     and gh on the MACHINE PATH, so the union alone is a fact about the image. What
#     makes it a fact about vibe is precheck.ps1's baseline and the judge's delta.
#   - There are no symlinks here. Claude gets an `@<canonical>` import line, Codex a
#     physical copy (Link-Harness in lib/instructions.ps1), so instructions.link.* is
#     `import:<path>` / `copy:current` rather than `symlink:<target>`.

[CmdletBinding()]
param(
  # Where the lane runner left lane.tsv / precheck.tsv / transcript.log / exit.
  [string]$StateDir = 'C:\vibe-real',
  # Write here rather than to stdout: Windows PowerShell's `>` writes UTF-16LE,
  # which the judge's awk cannot read. Empty means stdout.
  #
  # NOT named -Out: CmdletBinding adds -OutVariable and -OutBuffer, so `-Out` is an
  # ambiguous prefix and binding fails with no manifest and a zero exit status.
  [string]$Manifest = ''
)

$ErrorActionPreference = 'Continue'

# The registry-PATH measurement is shared with precheck.ps1, which takes it BEFORE
# the run. The judge asserts the difference, so the two have to be one piece of code.
. (Join-Path $PSScriptRoot 'lib\measure.ps1')

$lines = New-Object System.Collections.ArrayList
$tab = [char]9

# -- Normalisation -------------------------------------------------------------
#
# $HOME out, backslashes out of paths, single line, no tabs - because the host
# driver compares manifests across runs, across entry points and across guests. The
# hostname is pinned by the adapter rather than normalised here.

function Format-VibeText {
  param([string]$Value)
  if ($null -eq $Value) { return '' }
  $v = $Value -replace "`t", ' '
  $v = $v -replace "`r", ''
  $v = $v -replace "`n", ' '
  # Both separators, because a path reaches us either way on Windows.
  $v = $v.Replace($HOME.Replace('\', '/'), '$HOME')
  $v = $v.Replace($HOME, '$HOME')
  return $v.TrimEnd()
}

function Format-VibePath {
  param([string]$Value)
  if ($null -eq $Value) { return '' }
  return (Format-VibeText ($Value -replace '\\', '/'))
}

function Emit {
  param([string]$Key, $Value)
  $null = $lines.Add("$Key$tab" + (Format-VibeText ([string]$Value)))
}

function Emit-Path {
  param([string]$Key, $Value)
  $null = $lines.Add("$Key$tab" + (Format-VibePath ([string]$Value)))
}

function Emit-Bool {
  param([string]$Key, [bool]$Value)
  if ($Value) { Emit $Key 1 } else { Emit $Key 0 }
}

# -- What only the runner knows ------------------------------------------------

$null = $lines.Add('# vibe real-install state manifest')
# 2 added the precheck's baseline, which the judge's delta assertions require.
Emit 'manifest_version' 2

# Non-empty, not merely present: the runner truncates before it fills, so a precheck
# that died part-way leaves an EMPTY file - no marker, no keys, and a harness failure
# reported as a page of "nothing was measured", which reads as a vibe failure. An
# empty measurement is a missing one.
foreach ($pass in @('lane', 'precheck')) {
  $f = Join-Path $StateDir "$pass.tsv"
  if ((Test-Path -LiteralPath $f) -and ((Get-Item -LiteralPath $f).Length -gt 0)) {
    foreach ($l in (Get-Content -Encoding UTF8 -LiteralPath $f)) {
      if ([string]::IsNullOrWhiteSpace($l)) { continue }
      if ($l.StartsWith('#')) { continue }
      $null = $lines.Add(($l -replace "`r", ''))
    }
  } else {
    Emit "probe.missing.$pass" 1
  }
}

# -- The machine ---------------------------------------------------------------

Emit 'os' 'win'
# No root here. Emitted for the record; the judge skips it on Windows, because
# "not root" is what makes the POSIX sudo paths non-vacuous and has no analogue.
Emit 'env.root' 0
Emit 'env.userns.restricted' 'none'

$exitFile = Join-Path $StateDir 'exit'
if (Test-Path -LiteralPath $exitFile) {
  Emit 'transcript.exit' ((Get-Content -Encoding UTF8 -LiteralPath $exitFile -TotalCount 1) -replace '\s', '')
} else {
  Emit 'probe.missing.exit' 1
}

# -- The transcript: the verdict, and every warning behind it ------------------
#
# lib/apply.ps1 exits 0 even when steps warned, and its UI goes to Write-Host, so
# the runner captures every stream and the verdict comes from the TEXT. The finish
# strings are byte-identical to the bash spine's, so one parser serves both.

# -Encoding UTF8 on every read below, and it is load-bearing, not tidiness. Windows
# PowerShell 5.1 defaults Get-Content to the ANSI code page, so a BOM-less UTF-8
# transcript decodes with the non-ASCII glyphs mangled - the info() and error()
# prefixes are U+203A and U+2717, so info.* and error.* were SILENTLY never emitted,
# and derived.userns_fix_printed reads info.*. The runner writes the transcript as
# UTF-8 without a BOM through .NET for the same reason.
$log = Join-Path $StateDir 'transcript.log'
if (Test-Path -LiteralPath $log) {
  $text = Get-Content -Encoding UTF8 -LiteralPath $log -Raw
  if ($null -eq $text) { $text = '' }
  if ($text.Contains('Setup complete.')) {
    Emit 'transcript.verdict' 'clean'
  } elseif ($text.Contains('Setup finished, but')) {
    Emit 'transcript.verdict' 'warned'
  } else {
    Emit 'transcript.verdict' 'aborted'
  }

  # The glyph is the channel: Warn is "  ! ", Info "  <U+203A> ", Err "  <U+2717> ".
  $glyphs = @(
    @{ Key = 'warn';  Prefix = '  ! ' },
    @{ Key = 'info';  Prefix = ('  ' + [char]0x203A + ' ') },
    @{ Key = 'error'; Prefix = ('  ' + [char]0x2717 + ' ') }
  )
  foreach ($g in $glyphs) {
    $n = 0
    foreach ($l in (Get-Content -Encoding UTF8 -LiteralPath $log)) {
      $line = $l -replace "`r", ''
      if (-not $line.StartsWith($g.Prefix)) { continue }
      $body = $line.Substring($g.Prefix.Length)
      if ([string]::IsNullOrWhiteSpace($body)) { continue }
      $n++
      Emit ("{0}.{1:d4}" -f $g.Key, $n) $body
    }
    if ($g.Key -eq 'warn') { Emit 'transcript.warn_count' $n }
  }
} else {
  Emit 'probe.missing.transcript' 1
}

# -- Every installed tool's binary really RUNS --------------------------------
#
# On the run's own PATH plus vibe's install dirs, because this asks "did
# acquisition work" - a different question from "does a new terminal find it".
# `--version` rather than Get-Command: the faked suite's claude IS a stub, so a
# binary that executes is the whole point, and it catches a wrong-arch install.

$sep = [System.IO.Path]::PathSeparator
$probeDirs = @(
  (Join-Path $HOME '.local\bin')
  (Join-Path $HOME '.codex\bin')
)
if ($env:APPDATA) { $probeDirs += (Join-Path $env:APPDATA 'npm') }
if ($env:ProgramFiles) { $probeDirs += (Join-Path $env:ProgramFiles 'nodejs') }
if ($env:LOCALAPPDATA) { $probeDirs += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links') }

$savedPath = $env:PATH
foreach ($d in $probeDirs) {
  if (Test-Path -LiteralPath $d) { $env:PATH = "$d$sep$($env:PATH)" }
}

$tools = Get-VibeMeasureTool
foreach ($t in $tools) {
  $ran = $false
  $ver = 'absent'
  $cmd = Get-Command $t -ErrorAction SilentlyContinue
  if ($cmd) {
    # Reset FIRST. Get-Command is a cmdlet and does not touch $LASTEXITCODE, so on
    # the first iteration this compared $null to 0 - and on every later one it
    # compared the PREVIOUS tool's status, which is how tool.<t>.runs could read 0
    # for a working tool and 1 for a broken one. lib/common.ps1's Invoke-Spin resets
    # it for exactly this reason.
    $global:LASTEXITCODE = 0
    $out = (& $t --version 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) {
      $ran = $true
      $ver = $out.Trim()
    }
  }
  Emit-Bool "tool.$t.runs" $ran
  Emit "tool.$t.version_raw" $ver
}
$env:PATH = $savedPath

# -- A FRESH shell finds them: the REGISTRY PATH, not $env:PATH ---------------
#
# As a DELTA, exactly like the POSIX fresh-shell measurement: precheck.ps1 takes the
# same reading before the run, and the judge asserts the difference. Per scope as
# well as combined, because the runner images ship Git, Node and gh on the MACHINE
# PATH - so the union alone said "1" for tools no lane here ever installed.

$regScopeDirs = @{}
$regDirs = @()
foreach ($scope in (Get-VibeMeasureScope)) {
  $d = @(Get-VibeRegPathDir $scope)
  $regScopeDirs[$scope] = $d
  $regDirs += $d
}

Emit 'shell.kind' 'registry'
foreach ($t in $tools) {
  foreach ($scope in (Get-VibeMeasureScope)) {
    Emit-Bool ("shell.regpath." + $scope.ToLower() + ".$t") (Test-VibeRegPathResolves $t $regScopeDirs[$scope])
  }
  Emit-Bool "shell.regpath.$t" (Test-VibeRegPathResolves $t $regDirs)
}

# No rc file on this spine, and no persisted PATH line, so the marker keys the
# POSIX lanes assert do not exist here. Recorded explicitly rather than omitted, so
# a reader of the manifest sees the difference is deliberate.
Emit 'rc.file' 'none'
Emit 'rc.persists_path' 0

# -- Desktop apps, by the exact ids the CHECK_WIN cells use ------------------

# Test-WingetPackage <id> [-Exact] - is this package installed?
#
# The EXIT STATUS decides, not a substring of the output. `winget list --id <id>`
# already exits non-zero when nothing matches ("No installed package found matching
# input criteria"), and matching text instead was wrong twice over: winget's list
# output is a human-facing TABLE that wraps at the console width, so a long id is
# split across lines and `.Contains()` misses it; and app.chatgpt was matched on a
# DISPLAY NAME, so any package whose name contained "ChatGPT" counted.
#
# -Exact mirrors each block's own CHECK_WIN cell rather than being chosen here: the
# probe's job is to measure what the product checks, and the codex-desktop block
# deliberately queries its msstore product id without -e.
#
# --accept-source-agreements because a first winget call on a fresh machine
# otherwise stops to ask, and this one has no terminal to ask on.
function Test-WingetPackage {
  param([string]$Id, [switch]$Exact)
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
  $global:LASTEXITCODE = 0
  if ($Exact) {
    $null = (winget list --id $Id -e --accept-source-agreements 2>&1 | Out-String)
  } else {
    $null = (winget list --id $Id --accept-source-agreements 2>&1 | Out-String)
  }
  return ($LASTEXITCODE -eq 0)
}

Emit-Bool 'app.claude' (Test-WingetPackage 'Anthropic.Claude' -Exact)
Emit-Bool 'app.github-desktop' (Test-WingetPackage 'GitHub.GitHubDesktop' -Exact)
# The Microsoft Store product id, exactly as blocks/codex-desktop/meta's CHECK_WIN
# and INSTALL_WIN cells spell it.
Emit-Bool 'app.chatgpt' (Test-WingetPackage '9PLM9XGG6VKS')

# -- safer-installs, at the paths the tools themselves read ------------------
#
# The block has no apply.ps1 yet, so it is a Windows no-op and the judge does not
# assert these - they are emitted anyway so the day an apply.ps1 lands, the lane
# starts measuring it without a probe change.

function Get-KvValue {
  param([string]$File, [string]$Separator, [string]$Key)
  if (-not (Test-Path -LiteralPath $File)) { return 'absent' }
  foreach ($l in (Get-Content -Encoding UTF8 -LiteralPath $File)) {
    $i = $l.IndexOf($Separator)
    if ($i -lt 1) { continue }
    $k = $l.Substring(0, $i).Trim()
    if ($k -ne $Key) { continue }
    $v = $l.Substring($i + $Separator.Length).Trim()
    return $v.Trim('"')
  }
  return 'absent'
}

$npmrc = Join-Path $HOME '.npmrc'
Emit 'npmrc.min-release-age' (Get-KvValue $npmrc '=' 'min-release-age')
Emit 'npmrc.allow-git' (Get-KvValue $npmrc '=' 'allow-git')
Emit 'npmrc.allow-remote' (Get-KvValue $npmrc '=' 'allow-remote')

$miseCfg = Join-Path $HOME '.config\mise\config.toml'
if ($env:XDG_CONFIG_HOME) { $miseCfg = Join-Path $env:XDG_CONFIG_HOME 'mise\config.toml' }
Emit 'mise.minimum_release_age' (Get-KvValue $miseCfg '=' 'minimum_release_age')

$pnpmCfg = Join-Path $HOME '.config\pnpm\config.yaml'
if ($env:XDG_CONFIG_HOME) { $pnpmCfg = Join-Path $env:XDG_CONFIG_HOME 'pnpm\config.yaml' }
if (Test-Path -LiteralPath $pnpmCfg) { Emit-Path 'pnpm.config' $pnpmCfg } else { Emit 'pnpm.config' 'absent' }
Emit 'pnpm.minimumReleaseAge' (Get-KvValue $pnpmCfg ':' 'minimumReleaseAge')
Emit 'pnpm.minimumReleaseAgeStrict' (Get-KvValue $pnpmCfg ':' 'minimumReleaseAgeStrict')

# -- Instructions, sampled ---------------------------------------------------

$canon = Join-Path (Join-Path $HOME '.agents') 'AGENTS.md'
Emit-Path 'instructions.canonical' $canon
$canonText = ''
if (Test-Path -LiteralPath $canon) {
  $canonText = (Get-Content -Encoding UTF8 -LiteralPath $canon -Raw)
  if ($null -eq $canonText) { $canonText = '' }
}
Emit-Bool 'instructions.canonical.nonempty' (-not [string]::IsNullOrWhiteSpace($canonText))

function Get-VibeHash {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}
Emit 'instructions.canonical.sha256' (Get-VibeHash $canon)

# Claude: a single bare `@<canonical>` line (a path inside a code fence is not
# imported, which is why the whole file has to be that one line).
$claudeTarget = Join-Path (Join-Path $HOME '.claude') 'CLAUDE.md'
$claudeState = 'absent'
if (Test-Path -LiteralPath $claudeTarget) {
  $t = (Get-Content -Encoding UTF8 -LiteralPath $claudeTarget -Raw)
  if ($null -eq $t) { $t = '' }
  if ($t.Trim() -eq "@$canon") {
    $claudeState = 'import:' + (Format-VibePath $canon)
  } else {
    $claudeState = 'file:' + (Get-VibeHash $claudeTarget)
  }
}
Emit 'instructions.link.claude' $claudeState

# Codex: a physical copy, re-copied each run, so "current" means byte-identical to
# the canonical right now.
$codexTarget = Join-Path (Join-Path $HOME '.codex') 'AGENTS.md'
$codexState = 'absent'
if (Test-Path -LiteralPath $codexTarget) {
  $t = (Get-Content -Encoding UTF8 -LiteralPath $codexTarget -Raw)
  if ($null -eq $t) { $t = '' }
  if ($t -eq $canonText) { $codexState = 'copy:current' } else { $codexState = 'copy:stale' }
}
Emit 'instructions.link.codex' $codexState

Emit-Bool 'instructions.section.git' ($canonText.Contains('## Saving your work (git)'))
Emit-Bool 'instructions.section.node' ($canonText.Contains('## Node.js'))

# -- Every vibe-owned path: the differential's raw material ------------------

function Get-PathState {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
  $item = Get-Item -LiteralPath $Path -Force
  if ($item.PSIsContainer) { return 'dir' }
  return 'file:' + (Get-VibeHash $Path)
}

$owned = @(
  @{ Key = 'path.agents';       Path = $canon },
  @{ Key = 'path.claude-md';    Path = $claudeTarget },
  @{ Key = 'path.claude-json';  Path = (Join-Path $HOME '.claude.json') },
  @{ Key = 'path.codex-agents'; Path = $codexTarget },
  @{ Key = 'path.codex-config'; Path = (Join-Path $HOME '.codex\config.toml') },
  @{ Key = 'path.npmrc';        Path = $npmrc },
  @{ Key = 'path.mise-config';  Path = $miseCfg },
  @{ Key = 'path.pnpm-config';  Path = $pnpmCfg },
  @{ Key = 'path.starter';      Path = (Join-Path $HOME 'git\first-project') },
  @{ Key = 'path.starter-git';  Path = (Join-Path $HOME 'git\first-project\.git') }
)
foreach ($o in $owned) {
  Emit-Path $o.Key (Get-PathState $o.Path)
}

# -- Write it out ------------------------------------------------------------
#
# LF and UTF-8 without a BOM, written through .NET: `>` under Windows PowerShell
# 5.1 produces UTF-16LE, which the judge's awk reads as binary.

$body = ($lines -join "`n") + "`n"
if ([string]::IsNullOrWhiteSpace($Manifest)) {
  Write-Output $body
} else {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Manifest, $body, $enc)
}
exit 0
