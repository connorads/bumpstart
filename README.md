# vibe-setup

One-paste setup for agentic / "vibe" coding. Gets someone who may never
have used a terminal from nothing to happily talking to a coding agent - with
the tools, skills and instructions already in place, and **one thing to choose**:
which agent, because that follows the AI subscription you already have.

It composes vetted **blocks**. You (or a workshop leader) hand out one paste
listing the blocks you want; the applier resolves them, shows a plain-language
plan, asks **once**, then sets everything up and drops you into the agent.

macOS, Linux (including WSL 2) and native Windows (no WSL needed).

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

### Linux (Terminal)

Same ids, and the line carries a `wget` fallback because Ubuntu Desktop ships no
`curl`. If you use **Claude**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe 2>/dev/null || wget -qO- https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude starter
```

If you use **ChatGPT**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe 2>/dev/null || wget -qO- https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ codex starter
```

Tested on Ubuntu, Debian, Fedora and Arch, on x86-64 and arm64, and inside **WSL 2**
and containers. Derivatives (Mint, Pop!_OS, openSUSE, …) are found by capability, not
by name, so they generally work too. Your login password is asked for once, and only
if `git` needs installing.

**Not supported:** Alpine and other musl systems (the tools we install publish no
musl builds), NixOS (the vendor binaries need `/lib64`), and **WSL 1** — vibe refuses
that one and prints the single command that upgrades it to WSL 2.

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

Downloading needs **either `curl` or `wget`** - vibe uses whichever is there. macOS
always has curl. If a paste prints nothing at all, you have neither: install one
(`sudo apt install curl`) and paste again.

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
| `safer-installs` | tools    | tool         | Make npm/pnpm/mise wait 4 days on brand-new releases (macOS + Linux) |
| `welcome`        | steering | instructions | Greet the beginner + how to work with the agent every session      |
| `concise`        | steering | instructions | Ask the agent to keep answers concise                              |
| `ask-first`      | steering | instructions | Ask before installing tools / deleting files                       |
| `verify`         | steering | instructions | Run it before calling it done; show the real error                 |
| `secrets`        | steering | instructions | Keep keys out of the chat, and out of GitHub                        |
| `check-first`    | steering | instructions | Read the code / the docs instead of answering from memory          |
| `commit-often`   | steering | instructions | Commit at every working checkpoint; never force-push               |
| `follow-conventions` | steering | instructions | Match the codebase's conventions, not the agent's defaults     |
| `remember`       | steering | instructions | Write down decisions and surprises for the next reader             |
| `claude-desktop` | -        | app          | Install the Claude desktop app (arrives with `claude`; Linux: Debian/Ubuntu only) |
| `codex-desktop`  | -        | app          | Install the ChatGPT app, Codex's desktop home (arrives with `codex`; not on Linux) |
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
4. Put the install substrate in place - **Homebrew** on macOS, **mise** on Linux -
   then apply each block (check-then-act, so re-runs skip what is already there).
5. Assemble the block instructions into **one canonical file**
   (`~/.agents/AGENTS.md`), then symlink each installed agent's own path to it
   (`~/.claude/CLAUDE.md` for Claude, `~/.codex/AGENTS.md` for Codex) so both
   agents read the single source.
