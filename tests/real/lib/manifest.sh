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
# bump is a red, too loose and the differential proves nothing. Hence two subsets,
# each with a stated reason.
#
# Sourced, not executed. bash-3.2-clean.

# manifest_state_subset <file> — the keys that must be IDENTICAL between two runs of
# the same lane (idempotence) and between two entry points on the same guest
# (apply.sh vs the real paste). Everything about the machine's resulting state; none
# of the narration.
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
  awk -F'\t' '
    /^#/ { next }
    NF < 2 { next }
    $1 ~ /^(lane|adapter|guest|axis|mode|run|manifest_version)$/ { next }
    $1 ~ /^(transcript|warn|info|error|askpass|probe)\./ { next }
    $1 ~ /\.version_raw$/ { next }
    { print }
  ' "$1" | sort
}

# manifest_invariant_subset <file> — the keys that must be identical across EVERY
# POSIX lane, whatever the distro and whatever the paste. Deliberately tiny, because
# a big cross-distro subset would be a lie: the lanes install different tools by
# design, so most keys are supposed to differ.
#
# What is left is the design claim itself — one PATH line, written once, the same
# everywhere, and one canonical instructions path — which is exactly the thing a
# distro-specific regression would break.
manifest_invariant_subset() {
  awk -F'\t' '
    $1 == "rc.block" ||
    $1 == "rc.marker_count" ||
    $1 == "rc.vendor_path_lines" ||
    $1 == "instructions.canonical" ||
    $1 == "instructions.canonical.nonempty" { print }
  ' "$1" | sort
}

# manifest_diff <label-a> <file-a> <label-b> <file-b> <subset-fn> — 0 when the two
# subsets agree. On disagreement it NAMES the differing keys, because "the
# differential failed" is not a finding a reader can act on.
manifest_diff() {
  _md_a_label="$1"; _md_a="$2"; _md_b_label="$3"; _md_b="$4"; _md_fn="$5"
  _md_tmp="${TMPDIR:-/tmp}/vibe-mdiff.$$"
  mkdir -p "$_md_tmp" || return 1
  "$_md_fn" "$_md_a" > "$_md_tmp/a"
  "$_md_fn" "$_md_b" > "$_md_tmp/b"
  if diff -u "$_md_tmp/a" "$_md_tmp/b" > "$_md_tmp/d" 2>&1; then
    rm -rf "$_md_tmp"
    return 0
  fi
  printf '  differential %s vs %s disagrees:\n' "$_md_a_label" "$_md_b_label"
  sed -n '3,$p' "$_md_tmp/d" | sed 's/^/    /'
  rm -rf "$_md_tmp"
  return 1
}
