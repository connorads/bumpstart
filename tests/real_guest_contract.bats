#!/usr/bin/env bats
#
# The guest port contract. One tiny interface, three adapters, so `lanes/run.sh` is a
# single lane runner rather than a Linux script and a near-identical macOS one - and
# so the deferred local Windows guest becomes a fourth adapter rather than a fourth
# lane.
#
# ONE contract body, parameterised by adapter, run three times. That shape is the
# point: every adapter finding in the last round was a property asserted for
# `container` and forgotten elsewhere - the runner adapter inherited the caller's
# tty, guaranteed nothing about $SHELL, and its guest_fetch was never asked about a
# file that is not there. Per-adapter test bodies are how that happens; a shared one
# is how it stops.
#
# The properties, and what each would break:
#
#   guest_exec runs as an UNPRIVILEGED user      root skips every sudo path, and
#                                                bypasses the read-only repo below -
#                                                so the runner adapter, whose lane
#                                                user IS the caller, refuses root
#                                                rather than asserting less
#   ...with the target user's HOME               everything vibe writes lands there
#   ...with a bash or zsh $SHELL                 persist_path keys on it; an `sh`
#                                                $SHELL makes the probe report
#                                                `rc.file none` and every rc
#                                                assertion fail for a harness reason
#   ...with NO tty                               every prompt in the product is
#                                                `[ -t 0 ]`-gated, so a TTY hangs the
#                                                run rather than testing it
#   ...over POSIX sh constructs                  the interpreting shell differs by
#                                                adapter (bash / zsh / sh), so the
#                                                constructs run.sh really uses are
#                                                asserted on all three
#   the exit status comes back                   the applier's status is a data point
#   the repo is READ-ONLY to that user           a lane must not dirty the tree it is
#                                                testing
#   guest_fetch reports a file that is NOT there run.sh reads that status to tell
#                                                "the probe crashed" from "it ran"
#
# The runner leg needs nothing installed, so it runs everywhere - which is what stops
# the contract being vacuous on a machine with no container daemon. The container leg
# needs a docker daemon; the tart leg is `integration`-tagged because it boots a real
# macOS VM.

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

# start_guest / provision_guest — NOT `run guest_start`. bats' `run` evaluates its
# command inside a command substitution, so anything the adapter sets on the way up
# is lost with the subshell: the tart adapter's TART_IP and the runner adapter's
# GUEST_SHELL are both decided by guest_start and read by guest_exec. Redirection
# keeps the diagnostics without the subshell.
start_guest() {
  if ! guest_start > "$BATS_TEST_TMPDIR/start.log" 2>&1; then
    echo "guest_start failed:"; cat "$BATS_TEST_TMPDIR/start.log"; false
  fi
}
provision_guest() {
  if ! guest_provision > "$BATS_TEST_TMPDIR/provision.log" 2>&1; then
    echo "guest_provision failed:"; cat "$BATS_TEST_TMPDIR/provision.log"; false
  fi
}

# ── The shared body ───────────────────────────────────────────────────────────

