# lib/os.ps1: current-OS token detection, the pwsh mirror of tests/os.bats. The
# {mac,win,linux} token set (uppercased to MAC|WIN|LINUX) is the cross-spine
# contract. pwsh detection can't be faked the way uname is, so the deterministic
# assertions drive the $env:BUMP_OS seam (also the mac-hosted Windows e2e's lever)
# and the host truth is asserted loosely.

BeforeAll { . "$PSScriptRoot/../lib/os.ps1" }

Describe 'Get-BumpOs' {
  AfterEach { Remove-Item Env:BUMP_OS -ErrorAction SilentlyContinue }

  It 'honours the BUMP_OS override: <token>' -ForEach @(
    @{ token = 'mac' }, @{ token = 'win' }, @{ token = 'linux' }
  ) {
    $env:BUMP_OS = $token
    Get-BumpOs | Should -Be $token
  }

  It 'returns a valid token on the host with no override' {
    Get-BumpOs | Should -BeIn @('mac', 'win', 'linux')
  }
}

Describe 'Get-BumpOsKey' {
  AfterEach { Remove-Item Env:BUMP_OS -ErrorAction SilentlyContinue }

  It 'is the uppercase OS token: <token> -> <key>' -ForEach @(
    @{ token = 'mac'; key = 'MAC' }
    @{ token = 'win'; key = 'WIN' }
    @{ token = 'linux'; key = 'LINUX' }
  ) {
    $env:BUMP_OS = $token
    Get-BumpOsKey | Should -Be $key
  }
}
