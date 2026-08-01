# lib/run.ps1: the generic declarative runner, the pwsh mirror of tests/run.bats.
# Synthetic blocks carry host-keyed cells whose VALUES are PowerShell (the pwsh
# runner Invoke-Expressions them, so the cell body must be pwsh). A fake-log file
# stands in for the PATH-shadow fakes: install cells append to it.

BeforeAll {
  $env:NO_COLOR = '1'   # set before common.ps1 loads so UI stays plain + capturable
  . "$PSScriptRoot/../lib/common.ps1"
  . "$PSScriptRoot/../lib/meta.ps1"
  . "$PSScriptRoot/../lib/os.ps1"
  . "$PSScriptRoot/../lib/run.ps1"
  $script:osKey = Get-VibeOsKey

  function New-Block {
    param([string]$Id, [string[]]$Lines)
    $dir = Join-Path $script:root "blocks/$Id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'meta') -Value $Lines
  }

  # Meta lines are pwsh single-quoted literals so $ stays literal (expanded only
  # by the runner's Invoke-Expression at run time) and the cell's own single
  # quotes are the doubled ''. An INSTALL cell that records itself to the log:
  $script:logInstall = "INSTALL_$script:osKey='Add-Content -LiteralPath `$env:BUMP_FAKE_LOG -Value `"brew install thing`"'"

  # Cells that PRINT and then fail - the normal shape of a real WIN cell, since
  # winget, irm|iex and npm all narrate. Nothing else in this suite writes to
  # stdout, so without these the failure paths only ever exercised a silent block.
  $script:printThenThrow = "INSTALL_$script:osKey='Write-Output `"vendor chatter`"; throw `"vendor exploded`"'"
  $script:printThenRc    = "INSTALL_$script:osKey='Write-Output `"vendor chatter`"; `$global:LASTEXITCODE = 1'"
}

