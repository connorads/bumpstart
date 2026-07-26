#!/usr/bin/env bash
set -euo pipefail
#
# git (interactive tail): give git an identity, so a beginner's first commit is
# authored rather than rejected for a missing name/email. Installing git is
# declarative now (CHECK_MAC/INSTALL_MAC in meta, run by the generic runner
# before this tail); what remains here is the identity logic. The identity comes
# from their GitHub account (gh is pulled in via INCLUDE, and is an `auth` kind
# so it signs in before this `tool` step runs); the noreply email keeps their
# real address private on pushes. We only ever SET config that is unset — never
# clobber an identity the user already has. Non-fatal throughout: a missing
# GitHub sign-in prints a hint and skips, never aborting the setup.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"

# If the runner's install cell couldn't provide git (genuinely absent, e.g. a
# failed Homebrew install), there is no identity to set — skip, non-fatal.
if ! command -v git >/dev/null 2>&1; then
  warn "git is not available — skipping identity setup."
  exit 0
fi

# 2. Derive identity from GitHub — only when signed in. Separate --jq calls keep
#    each value's source explicit (and easy to fake in tests). Never fatal.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  login="$(gh api user --jq .login 2>/dev/null || true)"
  id="$(gh api user --jq .id 2>/dev/null || true)"
  name="$(gh api user --jq '.name // ""' 2>/dev/null || true)"

  email=""
  [ -n "$id" ] && [ -n "$login" ] && email="${id}+${login}@users.noreply.github.com"

  # A blank GitHub profile name: ask when we have a keyboard, else fall back to
  # the GitHub username so commits are still attributed to someone.
  if [ -z "$name" ]; then
    if [ -t 0 ]; then
      printf "\n    What name should show on your commits? (First Last) "
      read -r name || name=""
    fi
    [ -z "$name" ] && name="$login"
  fi

  # 3. Set GLOBAL identity, backing off from anything already set.
  if [ -n "$name" ]; then
    if git config --global --get user.name >/dev/null 2>&1; then
      success "git already knows you as $(git config --global --get user.name)"
    elif git config --global user.name "$name"; then
      success "Set your git name to $name"
    else
      warn "couldn't set your git name — continuing"
    fi
  fi
  if [ -n "$email" ]; then
    if git config --global --get user.email >/dev/null 2>&1; then
      success "git already uses $(git config --global --get user.email) for you"
    elif git config --global user.email "$email"; then
      success "Set your git email to $email"
    else
      warn "couldn't set your git email — continuing"
    fi
  fi
else
  info "Not signed into GitHub yet — sign in (gh auth login), then re-run to set your git name/email."
fi

# New repos should start on 'main' unless the user already chose otherwise.
if ! git config --global --get init.defaultBranch >/dev/null 2>&1; then
  if git config --global init.defaultBranch main; then
    success "New git projects will start on 'main'"
  else
    warn "couldn't set the default branch — continuing"
  fi
fi
