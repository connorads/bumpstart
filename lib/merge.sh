# shellcheck shell=bash
# merge.sh: idempotently merge a managed instructions block into a harness file
# (e.g. ~/.claude/CLAUDE.md), between per-id HTML-comment markers. The user owns
# everything outside the markers; we only ever touch our own region.
#
# Invariants (see tests/merge.bats):
#   - apply-twice == apply-once (byte-idempotent)
#   - text outside our markers is never changed
#   - a half-present marker pair (corruption) is refused, file untouched
#
# Depends on common.sh (success/warn). bash-3.2-clean.

# seed_scaffold <target> — write a friendly starter file for a novice to edit.
seed_scaffold() {
  cat > "$1" <<'EOF'
# Your coding-agent instructions

This file guides your AI coding agent. Edit it freely — in plain language, say
what you want the agent to do or avoid. A couple of examples to start:

- Explain your reasoning before making a big change.
- Ask before installing new tools or dependencies.

The block below is managed by vibe-setup — leave its markers in place so it can
be updated later.
EOF
}

# merge_managed_block <id> <content> <target>
merge_managed_block() {
  _m_id="$1"; _m_content="$2"; _m_target="$3"
  _m_start="<!-- vibe:$_m_id start -->"
  _m_end="<!-- vibe:$_m_id end -->"

  # Managed content always ends with exactly one trailing newline.
  case "$_m_content" in
    *$'\n') ;;
    *) _m_content="$_m_content"$'\n' ;;
  esac

  mkdir -p "$(dirname "$_m_target")"

  # Build the new managed block (marker + content + marker) in a temp file so
  # awk can splice it in without any multi-line-variable quoting hazards.
  _m_blk="$(mktemp "${TMPDIR:-/tmp}/vibeblk.XXXXXX")"
  { printf '%s\n' "$_m_start"; printf '%s' "$_m_content"; printf '%s\n' "$_m_end"; } > "$_m_blk"

  # Absent file → seed a scaffold, then append the block after a blank line.
  if [ ! -f "$_m_target" ]; then
    seed_scaffold "$_m_target"
    { printf '\n'; cat "$_m_blk"; } >> "$_m_target"
    rm -f "$_m_blk"
    success "Wrote $_m_id guidance to $_m_target"
    return 0
  fi

  # grep -F: markers may contain regex metacharacters from the id.
  _m_have_start=false; _m_have_end=false
  grep -Fq -- "$_m_start" "$_m_target" && _m_have_start=true
  grep -Fq -- "$_m_end"   "$_m_target" && _m_have_end=true

  # Exactly one marker present = corruption (or a hand-edit gone wrong). Refuse
  # rather than risk clobbering the user's text.
  if [ "$_m_have_start" != "$_m_have_end" ]; then
    warn "Managed markers for '$_m_id' look corrupt in $_m_target — leaving it untouched."
    rm -f "$_m_blk"
    return 1
  fi

  _m_out="$(mktemp "${TMPDIR:-/tmp}/vibemrg.XXXXXX")"
  if [ "$_m_have_start" = true ]; then
    # Replace the existing region (marker line through marker line, inclusive).
    awk -v start="$_m_start" -v end="$_m_end" -v blockfile="$_m_blk" '
      function emit_block(   line) {
        while ((getline line < blockfile) > 0) print line
        close(blockfile)
      }
      $0 == start { emit_block(); skip = 1; next }
      skip && $0 == end { skip = 0; next }
      skip { next }
      { print }
    ' "$_m_target" > "$_m_out"
  else
    # No markers yet → append after a blank-line separator.
    { cat "$_m_target"; printf '\n'; cat "$_m_blk"; } > "$_m_out"
  fi

  mv "$_m_out" "$_m_target"
  rm -f "$_m_blk"
  success "Updated $_m_id guidance in $_m_target"
  return 0
}