6. Make sure a new terminal window still finds what was installed: on macOS and
   Linux that is **one marked line** in your shell's startup file; on Windows it is
   your **account's PATH** in the registry, which has nowhere to put a marker (see
   [Removing it](#removing-it)).
7. Create a starter project (`~/git/first-project`, a git repo when the `git`
   block is in the plan), pre-trust it, copy a
   friendly first message to the clipboard (survives the sign-in - paste it with
   Cmd+V on macOS, Ctrl+Shift+V on Linux) and save it as `first-message.txt` in that
   folder, then launch the agent. A browser opens for sign-in - that one prompt
   stays.

Everything is idempotent: run it again and already-done steps are skipped; a
symlink already pointing at the canonical file is left alone. vibe never scribbles
in files you own - if the canonical file or a real agent config already exists, it
backs off and points you at it (use `--force` to replace: real files are moved to
`.bak` first). The one exception is the PATH line in step 6, which is appended and
marked rather than merged into anything.

If any step fails, the ending says so and names what failed. "Setup complete." is
only ever printed when nothing warned.

### Removing it

The PATH edit is the only change vibe makes outside its own config paths.

On **macOS and Linux** it is a line in a file you own, wrapped in markers, so
removing it is mechanical - delete these three lines from `~/.bashrc`, `~/.zshrc` or
`~/.config/fish/config.fish`:

```text
# >>> vibe-setup >>>
export PATH="$HOME/.local/bin:$HOME/.codex/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
# <<< vibe-setup <<<
```

On **Windows** it is your account's PATH (the per-user environment, `HKCU\Environment`),
because the CLI agents install into your home folder and their installers persist
nothing. A registry value has nowhere to put a comment marker, so removal means
deleting the two folders vibe added, by name: `%USERPROFILE%\.local\bin` and
`%USERPROFILE%\.codex\bin`. Search for "Edit environment variables for your account",
select each one under **Path**, and delete it. Anything else on that PATH was put
there by an installer, not by vibe.

Everything else lives under `~/.agents/`, `~/.claude*`, `~/.codex/`, `~/.local/`
and `~/git/first-project`.

On **Linux** the shape is identical; only how things are acquired differs. There is
no Homebrew: the agents install with their vendors' own Linux one-liners (which work
out your CPU and libc themselves), and `gh`, Node and pnpm come from **mise**, into
your home folder, with no admin password. `git` is the one exception - there is no
portable way to install it in user space, so it comes from whichever system package
manager the machine has (`apt-get`, `dnf`, `pacman`, `zypper`, found by asking, not
by reading a distro name), and that is the one step that needs your password. The
Claude desktop app installs from Anthropic's apt repository on Debian/Ubuntu, with
its signing key's fingerprint checked before the repository is trusted; the ChatGPT
app and GitHub Desktop have no official Linux build, so those blocks simply do not
appear in the plan.

On **Windows** the shape is identical too; the OS-specific bits differ: installs go
through winget + the CLIs' own PowerShell installers (no Homebrew), and instead
of a symlink each agent is linked to the canonical file its own way - Claude via
an `@import` line in `~/.claude/CLAUDE.md`, Codex via a physical copy of
`~/.codex/AGENTS.md` (Codex has no import). PATH is persisted to your account's
environment rather than to a startup file: everything winget installs is put on PATH
by its own installer, but the CLI agents install into your home folder and persist
nothing, so vibe adds those two folders itself. The clipboard paste is Ctrl+V.

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
run the setup now. The emitted command inherits the run's `BUMP_REF`: pin the
run (`BUMP_REF=<sha> … --build`) and the paste carries the same `BUMP_REF=<sha>`
prefix, so a workshop stays reproducible.

## Pinning (workshops)

An unpinned run uses `main`. For a reproducible workshop, pin the whole repo to a
commit SHA with `BUMP_REF` - vetted source is the audit layer:

