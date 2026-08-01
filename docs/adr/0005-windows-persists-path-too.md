# 0005 - Windows persists PATH too, in the registry rather than a startup file

bumpstart's promise is that after one paste you open a **new** terminal and your tools are
there. The bash spine keeps that promise with one marker-wrapped line in the login
shell's rc file (`lib/shellpath.sh`). The PowerShell spine kept it only by accident:
whatever winget installed was persisted by winget's own installer, and the two CLI
agents - the critical path - were not persisted at all. This records the decision to
persist them, and what the choice of mechanism costs.

Supersedes the claim in [0003](0003-real-installs-on-pristine-machines.md) that "the
PowerShell spine persists no PATH at all"; it does now, and the real-install lane
measures it. Extends [0004](0004-the-windows-lane-is-not-a-row.md), which is where the
gap in *asserting* it is recorded.

## Context

The first Windows real-install run reported `derived.shell.regpath.claude: got
[absent] want [installed]` on both images, and the pattern was clean. Node, git, gh and
the desktop apps arrive via winget, whose installers put them on a registry PATH.
`claude-cli` runs a vendor PowerShell script that installs into
`%USERPROFILE%\.local\bin` and persists nothing; `codex-cli` does the same into
`%USERPROFILE%\.codex\bin`. `Set-BumpPath` (the mirror of `fixup_path`) prepends both
to `$env:PATH`, which lasts exactly as long as the process.

Three things followed from that, and none of them is small:

- **The run's own closing line was wrong.** It says "Run 'claude' in
  `%USERPROFILE%\git\first-project` to start", and a new terminal cannot find `claude`.
  `lib/shellpath.sh`'s opening comment names this exact failure as "the single most
  demoralising way for a setup to fail, because nothing looked broken".
- **Re-running was not idempotent in the way it claims.** `CHECK_WIN` for the Claude
  CLI is `Get-Command claude`, which fails in a fresh process, so the second run
  reinstalled the CLI rather than skipping it.
- **The docs already promised it.** README step 6 and "Removing it" were written
  without OS qualification, under a top-level "What happens when you run it". The
  Windows quick start is separate, but that section is not - so the README described a
  PATH edit Windows did not make.

## Decision

**The Windows spine persists PATH, into the per-user registry environment
(`HKCU\Environment` → `Path`), adding exactly the two dirs whose installers persist
nothing.** `lib/shellpath.ps1` owns it, `lib/apply.ps1` calls it where `apply.sh` calls
`persist_path`, and `Show-Expectations` discloses it at the confirm gate.

That last part is the load-bearing half. The rule this project holds itself to is that
bumpstart writes its own config paths and **one** thing outside them, and that one thing is
named before it happens. Windows now has such a thing, so it gets the same treatment:
disclosed at the gate, state-aware (a PATH that already carries the dirs is left alone
and says so), and documented for removal.

The mechanics, each chosen against a plausible wrong answer:

- **The raw registry value, read and written.**
  `(Get-Item HKCU:\Environment).GetValue('Path', '', 'DoNotExpandEnvironmentNames')`
  and `Set-ItemProperty -Type ExpandString`. The obvious accessor,
  `[Environment]::GetEnvironmentVariable('Path', 'User')`, **expands** `%USERPROFILE%`
  -style entries, so writing its result back bakes today's expansion into entries bumpstart
  did not author - a silent, permanent change to somebody else's PATH.
- **Not `setx`.** It truncates the value at 1024 characters. On a machine with a long
  PATH that destroys entries bumpstart does not own, which is the worst outcome available.
- **Appended, not prepended.** The effective PATH is the Machine value followed by the
  User one, so nothing written to the User scope can precede a machine-wide entry.
  Prepending buys no ordering guarantee and would put bumpstart ahead of choices the person
  made in their own account.
- **`WM_SETTINGCHANGE` broadcast afterwards**, via `SendMessageTimeout` to
  `HWND_BROADCAST`. Explorer keeps its own copy of the environment and hands it to
  everything it launches, so without the broadcast the registry is right and a new
  terminal is still wrong until the next sign-in. `SendMessageTimeout` rather than
  `SendMessage` because one hung top-level window would otherwise block the setup.
- **The decision is pure, the effect is not.** `Get-BumpPathUpdate` takes the current
  PATH plus the dirs and returns the new value and whether anything changed, comparing
  entries case-insensitively, ignoring a trailing separator, and expanding `%VAR%`
  references *for the comparison only*. It is tested in both `check` jobs, on macOS and
  on Windows, because it needs no registry at all.
- **The effect half reaches the registry through one function**, `Get-BumpUserEnvKey`,
  and that single door is the seam the Pester suite fakes. Both worlds are therefore
  asserted on every host - the no-op where no per-user registry exists, and the value
  written, its kind and the second-run no-op where one does - so the suite is
  host-neutral by construction: no case is gated on the machine it runs on, and none
  aims a write at the account PATH of whoever ran it.

## Considered Options

| approach | what it costs | what it buys |
| --- | --- | --- |
| **User registry PATH** (chosen) | no marker, so removal is "delete these two dirs" rather than "delete the marked block" | a new terminal finds the agents; the same promise on all three OSes |
| Leave it to the vendors | the closing line stays wrong, and run 2 reinstalls the CLI every time | nothing bumpstart has to own |
| A line in the PowerShell `$PROFILE` | only PowerShell sees it - not cmd, not a GUI launcher, not VS Code's task runner - and it is a *second* mechanism to keep in step with the rc line | markers, and a mechanical removal story |
| `setx` | truncation at 1024 characters, i.e. data loss on exactly the machines with the most to lose | one line of code |
| Machine-scope PATH | a UAC prompt on the critical path, which is currently UAC-free, and an edit affecting every account | ordering ahead of machine entries |

**The `$PROFILE` option is the one that looks like the closest mirror and is worst.**
It reads as symmetrical with the rc line, but the thing being fixed is
`Get-Command claude` in a *fresh process of any kind*, and a PowerShell profile answers
that for one shell only.

## Consequences

- **Removal is by name, not by marker.** There is nowhere in a registry value to put a
  comment, so the README names the two folders and where to delete them. This is
  strictly worse than the rc block and is the accepted cost.
- **CI proves the value, not the experience.** The lane's probe reads the registry
  directly, so it would pass whether or not the broadcast happens; and no hosted runner
  gives us a logon session in which to open a genuinely new terminal. The code says so
  where it lives, rather than implying the lane covers it.
- **The codex dir gets the same fix and nothing asserts it.** The Windows lane resolves
  `claude starter`, so `codex-cli` has never run there - its registry-PATH zero in the
  manifest is the tool being absent, not a failure to persist. A second Windows lane is
  exactly the condition [0004](0004-the-windows-lane-is-not-a-row.md) names as flipping
  the "not a row" decision, and this is a second reason to want one.
- **`rc.file` and `rc.persists_path` in the Windows manifest are measurements now.**
  They were hardcoded `none` / `0`, which is how a spine that persisted nothing and a
  spine whose persistence broke read identically. A duplicate-entry count joins them, so
  a vendor installer that starts persisting these dirs itself shows up as a duplicate
  rather than passing quietly.
- **`manifest_invariant_subset` still refuses Windows manifests**, and the reason is now
  the shape of the claim rather than the absence of one: a registry value carries no
  `rc.block` and no marker count.
