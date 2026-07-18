# shellcheck shell=bash
# brew.sh: ensure Homebrew is installed and on PATH. Sourced, not executed.
# Depends on info/success from common.sh.

# ensure_brew: install Homebrew if absent, then put it on PATH for this run
# (Apple Silicon or Intel prefix).
ensure_brew() {
  if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
    info "Installing Homebrew (may prompt for your password + Xcode CLT)..."
    [ -t 0 ] && sudo -v
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    success "Homebrew already installed"
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}
