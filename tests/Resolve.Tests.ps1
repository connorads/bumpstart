# lib/resolve.ps1: the pwsh-only slice of the pure core - instruction Targets,
# which are OS-specific (MAC reads TARGET, WIN reads TARGET_WIN) and so live
# outside the shared cross-OS contract. Fixture harnesses carry the host-native
# target fields needed by the PowerShell lane on macOS and Windows.

BeforeAll {
  . "$PSScriptRoot/../lib/os.ps1"
  . "$PSScriptRoot/../lib/meta.ps1"
  . "$PSScriptRoot/../lib/resolve.ps1"
  $script:fix = "$PSScriptRoot/fixtures"
}

Describe 'Resolve-Plan targets' {
  It 'targets the harness file when a content block is present' {
    $plan = Resolve-Plan $script:fix @('claude', 'concise')
    $plan.Error | Should -Be ''
    ($plan.Targets -join ' ') | Should -Match '\.claude/CLAUDE\.md'
  }

  It 'codex + instructions targets AGENTS.md, not CLAUDE.md' {
    $plan = Resolve-Plan $script:fix @('codex', 'concise')
    ($plan.Targets -join ' ') | Should -Match '\.codex/AGENTS\.md'
    ($plan.Targets -join ' ') | Should -Not -Match '\.claude/CLAUDE\.md'
  }

  It 'both harnesses target both files' {
    $plan = Resolve-Plan $script:fix @('claude', 'codex', 'concise')
    ($plan.Targets -join ' ') | Should -Match '\.claude/CLAUDE\.md'
    ($plan.Targets -join ' ') | Should -Match '\.codex/AGENTS\.md'
  }

  It 'a bare harness with no content ships no targets' {
    $plan = Resolve-Plan $script:fix @('claude')
    $plan.Targets.Count | Should -Be 0
  }
}

Describe 'Resolve-Plan target methods (win)' {
  # The applier needs a linking method (import vs copy) per target and reads the
  # plan for it. Pinned on VIBE_OS=win because LINK_<OS> only exists there today.
  BeforeEach { $env:VIBE_OS = 'win' }
  AfterEach  { Remove-Item Env:VIBE_OS -ErrorAction SilentlyContinue }

  It 'a method rides with its target, index-aligned, across a two-harness plan' {
    $plan = Resolve-Plan $script:fix @('claude-cli', 'codex-cli', 'concise')
    $plan.Targets.Count | Should -Be 2
    $plan.TargetMethods.Count | Should -Be $plan.Targets.Count
    # By pairing, not by position: a re-rank of the harness kind must not be able
    # to silently swap Claude's @import for Codex's copy.
    $pairs = @{}
    for ($i = 0; $i -lt $plan.Targets.Count; $i++) { $pairs[$plan.Targets[$i]] = $plan.TargetMethods[$i] }
    $pairs['$HOME/.claude/CLAUDE.md'] | Should -Be 'import'
    $pairs['$HOME/.codex/AGENTS.md']  | Should -Be 'copy'
  }

  It 'falls back to the plain TARGET when a harness declares no TARGET_WIN' {
    # The rule the applier lost by re-deriving targets from the steps: meta.sh
    # documents TARGET_<OS>-then-TARGET, and a harness with only a plain TARGET
    # would otherwise silently link nothing.
    $root = Join-Path $TestDrive 'root'
    New-Item -ItemType Directory -Path (Join-Path $root 'blocks/only-plain') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'blocks/only-plain/meta') -Value @(
      'KIND=harness', 'AGENT=plain', 'DESC=x', 'TARGET="$HOME/.plain/AGENTS.md"'
    )
    New-Item -ItemType Directory -Path (Join-Path $root 'blocks/says-something') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'blocks/says-something/meta') -Value @('KIND=instructions', 'DESC=y')
    Set-Content -LiteralPath (Join-Path $root 'blocks/says-something/content.md') -Value '## Something'

    $plan = Resolve-Plan $root @('only-plain', 'says-something')
    $plan.Error | Should -Be ''
    $plan.Targets | Should -Be '$HOME/.plain/AGENTS.md'
    # No LINK_WIN declared -> the resolver's own default, so exactly one place decides.
    $plan.TargetMethods | Should -Be 'copy'
  }

  It 'a failed resolve carries an empty method list, like every other field' {
    $plan = Resolve-Plan $script:fix @('bogus')
    $plan.Error | Should -Match 'unknown block'
    $plan.TargetMethods.Count | Should -Be 0
  }
}
