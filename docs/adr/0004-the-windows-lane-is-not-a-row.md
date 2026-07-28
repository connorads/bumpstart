# 0004 - The Windows lane is not a row, and that is the drift

The real-install matrix is DATA: `tests/real/lanes.tsv`, read by the local driver and
by CI, so "local and CI run the same thing" is mechanical rather than aspirational.
Windows is the exception. Its lane is hand-rolled in YAML, doing in
`.github/workflows/ci.yml` what `tests/real/lanes/run.sh` does in shell for every
other lane. This records why it stays that way for now, and what it costs.

Extends [0003](0003-real-installs-on-pristine-machines.md), which chose the matrix-as-data
shape and made Windows CI-only.

## Context

0003 decided Windows is CI-only, and it was right to: local Windows means UTM/QEMU
with a hand-authored `autounattend.xml`, swtpm and the 24H2 ARM ISO, to hand-build
the one platform GitHub hosts pristine for free. Nothing here revisits that.

What it did not decide was whether the CI-only lane should still be a **row**. It
became a second copy of the lane runner instead, and every Windows finding in the
round that produced this record is a drift between those two copies of one rule, at
maximum distance from each other:

- **No precheck at all.** Every other lane measures the machine before the run, so
  the judge can assert a delta. The Windows lane wrote one hand-made line
  (`precheck.vibe_marker absent`) and nothing else - so `shell.regpath.git 1` was a
  fact about the runner image, not about vibe. The runner images ship Git, Node and
  gh on the Machine PATH, so `INSTALL_WIN` for `Git.Git`, `OpenJS.NodeJS.LTS` and
  `GitHub.cli` is executed by no lane in the project.
- **It ran once.** Against `ci.yml`'s own "Every lane runs twice", against 0003, and
  against the README. That matters more than it looks: `judge.sh` deliberately keeps
  its assertion set small *on the grounds that the differentials cover the rest*, so
  a lane with no second run has a far weaker oracle than the record implies. A second
  `winget install` erroring, a duplicated `@<canonical>` import line and a second
  registry PATH append were all undetectable.
- **A self-check where both sides come from the same resolver.** The lane resolves
  its expected block list with `tests/helpers/resolve_driver.sh`, and `judge.sh`
  compares that against the manifest's `blocks` key - which the workflow wrote from
  the same variable. The harness self-check that catches a mismatch on every other
  lane is vacuous here.

Three of those are fixed in the same round as this record. The fourth is inherent:
they will keep happening, one per round, for as long as there are two copies.

## Decision

**The Windows lane stays hand-rolled in YAML, and this record is the standing
statement of what that costs.** Fix the drift as it appears; do not pretend the
matrix covers Windows.

The reason is not effort. It is that `lanes/run.sh` is a bash program driving a POSIX
guest port, and the Windows lane is PowerShell 5.1 all the way down:

- Every command string the runner sends is POSIX sh. A `windows` adapter would have
  to translate each one, which means the port stops being "run this string" and
  becomes "run this string, unless the adapter is Windows".
- `guest_exec_root` has no analogue: there is no `sudo`, and the elevation model is a
  different shape, not a different command.
- The entry point is `powershell.exe -File lib\apply.ps1`, and the 5.1 floor is the
  thing under test - so the adapter would have to be careful about which shell runs
  what, on a spine whose whole point is that the runner's default pwsh 7 must not be
  used.
- `probe.ps1` already exists and already emits the same manifest. The judge is
  already shared. The part that is duplicated is the LANE LIFECYCLE, which is the
  part most entangled with the guest port.

So the honest position is that a `windows` guest adapter is a real piece of design
work, not a refactor, and doing it badly would put a Windows special case inside the
port that three other adapters have to read past.

**What holds the line meanwhile**, so the drift is visible rather than silent:

- `manifest_version`, asserted by the judge. A Windows manifest that stops carrying
  what the judge needs is a harness bug with a message, not a page of "nothing was
  measured".
- One judge, one probe contract, one `manifest_state_subset`. The Windows lane's
  idempotence differential is the same function every POSIX lane uses.
- `lib/measure.ps1` is the twin of `lib/measure.sh` and is held to it by a Pester
  case that reads the tool list out of the bash file.
- This record. The next Windows finding should be read as evidence about the shape,
  not as an isolated bug.

**The condition that flips this decision:** a second Windows lane. One hand-rolled
copy of the lane runner is a cost; two would be the same cost again, and at that
point the adapter is cheaper than the duplication it removes. The other trigger is
the local Windows guest 0003 deferred - if UTM/QEMU ever becomes worth it, the
adapter has to exist anyway, and it should be written once for both.

## Considered Options

| approach | what it costs | what it buys |
| --- | --- | --- |
| **Hand-rolled YAML** (chosen) | one drift per round, found by review rather than by the harness | no Windows special case inside the guest port |
| A `windows` guest adapter | translating POSIX command strings per adapter, or a port that is no longer one interface | a lanes.tsv row; every rule applied once |
| A second lane runner, `run.ps1` | two full lane runners to keep in step - the exact thing lanes/run.sh exists to avoid | native PowerShell throughout |
| Drop the Windows lane | the only real Windows install anywhere, and the only test of that spine's acquisition | nothing worth having |

**A second lane runner is the option that looks easiest and is worst.** `run.sh`'s
own header names the reason it is one runner: "a Linux script and a near-identical
macOS one would drift the moment either was touched". A `run.ps1` is that, with the
drift guaranteed rather than likely, because the two would not even be in the same
language.

## Consequences

- The README's lane table lists Windows without a lane name, because it has none.
  That is accurate and should stay that way until it does.
- `verdicts.sh` cannot hold the Windows lane to account the way it does the others:
  the Windows job writes no `lane.verdict`, so "did the suite prove anything" is
  answered for Linux and macOS only. A Windows job that silently stopped asserting
  would be caught by review, not by the harness. That is the sharpest edge of this
  decision and the first thing to fix if the lane grows.
- Anything added to `lanes/run.sh` has to be considered for the Windows job by hand.
  The precheck, the second run and the per-run `lane.tsv` all had to be, in this
  round.
