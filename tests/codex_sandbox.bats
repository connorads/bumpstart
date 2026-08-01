#!/usr/bin/env bats
#
# blocks/codex-cli/apply.sh — the sandbox probe. Codex runs every command inside a
# bubblewrap sandbox that needs an unprivileged user namespace, and Ubuntu 24.04 (the
# default `wsl --install` distro) ships with that switched off. Without this warning
# the symptom is the agent silently failing to edit files, which reads as "the AI is
# broken" rather than as a system setting.
#
# The kernel switch is the signal, not whether a packaged bwrap works: the AppArmor
# grant is attached to the path /usr/bin/bwrap and Codex uses its own bundled copy,
# so a system bwrap can succeed while Codex is still denied. $BUMP_PROC_DIR is the
# seam that makes those switches fakeable off Linux.

load helpers/common

setup() {
  setup_isolated_env
  PROC="$BATS_TEST_TMPDIR/proc"
  mkdir -p "$PROC"
  # Non-root, explicitly: root needs no namespace grant, so the probe exits early,
  # and inheriting the invoking identity would make every case below silently vacuous
  # wherever the suite happened to be run as root. The root case overrides this.
  make_fake id 'printf "1000\n"'
}

probe() {
  run env BUMP_LIB="$REPO_ROOT/lib" BUMP_ROOT="$REPO_ROOT" BUMP_OS="${1:-linux}" \
    BUMP_PROC_DIR="$PROC" \
    BUMP_BLOCK_DIR="$REPO_ROOT/blocks/codex-cli" BUMP_BLOCK_ID=codex-cli \
    bash "$REPO_ROOT/blocks/codex-cli/apply.sh"
}

@test "AppArmor restriction on: warns, and prints the sysctl that lifts it" {
  printf '1\n' > "$PROC/apparmor_restrict_unprivileged_userns"
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox can't start"* ]]
  [[ "$output" == *"apparmor_restrict_unprivileged_userns = 0"* ]]
  # and it says the agent is still usable, so this reads as a limit, not a failure
  [[ "$output" == *"still works without it"* ]]
}

@test "a working system bwrap does NOT clear an AppArmor restriction" {
  # The trap the whole probe exists for: `apt install bubblewrap` makes
  # /usr/bin/bwrap work while Codex's bundled copy is still denied, so trusting the
  # system binary would report a healthy sandbox on a machine that has none.
  printf '1\n' > "$PROC/apparmor_restrict_unprivileged_userns"
  make_fake bwrap   # exits 0: the packaged copy succeeds
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox can't start"* ]]
}

@test "AppArmor restriction off: reports the sandbox works" {
  printf '0\n' > "$PROC/apparmor_restrict_unprivileged_userns"
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox can start"* ]]
}

@test "the userns_clone switch off: warns with that switch's own fix" {
  # Debian and Arch expose a different knob, so the fix printed is keyed on which
  # knob the kernel HAS — the thing that must change — not on a distro name.
  printf '0\n' > "$PROC/unprivileged_userns_clone"
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"unprivileged_userns_clone = 1"* ]]
  [[ "$output" != *"apparmor"* ]]
}

@test "no kernel switch, but bwrap really fails: still warns" {
  # A container's seccomp profile or a hardened kernel: trust the attempt over the
  # absent switch.
  make_fake bwrap 'exit 1'
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox can't start"* ]]
  [[ "$output" == *"blocks unprivileged user namespaces"* ]]
}

@test "no switches and no bwrap to probe with: says nothing rather than guessing" {
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox can start"* ]]
}

@test "as root there is nothing to warn about" {
  # Containers and Codespaces run as root, which needs no namespace grant.
  printf '1\n' > "$PROC/apparmor_restrict_unprivileged_userns"
  make_fake id 'printf "0\n"'   # overrides setup's non-root fake
  probe
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "on a Mac the probe does not run at all" {
  printf '1\n' > "$PROC/apparmor_restrict_unprivileged_userns"
  probe mac
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
