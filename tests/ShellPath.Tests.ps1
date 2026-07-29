# lib/shellpath.ps1: the Windows half of "a new terminal still finds your tools".
#
# The effect half writes HKCU:\Environment and broadcasts WM_SETTINGCHANGE, so no
# hosted runner outside the Windows lane can exercise it. The DECISION half - which
# dirs go on the PATH, and whether any of them is already there - is pure, and this
# suite runs on macOS in the `check` job, so the logic that decides whether to write
# at all is covered without a Windows runner.
#
# What each case is about: the failure being fixed is claude-cli installing into
# %USERPROFILE%\.local\bin from a vendor script that persists nothing, so
# `derived.shell.regpath.claude` read [absent] where [installed] was wanted. The
# failure NOT to introduce while fixing it is a duplicate entry - which is what the
# already-present cases are for, in each of the four spellings a real PATH uses.

BeforeAll {
  $env:NO_COLOR = '1'
  . "$PSScriptRoot/../lib/common.ps1"
  . "$PSScriptRoot/../lib/shellpath.ps1"
}

Describe 'Get-VibePathUpdate' {
  BeforeEach {
    $script:dirs = @('C:\Users\me\.local\bin', 'C:\Users\me\.codex\bin')
  }

  It 'appends both dirs to a PATH that has neither' {
    $u = Get-VibePathUpdate -Current 'C:\Windows;C:\Windows\System32' -Dirs $script:dirs
    $u.Changed | Should -BeTrue
    $u.Added.Count | Should -Be 2
    $u.Value | Should -Be 'C:\Windows;C:\Windows\System32;C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
  }

  It 'changes nothing when both dirs are already there' {
    # The second run of the lane, and the second run of a beginner's paste. A PATH
    # that grows by two entries per install is the regression this asserts against.
    $current = 'C:\Windows;C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
    $u = Get-VibePathUpdate -Current $current -Dirs $script:dirs
    $u.Changed | Should -BeFalse
    $u.Added.Count | Should -Be 0
    $u.Value | Should -Be $current
  }

  It 'recognises an entry that differs only by a trailing backslash' {
    $u = Get-VibePathUpdate -Current 'C:\Users\me\.local\bin\;C:\Users\me\.codex\bin\' -Dirs $script:dirs
    $u.Changed | Should -BeFalse
  }

  It 'recognises an entry that differs only in case' {
    # Windows paths are case-insensitive, so C:\USERS\ME\.Local\Bin is the same dir.
    $u = Get-VibePathUpdate -Current 'C:\USERS\ME\.LOCAL\BIN;c:\users\me\.codex\bin' -Dirs $script:dirs
    $u.Changed | Should -BeFalse
  }

  It 'recognises an entry written as an environment reference' {
    # A hand-authored PATH usually says %USERPROFILE%\.local\bin. Appending the
    # literal beside it is a duplicate that reads as two different dirs.
    $env:VIBE_TEST_PROFILE = 'C:\Users\me'
    try {
      $u = Get-VibePathUpdate -Current '%VIBE_TEST_PROFILE%\.local\bin;%VIBE_TEST_PROFILE%\.codex\bin' -Dirs $script:dirs
      $u.Changed | Should -BeFalse
    } finally {
      Remove-Item Env:VIBE_TEST_PROFILE -ErrorAction SilentlyContinue
    }
  }

  It 'leaves an environment reference it did not author unexpanded' {
    # The value written back must not bake in today's expansion of somebody else's
    # entry: that is a permanent change to a PATH vibe was not asked to touch, and it
    # is why the raw registry value is read rather than the expanding accessor.
    $env:VIBE_TEST_PROFILE = 'C:\Users\me'
    try {
      $u = Get-VibePathUpdate -Current '%VIBE_TEST_PROFILE%\bin' -Dirs $script:dirs
      $u.Changed | Should -BeTrue
      $u.Value | Should -BeLike '%VIBE_TEST_PROFILE%\bin;*'
    } finally {
      Remove-Item Env:VIBE_TEST_PROFILE -ErrorAction SilentlyContinue
    }
  }

  It 'handles an empty PATH without a leading separator' {
    # An empty user PATH is the normal state of a fresh Windows account, so a
    # `;C:\...` value - which reads as "the current directory" - is the wrong answer.
    $u = Get-VibePathUpdate -Current '' -Dirs $script:dirs
    $u.Changed | Should -BeTrue
    $u.Value | Should -Be 'C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
  }

  It 'drops empty entries rather than preserving a malformed PATH' {
    $u = Get-VibePathUpdate -Current 'C:\Windows;;  ;' -Dirs $script:dirs
    $u.Value | Should -Be 'C:\Windows;C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
  }

  It 'adds only the dir that is missing' {
    $u = Get-VibePathUpdate -Current 'C:\Users\me\.local\bin' -Dirs $script:dirs
    $u.Changed | Should -BeTrue
    $u.Added | Should -Be @('C:\Users\me\.codex\bin')
  }
}

Describe 'Get-VibeOwnedPathDir' {
  It 'is exactly the two dirs whose installers persist nothing' {
    # winget puts node, git, gh and the desktop apps on a registry PATH itself, so
    # claiming those here would author a duplicate of somebody else's entry. The
    # README's removal instructions name these same two.
    $dirs = Get-VibeOwnedPathDir
    $dirs.Count | Should -Be 2
    ($dirs[0] -replace '\\', '/') | Should -BeLike '*/.local/bin'
    ($dirs[1] -replace '\\', '/') | Should -BeLike '*/.codex/bin'
  }
}

Describe 'the effect half, off Windows' {
  It 'is a no-op where there is no user registry, rather than a crash' {
    # apply.ps1 guards non-Windows before any of this runs, but the Pester suite
    # drives the whole applier with VIBE_OS=win on a Mac - so this path is real and
    # has to stay quiet.
    Test-VibeUserEnvironment | Should -BeFalse
    Get-VibeUserPathRaw | Should -Be ''
    Test-VibePersistedPath | Should -BeFalse
    { Set-VibePersistedPath } | Should -Not -Throw
  }
}
