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

  if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    success "Homebrew already installed"
  else
    info "Installing Homebrew (may prompt for your password + Xcode CLT)..."
    [ -t 0 ] && sudo -v
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Brew is installed but not yet on this shell's PATH — add it.
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}
