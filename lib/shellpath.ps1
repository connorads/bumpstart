# shellpath.ps1: make the dirs vibe installs into survive the terminal window, on
# Windows. The mirror of lib/shellpath.sh, and of the same promise.
#
# Set-VibePath (common.ps1) fixes PATH for THIS process only - it is fixup_path's
# twin. What that leaves is the failure shellpath.sh's own opening comment names: a
# beginner watches the install work, opens a new terminal, and is told "command not
# found", the most demoralising way for a setup to fail, because nothing looked
# broken. On Windows the pattern is narrower but real: everything installed via
# winget lands on a registry PATH courtesy of its own installer, and the CLI agents
# do NOT - claude-cli installs into %USERPROFILE%\.local\bin and codex-cli into
# %USERPROFILE%\.codex\bin, from vendor scripts that persist nothing - while the
# run's own closing line tells the reader to type `claude`.
#
# This is the ONLY thing outside vibe's own config paths that the Windows spine
# changes, and it is disclosed at the confirm gate (Show-Expectations in plan.ps1),
# exactly as the POSIX rc line is. A registry value has nowhere to put a comment
# marker, so removal is not "delete the marked block" but "delete these two dirs" -
# which is what the README says.
#
# Two things make this file testable anywhere. The pure core (Get-VibePathUpdate)
# holds all the logic, and the effect reaches the registry through exactly one
# function - Get-VibeUserEnvKey - which is the seam the suite fakes. So both worlds,
# a host with a per-user registry and a host without one, are asserted on every host,
# and no test writes the account PATH of whoever ran it. Windows PowerShell 5.1-clean.

# The user registry key that holds the per-account environment. Named once: three
# functions below open it, and a typo in one of them would be a silent no-op.
#
# Reached through the .NET registry API rather than the HKCU: provider drive, so the
# value KIND is spelled explicitly on both sides: reading needs
# DoNotExpandEnvironmentNames and writing needs ExpandString, and both are provider
# dynamic parameters that Windows PowerShell 5.1 does not offer on Set-ItemProperty by
# default. The API also fails cleanly off Windows (PlatformNotSupportedException),
# which is what makes the Pester run on a Mac a no-op rather than a crash.
$script:VibeUserEnvKey = 'Environment'
$script:VibeUserEnvPath = 'HKCU\Environment\Path'

# Get-VibeUserEnvKey [-Writable]: the opened key, or $null when there is none.
function Get-VibeUserEnvKey {
  param([switch]$Writable)
  try {
    return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:VibeUserEnvKey, [bool]$Writable)
  } catch {
    return $null
  }
}

# Get-VibeOwnedPathDir: the dirs vibe installs into that nothing else persists.
#
# Exactly two, and deliberately NOT all of Set-VibePath's candidates: %AppData%\npm
# and %ProgramFiles%\nodejs are put on PATH by Node's own MSI, so adding them here
# would author a duplicate of somebody else's entry. Keep this list and the README's
# removal instructions in step.
function Get-VibeOwnedPathDir {
  return @(
    (Join-Path $HOME '.local\bin')
    (Join-Path $HOME '.codex\bin')
  )
}

