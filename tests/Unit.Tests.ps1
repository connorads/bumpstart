# Focused unit tests for the pure helpers the Windows e2e anchor doesn't probe
# directly: the defensive trust path-key variants, $HOME/~ expansion, and the
# Codex copy-ownership heuristic.

BeforeAll {
  $env:NO_COLOR = '1'
  . "$PSScriptRoot/../lib/common.ps1"
  . "$PSScriptRoot/../lib/os.ps1"
  . "$PSScriptRoot/../lib/meta.ps1"
  . "$PSScriptRoot/../lib/run.ps1"
  . "$PSScriptRoot/../lib/instructions.ps1"
  . "$PSScriptRoot/../lib/trust.ps1"
}

Describe 'Get-VibePathVariants' {
  It 'yields slash + drive-case variants for a Windows path' {
    $v = Get-VibePathVariants 'C:\Users\me\git\first-project'
    $v | Should -Contain 'C:\Users\me\git\first-project'   # as-is
    $v | Should -Contain 'C:/Users/me/git/first-project'   # forward slash
    $v | Should -Contain 'c:\Users\me\git\first-project'   # drive lowercased
  }

  It 'is deduped and stable for a slash-free path' {
    $v = Get-VibePathVariants '/home/me/first-project'
    ($v | Select-Object -Unique).Count | Should -Be $v.Count
    $v | Should -Contain '/home/me/first-project'
  }
}

Describe 'Expand-VibeHome' {
  It 'expands a leading $HOME to the home dir' {
    (Expand-VibeHome '$HOME/.claude/CLAUDE.md') | Should -Be (Join-Path $HOME '.claude/CLAUDE.md')
  }
  It 'expands a leading ~' {
    (Expand-VibeHome '~/.codex/AGENTS.md') | Should -Be (Join-Path $HOME '.codex/AGENTS.md')
  }
  It 'leaves an absolute path untouched' {
    (Expand-VibeHome '/etc/thing') | Should -Be '/etc/thing'
  }
}

Describe 'Test-VibeCopyOwned' {
  It 'treats a missing target as ownable' {
    Test-VibeCopyOwned (Join-Path $TestDrive 'nope.md') | Should -BeTrue
  }
  It 'treats a canonical-style header file as ours' {
    $f = Join-Path $TestDrive 'ours.md'
    Set-Content -LiteralPath $f -Value "## Be concise`nstuff"
    Test-VibeCopyOwned $f | Should -BeTrue
  }
  It 'treats a foreign file as not ours' {
    $f = Join-Path $TestDrive 'foreign.md'
    Set-Content -LiteralPath $f -Value "My own AGENTS notes"
    Test-VibeCopyOwned $f | Should -BeFalse
  }
}

Describe 'Copy-StarterPrompt' {
  # The pwsh twin of the trust.bats cases. trust.sh explicitly REJECTS printing the
  # starter message - the agent's full-screen TUI wipes the scrollback moments
  # later, so the text the novice was told to copy is gone before they can - and
  # writes first-message.txt instead. trust.ps1 did exactly the rejected thing.
  BeforeEach {
    $script:origHome = $HOME
    $script:testHome = Join-Path $TestDrive ('home-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testHome -Force | Out-Null
    Set-Variable -Name HOME -Scope Global -Value $script:testHome -Force
    $script:repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
  }
  AfterEach {
    Set-Variable -Name HOME -Scope Global -Value $script:origHome -Force
    Remove-Item Function:Set-Clipboard -ErrorAction SilentlyContinue
  }

  It 'writes the starter message to a file, always' {
    # A clipboard survives the browser sign-in but not a reboot, a second
    # terminal, or a clipboard manager that drops it.
    function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) }
    Copy-StarterPrompt $script:repoRoot 6>$null | Out-Null
    $script:StarterPromptCopied | Should -BeTrue
    (Get-Content -Raw -LiteralPath (Join-Path (Get-StarterDir) 'first-message.txt')) |
      Should -Match 'build it together'
  }

  It 'names the file rather than printing text that gets wiped, when there is no clipboard' {
    function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) throw 'no clipboard' }
    $out = Copy-StarterPrompt $script:repoRoot 6>&1 | Out-String
    $script:StarterPromptCopied | Should -BeFalse
    $out | Should -Match 'first-message\.txt'
    (Get-Content -Raw -LiteralPath (Join-Path (Get-StarterDir) 'first-message.txt')) |
      Should -Match 'build it together'
  }

  It 'points Show-LoginFrame at the file when the clipboard is unavailable' {
    function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) throw 'no clipboard' }
    Copy-StarterPrompt $script:repoRoot 6>$null | Out-Null
    $out = Show-LoginFrame 'claude' 6>&1 | Out-String
    $out | Should -Match 'first-message\.txt'
    $out | Should -Not -Match 'on your clipboard'
  }

  It 'points Show-LoginFrame at the clipboard when there is one' {
    function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) }
    Copy-StarterPrompt $script:repoRoot 6>$null | Out-Null
    $out = Show-LoginFrame 'claude' 6>&1 | Out-String
    $out | Should -Match 'on your clipboard'
  }
}

Describe 'The wizard fold over axes' {
  BeforeAll {
    . "$PSScriptRoot/../lib/resolve.ps1"
    . "$PSScriptRoot/../lib/build.ps1"
    $script:fix = "$PSScriptRoot/fixtures"
  }

  It 'asks only about axes that have members, in their declared ORDER' {
    $axes = Get-VibeAxes $script:fix
    ($axes | ForEach-Object { $_.Id }) -join ' ' | Should -Be 'recipe agent tools steering'
  }

  It 'puts presets first in a group, then ids alphabetically' {
    # the coarse, ready-made choice leads; `starter` is a recipe, not an agent
    (Get-VibeAxisMembers $script:fix 'agent') -join ' ' | Should -Be 'claude codex claude-cli codex-cli'
    (Get-VibeAxisMembers $script:fix 'recipe') -join ' ' | Should -Be 'starter'
  }

  It 'never offers a block that declares no AXIS' {
    # mise arrives via node; nobody picks a version manager directly
    foreach ($ax in (Get-VibeAxes $script:fix)) {
      Get-VibeAxisMembers $script:fix $ax.Id | Should -Not -Contain 'mise'
    }
  }

  It 'shows what a row pulls in, so wholes and parts read as nested' {
    Get-VibeAxisDetail $script:fix 'starter' | Should -Be ' (pulls in: web beginner)'
    Get-VibeAxisDetail $script:fix 'concise' | Should -Be ''
  }
}
