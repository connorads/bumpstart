# lib/shellpath.ps1: the Windows half of "a new terminal still finds your tools".
#
# The DECISION half - which dirs go on the PATH, and whether any of them is already
# there - is pure, so it runs anywhere. The EFFECT half writes HKCU\Environment and
# broadcasts WM_SETTINGCHANGE, and it reaches that registry through exactly one
# function: Get-BumpUserEnvKey. That single door is the seam. Faking it asserts BOTH
# worlds - a host with a per-user registry and a host without one - on every host, so
# no case here is gated on the machine it happens to run on.
#
# Which is the point, because this file runs in both check jobs: `check` on macOS and
# `check-windows` on real Windows. A test stating "there is no user registry" is a
# claim about the host, true in one job and false in the other; a test that WRITES
# unfaked aims a $TestDrive path at the account PATH of whoever ran the suite. The
# seam removes both problems at once, and proving the no-op everywhere is strictly
# stronger than proving it where the host happens to lack a registry.
#
# Left to the windows-real-install lane: only the real registry value and the real
# broadcast, which need a logon session no hosted runner gives us.
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
  . "$PSScriptRoot/helpers/FakeEnvKey.ps1"
}

Describe 'Get-BumpPathUpdate' {
  BeforeEach {
    $script:dirs = @('C:\Users\me\.local\bin', 'C:\Users\me\.codex\bin')
  }

  It 'appends both dirs to a PATH that has neither' {
    $u = Get-BumpPathUpdate -Current 'C:\Windows;C:\Windows\System32' -Dirs $script:dirs
    $u.Changed | Should -BeTrue
    $u.Added.Count | Should -Be 2
    $u.Value | Should -Be 'C:\Windows;C:\Windows\System32;C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
  }

  It 'changes nothing when both dirs are already there' {
    # The second run of the lane, and the second run of a beginner's paste. A PATH
    # that grows by two entries per install is the regression this asserts against.
    $current = 'C:\Windows;C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
    $u = Get-BumpPathUpdate -Current $current -Dirs $script:dirs
    $u.Changed | Should -BeFalse
    $u.Added.Count | Should -Be 0
    $u.Value | Should -Be $current
  }

  It 'recognises an entry that differs only by a trailing backslash' {
    $u = Get-BumpPathUpdate -Current 'C:\Users\me\.local\bin\;C:\Users\me\.codex\bin\' -Dirs $script:dirs
    $u.Changed | Should -BeFalse
  }

  It 'recognises an entry that differs only in case' {
    # Windows paths are case-insensitive, so C:\USERS\ME\.Local\Bin is the same dir.
    $u = Get-BumpPathUpdate -Current 'C:\USERS\ME\.LOCAL\BIN;c:\users\me\.codex\bin' -Dirs $script:dirs
    $u.Changed | Should -BeFalse
  }

  It 'recognises an entry written as an environment reference' {
    # A hand-authored PATH usually says %USERPROFILE%\.local\bin. Appending the
    # literal beside it is a duplicate that reads as two different dirs.
    $env:BUMP_TEST_PROFILE = 'C:\Users\me'
    try {
      $u = Get-BumpPathUpdate -Current '%BUMP_TEST_PROFILE%\.local\bin;%BUMP_TEST_PROFILE%\.codex\bin' -Dirs $script:dirs
      $u.Changed | Should -BeFalse
    } finally {
      Remove-Item Env:BUMP_TEST_PROFILE -ErrorAction SilentlyContinue
    }
  }

  It 'leaves an environment reference it did not author unexpanded' {
    # The value written back must not bake in today's expansion of somebody else's
    # entry: that is a permanent change to a PATH bumpstart was not asked to touch, and it
    # is why the raw registry value is read rather than the expanding accessor.
    $env:BUMP_TEST_PROFILE = 'C:\Users\me'
    try {
      $u = Get-BumpPathUpdate -Current '%BUMP_TEST_PROFILE%\bin' -Dirs $script:dirs
      $u.Changed | Should -BeTrue
      $u.Value | Should -BeLike '%BUMP_TEST_PROFILE%\bin;*'
    } finally {
      Remove-Item Env:BUMP_TEST_PROFILE -ErrorAction SilentlyContinue
    }
  }

  It 'handles an empty PATH without a leading separator' {
    # An empty user PATH is the normal state of a fresh Windows account, so a
    # `;C:\...` value - which reads as "the current directory" - is the wrong answer.
    $u = Get-BumpPathUpdate -Current '' -Dirs $script:dirs
    $u.Changed | Should -BeTrue
    $u.Value | Should -Be 'C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
  }

  It 'drops empty entries rather than preserving a malformed PATH' {
    $u = Get-BumpPathUpdate -Current 'C:\Windows;;  ;' -Dirs $script:dirs
    $u.Value | Should -Be 'C:\Windows;C:\Users\me\.local\bin;C:\Users\me\.codex\bin'
  }

  It 'adds only the dir that is missing' {
    $u = Get-BumpPathUpdate -Current 'C:\Users\me\.local\bin' -Dirs $script:dirs
    $u.Changed | Should -BeTrue
    $u.Added | Should -Be @('C:\Users\me\.codex\bin')
  }
}

Describe 'Get-BumpOwnedPathDir' {
  It 'is exactly the two dirs whose installers persist nothing' {
    # winget puts node, git, gh and the desktop apps on a registry PATH itself, so
    # claiming those here would author a duplicate of somebody else's entry. The
    # README's removal instructions name these same two.
    $dirs = Get-BumpOwnedPathDir
    $dirs.Count | Should -Be 2
    ($dirs[0] -replace '\\', '/') | Should -BeLike '*/.local/bin'
    ($dirs[1] -replace '\\', '/') | Should -BeLike '*/.codex/bin'
  }
}

