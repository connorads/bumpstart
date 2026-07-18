# shellcheck shell=bash
# trust.sh: create a starter project we control and best-effort pre-seed harness
# trust, so the novice meets exactly one prompt — the browser login, which
# cannot be pre-seeded — rather than also a trust dialog. Depends on common.sh.
#
# We only ever pre-trust STARTER_DIR (a dir we create), never an arbitrary or
# cloned repo. Browser login is framed, not hidden: it is the one prompt that
# stays. bash-3.2-clean.

# The dedicated starter dir. Never blanket-trust $HOME.
STARTER_DIR="$HOME/code/first-project"

# ensure_starter_dir: create the starter project, echo its symlink-resolved path
# (pwd -P) — the key both harnesses match trust against.
ensure_starter_dir() {
  mkdir -p "$STARTER_DIR"
  ( cd "$STARTER_DIR" && pwd -P )
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

# frame_login <harness>: reassure the novice about the one prompt that stays.
frame_login() {
  echo ""
  info "Almost there — $1 will open your browser to sign in."
  info "Sign in there, then come back to this window."
  echo ""
}
