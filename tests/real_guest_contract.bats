#!/usr/bin/env bats
#
# The guest port contract. One tiny interface, two adapters, so `lanes/run.sh` is a
# single lane runner rather than a Linux script and a near-identical macOS one — and
# so the deferred local UTM Windows guest becomes a third adapter rather than a
# fourth lane.
#
# These cases are the port's definition. Every property asserted here is one the lane
# runner relies on and would fail obscurely without:
#
#   guest_exec runs as an UNPRIVILEGED user      root skips every sudo path
#   ...with the target user's HOME and SHELL     persist_path keys on $SHELL, and
#                                                everything vibe writes lands in $HOME
#   ...with NO tty                               every prompt in the product is
#                                                `[ -t 0 ]`-gated, so a TTY would hang
#                                                the run rather than test it
#   the exit status comes back                   the applier's status is a data point
#   the repo is READ-ONLY to that user           a lane must not be able to dirty the
#                                                tree it is testing. Asserted as the
#                                                run's own identity, because that is
#                                                the identity that matters: the
#                                                container and tart adapters get it
#                                                from a mount option, the runner
#                                                adapter from permission bits (which
#                                                root could still override).
#
# The container leg is fast and needs only a running docker daemon. The tart leg is
# tagged `integration` because it boots a real macOS VM.

load helpers/common

setup() {
  REAL="$REPO_ROOT/tests/real"
  export GUEST_NAME="vibe-port-contract-$$"
  export GUEST_REPO="$REPO_ROOT"
  export GUEST_STATE=/tmp/vibe-real
  export GUEST_PASSWORD='vibe-test-not-a-secret'
  export GUEST_SUDO=nopasswd
  # The contract needs no packages: `true` keeps the case to a few seconds while
  # still exercising the provision step's own command path.
  export GUEST_DEPS=true
}

# Cleanup belongs in teardown, NOT an EXIT trap: setting one inside a bats test
# replaces bats' own and silently aborts the rest of the file. setup/test/teardown
# share one shell, so an adapter the test sourced is still in scope here.
teardown() {
  if declare -F guest_destroy >/dev/null 2>&1; then
    guest_destroy || true
  fi
}

# ── The container adapter ─────────────────────────────────────────────────────

@test "the container adapter satisfies the guest port" {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "no running docker daemon (start colima)"

  export GUEST_IMAGE=ubuntu:24.04
  # shellcheck source=tests/real/guests/container.sh
  . "$REAL/guests/container.sh"

  run guest_start
  [ "$status" -eq 0 ] || { echo "guest_start: $output"; false; }

  run guest_exec_root 'id -u'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "0" ] || { echo "guest_exec_root is not root: $output"; false; }

  run guest_provision
  [ "$status" -eq 0 ] || { echo "guest_provision: $output"; false; }

  # Unprivileged, and with the identity the run needs.
  run guest_exec 'id -un'
  [ "$output" = "$GUEST_USER" ] || { echo "guest_exec ran as [$output]"; false; }
  run guest_exec 'printf "%s\n" "$HOME"'
  [ "$output" = "/home/$GUEST_USER" ] || { echo "HOME is [$output]"; false; }
  run guest_exec 'printf "%s\n" "$SHELL"'
  [ "$output" = "/bin/bash" ] || { echo "SHELL is [$output]"; false; }

  # No tty: every interactive prompt in the product is `[ -t 0 ]`-gated, so this is
  # what makes a headless run deterministic instead of a hang.
  run guest_exec 'test -t 0'
  [ "$status" -ne 0 ] || { echo "guest_exec has a tty"; false; }

  # The exit status comes back, unchanged.
  run guest_exec 'exit 7'
  [ "$status" -eq 7 ] || { echo "status was $status, want 7"; false; }

  # The repo is there, and read-only.
  run guest_exec "test -f $GUEST_SRC/lib/apply.sh"
  [ "$status" -eq 0 ] || { echo "the repo is not mounted at $GUEST_SRC"; false; }
  run guest_exec "touch $GUEST_SRC/.contract-write-probe"
  [ "$status" -ne 0 ] || { echo "the repo is WRITABLE to the run"; false; }

  # The state dir exists and the unprivileged user can write it.
  run guest_exec "printf 'hello\n' > $GUEST_STATE/contract"
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  run guest_fetch "$GUEST_STATE/contract" "$BATS_TEST_TMPDIR/fetched"
  [ "$status" -eq 0 ] || { echo "guest_fetch: $output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/fetched")" = "hello" ] || { echo "fetched the wrong bytes"; false; }

  # guest_keep tells a human how to get back in — the whole point of keeping a
  # failed guest alive.
  run guest_keep
  printf '%s\n' "$output" | grep -Fq "$GUEST_NAME" || { echo "$output"; false; }

  run guest_destroy
  [ "$status" -eq 0 ] || { echo "guest_destroy: $output"; false; }
  run guest_exec 'true'
  [ "$status" -ne 0 ] || { echo "the guest survived guest_destroy"; false; }
}

