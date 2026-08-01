# shellcheck shell=bash
# shellpath.sh: make the dirs bumpstart installs into survive the terminal window.
#
# fixup_path (common.sh) fixes PATH for THIS run only. That is why a beginner can
# watch an agent install, open a new terminal, and be told "command not found" —
# the single most demoralising way for a setup to fail, because nothing looked
# broken. So bumpstart writes exactly one marker-wrapped line into the startup file of
# the shell they log in with.
#
# This is the ONLY file outside bumpstart's own config paths that bumpstart edits, and it is
# disclosed at the confirm gate (_render_expectations in plan.sh). The markers are
# what make removing it mechanical, which is the deal the README states.
#
# Back off, never rewrite: an rc file already carrying the marker is left
# byte-identical — the same rule link_harness follows for a native config path.
# An rc file we would append to is only ever appended to, after making sure it
# ends in a newline, so a line the user wrote is never joined onto.
#
# Depends on common.sh (success/info/warn). bash-3.2-clean.

BUMP_PATH_MARKER_BEGIN="# >>> bumpstart >>>"
BUMP_PATH_MARKER_END="# <<< bumpstart <<<"

# _shell_rc — echo the startup file of the shell the user LOGS IN with ($SHELL,
# not the bash running this script — that one is gone the moment bumpstart exits), or
# nothing for a shell we don't know how to edit. Keyed on the basename, so
# /bin/zsh, /usr/bin/zsh and a Nix store path all answer the same.
_shell_rc() {
  case "$(basename "${SHELL:-}")" in
    zsh)  printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash) printf '%s' "$HOME/.bashrc" ;;
    fish) printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
  esac
}

# _path_line <posix|fish> — the one line we write. The dirs are exactly the ones
# fixup_path prepends for this run, so "what this run can see" and "what the next
# terminal can see" cannot drift. fish gets its own syntax: it has no `export` and
# no ${x:-y}, and fish_add_path is the idiom its docs prescribe.
#
# The single quotes are the point: $HOME and $PATH must land in the rc file
# UNEXPANDED, so the line reads correctly for whoever's shell later sources it.
# shellcheck disable=SC2016
_path_line() {
  if [ "$1" = fish ]; then
    printf 'fish_add_path $HOME/.local/bin $HOME/.codex/bin $HOME/.local/share/mise/shims'
  else
    printf 'export PATH="$HOME/.local/bin:$HOME/.codex/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"'
  fi
}

# persist_path: append the marker-wrapped PATH line to the login shell's rc file.
# Sets BUMP_PATH_PERSISTED to the file written (empty when nothing was written).
# Never fatal: an rc file we cannot write warns and the setup continues.
persist_path() {
  BUMP_PATH_PERSISTED=""
  _sp_shell="$(basename "${SHELL:-}")"
  _sp_rc="$(_shell_rc)"

  # An unfamiliar login shell: print the line rather than guess at a filename and
  # scribble in the wrong place.
  if [ -z "$_sp_rc" ]; then
    info "Add this to your shell's startup file so new terminals find your tools:"
    printf '    %s\n' "$(_path_line posix)"
    return 0
  fi

  if [ -f "$_sp_rc" ] && grep -Fq -- "$BUMP_PATH_MARKER_BEGIN" "$_sp_rc"; then
    success "Your shell already knows where bumpstart installs things"
    return 0
  fi

  case "$_sp_shell" in
    fish) _sp_kind=fish ;;
    *)    _sp_kind=posix ;;
  esac

  mkdir -p "$(dirname "$_sp_rc")"
  if [ -s "$_sp_rc" ] && [ -n "$(tail -c 1 "$_sp_rc")" ]; then
    printf '\n' >> "$_sp_rc" || true
  fi
  if {
    printf '%s\n' "$BUMP_PATH_MARKER_BEGIN"
    printf '%s\n' "$(_path_line "$_sp_kind")"
    printf '%s\n' "$BUMP_PATH_MARKER_END"
  } >> "$_sp_rc"; then
    BUMP_PATH_PERSISTED="$_sp_rc"
    success "New terminals will find your tools (one line added to $_sp_rc)"
  else
    warn "couldn't update $_sp_rc — new terminals may not find your tools"
  fi
  return 0
}
