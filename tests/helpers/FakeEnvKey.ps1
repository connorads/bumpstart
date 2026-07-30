# FakeEnvKey.ps1: a stand-in for the opened HKCU\Environment registry key, for the
# Pester suite. Dot-sourced, not executed, and named so `Invoke-Pester tests` (which
# discovers *.Tests.ps1) never runs it as a suite.
#
# Why it exists: lib/shellpath.ps1's effect half writes the account PATH of whoever is
# running, and the suite runs on Windows too (the `check-windows` job) - so an
# unfaked write aims a test's $TestDrive paths at a real person's environment.
# Get-VibeUserEnvKey is the single door to the registry, so a test that mocks it holds
# the whole effect half at arm's length while still running every line of it.
#
# Shared by ShellPath.Tests.ps1 (the effect half directly) and Apply.Tests.ps1 (the
# applier's persist step), because a double this load-bearing should not exist twice.

# New-FakeEnvState [-Value <raw PATH>] [-Writable <bool>]: the readable/assertable half.
# Kind records the RegistryValueKind the code wrote with - ExpandString or nothing is a
# real distinction, since rewriting the kind breaks every %VAR% already in the value.
function New-FakeEnvState {
  param(
    [string]$Value = '',
    [bool]$Writable = $true
  )
  return [pscustomobject]@{
    Value    = $Value
    Kind     = $null
    Writes   = 0
    Closed   = 0
    Writable = $Writable
  }
}

# New-FakeEnvKey <state>: the object Get-VibeUserEnvKey is mocked to return. Implements
# exactly the three members shellpath.ps1 uses, so a fourth one appearing there fails
# loudly here rather than being quietly faked.
function New-FakeEnvKey {
  param([Parameter(Mandatory = $true)]$State)

  $key = New-Object psobject
  $key | Add-Member -MemberType NoteProperty -Name State -Value $State
  # The value-options argument is accepted and ignored: DoNotExpandEnvironmentNames is
  # what the real read passes, and this double is raw storage, so it cannot expand.
  $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
    param($name, $default, $options)
    if ($null -eq $this.State.Value) { return $default }
    return $this.State.Value
  }
  $key | Add-Member -MemberType ScriptMethod -Name SetValue -Value {
    param($name, $value, $kind)
    # A key opened writable that still refuses the write - the "your PATH is managed"
    # case, which must warn rather than end the setup.
    if (-not $this.State.Writable) { throw 'the fake key refuses writes' }
    $this.State.Value = $value
    $this.State.Kind = $kind
    $this.State.Writes++
  }
  $key | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.State.Closed++ }
  return $key
}
