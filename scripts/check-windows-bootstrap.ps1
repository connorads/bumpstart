# Exercise the pasted entry from Restricted without changing registry policy.
# Windows-only: this is intentionally separate from the host-neutral Pester suite.
param([Parameter(Mandatory = $true)][string]$Ref)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$before = @((Get-ExecutionPolicy -Scope CurrentUser), (Get-ExecutionPolicy -Scope LocalMachine))
foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
  if ((Get-ExecutionPolicy -Scope $scope) -ne 'Undefined') {
    throw "The CI fixture must have no managed execution policy ($scope is set)."
  }
}
$originalPath = $env:PATH
$originalRef = $env:BUMP_REF
$env:BUMP_REF = $Ref
$env:BUMP_BOOTSTRAP_FILE = Join-Path $root 'bumpstart.ps1'
$env:BUMP_POLICY_CONTROL = Join-Path $root 'lib/common.ps1'
try {
  # Known-negative control: the fixture must actually enforce Restricted.
  $control = 'try { & $env:BUMP_POLICY_CONTROL; exit 0 } catch { Write-Output "POLICY_BLOCKED"; exit 17 }'
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($control))
  $out = & powershell.exe -NoProfile -ExecutionPolicy Restricted -OutputFormat Text -EncodedCommand $encoded 2>&1 | Out-String
  if ($LASTEXITCODE -ne 17 -or $out -notmatch 'POLICY_BLOCKED') {
    throw "Restricted policy control did not block script files: $out"
  }

  $paste = '& ([scriptblock]::Create((Get-Content -Raw $env:BUMP_BOOTSTRAP_FILE))) -Plan -Yes claude starter'
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($paste))
  foreach ($usePwsh in @($true, $false)) {
    $env:PATH = $originalPath
    if (-not $usePwsh) {
      $env:PATH = (($originalPath -split ';') | Where-Object {
        $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'pwsh.exe'))
      }) -join ';'
    }
    $available = [bool](Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)
    if ($available -ne $usePwsh) { throw "Cannot establish pwsh=$usePwsh fixture" }
    $out = & powershell.exe -NoProfile -ExecutionPolicy Restricted -OutputFormat Text -EncodedCommand $encoded 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Write-Host $out
    if ($rc -ne 0 -or $out -notmatch 'Agent to launch: claude') {
      throw "Restricted paste failed with pwsh=$usePwsh (exit $rc)"
    }
    Write-Host "PASS: Restricted paste reaches preview with pwsh=$usePwsh"
  }
} finally {
  $env:PATH = $originalPath
  $env:BUMP_REF = $originalRef
  Remove-Item Env:BUMP_BOOTSTRAP_FILE, Env:BUMP_POLICY_CONTROL -ErrorAction SilentlyContinue
  $after = @((Get-ExecutionPolicy -Scope CurrentUser), (Get-ExecutionPolicy -Scope LocalMachine))
  if (($before -join '|') -ne ($after -join '|')) { throw 'Permanent execution policy changed' }
}
