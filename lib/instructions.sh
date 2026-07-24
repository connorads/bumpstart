# shellcheck shell=bash
# instructions.sh: assemble the canonical agent-instructions file and symlink
# each installed harness's native path to it. Replaces the per-block marker
# merge: one canonical file, owned by the user, that every agent follows via a
# symlink (Anthropic's documented `ln -s AGENTS.md CLAUDE.md` pattern), which
# also collapses the both-agents duplication to a single source.
#
# The canonical file holds only the stacked block sections — no markers, no
# preamble — because it is the agent's context every session, so it stays
# token-lean. Novice orientation lives in the end-of-run terminal message.
#
# Back-off is the rule: we never rewrite a canonical the user may have edited,
# nor clobber a real native file. --force overrides both (rewrite the canonical;
# back a real native file up to .bak, then symlink). Depends on common.sh
# (success/info/warn) and meta.sh (block_dir). bash-3.2-clean.
#
# Outputs consumed by the finish message (apply.sh):
#   INSTRUCTIONS_WROTE       true when the canonical file was (re)written
#   INSTRUCTIONS_BACKED_OFF  true when a canonical existed and we left it as-is
#   LINK_BACKOFFS            newline-separated native paths we refused to link

# canonical_path — the single editable source of truth for agent instructions.
# Honours $XDG_CONFIG_HOME, default ~/.config/agents/AGENTS.md.
canonical_path() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agents/AGENTS.md"
}

# assemble_instructions <root> <force> — concatenate each in-plan block's
# content.md (in PLAN_STEP_IDS order, one blank line between sections) and write
# the canonical file. No content anywhere → no-op. Canonical present without
# force → back off (leave it). Sets INSTRUCTIONS_WROTE / INSTRUCTIONS_BACKED_OFF.
assemble_instructions() {
  _ai_root="$1"; _ai_force="$2"
  INSTRUCTIONS_WROTE=false
  INSTRUCTIONS_BACKED_OFF=false

  # Stack every in-plan block's content.md, newest section last. $(cat) strips a
  # section's own trailing newlines, so joining with a blank line is exact.
  _ai_buf=""
  _ai_n=${#PLAN_STEP_IDS[@]}
  _ai_i=0
  while [ "$_ai_i" -lt "$_ai_n" ]; do
    _ai_dir="$(block_dir "$_ai_root" "${PLAN_STEP_IDS[$_ai_i]}")"
    if [ -f "$_ai_dir/content.md" ]; then
      _ai_c="$(cat "$_ai_dir/content.md")"
      if [ -n "$_ai_buf" ]; then
        _ai_buf="$_ai_buf"$'\n'$'\n'"$_ai_c"
      else
        _ai_buf="$_ai_c"
      fi
    fi
    _ai_i=$((_ai_i + 1))
  done

  # Nothing to write → leave the filesystem untouched and the preview honest.
  [ -n "$_ai_buf" ] || return 0

  _ai_canon="$(canonical_path)"
  if [ -e "$_ai_canon" ] && [ "$_ai_force" != true ]; then
    # Never auto-rewrite a file the user owns and may have edited.
    INSTRUCTIONS_BACKED_OFF=true
    return 0
  fi

  mkdir -p "$(dirname "$_ai_canon")"
  printf '%s\n' "$_ai_buf" > "$_ai_canon"
  INSTRUCTIONS_WROTE=true
  return 0
}

# link_harness <native_path> <force> — point a harness's native instructions
# path at the canonical file. Idempotent: an existing symlink to the canonical
# is left alone (this is what makes re-runs a no-op without any markers). Absent
# → create the symlink. A real file / foreign symlink is backed off (recorded in
# LINK_BACKOFFS) unless force, which moves it to <native>.bak (timestamp-suffixed
# if .bak is taken) then relinks.
link_harness() {
  _lh_native="$1"; _lh_force="$2"
  _lh_canon="$(canonical_path)"
  mkdir -p "$(dirname "$_lh_native")"

  # Already the symlink we would create → nothing to do.
  if [ -L "$_lh_native" ] && [ "$(readlink "$_lh_native")" = "$_lh_canon" ]; then
    return 0
  fi

  # Nothing there (not even a broken symlink) → link it.
  if [ ! -e "$_lh_native" ] && [ ! -L "$_lh_native" ]; then
    ln -s "$_lh_canon" "$_lh_native"
    success "Linked $_lh_native to your instructions file"
    return 0
  fi

  # A real file or a foreign symlink is in the way.
  if [ "$_lh_force" != true ]; then
    LINK_BACKOFFS="${LINK_BACKOFFS:-}${_lh_native}
"
    return 0
  fi

  _lh_bak="$_lh_native.bak"
  if [ -e "$_lh_bak" ] || [ -L "$_lh_bak" ]; then
    _lh_bak="$_lh_native.bak.$(date +%Y%m%d%H%M%S)"
  fi
  mv "$_lh_native" "$_lh_bak"
  ln -sfn "$_lh_canon" "$_lh_native"
  success "Backed up $_lh_native to $_lh_bak and linked to your instructions file"
  return 0
}
