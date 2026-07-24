# shellcheck shell=bash
# brew.sh: ensure Homebrew is installed and on PATH. Sourced, not executed.
# Depends on info/success from common.sh.

# ensure_brew: install Homebrew if absent, then put it on PATH for this run
# (Apple Silicon or Intel prefix). If brew is already on PATH we leave PATH
# alone — re-running shellenv would re-prepend the brew prefix and could shadow
# earlier PATH entries.
ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    success "Homebrew already installed"
    return 0
  fi

  # The Apple-Silicon / Intel brew prefixes, overridable so the install branch is
  # reachable in tests without a real uninstall (defaults are the real paths).
  _eb_opt="${VIBE_BREW_OPT:-/opt/homebrew/bin/brew}"
  _eb_usr="${VIBE_BREW_USR:-/usr/local/bin/brew}"

  if [ -x "$_eb_opt" ] || [ -x "$_eb_usr" ]; then
    success "Homebrew already installed"
  else
    info "Installing Homebrew (may prompt for your password + Xcode CLT)..."
    # Narrate the blank, non-echoing sudo prompt before it fires — to a
    # first-timer it reads as "broken" otherwise. This is the canonical copy for
    # the password moment (the confirm gate only foreshadows it).
    info "macOS wants the password you use to log in to this Mac. Nothing appears as you type - that is normal. Press Return when you're done."
    [ -t 0 ] && sudo -v
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Brew is installed but not yet on this shell's PATH — add it.
  if [ -x "$_eb_opt" ]; then
    eval "$("$_eb_opt" shellenv)"
  elif [ -x "$_eb_usr" ]; then
    eval "$("$_eb_usr" shellenv)"
  fi
}