# assert_guest_port — every property the lane runner relies on, against whichever
# adapter is currently sourced and started.
assert_guest_port() {
  # Unprivileged, and with the identity the run needs.
  run guest_exec 'id -un'
  [ "$output" = "$GUEST_USER" ] || { echo "guest_exec ran as [$output]"; false; }
  run guest_exec 'printf "%s\n" "$HOME"'
  [ -n "$output" ] || { echo "guest_exec has no HOME"; false; }
  [ "$output" != "/" ] || { echo "HOME is /"; false; }
  local home="$output"
  run guest_exec 'test -d "$HOME" && test -w "$HOME"'
  [ "$status" -eq 0 ] || { echo "HOME ($home) is not a writable directory"; false; }

  # $SHELL, which persist_path keys on. Not merely set: set to a shell vibe
  # persists into, or the lane asserts nothing about persistence.
  run guest_exec 'printf "%s\n" "${SHELL:-unset}"'
  case "$(basename "$output")" in
    bash|zsh) : ;;
    *) echo "SHELL is [$output], which persist_path would only print advice for"; false ;;
  esac

  # No tty: every interactive prompt in the product is `[ -t 0 ]`-gated, so this is
  # what makes a headless run deterministic instead of a hang.
  run guest_exec 'test -t 0'
  [ "$status" -ne 0 ] || { echo "guest_exec has a tty on stdin"; false; }
  run guest_exec 'test -t 1'
  [ "$status" -ne 0 ] || { echo "guest_exec has a tty on stdout"; false; }

  # And the run cannot SEE the caller's stdin either, which is the property `test -t
  # 0` cannot check: under bats the caller's stdin happens to be /dev/null, so an
  # adapter that simply inherits it looks correct here and hangs the moment the lane
  # is driven from a terminal. `/bin/sh -c` inherits; `ssh` forwards. Both had to be
  # told not to.
  local got
  got="$(printf 'CALLER-STDIN\n' | guest_exec 'head -c 32 || true' 2>/dev/null)"
  [ -z "$got" ] || { echo "guest_exec read the caller's stdin: [$got]"; false; }

  # The exit status comes back, unchanged.
  run guest_exec 'exit 7'
  [ "$status" -eq 7 ] || { echo "status was $status, want 7"; false; }

  # The constructs the lane runner really sends, on every adapter. The interpreting
  # shell is bash here, zsh there and sh on the runner, so a bashism that passed on
  # one and failed on two is exactly the failure this case exists to catch.
  run guest_exec 'cd "$HOME" && { export NO_COLOR=1; printf "%s|%s\n" "$NO_COLOR" "$(id -un)" ; } > port.probe 2>&1; printf "%s\n" $? >> port.probe; cat port.probe; rm -f port.probe'
  [ "$status" -eq 0 ] || { echo "the lane runner's own construct failed: $output"; false; }
  printf '%s\n' "$output" | grep -q "^1|$GUEST_USER$" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^0$' || { echo "the exit capture did not land: $output"; false; }

  # The repo is there, and read-only to the identity that matters - the run's own.
  # The container and tart adapters get that from a mount option, the runner adapter
  # from permission bits (which root could still override).
  run guest_exec "test -f $GUEST_SRC/lib/apply.sh"
  [ "$status" -eq 0 ] || { echo "the repo is not at $GUEST_SRC"; false; }
  run guest_exec "touch $GUEST_SRC/.contract-write-probe"
  [ "$status" -ne 0 ] || { echo "the repo is WRITABLE to the run"; false; }

  # The state dir exists and the unprivileged user can write it.
  run guest_exec "printf 'hello\n' > $GUEST_STATE/contract"
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  run guest_fetch "$GUEST_STATE/contract" "$BATS_TEST_TMPDIR/fetched"
  [ "$status" -eq 0 ] || { echo "guest_fetch: $output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/fetched")" = "hello" ] || { echo "fetched the wrong bytes"; false; }

  # And a file that is NOT there is a failure, not a silent empty copy. run.sh reads
  # this status to tell "the probe crashed" from "the probe ran" - and it is on the
  # checked path for the manifest, the transcript and the askpass log.
  run guest_fetch "$GUEST_STATE/never-written-$$" "$BATS_TEST_TMPDIR/missing"
  [ "$status" -ne 0 ] || { echo "guest_fetch reported success for a file that is not there"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/missing" ] || { echo "guest_fetch left bytes behind"; false; }
}

# ── The container adapter ─────────────────────────────────────────────────────

