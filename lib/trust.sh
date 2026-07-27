# shellcheck shell=bash
# trust.sh: create a starter project we control and best-effort pre-seed harness
# trust, so the novice meets exactly one prompt — the browser login, which
# cannot be pre-seeded — rather than also a trust dialog. Depends on common.sh.
#
# We only ever pre-trust STARTER_DIR (a dir we create), never an arbitrary or
# cloned repo. Browser login is framed, not hidden: it is the one prompt that
# stays. Also depends on os.sh (vibe_os, vibe_wsl) for the clipboard tool and the
# paste keystroke. bash-3.2-clean.

# The dedicated starter dir, under the user's ~/git repo convention. Never
# blanket-trust $HOME.
STARTER_DIR="$HOME/git/first-project"

# Set true once the starter prompt reaches the clipboard, so the finish message
# only claims "on your clipboard" when it actually is. STARTER_PROMPT_FILE is where
# the same text was written — the fallback that survives the agent's TUI taking over
# the screen. Pre-declared for set -u.
STARTER_PROMPT_COPIED=false
STARTER_PROMPT_FILE=""

# ensure_starter_dir: create the starter project, echo its symlink-resolved path
# (pwd -P) — the key both harnesses match trust against.
ensure_starter_dir() {
  mkdir -p "$STARTER_DIR"
  ( cd "$STARTER_DIR" && pwd -P )
}

# init_starter_repo <dir>: make the starter project a real git repo so the agent
# has somewhere to commit. No-op if it already is one; needs git on PATH — the
# caller only invokes this when the `git` block ran, so git is installed and an
# identity is set. Non-fatal: a failure warns and the setup continues.
init_starter_repo() {
  _ir_dir="$1"
  [ -d "$_ir_dir/.git" ] && return 0
  command -v git >/dev/null 2>&1 || return 0
  if git -C "$_ir_dir" init -b main >/dev/null 2>&1 \
    || git -C "$_ir_dir" init >/dev/null 2>&1; then
    success "Made your project a git project (so we can save your work)"
  else
    warn "couldn't set up git in your project — continuing"
  fi
}

# preseed_codex_trust <realpath>: mark the dir trusted in ~/.codex/config.toml.
# Reliable: global approval_policy/sandbox_mode/--yolo do NOT suppress the
# per-dir prompt (openai/codex#14345), but a trusted project entry does.
# Idempotent — skip if the section is already present.
preseed_codex_trust() {
  _t_path="$1"
  _t_cfg="$HOME/.codex/config.toml"
  _t_header="[projects.\"$_t_path\"]"
  mkdir -p "$(dirname "$_t_cfg")"
  if [ -f "$_t_cfg" ] && grep -Fq -- "$_t_header" "$_t_cfg"; then
    success "Codex already trusts $_t_path"
    return 0
  fi
  if [ -f "$_t_cfg" ]; then printf '\n' >> "$_t_cfg"; fi
  printf '%s\n' "$_t_header" >> "$_t_cfg"
  printf 'trust_level = "trusted"\n' >> "$_t_cfg"
  success "Pre-trusted $_t_path for Codex"
}

# preseed_claude_trust <realpath>: best-effort onboarding + trust in
# ~/.claude.json. The schema is undocumented and version-fragile (VS Code
# rewrites it; CVE history), so we only seed the file when ABSENT — never edit
# an existing config. If it exists, a one-time trust prompt may still appear.
preseed_claude_trust() {
  _t_path="$1"
  _t_json="$HOME/.claude.json"
  if [ -f "$_t_json" ]; then
    info "Claude config already exists — leaving it; you may see a one-time trust prompt."
    return 0
  fi
  cat > "$_t_json" <<EOF
{
  "hasCompletedOnboarding": true,
  "projects": {
    "$_t_path": {
      "hasTrustDialogAccepted": true
    }
  }
}
EOF
  success "Pre-trusted $_t_path for Claude (best-effort)"
}

# preseed_trust <harness> <realpath>: dispatch to the harness-specific seeder.
preseed_trust() {
  case "$1" in
    claude) preseed_claude_trust "$2" ;;
    codex)  preseed_codex_trust  "$2" ;;
    *) : ;;
  esac
}

