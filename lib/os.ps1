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
  # Test seam: an explicit override wins (parity with os.sh's $VIBE_OS). Required
  # here - it's how the mac-hosted Windows e2e forces the win token set.
  if ($env:VIBE_OS) { return $env:VIBE_OS }
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
