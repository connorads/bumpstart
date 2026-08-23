# 0003 - Real installs, on pristine machines

bumpstart's whole claim is that one paste turns a machine nobody has touched into a working
agent setup. Every test asserts that against fakes. This adds four lanes that run the
**real** installers against machines that have never seen bumpstart, driven by
`mise run vm-test` locally and by CI, with **one pair of guest-side verify scripts** as
the contract and **no orchestration framework at all**.

Extends the testing posture in [0002](0002-linux-support.md), which named Ubuntu Desktop
and WSL as "a documented manual checklist, because hosted runners have neither". One of
those two is now testable.

## Context

The faked suite is right and stays the fast gate: PATH-shadow fakes on bash, shadow
functions on PowerShell, one `resolve-cases.tsv` locking the twin resolvers. It runs in
seconds, needs no network, and catches the whole class of bug that lives in resolution
and composition.

It cannot, structurally, reach the class that lives in **acquisition**. Exactly one real
install exists today - the weekly `linux-real-install` job in a bare `ubuntu:24.04` -
and it proves the single most important thing (a fresh login shell finds the tools) on
one distro, for one block pair, with no desktop app and no password.

What no fake can prove:

1. **The vendor installers still exist and still work.** Every `INSTALL_*` cell is a URL
   someone else controls. A fake asserts we invoked it, never that it succeeded.
2. **The bootstrap.** `tests/e2e.bats` targets `lib/apply.sh` directly, by design. The
   `bumpstart` / `bumpstart.ps1` fetch path - tarball, `BUMP_REF` pin, wget fallback, layout check
   - is only unit-tested. The thing people actually paste has never run end to end.
3. **PATH persistence into a *new* shell** - and *which* new shell, see below. POSIX
   only: the PowerShell spine persists no PATH at all (there is no `shellpath.ps1`;
   the only PATH code in `lib/*.ps1` is the in-run `$env:PATH` prepend), so Windows
   relies entirely on each installer's own registry edit. That is a different claim
   and needs a different measurement - the User-scope registry PATH, never
   `$env:PATH`, which the harness's own `$GITHUB_PATH` additions would mask.
4. **Desktop apps.** `brew install --cask`, `winget`, and the Anthropic apt repository
   with its fingerprint check.
5. **The sudo password prompt.** 0002 made privilege `apply.sh`-owned precisely because
   `spin` erases a password as it is typed. Nothing tests that, because every container
   runs as root and every VM tool defaults to passwordless sudo.
6. **0002's own headline finding.** "24.04 and 26.04 ship neither `curl` nor `git`" is
   correct for the *Desktop* ISO. But `docker run ubuntu:24.04` is the server/cloud
   rootfs, which **has** curl. So the wget fallback - the reason the Linux paste is
   shaped the way it is - has never once run on a machine that lacks curl.

**The login-shell trap, which decides how we assert.** Three shells people call "a fresh
shell" source three different things:

| invocation | sources |
| --- | --- |
| `bash -lc` (login, non-interactive) | `~/.profile` only |
| `bash -ic` (non-login, interactive) | `~/.bashrc` only |
| `bash -c` | nothing |

Layered on Debian/Ubuntu's `/etc/skel`: `.profile` sources `.bashrc` **only when
`$BASH_VERSION` is set**, and `.bashrc` opens with `case $- in *i*) ;; *) return;; esac`.
So an installer appending PATH to `.bashrc` works perfectly in a real terminal and is
**invisible to `bash -lc`**; writing to `.profile` inverts the result. One assertion
cannot see both. (Relatedly, stock `.profile` adds `~/.local/bin` only if that directory
already exists when it runs.)

**Four facts constrain the shape, and three of them were surprises:**

- **Nothing built on Apple's Virtualization.framework can run Windows** - no vTPM for
  non-macOS guests, and ARM WinPE ships no virtio disk driver, so the guest cannot read
  the disk it booted from. That rules out Tart and Lima-vz for Windows entirely.
- **`bumpstart` is public**, so GitHub's macOS and Windows runners are free and
  unlimited - including **`windows-11-arm`, the only Windows 11 *client* image available
  from any CI vendor**, hosted or otherwise. Everyone else sells Server 2022/2025.
