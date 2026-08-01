# 0006 - The project is called bumpstart

The project shipped as `vibe-setup`. This records why it is now `bumpstart`, which
names were rejected and on what grounds, and why the rename happened when it did
rather than later.

## Context

`vibe-setup` undersold the thing. Two problems, both in the name:

- **`-setup` reads as a chore.** It names a script that installs packages. What this
  actually does is compose vetted blocks and *steer the agent* - the instructions files
  are half the product, and the name gave no hint of them.
- **`vibe` ages with the meme.** "Vibe coding" is a phrase with a shelf life. The
  practice this tool serves may well outlive the word for it, and a project named after
  the word does not.

The tagline still says "agentic / \"vibe\" coding", because that is the practice and it
is what a reader searches for. The tool is not named after it.

## Decision

**The project is `bumpstart`** - bump-starting an engine with borrowed momentum. The
metaphor is the product: a beginner gets a working setup from somebody else's push, and
then drives.

The surface renames with it:

| thing | value |
| --- | --- |
| repo | `connorads/bumpstart` (renamed on GitHub, which preserves web and git redirects) |
| entry points | `bumpstart`, `bumpstart.ps1` |
| shell prefix | `BUMP_*` / `bump_*` |
| PowerShell prefix | `*-Bump*` verbs, `$Bump*` variables |
| PATH marker | `# >>> bumpstart >>>` / `# <<< bumpstart <<<` |

`BUMP_*` rather than `BUMPSTART_*` for the same width as `VIBE_*`, so nothing reflows.

Block, axis, preset and recipe ids do not change: they name what a user is choosing
(`claude`, `starter`, `node`), never the project. `~/.agents/AGENTS.md` and
`~/git/first-project` do not change either - they are the user's paths, not ours.
`install.sh` and `install.ps1` keep their generic names, because the README documents
them as the shortest paste.

## Considered Options

Every shortlisted alternative was checked for collisions before being ruled out.

| name | why not |
| --- | --- |
| **bumpstart** (chosen) | unclaimed; the jump-start metaphor without the generic word |
| `cairn` | taken in the AI/dev-tooling aisle - a collision where our users look |
| `kiln` | same |
| `hearth` | same |
| `flint` | same |
| `primer` | same |
| `jumplead` | a live B2B SaaS with the ® - the exact metaphor, unavailable |
| `jumpstart` | generic and unownable: Solaris JumpStart, SageMaker JumpStart, npm `jumpstart`, JumpStart Games |

`jumpstart` is the instructive rejection. It is the *right* metaphor and it is free to
use, which is precisely the problem - a name nobody can own is a name nobody can find.
`bumpstart` is the same picture, one letter away, and unclaimed.

## Consequences

- **No compatibility layer, and none is needed.** The repo was 18 days old, public, with
  0 stars and 0 forks. Nothing was in the wild, so there is no old-name stub repo, no
  `VIBE_*` alias, and no legacy marker the PATH remover has to recognise. Renaming
  outright and updating every caller is the whole change.
- **The cost was only ever going to rise.** The PATH marker lands in an attendee's
  `.zshrc` and the paste URL lands in somebody's slides. Every workshop run from here
  would have added machines carrying the old marker and links pointing at the old paste.
  Doing it at zero users is the cheapest this decision will ever be.
- **GitHub's redirects cover the tail.** A repo rename keeps web and git redirects for
  the old path, so an old clone still fetches and an old link still resolves. Raw
  content URLs are not covered, which is why the paste lane is the lane that proves the
  rename: it fetches the bootstrap from `raw.githubusercontent.com` at the commit under
  test, and it is the only lane anywhere that runs the bootstrap at all
  ([0003](0003-real-installs-on-pristine-machines.md)).
- **The rename could not be verified until it was pushed.** Every local gate passed on
  the rename commits while the paste URL still 404'd, because the repo had not been
  renamed yet. That gap is inherent to a bootstrap that fetches itself.
