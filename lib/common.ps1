# common.ps1: colour/UI helpers, the pwsh mirror of common.sh. Dot-sourced, no
# side effects beyond defining vars/functions. 5.1-safe: ANSI via [char]0x1b (the
# `e escape is pwsh-7-only), no OS automatics, 5.1-safe cmdlets only.
#
# Colours off when $env:NO_COLOR is set or stdout is redirected (pipes/CI/tests).
# $script:UiFancy gates the animated/cursor bits on top of colour so redirected
# output stays plain and deterministic.

$script:UiFancy = $false
if ($env:NO_COLOR -or [Console]::IsOutputRedirected) {
  $script:Green = ''; $script:Blue = ''; $script:Red = ''; $script:Yellow = ''
  $script:Dim = ''; $script:Bold = ''; $script:Reset = ''
  $script:Cyan = ''; $script:Magenta = ''
} else {
  $e = [char]0x1b
  $script:Green = "$e[32m"; $script:Blue = "$e[34m"; $script:Red = "$e[31m"
  $script:Yellow = "$e[33m"; $script:Dim = "$e[2m"; $script:Bold = "$e[1m"
  $script:Reset = "$e[0m"; $script:Cyan = "$e[36m"; $script:Magenta = "$e[35m"
  $script:UiFancy = $true
}

# One glyph, a two-space gutter, consistent spacing. All UI goes to Write-Host
# (the Information stream) so tests can capture it with 6>&1 and a redirected
# console still shows it.
function Info    { param([string]$Msg) Write-Host "  $($script:Blue)$([char]0x203A)$($script:Reset) $Msg" }
function Success { param([string]$Msg) Write-Host "  $($script:Green)$([char]0x2713)$($script:Reset) $Msg" }
function Warn    { param([string]$Msg) Write-Host "  $($script:Yellow)!$($script:Reset) $Msg" }
function Err     { param([string]$Msg) Write-Host "  $($script:Red)$([char]0x2717)$($script:Reset) $Msg" }

# Warning ledger, the mirror of common.sh's. Every non-fatal step failure records
# the thing that failed, so the finish message can name it instead of printing a
# green 'Setup complete.' over a machine where an install warned 40 lines ago and
# scrolled away. Separate from Warn itself: not every warning is a failed step (a
# deliberate back-off is a warning too), and only failures change the verdict.
$script:BumpWarnCount = 0
$script:BumpWarnItems = @()

# Add-BumpWarning <label>: count one failed step and remember its human label, once.
# Deduped by label, mirroring record_warning: a tool can be attempted twice in one
# run by design, and the same name listed twice reads as a bug in bumpstart rather than as
# one thing that didn't work.
function Add-BumpWarning {
  param([string]$Label)
  if ($script:BumpWarnItems -contains $Label) { return }
  $script:BumpWarnCount++
  $script:BumpWarnItems += $Label
}

# Step <n> <total> <label>: a numbered progress header before each install block.
function Step {
  param([int]$Num, [int]$Total, [string]$Label)
  Write-Host ""
  Write-Host "  $($script:Bold)$($script:Cyan)[$Num/$Total]$($script:Reset) $Label"
}

# Hrule: a dim decorative rule. Fancy-only - a no-op in plain/piped/test output.
function Hrule {
  if (-not $script:UiFancy) { return }
  Write-Host "  $($script:Dim)$([char]0x2500 * 40)$($script:Reset)"
}

# Invoke-Spin <label> <scriptblock>: run a block while showing (in fancy mode) a
# calm working indicator. Returns ONE boolean - $true on success, $false when the
# block throws or leaves a non-zero native exit code. Non-fatal by contract:
# callers warn-and-continue on $false.
#
# The block's output goes to Write-Host, the Information stream this module
# declares for all UI, and NOT back on the success stream: left there it rides
# out alongside the flag, so `$ok = Invoke-Spin ...` binds an ARRAY - and every
# multi-element array is truthy, so a failed install that printed first read as a
# success. Every real WIN cell prints (winget, irm|iex, npm), so that was the
# normal case. Write-Host rather than Out-Null because the vendor's error text is
# the only clue the user gets, and rather than Out-Host because the latter is
# invisible to 6>&1 - which would make this contract untestable.
#
# Fancy mode diverges from common.sh's spin, deliberately: bash captures the
# output and reveals it only on failure, which needs a background job. The 5.1
# floor has no Start-ThreadJob, and Start-Job's separate runspace cannot see this
# dot-sourced spine, so here the label sits on its own line and the block's
# output streams below it.
function Invoke-Spin {
  param([string]$Label, [scriptblock]$Script)
  if ($script:UiFancy) {
    Write-Host "  $($script:Cyan)*$($script:Reset) $Label"
  }
  $global:LASTEXITCODE = 0
  $ok = $true
  $encoding = [Console]::OutputEncoding
  try {
    # Native installers emit UTF-8; PowerShell decodes their captured output
    # using Console.OutputEncoding, which may still be an OEM code page in 5.1.
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    & $Script | Write-Host
    if ($LASTEXITCODE -ne 0) { $ok = $false }
  } catch {
    # The vendor's own message is the only thing that says WHY; the caller's
    # "Couldn't install X" alone leaves nothing to act on.
    Warn $_.Exception.Message
    $ok = $false
  } finally {
    [Console]::OutputEncoding = $encoding
  }
  return $ok
}

