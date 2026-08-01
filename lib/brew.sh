# shellcheck shell=bash
# brew.sh: ensure Homebrew is installed and on PATH. Sourced, not executed.
# Depends on info/success from common.sh.

# ensure_brew: install Homebrew if absent, then put it on PATH for this run
# (Apple Silicon or Intel prefix). If brew is already on PATH we leave PATH
# alone — re-running shellenv would re-prepend the brew prefix and could shadow
# earlier PATH entries.
#
# Non-fatal on failure, and it ALWAYS returns 0: it is the mac substrate, called
# bare under the applier's set -e, and the same warn-and-record policy every
# block step lives under has to cover it too. Mirrors ensure_mise (lib/mise.sh),
# the Linux half of the same slot.
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
    # Split out of an AND-list rather than `[ -t 0 ] && sudo -v`. `set -e` ignores
    # a failing LEFT operand, so a non-tty run always survived that line — but a
    # wrong password with a tty present is a failing RIGHT operand, which ended
    # the whole setup wordlessly. Warn and let the installer ask again itself.
    if [ -t 0 ] && ! sudo -v; then
      warn "couldn't confirm your password — Homebrew will ask again if it needs to"
    fi
    # Fetch first, run second. `bash -c "$(curl ...)"` hands bash an EMPTY script
    # when the download fails (offline, a 404, a proxy's empty 200), and bash
    # exits 0 — so the run reported an install that never happened. The whole
    # chain sits in an `if` condition, which set -e exempts. Still `bash -c
    # "$script"` and not a pipe, so the installer's own sudo/CLT prompts keep stdin.
    if _eb_script="$(vibe_fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" &&
       [ -n "$_eb_script" ] &&
       NONINTERACTIVE=1 /bin/bash -c "$_eb_script"; then
      success "Homebrew installed"
    else
      warn "couldn't install Homebrew — the tools that need it may be skipped"
      record_warning "Homebrew"
      return 0
    fi
  fi

  # Brew is installed but not yet on this shell's PATH — add it.
  if [ -x "$_eb_opt" ]; then
    eval "$("$_eb_opt" shellenv)"
  elif [ -x "$_eb_usr" ]; then
    eval "$("$_eb_usr" shellenv)"
  fi
}
