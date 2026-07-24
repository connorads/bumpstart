# shellcheck shell=bash
# trust.sh: create a starter project we control and best-effort pre-seed harness
# trust, so the novice meets exactly one prompt — the browser login, which
# cannot be pre-seeded — rather than also a trust dialog. Depends on common.sh.
#
# We only ever pre-trust STARTER_DIR (a dir we create), never an arbitrary or
# cloned repo. Browser login is framed, not hidden: it is the one prompt that
# stays. bash-3.2-clean.

# The dedicated starter dir, under the user's ~/git repo convention. Never
# blanket-trust $HOME.
STARTER_DIR="$HOME/git/first-project"

# Set true once the starter prompt reaches the clipboard, so the finish message
# only claims "on your clipboard" when it actually is.
STARTER_PROMPT_COPIED=false

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

# copy_starter_prompt <root>: put the friendly first message on the clipboard so
# it survives the browser sign-in and the novice can paste it into the empty
# agent prompt. Reads <root>/starter-prompt.txt (no-op if missing/empty). When
# pbcopy is absent (non-macOS/headless) it prints the prompt to copy by hand and
# leaves STARTER_PROMPT_COPIED false. Never fatal.
copy_starter_prompt() {
  _sp_file="$1/starter-prompt.txt"
  [ -f "$_sp_file" ] || return 0
  _sp_text="$(cat "$_sp_file")"
  [ -n "$_sp_text" ] || return 0
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$_sp_text" | pbcopy && STARTER_PROMPT_COPIED=true
  else
    echo ""
    info "Copy this and paste it as your first message to the agent:"
    printf '\n%s\n\n' "$_sp_text"
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
    info "When you're back and see the empty prompt box, press Cmd+V to paste it, then Enter."
  fi
  echo ""
}
