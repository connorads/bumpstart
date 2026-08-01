#!/usr/bin/env bash
set -euo pipefail
#
# claude-desktop (interactive tail): install the Claude desktop app on Linux, which
# ships as an official beta from Anthropic's apt repository (Ubuntu 22.04+ / Debian
# 12+, amd64 and arm64).
#
# A script tail rather than an INSTALL_LINUX cell for two reasons that both matter:
#   - It needs a package manager and therefore a sudo password, and a cell runs
#     through spin, which rewrites the terminal line every 0.1s and would erase the
#     password prompt as it is typed. See blocks/git/apply.sh for the same reason.
#   - Registering a third-party repository means trusting a signing key, and the
#     fingerprint is VERIFIED HERE IN CODE rather than printed for a beginner to
#     eyeball. Asking someone who has never used a terminal to compare 40 hex
#     characters is not a security check; it is a formality they will skip.
#
# Debian-family only, by capability probe: a machine with no apt-get warns and
# continues. The app is an add-on — the CLI is what the setup launches — so nothing
# here is ever fatal.
#
# Known wart: _block_runs is true on the presence of an apply.sh, so this row renders
# on Fedora and Arch too and then warns. The dim "not on this machine, because …"
# plan footer is the follow-up that fixes that class properly.

# shellcheck source=lib/common.sh
. "$BUMP_LIB/common.sh"
# shellcheck source=lib/os.sh
. "$BUMP_LIB/os.sh"

[ "$(bump_os)" = linux ] || exit 0

# Anthropic's release signing key, and the fingerprint we require it to have. A key
# fetched over TLS from a host we already trust is most of the story; pinning the
# fingerprint is what makes a swapped key a refusal rather than a silent success.
# Verified live: this fingerprint is what downloads.claude.ai/claude-desktop/key.asc
# actually carries (uid "Anthropic Claude Code Release Signing").
KEY_URL="${BUMP_CLAUDE_KEY_URL:-https://downloads.claude.ai/claude-desktop/key.asc}"
KEY_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
# apt reads an ASCII-armoured key when the path ends in .asc, which is the form the
# vendor publishes and documents — so the key is installed byte-for-byte as fetched,
# with no dearmor step to go wrong between checking it and trusting it.
KEYRING="/usr/share/keyrings/claude-desktop-archive-keyring.asc"
LIST="/etc/apt/sources.list.d/claude-desktop.list"
REPO_LINE="deb [arch=amd64,arm64 signed-by=$KEYRING] https://downloads.claude.ai/claude-desktop/apt/stable stable main"

if command -v claude-desktop >/dev/null 2>&1; then
  success "the Claude desktop app already installed"
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  warn "the Claude desktop app only ships for Debian/Ubuntu so far — skipping it."
  info "Claude Code (the terminal one) is installed and is what this setup launches."
  exit 0
fi

# sudo only when we are not already root, and only when it exists.
dsudo=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    dsudo="sudo"
  else
    warn "installing the Claude desktop app needs admin rights and there is no sudo here — skipping it."
    exit 0
  fi
fi

if ! command -v gpg >/dev/null 2>&1; then
  # Without gpg the fingerprint cannot be checked, and an unverified third-party
  # repository is not something to add on a beginner's behalf.
  warn "need gpg to check the Claude app's signing key — skipping the desktop app."
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/bumpstart-claude.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if ! bump_fetch "$KEY_URL" > "$tmp/key.asc" 2>/dev/null || [ ! -s "$tmp/key.asc" ]; then
  warn "couldn't download the Claude app's signing key — skipping the desktop app."
  exit 0
fi

# --with-colons is the machine-readable form; the fpr record's 10th field is the
# fingerprint, unspaced, so this needs no normalising. Read from the same file that
# gets installed, so there is nothing between the check and the trust.
got="$(gpg --show-keys --with-colons "$tmp/key.asc" 2>/dev/null \
  | awk -F: '$1 == "fpr" { print $10; exit }' || true)"

if [ "$got" != "$KEY_FPR" ]; then
  warn "the Claude app's signing key is not the one we expect — NOT installing the desktop app."
  info "Expected $KEY_FPR"
  info "Got      ${got:-nothing}"
  info "Claude Code (the terminal one) is installed and unaffected. Report this if it persists."
  exit 0
fi
success "Checked the Claude app's signing key"

if ! $dsudo install -m 0644 "$tmp/key.asc" "$KEYRING" 2>/dev/null; then
  warn "couldn't install the Claude app's signing key — skipping the desktop app."
  exit 0
fi

# Idempotent: rewrite the one-line source only when it differs, so a re-run leaves
# the file byte-identical and apt has nothing to re-fetch.
if [ "$(cat "$LIST" 2>/dev/null || true)" != "$REPO_LINE" ]; then
  if ! printf '%s\n' "$REPO_LINE" | $dsudo tee "$LIST" >/dev/null; then
    warn "couldn't register the Claude app's repository — skipping the desktop app."
    exit 0
  fi
fi

info "Installing the Claude desktop app (your system will ask for your password)..."
if [ -n "$dsudo" ]; then
  # Narrate the blank, non-echoing prompt before it fires — same reason as brew.sh.
  info "Your computer wants the password you use to log in. Nothing appears as you type - that is normal. Press Return when you're done."
  [ -t 0 ] && sudo -v
fi

if $dsudo apt-get update -qq && $dsudo apt-get install -y -qq claude-desktop; then
  success "the Claude desktop app installed"
else
  warn "couldn't install the Claude desktop app — continuing."
  info "Claude Code (the terminal one) is installed and is what this setup launches."
fi