Describe 'run.ps1' {
  BeforeEach {
    $script:root = Join-Path $TestDrive 'root'
    New-Item -ItemType Directory -Path (Join-Path $script:root 'blocks') -Force | Out-Null
    $env:BUMP_FAKE_LOG = Join-Path $TestDrive 'fake.log'
    Set-Content -LiteralPath $env:BUMP_FAKE_LOG -Value ''
  }
  AfterEach { Remove-Item Env:BUMP_FAKE_LOG -ErrorAction SilentlyContinue }

  It 'Test-BlockCheck is $true when the CHECK cell passes' {
    New-Block present @('KIND=tool', "CHECK_$script:osKey='`$true'")
    Test-BlockCheck $script:root 'present' | Should -BeTrue
  }

  It 'Test-BlockCheck is $false when the CHECK cell fails' {
    New-Block absent @('KIND=tool', "CHECK_$script:osKey='`$false'")
    Test-BlockCheck $script:root 'absent' | Should -BeFalse
  }

  It 'Test-BlockCheck is $null when there is no CHECK cell' {
    New-Block bare @('KIND=instructions', 'DESC=x')
    Test-BlockCheck $script:root 'bare' | Should -BeNullOrEmpty
  }

  It 'Test-BlockCheck reads the OUTPUT of the cell, not its exit status' {
    # The Windows contract is the opposite of the POSIX one, on the same field
    # family: bash reads a CHECK cell's exit status, this reads the truthiness of
    # what the cell returns. Pinned in both directions so a future "make it match
    # bash" refactor fails loudly instead of silently marking every Windows block
    # installed. A cell that emits something is satisfied...
    New-Block emits @('KIND=tool', "CHECK_$script:osKey='`"anything`"'")
    Test-BlockCheck $script:root 'emits' | Should -BeTrue
  }

  It 'Test-BlockCheck is $false for a cell that succeeds but emits nothing' {
    # ...and one that emits nothing is NOT, however cleanly it ran. This is what
    # `Get-Command x -ErrorAction SilentlyContinue` relies on, and why the winget
    # cells pipe through Select-String rather than trusting winget's exit code.
    New-Block silent @('KIND=tool', "CHECK_$script:osKey='`$null'")
    Test-BlockCheck $script:root 'silent' | Should -BeFalse
  }

  It 'Invoke-Cell skips the install when already satisfied' {
    New-Block sat @('KIND=tool', 'LABEL=thing', "CHECK_$script:osKey='`$true'", $logInstall)
    $out = Invoke-Cell $script:root 'sat' 6>&1 | Out-String
    $out | Should -Match 'already installed'
    (Get-Content -Raw -LiteralPath $env:BUMP_FAKE_LOG) | Should -Not -Match 'brew install thing'
  }

  It 'Invoke-Cell runs the install when not satisfied' {
    New-Block act @('KIND=tool', 'LABEL=thing', "CHECK_$script:osKey='`$false'", $logInstall)
    Invoke-Cell $script:root 'act' 6>&1 | Out-Null
    (Get-Content -Raw -LiteralPath $env:BUMP_FAKE_LOG) | Should -Match 'brew install thing'
  }

  It 'Invoke-Cell is a silent no-op for an unmapped block' {
    New-Block note @('KIND=instructions', 'DESC=x')
    $out = Invoke-Cell $script:root 'note' 6>&1 | Out-String
    $out.Trim() | Should -BeNullOrEmpty
  }

  It 'Invoke-Cell warns but does not throw when the install fails (non-fatal)' {
    New-Block boom @('KIND=tool', 'LABEL=thing', "CHECK_$script:osKey='`$false'", "INSTALL_$script:osKey='throw `"fail`"'")
    $out = Invoke-Cell $script:root 'boom' 6>&1 | Out-String
    $out | Should -Match "Couldn't install"
  }

  It 'Invoke-Cell warns when the install PRINTED and then threw' {
    # The case the silent fakes never reached: the cell's chatter used to ride
    # back on the success stream beside Invoke-Spin's flag, making the result a
    # truthy array - so this printed "installed" over a machine where nothing
    # landed, and never reached the ledger.
    New-Block noisy @('KIND=tool', 'LABEL=thing', "CHECK_$script:osKey='`$false'", $printThenThrow)
    $script:VibeWarnCount = 0
    $script:VibeWarnItems = @()
    $out = Invoke-Cell $script:root 'noisy' 6>&1 | Out-String
    $out | Should -Match "Couldn't install thing"
    $out | Should -Not -Match 'thing installed'
    $script:VibeWarnItems | Should -Contain 'thing'
  }

  It 'Invoke-Cell warns when the install PRINTED and then left a non-zero exit code' {
    New-Block noisyrc @('KIND=tool', 'LABEL=thing', "CHECK_$script:osKey='`$false'", $printThenRc)
    $script:VibeWarnCount = 0
    $script:VibeWarnItems = @()
    $out = Invoke-Cell $script:root 'noisyrc' 6>&1 | Out-String
    $out | Should -Match "Couldn't install thing"
    $out | Should -Not -Match 'thing installed'
    $script:VibeWarnItems | Should -Contain 'thing'
  }

  It "Invoke-Cell shows the vendor's own output" {
    New-Block chatty @('KIND=tool', 'LABEL=thing', "CHECK_$script:osKey='`$false'", $printThenRc)
    $out = Invoke-Cell $script:root 'chatty' 6>&1 | Out-String
    $out | Should -Match 'vendor chatter'
  }

  It 'Invoke-Cell falls back to DESC for the label when LABEL is unset' {
    New-Block desc @('KIND=tool', 'DESC="the widget"', "CHECK_$script:osKey='`$true'", $logInstall)
    $out = Invoke-Cell $script:root 'desc' 6>&1 | Out-String
    $out | Should -Match 'the widget already installed'
  }

  It 'Test-BlockRuns is true for a block with an INSTALL cell' {
    New-Block cell @('KIND=tool', $logInstall)
    Test-BlockRuns $script:root 'cell' | Should -BeTrue
  }

  It 'Test-BlockRuns is true for a block with an apply.ps1 (escape hatch)' {
    New-Block script @('KIND=auth', 'DESC=x')
    Set-Content -LiteralPath (Join-Path $script:root 'blocks/script/apply.ps1') -Value '# tail'
    Test-BlockRuns $script:root 'script' | Should -BeTrue
  }

  It 'Test-BlockRuns is false for an instruction-only block' {
    New-Block only @('KIND=instructions', 'DESC=x')
    Test-BlockRuns $script:root 'only' | Should -BeFalse
  }
}
