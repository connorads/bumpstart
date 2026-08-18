# lib/apply.ps1: the Windows e2e anchor - the pwsh analogue of tests/e2e.bats.
# Dot-sources apply.ps1 (which defines Invoke-BumpSetup without running) and
# drives it in-process with $env:BUMP_OS=win, so the WIN command cells fire.
# Installers are faked as global shadow functions (winget/npm/irm|iex/clipboard);
# real git is kept on a hermetic PATH so repo init works, while node/gh/claude/
# codex/pnpm are OFF PATH so their CHECK fails and the install dispatch is
# observable. Asserts: canonical file, Claude @import line, Codex copy, trust
# JSON/TOML, per-OS (no-mise) content, install dispatch, idempotent re-run.

BeforeAll {
  $env:NO_COLOR = '1'   # before apply.ps1 (-> common.ps1) loads, so UI is plain
  . "$PSScriptRoot/../lib/apply.ps1"
  . "$PSScriptRoot/helpers/FakeEnvKey.ps1"

  $script:repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
  $script:origPath = $env:PATH
  $script:origHome = $HOME
  $script:origEnvHome = $env:HOME
  $script:origAppData = $env:APPDATA
  $script:origProgramFiles = $env:ProgramFiles

  # Every external tool is a global shadow function (functions beat applications
  # in command lookup), so the test never depends on host PATH: node/gh/claude/
  # codex/pnpm are simply never defined -> their Get-Command CHECK reports absent
  # -> the install dispatch is observable. git IS faked (config no-op, init makes
  # a .git dir) so the CHECK passes and repo init works without a real git.
  function global:winget { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "winget $($args -join ' ')" }
  function global:npm    { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "npm $($args -join ' ')" }
  function global:Invoke-RestMethod {
    param([Parameter(Position = 0)][string]$Uri)
    if ($Uri -match 'claude\.ai/install\.ps1') { return 'Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "INSTALL claude"' }
    if ($Uri -match 'codex/install\.ps1')      { return 'Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "INSTALL codex"' }
    return ''
  }
  function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value 'CLIPBOARD' }
  function global:git {
    if ($args -contains 'init') {
      $ci = [array]::IndexOf([object[]]$args, '-C')
      $dir = if ($ci -ge 0) { $args[$ci + 1] } else { '.' }
      New-Item -ItemType Directory -Path (Join-Path $dir '.git') -Force | Out-Null
    }
    $global:LASTEXITCODE = 0   # config --get returns nothing -> tail takes the "set" path
  }
}

