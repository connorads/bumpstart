#!/usr/bin/env bash
set -euo pipefail
#
# github (interactive tail): offer a GitHub sign-in. Installing gh is
# declarative now (CHECK_MAC/INSTALL_MAC in meta, run by the generic runner
# before this tail); what remains here is the part that needs a keyboard, so it
# only runs with a terminal and when not already authenticated. Check-then-act.
#
# The block declares INCLUDE="git", not the other way round: choosing GitHub means
# choosing git, while choosing git means nothing about GitHub. This is an `auth`
# block and git is a `tool` one, so the sign-in below lands before git's identity
# step reads it. ADR 0007.

# shellcheck source=lib/common.sh
. "$BUMP_LIB/common.sh"

if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
  if [ -t 0 ]; then
    printf "\n    Log in to GitHub now? %s[Y/n]%s " "$YELLOW" "$RESET"
    read -r reply
    case "$reply" in
      ""|[Yy]*) gh auth login && success "GitHub authenticated" ;;
      *) info "Skipped — run 'gh auth login' later." ;;
    esac
  else
    info "Not a terminal — skipping gh auth. Run 'gh auth login' later."
  fi
fi