# Get-VibePathKey <entry>: the form two PATH entries are compared in - trimmed, no
# trailing separator, case-folded, and with %VAR% references expanded.
#
# Expanded for the COMPARISON ONLY. A PATH already carrying %USERPROFILE%\.local\bin
# holds that dir, and appending the literal path beside it is precisely the duplicate
# this file exists not to create; but the entries written back are untouched, because
# expanding somebody else's entry into the value is a change vibe was not asked to
# make.
function Get-VibePathKey {
  param([string]$Entry)
  $e = [Environment]::ExpandEnvironmentVariables($Entry.Trim())
  return ($e.TrimEnd('\', '/')).ToLowerInvariant()
}

# Get-VibePathUpdate -Current <raw PATH> -Dirs <dirs vibe owns>: the pure core.
# Returns @{ Value = <new raw PATH>; Changed = <bool>; Added = @(<dirs>) }.
#
# APPENDED, not prepended, and the reason is worth stating because shellpath.sh
# prepends: on Windows the effective PATH is the Machine value followed by the User
# one, so nothing written here can come before a machine-wide entry anyway. Prepending
# would buy no ordering guarantee and would put vibe ahead of choices the person made
# in their own account PATH.
function Get-VibePathUpdate {
  param([string]$Current, [string[]]$Dirs)

  $entries = @()
  if (-not [string]::IsNullOrWhiteSpace($Current)) {
    foreach ($e in ($Current -split ';')) {
      if ([string]::IsNullOrWhiteSpace($e)) { continue }
      $entries += $e.Trim()
    }
  }

  $have = @{}
  foreach ($e in $entries) { $have[(Get-VibePathKey $e)] = $true }

  $added = @()
  foreach ($d in $Dirs) {
    if ([string]::IsNullOrWhiteSpace($d)) { continue }
    $k = Get-VibePathKey $d
    if ($have.ContainsKey($k)) { continue }
    $have[$k] = $true
    $added += $d
    $entries += $d
  }

  return @{
    Value   = ($entries -join ';')
    Changed = ($added.Count -gt 0)
    Added   = $added
  }
}

# Test-VibeUserEnvironment: is there a per-user registry environment to write?
#
# Windows-only by construction. apply.ps1 guards non-Windows before anything here
# runs, but the Pester suite drives the whole applier with $env:VIBE_OS=win on a Mac,
# where HKCU does not exist - so this is what makes that a no-op rather than a crash.
function Test-VibeUserEnvironment {
  $key = Get-VibeUserEnvKey
  if (-not $key) { return $false }
  $key.Close()
  return $true
}

# Get-VibeUserPathRaw: the User PATH exactly as it is stored.
#
# NOT [Environment]::GetEnvironmentVariable('Path', 'User'): that accessor EXPANDS
# %USERPROFILE%-style entries, so writing its result back bakes today's expansion into
# a PATH vibe did not author - a silent, permanent change to somebody else's entries.
# DoNotExpandEnvironmentNames is how you read the value that was actually written.
function Get-VibeUserPathRaw {
  $key = Get-VibeUserEnvKey
  if (-not $key) { return '' }
  try {
    return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  } catch {
    return ''
  } finally {
    $key.Close()
  }
}

# Send-VibeEnvironmentChange: tell the running desktop that the environment moved.
#
# Without it the registry is correct and a NEW terminal is still wrong: Explorer keeps
# its own copy of the environment and hands it to everything it launches, so the
# user-visible promise - open a terminal, type `claude` - fails until the next sign-in.
# WM_SETTINGCHANGE broadcast with "Environment" is how installers ask for that copy to
# be refreshed.
#
# The honest limit: the CI lane reads the registry value directly, so it passes whether
# or not this broadcast lands. CI proves the value is persisted; proving a new terminal
# SEES it needs a logon session, which no hosted runner gives us.
#
# SendMessageTimeout rather than SendMessage: a single hung top-level window would
# otherwise block the setup indefinitely. Never fatal - the write has already happened,
# and the fallback is the next sign-in.
function Send-VibeEnvironmentChange {
  try {
    if (-not ('VibeSetup.Env' -as [type])) {
      Add-Type -Namespace VibeSetup -Name Env -ErrorAction Stop -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
  System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam,
  uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
    }
    # HWND_BROADCAST 0xffff, WM_SETTINGCHANGE 0x1A, SMTO_ABORTIFHUNG 0x2, 5s timeout
    $res = [System.UIntPtr]::Zero
    $null = [VibeSetup.Env]::SendMessageTimeout(
      [System.IntPtr]0xffff, 0x1A, [System.UIntPtr]::Zero, 'Environment', 0x2, 5000, [ref]$res)
  } catch {
    Info 'If a new terminal cannot find your tools yet, sign out and back in.'
  }
}

# Test-VibePersistedPath: would persisting change anything? $true = already there.
#
# The confirm gate is state-aware for the reason plan.sh's is: promising "adds your
# install dirs to PATH" where nothing will change is a promise the run does not keep.
function Test-VibePersistedPath {
  if (-not (Test-VibeUserEnvironment)) { return $false }
  $upd = Get-VibePathUpdate -Current (Get-VibeUserPathRaw) -Dirs (Get-VibeOwnedPathDir)
  return (-not $upd.Changed)
}

# Set-VibePersistedPath: persist vibe's install dirs on the User PATH, so a new
# terminal finds them. Sets $script:VibePathPersisted to what was written (empty when
# nothing was). Never fatal: a PATH we cannot write warns and the setup continues,
# exactly as persist_path does.
#
# RegistryValueKind.ExpandString, never `setx`: setx TRUNCATES the value at 1024
# characters, which on a machine with a long PATH quietly destroys entries vibe does
# not own. ExpandString because that is what a PATH holding %USERPROFILE% has to be,
# and rewriting the kind would break every reference in it.
function Set-VibePersistedPath {
  $script:VibePathPersisted = ''
  if (-not (Test-VibeUserEnvironment)) { return }

  $upd = Get-VibePathUpdate -Current (Get-VibeUserPathRaw) -Dirs (Get-VibeOwnedPathDir)
  if (-not $upd.Changed) {
    Success 'Your account already knows where vibe installs things'
    return
  }

  $key = Get-VibeUserEnvKey -Writable
  if (-not $key) {
    Warn "couldn't open your account's environment - new terminals may not find your tools"
    return
  }
  try {
    $key.SetValue('Path', $upd.Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
  } catch {
    Warn "couldn't update your account's PATH - new terminals may not find your tools"
    return
  } finally {
    $key.Close()
  }

  $script:VibePathPersisted = $script:VibeUserEnvPath
  Send-VibeEnvironmentChange
  Success ('New terminals will find your tools (added to your PATH: ' + ($upd.Added -join '; ') + ')')
}
