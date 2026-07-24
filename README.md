# vibe-setup

One-paste macOS setup for agentic / "vibe" coding. Gets someone who may never
have used a terminal from nothing to happily talking to a coding agent - with
the right agent, tools, skills and instructions already in place, and **nothing
to choose**.

It composes vetted **blocks**. You (or a workshop leader) hand out one paste
listing the blocks you want; the applier resolves them, shows a plain-language
plan, asks **once**, then sets everything up and drops you into the agent.

macOS only (for now).

## Quick start

Install Claude Code and go:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/install.sh)"
```

Or compose your own setup with `vibe` and a list of block ids:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude gh-auth node concise
```

Or use a named preset:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ web-starter
```

The `$(...)` form downloads the script first so your terminal stays the input -
needed because `gh auth login` and the agent CLIs are interactive. `curl | bash`
would break those prompts. (Homebrew uses the same trick.) The `_ a b` after the
paste sets the block list; `_` is a throwaway `$0`.

## Blocks

A block is a small, vetted unit of setup. You compose them by listing ids. The
list is **unioned**; dependencies are pulled in automatically; the only
single-choice is which agent launches, and there **last in the list wins**
(`claude codex` launches Codex, `codex claude` launches Claude).

| id           | kind         | what it does                                                       |
| ------------ | ------------ | ------------------------------------------------------------------ |
| `claude`     | harness      | Install Claude Code (CLI + desktop app); can be the launched agent |
| `codex`      | harness      | Install Codex (CLI + ChatGPT app); can be the launched agent       |
| `gh-auth`    | auth         | Install GitHub CLI + offer sign-in                                 |
| `mise`       | tool         | Install mise (runtime version manager)                             |
| `node`       | tool         | Install Node.js LTS via mise (pulls in `mise`)                     |
| `pnpm`       | tool         | Install pnpm via mise (pulls in `mise`)                            |
| `concise`    | instructions | Ask the agent to keep answers concise                              |
| `ask-first`  | instructions | Ask before installing tools / deleting files                       |

A tool block also teaches the agent how to use what it installs: its short
guidance is merged into the agent's instructions file, but only when that block
is in the plan - so `mise`/`node`/`pnpm` steer the agent to those tools instead
of a hand-rolled installer, and the guidance is present exactly when the tool is.

The `skill` and `mcp` kinds are supported by the applier, but no recommended
skill or MCP block ships yet - better none than a redundant one.

Presets are just a block whose content is a list of other ids:

| preset         | expands to                    |
| -------------- | ----------------------------- |
| `web-starter`  | `claude gh-auth node concise` |

## What happens when you run it

1. Fetch the repo at a pinned ref (default `main`) as a tarball, run it locally.
2. **Resolve** the id list to a plan (expand presets + deps, dedupe, order by
   kind, pick the launch agent). Any bad id / cycle / missing-agent fails **here**,
   before anything is installed.
3. Print the plan and ask **once** to proceed.
4. Install Homebrew if needed, then apply each block (check-then-act, so re-runs
   skip what is already there).
5. Merge any instructions into the file each agent actually reads
   (`~/.claude/CLAUDE.md` for Claude, `~/.codex/AGENTS.md` for Codex).
6. Create a starter project (`~/code/first-project`), pre-trust it, then launch
   the agent there. A browser opens for sign-in - that one prompt stays.

Everything is idempotent: run it again and already-done steps are skipped;
managed instruction blocks live between markers and are updated in place, leaving
the rest of the file untouched.

## Flags

| flag             | effect                                        |
| ---------------- | --------------------------------------------- |
| `--plan`         | Print the resolved plan and exit - no changes |
| `--list`         | Print the block/preset catalogue and exit     |
| `--show <id>`    | Print one block's detail (kind, deps, target) |
| `--build`        | Interactive wizard - assemble a bundle, emit the paste |
| `--yes` / `-y`   | Skip the confirm (for headless / VM runs)     |
| `--no-launch`    | Don't drop into the agent at the end          |
| `--no-desktop`   | Install the CLI only, skip the desktop app    |

Preview a setup without touching anything:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ web-starter --plan
```

## Composing a bundle (workshop leaders)

Whoever hands out the paste can discover and assemble it in the CLI rather than
recalling ids from the table above.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ --list       # what blocks exist
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ --show node  # one block's detail
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ --build      # wizard
```

`--build` asks which agent launches (required), then offers every other block as
opt-in. It previews the resolved plan, then **prints the one-paste command** to
hand out (and copies it to the clipboard where `pbcopy` exists), and offers to
run the setup now. The emitted command inherits the run's `VIBE_REF`: pin the
run (`VIBE_REF=<sha> … --build`) and the paste carries the same `VIBE_REF=<sha>`
prefix, so a workshop stays reproducible.

## Pinning (workshops)

An unpinned run uses `main`. For a reproducible workshop, pin the whole repo to a
commit SHA with `VIBE_REF` - vetted source is the audit layer:

```bash
VIBE_REF=<sha> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ web-starter
```

Vendor CLI versions (Claude, Codex, mise, ...) sit outside the pin - they always
install the latest.

## Notes

- The CLI is the stable spine; the desktop app is a fast-moving vendor layer, so
  a failed cask install warns and continues rather than aborting.
- Codex's desktop experience lives inside the ChatGPT app (`brew install --cask
  chatgpt`) since the July 2026 Codex/ChatGPT merge.
- Instructions are written to each agent's own file; neither agent reads
  `~/.agents/AGENTS.md` by default, so nothing is written there.

## Development

Pure bash, targeting macOS `/bin/bash` (3.2). Tooling via `mise`:

```bash
mise run lint          # shellcheck
mise run test          # bats suite
mise run test-fast     # skip integration-tagged tests
mise run test-bash32   # run the whole suite under /bin/bash (3.2)
mise run check         # lint + test
```

Tests are black-box with PATH-shadow fakes (no network, no real installs). The
pure resolver is exercised via `--plan` against a fixture block tree; `merge.sh`
and `trust.sh` are driven under `/bin/bash` against an isolated `HOME`.
