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
  $cell = Get-Meta $dir ("SATISFIED_" + (Get-BumpOsKey))
  if (-not $cell) { $cell = Get-Meta $dir ("CHECK_" + (Get-BumpOsKey)) }
  if (-not $cell) { return 2 }
  # Read by the TRUTHINESS OF WHAT THE CELL RETURNS, not by an exit status - the
  # same model Test-BlockCheck uses, and the opposite of plan.sh's _step_satisfied.
  # A cell that emits unconditionally therefore dims its row at the gate forever.
  #
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

    # Will this row's guidance be merged? Keyed on *carries content*, not on KIND:
    # a tool block stacks a section into the canonical file too, and its "already
    # set up" (a binary probe) would otherwise imply guidance that was silently
    # not merged.
    $tag = ''
    if ($instrBackoff -and (Test-BlockHasContent (Get-BlockDir $Root $id))) {
      if ($kind -eq 'instructions') {
        $tag = [char]0x21B7 + ' skipped (file exists)'
      } else {
        $tag = [char]0x21B7 + ' guidance skipped'
      }
    }
    # The trailing state text, from two independent facts: is the step already
    # done, and will its guidance land.
    $state = ''
    if ($rc -eq 0) { $state = $script:Green + [char]0x2713 + ' already set up' + $script:Reset }
    if ($tag) {
      if ($state) { $state = $state + ' ' + $script:Dim + [char]0x00B7 + $script:Reset + ' ' }
      $state = $state + $script:Dim + $tag + $script:Reset
    }

    $badge = "[$kind]".PadRight(14)
    if ($state -and (($rc -eq 0) -or ($kind -eq 'instructions'))) {
      Write-Host ("    {0}{1} {2}{3}  {4}" -f $script:Dim, $badge, $desc, $script:Reset, $state)
    } elseif ($state) {
      Write-Host ("    {0}{1}{2} {3}  {4}" -f (Get-KindColour $kind), $badge, $script:Reset, $desc, $state)
    } else {
      Write-Host ("    {0}{1}{2} {3}" -f (Get-KindColour $kind), $badge, $script:Reset, $desc)
    }
  }

  Write-Host ''
  Write-Host ("  Agent to launch: {0}{1}{2}" -f $script:Bold, $Plan.DefaultHarness, $script:Reset)

  if ($Full -and $Plan.Targets.Count -gt 0) {
    Write-Host ("  Instructions file: {0}" -f (Get-CanonicalPath))
    Write-Host '  linked from:'
    foreach ($t in $Plan.Targets) { Write-Host ("    {0}" -f (Expand-BumpHome $t)) }
  }

  if ($Full) {
    Write-Host ''
    Write-Host ("  {0}Files this will create or change{1}" -f $script:Bold, $script:Reset)
    switch ($Plan.DefaultHarness) {
      'claude' { Write-Host ("    {0}  (marks first-project trusted, and skips Claude's first-run onboarding screen)" -f (Join-Path $HOME '.claude.json')) }
      'codex'  { Write-Host ("    {0}  (marks first-project trusted)" -f (Join-Path $HOME '.codex\config.toml')) }
    }
    if ($Plan.StepIds -contains 'git') {
      Write-Host ("    {0}  (your name, email, and default branch)" -f (Join-Path $HOME '.gitconfig'))
    }
  }

  Show-Expectations -Plan $Plan -Root $Root -Force $Force -InstrBackoff $instrBackoff -Done $done -Actionable $actionable
  Write-Host ''
}

# Get-AgentAccount <root> <agent> - the brand a person signs into for an agent,
# read from the harness block that declares that AGENT (its ACCOUNT cell). Data,
# not a lookup table, so a new harness block names itself with no code change.
function Get-AgentAccount {
  param([string]$Root, [string]$Agent)
  foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $Root 'blocks') -Directory)) {
    if ((Get-Meta $d.FullName 'AGENT') -ne $Agent) { continue }
    $cell = Get-Meta $d.FullName 'ACCOUNT'
    if ($cell) { return $cell }
    break
  }
  return $Agent
}

# Show-Expectations - set honest expectations from the resolved plan + a couple of
# cheap probes. Windows wording: the UAC narration replaces mac's Homebrew line.
function Show-Expectations {
  param($Plan, [string]$Root, [bool]$Force, [bool]$InstrBackoff, [int]$Done, [int]$Actionable)

  # The brand actually signed into, not the CLI's name (a Codex sign-in is a
  # ChatGPT account).
  $acct = Get-AgentAccount $Root $Plan.DefaultHarness

  Write-Host ''
  Write-Host ("  {0}What will happen{1}" -f $script:Bold, $script:Reset)

  # UAC narration - the honest analogue of mac's "password once". CLI agents are
  # the no-UAC critical path; winget-installed Node/Git each raise one prompt.
  Add-Expectation "Claude Code and Codex install just for you - no admin prompt."
  $needsWinget = @('node', 'git', 'gh-auth', 'claude-desktop', 'codex-desktop', 'github-desktop') | Where-Object { $Plan.StepIds -contains $_ }
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

  # The one edit vibe makes outside its own config paths, named here rather than
  # discovered later - the same deal plan.sh strikes for the rc line. State-aware for
  # the same reason too: an account PATH that already carries the dirs is left alone,
  # and "adds" there would promise a change that will not happen.
  if (Test-BumpPersistedPath) {
    Add-Expectation "Your account's PATH already has vibe's install folders - it is left as-is."
  } else {
    $dirs = (Get-BumpOwnedPathDir) -join ' and '
    Add-Expectation "Adds $dirs to your account's PATH so a NEW terminal window still finds the tools it installs."
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
  # gh and GitHub Desktop keep separate credential stores, so a plan with both
  # means two GitHub sign-ins. The second is not on this paste's critical path -
  # it happens whenever the app is first opened - so name it and say when.
  if ($Plan.StepIds -contains 'github-desktop') {
    Add-Expectation "GitHub Desktop asks for its own GitHub sign-in the first time you open it - it can't reuse the terminal's."
  }
  Add-Expectation "At the end you'll sign into your $acct account in the browser - create one first if you don't have it."

  # Which agent to install is not a tooling choice - it follows the subscription
  # the person already pays for, and a mismatch otherwise only surfaces at that
  # browser sign-in, after the install. So name the alternative here, while
  # Ctrl-C is still cheap. Only when the plan installs exactly one agent: someone
  # who asked for both has already answered the question.
  $harnessCount = @($Plan.StepKinds | Where-Object { $_ -eq 'harness' }).Count
  if ($harnessCount -eq 1) {
    foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $Root 'blocks') -Directory)) {
      $alt = Get-Meta $d.FullName 'AGENT'
      if (-not $alt -or $alt -eq $Plan.DefaultHarness) { continue }
      Add-Expectation ("Use {0} instead? Press Ctrl-C and re-run with '{1}' in place of '{2}'." -f (Get-AgentAccount $Root $alt), $alt, $Plan.DefaultHarness)
    }
  }

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
