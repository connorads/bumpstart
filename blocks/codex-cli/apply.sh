#!/usr/bin/env bash
set -euo pipefail
#
# codex-cli (interactive tail): check that Codex's sandbox can actually start on
# this Linux machine, and print the exact fix when it cannot.
#
# Codex sandboxes every command it runs with bubblewrap, which needs an unprivileged
# user namespace. On Ubuntu 24.04 — what `wsl --install` gives you by default — that
# is switched off, and `apt install bubblewrap` does NOT fix it: the AppArmor grant
# that permits the namespace is attached to the PATH /usr/bin/bwrap, and Codex ships
# and uses its own bundled copy, which the grant does not cover. So a working system
# bwrap proves nothing here, and the kernel switch is the accurate signal.
#
# The symptom otherwise is the agent silently being unable to edit files, which
# reads to a beginner as "the AI is broken" rather than as a system setting.
#
# This tail only diagnoses: the block still installs. Turning unprivileged user
# namespaces back on is a system-wide security decision and the user's call, so we
# print the command and let them run it.
#
# Linux only — run_block does not filter by OS, so this guards and exits 0 on mac.
# If a third block needs a tail like this, promote to apply.<os>.sh with apply.sh as
# the fallback, mirroring how content.<os>.md resolves.

# shellcheck source=lib/common.sh
. "$VIBE_LIB/common.sh"
# shellcheck source=lib/os.sh
. "$VIBE_LIB/os.sh"

[ "$(vibe_os)" = linux ] || exit 0

# Root needs no namespace grant at all (containers, Codespaces), so there is
# nothing to warn about.
[ "$(id -u)" -eq 0 ] && exit 0

# $VIBE_PROC_DIR is the test seam, the same shape as $VIBE_OSRELEASE_FILE in os.sh.
PROC="${VIBE_PROC_DIR:-/proc/sys/kernel}"
APPARMOR_KNOB="$PROC/apparmor_restrict_unprivileged_userns"
CLONE_KNOB="$PROC/unprivileged_userns_clone"

restricted=""
if [ -r "$APPARMOR_KNOB" ] && [ "$(cat "$APPARMOR_KNOB" 2>/dev/null)" = 1 ]; then
  restricted=apparmor
elif [ -r "$CLONE_KNOB" ] && [ "$(cat "$CLONE_KNOB" 2>/dev/null)" = 0 ]; then
  restricted=clone
elif command -v bwrap >/dev/null 2>&1 &&
     ! bwrap --dev-bind / / --unshare-net true >/dev/null 2>&1; then
  # No kernel switch says no, yet the real thing still fails — a container's seccomp
  # profile, or a hardened kernel. Trust the attempt over the absent switch.
  restricted=other
fi

if [ -z "$restricted" ]; then
  success "Codex's sandbox can start on this machine"
  exit 0
fi

warn "Codex's sandbox can't start here, so it may not be able to edit your files."
# Which fix to print is keyed on which knob this kernel HAS, not on a distro name:
# the knob is the thing that has to change, and probing for it covers every
# derivative without a table of them.
case "$restricted" in
  apparmor)
    info "To allow it, run these two lines, then open a new terminal:"
    info "  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/99-userns.conf"
    info "  sudo sysctl --system" ;;
  clone)
    info "To allow it, run these two lines, then open a new terminal:"
    info "  echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/99-userns.conf"
    info "  sudo sysctl --system" ;;
  *)
    info "Something on this machine blocks unprivileged user namespaces - if you didn't set that up, ask whoever did." ;;
esac
info "Codex still works without it - it just asks your permission for more things."
