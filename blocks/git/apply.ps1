# git (interactive tail): give git an identity so a beginner's first commit is
# authored, not rejected for a missing name/email. Installing git is declarative
# (CHECK_WIN/INSTALL_WIN in meta); this is the identity logic. Identity comes from
# the GitHub account (gh is pulled in via INCLUDE and signs in first); the noreply
# email keeps the real address private. We only SET config that is unset - never
# clobber an existing identity. Non-fatal throughout. The pwsh mirror of
# git/apply.sh. 5.1-safe.
. (Join-Path $env:VIBE_LIB 'common.ps1')

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Warn 'git is not available - skipping identity setup.'
  return
}

$signedIn = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh auth status 2>$null | Out-Null
  $signedIn = ($LASTEXITCODE -eq 0)
}

if ($signedIn) {
  $login = (gh api user --jq .login 2>$null)
  $id = (gh api user --jq .id 2>$null)
  $name = (gh api user --jq '.name // ""' 2>$null)

  $email = ''
  if ($id -and $login) { $email = "$id+$login@users.noreply.github.com" }

  if (-not $name) {
    if (-not [Console]::IsInputRedirected) {
      Write-Host "`n    What name should show on your commits? (First Last) " -NoNewline
      $name = [Console]::ReadLine()
    }
    if (-not $name) { $name = $login }
  }

  if ($name) {
    if (git config --global --get user.name 2>$null) {
      Success "git already knows you as $(git config --global --get user.name)"
    } else {
      git config --global user.name $name
      if ($LASTEXITCODE -eq 0) { Success "Set your git name to $name" }
      else { Warn "couldn't set your git name - continuing" }
    }
  }
  if ($email) {
    if (git config --global --get user.email 2>$null) {
      Success "git already uses $(git config --global --get user.email) for you"
    } else {
      git config --global user.email $email
      if ($LASTEXITCODE -eq 0) { Success "Set your git email to $email" }
      else { Warn "couldn't set your git email - continuing" }
    }
  }
} else {
  Info 'Not signed into GitHub yet - sign in (gh auth login), then re-run to set your git name/email.'
}

if (-not (git config --global --get init.defaultBranch 2>$null)) {
  git config --global init.defaultBranch main
  if ($LASTEXITCODE -eq 0) {
    Success "New git projects will start on 'main'"
  } else {
    Warn "couldn't set the default branch - continuing"
  }
}