@test "the container adapter satisfies the guest port" {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "no running docker daemon (start colima)"

  export GUEST_IMAGE=ubuntu:24.04
  # shellcheck source=tests/real/guests/container.sh
  . "$REAL/guests/container.sh"

  start_guest

  run guest_exec_root 'id -u'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "0" ] || { echo "guest_exec_root is not root: $output"; false; }

  provision_guest

  assert_guest_port

  # Adapter-specific: a container's home really is /home/<user>, and guest_keep
  # tells a human how to get back in - the whole point of keeping a failed guest.
  run guest_exec 'printf "%s\n" "$HOME"'
  [ "$output" = "/home/$GUEST_USER" ] || { echo "HOME is [$output]"; false; }
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

  start_guest
  provision_guest

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
  tart list 2>/dev/null | grep -q 'macos-tahoe-vanilla' || skip "the macos-tahoe-vanilla image is not pulled"
  command -v sshpass >/dev/null 2>&1 || skip "sshpass not installed"

  export GUEST_IMAGE=macos-tahoe-vanilla
  # shellcheck source=tests/real/guests/tart.sh
  . "$REAL/guests/tart.sh"

  start_guest
  provision_guest

  assert_guest_port

  run guest_destroy
  [ "$status" -eq 0 ] || { echo "guest_destroy: $output"; false; }
}

# bats test_tags=integration
@test "a kept tart guest is stopped before the next run deletes it" {
  # A class-1 failure keeps the guest alive on purpose, so the NEXT run finds it
  # running - and `tart delete` refuses while it is, so the clone fails and the lane
  # reports class 2, "not a vibe failure", from then on. One real assertion failure
  # silently demoting itself to not-red.
  command -v tart >/dev/null 2>&1 || skip "tart not installed"
  tart list 2>/dev/null | grep -q 'macos-tahoe-vanilla' || skip "the macos-tahoe-vanilla image is not pulled"
  command -v sshpass >/dev/null 2>&1 || skip "sshpass not installed"

  export GUEST_IMAGE=macos-tahoe-vanilla
  # shellcheck source=tests/real/guests/tart.sh
  . "$REAL/guests/tart.sh"

  start_guest
  # Exactly what a kept corpse looks like: still running, nothing cleaned up.
  start_guest
  run guest_exec 'id -un'
  [ "$status" -eq 0 ] || { echo "the re-clone is not reachable: $output"; false; }
}

# ── The runner adapter (no virtualisation: the machine IS the throwaway) ───────

@test "the runner adapter satisfies the same guest port, or refuses when it cannot" {
  # No docker and no VM needed, so this leg runs everywhere - which is what stops the
  # port contract being vacuous on a machine with no container daemon.
  # VIBE_REAL_ALLOW_HOST is the adapter's own safety catch; nothing here runs an entry
  # point, so nothing is installed.
  export VIBE_REAL_ALLOW_HOST=1
  export GUEST_IMAGE=this-machine
  export GUEST_STATE="$BATS_TEST_TMPDIR/state"
  # shellcheck source=tests/real/guests/runner.sh
  . "$REAL/guests/runner.sh"

  # Root asserts the REFUSAL, not a skip. This adapter runs the lane as the invoking
  # user and enforces the read-only repo with permission bits, so under root the port
  # cannot hold - `touch` in a directory stripped by `chmod -R a-w` succeeds. Two
  # branches, both asserting: a skip here would quietly stop testing the adapter in
  # every root container, which is where it ran.
  if [ "$(id -u)" = 0 ]; then
    run guest_start
    [ "$status" -ne 0 ] || { echo "the runner adapter started as root"; false; }
    printf '%s\n' "$output" | grep -q 'root' || { echo "$output"; false; }
    [ ! -d "$GUEST_SRC" ] || { echo "it copied the repo before refusing"; false; }
    return 0
  fi

  start_guest
  provision_guest

  assert_guest_port
}

