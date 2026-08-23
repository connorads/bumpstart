# Contributing

## The two spines

bumpstart is twin-authored against one shared fixture contract so the halves cannot
drift: **bash** (macOS + Linux, targeting `/bin/bash` 3.2, the oldest bash in the
support set) and **PowerShell** (Windows, targeting **Windows PowerShell 5.1**, the
default shell on a fresh Windows, not pwsh 7).

Blocks are single-sourced: per-OS install and check live in block metadata as data
(`CHECK_MAC` / `INSTALL_LINUX` / `INSTALL_WIN` / …). Only the thin runner and the
pure resolver are authored twice.

One rule keeps the OS spread from leaking into code: **a portable command is a cell;
anything that differs by machine is a `blocks/*/apply.sh`; anything that cannot be
done honestly is absent.** A deny-grep in `tests/meta_schema.bats` enforces it - no
distro token (`ubuntu`, `apt-get`, `/etc/os-release`, …) may appear in a meta cell or
anywhere under `lib/`.

One asymmetry to know when writing a `CHECK_*` cell: a POSIX cell is read by its
**exit status**, a `CHECK_WIN` cell by the **truthiness of what it returns**. So a
Windows cell that emits something unconditionally is permanently "satisfied" and its
install never runs - hence the `| Select-String <id>` in the winget cells.

## Running the checks

```bash
# bash spine (macOS + Linux)
mise run lint          # shellcheck
mise run lint-actions  # actionlint + zizmor over .github/workflows
mise run test-bash32   # the whole bats suite under /bin/bash (3.2)
mise run check         # lint + lint-actions + test

# PowerShell spine (Pester + PSScriptAnalyzer; run bootstrap once first)
pwsh -File bootstrap.ps1   # install pinned Pester + PSScriptAnalyzer
mise run test-ps           # Pester suite (pure core, shared contract, Windows e2e)
mise run lint-ps           # PSScriptAnalyzer 5.1-floor gate + the $IsWindows grep
mise run check-ps          # lint-ps + test-ps
```

Tests are black-box with fakes - no network, no real installs: PATH-shadow fakes on
bash, shadow functions on PowerShell. The two resolvers are locked to one
`tests/fixtures/contract/resolve-cases.tsv` (driven by `contract.bats` and
`Contract.Tests.ps1`). `BUMP_OS` is the seam that lets one host exercise every lane:
the Windows e2e (`Apply.Tests.ps1`) drives the applier in-process with `BUMP_OS=win`,
and the Linux cells and script tails are asserted the same way from a Mac.

A prompt gated on `[ -t 0 ]` is unreachable from bats, which redirects every test's
stdin. `tty_run` in `tests/helpers/common.bash` supplies a real terminal through
`script(1)`; `require_pty` skips where that is absent.

**Support contracts (mechanically enforced):** bash stays 3.2-clean - no associative
arrays, `mapfile` or `${v,,}`. PowerShell stays 5.1-clean - no `$IsWindows` outside
`lib/os.ps1`, no 7-only syntax (ternary, `??`, `&&` / `||`) - gated by
`PSUseCompatibleSyntax` / `PSUseCompatibleCommands` / `PSUseCompatibleTypes` against
the bundled 5.1 profile in `lint-ps`, plus a windows-latest 5.1 smoke.

## CI

CI runs on pushes to `main`, on pull requests, on manual dispatch, and weekly.

Three lanes cover the faked suite: `macos-latest` (the real bash 3.2 floor plus the
pwsh pure core), `windows-latest` (the PowerShell spine on real Windows), and
`ubuntu-latest`, which runs the bats suite inside `ubuntu:24.04`, `debian:12`,
`fedora:42` and `archlinux:base` under bash 5.

`.github/dependabot.yml` bumps the SHA-pinned actions weekly with a 7-day cooldown -
the Actions arm of the release-age quarantine.

## Real installs, on pristine machines

Fakes cannot reach **acquisition**: whether a vendor installer still exists and still
works, whether the thing people actually paste runs end to end, whether a desktop app
really installs, whether the sudo password prompt fires. So a separate set of lanes
really installs from vendor URLs into machines that have never seen bumpstart.
Rationale and rejected alternatives:
[docs/adr/0003](docs/adr/0003-real-installs-on-pristine-machines.md).

```bash
mise run vm-test-linux    # the container lanes (~10 min; needs a running colima)
mise run vm-test-macos    # the pristine-Mac lanes (needs tart + a 23 GB image)
mise run vm-test          # everything, 30-60 min
mise run vm-clean         # reap leftover guests and log bundles
```

One lane on its own, which is what you want when a judge assertion changes:

```bash
bash tests/real/lanes/run.sh ubuntu-password --out /tmp/lane
```

Prerequisites, never auto-installed - a harness that silently installs a hypervisor
has the same manners problem bumpstart exists to avoid:

- **colima** running (`colima start`) for the container lanes.
- **tart** and **sshpass** for the macOS lanes, plus `mise run vm-image-macos` once
  for the 23 GB `macos-tahoe-vanilla` image (~30-43 GB resident). Lanes run serially:
  one macOS guest at 6 GB plus colima's own VM does not fit twice on 16 GB.

