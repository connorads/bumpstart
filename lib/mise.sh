# shellcheck shell=bash
# mise.sh: ensure mise is installed and on PATH. The Linux mirror of brew.sh, and
# the same pre-loop slot in the applier. Sourced, not executed.
#
# Why a pre-loop step and not just the `mise` block's own cell: block steps run in
# KIND rank order, and `auth` (20) runs before `tool` (30) — deliberately, so gh
# signs in before the git block reads the identity from it. That puts gh-auth ahead
# of the mise block, so a gh-auth cell that installs gh *via mise* would run before
# mise existed, fail, warn, and leave gh missing for the rest of the run. Making
# mise unconditional and early is what lets a rank-20 step use it. The alternative,
# INCLUDE="mise" on gh-auth, is wrong: INCLUDE is OS-invariant, so it would pull
# mise into every macOS plan too.
#
# The `mise` block keeps its own Linux cells regardless, so when node/pnpm pull it
# in the plan row still renders and its content.md still merges — it simply reports
# "already installed". That mirrors macOS exactly, where ensure_brew runs pre-loop
# and `brew install mise` is also a block cell.
#
# No sudo anywhere: mise.run installs a single user-owned binary into ~/.local/bin.
# Depends on common.sh (info/success/warn, vibe_fetch). bash-3.2-clean.

# ensure_mise: install mise if absent, then make sure THIS run can see it.
ensure_mise() {
  if command -v mise >/dev/null 2>&1; then
    success "mise already installed"
    return 0
  fi

  # The install location, overridable so the "already there but not on PATH" branch
  # is reachable in tests without a real uninstall (the default is the real path).
  _em_bin="${VIBE_MISE_BIN:-$HOME/.local/bin/mise}"

  if [ -x "$_em_bin" ]; then
    success "mise already installed"
  else
    info "Installing mise (a version manager for your tools)..."
    # POSIX sh, not bash: the installer is sh-compatible and this needs no bashisms.
    # MISE_INSTALL_HELP=0 suppresses the "now add this to your shell" epilogue —
    # persist_path owns that edit, and two tools both claiming it is how a beginner
    # ends up with the line twice.
    if vibe_fetch https://mise.run | MISE_INSTALL_HELP=0 sh; then
      success "mise installed"
    else
      warn "couldn't install mise — the tools that need it may be skipped"
      record_warning "mise"
      return 0
    fi
  fi

  # Installed but not yet on this shell's PATH — add its dir for this run.
  _em_dir="$(dirname "$_em_bin")"
  case ":$PATH:" in
    *":$_em_dir:"*) : ;;
    *) export PATH="$_em_dir:$PATH" ;;
  esac
}
