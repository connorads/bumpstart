# lib/resolve.ps1: the pwsh-only slice of the pure core — instruction Targets,
# which are OS-specific (MAC reads TARGET, WIN reads TARGET_WIN) and so live
# outside the shared cross-OS contract. Runs on the mac host with no override, so
# Get-VibeOsKey is MAC and the target field read is TARGET (the slice-1 asymmetry:
# mac's target is the bare TARGET).

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
