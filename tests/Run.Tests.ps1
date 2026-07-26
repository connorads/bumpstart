# lib/run.ps1: the generic declarative runner, the pwsh mirror of tests/run.bats.
# Synthetic blocks carry MAC-keyed cells whose VALUES are PowerShell (the pwsh
# runner Invoke-Expressions them, so the cell body must be pwsh) — runner
# mechanics are OS-token-agnostic; real WIN dispatch is covered in slice 4. A
# fake-log file stands in for the PATH-shadow fakes: install cells append to it.

BeforeAll {
  $env:NO_COLOR = '1'   # set before common.ps1 loads so UI stays plain + capturable
  . "$PSScriptRoot/../lib/common.ps1"
  . "$PSScriptRoot/../lib/meta.ps1"
  . "$PSScriptRoot/../lib/os.ps1"
  . "$PSScriptRoot/../lib/run.ps1"

  function New-Block {
    param([string]$Id, [string[]]$Lines)
    $dir = Join-Path $script:root "blocks/$Id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'meta') -Value $Lines
  }

  # Meta lines are pwsh single-quoted literals so $ stays literal (expanded only
  # by the runner's Invoke-Expression at run time) and the cell's own single
  # quotes are the doubled ''. An INSTALL cell that records itself to the log:
  $script:logInstall = 'INSTALL_MAC=''Add-Content -LiteralPath $env:VIBE_FAKE_LOG -Value "brew install thing"'''
}

Describe 'run.ps1' {
  BeforeEach {
    $script:root = Join-Path $TestDrive 'root'
    New-Item -ItemType Directory -Path (Join-Path $script:root 'blocks') -Force | Out-Null
    $env:VIBE_FAKE_LOG = Join-Path $TestDrive 'fake.log'
    Set-Content -LiteralPath $env:VIBE_FAKE_LOG -Value ''
  }
  AfterEach { Remove-Item Env:VIBE_FAKE_LOG -ErrorAction SilentlyContinue }

  It 'Test-BlockCheck is $true when the CHECK cell passes' {
    New-Block present @('KIND=tool', 'CHECK_MAC=''$true''')
    Test-BlockCheck $script:root 'present' | Should -BeTrue
  }

  It 'Test-BlockCheck is $false when the CHECK cell fails' {
    New-Block absent @('KIND=tool', 'CHECK_MAC=''$false''')
    Test-BlockCheck $script:root 'absent' | Should -BeFalse
  }

  It 'Test-BlockCheck is $null when there is no CHECK cell' {
    New-Block bare @('KIND=instructions', 'DESC=x')
    Test-BlockCheck $script:root 'bare' | Should -BeNullOrEmpty
  }

  It 'Invoke-Cell skips the install when already satisfied' {
    New-Block sat @('KIND=tool', 'LABEL=thing', 'CHECK_MAC=''$true''', $logInstall)
    $out = Invoke-Cell $script:root 'sat' 6>&1 | Out-String
    $out | Should -Match 'already installed'
    (Get-Content -Raw -LiteralPath $env:VIBE_FAKE_LOG) | Should -Not -Match 'brew install thing'
  }

  It 'Invoke-Cell runs the install when not satisfied' {
    New-Block act @('KIND=tool', 'LABEL=thing', 'CHECK_MAC=''$false''', $logInstall)
    Invoke-Cell $script:root 'act' 6>&1 | Out-Null
    (Get-Content -Raw -LiteralPath $env:VIBE_FAKE_LOG) | Should -Match 'brew install thing'
  }

  It 'Invoke-Cell is a silent no-op for an unmapped block' {
    New-Block note @('KIND=instructions', 'DESC=x')
    $out = Invoke-Cell $script:root 'note' 6>&1 | Out-String
    $out.Trim() | Should -BeNullOrEmpty
  }

  It 'Invoke-Cell warns but does not throw when the install fails (non-fatal)' {
    New-Block boom @('KIND=tool', 'LABEL=thing', 'CHECK_MAC=''$false''', 'INSTALL_MAC=''throw "fail"''')
    $out = Invoke-Cell $script:root 'boom' 6>&1 | Out-String
    $out | Should -Match "Couldn't install"
  }

  It 'Invoke-Cell falls back to DESC for the label when LABEL is unset' {
    New-Block desc @('KIND=tool', 'DESC="the widget"', 'CHECK_MAC=''$true''', $logInstall)
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

