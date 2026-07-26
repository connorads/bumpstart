# lib/meta.ps1: the line-reader parser, the pwsh mirror of tests/meta_schema.bats.
# A per-OS cell resolves verbatim (one layer of outer quotes stripped), an unset
# field is '', and a single-quoted $(...) value stays inert — Get-Meta parses, it
# never evaluates.

BeforeAll { . "$PSScriptRoot/../lib/meta.ps1" }

Describe 'Get-Meta' {
  BeforeEach {
    $script:blk = Join-Path $TestDrive 'blk'
    New-Item -ItemType Directory -Path $script:blk -Force | Out-Null
  }

  It 'reads a per-OS INSTALL cell verbatim' {
    Set-Content -LiteralPath (Join-Path $script:blk 'meta') `
      -Value "INSTALL_MAC='curl -fsSL https://example/install.sh | bash'"
    Get-Meta $script:blk 'INSTALL_MAC' | Should -Be 'curl -fsSL https://example/install.sh | bash'
  }

  It 'reads a per-OS CHECK cell verbatim' {
    Set-Content -LiteralPath (Join-Path $script:blk 'meta') `
      -Value "CHECK_MAC='command -v mise >/dev/null 2>&1'"
    Get-Meta $script:blk 'CHECK_MAC' | Should -Be 'command -v mise >/dev/null 2>&1'
  }

  It 'strips one layer of double quotes (matching the shell)' {
    Set-Content -LiteralPath (Join-Path $script:blk 'meta') -Value 'DESC="Install Node.js (LTS)"'
    Get-Meta $script:blk 'DESC' | Should -Be 'Install Node.js (LTS)'
  }

  It 'returns an unquoted value as-is' {
    Set-Content -LiteralPath (Join-Path $script:blk 'meta') -Value 'KIND=harness'
    Get-Meta $script:blk 'KIND' | Should -Be 'harness'
  }

  It 'returns the empty string for an unset field' {
    Set-Content -LiteralPath (Join-Path $script:blk 'meta') -Value 'KIND=tool'
    Get-Meta $script:blk 'INSTALL_WIN' | Should -Be ''
    Get-Meta $script:blk 'SATISFIED_LINUX' | Should -Be ''
  }

  It 'keeps a single-quoted $(...) value inert (parser, not evaluator)' {
    $ran = Join-Path $TestDrive 'RAN'
    $line = "INSTALL_MAC='echo `$(New-Item -ItemType File -Path `"$ran`")'"
    Set-Content -LiteralPath (Join-Path $script:blk 'meta') -Value $line
    Get-Meta $script:blk 'INSTALL_MAC' | Should -Match '\$\('
    Test-Path -LiteralPath $ran | Should -BeFalse
  }
}

Describe 'Get-BlockDir' {
  It 'finds a block dir, a preset dir, or returns null' {
    $root = Join-Path $TestDrive 'root'
    New-Item -ItemType Directory -Path (Join-Path $root 'blocks/foo') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'blocks/foo/meta') -Value 'KIND=tool'
    New-Item -ItemType Directory -Path (Join-Path $root 'presets/bar') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'presets/bar/meta') -Value 'KIND=preset'

    (Get-BlockDir $root 'foo') | Should -Be (Join-Path $root 'blocks/foo')
    (Get-BlockDir $root 'bar') | Should -Be (Join-Path $root 'presets/bar')
    (Get-BlockDir $root 'nope') | Should -BeNullOrEmpty
  }
}
