# plan.ps1: render the resolved Plan as a plain-language preview + the single
# confirm gate. The pwsh mirror of plan.sh. Depends on common.ps1 (colours),
# meta.ps1/os.ps1/run.ps1 (Test-StepSatisfied, Test-BlockRuns), instructions.ps1
# (Get-CanonicalPath). 5.1-safe.
#
# The imperative shell runs Windows-only (apply.ps1 guards non-Windows), so the
# "what will happen" wording is Windows: an honest UAC narration in place of
# mac's Homebrew/password line. The CLI agents (Claude Code, Codex) install
# per-user with NO UAC - the critical path - but Node.js and Git install
# machine-wide via winget and each raise one UAC prompt (Node ships a
# machine-scoped MSI; Git for Windows is a per-machine Inno installer).

# The accent colour for a step's [kind] badge (mirrors plan.sh's _kind_colour).
function Get-KindColour {
  param([string]$Kind)
  switch ($Kind) {
    'harness' { $script:Magenta }
    'app'     { $script:Magenta }
    'auth'    { $script:Yellow }
    'tool'    { $script:Cyan }
    'mcp'     { $script:Blue }
    'skill'   { $script:Green }
    default   { $script:Dim }
  }
}

# Test-StepSatisfied <root> <id> - mirror the block's own cheap probe so the gate
# can dim steps already in place. Reads SATISFIED_<os> (the gate-only escape
# hatch) else CHECK_<os> (the install skip predicate). Returns 0 = satisfied,
# 1 = actionable but not done, 2 = unmapped (no cell -> neutral row).
function Test-StepSatisfied {
  param([string]$Root, [string]$Id)
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) { return 2 }
  $cell = Get-Meta $dir ("SATISFIED_" + (Get-VibeOsKey))
  if (-not $cell) { $cell = Get-Meta $dir ("CHECK_" + (Get-VibeOsKey)) }
  if (-not $cell) { return 2 }
  # A probe that errors (e.g. winget absent) reads as actionable, never a crash.
  try {
    if (Invoke-Expression $cell) { return 0 } else { return 1 }
  } catch {
    return 1
  }
}

# Show-Plan <plan> <root> [-Full] [-Force] - print the ordered steps, the agent
# that will launch, and the "what will happen" heads-up. -Full (the --plan dry-run
# + wizard) also prints the canonical file, the linked harness paths, and the
# material files - author/debug detail omitted at the novice confirm gate.
function Show-Plan {
  param(
    [Parameter(Mandatory)] $Plan,
    [Parameter(Mandatory)] [string]$Root,
    [switch]$Full,
    [bool]$Force = $false
  )

  Write-Host ""
  Write-Host '  This will set up:'
  Hrule
  Write-Host ''

  # Instruction blocks back off when the canonical file already exists. Compute
  # that once so the skipped-row tag and the "leaves it as-is" bullet agree.
  $instrBackoff = $false
  if ($Plan.Targets.Count -gt 0 -and -not $Force -and (Test-Path -LiteralPath (Get-CanonicalPath))) {
    $instrBackoff = $true
  }

  $done = 0; $actionable = 0
  for ($i = 0; $i -lt $Plan.StepIds.Count; $i++) {
    $id = $Plan.StepIds[$i]
    $kind = $Plan.StepKinds[$i]
    $desc = $Plan.StepDescs[$i]

    # Render-rule: a block with no cell for this OS and no script tail (e.g. mise
    # on Windows, pulled in but node-installs-via-winget there) is a dead row -
    # skip it unless it is an instructions block.
    if ($kind -ne 'instructions' -and -not (Test-BlockRuns $Root $id)) { continue }

    $rc = Test-StepSatisfied $Root $id
    if ($rc -eq 0) { $actionable++; $done++ }
    elseif ($rc -eq 1) { $actionable++ }

    $badge = "[$kind]".PadRight(14)
    if ($rc -eq 0) {
      Write-Host ("    {0}{1} {2}{3}  {4}{5}{3}" -f $script:Dim, $badge, $desc, $script:Reset, $script:Green, ([char]0x2713 + ' already set up'))
    } elseif ($kind -eq 'instructions' -and $instrBackoff) {
      Write-Host ("    {0}{1} {2}{3}  {0}{4}{3}" -f $script:Dim, $badge, $desc, $script:Reset, ([char]0x21B7 + ' skipped (file exists)'))
    } else {
      Write-Host ("    {0}{1}{2} {3}" -f (Get-KindColour $kind), $badge, $script:Reset, $desc)
    }
  }

  Write-Host ''
  Write-Host ("  Agent to launch: {0}{1}{2}" -f $script:Bold, $Plan.DefaultHarness, $script:Reset)

  if ($Full -and $Plan.Targets.Count -gt 0) {
    Write-Host ("  Instructions file: {0}" -f (Get-CanonicalPath))
    Write-Host '  linked from:'
    foreach ($t in $Plan.Targets) { Write-Host ("    {0}" -f (Expand-VibeHome $t)) }
  }

  if ($Full) {
    Write-Host ''
    Write-Host ("  {0}Files this will create or change{1}" -f $script:Bold, $script:Reset)
    switch -Regex ($Plan.DefaultHarness) {
      '^claude' { Write-Host ("    {0}  (marks first-project trusted, and skips Claude's first-run onboarding screen)" -f (Join-Path $HOME '.claude.json')) }
      '^codex'  { Write-Host ("    {0}  (marks first-project trusted)" -f (Join-Path $HOME '.codex\config.toml')) }
    }
    if ($Plan.StepIds -contains 'git') {
      Write-Host ("    {0}  (your name, email, and default branch)" -f (Join-Path $HOME '.gitconfig'))
    }
  }

  Show-Expectations -Plan $Plan -Force $Force -InstrBackoff $instrBackoff -Done $done -Actionable $actionable
  Write-Host ''
}

