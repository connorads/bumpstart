#!/usr/bin/env bash
set -euo pipefail
#
# git (interactive tail): give git an identity, so a beginner's first commit is
# authored rather than rejected for a missing name/email. Installing git is
# declarative now (CHECK_MAC/INSTALL_MAC in meta, run by the generic runner
# before this tail); what remains here is the identity logic.
#
# git needs a name and an email and nothing else, so this block requires no
# account anywhere. It reads the identity off a GitHub sign-in when one happens
# to be there, and otherwise asks. We only ever SET config that is unset — never
# clobber an identity the user already has. Non-fatal throughout: nothing here
# can abort the setup.

# shellcheck source=lib/common.sh
. "$BUMP_LIB/common.sh"
# shellcheck source=lib/os.sh
. "$BUMP_LIB/os.sh"

# ── 1. Linux only: install git itself ─────────────────────────────────────────
#
# git is the ONE tool with no portable user-space install: no vendor one-liner, and
# mise's git is a source build. So it is the single exception to "a portable command
# is a cell" — and because it needs the system package manager, and therefore a
# sudo password prompt, it cannot live in a cell at all: run_cell executes cells
# through spin, which backgrounds the command and rewrites the terminal line every
# 0.1s, erasing a password prompt as it is typed. run_block runs this script
# directly, so this is the only place privileged work is correct.
#
# Ubuntu Desktop 24.04 and 26.04 ship no git at all, so this is not a rare path.
#
# The manager is found by CAPABILITY, never by reading a distro name: probing for
# the command makes Mint, Pop!_OS, openSUSE and every other derivative work for
# free, where an /etc/os-release table would need a row each.
if [ "$(bump_os)" = linux ] && ! command -v git >/dev/null 2>&1; then
  # sudo only when we are not already root (containers, Codespaces) and it exists.
  gsudo=""
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      gsudo="sudo"
    else
      warn "git is missing and there is no sudo here — install git yourself, then re-run."
      exit 0
    fi
  fi

  install_git=""
  if command -v apt-get >/dev/null 2>&1; then
    install_git="$gsudo apt-get update -qq && $gsudo apt-get install -y -qq git"
  elif command -v dnf >/dev/null 2>&1; then
    install_git="$gsudo dnf install -y -q git"
  elif command -v pacman >/dev/null 2>&1; then
    install_git="$gsudo pacman -Sy --noconfirm --needed git"
  elif command -v zypper >/dev/null 2>&1; then
    install_git="$gsudo zypper --non-interactive install -y git"
  fi

  if [ -z "$install_git" ]; then
    warn "couldn't find a package manager to install git — install it yourself, then re-run."
  else
    info "Installing git (your system will ask for your password)..."
    # Narrate the blank, non-echoing sudo prompt BEFORE it fires — to a first-timer
    # it reads as "broken" otherwise. Same copy and same reason as lib/brew.sh.
    if [ -n "$gsudo" ]; then
      info "Your computer wants the password you use to log in. Nothing appears as you type - that is normal. Press Return when you're done."
      [ -t 0 ] && sudo -v
    fi
    # NOT through spin: it would erase the password prompt while it is being typed.
    if eval "$install_git"; then
      success "git installed"
    else
      warn "couldn't install git — continuing without it."
    fi
  fi
fi

# ── 2. Identity ───────────────────────────────────────────────────────────────

# If git is still absent (a failed install, a manager we don't know), there is no
# identity to set — skip, non-fatal.
if ! command -v git >/dev/null 2>&1; then
  warn "git is not available — skipping identity setup."
  exit 0
fi

# can_ask — is there a person here to answer? Both halves matter. `--yes` reaches
# us as BUMP_YES (run_block passes it), and a run that was told not to ask must not
# then stop for a question; a redirected stdin means the same thing from the other
# direction.
can_ask() { [ -t 0 ] && [ -z "${BUMP_YES:-}" ]; }

# 2a. Where the name and email come from. Two sources, neither of them a
# dependency — `github` is not in every plan, and a machine with no keyboard is
# not a machine to invent an identity on.
#
# A GitHub sign-in wins when it is there, for the ADDRESS more than the name:
# {id}+{login}@users.noreply.github.com is what keeps a real address off every
# public commit, and someone who types their own publishes it on their first push.
# `github` is an `auth` block and this is a `tool` block, so its sign-in has
# already happened by the time this runs. Separate --jq calls keep each value's
# source explicit (and easy to fake in tests). Never fatal.
#
# Declared empty up front because 2b below is the single writer: a branch that
# finds nothing to offer leaves both blank and 2b does nothing.
name=""
email=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  login="$(gh api user --jq .login 2>/dev/null || true)"
  id="$(gh api user --jq .id 2>/dev/null || true)"
  name="$(gh api user --jq '.name // ""' 2>/dev/null || true)"

  [ -n "$id" ] && [ -n "$login" ] && email="${id}+${login}@users.noreply.github.com"

  # A blank GitHub profile name: ask when we can, else fall back to the GitHub
  # username so commits are still attributed to someone. Not asked at all when git
  # already has a name — 2b would only report it back.
  if [ -z "$name" ]; then
    if can_ask && ! git config --global --get user.name >/dev/null 2>&1; then
      printf "\n    What name should show on your commits? (First Last) "
      read -r name || name=""
    fi
    [ -z "$name" ] && name="$login"
  fi

# No GitHub here, so ask — but only when git has no name yet, and only when there
# is someone to ask. Otherwise set nothing and say so: an unset identity is
# honest, where a fabricated one ends up in commit metadata forever. git's own
# error at the first commit names the exact command that fixes it, and the agent
# can walk them through it.
elif ! git config --global --get user.name >/dev/null 2>&1; then
  if can_ask; then
    printf "\n    What name should show on your commits? (First Last) "
    read -r name || name=""
    printf "    What email should show on your commits? "
    read -r email || email=""
  else
    info "Nobody here to ask, so git has no name yet — set one with: git config --global user.name \"Your Name\""
    info "...and an email with: git config --global user.email you@example.com"
  fi
fi

# 2b. Set GLOBAL identity, backing off from anything already set. One writer for
# both sources above, so "only ever set what is unset" is stated once.
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

# New repos should start on 'main' unless the user already chose otherwise.
if ! git config --global --get init.defaultBranch >/dev/null 2>&1; then
  if git config --global init.defaultBranch main; then
    success "New git projects will start on 'main'"
  else
    warn "couldn't set the default branch — continuing"
  fi
fi
