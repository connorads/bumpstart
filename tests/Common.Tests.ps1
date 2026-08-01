# lib/common.ps1: the UI helpers. Focus: the Invoke-Spin contract in plain mode
# (no UiFancy) - run the block, stream its output through, and return ONE
# boolean saying whether it worked. The pwsh twin of tests/common.bats, which
# had none: every fake in the pwsh suite was silent, so the failure paths only
# ever exercised a block that printed nothing.
#
# Plus the warning ledger's dedupe, the twin of the e2e.bats case.

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

Describe 'Add-BumpWarning' {
  BeforeEach {
    $script:BumpWarnCount = 0
    $script:BumpWarnItems = @()
  }

  It 'lists one thing once, however many times it was attempted' {
    # The twin of the e2e.bats case: a tool can be attempted twice in one run by
    # design (the substrate and its own block cell), and the same name listed
    # twice reads as a bug in vibe rather than as one thing that didn't work.
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