The lane matrix is data in [`tests/real/lanes.tsv`](tests/real/lanes.tsv), read by the
local driver **and** by CI, so both run the same thing:

| lane | machine | what only it covers |
| --- | --- | --- |
| `ubuntu-base` | `ubuntu:24.04` | the Claude desktop app from Anthropic's apt repository, signing key and all |
| `ubuntu-no-curl` | `ubuntu:24.04` minus curl | the wget fallback the Linux paste is shaped around |
| `ubuntu-no-git` | `ubuntu:24.04` minus git | installing git through the system package manager |
| `ubuntu-paste` | `ubuntu:24.04` | the **real paste** on Linux: the `bumpstart` bootstrap, the tarball fetch, and the `BUMP_REF` pin - and the apply-vs-paste differential against `ubuntu-base` |
| `debian-codex` | `debian:12` | Codex, and its sandbox diagnostic on a restricted-userns kernel |
| `debian-install-sh` | `debian:12` | the legacy `install.sh` entry point with no ids |
| `fedora-safer` | `fedora:42` | a non-apt distro, pnpm, and the `safer-installs` config |
| `ubuntu-password` | `ubuntu:24.04`, password sudo | the **sudo password prompt** - every other lane is NOPASSWD or root. Also the only lane that installs `git` with no `github`, so it is where the identity prompt's headless path runs for real |
| `arch-base` | `archlinux:base` | `pacman` as the manager that installs git. x86-only upstream, so it reports class 2 on Apple Silicon |
| `macos-vanilla` | Tart, vanilla Tahoe | the only genuinely first-time Mac: Homebrew, the Xcode CLT, casks |
| `macos-vanilla-paste` | Tart, vanilla Tahoe | the real paste, fetching `bumpstart` from the commit under test |
| `macos-drift` | `macos-latest`, de-brewed | CI only, weekly. **Drift detection, not a pristine Mac** |
| Windows | `windows-2025` + `windows-11-arm` | CI only: winget, and PATH via the registry rather than any rc file. Twice, like every other lane - but hand-rolled in the workflow rather than a row here, which is a standing drift risk: [docs/adr/0004](docs/adr/0004-the-windows-lane-is-not-a-row.md) |

How a lane decides it worked: a guest-side **precheck** measures the machine before
anything runs, a guest-side **probe** measures it again afterwards and emits a
normalised state manifest, and one **pure** judge turns that plus the resolved block
list into TAP. The two measurements matter as much as either alone: "git resolves in a
fresh shell" is true on a machine that shipped git, so the judge asserts the **delta**
and names whose doing each pass was.

The judge touches no machine, so its assertions are unit-tested over fixture manifests
in the fast suite (`tests/real_judge.bats`) - a wrong assertion is caught by
`mise run check`, not by a 40-minute lane run. It asserts only what a fake cannot
reach; everything else is proved by making runs that *ought* to agree produce an
identical manifest: run 1 against run 2 on every lane, `apply.sh` against the real
paste on every image that has both rows, and the one PATH line against itself across
every POSIX lane. The cross-lane half runs locally through `drive.sh` and in CI
through a job that collects the manifests every lane uploaded.

The fixtures under `tests/fixtures/real/` are goldens produced by the probe under
test. Regenerate them from a lane run rather than hand-editing; a hand-edited golden
is a fixture of a machine that never existed.

Three exit classes, not pass/fail, because a lane that reports "upstream moved" as
"bumpstart is broken" is a lane that gets muted: **1** an assertion failed, **2**
infrastructure (a guest, an image, a vendor URL), **3** a harness bug. No retries
anywhere. A class-1 failure keeps the guest alive and prints how to reattach; every
non-zero class leaves a log bundle.

Class 2 is reported without going red, which is what stops the lanes being muted - and
is also how *every* leg failing the same way could read as a green tick. So each lane
writes a `lane.verdict` counting the assertions that actually ran, and a summary job
aggregates them: a matrix where **no** lane reached a judgement fails, and so does one
where a declared lane never reported. It is the same rule the judge applies to a
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

## The README demo

`docs/assets/demo.svg` is a real confirm gate, captured from a container that has
never seen bumpstart - so it shows the plan a beginner sees, not the "already set up"
ticks a maintainer's machine produces. Re-record it whenever the plan output changes:

```bash
termctrl save --format svg --cols 132 --rows 38 --hide-cursor --color always \
  --wait-for "Press Enter to set up" --deadline-ms 240000 -o docs/assets/demo \
  -- docker run --rm -it -v "$PWD:/src:ro" -w /src ubuntu:24.04 bash -c '
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl git ca-certificates >/dev/null 2>&1
    useradd -m -s /bin/bash bumpstart >/dev/null 2>&1
    clear
    exec su bumpstart -c "cd /src && exec bash lib/apply.sh claude starter"
  '
```

It stops at the gate and installs nothing: `--wait-for` captures the frozen screen and
the container is torn down without an answer ever being sent.

One render, not a light/dark pair. termctrl has no theme option and renders a fixed
dark palette, and a terminal screenshot reads correctly on a light page anyway. A
light variant would mean post-processing every colour by hand on every re-record.
