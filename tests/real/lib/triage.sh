# shellcheck shell=bash
# triage.sh: is this transcript a story about vibe, or about the world around it?
#
#   triage <transcript> [ref]   — sets TRIAGE_CLASS, TRIAGE_REASON, TRIAGE_HINT
#
# PURE: a file and a string in, three variables out. It reads no machine, runs no
# binary and touches no network — the same split as the probe/judge, and for the
# same reason. This is a decision over text that used to be entangled with the
# imperative flow of one lane, so it could only be exercised by running that lane;
# as a function it gets a bats table, and it is a rule that has earned one. A lane
# reporting "upstream moved" as "vibe is broken" is a lane that gets muted, and a
# lane reporting the reverse is worse.
#
# TRANSPORT failures only, matched on the vendor tools' own wording — AND only while
# the run did not reach its own clean verdict. That second half is the correction:
# every pattern here matches text that APPEARED, with no notion of recovery, so a
# retried mirror timeout returned class 2 BEFORE the probe ran, and a genuine
# regression later in the same run was never judged at all. An infrastructure error
# stops being one the moment the business outcome changes, and "Setup complete." is
# the applier's own statement that the outcome is an install worth judging.
#
# bash-3.2-clean. Sourced, not executed.

# CLASS_* live in lib/class.sh — the one owner of the severity order. Sourced here
# too so this file stands alone under a test that has not sourced the runner.
# shellcheck source=tests/real/lib/class.sh
[ -n "${CLASS_INFRA:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/class.sh"

TRIAGE_CLASS=0   # 0 = nothing here stops the probe and judge deciding
TRIAGE_REASON="" # what to tell the reader
TRIAGE_HINT=""   # the caveat behind the reason, where there is one

triage() {
  TRIAGE_CLASS=0
  TRIAGE_REASON=""
  TRIAGE_HINT=""
  _t_log="$1"
  _t_ref="${2:-}"

  if [ ! -f "$_t_log" ]; then
    TRIAGE_CLASS="$CLASS_HARNESS"
    TRIAGE_REASON="there is no transcript to read at $_t_log"
    return 0
  fi

  # THE recovery rule, and it comes first deliberately. A run that printed its own
  # clean verdict got to the end, so whatever transport wording appeared on the way
  # is something it survived — and the probe and judge must be allowed to look at
  # what it left behind.
  if grep -Fq 'Setup complete.' "$_t_log" 2>/dev/null; then
    return 0
  fi

  # The bootstrap failing to DELIVER vibe is infrastructure, not a vibe assertion:
  # there is no install to judge.
  if grep -Fq 'could not fetch' "$_t_log" 2>/dev/null ||
     grep -Fq 'unexpected tarball layout' "$_t_log" 2>/dev/null; then
    TRIAGE_CLASS="$CLASS_INFRA"
    if [ -n "$_t_ref" ]; then
      TRIAGE_REASON="the bootstrap could not fetch vibe (ref '$_t_ref')"
    else
      TRIAGE_REASON="the bootstrap could not fetch vibe"
    fi
    return 0
  fi

  # So is the network being unreachable. Observed the hard way: a lane went red for
  # "Couldn't install Node.js" when the real cause was one DNS lookup failing inside
  # the container. Reporting that as "vibe is wrong" is how a lane earns a mute.
  #
  # A 404 is included because a vendor deleting an installer is the single most
  # likely thing these lanes exist to catch — with the caveat spelled out, since a
  # 404 can equally mean OUR url is wrong, and that is a class-1 bug in a class-2
  # coat.
  _t_net="$(grep -oE 'Temporary failure in name resolution|Could not resolve host|dns error|Connection timed out|Connection refused|Network is unreachable|Could not connect to server|error sending request|The requested URL returned error: (404|5[0-9][0-9])|HTTP request sent.*(404|503)' \
    "$_t_log" 2>/dev/null | head -1)"
  if [ -n "$_t_net" ]; then
    TRIAGE_CLASS="$CLASS_INFRA"
    TRIAGE_REASON="the guest could not reach the network: '$_t_net'"
    TRIAGE_HINT="if that was a 404, check the INSTALL cell's url as well as the vendor"
    return 0
  fi

  # And so is a guest whose CPU cannot execute the vendor's binary. archlinux:base
  # publishes no arm64 image, so on Apple Silicon that lane runs emulated x86_64 and
  # Claude Code's x64 build dies on missing AVX. That says nothing about vibe.
  _t_cpu="$(grep -oE 'CPU lacks AVX support|Illegal instruction|exec format error|cannot execute binary file|Exec format error' \
    "$_t_log" 2>/dev/null | head -1)"
  if [ -n "$_t_cpu" ]; then
    TRIAGE_CLASS="$CLASS_INFRA"
    TRIAGE_REASON="the guest cannot execute a vendor binary: '$_t_cpu' (an emulated arch?)"
    return 0
  fi

  return 0
}