# paste_key: the keystroke that pastes into a terminal here. Cmd+V on macOS;
# Ctrl+Shift+V everywhere else, which VTE (GNOME Terminal, Tilix, xfce4-terminal)
# and Windows Terminal both use — so WSL needs no branch of its own. Naming the
# wrong key is worse than naming none: the novice presses it, nothing happens, and
# they conclude the message was never copied.
paste_key() {
  case "$(vibe_os)" in
    mac) printf 'Cmd+V' ;;
    *)   printf 'Ctrl+Shift+V' ;;
  esac
}

# copy_starter_prompt <root>: put the friendly first message where the novice can
# retrieve it after the browser sign-in, and paste into the empty agent prompt.
# Reads <root>/starter-prompt.txt (no-op if missing/empty). Never fatal.
#
# The chain covers every place this runs: pbcopy (macOS), clip.exe (WSL, which can
# reach the Windows clipboard), wl-copy (Wayland — the default on Ubuntu Desktop),
# xclip (X11). Then the fallback that actually works: WRITE THE TEXT TO A FILE.
# Printing it was not a fallback at all — the applier execs the agent moments later
# and its full-screen TUI wipes the scrollback, so the message the novice was told
# to copy is gone before they can. A file survives that, and frame_login points at
# it.
copy_starter_prompt() {
  _sp_file="$1/starter-prompt.txt"
  [ -f "$_sp_file" ] || return 0
  _sp_text="$(cat "$_sp_file")"
  [ -n "$_sp_text" ] || return 0

  STARTER_PROMPT_FILE=""
  # Try each tool in turn and stop at the first that WORKS, not the first that
  # exists: a clipboard tool can be installed and still fail (no pasteboard in a
  # headless session, no Wayland socket over ssh), and falling through then is the
  # difference between a message the novice has and one they don't.
  for _sp_tool in pbcopy clip.exe wl-copy xclip; do
    command -v "$_sp_tool" >/dev/null 2>&1 || continue
    # clip.exe is only meaningful under WSL 2; a stray one elsewhere would write to a
    # clipboard nothing on this side can read.
    if [ "$_sp_tool" = clip.exe ] && [ "$(vibe_wsl)" != 2 ]; then continue; fi
    if [ "$_sp_tool" = xclip ]; then
      printf '%s' "$_sp_text" | xclip -selection clipboard && STARTER_PROMPT_COPIED=true
    else
      printf '%s' "$_sp_text" | "$_sp_tool" && STARTER_PROMPT_COPIED=true
    fi
    if [ "$STARTER_PROMPT_COPIED" = true ]; then break; fi
  done

  # Written either way: a clipboard survives a browser sign-in, but not a reboot, a
  # second terminal, or a clipboard manager that drops it.
  STARTER_PROMPT_FILE="${STARTER_DIR}/first-message.txt"
  mkdir -p "$STARTER_DIR" 2>/dev/null || true
  printf '%s\n' "$_sp_text" > "$STARTER_PROMPT_FILE" 2>/dev/null || STARTER_PROMPT_FILE=""

  if [ "$STARTER_PROMPT_COPIED" != true ] && [ -n "$STARTER_PROMPT_FILE" ]; then
    echo ""
    info "Your first message to the agent is saved here:"
    printf '    %s\n' "$STARTER_PROMPT_FILE"
  fi
}

# frame_login <harness>: reassure the novice about the one prompt that stays,
# and (when we copied it) point at the starter message waiting on the clipboard.
frame_login() {
  echo ""
  info "Almost there — $1 will open your browser to sign in."
  info "Sign in there, then come back to this window."
  if [ "${STARTER_PROMPT_COPIED:-false}" = true ]; then
    info "I've put a starter message on your clipboard to get you going."
    info "When you're back and see the empty prompt box, press $(paste_key) to paste it, then Enter."
  elif [ -n "${STARTER_PROMPT_FILE:-}" ]; then
    # No clipboard tool here, and the agent's full-screen TUI is about to wipe the
    # screen — so point at the file, which is still there afterwards.
    info "Your first message is saved in first-message.txt, in the folder the agent opens."
    info "Ask the agent to read it, or copy it in yourself."
  fi
  echo ""
}
