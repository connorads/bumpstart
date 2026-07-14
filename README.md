# vibe-setup

One-paste macOS setup for agentic / "vibe" coding. Installs Homebrew + GitHub CLI,
lets you pick a coding agent (Claude or Codex), installs its CLI + desktop app, and
drops you straight in.

macOS only (for now).

## Usage

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/install.sh)"
```

The `$(...)` form downloads the script first so stdin stays your terminal - needed
because `gh auth login` and the agent CLIs are interactive. `curl | bash` would break
those prompts. (Homebrew uses the same trick.)

## What it does

1. Installs Homebrew + `gh`, and offers to run `gh auth login`.
2. Asks which agent you use - **Claude Code** (default) or **Codex**.
3. Installs the chosen agent's CLI (the stable spine) and its desktop app
   (Claude.app, or the ChatGPT app which now hosts Codex), then launches the CLI so
   you sign in.

Everything is idempotent - already-installed tools are skipped.

## Flags

Mostly for headless / VM testing:

| Flag | Effect |
| --- | --- |
| `--agent claude\|codex` | Skip the picker |
| `--no-desktop` | Install the CLI only, skip the desktop app |
| `--no-launch` | Don't drop into the agent at the end (script returns) |

Example (non-interactive): `bash install.sh --agent claude --no-desktop --no-launch`

## Notes

- The CLI is the stable spine; the desktop app is a fast-moving vendor layer, so a
  failed cask install warns and continues rather than aborting.
- Codex's desktop experience lives inside the ChatGPT app (`brew install --cask
  chatgpt`) since the July 2026 Codex/ChatGPT app merge.
