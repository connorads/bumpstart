# shellcheck shell=bash
# tart.sh: the Tart adapter for the guest port — a genuinely first-time Mac.
#
# The same seven operations as guests/container.sh, so lanes/run.sh does not know
# which one it is driving. See that file for the port's rationale.
#
# `ghcr.io/cirruslabs/macos-tahoe-vanilla`, never `-base`: the base image preinstalls
# brew, mise, node, git, gh and yarn — very nearly the exact set vibe installs — so
# testing against it would be a guaranteed false pass. Reset is `tart clone`, an APFS
# clonefile and therefore instant.
#
# Three properties of the vanilla image shape this adapter, all read from its Packer
# template (vanilla-tahoe.pkr.hcl):
#   - `admin ALL=(ALL) NOPASSWD: ALL` is baked in, so Homebrew installs headlessly
#     and this lane needs no askpass. The flip side: macOS's own password path
#     (lib/brew.sh) is therefore NOT exercised here, exactly as on the NOPASSWD Linux
#     legs. The password mode is refused outright rather than silently passing.
#   - `recovery_partition = "keep"`, deliberately, because softwareupdate needs it —
#     which is how Homebrew installs the Xcode command line tools. If the CLT step
#     fails, suspect this first.
#   - Gatekeeper is DISABLED (`spctl --global-disable`, asserted in the build), so the
#     guest is MORE PERMISSIVE than a real Mac: a cask install cannot hit a "developer
#     cannot be verified" refusal here. Pristine with respect to Homebrew, NOT with
#     respect to Gatekeeper.
#
# There is no Tart guest agent in the vanilla image, so `tart exec` does not exist and
# everything goes over ssh as admin/admin (the credentials the template sets).
# NEVER `ssh -t`: every prompt in the product is `[ -t 0 ]`-gated, so a TTY would hang
# the run rather than test it.
#
# bash-3.2-clean. Sourced, not executed.

GUEST_KIND=tart
# shellcheck disable=SC2209  # the guest's account name, not the `admin` command
GUEST_USER=admin
# tart's --dir lands at /Volumes/My Shared Files/<name>, whose spaces would have to
# be quoted through every layer of every command string. guest_provision symlinks it
# somewhere spaceless and this is that path.
GUEST_SRC=/tmp/vibe-src
TART_SHARE='/Volumes/My Shared Files/repo'

# Tart's LRU sweep would delete the 23 GB golden image to make room for clones
# (`tart clone --prune-limit` confirms the 100 GB default), so this is exported for
# every tart call, not just the ones that obviously allocate.
export TART_NO_AUTO_PRUNE=1

TART_IP=""
TART_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"

_tart_ssh() {
  # shellcheck disable=SC2086  # TART_SSH_OPTS is a deliberate word-split option list
  sshpass -p admin ssh $TART_SSH_OPTS "$GUEST_USER@$TART_IP" "$@"
}