# Wait-Enter <prompt>: pause until Enter, so an on-screen message can be read. A
# no-op when input is redirected (headless/piped runs never block).
function Wait-Enter {
  param([string]$Prompt)
  if ([Console]::IsInputRedirected) { return }
  Write-Host ""
  Write-Host "  $($script:Cyan)$([char]0x23CE)$($script:Reset) $Prompt " -NoNewline
  [void][Console]::ReadLine()
}

# Registry values include paths added by winget's installers after this process
# started. Reading them never replaces the caller's process-only PATH entries.
function Get-BumpRegistryPath {
  [Environment]::GetEnvironmentVariable('Path', 'Machine')
  [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Test-BumpCommand {
  param([string]$Name)
  $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command) { return $false }
  $global:LASTEXITCODE = 0
  try {
    & $command --version *> $null
    return ($? -and $LASTEXITCODE -eq 0)
  } catch { return $false }
}

# Set-BumpPath: freshly-installed CLIs land in per-user dirs the current shell may
# not have on PATH yet - prepend the Windows ones so the launch step and any
# later cell sees them without a re-login. The mirror of common.sh's fixup_path.
# Existing owned dirs are prepended; registry entries are appended even before
# their directory exists, so the agent installer sees its announced destination.
#   Claude Code + Codex per-user installers -> %USERPROFILE%\.local\bin
#   npm-global (pnpm + npm-installed Codex)  -> %AppData%\npm
#   Node.js (winget machine MSI)             -> %ProgramFiles%\nodejs
function Set-BumpPath {
  $candidates = @(
    (Join-Path $HOME '.local\bin')
    (Join-Path $HOME '.codex\bin')
  )
  if ($env:APPDATA)      { $candidates += (Join-Path $env:APPDATA 'npm') }
  if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'nodejs') }

  $sep = [System.IO.Path]::PathSeparator
  $entries = @($env:PATH -split [regex]::Escape($sep) | Where-Object { $_ })
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $entries) { [void]$seen.Add($entry.TrimEnd('\', '/')) }
  foreach ($dir in $candidates) {
    if ((Test-Path -LiteralPath $dir) -and $seen.Add($dir.TrimEnd('\', '/'))) {
      $entries = @($dir) + $entries
    }
  }
  foreach ($value in (Get-BumpRegistryPath)) {
    foreach ($entry in ($value -split ';')) {
      $dir = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
      if ($dir -and $seen.Add($dir.TrimEnd('\', '/'))) { $entries += $dir }
    }
  }
  $env:PATH = $entries -join $sep
}

# Expand-BumpHome <path>: expand a leading $HOME or ~ in a meta path literal (e.g.
# TARGET_WIN='$HOME/.claude/CLAUDE.md') to the automatic $HOME (= %USERPROFILE% on
# Windows, defined in both 5.1 and pwsh 7). Bash source-expands its own paths; the
# pwsh line-reader returns them literal, so this is where they resolve.
function Expand-BumpHome {
  param([string]$Path)
  if ($Path -like '$HOME*') { return (Join-Path $HOME ($Path.Substring(5).TrimStart('/', '\'))) }
  if ($Path -like '~*')     { return (Join-Path $HOME ($Path.Substring(1).TrimStart('/', '\'))) }
  return $Path
}

# Copy-ToClipboard <text>: put text on the clipboard, returning $true on success.
# Uses Set-Clipboard (present in Windows PowerShell 5.1 and pwsh 7). Returns
# $false when the cmdlet is unavailable or fails, so callers can fall back to
# printing the text for a manual copy. Never throws.
function Copy-ToClipboard {
  param([string]$Text)
  if (-not (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) { return $false }
  try {
    Set-Clipboard -Value $Text -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}
