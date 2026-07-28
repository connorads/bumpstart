# 0002 - Linux support, with no distro knowledge in the spine

vibe runs on Linux: Ubuntu, Debian, Fedora, Arch and their derivatives, on x86-64
and arm64, in WSL 2 and in containers. It is added with **no new key dimension** -
the pre-declared `CHECK_LINUX`/`INSTALL_LINUX`/`SATISFIED_LINUX` cells only - and one
rule about where knowledge is allowed to live.

Supersedes the Linux item parked in [0001](0001-axis-as-the-human-taxonomy.md).

## Context

0001 parked Linux on two grounds: no `*_LINUX` cells plus Homebrew being the whole
install substrate, and "no official Linux desktop app exists for Claude, ChatGPT *or*
GitHub Desktop".

The second ground is now one third false: Claude Desktop for Linux shipped as an
official Anthropic beta (apt, Ubuntu 22.04+ / Debian 12+, amd64 and arm64).

The first turned out to be the wrong shape. Both agent CLIs already publish official
Linux one-liners identical in spirit to their mac cells, so nothing needed a Homebrew
equivalent for the critical path. What did need deciding was `gh`, Node, pnpm and
git - and, more importantly, three things larger than any cell:

1. **The paste line did not run on Ubuntu Desktop.** 24.04 and 26.04 ship neither
   `curl` nor `git` (both ISO manifests confirm it; `wget` and `sudo` are present).
   The old paste exited 0 having printed nothing.
2. **Privilege cannot live in a meta cell.** `run_cell` executes cells through
   `spin`, which backgrounds the command and rewrites the terminal line every 0.1s,
   so a sudo password prompt is erased as it is typed. `lib/brew.sh` already worked
   around this on macOS by calling `sudo -v` outside `spin`. `run_block` runs
   `apply.sh` directly, so `apply.sh` is the only place privileged work is correct.
3. **Nothing verified the machine at the end.** A Linux run has many more ways to
   half-fail (dpkg lock, missing package, OOM kill, refused sudo), and the applier
   printed "Setup complete." regardless, then told the user to run a binary that
   might not exist.

## Decision

**Keying.** `CHECK_LINUX`/`INSTALL_LINUX`/`SATISFIED_LINUX` and nothing else. Those
fields were already pre-declared in `lib/meta.sh` and already linted in
`tests/meta_schema.bats`, so the PowerShell spine, `Get-Meta` and the shared
`resolve-cases.tsv` contract fixture are all untouched.

**The rule.** *A portable command is a cell; anything that differs by machine is a
`blocks/*/apply.sh`; anything that cannot be done honestly is absent.* Enforced, not
just documented: a deny-grep in `tests/meta_schema.bats` bans distro tokens
(`ubuntu|debian|fedora|rhel|arch|suse|apt-get|dnf|pacman|apk|zypper|/etc/os-release`)
in any meta cell and anywhere under `lib/`, exempting `blocks/*/apply.sh` as the one
legal home for a package-manager probe.

**Acquisition.** Portable and user-scoped. The agents come from their vendors' own
Linux one-liners (each resolves arch and libc itself, so no arch branching). `mise`
supplies `gh`, Node and pnpm, into `~/.local`, with no password. `gh` in particular is
a statically linked Go binary on every target, which *deletes* the signed-repo keyring
dance rather than expressing it four times.

**git is the single exception,** and lives in `blocks/git/apply.sh`: there is no
portable user-space install, and Ubuntu Desktop ships none. The manager is found by
**capability** - is `apt-get`/`dnf`/`pacman`/`zypper` on PATH - so Mint, Pop!_OS and
openSUSE work without a row of their own.

**`ensure_mise` is the Linux mirror of `ensure_brew`,** called from the same pre-loop
slot, on Linux only, unconditionally. This is what fixes an ordering defect found
while validating the plan: `_kind_rank` puts `auth` at 20 and `tool` at 30, so
`gh-auth` runs *before* the `mise` block, and an `INSTALL_LINUX='mise use -g gh'`
cell would otherwise execute before mise existed. Changing `gh-auth`'s KIND was not
available (`auth` exists so gh signs in before the `git` step reads the identity from
it), and adding a KIND touches the shared contract fixture, which 0001 rejected.

**PATH persistence is applier-owned.** `persist_path` (`lib/shellpath.sh`) appends
one marker-wrapped line to the login shell's rc file, beside `assemble_instructions`
in the same central-effects slot, disclosed at the confirm gate.

**Claude Desktop ships in v1** via `blocks/claude-desktop/apply.sh`, with the signing
key's fingerprint verified in code. No Linux cell. `codex-desktop` and
`github-desktop` get nothing at all.

**WSL 1 is refused** by both platform guards, with the one command that fixes it.

