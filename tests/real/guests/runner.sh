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
# to provision unless $CI is set or VIBE_REAL_ALLOW_HOST=1 is explicit. drive.sh's
# lane groups never select it either.
#
# The repo is still mounted read-only, like every other adapter: it is copied to a
# scratch path and stripped of write permission, so a lane cannot dirty the checkout
# it is testing.
#
# bash-3.2-clean. Sourced, not executed.

GUEST_KIND=runner
GUEST_USER="$(id -un)"
GUEST_SRC="${TMPDIR:-/tmp}/vibe-real-src"

guest_start() {
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
  if [ -z "${CI:-}" ] && [ "${VIBE_REAL_ALLOW_HOST:-}" != 1 ]; then
    printf 'guest: the runner adapter really installs into %s.\n' "$HOME" >&2
    printf '       Set VIBE_REAL_ALLOW_HOST=1 only on a machine you are willing to lose.\n' >&2
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

guest_exec() {
  /bin/sh -c "$1"
}

guest_exec_root() {
  sudo -n /bin/sh -c "$1"
}

guest_fetch() {
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
