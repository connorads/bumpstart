# gh-auth (interactive tail): offer a GitHub sign-in. Installing gh is
# declarative (CHECK_WIN/INSTALL_WIN in meta, run by the generic runner before
# this tail); what remains here needs a keyboard, so it only runs with a terminal
# and when not already authenticated. The pwsh mirror of gh-auth/apply.sh.
# 5.1-safe.
. (Join-Path $env:BUMP_LIB 'common.ps1')

if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    if (-not [Console]::IsInputRedirected) {
      Write-Host ("`n    {0}Log in to GitHub now? [Y/n]{1} " -f $script:Yellow, $script:Reset) -NoNewline
      $reply = [Console]::ReadLine()
      if ($reply -eq '' -or $reply -match '^[Yy]') {
        gh auth login
        if ($LASTEXITCODE -eq 0) { Success 'GitHub authenticated' }
      } else {
        Info "Skipped - run 'gh auth login' later."
      }
    } else {
      Info "Not a terminal - skipping gh auth. Run 'gh auth login' later."
    }
  }
}
