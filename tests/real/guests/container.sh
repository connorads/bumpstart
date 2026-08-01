# shellcheck shell=bash
# container.sh: the docker adapter for the guest port.
#
# The port, so lanes are written once instead of once per virtualisation
# technology. Seven operations; each earns its place:
#
#   guest_start        create/boot the guest with the repo mounted read-only
#   guest_provision    turn it into a pristine machine with an unprivileged test
#                      user, per $GUEST_SUDO, and a world-writable state dir
#   guest_exec <cmd>   run <cmd> as that user, stdout/stderr through, exit status back
#   guest_exec_root    the same, privileged — a container starts with root and no
#                      other user, so this cannot be folded into guest_exec
#   guest_fetch <r> <l>  copy a file out (the manifest, the transcript); FAILS when
#                        the remote file is not there, because run.sh reads that
#                        status to tell "the probe crashed" from "the probe ran"
#   guest_destroy      tear it down
#   guest_keep         leave it up and print how to get back in
#
# The adapter sets: GUEST_SRC (where the repo is mounted), GUEST_USER (the
# unprivileged identity), GUEST_KIND.
# The runner sets: GUEST_NAME, GUEST_IMAGE, GUEST_REPO, GUEST_SUDO
# (nopasswd|password), GUEST_PASSWORD, GUEST_DEPS, GUEST_STATE.
#
# NEVER `-t`: every interactive prompt in the product is `[ -t 0 ]`-gated
# (gh auth login's Y/n, the blank-name question, sudo -v, press_enter), so a TTY
# would hang the run rather than test it. No stdin either, so `[ -t 0 ]` is false.
#
# Lane strings are POSIX sh. The interpreting shell differs by adapter - bash here
# (the test user's login shell), zsh on tart (macOS), sh on the runner - and pinning
# one everywhere would mean either losing $SHELL, which persist_path keys on, or
# forcing a shell the guest does not have. So the RULE is the contract instead, and
# tests/real_guest_contract.bats runs the constructs the lane runner actually uses
# on every adapter, so a bashism cannot pass on one and fail on two.
#
# bash-3.2-clean. Sourced, not executed.

GUEST_KIND=container
GUEST_SRC=/src
GUEST_USER=tester

guest_start() {
  if ! command -v docker >/dev/null 2>&1; then
    printf 'guest: docker is not installed\n' >&2
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    printf 'guest: no running docker daemon — start colima first (see the README)\n' >&2
    return 1
  fi
  docker rm -f "$GUEST_NAME" >/dev/null 2>&1 || true
  # --hostname is pinned so the manifest is comparable across guests without the
  # probe having to substitute a short container id out of every value (which would
  # also rewrite it out of the middle of a sha256).
  # sleep infinity keeps the guest alive between exec calls, so one lane is one
  # machine rather than one machine per step.
  docker run -d \
    --name "$GUEST_NAME" \
    --hostname bumpstart-guest \
    -v "$GUEST_REPO:$GUEST_SRC:ro" \
    -w / \
    "$GUEST_IMAGE" \
    sleep infinity >/dev/null 2>&1
}

guest_provision() {
  # The image's bare minimum, as data from the lane row — deliberately NOT a
  # convenience "install everything", because what the guest lacks is the point.
  if ! guest_exec_root "{ $GUEST_DEPS ; } > /tmp/bumpstart-deps.log 2>&1"; then
    guest_exec_root 'tail -40 /tmp/bumpstart-deps.log' >&2
    return 1
  fi

  # -s /bin/bash matters: useradd defaults to /bin/sh, and persist_path keys on the
  # LOGIN shell. A sh user is told the PATH line instead of having it written —
  # correct behaviour, and it would make the fresh-shell assertions vacuous.
  guest_exec_root "id -u $GUEST_USER >/dev/null 2>&1 || useradd -m -s /bin/bash $GUEST_USER" || return 1

  # A sudoers drop-in rather than a group, because the privileged group is `sudo` on
  # Debian and `wheel` on Fedora/Arch and probing for the right name is a distro
  # table we do not need. mkdir first: /etc/sudoers.d arrives with the sudo package,
  # and a lane whose deps do not include sudo would otherwise fail here obscurely.
  guest_exec_root "mkdir -p /etc/sudoers.d" || return 1
  if [ "$GUEST_SUDO" = password ]; then
    guest_exec_root "printf '%s ALL=(ALL) ALL\n' $GUEST_USER > /etc/sudoers.d/bumpstart-test" || return 1
    guest_exec_root "printf '%s:%s\n' $GUEST_USER '$GUEST_PASSWORD' | chpasswd" || return 1
  else
    guest_exec_root "printf '%s ALL=(ALL) NOPASSWD: ALL\n' $GUEST_USER > /etc/sudoers.d/bumpstart-test" || return 1
  fi
  guest_exec_root "chmod 0440 /etc/sudoers.d/bumpstart-test" || return 1

  # Outside $HOME on purpose: the probe hashes vibe-owned paths under the home dir,
  # and harness scratch living there would show up as a state difference.
  guest_exec_root "mkdir -p $GUEST_STATE && chmod 1777 $GUEST_STATE" || return 1
}

# su, not `docker exec -u`: -u leaves HOME pointing at the image's (usually /root)
# and never sets SHELL, and both are load-bearing here — persist_path reads $SHELL
# and everything vibe writes lands under $HOME. Plain `su` (not `su -`) resets
# HOME/SHELL/USER from /etc/passwd while preserving the rest of the environment, so
# SUDO_ASKPASS and NO_COLOR still reach the run.
guest_exec() {
  docker exec "$GUEST_NAME" su "$GUEST_USER" -c "$1"
}

guest_exec_root() {
  docker exec "$GUEST_NAME" /bin/sh -c "$1"
}

guest_fetch() {
  docker cp "$GUEST_NAME:$1" "$2" >/dev/null 2>&1
}

guest_destroy() {
  docker rm -f "$GUEST_NAME" >/dev/null 2>&1
}

guest_keep() {
  printf '  the guest is still up. To look around:\n'
  printf '    docker exec -it %s su - %s\n' "$GUEST_NAME" "$GUEST_USER"
  printf '    docker rm -f %s        # when you are done\n' "$GUEST_NAME"
}
