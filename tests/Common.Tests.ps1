# lib/common.ps1: the UI helpers. Focus: the Invoke-Spin contract in plain mode
# (no UiFancy) - run the block, stream its output through, and return ONE
# boolean saying whether it worked. The pwsh twin of tests/common.bats, which
# had none: every fake in the pwsh suite was silent, so the failure paths only
# ever exercised a block that printed nothing.
#
# Plus the warning ledger's dedupe, the twin of the e2e.bats case, and the roots
# Set-BumpPath is allowed to draw a PATH entry from.

BeforeAll {
  $env:NO_COLOR = '1'   # before common.ps1 loads, so UI stays plain + capturable
  . "$PSScriptRoot/../lib/common.ps1"
}

Describe 'Invoke-Spin' {
  It 'returns exactly one value, and it is a boolean' {
    # The bug this pins: with `& $Script` on the success stream, a block that
    # PRINTS makes the caller's `$ok = Invoke-Spin ...` an Object[] of chatter
    # plus the flag. Every multi-element array is truthy, so a failed install
    # reported success. Count and type, because either alone passes by luck.
    $r = Invoke-Spin 'x' { Write-Output 'chatter'; $global:LASTEXITCODE = 1 } 6>$null
    @($r).Count | Should -Be 1
    $r | Should -BeOfType [bool]
    $r | Should -BeFalse
  }

  It 'is $true for a block that prints and succeeds' {
    $r = Invoke-Spin 'x' { Write-Output 'chatter' } 6>$null
    @($r).Count | Should -Be 1
    $r | Should -BeTrue
  }

  It "streams the block's output through" {
    # The twin of common.bats' "spin streams the command's stdout through": the
    # vendor's own narration is most of what a beginner sees, so it may not be
    # swallowed. Via Write-Host (the Information stream common.ps1 declares for
    # all UI), which is why this is captured with 6>&1.
    $out = Invoke-Spin 'print' { Write-Output 'hello-from-cmd' } 6>&1 | Out-String
    $out | Should -Match 'hello-from-cmd'
  }

  It 'runs the block' {
    $script:ran = $false
    Invoke-Spin 'x' { $script:ran = $true } 6>$null | Out-Null
    $script:ran | Should -BeTrue
  }

  It 'does not inherit a stale $LASTEXITCODE from an earlier command' {
    $global:LASTEXITCODE = 3
    $r = Invoke-Spin 'x' { } 6>$null
    $r | Should -BeTrue
  }

  It 'reports the exception message when the block throws' {
    # A bare `catch { $ok = $false }` threw away the only clue on offer: the
    # vendor's reason. "Couldn't install X" alone leaves nothing to act on.
    $out = Invoke-Spin 'x' { throw 'kaboom-from-vendor' } 6>&1 | Out-String
    $out | Should -Match 'kaboom-from-vendor'
  }

  It 'is $false when the block throws' {
    $r = Invoke-Spin 'x' { throw 'nope' } 6>$null
    @($r).Count | Should -Be 1
    $r | Should -BeFalse
  }
}