# Show-Expectations - set honest expectations from the resolved plan + a couple of
# cheap probes. Windows wording: the UAC narration replaces mac's Homebrew line.
function Show-Expectations {
  param($Plan, [bool]$Force, [bool]$InstrBackoff, [int]$Done, [int]$Actionable)

  switch -Regex ($Plan.DefaultHarness) {
    '^claude' { $acct = 'Claude' }
    '^codex'  { $acct = 'Codex' }
    default   { $acct = $Plan.DefaultHarness }
  }

  Write-Host ''
  Write-Host ("  {0}What will happen{1}" -f $script:Bold, $script:Reset)

  # UAC narration - the honest analogue of mac's "password once". CLI agents are
  # the no-UAC critical path; winget-installed Node/Git each raise one prompt.
  Add-Expectation "Claude Code and Codex install just for you - no admin prompt."
  $needsWinget = @('node', 'git', 'gh-auth', 'claude-desktop', 'codex-desktop') | Where-Object { $Plan.StepIds -contains $_ }
  if (($Plan.StepIds -contains 'node') -or ($Plan.StepIds -contains 'git')) {
    Add-Expectation "Node.js and Git install for everyone via winget - Windows asks permission once for each."
  } elseif ($needsWinget) {
    Add-Expectation "Some apps install via winget - Windows may ask permission once."
  }

  if ($Plan.Targets.Count -gt 0) {
    if ($Force) {
      Add-Expectation "Rebuilds your one instructions file, backing up any existing one to .bak."
    } elseif ($InstrBackoff) {
      Add-Expectation "You already have an instructions file - vibe leaves it as-is and won't merge in new guidance (re-run with --force to rebuild it)."
    } else {
      Add-Expectation "Creates one instructions file that your agent reads every session."
    }
  }

  if ($Plan.DefaultHarness -eq 'claude' -and (Test-Path -LiteralPath (Join-Path $HOME '.claude.json'))) {
    Add-Expectation "You already have a Claude config, so vibe won't change its trust settings - you may see a one-time 'trust this folder?' prompt."
  } else {
    Add-Expectation "Marks your first-project folder as trusted, so $acct won't keep asking permission to work there."
  }

  if ($Plan.StepIds -contains 'git') {
    Add-Expectation "Makes sure git has your name and email (from your GitHub account) and makes 'main' the default branch for new projects."
  }
  if ($Plan.StepIds -contains 'gh-auth') {
    Add-Expectation "You'll also sign into GitHub - create a free account first if you don't have one."
  }
  Add-Expectation "At the end you'll sign into your $acct account in the browser - create one first if you don't have it."

  if ($Actionable -gt 0 -and $Done -eq $Actionable) {
    Add-Expectation "Everything installable is already in place - vibe will just link things up and drop you into $acct."
  }
  Add-Expectation ("The agent works in {0} and asks before changing files or running commands." -f (Get-StarterDir))
}

# Add-Expectation <text>: one expectation bullet, the dim > glyph.
function Add-Expectation {
  param([string]$Text)
  Write-Host ("    {0}{1}{2} {3}" -f $script:Dim, [char]0x203A, $script:Reset, $Text)
}

# Confirm-Plan: the one interactive gate. $true = proceed, $false = abort. No
# terminal (input redirected) aborts rather than guessing - callers pass -Yes.
function Confirm-Plan {
  if ([Console]::IsInputRedirected) {
    Err 'No terminal to confirm. Re-run with -Yes to proceed non-interactively.'
    return $false
  }
  Write-Host ("`n  {0}Press Enter to set up{1} {2}.{1} {2}Ctrl-C to cancel{1} " -f $script:Bold, $script:Reset, $script:Dim) -NoNewline
  $reply = [Console]::ReadLine()
  if ($reply -eq '' -or $reply -match '^[Yy]') { return $true }
  return $false
}