@test "the container adapter's password mode really requires a password" {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "no running docker daemon (start colima)"

  export GUEST_IMAGE=ubuntu:24.04
  export GUEST_SUDO=password
  export GUEST_DEPS='apt-get update -qq && apt-get install -y -qq sudo'
  # shellcheck source=tests/real/guests/container.sh
  . "$REAL/guests/container.sh"

  run guest_start
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run guest_provision
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  # This is the assertion the whole password axis rests on: if NOPASSWD leaks in,
  # `sudo -n` succeeds, the askpass helper is never consulted, and the axis silently
  # tests nothing.
  run guest_exec 'sudo -n true'
  [ "$status" -ne 0 ] || { echo "NOPASSWD leaked into the password mode"; false; }

  # SUDO_ASKPASS ALONE is not enough, contrary to sudo's own man page. Asserted, not
  # assumed: the day sudo starts honouring it, this case is where that shows up, and
  # bin/sudo-forces-askpass can go.
  run guest_exec "printf '%s' '$GUEST_PASSWORD' > $GUEST_STATE/password"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run guest_exec "SUDO_ASKPASS=$GUEST_SRC/tests/real/bin/askpass VIBE_REAL_DIR=$GUEST_STATE sudo true"
  [ "$status" -ne 0 ] || { echo "SUDO_ASKPASS alone now works — drop the shim"; false; }

  # The mechanism the lane actually uses: the shim ahead of the real sudo on PATH.
  # Plain `sudo`, exactly as blocks/git/apply.sh calls it, goes through and logs
  # exactly one prompt.
  run guest_exec "mkdir -p $GUEST_STATE/bin && cp $GUEST_SRC/tests/real/bin/sudo-forces-askpass $GUEST_STATE/bin/sudo && chmod 0755 $GUEST_STATE/bin/sudo"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run guest_exec "rm -f $GUEST_STATE/askpass.log; PATH=$GUEST_STATE/bin:\$PATH SUDO_ASKPASS=$GUEST_SRC/tests/real/bin/askpass VIBE_REAL_DIR=$GUEST_STATE sudo true"
  [ "$status" -eq 0 ] || { echo "sudo through the shim failed: $output"; false; }
  run guest_exec "wc -l < $GUEST_STATE/askpass.log"
  [ "$(printf '%s' "$output" | tr -d ' ')" = "1" ] || { echo "askpass log has [$output] lines"; false; }
}

# ── The tart adapter ─────────────────────────────────────────────────────────

# bats test_tags=integration
@test "the tart adapter satisfies the same guest port" {
  command -v tart >/dev/null 2>&1 || skip "tart not installed"
  [ -f "$REAL/guests/tart.sh" ] || skip "no tart adapter yet"
  tart list 2>/dev/null | grep -q 'macos-tahoe-vanilla' || skip "the macos-tahoe-vanilla image is not pulled"
  command -v sshpass >/dev/null 2>&1 || skip "sshpass not installed"

  export GUEST_IMAGE=macos-tahoe-vanilla
  # shellcheck source=tests/real/guests/tart.sh
  . "$REAL/guests/tart.sh"

  run guest_start
  [ "$status" -eq 0 ] || { echo "guest_start: $output"; false; }
  run guest_provision
  [ "$status" -eq 0 ] || { echo "guest_provision: $output"; false; }

  run guest_exec 'id -un'
  [ "$output" = "$GUEST_USER" ] || { echo "guest_exec ran as [$output]"; false; }
  run guest_exec 'test -t 0'
  [ "$status" -ne 0 ] || { echo "guest_exec has a tty"; false; }
  run guest_exec 'exit 7'
  [ "$status" -eq 7 ] || { echo "status was $status, want 7"; false; }
  run guest_exec "test -f $GUEST_SRC/lib/apply.sh"
  [ "$status" -eq 0 ] || { echo "the repo is not mounted at $GUEST_SRC"; false; }
  run guest_exec "touch $GUEST_SRC/.contract-write-probe"
  [ "$status" -ne 0 ] || { echo "the repo is WRITABLE to the run"; false; }

  run guest_exec "printf 'hello\n' > $GUEST_STATE/contract"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run guest_fetch "$GUEST_STATE/contract" "$BATS_TEST_TMPDIR/fetched"
  [ "$status" -eq 0 ] || { echo "guest_fetch: $output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/fetched")" = "hello" ] || { echo "fetched the wrong bytes"; false; }

  run guest_destroy
  [ "$status" -eq 0 ] || { echo "guest_destroy: $output"; false; }
}

