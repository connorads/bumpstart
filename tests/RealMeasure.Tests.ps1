# tests/real/lib/measure.ps1: the registry-PATH measurement shared by precheck.ps1
# (before a run) and probe.ps1 (after it). The judge asserts the DELTA between them,
# so the two must ask exactly one question - which is why they are one file, and why
# that file gets its own tests.
#
# The question is "would a new terminal find this tool", and the old answer was a
# hand-written extension list including the empty string. That resolved a DIRECTORY
# named `node` sitting on PATH, and npm's extensionless MSYS shim, which cmd.exe
# cannot execute. Neither is a working install, and both would have read as one.

BeforeAll { . "$PSScriptRoot/../tests/real/lib/measure.ps1" }

Describe 'Test-VibeRegPathResolves' {
  BeforeEach {
    $script:dir = Join-Path ([System.IO.Path]::GetTempPath()) ("vibe-measure-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
    $script:savedExt = $env:PATHEXT
    $env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
  }
  AfterEach {
    Remove-Item -Recurse -Force $script:dir -ErrorAction SilentlyContinue
    $env:PATHEXT = $script:savedExt
  }

  It 'finds an executable with a PATHEXT extension' {
    Set-Content -LiteralPath (Join-Path $script:dir 'node.exe') -Value 'x'
    Test-VibeRegPathResolves 'node' @($script:dir) | Should -BeTrue
  }

  It 'finds a shim with any PATHEXT extension, not just .exe' {
    Set-Content -LiteralPath (Join-Path $script:dir 'pnpm.cmd') -Value 'x'
    Test-VibeRegPathResolves 'pnpm' @($script:dir) | Should -BeTrue
  }

  It 'does NOT resolve a directory that happens to share the name' {
    New-Item -ItemType Directory -Path (Join-Path $script:dir 'node') -Force | Out-Null
    Test-VibeRegPathResolves 'node' @($script:dir) | Should -BeFalse
  }

  It 'does NOT resolve an extensionless file cmd.exe could not execute' {
    # npm's MSYS shim. A new terminal on Windows cannot run it, so reporting it as
    # resolvable is the vacuous pass this measurement exists to avoid.
    Set-Content -LiteralPath (Join-Path $script:dir 'claude') -Value '#!/bin/sh'
    Test-VibeRegPathResolves 'claude' @($script:dir) | Should -BeFalse
  }

  It 'honours PATHEXT rather than a hand-written list' {
    Set-Content -LiteralPath (Join-Path $script:dir 'gh.ps1') -Value 'x'
    Test-VibeRegPathResolves 'gh' @($script:dir) | Should -BeFalse
    $env:PATHEXT = '.COM;.EXE;.PS1'
    Test-VibeRegPathResolves 'gh' @($script:dir) | Should -BeTrue
  }

  It 'says no when the tool is nowhere on the list' {
    Test-VibeRegPathResolves 'mise' @($script:dir) | Should -BeFalse
  }

  It 'ignores an empty or missing directory entry rather than throwing' {
    Test-VibeRegPathResolves 'git' @('', $script:dir) | Should -BeFalse
    Test-VibeRegPathResolves 'git' @() | Should -BeFalse
  }
}

Describe 'the measured set' {
  It 'is the same tools the POSIX side measures' {
    # One list per spine, and they have to agree: the judge reads tool names off the
    # resolved block list and expects a key for each on either OS.
    $posix = (Select-String -Path "$PSScriptRoot/../tests/real/lib/measure.sh" `
      -Pattern '^MEASURE_TOOLS="(.*)"$').Matches[0].Groups[1].Value -split ' '
    (Get-VibeMeasureTool) | Should -Be $posix
  }
}
