# lib/apply.ps1: the Windows e2e anchor - the pwsh analogue of tests/e2e.bats.
# Dot-sources apply.ps1 (which defines Invoke-VibeSetup without running) and
# drives it in-process with $env:VIBE_OS=win, so the WIN command cells fire.
# Installers are faked as global shadow functions (winget/npm/irm|iex/clipboard);
# real git is kept on a hermetic PATH so repo init works, while node/gh/claude/
# codex/pnpm are OFF PATH so their CHECK fails and the install dispatch is
# observable. Asserts: canonical file, Claude @import line, Codex copy, trust
# JSON/TOML, per-OS (no-mise) content, install dispatch, idempotent re-run.

BeforeAll {
  $env:NO_COLOR = '1'   # before apply.ps1 (-> common.ps1) loads, so UI is plain
  . "$PSScriptRoot/../lib/apply.ps1"

  $script:repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
  $script:origPath = $env:PATH
  $script:origHome = $HOME
  $script:origEnvHome = $env:HOME

  # Every external tool is a global shadow function (functions beat applications
  # in command lookup), so the test never depends on host PATH: node/gh/claude/
  # codex/pnpm are simply never defined -> their Get-Command CHECK reports absent
  # -> the install dispatch is observable. git IS faked (config no-op, init makes
  # a .git dir) so the CHECK passes and repo init works without a real git.
  function global:winget { Add-Content -LiteralPath $env:VIBE_FAKE_LOG -Value "winget $($args -join ' ')" }
  function global:npm    { Add-Content -LiteralPath $env:VIBE_FAKE_LOG -Value "npm $($args -join ' ')" }
  function global:Invoke-RestMethod {
    param([Parameter(Position = 0)][string]$Uri)
    if ($Uri -match 'claude\.ai/install\.ps1') { return 'Add-Content -LiteralPath $env:VIBE_FAKE_LOG -Value "INSTALL claude"' }
    if ($Uri -match 'codex/install\.ps1')      { return 'Add-Content -LiteralPath $env:VIBE_FAKE_LOG -Value "INSTALL codex"' }
    return ''
  }
  function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) Add-Content -LiteralPath $env:VIBE_FAKE_LOG -Value 'CLIPBOARD' }
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
}

Describe 'apply.ps1 (Windows spine)' {
  BeforeEach {
    $script:testHome = Join-Path $TestDrive ('home-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testHome -Force | Out-Null
    Set-Variable -Name HOME -Scope Global -Value $script:testHome -Force
    $env:HOME = $script:testHome
    $env:VIBE_OS = 'win'
    $env:VIBE_ROOT = $script:repoRoot
    $env:VIBE_FAKE_LOG = Join-Path $script:testHome 'fake.log'
    Set-Content -LiteralPath $env:VIBE_FAKE_LOG -Value ''
    # An empty bin on PATH: no host tool leaks in, so only the shadow functions
    # above are "present" and every install dispatch is observable.
    $emptyBin = Join-Path $script:testHome 'bin'
    New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
    $env:PATH = $emptyBin
  }
  AfterEach {
    foreach ($v in 'VIBE_OS', 'VIBE_ROOT', 'VIBE_FAKE_LOG', 'VIBE_LIB', 'VIBE_BLOCK_DIR', 'VIBE_BLOCK_ID') {
      Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
  }

  It 'claude starter dispatches installs, lands per-OS content, links Claude via @import, pre-trusts' {
    $out = Invoke-VibeSetup -Yes -NoLaunch -Ids @('claude', 'starter') 6>&1 | Out-String
    $out | Should -Match 'Setup complete'
    $out | Should -Match 'Agent to launch: claude'

    $log = Get-Content -Raw -LiteralPath $env:VIBE_FAKE_LOG
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
    $out = Invoke-VibeSetup -Plan -Ids @('claude', 'starter') 6>&1 | Out-String
    $out | Should -Match 'sign into your Claude account'
    $out | Should -Match 'Use ChatGPT instead\?'
    $out | Should -Match "re-run with 'codex' in place of 'claude'"

    # generated from the catalogue, not hardcoded - so it is symmetric...
    $out = Invoke-VibeSetup -Plan -Ids @('codex', 'starter') 6>&1 | Out-String
    $out | Should -Match 'sign into your ChatGPT account'
    $out | Should -Match 'Use Claude instead\?'

    # ...and silent once the plan already installs both
    $out = Invoke-VibeSetup -Plan -Ids @('claude', 'codex', 'starter') 6>&1 | Out-String
    $out | Should -Not -Match 'instead\?'
  }

  It 'codex copies instructions (no import) and writes the trust TOML' {
    Invoke-VibeSetup -Yes -NoLaunch -Ids @('codex', 'concise') 6>&1 | Out-Null

    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    $agents = Join-Path $script:testHome '.codex/AGENTS.md'
    (Get-Content -Raw -LiteralPath $agents) | Should -Match '## Be concise'   # physical copy, not an @import
    (Get-Content -Raw -LiteralPath $agents) | Should -Not -Match "^@"

    $toml = Join-Path $script:testHome '.codex/config.toml'
    (Get-Content -Raw -LiteralPath $toml) | Should -Match 'trust_level = "trusted"'
    (Get-Content -Raw -LiteralPath $toml) | Should -Match '\[projects\.'
  }

  It 'a second run leaves the canonical identical and backs off' {
    Invoke-VibeSetup -Yes -NoLaunch -Ids @('claude', 'concise') 6>&1 | Out-Null
    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    $once = Get-Content -Raw -LiteralPath $canon

    $out = Invoke-VibeSetup -Yes -NoLaunch -Ids @('claude', 'concise') 6>&1 | Out-String
    (Get-Content -Raw -LiteralPath $canon) | Should -Be $once
    $out | Should -Match 'left as-is'
    $out | Should -Match 'skipped \(file exists\)'
  }

  It '-Force rewrites the canonical but keeps a .bak of what was there' {
    $canon = Join-Path $script:testHome '.agents/AGENTS.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $canon) -Force | Out-Null
    Set-Content -LiteralPath $canon -Value 'MY OWN NOTES'

    Invoke-VibeSetup -Yes -NoLaunch -Force -Ids @('claude', 'concise') 6>&1 | Out-Null

    (Get-Content -Raw -LiteralPath $canon) | Should -Match '## Be concise'
    (Get-Content -Raw -LiteralPath "$canon.bak").Trim() | Should -Be 'MY OWN NOTES'
  }

  It 'a non-Windows OS redirects to the mac paste before any effect' {
    $env:VIBE_OS = 'mac'
    $out = Invoke-VibeSetup -Yes -NoLaunch -Ids @('claude') 6>&1 | Out-String
    $out | Should -Match 'macOS paste'
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude.json') | Should -BeFalse
  }

  It 'unknown id fails at plan time and applies nothing' {
    $out = Invoke-VibeSetup -Yes -NoLaunch -Ids @('bogus') 6>&1 | Out-String
    $out | Should -Match 'unknown block: bogus'
    Test-Path -LiteralPath (Join-Path $script:testHome '.claude/CLAUDE.md') | Should -BeFalse
  }
}
