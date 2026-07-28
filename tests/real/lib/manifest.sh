# shellcheck shell=bash
# manifest.sh: the manifest DIFFERENTIALS — the half of the oracle that needs no
# hand-written expectations at all.
#
# The judge asserts only what a fake structurally cannot reach. Everything else is
# proved by making two runs that OUGHT to agree produce an identical normalised
# state, so a new block is covered automatically and there is no second copy of the
# expectations to drift.
#
# Which keys are compared is the load-bearing decision: too strict and every version
# bump is a red, too loose and the differential proves nothing. Hence three subsets,
# each with a stated reason and each answering a different question.
#
# Sourced, not executed. bash-3.2-clean.
#
# Every subset FAILS rather than yielding nothing. Two manifests sharing no keys
# produce two empty subsets, `diff` succeeds, and the differential reported
# agreement while comparing nothing at all — so a probe regression that stopped
# emitting `rc.block`, or a manifest that could not be read, would make the driver
# print "the OS-invariant subset agrees" for every lane pair in the matrix. A
# minimum key count is the cheapest thing that cannot be satisfied by silence.

# What a subset must yield for a comparison to mean anything. The invariant subset
# selects exactly five named keys, so anything less is a key that vanished; the state
# subset carries ~60 on a real manifest, and 20 is well under any legitimate lane
# while still far above "the file was empty".
MANIFEST_STATE_MIN=20
MANIFEST_INVARIANT_MIN=5

# _manifest_subset_guard <file> <label> <min> — reads stdin (the subset), prints it,
# and fails when there is not enough of it to be a measurement.
_manifest_subset_guard() {
  _msg_body="$(cat)"
  _msg_n="$(printf '%s\n' "$_msg_body" | grep -c '[^[:space:]]')"
  if [ "$_msg_n" -lt "$3" ]; then
    printf 'manifest: %s yielded %s %s keys, fewer than the %s a real manifest carries\n' \
      "$1" "$_msg_n" "$2" "$3" >&2
    return 1
  fi
  printf '%s\n' "$_msg_body"
}

# manifest_state_subset <file> — the keys that must be IDENTICAL between two runs of
# the same lane on ONE guest (idempotence). Everything about the machine's resulting
# state; none of the narration. Across guests, use manifest_entry_subset.
#
# Excluded, and why:
#   lane / adapter / guest / axis / mode / run  — identify the run, not its result
#   transcript.* warn.* info.* error.*          — "no NEW warnings" is the judge's
#                                                 job; run 2 legitimately says
#                                                 "already installed" instead of
#                                                 "installed"
#   tool.*.version_raw                          — a release landing mid-lane would
#                                                 make idempotence red for a reason
#                                                 that is not a bug
#   askpass.* probe.missing.*                   — per-run harness records
manifest_state_subset() {
  [ -r "$1" ] || { printf 'manifest: cannot read %s\n' "$1" >&2; return 1; }
  awk -F'\t' '
    /^#/ { next }
    NF < 2 { next }
    $1 ~ /^(lane|adapter|guest|axis|mode|run|manifest_version)$/ { next }
    $1 ~ /^(transcript|warn|info|error|askpass|probe)\./ { next }
    $1 ~ /\.version_raw$/ { next }
    { print }
  ' "$1" | sort | _manifest_subset_guard "$1" state "$MANIFEST_STATE_MIN"
}

# manifest_entry_subset <file> — the state subset MINUS what a vendor seeds with
# per-install randomness. Used for the apply-vs-paste differential, which compares
# two different GUESTS; manifest_state_subset compares two runs on ONE guest, where
# these keys are stable and worth asserting.
#
# Exactly one key today, and it is measured rather than assumed: Claude Code's own
# installer writes ~/.claude.json before vibe looks at it, carrying firstStartTime,
# machineID and userID. vibe's preseed_claude_trust then leaves it alone by design
# ("never edit an existing config"), so the hash differs between any two machines
# and is identical between two runs on one - which is precisely the split below.
manifest_entry_subset() {
  manifest_state_subset "$1" | awk -F'\t' '$1 != "path.claude-json"'
}

# manifest_invariant_subset <file> — the keys that must be identical across EVERY
# POSIX lane, whatever the distro and whatever the paste. Deliberately tiny, because
# a big cross-distro subset would be a lie: the lanes install different tools by
# design, so most keys are supposed to differ.
#
# What is left is the design claim itself — one PATH line, written once, the same
# everywhere, and one canonical instructions path — which is exactly the thing a
# distro-specific regression would break.
#
# POSIX-only, and refused rather than left to the caller: the PowerShell spine
# persists no PATH at all, so a Windows manifest carries none of the rc keys and
# would otherwise trip the minimum below with a puzzling message.
manifest_invariant_subset() {
  [ -r "$1" ] || { printf 'manifest: cannot read %s\n' "$1" >&2; return 1; }
  case "$(awk -F'\t' '$1 == "os" { print $2; exit }' "$1")" in
    win) printf 'manifest: %s is a Windows manifest, and the invariant subset is the POSIX rc claim\n' "$1" >&2
         return 1 ;;
  esac
  awk -F'\t' '
    $1 == "rc.block" ||
    $1 == "rc.marker_count" ||
    $1 == "rc.vendor_path_lines" ||
    $1 == "instructions.canonical" ||
    $1 == "instructions.canonical.nonempty" { print }
  ' "$1" | sort | _manifest_subset_guard "$1" invariant "$MANIFEST_INVARIANT_MIN"
}

# manifest_diff <label-a> <file-a> <label-b> <file-b> <subset-fn> — 0 when the two
# subsets agree. On disagreement it NAMES the differing keys, because "the
# differential failed" is not a finding a reader can act on.
manifest_diff() {
  _md_a_label="$1"; _md_a="$2"; _md_b_label="$3"; _md_b="$4"; _md_fn="$5"
  _md_tmp="${TMPDIR:-/tmp}/vibe-mdiff.$$"
  mkdir -p "$_md_tmp" || return 1
  # The subset's own status decides, before diff gets a look in: comparing two
  # things neither of which could be read is not a comparison, and `diff` calls it
  # a match.
  if ! "$_md_fn" "$_md_a" > "$_md_tmp/a" || ! "$_md_fn" "$_md_b" > "$_md_tmp/b"; then
    printf '  differential %s vs %s could not be taken — one side yielded no usable subset\n' \
      "$_md_a_label" "$_md_b_label"
    rm -rf "$_md_tmp"
    return 1
  fi
  if diff -u "$_md_tmp/a" "$_md_tmp/b" > "$_md_tmp/d" 2>&1; then
    rm -rf "$_md_tmp"
    return 0
  fi
  printf '  differential %s vs %s disagrees:\n' "$_md_a_label" "$_md_b_label"
  sed -n '3,$p' "$_md_tmp/d" | sed 's/^/    /'
  rm -rf "$_md_tmp"
  return 1
}