- **There is no clean hosted macOS and GitHub says there never will be**
  ([runner-images#222](https://github.com/actions/runner-images/issues/222)). Homebrew,
  Node and git are preinstalled; the managed alternatives (Depot, Blacksmith, Namespace,
  Codemagic) all sell image *parity* with GitHub, so none of them is cleaner.
  `ghcr.io/cirruslabs/macos-tahoe-vanilla` is the only pristine macOS obtainable
  anywhere - verified: 23 GB, 96 layers, and zero occurrences of "brew" in its Packer
  template.
- **The host is 16 GB RAM / 64 GB free.** Apple's SLA allows two concurrent macOS guests;
  RAM allows one. A macOS image and a Windows image do not both fit.

## Decision

**Four lanes, one contract.**

| lane | where | pristine via | covers |
| --- | --- | --- | --- |
| Linux ×4 distros | local + CI | new container | arm64 local, x64 in CI; **no-curl/no-git** and **password-sudo** axes |
| macOS | local, Tart | `tart clone` of `macos-tahoe-vanilla`, CoW, discard | the only genuinely first-time Mac |
| macOS drift | CI `macos-latest`, weekly | scrub Homebrew + Xcode CLT first | vendor drift, not a clean Mac |
| Windows | CI only | new VM per job | `windows-11-arm` (client, ARM) + `windows-2025` (Server, x64) |

**The contract is a probe/judge split, and the split is the load-bearing part.**
`tests/real/probe.{sh,ps1}` run *inside the guest* and emit a normalised state
manifest; `tests/real/judge.sh` is **pure** - manifest plus the resolved block list in,
TAP out - and touches no machine at all. No test framework is installed into a pristine
machine: the first thing a harness installs must not be a dependency of the thing it is
testing.

Why not one verify script per spine, which is what this record first said: the
judgement logic (which blocks are expected, which warnings are legitimate, which keys
must agree) is then **unit-testable over fixture manifests in the existing fast bats
suite**, no guest required. A wrong assertion is caught by `mise run check` on every
commit rather than by a 40-minute lane run. Gather, decide, report - in that order,
once. It also means ONE judge decides every lane including Windows, so the two spines
cannot drift on what "it worked" means.

The judge asserts each harness path's **target** and the canonical file's **content**,
not mere existence, and on POSIX it measures PATH across **all three** shell
invocations above rather than picking one - `bash -lc` as a `# TODO`, so the known gap
is documented and breaks loudly if it changes.

**macOS uses `-vanilla`, never `-base`.** `macos-tahoe-base` preinstalls brew, mise,
node, git, gh and yarn - nearly the exact set bumpstart installs. Testing against it is a
guaranteed false pass.

**The vanilla image is pristine w.r.t. Homebrew, NOT w.r.t. Gatekeeper.** Its Packer
template disables Gatekeeper (`spctl --global-disable`, asserted in the build), so the
guest is *more permissive* than a real Mac: a cask install cannot hit a "developer
cannot be verified" refusal there. It also bakes in `admin ALL=(ALL) NOPASSWD: ALL`, so
macOS's own password path (`lib/brew.sh`) is not exercised either. Both are stated in
CONTRIBUTING.md, because a caveat only in a commit message is a caveat nobody reads. Tart is `openai/tart` under FSL-1.1-ALv2 (Apache-2.0 after two
years), free for this use; `tart.run/licensing` still advertises the retired paid tiers
and is stale. Reset is `tart clone`, which is an APFS `clonefile` and therefore instant.

**Windows is CI-only, deliberately reversing "local first" for one lane.** Local Windows
means UTM/QEMU with a hand-authored `autounattend.xml`, swtpm, and the 24H2 ARM ISO - a
day of work and 12-15 GB competing with the macOS image, to hand-build the one platform
GitHub hosts pristine for free. Encoded in the workflow, because each is a silent
failure: **`shell: powershell`** (the runner default is pwsh 7, which would defeat the
5.1 floor these tests exist to protect), **`timeout-minutes`** (winget currently hangs
rather than failing), **bootstrap winget on `windows-11-arm`** (in-box on Server 2025,
absent there), and append `%LOCALAPPDATA%\Microsoft\WinGet\Links` to `$GITHUB_PATH`.

**The Desktop gap is synthesised, not virtualised.** `apt-get remove -y curl` (and a
no-git leg) as a matrix axis on the existing container lanes. It reaches the actual code
path for minutes of work; a real Desktop ISO costs a day and gigabytes to additionally
reach snapd and a session bus, which nothing in bumpstart touches yet.

**The password prompt is asserted through an askpass helper, not a TTY driver.** A
non-root user with a password-required sudoers entry, and a stub that logs the prompt
text and counts invocations - so the assertion is the actual promise ("asks once, and
only if git needs installing") rather than keystroke choreography. `sudo -k` in setup, or
credential caching makes the count lie. The stub fails closed, so an unstubbed prompt is
a loud failure rather than a six-hour hang.

**One exception to "the lanes shadow nothing", and it was forced.** This record first
said `SUDO_ASKPASS` alone would be enough, on the strength of sudo's own man page: the
helper is used "if no terminal is available or if the `-A` option is specified". Measured
on sudo 1.9.15p5 (Ubuntu 24.04), that is false - with no terminal and `SUDO_ASKPASS`
exported, sudo refuses with "a terminal is required … or configure an askpass helper" and
never runs it. `Path askpass` in `/etc/sudo.conf` does not change it either. Only an
explicit `-A` works. So the password lane puts a `sudo` ahead of the real one on PATH
that adds `-A`, and nothing else. It changes how the password is read, not whether
privilege was required, granted, or how many times it was asked for -
`blocks/git/apply.sh` still runs unmodified - and the shim is never on the probe's PATH.
`tests/real_guest_contract.bats` asserts the man page is still wrong, so the day sudo
starts honouring the variable, the shim can go.

**No orchestrator.** Plain shell plus mise tasks, whose `sources`/`outputs` caching is
already the "don't rebuild the golden image" primitive.

**Every run hits vendor URLs live.** Catching upstream drift is the point; a caching
proxy would remove the only thing these lanes uniquely see.

**Pristine only, and failures keep the corpse.** A failed guest survives with a log
bundle and a printed reattach command; a passing guest is discarded immediately.

**Matrix per lane:** each lane's paste is a row in `tests/real/lanes.tsv`, run twice for
idempotence. Across the whole matrix every block is really installed at least once -
spread over lanes, not repeated in each - and the matrix is DATA read by both the local
driver and CI, so "local and CI run the same thing" is mechanical rather than
aspirational. Idempotence is a manifest **differential**, not a second set of
assertions: "no new warnings, no new file changes", not identical output, because an
unauthenticated run sets no git identity, so `git`'s SATISFIED cell stays false and the
block legitimately re-runs.

**Non-targets, named:** authentication and sign-in of any kind; GUI driving and
screenshots; non-pristine starting states; upgrade and back-compat paths (nothing is
released yet); x86-64 anywhere but CI; **Windows 11 x64 client**, which no lane reaches
and no vendor hosts; WSL 2, which stays 0002's manual checklist because it needs nested
virtualisation inside an ARM Windows guest.

## Considered Options

**How to decide "it worked" - four ways, and why the small one won.** The oracle is the
load-bearing choice: four lanes and CI couple to it, and getting its *scope* wrong is
what makes a harness rot.

| approach | simplicity | cost when blocks change | failure behaviour |
| --- | --- | --- | --- |
| **Small expectations + differential** (chosen) | one probe, one pure judge, a manifest diff | **none** - new blocks are covered by the diff automatically | the diff names the differing key |
| Full hand-written assertion set | one script, but long | every block change touches the faked suite *and* this | precise |
| Re-run the existing bats suite un-faked in the guest | reuses assertions | none | precise |
| Nothing new - extend the weekly job's inline greps | ~20 lines total | none | "something broke" |

The **full hand-written assertion set** is what was drafted first, and it is the trap:
`instructions.bats` (12 tests), `shellpath.bats` (8), `trust.bats` (14) and `e2e.bats`
(34) already prove canonical assembly and ordering, symlink creation and idempotence,
the marker line across zsh/bash/fish, the byte-identical second run, both trust
preseeds and the starter repo. Re-asserting those against a real machine buys almost
nothing and taxes every future block twice.

**Reusing the bats suite in the guest** is eliminated on demonstrated infeasibility, not
preference: it is built on `setup_isolated_env` plus PATH-shadow fakes and asserts
`lib/` functions rather than a real machine. Its fakes *are* its design.

**The do-nothing option** is genuinely close, and it prices the rest. Three greps would
catch the single most valuable thing - a fresh shell finding the tools - and on a
one-afternoon budget that is what to build. It loses because it cannot tell a vendor
installer regression from a bumpstart bug, and cannot see the desktop-app or rc-line failures
at all.

So: a deliberately **small** hand-written expectation set covering only what a fake
structurally cannot reach, plus **differential agreement** for everything else - two
runs that ought to agree must produce an identical normalised state manifest. The repo
already locks two implementations to one fixture (`resolve-cases.tsv`), so this
introduces no new concept. The cost it buys is real and named: the manifest needs
careful normalisation, too strict and every version bump is red, too loose and the
differential proves nothing - which is why the subset choice is pinned down by unit
tests rather than by judgement at review time.

**Ansible, with Molecule as the harness.** The obvious answer, and the one asked for
first. Rejected on a specific mechanical failure, not on taste: Molecule's idempotence
check re-runs converge and greps for `changed=0`, our converge is one
`command: bash install.sh`, and `command` always reports changed. So the step either
fails unconditionally, or gets `changed_when: false` and becomes **a test that cannot
fail**, or gets a hand-written `changed_when` parsing our own stdout - at which point we
wrote the assertion and Molecule contributed a directory layout. Molecule tests
*Ansible's* idempotence; ours is a filesystem property, which is what bats and Pester are
already for. Ansible-the-provisioner is also the wrong tool for a project whose entire
subject is provisioning without one.

**Packer to build the golden images.** The right tool, an order of magnitude out on
scale. It earns its keep building one image for many targets, or giving a team a
reviewable spec. We have one maintainer, one machine, and a `-vanilla` image someone else
already publishes; the Tart builder's job here reduces to `tart pull`.

**Vagrant.** Cannot reach the hardest target at all - no arm64 Windows box exists in the
registry - and gets us Linux guests that containers cover better. Also no stable release
since 2025-08-21.

**Test Kitchen.** Genuinely revived (v4 removed Chef entirely, Sous Chefs now maintain
it), which makes it seductive. Rejected: no Apple Silicon driver exists, so we would
write one in Ruby; it has no snapshot primitive (create/converge/verify/destroy only);
and InSpec, its natural verifier, is now under a Chef EULA including `inspec-core`.

**Dagger.** Structurally cannot drive VMs - no device passthrough in the API, and on this
host the engine itself runs inside a Linux VM with no `/dev/kvm`. It solves the Linux
third we already solved in fifteen lines of `docker run`. Earthly is unmaintained since
2025.

**Nix VM tests (`testers.runNixOSTest`).** Superficially perfect for this repo's
neighbours. Rejected hardest of all: the guest is **NixOS**, with no FHS, no `/usr/bin`,
a read-only store and no apt or dnf. bumpstart would fail for reasons that say nothing about
Ubuntu - and 0002 already rejected Nix as a substrate for the same class of reason.

**A local UTM Windows guest as well.** `utmctl start --disposable` is the cleanest reset
primitive found anywhere. Deferred, not dismissed: it becomes worth its day of setup the
first time a Windows failure needs interactive debugging that a CI log cannot give.

**A self-hosted GitHub runner on this Mac, driving ephemeral Tart VMs.** Turnkey projects
exist (Tartelet, Cilicon) with 25-30 s recycle times. Rejected on security, for this repo
specifically: GitHub's own guidance is that self-hosted runners "should almost never be
used for public repositories", `pull_request_target` bypasses the approval setting
entirely, and one merged typo fix clears the first-time-contributor bar permanently. An
ephemeral VM restores the clean-machine property but still executes a stranger's PR on
this laptop, on this network. Tart stays a local task, not a runner.

**A fresh macOS user account instead of a VM.** Real, in use by other dotfiles repos, and
free on a hosted runner. Kept as a possible CI refinement, rejected as the *pristine*
mechanism: it does not reset `/opt/homebrew`, which is the single most important thing to
reset; on Apple Silicon the new user is not in `admin` and so lacks the group ownership
Homebrew expects; and setting a password non-interactively is broken on recent macOS.

**The de-brewed `macos-latest` job alone, with no local VM.** Zero disk, zero setup.
Rejected as *sufficient*: scrubbing a runner is best-effort, so the genuine first-time-Mac
path - the entire audience of this project - would remain untested. Kept as the weekly
drift lane, which is a different job.

**A real Ubuntu Desktop ISO in a Lima/qemu VM.** The only way to reach snapd, flatpak and
a desktop keyring, and the only true test of 0002's Desktop claim. Deferred behind
synthesis: it costs a day and several GB, Lima's snapshot support is unimplemented on the
`vz` driver so it forces the slower `qemu` backend, and no current block touches snap or
flatpak. Revisit when one does.

**Paid Apple Silicon CI** (Codemagic ~$0.114/min, Depot/Blacksmith/Namespace
$0.05-0.08/min, EC2 Mac at $1.23/hr behind a 24-hour minimum and up to 4.5 hours of
scrubbing, Scaleway at €0.11/hr behind a 24-hour delete block, MacStadium Orka at
$149/mo+). Rejected: none ships a Homebrew-free image, so the money buys speed we do not
need and not the pristineness we do. Orka is the sole exception in offering plain base
images, at a price and an operational weight far beyond one maintainer.

**bats and Pester inside the guest instead of a verify script.** Richer output, and it
matches the existing suite's idiom. Rejected: it requires installing a test framework
into every pristine machine, which is itself an install that has to work first, and there
is no bats on Windows. TAP from a plain script gives up assertion helpers and keeps the
guest honest.

## Consequences

- **A new local prerequisite:** Tart, plus a 23 GB pull and ~30-43 GB resident. Documented
  in CONTRIBUTING.md, never auto-installed - a harness that silently
  installs a hypervisor has the same manners problem bumpstart exists to avoid. Note nixpkgs
  currently supplies tart 2.30.6 against 2.34.0 upstream.
- **One macOS guest at a time**, at 6 GB. Apple's floor is 4 GB and Tart hard-codes it
  because guests freeze below it; the macOS and Windows lanes could never have run
  concurrently on this host anyway.
- **Windows has no local reproduction path.** A red Windows lane is debugged through CI
  logs and re-runs until the deferred UTM guest exists.
- **Windows 11 x64 client is covered by nothing.** `windows-11-arm` is client-on-ARM,
  `windows-2025` is Server-on-x64; between them the untested slice is client-specific
  behaviour on x64. Local x64 Windows is impossible on Apple Silicon (Parallels' x86
  emulation refuses Windows 11 builds 26100+), and the only better target found -
  runs-on.com's bare `windows-*-base-x64` images - is still Server. Accepted and recorded
  rather than chased.
- **The synthesised no-curl container is not a desktop.** It reaches the wget fallback and
  nothing else: no snapd, no flatpak, no session D-Bus, no keyring. 0002's Ubuntu Desktop
  checklist shrinks; it does not disappear.
- **The weekly macOS CI lane is not pristine and must not be described as such**, or the
  local Tart lane will quietly stop being run.
- **The container images are barer than any real desktop**, so a lane's dependency list
  is a judgement each time. The test applied: a package joins it only when a real machine
  of that family already ships it. `gnupg` on the Debian/Ubuntu legs passes that test;
  so does `libatomic` on Fedora, which mise's prebuilt `pnpm` links and `fedora:42`'s
  rootfs omits while Fedora Workstation has it. Where the container itself cannot work
  otherwise, that is stated too (pacman 7's seccomp sandbox will not start under colima's
  kernel).
- **The Arch lane is CI-primary.** `archlinux:base` publishes no arm64 image, so on Apple
  Silicon it runs emulated x86_64 and the vendors' x64 builds die on missing CPU features
  (Claude Code's Bun binary wants AVX). That is classified as infrastructure, not as bumpstart
  being wrong. `ubuntu-latest` is x86_64, so CI runs it natively; the password axis was
  moved onto Ubuntu so the one lane covering the sudo prompt also runs on a contributor's
  Mac.
- **The first real run found a product gap the faked suite cannot see.** On a genuinely
  minimal Fedora, `pnpm` installs, bumpstart reports "pnpm installed", and the binary cannot
  execute at all (`libatomic.so.1`). Asserting `--version` exits 0 rather than
  `command -v` is exactly what caught it, and it is the shape of finding these lanes
  exist for: a step that succeeds and leaves nothing usable.
- **Runs will fail for reasons that are not our bug** - a vendor URL moving, an installer
  changing, GitHub's `winget` hang. That is the entire value of the lane, so the failure
  output has to distinguish "bumpstart is wrong" from "upstream moved", or the lane gets muted.
- **`mise run check` is unchanged** and stays the commit-time gate. `vm-test` is invoked
  explicitly and is expected to take 30-60 minutes.
- Prerequisite landed separately: the repo now has a `mise.lock`. `bats = "1"` had floated
  onto 1.14.0, which changed `run` to honour `set -e` inside helper functions - drift in
  the harness that verifies everything else was the wrong thing to leave unpinned.
