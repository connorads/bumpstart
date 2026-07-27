# vibe-setup

One-paste macOS setup for agentic / "vibe" coding. Gets someone who may never
have used a terminal from nothing to happily talking to a coding agent - with
the tools, skills and instructions already in place, and **one thing to choose**:
which agent, because that follows the AI subscription you already have.

It composes vetted **blocks**. You (or a workshop leader) hand out one paste
listing the blocks you want; the applier resolves them, shows a plain-language
plan, asks **once**, then sets everything up and drops you into the agent.

macOS and native Windows (no WSL needed). Linux is not supported yet.

## Quick start

There is one thing only you know: **which AI subscription you already pay for**.
Pick the line that matches it and paste. Everything else is chosen for you -
`starter` is the whole beginner setup (GitHub + git + Node + beginner
instructions).

### macOS (Terminal)

If you use **Claude**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude starter
```

If you use **ChatGPT**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ codex starter
```

### Windows (PowerShell)

Open **PowerShell** (the one already on your PC). If you use **Claude**:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe.ps1))) claude starter
```

If you use **ChatGPT**:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe.ps1))) codex starter
```

The Windows install needs no admin for the coding agents themselves (Claude Code
and Codex install just for you); Node.js and Git install for all users via
winget and each ask permission once.

### The shortest paste

With no ids at all you get `claude starter`, the same beginner setup on Claude:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/install.sh)"
```

```powershell
irm https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe.ps1 | iex
```

Or compose your own setup from any list of block ids:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude gh-auth node concise
```

The `$(...)` form downloads the script first so your terminal stays the input -
needed because `gh auth login` and the agent CLIs are interactive. `curl | bash`
would break those prompts. (Homebrew uses the same trick.) The `_ a b` after the
paste sets the block list; `_` is a throwaway `$0`.

## Blocks

A block is a small, vetted unit of setup. You compose them by listing ids. The
list is **unioned** and dependencies are pulled in automatically, so there is no
removal operator: **every id only ever adds**. That rule shapes the vocabulary -
each id names the smallest thing that is true, and a preset contains only what
every user of it wants.

The one single-choice is which agent launches, and there **last in the list
wins** (`claude codex` launches Codex, `codex claude` launches Claude).

### Axes

Every block carries two labels. `kind` is for the applier: it decides when a
block runs. **`axis` is for you**: it names the question the block answers, and
it is what `--build` asks and `--list` groups by.

| axis       | the question it asks             |
| ---------- | -------------------------------- |
| `recipe`   | Start from a ready-made setup?    |
| `agent`    | Which agent should launch?        |
| `tools`    | What should we install?           |
| `steering` | How should the agent be steered?  |

A block with no axis is never offered on its own but is still pulled in as a
dependency - `mise` is the example: nobody picks a version manager directly, it
arrives with `node` or `pnpm`. Axes are data (`axes/<id>/meta`), so adding a
question is adding a directory.

### Atoms

| id               | axis     | kind         | what it does                                                       |
| ---------------- | -------- | ------------ | ------------------------------------------------------------------ |
| `claude-cli`     | agent    | harness      | Install Claude Code (CLI); can be the launched agent               |
| `codex-cli`      | agent    | harness      | Install Codex (CLI); can be the launched agent                     |
| `gh-auth`        | tools    | auth         | Install GitHub CLI + offer sign-in                                 |
| `git`            | tools    | tool         | Install git + set your name/email from GitHub (pulls in `gh-auth`) |
| `github-desktop` | tools    | app          | Install GitHub Desktop, so you can see and undo what the agent did (pulls in `git`) |
| `node`           | tools    | tool         | Install Node.js LTS via mise (pulls in `mise`)                     |
| `pnpm`           | tools    | tool         | Install pnpm via mise (pulls in `mise`)                            |
| `safer-installs` | tools    | tool         | Make npm/pnpm/mise wait 4 days on brand-new releases (macOS only)  |
| `welcome`        | steering | instructions | Greet the beginner + how to work with the agent every session      |
| `concise`        | steering | instructions | Ask the agent to keep answers concise                              |
| `ask-first`      | steering | instructions | Ask before installing tools / deleting files                       |
| `verify`         | steering | instructions | Run it before calling it done; show the real error                 |
| `secrets`        | steering | instructions | Keep keys out of the chat, and out of GitHub                        |
| `check-first`    | steering | instructions | Read the code / the docs instead of answering from memory          |
| `commit-often`   | steering | instructions | Commit at every working checkpoint; never force-push               |
| `follow-conventions` | steering | instructions | Match the codebase's conventions, not the agent's defaults     |
| `remember`       | steering | instructions | Write down decisions and surprises for the next reader             |
| `claude-desktop` | -        | app          | Install the Claude desktop app (arrives with `claude`)             |
| `codex-desktop`  | -        | app          | Install the ChatGPT app, Codex's desktop home (arrives with `codex`) |
| `mise`           | -        | tool         | Install mise (runtime version manager; arrives with `node`/`pnpm`) |