# ── The runner adapter (no virtualisation: the machine IS the throwaway) ───────

@test "the runner adapter satisfies the same guest port" {
  # No docker and no VM needed, so this leg runs everywhere - which is what stops the
  # port contract being vacuous on a machine with no container daemon.
  # VIBE_REAL_ALLOW_HOST is the adapter's own safety catch; nothing here runs an entry
  # point, so nothing is installed.
  export VIBE_REAL_ALLOW_HOST=1
  export GUEST_IMAGE=this-machine
  export GUEST_STATE="$BATS_TEST_TMPDIR/state"
  # shellcheck source=tests/real/guests/runner.sh
  . "$REAL/guests/runner.sh"

  run guest_start
  [ "$status" -eq 0 ] || { echo "guest_start: $output"; false; }
  run guest_provision
  [ "$status" -eq 0 ] || { echo "guest_provision: $output"; false; }

  run guest_exec 'id -un'
  [ "$output" = "$GUEST_USER" ] || { echo "guest_exec ran as [$output]"; false; }
  run guest_exec 'test -t 0'
  [ "$status" -ne 0 ] || { echo "guest_exec has a tty"; false; }
  run guest_exec 'exit 7'
  [ "$status" -eq 7 ] || { echo "status was $status, want 7"; false; }

  run guest_exec "test -f $GUEST_SRC/lib/apply.sh"
  [ "$status" -eq 0 ] || { echo "the repo is not at $GUEST_SRC"; false; }
  run guest_exec "touch $GUEST_SRC/.contract-write-probe"
  [ "$status" -ne 0 ] || { echo "the repo copy is WRITABLE to the run"; false; }

  run guest_exec "printf 'hello\n' > $GUEST_STATE/contract"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run guest_fetch "$GUEST_STATE/contract" "$BATS_TEST_TMPDIR/fetched"
  [ "$status" -eq 0 ] || { echo "guest_fetch: $output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/fetched")" = "hello" ] || { echo "fetched the wrong bytes"; false; }

  run guest_destroy
  [ "$status" -eq 0 ] || { echo "guest_destroy: $output"; false; }
}

@test "the runner adapter refuses to install into a home nobody asked it to" {
  # The one thing standing between `mise run vm-test` and a developer's real $HOME.
  unset VIBE_REAL_ALLOW_HOST
  local saved_ci="${CI:-}"
  unset CI
  export GUEST_IMAGE=this-machine
  export GUEST_STATE="$BATS_TEST_TMPDIR/state"
  # shellcheck source=tests/real/guests/runner.sh
  . "$REAL/guests/runner.sh"
  run guest_provision
  [ -z "$saved_ci" ] || export CI="$saved_ci"
  [ "$status" -ne 0 ] || { echo "the runner adapter provisioned unasked"; false; }
  printf '%s\n' "$output" | grep -q 'VIBE_REAL_ALLOW_HOST' || { echo "$output"; false; }
}

@test "drive.sh's lane groups can never select the runner adapter" {
  # Belt to the adapter's braces: the group filters are what `mise run vm-test` uses,
  # and the runner adapter installs into the real $HOME of whatever machine it is on.
  # Asserted through the same lane_names() drive.sh calls, over the real matrix.
  # shellcheck source=tests/real/lib/lanes.sh
  . "$REAL/lib/lanes.sh"
  local runner_lanes
  runner_lanes="$(lane_names "$REAL/lanes.tsv" runner)"
  [ -n "$runner_lanes" ] || skip "no runner lanes to guard"

  local selectable
  selectable="$(lane_names "$REAL/lanes.tsv" container tart)"
  for l in $runner_lanes; do
    printf '%s\n' "$selectable" | grep -qx "$l" \
      && { echo "the 'all' group can select the runner lane $l"; false; }
  done
  # And drive.sh really asks for those two groups, rather than everything.
  grep -q 'lane_names "$REAL/lanes.tsv" container tart' "$REAL/drive.sh" \
    || { echo "drive.sh's 'all' group no longer names its adapters"; false; }
}