Describe 'the effect half, where there is no user registry' {
  # A Mac, and equally a Windows account whose Environment key will not open. Faked
  # rather than left to the host: asserted here it holds on every machine the suite
  # runs on, and it cannot go red for the reason it once did - by stating a fact about
  # the host in a suite that runs on two of them.
  BeforeEach {
    Mock Get-BumpUserEnvKey { $null }
    Mock Send-BumpEnvironmentChange { }
  }

  It 'is a no-op rather than a crash' {
    # apply.ps1 guards non-Windows before any of this runs, but the Pester suite
    # drives the whole applier with BUMP_OS=win on a Mac - so this path is real and
    # has to stay quiet.
    Test-BumpUserEnvironment | Should -BeFalse
    Get-BumpUserPathRaw | Should -Be ''
    Test-BumpPersistedPath | Should -BeFalse
    { Set-BumpPersistedPath } | Should -Not -Throw
    # Quiet all the way out: nothing to write means nothing to announce either.
    Should -Invoke Send-BumpEnvironmentChange -Times 0 -Exactly
  }
}

Describe 'the effect half, where there is a user registry' {
  # The same effect against a fake key rather than the account of whoever ran the
  # suite. What this buys over the real-install lane: the lane is Windows-only,
  # weekly, and cannot fail a PR - so the value written, its KIND and the second-run
  # no-op were asserted nowhere a change to this file gets reviewed.
  BeforeEach {
    $script:reg = New-FakeEnvState -Value 'C:\Windows'
    $script:key = New-FakeEnvKey $script:reg
    Mock Get-BumpUserEnvKey { $script:key }
    # The broadcast needs a desktop to hear it and a user32.dll to make it. Its absence
    # is already non-fatal in the code; faking it keeps this suite from shouting at the
    # window manager of whoever is running.
    Mock Send-BumpEnvironmentChange { }
  }

  It 'reads the account PATH back before it has anything of bumpstart own in it' {
    Test-BumpUserEnvironment | Should -BeTrue
    Get-BumpUserPathRaw | Should -Be 'C:\Windows'
    # The confirm gate is state-aware, so "already there" has to be false here or the
    # gate promises a PATH edit it will not make.
    Test-BumpPersistedPath | Should -BeFalse
  }

  It 'appends the owned dirs and writes the value as an ExpandString' {
    Set-BumpPersistedPath 6>$null
    $script:reg.Writes | Should -Be 1
    ($script:reg.Value -replace '\\', '/') | Should -BeLike 'C:/Windows;*/.local/bin;*/.codex/bin'
    # Not a plain String: a REG_SZ value would kill every %VAR% already in the PATH.
    $script:reg.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    # Without the broadcast the registry is right and a new terminal is still wrong
    # until the next sign-in, so it is part of the promise, not a flourish.
    Should -Invoke Send-BumpEnvironmentChange -Times 1 -Exactly
  }

  It 'writes nothing on a second run' {
    # The pure core already refuses to duplicate; this is the same promise through the
    # effect, which is where a beginner's second paste actually lands.
    Set-BumpPersistedPath 6>$null
    Set-BumpPersistedPath 6>$null
    $script:reg.Writes | Should -Be 1
    # ...and the gate for a third run now says so, rather than promising the edit again.
    Test-BumpPersistedPath | Should -BeTrue
  }

  It 'leaves an entry it did not author unexpanded in what it writes' {
    # The reason the raw value is read rather than the expanding accessor: writing back
    # today's expansion of somebody else's %VAR% is a permanent change to a PATH bumpstart
    # was not asked to touch. Asserted end to end here, not only on the pure core.
    $script:reg.Value = '%BUMP_TEST_PROFILE%\bin'
    $env:BUMP_TEST_PROFILE = 'C:\Users\me'
    try {
      Set-BumpPersistedPath 6>$null
      $script:reg.Value | Should -BeLike '%BUMP_TEST_PROFILE%\bin;*'
    } finally {
      Remove-Item Env:BUMP_TEST_PROFILE -ErrorAction SilentlyContinue
    }
  }

  It 'warns rather than throwing when the key cannot be opened for writing' {
    Mock Get-BumpUserEnvKey { if ($Writable) { return $null } return $script:key }
    { Set-BumpPersistedPath 3>$null 6>$null } | Should -Not -Throw
    $script:reg.Writes | Should -Be 0
  }

  It 'warns rather than throwing when the write itself is refused' {
    # A managed or locked-down account. The setup has already done everything else it
    # promised, so this ends in a warning, not a failure.
    $script:reg.Writable = $false
    { Set-BumpPersistedPath 3>$null 6>$null } | Should -Not -Throw
  }
}

Describe 'the seam itself, unmocked' {
  # The one thing a fake cannot cover: Get-BumpUserEnvKey's own try/catch, which is
  # what makes "no registry" a value rather than an exception. Off Windows the .NET
  # registry API raises PlatformNotSupportedException; on Windows it returns a key.
  # Either answer is fine here - the point is that it ANSWERS, on whichever host you
  # are on, because every caller above treats the result as data.
  #
  # Nothing in this block writes. Set-BumpPersistedPath is deliberately absent: unfaked
  # it edits the account PATH of whoever ran the suite.
  It 'answers with a key or with nothing, and never throws' {
    { $script:probe = Get-BumpUserEnvKey } | Should -Not -Throw
    if ($script:probe) { $script:probe.Close() }

    Test-BumpUserEnvironment | Should -BeOfType [bool]
    Get-BumpUserPathRaw     | Should -BeOfType [string]
    Test-BumpPersistedPath  | Should -BeOfType [bool]
  }
}