`github-desktop` is opt-in, not part of `web` or `starter`. Note it means a
second GitHub sign-in: `gh` and GitHub Desktop keep separate credential stores
and neither can read the other's token. That one happens whenever you first open
the app, so it is off the paste's critical path - `--plan` says so.

### Presets, one per axis

A preset is just a block whose content is a list of other ids. Each of these
covers exactly one axis, so they compose - pick the one you want per axis (on a
multi-select axis you *may* pick more than one, but two steering presets is
rarely what you want: you'd get both sets of habits).

| preset     | axis     | expands to                  |
| ---------- | -------- | --------------------------- |
| `claude`   | agent    | `claude-cli claude-desktop` |
| `codex`    | agent    | `codex-cli codex-desktop`   |
| `web`      | tools    | `gh-auth git node`          |
| `beginner` | steering | `welcome concise ask-first verify secrets` |
| `dev`      | steering | `concise ask-first verify secrets check-first commit-often follow-conventions remember` |

`beginner` and `dev` are the two steering tiers. `dev` is the same safety habits
plus the ones that matter once you're writing real code - check before you
recall, commit at every checkpoint, match the codebase, write down what you
learned - and deliberately drops `welcome`, which exists to explain the basics:

```text
… _ claude web dev        # the stack, steered for someone who codes
```

### Recipes

A recipe spans axes: it is the ready-made setup a workshop hands out.

| recipe    | axis   | expands to     |
| --------- | ------ | -------------- |
| `starter` | recipe | `web beginner` |

`starter` is deliberately **agent-free**: which agent you want is not a tooling
choice, it is which subscription you already pay for, and a workshop handout
can't know that for the room. So the agent is always a separate id:

```text
… _ claude starter        # everything Claude + stack + beginner habits (the default)
… _ codex starter         # the same on ChatGPT/Codex
… _ claude-cli starter    # CLI only, no desktop app
… _ claude codex starter  # both agents, launches codex (last in the list wins)
… _ codex web             # the stack without the beginner instructions
… _ claude starter github-desktop   # …plus a GUI for seeing and undoing changes
```

Appending an agent id to *any* preset sets the launcher: the launch scan runs
over the expanded list in input order, so `claude starter codex` installs both
and launches Codex. It adds, never replaces.

Desktop-ness is a composition choice too: `claude` (a bundle) gives CLI +
desktop app, `claude-cli` gives CLI-only. Same for `codex`. The launched agent
is always the CLI - the desktop app is an add-on.

A tool block also teaches the agent how to use what it installs: its short
guidance is stacked into the canonical instructions file, but only when that
block is in the plan - so `mise`/`node`/`pnpm` steer the agent to those tools
instead of a hand-rolled installer, and the guidance is present exactly when the
tool is.

The `skill` and `mcp` kinds are supported by the applier, but no recommended
skill or MCP block ships yet - better none than a redundant one.

## What happens when you run it

1. Fetch the repo at a pinned ref (default `main`) as a tarball, run it locally.
2. **Resolve** the id list to a plan (expand presets + deps, dedupe, order by
   kind, pick the launch agent). Any bad id / cycle / missing-agent fails **here**,
   before anything is installed.
3. Print the plan and ask **once** to proceed.
4. Install Homebrew if needed, then apply each block (check-then-act, so re-runs
   skip what is already there).
5. Assemble the block instructions into **one canonical file**
   (`~/.agents/AGENTS.md`), then symlink each installed agent's own path to it
   (`~/.claude/CLAUDE.md` for Claude, `~/.codex/AGENTS.md` for Codex) so both
   agents read the single source.
6. Create a starter project (`~/git/first-project`, a git repo when the `git`
   block is in the plan), pre-trust it, copy a
   friendly first message to the clipboard (survives the sign-in - paste it with
   Cmd+V), then launch the agent. A browser opens for sign-in - that one prompt
   stays.

Everything is idempotent: run it again and already-done steps are skipped; a
symlink already pointing at the canonical file is left alone. vibe never scribbles
in files you own - if the canonical file or a real agent config already exists, it
backs off and points you at it (use `--force` to replace: real files are moved to
`.bak` first).

On **Windows** the shape is identical; the OS-specific bits differ: installs go
through winget + the CLIs' own PowerShell installers (no Homebrew), and instead
of a symlink each agent is linked to the canonical file its own way - Claude via
an `@import` line in `~/.claude/CLAUDE.md`, Codex via a physical copy of
`~/.codex/AGENTS.md` (Codex has no import). The clipboard paste is Ctrl+V.

## Flags

| flag             | effect                                        |
| ---------------- | --------------------------------------------- |
| `--plan`         | Print the resolved plan and exit - no changes |
| `--list`         | Print the catalogue, grouped by axis, and exit |
| `--show <id>`    | Print one block's detail (axis, kind, deps, target) |
| `--build`        | Interactive wizard - one question per axis, emit the paste |
| `--yes` / `-y`   | Skip the confirm (for headless / VM runs)     |
| `--force`        | Rewrite an existing canonical file; back real agent configs up to `.bak` then link |
| `--no-launch`    | Don't drop into the agent at the end          |

Preview a setup without touching anything:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude starter --plan
```

## Composing a bundle (workshop leaders)

Whoever hands out the paste can discover and assemble it in the CLI rather than
recalling ids from the table above.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ --list       # what blocks exist
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ --show node  # one block's detail
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ --build      # wizard
```

`--build` asks **one question per axis**, in the order the axes declare: start
from a recipe, which agent launches (required, pick a number), what to install,
how to steer. Each row shows what it pulls in, so a whole and its parts read as
nested rather than as separate ticks. Answering "starter" then "claude" emits
`claude starter` - the same string the Quick start hands out. It previews the
resolved plan, then **prints the one-paste command** to hand out (and copies it
to the clipboard where `pbcopy` exists), and offers to
run the setup now. The emitted command inherits the run's `VIBE_REF`: pin the
run (`VIBE_REF=<sha> … --build`) and the paste carries the same `VIBE_REF=<sha>`
prefix, so a workshop stays reproducible.

## Pinning (workshops)

An unpinned run uses `main`. For a reproducible workshop, pin the whole repo to a
commit SHA with `VIBE_REF` - vetted source is the audit layer:

```bash
VIBE_REF=<sha> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude starter
```

Vendor CLI versions (Claude, Codex, mise, ...) sit outside the pin - they always
install the latest.

## Notes

- The CLI is the stable spine; the desktop app is a fast-moving vendor layer, so
  a failed cask install warns and continues rather than aborting.
- Codex's desktop experience lives inside the ChatGPT app (`brew install --cask
  chatgpt`) since the July 2026 Codex/ChatGPT merge.
- Instructions live in one canonical file (`~/.agents/AGENTS.md`); each agent's
  own path is a symlink to it (the documented `ln -s AGENTS.md CLAUDE.md`
  pattern), so editing one file steers every agent and every session.
  `~/.agents/` is the one agents root: it is already where Codex, Amp, opencode
  and pi look for user-scope skills. No standard names a user-level `AGENTS.md`
  yet - [agents.md](https://agents.md) is repo-scoped.
- **Set up before this moved?** Earlier versions wrote the canonical file to
  `~/.config/agents/AGENTS.md`. A re-run writes the new path but will **not**
  relink: `~/.claude/CLAUDE.md` still points at the old file, so vibe sees a
  foreign symlink and backs off, and your agent keeps reading the old file. Move
  your edits into `~/.agents/AGENTS.md`, delete the old file, and re-run - or
  re-run with `--force`, which backs the old links up to `.bak` and relinks.
- Why `kind` and `axis` are separate labels, and what was rejected on the way:
  [docs/adr/0001](docs/adr/0001-axis-as-the-human-taxonomy.md).

## Development

Two spines, twin-authored against one shared fixture contract so they can't
drift: **bash** (macOS, targeting `/bin/bash` 3.2) and **PowerShell** (Windows,
targeting **Windows PowerShell 5.1** — the default shell on a fresh Windows, not
pwsh 7). Blocks are single-sourced: per-OS install/check live in block metadata
as data (`CHECK_MAC`/`INSTALL_WIN`/…); only the thin runner + the pure resolver
are authored twice. Tooling via `mise`:

```bash
# bash spine (macOS)
mise run lint          # shellcheck
mise run test-bash32   # the whole bats suite under /bin/bash (3.2)
mise run check         # lint + test

# PowerShell spine (Pester + PSScriptAnalyzer; run bootstrap once first)
pwsh -File bootstrap.ps1   # install pinned Pester + PSScriptAnalyzer
mise run test-ps           # Pester suite (pure core, shared contract, Windows e2e)
mise run lint-ps           # PSScriptAnalyzer 5.1-floor gate + the $IsWindows grep
mise run check-ps          # lint-ps + test-ps
```

Tests are black-box with fakes (no network, no real installs): PATH-shadow fakes
on bash, shadow functions on PowerShell. The two resolvers are locked to one
`tests/fixtures/contract/resolve-cases.tsv` (driven by `contract.bats` and
`Contract.Tests.ps1`). The Windows e2e (`Apply.Tests.ps1`) drives the applier
in-process with `VIBE_OS=win`.

**Support contracts (mechanically enforced):** bash stays 3.2-clean (no
associative arrays / `mapfile` / `${v,,}`); PowerShell stays 5.1-clean — no
`$IsWindows` outside `lib/os.ps1`, no 7-only syntax (ternary, `??`, `&&`/`||`) —
gated by `PSUseCompatibleSyntax`/`PSUseCompatibleCommands`/`PSUseCompatibleTypes`
against the bundled 5.1 profile in `lint-ps`, plus a windows-latest 5.1 smoke.
CI runs both lanes (`macos-latest` + `windows-latest`).
