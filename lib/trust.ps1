# trust.ps1: create a starter project we control and best-effort pre-seed harness
# trust, so the novice meets exactly one prompt - the browser login - not also a
# trust dialog. The pwsh mirror of trust.sh. We only ever pre-trust the starter
# dir we create, never an arbitrary/cloned repo. Depends on common.ps1. 5.1-safe.
#
# Windows defensiveness: a harness may normalise the project path differently
# (drive-letter case, / vs \), so we write the trust entry under every plausible
# spelling. If none matches at run time the fallback is one honest click.

# Get-StarterDir - the dedicated starter dir under the ~/git convention (display
# form; not necessarily created yet). Never blanket-trust $HOME.
function Get-StarterDir { return (Join-Path (Join-Path $HOME 'git') 'first-project') }

# New-StarterDir - create the starter project, return its resolved real path (the
# key both harnesses match trust against). The pwd -P analogue.
function New-StarterDir {
  $dir = Get-StarterDir
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  return (Get-Item -LiteralPath $dir).FullName
}

# Get-VibePathVariants <path> - distinct spellings of a Windows path a harness
# might store trust under: as-is, all-forward-slash, all-back-slash, and the
# drive-letter case toggled for each. Deduped, order-stable.
function Get-VibePathVariants {
  param([string]$Path)
  $forms = New-Object System.Collections.Generic.List[string]
  foreach ($p in @($Path, ($Path -replace '\\', '/'), ($Path -replace '/', '\'))) {
    $forms.Add($p)
    if ($p.Length -ge 2 -and $p[1] -eq ':') {
      $drive = $p.Substring(0, 1)
      $rest = $p.Substring(1)
      $toggled = if ($drive -cmatch '[A-Z]') { $drive.ToLower() } else { $drive.ToUpper() }
      $forms.Add("$toggled$rest")
    }
  }
  $seen = New-Object System.Collections.Generic.HashSet[string]
  $out = @()
  foreach ($f in $forms) { if ($seen.Add($f)) { $out += $f } }
  return $out
}

# Initialize-StarterRepo <dir> - make the starter project a real git repo so the
# agent has somewhere to commit. No-op if it already is one; needs git on PATH
# (the caller only invokes this when the git block ran). Non-fatal.
function Initialize-StarterRepo {
  param([string]$Dir)
  if (Test-Path -LiteralPath (Join-Path $Dir '.git')) { return }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
  git -C $Dir init -b main *> $null
  if ($LASTEXITCODE -ne 0) { git -C $Dir init *> $null }
  if ($LASTEXITCODE -eq 0) {
    Success 'Made your project a git project (so we can save your work)'
  } else {
    Warn "couldn't set up git in your project - continuing"
  }
}

# Set-CodexTrust <path> - mark the dir trusted in ~/.codex/config.toml. Global
# approval_policy/--yolo do NOT suppress the per-dir prompt; a trusted project
# entry does. Append-idempotent, one section per path variant.
function Set-CodexTrust {
  param([string]$Path)
  $cfg = Join-Path (Join-Path $HOME '.codex') 'config.toml'
  New-Item -ItemType Directory -Path (Split-Path -Parent $cfg) -Force | Out-Null
  $existing = if (Test-Path -LiteralPath $cfg) { Get-Content -LiteralPath $cfg -Raw } else { '' }

  $wrote = $false
  foreach ($v in (Get-VibePathVariants $Path)) {
    $header = "[projects.`"$v`"]"
    if ($existing.Contains($header)) { continue }
    if ((Test-Path -LiteralPath $cfg) -and (Get-Item -LiteralPath $cfg).Length -gt 0) {
      Add-Content -LiteralPath $cfg -Value ''
    }
    Add-Content -LiteralPath $cfg -Value $header
    Add-Content -LiteralPath $cfg -Value 'trust_level = "trusted"'
    $existing += "`n$header`ntrust_level = `"trusted`""
    $wrote = $true
  }
  if ($wrote) { Success "Pre-trusted $Path for Codex" } else { Success "Codex already trusts $Path" }
}

# Set-ClaudeTrust <path> - best-effort onboarding + trust in ~/.claude.json. The
# schema is undocumented and version-fragile, so we only seed the file when
# ABSENT - never edit an existing config. Writes the trust key under every path
# variant so a differently-normalising harness still finds a trusted entry.
function Set-ClaudeTrust {
  param([string]$Path)
  $json = Join-Path $HOME '.claude.json'
  if (Test-Path -LiteralPath $json) {
    Info 'Claude config already exists - leaving it; you may see a one-time trust prompt.'
    return
  }
  $projects = [ordered]@{}
  foreach ($v in (Get-VibePathVariants $Path)) {
    $projects[$v] = [ordered]@{ hasTrustDialogAccepted = $true }
  }
  $obj = [ordered]@{
    hasCompletedOnboarding = $true
    projects               = $projects
  }
  New-Item -ItemType Directory -Path (Split-Path -Parent $json) -Force | Out-Null
  Set-Content -LiteralPath $json -Value ($obj | ConvertTo-Json -Depth 5)
  Success "Pre-trusted $Path for Claude (best-effort)"
}

# Set-VibeTrust <harness> <path> - dispatch to the harness-specific seeder.
function Set-VibeTrust {
  param([string]$Harness, [string]$Path)
  switch ($Harness) {
    'claude' { Set-ClaudeTrust $Path }
    'codex'  { Set-CodexTrust $Path }
    default  { }
  }
}

# Copy-StarterPrompt <root> - put the friendly first message on the clipboard so
# it survives the browser sign-in. Reads <root>/starter-prompt.txt (no-op if
# missing/empty). Falls back to printing it when no clipboard is available.
function Copy-StarterPrompt {
  param([string]$Root)
  $script:StarterPromptCopied = $false
  $file = Join-Path $Root 'starter-prompt.txt'
  if (-not (Test-Path -LiteralPath $file)) { return }
  $text = (Get-Content -LiteralPath $file -Raw)
  if ([string]::IsNullOrWhiteSpace($text)) { return }
  if (Copy-ToClipboard $text) {
    $script:StarterPromptCopied = $true
  } else {
    Write-Host ''
    Info 'Copy this and paste it as your first message to the agent:'
    Write-Host "`n$text`n"
  }
}

# Show-LoginFrame <harness> - reassure the novice about the one prompt that stays,
# and (when copied) point at the starter message on the clipboard.
function Show-LoginFrame {
  param([string]$Harness)
  Write-Host ''
  Info "Almost there - $Harness will open your browser to sign in."
  Info 'Sign in there, then come back to this window.'
  if ($script:StarterPromptCopied) {
    Info "I've put a starter message on your clipboard to get you going."
    Info "When you're back and see the empty prompt box, press Ctrl+V to paste it, then Enter."
  }
  Write-Host ''
}
