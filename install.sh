#!/usr/bin/env bash
set -euo pipefail

# Vibe-coding setup for macOS.
#
# Run with:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/install.sh)"
#
# The $() substitution downloads the script first so stdin stays the terminal —
# needed because `gh auth login` and the agent CLIs are interactive. `curl | bash`
# pipes stdin and would break those prompts. Homebrew uses the same trick.
#
# Flags (mostly for headless / VM testing):
#   --agent claude|codex   skip the picker
#   --no-desktop           install the CLI only, skip the desktop app
#   --no-launch            don't drop into the agent at the end (script returns)

# ── Options ─────────────────────────────────────────────────────────────────────

AGENT=""
DESKTOP=true
LAUNCH=true

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    --agent=*) AGENT="${1#*=}"; shift ;;
    --no-desktop) DESKTOP=false; shift ;;
    --no-launch) LAUNCH=false; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Colours + formatting ────────────────────────────────────────────────────────

if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  GREEN="" BLUE="" RED="" YELLOW="" DIM="" BOLD="" RESET=""
else
  GREEN=$'\033[32m' BLUE=$'\033[34m' RED=$'\033[31m'
  YELLOW=$'\033[33m' DIM=$'\033[2m' BOLD=$'\033[1m' RESET=$'\033[0m'
fi

info()    { printf "  %s>%s %s\n" "$BLUE" "$RESET" "$1"; }
success() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()    { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1" >&2; }
error()   { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1" >&2; }
step()    { printf "\n  %s[%s/%s]%s %s\n" "$BOLD" "$1" "$2" "$RESET" "$3"; }

# ── Preflight: macOS only ────────────────────────────────────────────────────────

if [ "$(uname -s)" != "Darwin" ]; then
  error "This installer is macOS-only for now."
  exit 1
fi

echo ""
printf "  %svibe-coding setup%s %s— macOS%s\n" "$BOLD" "$RESET" "$DIM" "$RESET"
echo ""
echo "  This will:"
echo "    1. Install Homebrew + GitHub CLI (gh)"
echo "    2. Ask which coding agent you use (Claude or Codex)"
echo "    3. Install its CLI + desktop app, then drop you in"
echo ""

# ── Agent metadata ───────────────────────────────────────────────────────────────
# Fields per agent: name | cli cmd | cli installer | desktop .app | desktop cask

agent_meta() {
  case "$1" in
    claude) printf '%s\n' \
      "Claude Code" \
      "claude" \
      "curl -fsSL https://claude.ai/install.sh | bash" \
      "Claude.app" \
      "claude" ;;
    codex) printf '%s\n' \
      "Codex" \
      "codex" \
      "curl -fsSL https://chatgpt.com/codex/install.sh | sh" \
      "ChatGPT.app" \
      "chatgpt" ;;
    *) return 1 ;;
  esac
}

# ── Step 1: Homebrew + gh ────────────────────────────────────────────────────────

step 1 3 "Installing Homebrew + GitHub CLI"
echo ""

if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
  info "Installing Homebrew (may prompt for your password + Xcode CLT)..."
  [ -t 0 ] && sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  success "Homebrew already installed"
fi

# Put brew on PATH for the rest of this run (Apple Silicon or Intel prefix)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if command -v gh >/dev/null 2>&1; then
  success "gh already installed"
else
  info "Installing gh..."
  brew install gh
  success "gh installed"
fi

# gh auth — interactive, so only when we have a terminal and aren't logged in
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

# ── Step 2: Pick an agent ────────────────────────────────────────────────────────

step 2 3 "Choosing a coding agent"

if [ -z "$AGENT" ]; then
  if [ ! -t 0 ]; then
    error "No terminal for the picker. Pass --agent claude|codex."
    exit 1
  fi
  echo ""
  printf "    %s1)%s Claude Code %s(recommended)%s\n" "$BOLD" "$RESET" "$DIM" "$RESET"
  printf "    %s2)%s Codex\n" "$BOLD" "$RESET"
  printf "\n    Choose %s[1-2]%s (default 1): " "$YELLOW" "$RESET"
  read -r choice
  case "$choice" in
    ""|1) AGENT="claude" ;;
    2)    AGENT="codex" ;;
    *)    error "Invalid choice"; exit 1 ;;
  esac
fi

if ! agent_meta "$AGENT" >/dev/null; then
  error "Unknown agent '$AGENT' (expected: claude or codex)"
  exit 1
fi

{ read -r A_NAME; read -r A_CLI; read -r A_CLI_INSTALL; read -r A_APP; read -r A_CASK; } < <(agent_meta "$AGENT")
echo ""
success "Selected $A_NAME"

# ── Step 3: Install the agent (CLI + optional desktop) ───────────────────────────

step 3 3 "Installing $A_NAME"
echo ""

# CLI (the stable spine) — best-effort so a failure still shows the summary
if command -v "$A_CLI" >/dev/null 2>&1; then
  success "$A_NAME CLI already installed"
else
  info "Installing $A_NAME CLI..."
  if bash -c "$A_CLI_INSTALL"; then
    success "$A_NAME CLI installed"
  else
    error "Couldn't install the $A_NAME CLI — try again or install by hand."
  fi
fi

# Desktop app (fast-moving vendor layer) — non-fatal, skippable
if [ "$DESKTOP" = true ]; then
  if [ -d "/Applications/$A_APP" ]; then
    success "$A_NAME desktop app already installed"
  else
    info "Installing the $A_NAME desktop app..."
    if brew install --cask "$A_CASK"; then
      success "$A_NAME desktop app installed"
    else
      warn "Couldn't install the desktop app — skipping (later: brew install --cask $A_CASK)"
    fi
  fi
fi

# Freshly-installed CLIs often land in ~/.local/bin — make sure this shell sees them
export PATH="$HOME/.local/bin:$HOME/.codex/bin:$PATH"

# ── Done ─────────────────────────────────────────────────────────────────────────

echo ""
success "Setup complete."
[ -d "/Applications/$A_APP" ] && info "Desktop app installed — open it and sign in when you like."

if [ "$LAUNCH" = true ] && command -v "$A_CLI" >/dev/null 2>&1; then
  echo ""
  info "Starting $A_NAME — sign in when prompted..."
  echo ""
  exec "$A_CLI"
else
  echo ""
  info "Run '$A_CLI' to start (you'll sign in on first launch)."
fi