AfterAll {
  Remove-Item Function:winget, Function:npm, Function:Invoke-RestMethod, Function:Set-Clipboard, Function:git -ErrorAction SilentlyContinue
  $env:PATH = $script:origPath
  Set-Variable -Name HOME -Scope Global -Value $script:origHome -Force
  $env:HOME = $script:origEnvHome
  foreach ($v in @{ APPDATA = $script:origAppData; ProgramFiles = $script:origProgramFiles }.GetEnumerator()) {
    if ($null -eq $v.Value) { Remove-Item "Env:$($v.Key)" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$($v.Key)" -Value $v.Value }
  }
}

Describe 'apply.ps1 (Windows spine)' {
  BeforeEach {
    $script:testHome = Join-Path $TestDrive ('home-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testHome -Force | Out-Null
    Set-Variable -Name HOME -Scope Global -Value $script:testHome -Force
    $env:HOME = $script:testHome
    $env:BUMP_OS = 'win'
    $env:BUMP_ROOT = $script:repoRoot
    $env:BUMP_FAKE_LOG = Join-Path $script:testHome 'fake.log'
    Set-Content -LiteralPath $env:BUMP_FAKE_LOG -Value ''
    # An empty bin on PATH: no host tool leaks in, so only the shadow functions
    # above are "present" and every install dispatch is observable.
    $emptyBin = Join-Path $script:testHome 'bin'
    New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
    $env:PATH = $emptyBin

    # ...and the same for the two dirs Set-BumpPath takes from the HOST rather than
    # from $HOME. fixup_path's POSIX twin is entirely $HOME-relative, so setting $HOME
    # is the whole story there; the Windows one also prepends %AppData%\npm and
    # %ProgramFiles%\nodejs, which on a real Windows host are the runner's own. That
    # is correct for the product - a node installed by an earlier run has to be
    # findable - and fatal for a suite that asserts an install DISPATCHES: the
    # fixup runs before the install loop, so C:\Program Files\nodejs lands on PATH
    # and node's `Get-Command node` CHECK reports satisfied on a machine the test
    # believes has no node. Point both inside $TestDrive so the dirs still exist and
    # the prepend branch still runs, over content the test owns.
    $env:APPDATA = Join-Path (Join-Path $script:testHome 'AppData') 'Roaming'
    $env:ProgramFiles = Join-Path $script:testHome 'ProgramFiles'
    New-Item -ItemType Directory -Path (Join-Path $env:APPDATA 'npm') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $env:ProgramFiles 'nodejs') -Force | Out-Null

    # The account PATH is faked for the same reason the installers are: an applied run
    # calls Set-BumpPersistedPath, which on a Windows host appends THIS TEST'S $TestDrive
    # dirs to the registry PATH of whoever ran the suite, and broadcasts
    # WM_SETTINGCHANGE - once per applied case. Get-BumpUserEnvKey is the only door to
    # that registry (see helpers/FakeEnvKey.ps1), so mocking it runs every line of the
    # persist step against a value the test can read back instead.
    $script:regPath = New-FakeEnvState -Value 'C:\Windows;C:\Windows\System32'
    $script:regKey = New-FakeEnvKey $script:regPath
    Mock Get-BumpUserEnvKey { $script:regKey }
    Mock Send-BumpEnvironmentChange { }
  }
  AfterEach {
    foreach ($v in 'BUMP_OS', 'BUMP_ROOT', 'BUMP_FAKE_LOG', 'BUMP_LIB', 'BUMP_BLOCK_DIR', 'BUMP_BLOCK_ID') {
      Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
  }

  It 'claude starter dispatches installs, lands per-OS content, links Claude via @import, pre-trusts' {
    $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'starter') 6>&1 | Out-String
    $out | Should -Match 'Setup complete'
    $out | Should -Match 'Agent to launch: claude'

    $log = Get-Content -Raw -LiteralPath $env:BUMP_FAKE_LOG
    $log | Should -Match 'INSTALL claude'                        # claude-cli via irm|iex
    $log | Should -Match 'winget install --id Anthropic.Claude'  # claude-desktop
    $log | Should -Match 'winget install --id OpenJS.NodeJS.LTS' # node (winget, no mise)
    $log | Should -Match 'winget install --id GitHub.cli'        # gh-auth

    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    Test-Path -LiteralPath $canon | Should -BeTrue
    $canonText = Get-Content -Raw -LiteralPath $canon
    $canonText | Should -Match '## Be concise'
    $canonText | Should -Match 'Node.js and npm are installed'   # content.win.md
    $canonText | Should -Not -Match 'managed by mise'            # mise content dropped on Windows

    $claudeMd = Join-Path $script:testHome '.claude/CLAUDE.md'
    (Get-Content -Raw -LiteralPath $claudeMd).Trim() | Should -Be "@$canon"

    $trust = Join-Path $script:testHome '.claude.json'
    (Get-Content -Raw -LiteralPath $trust) | Should -Match 'hasTrustDialogAccepted'
    (Get-Content -Raw -LiteralPath $trust) | Should -Match 'hasCompletedOnboarding'

    Test-Path -LiteralPath (Join-Path $script:testHome 'git/first-project/.git') | Should -BeTrue
  }

  It 'a one-agent plan names the other agent at the gate; a two-agent plan does not' {
    $out = Invoke-BumpSetup -Plan -Ids @('claude', 'starter') 6>&1 | Out-String
    $out | Should -Match 'sign into your Claude account'
    $out | Should -Match 'Use ChatGPT instead\?'
    $out | Should -Match "re-run with 'codex' in place of 'claude'"

    # generated from the catalogue, not hardcoded - so it is symmetric...
    $out = Invoke-BumpSetup -Plan -Ids @('codex', 'starter') 6>&1 | Out-String
    $out | Should -Match 'sign into your ChatGPT account'
    $out | Should -Match 'Use Claude instead\?'

    # ...and silent once the plan already installs both
    $out = Invoke-BumpSetup -Plan -Ids @('claude', 'codex', 'starter') 6>&1 | Out-String
    $out | Should -Not -Match 'instead\?'
  }

  It 'discloses the PATH edit at the gate, because it is the one thing outside bumpstart own paths' {
    # The deal the project holds itself to: bumpstart writes its own config paths, plus ONE
    # thing outside them, and that one thing is NAMED before it happens. On Windows it
    # is the account PATH (lib/shellpath.ps1) rather than an rc line, and the promise
    # does not get to be OS-dependent. Asserted at the gate, where Ctrl-C is still
    # cheap - not after the write.
    $out = Invoke-BumpSetup -Plan -Ids @('claude', 'starter') 6>&1 | Out-String
    $out | Should -Match "account's PATH"
    $out | Should -Match 'NEW terminal window'
    # The dirs by name, because "adds some folders to PATH" is not a removal
    # instruction. Slash-normalised: Join-Path builds these with the host separator.
    ($out -replace '\\', '/') | Should -Match '\.local/bin'
    ($out -replace '\\', '/') | Should -Match '\.codex/bin'
  }

  It 'persists the install dirs on the account PATH, not only promises them at the gate' {
    # The other half of the case above: the gate's wording was asserted and the EFFECT
    # was not, so the applier could stop calling Set-BumpPersistedPath and only the
    # weekly Windows lane would notice. Appended to what was already there, never
    # replacing it.
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'starter') 6>&1 | Out-Null
    $script:regPath.Writes | Should -Be 1
    ($script:regPath.Value -replace '\\', '/') | Should -BeLike 'C:/Windows;C:/Windows/System32;*/.local/bin;*/.codex/bin'
    $script:regPath.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
  }

  It 'fixes up this run PATH before the install loop, not after it' {
    # The reason common.ps1 gives for the fixup, and the reason apply.sh calls its
    # mirror pre-loop: a block's CHECK cell has to see what an earlier block
    # installed. On Windows npm arrives with node's winget MSI and blocks/pnpm's
    # cell is `npm install -g pnpm`, so run after the loop this fixed up a PATH
    # nothing was left to use.
    #
    # Order is the assertion, not effect - what Set-BumpPath actually prepends is
    # its own business, and asserting it here would just restate common.ps1.
    Mock Set-BumpPath { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value 'PATHFIX' }
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'node') 6>$null | Out-Null

    $log = @(Get-Content -LiteralPath $env:BUMP_FAKE_LOG)
    $fix = [array]::IndexOf($log, 'PATHFIX')
    $firstInstall = -1
    for ($i = 0; $i -lt $log.Count; $i++) {
      if ($log[$i] -like 'winget install*') { $firstInstall = $i; break }
    }
    $fix | Should -BeGreaterThan -1
    $firstInstall | Should -BeGreaterThan $fix
  }

  It 'codex copies instructions (no import) and writes the trust TOML' {
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('codex', 'concise') 6>&1 | Out-Null

    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    $agents = Join-Path $script:testHome '.codex/AGENTS.md'
    (Get-Content -Raw -LiteralPath $agents) | Should -Match '## Be concise'   # physical copy, not an @import
    (Get-Content -Raw -LiteralPath $agents) | Should -Not -Match "^@"

    $toml = Join-Path $script:testHome '.codex/config.toml'
    (Get-Content -Raw -LiteralPath $toml) | Should -Match 'trust_level = "trusted"'
    (Get-Content -Raw -LiteralPath $toml) | Should -Match '\[projects\.'
  }

  It "a codex-only plan does not touch Claude's path" {
    # The missing analogue of the e2e.bats case: a plan that installs one agent
    # must not leave the other one's config file behind pointing at anything.
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('codex', 'concise') 6>$null | Out-Null
    Test-Path -LiteralPath (Join-Path $script:testHome '.codex/AGENTS.md')  | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude/CLAUDE.md') | Should -BeFalse
  }

  It 'a harness with nothing to say writes no instructions file and links nothing at it' {
    # claude-cli alone carries no content, so the resolver ships no targets and
    # the assembler has nothing to write. The applier used to re-derive the
    # targets from the steps, losing that gate: it wrote ~/.claude/CLAUDE.md
    # importing a canonical that does not exist.
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude-cli') 6>$null | Out-Null
    Test-Path -LiteralPath (Join-Path $script:testHome '.agents/AGENTS.md')  | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude/CLAUDE.md') | Should -BeFalse
  }

  It 'does not link a harness at an instructions file that was never written' {
    # blocks/mise carries content.md but has no INSTALL_WIN and no apply.ps1, so
    # on Windows it does no work and the assembler drops its section - leaving
    # nothing to write. The resolver still resolves Claude's target, because the
    # plan does carry content. Without the guard, ~/.claude/CLAUDE.md was written
    # as an @import of a canonical that is not there.
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude-cli', 'mise') 6>$null | Out-Null
    Test-Path -LiteralPath (Join-Path $script:testHome '.agents/AGENTS.md')  | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude/CLAUDE.md') | Should -BeFalse
  }

  It 'a second run leaves the canonical identical and backs off' {
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'concise') 6>&1 | Out-Null
    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    $once = Get-Content -Raw -LiteralPath $canon

    $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'concise') 6>&1 | Out-String
    (Get-Content -Raw -LiteralPath $canon) | Should -Be $once
    $out | Should -Match 'left as-is'
    $out | Should -Match 'skipped \(file exists\)'
  }

  It 'puts the instruction sections above the tool guidance' {
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'starter') 6>&1 | Out-Null
    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    $lines = Get-Content -LiteralPath $canon
    # node is a [tool] (kind rank 30), so the plan runs it before the
    # [instructions] blocks - but the behavioural frame leads the file.
    $frame = [array]::IndexOf($lines, '## Be concise')
    $reference = [array]::IndexOf($lines, '## Node.js')
    $frame | Should -BeGreaterThan -1
    $reference | Should -BeGreaterThan -1
    $frame | Should -BeLessThan $reference
  }

  It 'a re-run tags a content-carrying tool row, not just the instruction rows' {
    Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'node') 6>&1 | Out-Null
    # node ships content.win.md, so on the re-run its guidance is skipped too -
    # an unqualified 'already set up' would claim the whole row landed.
    $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'node') 6>&1 | Out-String
    $out | Should -Match 'guidance skipped'
  }

  It '-Force rewrites the canonical but keeps a .bak of what was there' {
    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $canon) -Force | Out-Null
    Set-Content -LiteralPath $canon -Value 'MY OWN NOTES'

    Invoke-BumpSetup -Yes -NoLaunch -Force -Ids @('claude', 'concise') 6>&1 | Out-Null

    (Get-Content -Raw -LiteralPath $canon) | Should -Match '## Be concise'
    (Get-Content -Raw -LiteralPath "$canon.bak").Trim() | Should -Be 'MY OWN NOTES'
  }

  It 'names a step that failed instead of a green Setup complete' {
    # winget fails, so every winget-backed cell in the plan warns. The verdict has
    # to follow: an unqualified success line over a broken machine is the one
    # message that costs trust. Mirrors the bats case in e2e.bats.
    #
    # It PRINTS before it fails, because a real winget does - and the silent fake
    # this replaced made the case pass for the wrong reason: it only ever
    # exercised the path where the cell produced nothing. The text carries no
    # package id, so the `winget list | Select-String <id>` CHECK cells still
    # read "not satisfied".
    function global:winget { Write-Output 'installer output'; $global:LASTEXITCODE = 1 }
    try {
      $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'node') 6>&1 | Out-String
      $out | Should -Not -Match 'Setup complete'
      $out | Should -Match "steps didn't work"
      $out | Should -Match 'Node.js'
      $out | Should -Match "retries only what's missing"
    } finally {
      function global:winget { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "winget $($args -join ' ')" }
    }
  }

  It "runs warn-and-continue whichever bootstrap branch invoked it" {
    # bumpstart.ps1 sets 'Stop', then spawns a pwsh 7 process when one is on PATH (which
    # resets the preference) but invokes the applier in the SAME runspace when there
    # isn't - and that is the fresh-Windows branch, the beginner's path. Every test
    # regime and CI lane has pwsh 7, so 'Stop' was the one condition nothing covered,
    # and under it a non-terminating error outside an Invoke-Spin try/catch ends a
    # setup whose whole design is to warn and carry on.
    #
    # A global shadow function rather than Mock: PowerShell resolves
    # $ErrorActionPreference dynamically up the call stack, so a plain function
    # reports the applier's effective value. A mock body resolves variables from
    # where it was defined, and would assert nothing.
    $ErrorActionPreference = 'Stop'
    function global:winget { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "EAP=$ErrorActionPreference" }
    try {
      Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude', 'node') 6>$null | Out-Null
      $log = Get-Content -Raw -LiteralPath $env:BUMP_FAKE_LOG
      $log | Should -Match 'EAP=Continue'
      $log | Should -Not -Match 'EAP=Stop'
    } finally {
      function global:winget { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value "winget $($args -join ' ')" }
    }
  }

  It 'admits a missing agent binary instead of a run-it hint' {
    # claude is never defined as a shadow function, so the install dispatch runs
    # but no binary exists — the shape of an installer that landed off PATH.
    $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude-cli') 6>&1 | Out-String
    $out | Should -Match "isn't installed, so there's nothing to open yet"
    $out | Should -Not -Match "Run 'claude' in"
  }

  It 'records the launch rather than running it inside the value read as the exit code' {
    # The launch branch had no coverage at all. Running the agent inside the
    # assignment `$rc = Invoke-BumpSetup ...` puts whatever it printed on the
    # success stream beside the return code, and `exit @('chatter', 1)` exits 0 -
    # so a printing agent masked a failed setup. (On a real console it is worse:
    # a native command in a captured pipeline gets a pipe, not the terminal.)
    function global:claude { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value 'LAUNCHED claude' }
    # Wait-Enter is a no-op only when input is redirected; mocked so a
    # terminal-attached run of this suite cannot block on it.
    Mock Wait-Enter { }
    $cwd = (Get-Location).Path
    try {
      Invoke-BumpSetup -Yes -Ids @('claude-cli') 6>$null | Out-Null
      (Get-Content -Raw -LiteralPath $env:BUMP_FAKE_LOG) | Should -Not -Match 'LAUNCHED claude'
      $script:BumpLaunch | Should -Be 'claude'
      ($script:BumpLaunchDir -replace '\\', '/') | Should -Match 'git/first-project$'
      (Get-Location).Path | Should -Be $cwd
    } finally {
      Remove-Item Function:claude -ErrorAction SilentlyContinue
    }
  }

  It 'records no launch under -NoLaunch' {
    function global:claude { Add-Content -LiteralPath $env:BUMP_FAKE_LOG -Value 'LAUNCHED claude' }
    try {
      Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude-cli') 6>$null | Out-Null
      $script:BumpLaunch | Should -BeNullOrEmpty
    } finally {
      Remove-Item Function:claude -ErrorAction SilentlyContinue
    }
  }

  It 'a non-Windows OS redirects to the mac paste before any effect' {
    $env:BUMP_OS = 'mac'
    $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('claude') 6>&1 | Out-String
    $out | Should -Match 'macOS paste'
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude.json') | Should -BeFalse
  }

  It 'unknown id fails at plan time and applies nothing' {
    $out = Invoke-BumpSetup -Yes -NoLaunch -Ids @('bogus') 6>&1 | Out-String
    $out | Should -Match 'unknown block: bogus'
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude/CLAUDE.md') | Should -BeFalse
  }
}
