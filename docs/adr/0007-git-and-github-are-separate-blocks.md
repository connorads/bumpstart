# 0007 - git and GitHub are separate blocks, and git is the one that stands alone

Status: accepted.

`git` declared `INCLUDE="gh-auth"`, so every plan containing git also installed the
GitHub CLI and opened a browser to sign in. This records the reversal: `git` means
git, `github` is what you add when you want an account, and the dependency runs the
other way.

## Context

The dependency existed for one reason: git needs a name and an email, and the
GitHub API has both. `gh api user` gives a login, a numeric id and a profile name,
and `{id}+{login}@users.noreply.github.com` is an address that keeps a real one off
public commits. Reading them was cheaper than asking for them.

What it cost was the entry price. Every beginner paste installed `gh` and stopped at
a browser sign-in, so a GitHub account became a prerequisite for writing any code at
all - and nothing said so until the browser opened mid-run. The README's claim that
"there is one thing only you know: which AI subscription you already pay for" was
false for exactly this reason.

The two things are not the same size. git is version control on this machine and
needs no account anywhere. GitHub is a service you sign up to. An id that names the
small thing and installs the large one is the wrong shape.

## Decision

**`git` installs git and gives it a name and an email. `github` installs the CLI and
signs in. `github` INCLUDEs `git`; `git` includes nothing.**

Choosing GitHub means choosing git. Choosing git means nothing about GitHub.

`gh-auth` is renamed to `github` with **no alias**. An id resolves before anything is
installed, so an old paste fails at the gate with "unknown id" rather than part-way
through a setup.

`starter` is unchanged - it still contains `github` through `web`, so the default
beginner paste still signs you in and still gets the noreply address.

### Where the identity comes from

`blocks/git/apply.sh` is the single writer of `user.name` and `user.email`, and it
takes them from whichever of two sources is there:

1. a GitHub sign-in, when one exists - for the address more than the name;
2. otherwise a question, when there is somebody to ask;
3. otherwise nothing, and a line naming the command that fixes it.

Ordering makes (1) work without either block knowing about the plan: `github` is an
`auth` block (rank 20) and `git` is a `tool` block (rank 30), so the sign-in has
already happened by the time git reads it.

The identity write stays in `git` rather than moving to `github` because on Linux
and Windows **git is not installed yet at rank 20** - the `git` block is what
installs it there. A `github` block that configured git would be configuring a
binary that does not exist on precisely the machines this change is for.

`--yes` now reaches a block as `BUMP_YES`. Without it the flag stopped at the
confirm gate, and a block on a real terminal could still ask a question - which
is the whole failure `--yes` exists to prevent.

## Consequences

A beginner can start with no GitHub account: `claude git node concise` installs a
working setup and asks two questions.

Nothing new arbitrates between the two blocks. They agree because `git` only ever
sets config that is unset, and because kind ordering puts the sign-in first - the
same two rules the block already ran on.

An unattended run cannot stall on the new question, on either spine.

## What this gives up

The GitHub path sets `{id}+{login}@users.noreply.github.com`, which keeps a real
address off public commits. A hand-typed email has no such protection, and someone
who types their personal address will publish it on their first push.

Accepted, on two grounds. The prompted path is for people with no GitHub account,
who are not pushing anywhere yet. And `github` stays in `starter`, so the default
paste is still the protected one - the prompt is the fallback, not the norm.

## Considered options

| option | why not |
| --- | --- |
| **the split above** (chosen) | git means git; the account is a separate, named choice |
| keep the dependency, fall back to a prompt when gh is absent | leaves the browser sign-in in every beginner paste, which is the whole problem |
| split, but keep `gh-auth` as a hidden alias for `github` | two names for one thing, forever, and the failure it prevents is a clear error at resolve time |
| generate `name@localhost` when nobody answers | junk in commit metadata that cannot be un-written, and it breaks on the first push |
| move the identity write into `blocks/github` | git is not installed at rank 20 on Linux or Windows, so the default paste would silently skip the noreply address on both |