guest_start() {
  if ! command -v tart >/dev/null 2>&1; then
    printf 'guest: tart is not installed (see the README Development section)\n' >&2
    return 1
  fi
  if ! command -v sshpass >/dev/null 2>&1; then
    printf 'guest: sshpass is not installed — the vanilla image has no tart guest agent\n' >&2
    return 1
  fi
  if ! tart list 2>/dev/null | grep -q -- "$GUEST_IMAGE"; then
    printf 'guest: the %s image is not pulled. Run: mise run vm-image-macos (23 GB)\n' "$GUEST_IMAGE" >&2
    return 1
  fi

  # One clone at a time per VM, never two of the same source concurrently.
  tart delete "$GUEST_NAME" >/dev/null 2>&1 || true
  tart clone "$GUEST_IMAGE" "$GUEST_NAME" >/dev/null 2>&1 || return 1
  # 6 GB: Apple's floor is 4 and Tart hard-codes it because guests freeze below it.
  # The image itself was built at 4 CPU / 8 GB, so this is in range.
  tart set "$GUEST_NAME" --memory 6144 --cpu 4 >/dev/null 2>&1 || return 1

  # --no-graphics needs FileVault off, which the vanilla image already is.
  nohup tart run --no-graphics --dir="repo:$GUEST_REPO:ro" "$GUEST_NAME" \
    >"${TMPDIR:-/tmp}/vibe-tart-$GUEST_NAME.log" 2>&1 &

  # Bounded polling for a genuinely pending thing is not a retry: the VM has to boot
  # and sshd has to come up, and there is no event to wait on.
  _gs_i=0
  while [ "$_gs_i" -lt 120 ]; do
    TART_IP="$(tart ip "$GUEST_NAME" 2>/dev/null)"
    [ -n "$TART_IP" ] && break
    sleep 2
    _gs_i=$((_gs_i + 1))
  done
  if [ -z "$TART_IP" ]; then
    printf 'guest: %s never reported an IP\n' "$GUEST_NAME" >&2
    return 1
  fi

  _gs_i=0
  while [ "$_gs_i" -lt 60 ]; do
    if _tart_ssh true >/dev/null 2>&1; then return 0; fi
    sleep 2
    _gs_i=$((_gs_i + 1))
  done
  printf 'guest: sshd on %s (%s) never answered\n' "$GUEST_NAME" "$TART_IP" >&2
  return 1
}

guest_provision() {
  if [ "${GUEST_SUDO:-nopasswd}" = password ]; then
    # Refused, not worked around: the image bakes in NOPASSWD, so a "password" lane
    # here would pass while asserting nothing. macOS's password path stays a
    # documented gap rather than a fake pass.
    printf 'guest: the vanilla macOS image has NOPASSWD sudo baked in — the password axis cannot run here\n' >&2
    return 1
  fi
  # A spaceless path to the read-only share, so no command string has to quote
  # "/Volumes/My Shared Files/repo".
  _gp_link="ln -sfn '$TART_SHARE' '$GUEST_SRC'"
  _tart_ssh "$_gp_link" >/dev/null 2>&1 || return 1
  _tart_ssh "test -f '$GUEST_SRC/lib/apply.sh'" >/dev/null 2>&1 || {
    printf 'guest: the repo share did not appear at %s\n' "$TART_SHARE" >&2
    return 1
  }
  guest_exec_root "mkdir -p $GUEST_STATE && chmod 1777 $GUEST_STATE" || return 1
}

guest_exec() {
  _tart_ssh "$1"
}

# The command arrives on stdin rather than as an argument, so it needs no second
# round of quote escaping to survive `ssh <string>` then `sudo sh -c <string>`.
guest_exec_root() {
  printf '%s\n' "$1" | _tart_ssh "sudo -n /bin/sh -s"
}

guest_fetch() {
  # shellcheck disable=SC2086  # deliberate word-split option list
  sshpass -p admin scp $TART_SSH_OPTS "$GUEST_USER@$TART_IP:$1" "$2" >/dev/null 2>&1
}

guest_destroy() {
  tart stop "$GUEST_NAME" >/dev/null 2>&1 || true
  # tart stop is asynchronous; delete refuses while the VM is still running.
  _gd_i=0
  while [ "$_gd_i" -lt 30 ]; do
    if tart delete "$GUEST_NAME" >/dev/null 2>&1; then return 0; fi
    sleep 2
    _gd_i=$((_gd_i + 1))
  done
  printf 'guest: could not delete %s - run "tart delete %s" by hand\n' "$GUEST_NAME" "$GUEST_NAME" >&2
  return 1
}

guest_keep() {
  printf '  the guest is still running. To look around:\n'
  printf '    sshpass -p admin ssh %s@%s\n' "$GUEST_USER" "$TART_IP"
  printf '    tart stop %s && tart delete %s   # when you are done\n' "$GUEST_NAME" "$GUEST_NAME"
}
