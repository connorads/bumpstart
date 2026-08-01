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
# POSIX-only, and refused rather than left to the caller: the Windows spine persists
# into a registry value, not an rc file, so a Windows manifest carries no rc.block and
# no marker count - there is nowhere in a registry value to put a marker - and it would
# otherwise trip the minimum below with a puzzling message. The refusal is about the
# SHAPE of the claim, not about whether Windows persists anything: since
# lib/shellpath.ps1 it does, and rc.persists_path is where that is recorded.
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

# _manifest_compare <label-a> <file-a> <label-b> <file-b> — compare two subsets and
# print one indented line per difference. 0 when they agree, 1 when they do not.
#
# awk, NOT `diff`. `diff` is not in archlinux:base (the `base` metapackage carries no
# diffutils), and its absence arrived here as a NON-ZERO STATUS - which manifest_diff
# read as "the manifests disagree", while the `sed -n '3,$p'` that stripped diff's
# header deleted the only line in the file. Eleven cases reported "vibe is wrong" and
# named no key. A missing tool is a harness bug; the way to stop misclassifying it is
# to stop depending on it, and this was the only `diff` in the test tree.
#
# It also reports better than a unified diff: keys that DIFFER, keys only in A and
# keys only in B, which is what this function's callers say they name. Both sides are
# already sorted `key<TAB>value`, so a hash join is all it takes.
#
# FNR == NR is safe here because manifest_diff is the only caller and it passes two
# distinct files that the subset guard has already refused to leave empty. A key
# appearing twice on one side folds into one entry carrying both values, so a
# duplicate still differs from a single. POSIX awk, bash-3.2-clean.
_manifest_compare() {
  awk -v la="$1" -v lb="$3" '
    {
      p = index($0, "\t")
      if (p < 2) next
      k = substr($0, 1, p - 1)
      v = substr($0, p + 1)
      if (FNR == NR) {
        if (k in a) { a[k] = a[k] " | " v } else { a[k] = v; ka[++na] = k }
      } else {
        if (k in b) { b[k] = b[k] " | " v } else { b[k] = v; kb[++nb] = k }
      }
    }
    END {
      for (i = 1; i <= na; i++) {
        k = ka[i]
        if (!(k in b)) {
          printf "    %s: only in %s [%s]\n", k, la, a[k]
          d++
        } else if (a[k] != b[k]) {
          printf "    %s: %s [%s] vs %s [%s]\n", k, la, a[k], lb, b[k]
          d++
        }
      }
      for (i = 1; i <= nb; i++) {
        k = kb[i]
        if (!(k in a)) {
          printf "    %s: only in %s [%s]\n", k, lb, b[k]
          d++
        }
      }
      if (d > 0) { exit 1 }
    }
  ' "$2" "$4"
}

# manifest_diff <label-a> <file-a> <label-b> <file-b> <subset-fn> — 0 when the two
# subsets agree. On disagreement it NAMES the differing keys, because "the
# differential failed" is not a finding a reader can act on.
manifest_diff() {
  _md_a_label="$1"; _md_a="$2"; _md_b_label="$3"; _md_b="$4"; _md_fn="$5"
  _md_tmp="${TMPDIR:-/tmp}/bumpstart-mdiff.$$"
  mkdir -p "$_md_tmp" || return 1
  # The subset's own status decides, before the comparison gets a look in: comparing
  # two things neither of which could be read is not a comparison, and a hash join
  # over two empty files calls it a match.
  if ! "$_md_fn" "$_md_a" > "$_md_tmp/a" || ! "$_md_fn" "$_md_b" > "$_md_tmp/b"; then
    printf '  differential %s vs %s could not be taken — one side yielded no usable subset\n' \
      "$_md_a_label" "$_md_b_label"
    rm -rf "$_md_tmp"
    return 1
  fi
  if _manifest_compare "$_md_a_label" "$_md_tmp/a" "$_md_b_label" "$_md_tmp/b" > "$_md_tmp/d"; then
    rm -rf "$_md_tmp"
    return 0
  fi
  printf '  differential %s vs %s disagrees:\n' "$_md_a_label" "$_md_b_label"
  cat "$_md_tmp/d"
  rm -rf "$_md_tmp"
  return 1
}
