BeforeAll {
  $script:bootstrap = (Resolve-Path "$PSScriptRoot/../bumpstart.ps1").Path
  $script:hostExe = (Get-Process -Id $PID).Path

  function Invoke-BootstrapProbe {
    param([string]$Mode = 'ok', [int]$ExitCode = 0)
    $env:BUMP_PROBE_BOOTSTRAP = $script:bootstrap
    $env:BUMP_PROBE_MODE = $Mode
    $env:BUMP_PROBE_EXIT = [string]$ExitCode
    $code = @'
$PSVersionTable.PSEdition = 'Desktop'
function Get-ExecutionPolicy {
  param($Scope)
  if ($env:BUMP_PROBE_MODE -eq 'policy') { return 'AllSigned' }
  return 'Undefined'
}
function Invoke-RestMethod {
  param($Uri, $OutFile)
  if ($env:BUMP_PROBE_MODE -eq 'download') { throw 'probe download failed' }
}
function tar {
  if ($env:BUMP_PROBE_MODE -eq 'tar') { $global:LASTEXITCODE = 2; return }
  $global:LASTEXITCODE = 0
  if ($env:BUMP_PROBE_MODE -eq 'layout') { return }
  $dest = Join-Path $args[-1] 'source/lib'
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  'Write-Host ("APPLY_ARGS=" + ($args -join "|")); exit ([int]$env:BUMP_PROBE_EXIT)' | Set-Content (Join-Path $dest 'apply.ps1')
}
& ([scriptblock]::Create((Get-Content -Raw $env:BUMP_PROBE_BOOTSTRAP))) claude starter -Plan
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $out = & $script:hostExe -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String
    return @{ Text = $out; Code = $LASTEXITCODE }
  }
}

AfterAll {
  'BUMP_PROBE_BOOTSTRAP', 'BUMP_PROBE_MODE', 'BUMP_PROBE_EXIT' | ForEach-Object {
    Remove-Item "Env:$_" -ErrorAction SilentlyContinue
  }
}

Describe 'Windows paste bootstrap' {
  It 'dispatches a successful setup' {
    $r = Invoke-BootstrapProbe
    $r.Text | Should -Match 'APPLY_ARGS=claude\|starter\|-Plan'
    $r.Code | Should -Be 0
  }

  It 'hands arguments to the child applier and preserves its failure exit code' {
    $r = Invoke-BootstrapProbe -ExitCode 7
    $r.Text | Should -Match 'APPLY_ARGS=claude\|starter\|-Plan'
    $r.Code | Should -Be 7
  }

  It 'returns failure for a download error' {
    $r = Invoke-BootstrapProbe -Mode download
    $r.Text | Should -Match 'could not fetch'
    $r.Text | Should -Not -Match 'APPLY_ARGS='
    $r.Code | Should -Be 1
  }

  It 'does not dispatch after tar fails' {
    $r = Invoke-BootstrapProbe -Mode tar
    $r.Text | Should -Not -Match 'APPLY_ARGS='
    $r.Code | Should -Be 1
  }

  It 'returns failure for an unexpected archive layout' {
    $r = Invoke-BootstrapProbe -Mode layout
    $r.Text | Should -Match 'unexpected tarball layout'
    $r.Code | Should -Be 1
  }

  It 'does not switch hosts to bypass an incoming managed policy' {
    $r = Invoke-BootstrapProbe -Mode policy
    $r.Text | Should -Match 'managed.*policy'
    $r.Text | Should -Not -Match 'APPLY_ARGS='
    $r.Code | Should -Be 1
  }
}
