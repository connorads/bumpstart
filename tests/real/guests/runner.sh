# shellcheck shell=bash
# runner.sh: the "this machine IS the throwaway" adapter, for a hosted CI runner.
#
# The same seven operations as guests/container.sh (see that file for the port's
# rationale), with no virtualisation at all: a GitHub runner already gets a fresh VM
# per job, so the isolation is the job boundary.
#
# It exists for the weekly macOS drift lane. There is no clean hosted macOS and
# GitHub says there never will be (runner-images#222), so that lane scrubs Homebrew
# and the Xcode CLT and runs on the runner itself. It is DRIFT DETECTION — did a
# vendor installer change under us — NOT a pristine Mac. The pristine Mac is the
# local tart lane, and describing this one as pristine is how that lane quietly stops
# being run.
#
# DANGEROUS BY NATURE, so it fails closed: a real install into $HOME is exactly what
# it does, and on a developer's laptop that is their actual home directory. It refuses
# to provision unless $CI is set or BUMP_REAL_ALLOW_HOST=1 is explicit. drive.sh's
# lane groups never select it either. It refuses a root run for the same reason it
# refuses the password axis: root cannot fail the properties the lane is there to
# check, so the lane would pass while asserting nothing.
#
# The repo is still mounted read-only, like every other adapter: it is copied to a
# scratch path and stripped of write permission, so a lane cannot dirty the checkout
# it is testing.
#
# bash-3.2-clean. Sourced, not executed.

GUEST_KIND=runner
GUEST_USER="$(id -un)"
GUEST_SRC="${TMPDIR:-/tmp}/vibe-real-src"
# Set by guest_start from the password database, never inherited.
GUEST_SHELL=

# The user's real login shell, from the password database rather than from $SHELL:
# a CI step inherits whatever the runner happened to start it with, and $SHELL is
# what persist_path keys on. guests/container.sh spends five lines forcing
# `useradd -s /bin/bash` for the same reason.
_runner_login_shell() {
  if command -v dscl >/dev/null 2>&1; then
    dscl . -read "/Users/$GUEST_USER" UserShell 2>/dev/null | awk '{print $2}'
  elif command -v getent >/dev/null 2>&1; then
    getent passwd "$GUEST_USER" 2>/dev/null | awk -F: '{print $7}'
  fi
}

guest_start() {
  # The host guard, BEFORE anything is written. It used to live in guest_provision,
  # which runs after guest_start has already dropped a full copy of the repo into
  # TMPDIR - so the refusal came after the side effect it exists to prevent.
  if [ -z "${CI:-}" ] && [ "${BUMP_REAL_ALLOW_HOST:-}" != 1 ]; then
    printf 'guest: the runner adapter really installs into %s.\n' "$HOME" >&2
    printf '       Set BUMP_REAL_ALLOW_HOST=1 only on a machine you are willing to lose.\n' >&2
    return 1
  fi

  # Root is REFUSED, not worked around, and for the same reason the guard above
  # exists: this adapter runs the lane as the invoking user, so the invoking user's
  # privilege is the lane's. Two properties die under root, both silently:
  #   - "the repo is read-only to the run" is enforced here with `chmod -R a-w`,
  #     which root bypasses - so the port contract fails for a reason that is not
  #     about vibe, on the one leg where the assertion is also vacuous.
  #   - every sudo path in the product becomes a no-op, which is exactly what
  #     judge.sh's "the run was NOT root" check exists to catch. On the macOS drift
  #     lane that would leave `git`'s password step asserting nothing at all.
  if [ "$(id -u)" = 0 ]; then
    printf 'guest: this adapter runs the lane as the INVOKING user, and that user is root.\n' >&2
    printf '       Root bypasses the read-only repo copy and makes every sudo path in the\n' >&2
    printf '       product vacuous, so the lane would assert nothing. Run it unprivileged.\n' >&2
    return 1
  fi

  # $SHELL is a GUARANTEE of this port, not an accident of the invoking process. An
  # unset or `sh` $SHELL makes persist_path print the PATH line instead of writing it
  # - correct behaviour - and the probe then reports `rc.file none` while every rc
  # assertion fails for a harness reason.
  GUEST_SHELL="$(_runner_login_shell)"
  [ -n "$GUEST_SHELL" ] || GUEST_SHELL="${SHELL:-}"
  case "$(basename "${GUEST_SHELL:-none}")" in
    bash|zsh) : ;;
    *)
      printf 'guest: the login shell here is [%s], and vibe persists PATH only into\n' "${GUEST_SHELL:-unset}" >&2
      printf '       bash or zsh - so this lane would assert nothing about persistence.\n' >&2
      return 1 ;;
  esac

  if [ ! -d "$GUEST_REPO" ]; then
    printf 'guest: no repo at %s\n' "$GUEST_REPO" >&2
    return 1
  fi
  rm -rf "$GUEST_SRC" 2>/dev/null || true
  mkdir -p "$GUEST_SRC" || return 1
  # A copy rather than the checkout, made read-only: the same property the container
  # and tart adapters get from their mount options.
  (cd "$GUEST_REPO" && tar cf - .) | (cd "$GUEST_SRC" && tar xf -) || return 1
  chmod -R a-w "$GUEST_SRC" || return 1
}

guest_provision() {
  # Belt to guest_start's braces: the guard is repeated because provisioning is the
  # step that grants privilege, and a future caller might reach it another way.
  if [ -z "${CI:-}" ] && [ "${BUMP_REAL_ALLOW_HOST:-}" != 1 ]; then
    printf 'guest: the runner adapter really installs into %s.\n' "$HOME" >&2
    printf '       Set BUMP_REAL_ALLOW_HOST=1 only on a machine you are willing to lose.\n' >&2
    return 1
  fi
  if [ "${GUEST_SUDO:-nopasswd}" = password ]; then
    # A hosted runner has passwordless sudo, so a "password" lane here would pass
    # while asserting nothing.
    printf 'guest: a hosted runner has NOPASSWD sudo — the password axis cannot run here\n' >&2
    return 1
  fi
  mkdir -p "$GUEST_STATE" || return 1
  chmod 1777 "$GUEST_STATE" 2>/dev/null || true
}

# `< /dev/null` is not tidiness. docker exec and ssh hand the run no stdin at all,
# so every `[ -t 0 ]`-gated prompt in the product is false; a bare `/bin/sh -c`
# inherits the CALLER's, so running the drift lane from a terminal would take every
# one of those prompts live and hang - the exact outcome guests/container.sh says
# this port exists to prevent. The existing contract case passed only because bats
# happened to supply /dev/null.
guest_exec() {
  SHELL="$GUEST_SHELL" HOME="$HOME" /bin/sh -c "$1" < /dev/null
}

guest_exec_root() {
  sudo -n /bin/sh -c "$1" < /dev/null
}

guest_fetch() {
  [ -f "$1" ] || return 1
  cp "$1" "$2" >/dev/null 2>&1
}

guest_destroy() {
  # The job's VM is the teardown. Only the read-only copy is ours to remove, and its
  # own permissions are in the way.
  chmod -R u+w "$GUEST_SRC" 2>/dev/null || true
  rm -rf "$GUEST_SRC" 2>/dev/null || true
  return 0
}

guest_keep() {
  printf '  this lane ran on the machine itself; there is no guest to reattach to.\n'
  printf '  the log bundle is what is left.\n'
}
