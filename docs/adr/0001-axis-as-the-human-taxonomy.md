# 0001 - AXIS is the human taxonomy, alongside KIND

Every block and preset carries two labels. `KIND` tells the applier **when** to
run a block. `AXIS` tells a person **what decision** the block represents, and it
is the only thing `--build` and `--list` group by. Axes are data
(`axes/<id>/meta`), so adding a question costs a directory, not code.

## Context

`KIND` was doing both jobs. It drives `_kind_rank` (step order), the `[kind]`
colours in the plan, and TARGET semantics for a harness - and it was also the
grouping the wizard used to ask a human what they wanted. Every wart in the
wizard traced to that overload:

- `_pulls_in_harness` existed only to infer "is this preset the agent choice" by
  expanding it and looking for a harness - inferring intent from mechanics.
- The opt-in list sorted by `_kind_rank`, which is *execution order*, so presets
  - the coarse, useful choices - came last, after ten atom questions.
- `starter` is a recipe spanning two axes; it sat in the same flat list as `web`,
  a point on one.
- Wholes and parts shared that flat list with no containment shown: `starter` ⊃
  `web` ⊃ `gh-auth`, each with its own y/N prompt.

The visible symptom was that `--build` emitted `claude-cli starter` where the
README hands out `claude starter`. Not wrong - `claude-cli claude-desktop
starter` is the same plan spelled long - but the wizard could not produce the
string the project documents, because agent *bundles* were excluded from the
opt-in list on the grounds that they "pull in a harness".

Adding `github-desktop` forced the issue: it is the first `KIND=app` that is not
the vendor client of the harness you already chose, so no `KIND`-shaped rule
puts it in the right question.

## Decision

Add `AXIS` to block/preset metadata and an `axes/<id>/meta` manifest declaring
`LABEL` (the question), `ORDER` (when it is asked), `SELECT` (`one` = required
numbered pick, `multi` = per-row y/N) and, for a single-select, `DEFAULT`.

The axes are `recipe` (5), `agent` (10), `tools` (20), `steering` (30).

`AXIS` presence is what makes a block offerable. `mise` declares none: nobody
picks a version manager directly, and it stays fully resolvable as a dependency
of `node`/`pnpm`.

The wizard becomes a fold: enumerate the axes with members, sort by `ORDER`, ask
one question each. `_pulls_in_harness` / `Test-PullsInHarness` are deleted - the
agent axis is declared, not inferred. `--list` groups by the same axes, with
`KIND` demoted to a dim tag.

`starter` stays `KIND=preset` and gains `AXIS=recipe`, so `resolve.sh` /
`resolve.ps1` and `tests/fixtures/contract/resolve-cases.tsv` are untouched.

`github-desktop` ships opt-in only, with `INCLUDE="git"`.

## Considered Options

**Minimal fix: let the wizard offer agent bundles.** Drop `_pulls_in_harness`,
list `claude`/`codex` in the harness question. Emits the right string in about
ten lines. Rejected: it fixes the symptom and leaves `KIND` overloaded, so the
next block that doesn't fit an execution kind reopens the whole question -
`github-desktop` already is that block.

**`AXIS` as a field, with order and copy hardcoded in both spines.** No manifest;
each spine holds a table of axis → question → position. Rejected: adding an axis
then means editing bash *and* PowerShell in lockstep, which is exactly the
twin-authoring cost the block metadata exists to avoid. A dir with a `meta` in it
is read by the existing `meta_get`/`Get-Meta` verbatim, so the manifest costs no
parsing code at all.

**A fourth `supervision` axis for `github-desktop`.** Seeing and undoing changes
is arguably its own decision, not "what to install". Rejected: a category with
exactly one member is invented rather than discovered. Revisit if a diff viewer
or an editor integration arrives - two members make it a real axis.

**`KIND=recipe` for `starter`.** The overload is real, so split it in `KIND` too.
Rejected: `KIND` is consumed by the pure core, so a new kind means a
`_kind_rank` case, a `Get-KindRank` case and a change to the shared contract
fixture - all to express something `AXIS=recipe` already says, with no
behavioural gain.

**Put `github-desktop` in `web`/`starter`.** It would reach every workshop
attendee, who arguably needs it most. Rejected: preset membership is a one-way
door. An unpinned paste already printed on a slide would silently gain an app
install and a deferred second OAuth. Opt-in first; promote later on evidence,
which is the direction that stays reversible.

**Default the single-select to the first row.** No `DEFAULT` field; row one wins.
Rejected: the rows are sorted, so the default would move the day a member sorts
alphabetically earlier - a silent change to what a hurried author gets by
pressing Enter.

## Consequences

- Adding a block to a question is one `AXIS=` line; adding a question is one
  directory. Neither spine changes.
- A block author now has to know both labels and which is which. The `--show`
  output names the axis (or says the block is dependency-only) to keep that
  discoverable, and `--list` headings carry the wizard's own wording.
- `AXIS` is unvalidated: a typo yields a block that is silently never offered.
  Both spines treat "axis dir missing" as no-axis rather than erroring, since a
  wizard that refuses to run is worse than a block that isn't listed. If the
  catalogue grows, a schema test belongs in `tests/meta_schema.bats`.
- The wizard now asks four questions where it asked two, and the required
  single-select is no longer first (the recipe question opens). The emitted id
  list still leads with that required pick, so the paste keeps the shape the
  README documents and stays editable by swapping the first word.
- `KIND` keeps every machine job it had, so the pure core, the contract fixture,
  and the plan's step ordering are untouched by any of this.

### Parked

The Linux item below is superseded by
[0002](0002-linux-support.md), which decides it.

- Linux. `bump_os` returns `linux` and `bump_os_key` returns `LINUX`, but no
  block has `*_LINUX` cells and `ensure_brew` is the whole install substrate.
  Beyond that, no official Linux desktop app exists for Claude, ChatGPT *or*
  GitHub Desktop, so the `agent` axis presets cannot mean "CLI + app" there.
- The first `skill`/`mcp` block - better none than a redundant one.
- `build.sh` emitting the Windows paste line alongside the mac one, as
  `build.ps1` already emits both.