Describe 'Set-BumpPath' {
  # Three roots, named here as a contract rather than as a description: $HOME,
  # %APPDATA% and %ProgramFiles%. fixup_path, the POSIX twin, draws from $HOME
  # alone, so a suite that sets $HOME is hermetic there; this one reaches outside
  # it, and Apply.Tests.ps1 has to redirect all three to stay a statement about
  # bumpstart rather than about the machine running it. It did not, and the cost was a
  # Windows-only CI failure that read as "the winget install never dispatched": the
  # runner's own C:\Program Files\nodejs went on PATH before the install loop, so
  # node's `Get-Command node` CHECK reported satisfied. A fourth root added here
  # without the same redirect would reintroduce that, so fail on the root list.
  BeforeEach {
    Mock Get-BumpRegistryPath { '' }
    $script:origHome = $HOME
    $script:origPath = $env:PATH
    $script:origAppData = $env:APPDATA
    $script:origProgramFiles = $env:ProgramFiles

    $script:root = Join-Path $TestDrive ('fixup-' + [guid]::NewGuid().ToString('N'))
    $script:fakeHome = Join-Path $script:root 'home'
    $env:APPDATA = Join-Path $script:root 'appdata'
    $env:ProgramFiles = Join-Path $script:root 'programfiles'
    Set-Variable -Name HOME -Scope Global -Value $script:fakeHome -Force
  }
  AfterEach {
    Set-Variable -Name HOME -Scope Global -Value $script:origHome -Force
    $env:PATH = $script:origPath
    foreach ($v in @{ APPDATA = $script:origAppData; ProgramFiles = $script:origProgramFiles }.GetEnumerator()) {
      if ($null -eq $v.Value) { Remove-Item "Env:$($v.Key)" -ErrorAction SilentlyContinue }
      else { Set-Item "Env:$($v.Key)" -Value $v.Value }
    }
  }

  It 'prepends nothing that is not under $HOME, %APPDATA% or %ProgramFiles%' {
    foreach ($d in @(
        (Join-Path $script:fakeHome '.local/bin')
        (Join-Path $script:fakeHome '.codex/bin')
        (Join-Path $env:APPDATA 'npm')
        (Join-Path $env:ProgramFiles 'nodejs'))) {
      New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    $env:PATH = 'SENTINEL'
    Set-BumpPath

    $entries = @($env:PATH -split [regex]::Escape([System.IO.Path]::PathSeparator))
    $entries[-1] | Should -Be 'SENTINEL'   # appended to, never replaced
    $added = @($entries[0..($entries.Count - 2)])
    $added.Count | Should -Be 4            # every candidate existed, so every one was added
    foreach ($e in $added) { $e | Should -BeLike "$script:root*" }
  }

  It 'refreshes registry paths without losing inherited entries or adding duplicates' {
    $env:PATH = 'sentinel'
    Mock Get-BumpRegistryPath { '/new/git;/new/gh;SENTINEL;/NEW/GIT/' }
    Set-BumpPath
    Set-BumpPath
    $entries = @($env:PATH -split [regex]::Escape([IO.Path]::PathSeparator))
    $entries | Should -HaveCount 3
    $entries[0] | Should -Be 'sentinel'
    $entries | Should -Contain '/new/git'
    $entries | Should -Contain '/new/gh'
  }

  It 'prepends only the dirs that exist' {
    # The half that keeps the case above honest: without it a Set-BumpPath that
    # added nothing at all would pass its root check vacuously.
    New-Item -ItemType Directory -Path (Join-Path $script:fakeHome '.local/bin') -Force | Out-Null
    $env:PATH = 'SENTINEL'
    Set-BumpPath

    $entries = @($env:PATH -split [regex]::Escape([System.IO.Path]::PathSeparator))
    $entries.Count | Should -Be 2
    ($entries[0] -replace '\\', '/') | Should -BeLike '*/.local/bin'
  }
}

Describe 'Add-BumpWarning' {
  BeforeEach {
    $script:BumpWarnCount = 0
    $script:BumpWarnItems = @()
  }

  It 'lists one thing once, however many times it was attempted' {
    # The twin of the e2e.bats case: a tool can be attempted twice in one run by
    # design (the substrate and its own block cell), and the same name listed
    # twice reads as a bug in bumpstart rather than as one thing that didn't work.
    Add-BumpWarning 'mise'
    Add-BumpWarning 'mise'
    $script:BumpWarnCount | Should -Be 1
    @($script:BumpWarnItems).Count | Should -Be 1
  }

  It 'counts distinct failures separately' {
    Add-BumpWarning 'mise'
    Add-BumpWarning 'Node.js'
    $script:BumpWarnCount | Should -Be 2
    $script:BumpWarnItems | Should -Contain 'Node.js'
  }
}

Describe 'native installer output encoding' {
  BeforeAll {
    $script:encodingHost = (Get-Process -Id $PID).Path
  }
  BeforeEach { $script:savedEncoding = [Console]::OutputEncoding }
  AfterEach { [Console]::OutputEncoding = $script:savedEncoding }

  It 'decodes native UTF-8 <Stream> and preserves exit <Code>' -TestCases @(
    @{ Stream = 'Output'; Code = 0 }
    @{ Stream = 'Error'; Code = 0 }
    @{ Stream = 'Output'; Code = 7 }
  ) {
    param($Stream, $Code)
    $ErrorActionPreference = 'Continue'
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850)
    $emit = '$b=[byte[]](226,134,146,32,226,154,160,10); $s=[Console]::OpenStandard' + $Stream + '(); $s.Write($b,0,$b.Length); exit ' + $Code
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($emit))
    $out = @(Invoke-Spin 'native encoding probe' {
      & $script:encodingHost -NoProfile -OutputFormat Text -EncodedCommand $encoded
    } 2>&1 6>&1)
    $expected = [string][char]0x2192 + ' ' + [char]0x26A0
    ($out | Out-String).Contains($expected) | Should -BeTrue
    $flags = @($out | Where-Object { $_ -is [bool] })
    $flags | Should -HaveCount 1
    $flags[0] | Should -Be ($Code -eq 0)
    [Console]::OutputEncoding.CodePage | Should -Be 850
  }

  It 'uses UTF-8 during an installer and restores encoding after an exception' {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850)
    $script:insideEncoding = 0
    $ok = Invoke-Spin 'throwing installer' {
      $script:insideEncoding = [Console]::OutputEncoding.CodePage
      throw 'installer failure'
    } 6>$null
    $ok | Should -BeFalse
    $script:insideEncoding | Should -Be 65001
    [Console]::OutputEncoding.CodePage | Should -Be 850
  }
}