```bash
BUMP_REF=<sha> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)" _ claude starter
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
- How Linux is supported without a distro table anywhere, and what was rejected -
  distro-family cells, Homebrew on Linux, Nix, machine profiles:
  [docs/adr/0002](docs/adr/0002-linux-support.md).
- Why the Windows PATH edit is a registry value rather than a startup-file line, what
  that costs at removal time, and what was rejected - `setx`, the PowerShell
  `$PROFILE`, machine scope:
  [docs/adr/0005](docs/adr/0005-windows-persists-path-too.md).

## Development

Two spines, twin-authored against one shared fixture contract so they can't
drift: **bash** (macOS + Linux, targeting `/bin/bash` 3.2 — the oldest bash in the
support set) and **PowerShell** (Windows, targeting **Windows PowerShell 5.1** — the
default shell on a fresh Windows, not pwsh 7). Blocks are single-sourced: per-OS
install/check live in block metadata as data
(`CHECK_MAC`/`INSTALL_LINUX`/`INSTALL_WIN`/…); only the thin runner + the pure
resolver are authored twice.

One rule keeps the OS spread from leaking into code: **a portable command is a cell;
anything that differs by machine is a `blocks/*/apply.sh`; anything that cannot be
done honestly is absent.** A deny-grep in `tests/meta_schema.bats` enforces it — no
distro token (`ubuntu`, `apt-get`, `/etc/os-release`, …) may appear in a meta cell or
anywhere under `lib/`.

One asymmetry to know when writing a `CHECK_*` cell: a POSIX cell is read by its
**exit status**, a `CHECK_WIN` cell by the **truthiness of what it returns** — so a
Windows cell that emits something unconditionally is permanently "satisfied" and its
install never runs (hence the `| Select-String <id>` in the winget cells).

Tooling via `mise`:

```bash
# bash spine (macOS + Linux)
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
`Contract.Tests.ps1`). `BUMP_OS` is the seam that lets one host exercise every
lane: the Windows e2e (`Apply.Tests.ps1`) drives the applier in-process with
`BUMP_OS=win`, and the Linux cells and script tails are asserted the same way from
a Mac.

**Support contracts (mechanically enforced):** bash stays 3.2-clean (no
associative arrays / `mapfile` / `${v,,}`); PowerShell stays 5.1-clean — no
`$IsWindows` outside `lib/os.ps1`, no 7-only syntax (ternary, `??`, `&&`/`||`) —
gated by `PSUseCompatibleSyntax`/`PSUseCompatibleCommands`/`PSUseCompatibleTypes`
against the bundled 5.1 profile in `lint-ps`, plus a windows-latest 5.1 smoke.

CI runs three lanes for the faked suite: `macos-latest` (the real bash 3.2 floor + the
pwsh pure core), `windows-latest` (the PowerShell spine on real Windows), and
`ubuntu-latest`, which runs the bats suite inside `ubuntu:24.04`, `debian:12`,
`fedora:42` and `archlinux:base` under bash 5.

### Real installs, on pristine machines

Fakes cannot reach **acquisition**: whether a vendor installer still exists and still
works, whether the thing people actually paste runs end to end, whether a desktop app
really installs, whether the sudo password prompt fires. So a separate set of lanes
really installs from vendor URLs into machines that have never seen vibe. Rationale
and rejected alternatives: [docs/adr/0003](docs/adr/0003-real-installs-on-pristine-machines.md).

```bash
mise run vm-test-linux    # the container lanes (~10 min; needs a running colima)
mise run vm-test-macos    # the pristine-Mac lanes (needs tart + a 23 GB image)
mise run vm-test          # everything, 30-60 min
mise run vm-clean         # reap leftover guests and log bundles
```

Prerequisites, never auto-installed - a harness that silently installs a hypervisor
has the same manners problem vibe exists to avoid:

- **colima** running (`colima start`) for the container lanes.
- **tart** and **sshpass** for the macOS lanes, plus `mise run vm-image-macos` once for
  the 23 GB `macos-tahoe-vanilla` image (~30-43 GB resident). Lanes run serially: one
  macOS guest at 6 GB plus colima's own VM does not fit twice on 16 GB.

The lane matrix is data in [`tests/real/lanes.tsv`](tests/real/lanes.tsv), read by the
local driver **and** by CI, so both run the same thing:

| lane | machine | what only it covers |
| --- | --- | --- |
| `ubuntu-base` | `ubuntu:24.04` | the Claude desktop app from Anthropic's apt repository, signing key and all |
| `ubuntu-no-curl` | `ubuntu:24.04` minus curl | the wget fallback the Linux paste is shaped around |
| `ubuntu-no-git` | `ubuntu:24.04` minus git | installing git through the system package manager |
| `ubuntu-paste` | `ubuntu:24.04` | the **real paste** on Linux: the `vibe` bootstrap, the tarball fetch, and the `BUMP_REF` pin - and the apply-vs-paste differential against `ubuntu-base` |
| `debian-codex` | `debian:12` | Codex, and its sandbox diagnostic on a restricted-userns kernel |
| `debian-install-sh` | `debian:12` | the legacy `install.sh` entry point with no ids |
| `fedora-safer` | `fedora:42` | a non-apt distro, pnpm, and the `safer-installs` config |
| `ubuntu-password` | `ubuntu:24.04`, password sudo | the **sudo password prompt** - every other lane is NOPASSWD or root |
| `arch-base` | `archlinux:base` | `pacman` as the manager that installs git. x86-only upstream, so it reports class 2 on Apple Silicon |
| `macos-vanilla` | Tart, vanilla Tahoe | the only genuinely first-time Mac: Homebrew, the Xcode CLT, casks |
| `macos-vanilla-paste` | Tart, vanilla Tahoe | the real paste, fetching `vibe` from the commit under test |
| `macos-drift` | `macos-latest`, de-brewed | CI only, weekly. **Drift detection, not a pristine Mac** |
| Windows | `windows-2025` + `windows-11-arm` | CI only: winget, and PATH via the registry rather than any rc file. Twice, like every other lane - but hand-rolled in the workflow rather than a row here, which is a standing drift risk: [docs/adr/0004](docs/adr/0004-the-windows-lane-is-not-a-row.md) |

How a lane decides it worked: a guest-side **precheck** measures the machine before
anything runs, a guest-side **probe** measures it again afterwards and emits a
normalised state manifest, and one **pure** judge turns that plus the resolved block
list into TAP. The two measurements matter as much as either alone: "git resolves in
a fresh shell" is true on a machine that shipped git, so the judge asserts the
**delta** and names whose doing each pass was. The judge
touches no machine, so its assertions are unit-tested over fixture manifests in the
fast suite (`tests/real_judge.bats`) - a wrong assertion is caught by `mise run check`,
not by a 40-minute lane run. It asserts only what a fake cannot reach; everything else
is proved by making runs that *ought* to agree produce an identical manifest: run 1
against run 2 on every lane, `apply.sh` against the real paste on every image that
has both rows, and the one PATH line against itself across every POSIX lane. The
cross-lane half runs locally through `drive.sh` and in CI through a job that
collects the manifests every lane uploaded.

Three exit classes, not pass/fail, because a lane that reports "upstream moved" as
"vibe is broken" is a lane that gets muted: **1** an assertion failed, **2**
infrastructure (a guest, an image, a vendor URL), **3** a harness bug. No retries
anywhere. A class-1 failure keeps the guest alive and prints how to reattach; every
non-zero class leaves a log bundle.

Class 2 is reported without going red, which is what stops the lanes being muted -
and is also how *every* leg failing the same way could read as a green tick. So each
lane writes a `lane.verdict` counting the assertions that actually ran, and a summary
job aggregates them: a matrix where **no** lane reached a judgement fails, and so does
one where a declared lane never reported. It is the same rule the judge applies to a
single lane ("a lane that asserts nothing cannot pass"), one level up.

The verdict also records how long each apply took, and the summary names a lane whose
slowest apply is far outside the median. Reported, never asserted - a timing assertion
in CI is a flake generator, and what this is for is pointing at a transcript worth
reading.

Two caveats worth stating plainly. The vanilla macOS image has **Gatekeeper disabled**
and passwordless sudo baked in, so it is pristine with respect to Homebrew but *more
permissive* than a real Mac - a cask install cannot hit a "developer cannot be
verified" refusal there, and macOS's own password path is not exercised. And the
container images are barer than any real desktop, so a lane adds a package to its
minimum only when a real machine of that family already ships it.