@test "the runner adapter refuses to install into a home nobody asked it to" {
  # The one thing standing between `mise run vm-test` and a developer's real $HOME -
  # and it is checked in guest_start, BEFORE the repo copy that used to happen first.
  unset VIBE_REAL_ALLOW_HOST
  local saved_ci="${CI:-}"
  unset CI
  export GUEST_IMAGE=this-machine
  export GUEST_STATE="$BATS_TEST_TMPDIR/state"
  # shellcheck source=tests/real/guests/runner.sh
  . "$REAL/guests/runner.sh"

  run guest_start
  [ -z "$saved_ci" ] || export CI="$saved_ci"
  [ "$status" -ne 0 ] || { echo "the runner adapter started unasked"; false; }
  printf '%s\n' "$output" | grep -q 'VIBE_REAL_ALLOW_HOST' || { echo "$output"; false; }
  [ ! -d "$GUEST_SRC" ] || { echo "it copied the repo before refusing"; false; }

  unset CI
  run guest_provision
  [ -z "$saved_ci" ] || export CI="$saved_ci"
  [ "$status" -ne 0 ] || { echo "the runner adapter provisioned unasked"; false; }
}

@test "the runner adapter refuses the password axis, which it cannot honour" {
  # A hosted runner has NOPASSWD sudo, so a password lane here would pass while
  # asserting nothing - the same refusal the tart adapter makes for the same reason.
  export VIBE_REAL_ALLOW_HOST=1
  export GUEST_IMAGE=this-machine
  export GUEST_STATE="$BATS_TEST_TMPDIR/state"
  export GUEST_SUDO=password
  # shellcheck source=tests/real/guests/runner.sh
  . "$REAL/guests/runner.sh"
  # guest_provision directly, with no guest_start: this refusal lives in provision,
  # and guest_start refuses a root caller before reaching it - so going through it
  # would make the case depend on the identity running the suite rather than on the
  # axis.
  run guest_provision
  [ "$status" -ne 0 ] || { echo "the password axis was accepted on a NOPASSWD runner"; false; }
  printf '%s\n' "$output" | grep -q 'NOPASSWD' || { echo "$output"; false; }
}

@test "the runner adapter destroys its copy despite the permission bits it set" {
  export VIBE_REAL_ALLOW_HOST=1
  export GUEST_IMAGE=this-machine
  export GUEST_STATE="$BATS_TEST_TMPDIR/state"
  # shellcheck source=tests/real/guests/runner.sh
  . "$REAL/guests/runner.sh"

  # Root never gets a copy to destroy, because guest_start refuses first. What is
  # left worth asserting is that teardown is still safe to call after a refusal -
  # lanes/run.sh's cleanup() runs on every exit path, that one included.
  if [ "$(id -u)" = 0 ]; then
    run guest_start
    [ "$status" -ne 0 ] || { echo "the runner adapter started as root"; false; }
    run guest_destroy
    [ "$status" -eq 0 ] || { echo "guest_destroy after a refusal: $output"; false; }
    [ ! -d "$GUEST_SRC" ] || { echo "$GUEST_SRC exists after a refusal"; false; }
    return 0
  fi

  start_guest
  [ -d "$GUEST_SRC" ] || { echo "no copy at $GUEST_SRC"; false; }
  run guest_destroy
  [ "$status" -eq 0 ] || { echo "guest_destroy: $output"; false; }
  [ ! -d "$GUEST_SRC" ] || { echo "the read-only copy survived its own permission bits"; false; }
}

@test "drive.sh's lane groups can never select the runner adapter" {
  # Belt to the adapter's braces: the group filters are what `mise run vm-test` uses,
  # and the runner adapter installs into the real $HOME of whatever machine it is on.
  # Asserted through the same lane_names() drive.sh calls, over the real matrix.
  # shellcheck source=tests/real/lib/lanes.sh
  . "$REAL/lib/lanes.sh"
  local runner_lanes selectable
  runner_lanes="$(lane_names "$REAL/lanes.tsv" runner)"
  [ -n "$runner_lanes" ] || skip "no runner lanes to guard"

  selectable="$(lane_names "$REAL/lanes.tsv" container tart)"
  for l in $runner_lanes; do
    printf '%s\n' "$selectable" | grep -qx "$l" \
      && { echo "the 'all' group can select the runner lane $l"; false; }
  done
  grep -q 'lane_names "$REAL/lanes.tsv" container tart' "$REAL/drive.sh" \
    || { echo "drive.sh's 'all' group no longer names its adapters"; false; }
}
