# git (interactive tail): give git an identity so a beginner's first commit is
# authored, not rejected for a missing name/email. Installing git is declarative
# (CHECK_WIN/INSTALL_WIN in meta); this is the identity logic.
#
# git needs a name and an email and nothing else, so this block requires no account
# anywhere. It reads the identity off a GitHub sign-in when one happens to be there
# - the noreply address keeps a real one off public commits - and otherwise asks.
# We only SET config that is unset - never clobber an existing identity. Non-fatal
# throughout. The pwsh mirror of git/apply.sh. 5.1-safe.
. (Join-Path $env:BUMP_LIB 'common.ps1')

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Warn 'git is not available - skipping identity setup.'
  return
}

# Is there a person here to answer? Both halves matter. -Yes reaches us as
# BUMP_YES (Invoke-BlockTail passes it), and a run told not to ask must not then
# stop for a question; a redirected stdin says the same from the other direction.
$canAsk = (-not $env:BUMP_YES) -and (-not [Console]::IsInputRedirected)

# Read once into a variable, rather than `if (git ... 2>$null)` with a second
# identical call in the message. A redirection inside an `if` condition also
# reads to PSScriptAnalyzer as a mistyped comparison operator, so hoisting it
# is what lets this file join the 5.1 lint floor.
$haveName = (git config --global --get user.name 2>$null)

# Where the name and email come from. Two sources, neither a dependency: `github`
# is not in every plan, and a machine with no keyboard is not one to invent an
# identity on. Declared empty up front because the writer below is single.
$name = ''
$email = ''

$signedIn = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh auth status 2>$null | Out-Null
  $signedIn = ($LASTEXITCODE -eq 0)
}

if ($signedIn) {
  $login = (gh api user --jq .login 2>$null)
  $id = (gh api user --jq .id 2>$null)
  $name = (gh api user --jq '.name // ""' 2>$null)

  if ($id -and $login) { $email = "$id+$login@users.noreply.github.com" }

  # A blank GitHub profile name: ask when we can, else fall back to the login so
  # commits are still attributed to someone. Not asked when git already has a name.
  if (-not $name) {
    if ($canAsk -and (-not $haveName)) {
      Write-Host "`n    What name should show on your commits? (First Last) " -NoNewline
      $name = [Console]::ReadLine()
    }
    if (-not $name) { $name = $login }
  }
} elseif (-not $haveName) {
  # No GitHub here, so ask - when there is someone to ask. Otherwise set nothing
  # and say so: an unset identity is honest, where a fabricated one ends up in
  # commit metadata forever, and git's own error at the first commit names the
  # exact command that fixes it.
  if ($canAsk) {
    Write-Host "`n    What name should show on your commits? (First Last) " -NoNewline
    $name = [Console]::ReadLine()
    Write-Host '    What email should show on your commits? ' -NoNewline
    $email = [Console]::ReadLine()
  } else {
    Info 'Nobody here to ask, so git has no name yet - set one with: git config --global user.name "Your Name"'
    Info '...and an email with: git config --global user.email you@example.com'
  }
}

# Set the GLOBAL identity, backing off from anything already set. One writer for
# both sources above, so "only ever set what is unset" is stated once.
if ($name) {
  if ($haveName) {
    Success "git already knows you as $haveName"
  } else {
    git config --global user.name $name
    if ($LASTEXITCODE -eq 0) { Success "Set your git name to $name" }
    else { Warn "couldn't set your git name - continuing" }
  }
}
if ($email) {
  $haveEmail = (git config --global --get user.email 2>$null)
  if ($haveEmail) {
    Success "git already uses $haveEmail for you"
  } else {
    git config --global user.email $email
    if ($LASTEXITCODE -eq 0) { Success "Set your git email to $email" }
    else { Warn "couldn't set your git email - continuing" }
  }
}

$haveBranch = (git config --global --get init.defaultBranch 2>$null)
if (-not $haveBranch) {
  git config --global init.defaultBranch main
  if ($LASTEXITCODE -eq 0) {
    Success "New git projects will start on 'main'"
  } else {
    Warn "couldn't set the default branch - continuing"
  }
}