**Non-targets, named:** Alpine and other musl systems, NixOS, WSL 1. The tested set
is narrower than the support claim: CI covers `ubuntu:24.04`, `debian:12`,
`fedora:42` and `archlinux:base`; WSL and Ubuntu Desktop are a documented manual
checklist, because hosted runners have neither.

The Ubuntu Desktop half of that checklist has since shrunk. [0003](0003-real-installs-on-pristine-machines.md)
adds real-install lanes with a **`no-curl` axis** (and a `no-git` one), which is what
finding 1 above actually needs: `docker run ubuntu:24.04` is the server rootfs, so the
wget fallback the Linux paste is shaped around had never once run on a machine lacking
curl. What the synthesised axis still does not reach is snapd, flatpak, a session
D-Bus or a keyring — none of which any block touches yet.

## Considered Options

**A `*_UNIX` cell tier, with macOS migrated off Homebrew onto mise.** One cell serves
both POSIX spines, and `brew install gh` stops being a mac special case. Rejected: it
contradicts the `{MAC,WIN,LINUX}` token set documented as the cross-spine CONTRACT in
`lib/os.sh` and `lib/os.ps1`, and forces an inert PowerShell twin for a tier Windows
can never use. Authoring plain `INSTALL_LINUX` cells that happen to use mise reaches
the same Linux result with the mac spine untouched. Unifying macOS onto mise stays
available later, on its own evidence rather than as a passenger on this change.

**Distro-family cells (`INSTALL_DEBIAN`, `INSTALL_FEDORA`, …).** The obvious shape,
and how most installers do it. Rejected: it makes every derivative a code change -
Mint, Pop!_OS, elementary and Zorin are all Debian-family but none of them *is*
Debian - and it multiplies the cell count by the number of families for tools that
have a portable install anyway. Capability probing answers the same question with one
branch that never needs a new row.

**Capability probes in the runner, so any block could ask "which manager".** A
`vibe_pkg_install` helper in `lib/`. Rejected: it puts distro knowledge in the spine,
where the deny-grep now forbids it, and it invites blocks to reach for a package
manager when a portable install exists. Exactly one block needs it (`git`), and one
caller is not an abstraction.

**Machine profiles (a `profiles/ubuntu-desktop/` dir with per-machine overrides).**
More expressive than cells, and could carry the whole install strategy. Rejected: a
profile has to be *selected*, which means detecting the machine, which is the problem
it claims to solve - and a beginner cannot tell which profile they are.

**Homebrew on Linux, reusing every `*_MAC` cell verbatim.** Zero new cells; the mac
spine becomes the Linux spine. Rejected on several grounds at once: it refuses casks
(so no desktop app), it wants `/home/linuxbrew` and a compiler toolchain, it is a
~500MB substrate for four tools, and it is not how any Linux user expects software to
arrive. A version manager already in the plan (`mise`) does the same job at a tenth
of the weight.

**Nix / home-manager as the install substrate.** Genuinely reproducible, genuinely
cross-platform, and it would pin everything. Rejected: it needs root to install the
daemon, it introduces a language before the beginner has installed a language, and a
failure inside it is unreadable to the person this project exists for. The audience
is someone who has never opened a terminal.

## Consequences

- Adding a Linux install for a portable tool is one `INSTALL_LINUX=` line. Nothing in
  `lib/` and nothing in PowerShell changes.
- **An agent-only Linux plan installs a version manager it never uses** (~10MB,
  root-free), because `ensure_mise` is unconditional. Disclosed at the confirm gate.
  It is the same trade macOS already makes, installing Homebrew for a CLI-only plan.
- **"vibe never edits your shell config" stops being true.** It was already false in
  effect - the Codex installer writes a marked block into `~/.bashrc`/`~/.zshrc`
  today, keyed on `$SHELL`, with no fish branch. Now vibe owns one marked line
  instead, discloses it, and the README says how to remove it. `fixup_path` moving
  before the block loop is what makes Codex skip its own edit.
- **"Setup complete." now means it.** The finish message names what failed when
  anything did, and a failed agent install no longer prints advice to run a missing
  binary. Twin-authored: the honesty fix is not Linux-specific, so shipping it on one
  spine only would create exactly the copy divergence twin-authoring exists to
  prevent.
- `_block_runs` is true on the presence of an `apply.sh`, so `claude-desktop` renders
  a row on Fedora and Arch and then warns. A dim "not on this machine, because …"
  plan footer is the follow-up that fixes that class properly.
- Two pre-existing defects were found while validating this and deliberately **not**
  fixed here, because neither is Linux-specific: the `safer-installs` age gate lands
  *after* the tools it should gate (within-rank order is expansion order, so a plan
  resolves git → mise → node → safer-installs), and the cross-spine contract fixture
  has no OS column, which makes a per-OS `TARGET` divergence structurally uncatchable.
