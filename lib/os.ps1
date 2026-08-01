# os.ps1: current-OS detection, the pwsh mirror of lib/os.sh. The {mac,win,linux}
# token set (uppercased to MAC|WIN|LINUX cell suffixes) is the cross-spine
# CONTRACT, so a block's per-OS command cell is keyed the same on both spines.
# Dot-sourced, not executed.
#
# Windows PowerShell 5.1-safe: 5.1 leaves the $IsWindows/$IsMacOS/$IsLinux
# automatics unset ($null), so detection leads with $PSVersionTable.PSEdition
# (Desktop => Windows PowerShell => win) before touching those automatics. This is
# the ONLY file allowed to reference them (the lint-ps grep enforces that).

function Get-VibeOs {
  # Test seam: an explicit override wins (parity with os.sh's $BUMP_OS). Required
  # here - it's how the mac-hosted Windows e2e forces the win token set.
  if ($env:BUMP_OS) { return $env:BUMP_OS }
  # Windows PowerShell 5.1 is the Desktop edition and is Windows-only.
  if ($PSVersionTable.PSEdition -eq 'Desktop') { return 'win' }
  # pwsh 6+ (Core edition): the OS automatics are defined and reliable.
  if ($IsWindows) { return 'win' }
  if ($IsMacOS)   { return 'mac' }
  if ($IsLinux)   { return 'linux' }
  return 'linux'
}

function Get-VibeOsKey {
  switch (Get-VibeOs) {
    'mac'   { 'MAC' }
    'win'   { 'WIN' }
    'linux' { 'LINUX' }
    default { 'LINUX' }
  }
}

# Test-BlockHasContent <blockDir> - $true when this block stacks a section into the
# canonical instructions file on the current OS: a per-OS content.<os>.md, else the
# neutral content.md. The one answer to "does this block carry guidance", shared by
# the resolver, the catalogue and the plan. Mirrors block_has_content in os.sh.
#
# Lives here, not in run.ps1, because it takes a block DIR and needs only
# Get-VibeOs: Contract.Tests.ps1 dot-sources os + meta + resolve alone.
function Test-BlockHasContent {
  param([string]$BlockDir)
  if (Test-Path -LiteralPath (Join-Path $BlockDir ("content." + (Get-VibeOs) + '.md'))) { return $true }
  return (Test-Path -LiteralPath (Join-Path $BlockDir 'content.md'))
}
