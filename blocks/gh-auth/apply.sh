#!/usr/bin/env bash
set -euo pipefail
#
# gh-auth (interactive tail): offer a GitHub sign-in. Installing gh is
# declarative now (CHECK_MAC/INSTALL_MAC in meta, run by the generic runner
# before this tail); what remains here is the part that needs a keyboard, so it
# only runs with a terminal and when not already authenticated. Check-then-act.

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
