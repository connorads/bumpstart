# PSScriptAnalyzer settings — the pwsh lint gate (lint-ps). Enforces the Windows
# PowerShell 5.1 floor: every product lib/*.ps1 (and later the entry *.ps1) must
# run under the default shell on a fresh Windows, powershell.exe 5.1, NOT pwsh 7.
#
# The floor is mechanical, not reviewer memory:
#   - PSUseCompatibleSyntax flags 7-only syntax (ternary ?:, ??, && / ||, etc.)
#     against both 5.1 and 7.
#   - PSUseCompatibleCommands / PSUseCompatibleTypes flag cmdlets/params/.NET
#     types absent from the bundled Windows-PowerShell-5.1 profile.
# The $IsWindows/$IsMacOS/$IsLinux automatics are NOT covered by these rules (they
# are variables, not commands) — a sibling grep in lint-ps enforces that they
# appear only in lib/os.ps1.
#
# Only the 5.1 profile is targeted for Commands/Types: 5.1 is the true floor, and
# PSUseCompatibleSyntax already covers the 7-vs-5.1 syntax both ways. Adding the
# old bundled 6.1 core profile would flag genuine pwsh-7 cmdlets as absent.

@{
  Severity = @('Error', 'Warning')

  # Write-Host is the intended UI channel; Invoke-Expression is the runner's
  # design (evaluating per-OS command cells, the eval analogue). PSUseSingularNouns
  # misfires on Get-VibeOs ("Os" is an abbreviation, not a plural). All safe here,
  # so their advisory rules would be noise.
  ExcludeRules = @(
    'PSAvoidUsingWriteHost',
    'PSAvoidUsingInvokeExpression',
    'PSUseSingularNouns'
  )

  Rules = @{
    PSUseCompatibleSyntax = @{
      Enable         = $true
      TargetVersions = @('5.1', '7.0')
    }
    # The bundled Windows-PowerShell-5.1 profile (build 14393). Reference it by its
    # full compatibility_profiles filename base; the short Settings/ alias
    # (desktop-5.1.*) does not resolve in PSScriptAnalyzer 1.25.
    PSUseCompatibleCommands = @{
      Enable         = $true
      TargetProfiles = @('win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework')
    }
    PSUseCompatibleTypes = @{
      Enable         = $true
      TargetProfiles = @('win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework')
    }
  }
}
