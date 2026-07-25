# shellcheck shell=bash
# build.sh: the author-facing wizard. Assembles a valid bundle interactively
# (required harness single-select, then per-block opt-in), previews the exact
# plan the novice will see, and emits the shareable one-paste command. Read-only:
# run_wizard sets WIZARD_IDS[] + WIZARD_RUN_NOW for the caller to optionally apply.
# Depends on meta.sh, resolve.sh, plan.sh, common.sh. bash-3.2-clean.
#
# The optional-block loop iterates a pre-sorted id list with a plain `for` (ids
# never contain whitespace) rather than `while read < <(…)`, so the interactive
# `read` inside the loop reads the operator's answers on fd 0, not the list.

# emit_paste_command <id>... — print the README one-liner for these ids and copy
# it to the clipboard when pbcopy exists. Inherits the run's ref: prefixes
# "VIBE_REF=<ref> " only when the ref is not the default main (the bootstrap URL
# stays /main/, matching the documented pin pattern).
emit_paste_command() {
  _e_ref="${VIBE_REF:-main}"
  _e_prefix=""
  [ "$_e_ref" != "main" ] && _e_prefix="VIBE_REF=$_e_ref "
  _e_cmd="${_e_prefix}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/connorads/vibe-setup/main/vibe)\" _ $*"

  printf "\n  Share this one-paste command:\n\n    %s\n\n" "$_e_cmd"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$_e_cmd" | pbcopy && info "Copied to clipboard."
  fi
}

# run_wizard <root> — drive the interactive build. Populates WIZARD_IDS[] (the
# chosen ids, harness first) and WIZARD_RUN_NOW (true iff the operator asked to
# apply now). Returns 1 on no answers (EOF/headless) or an invalid choice.
run_wizard() {
  _w_root="$1"
  WIZARD_IDS=()
  WIZARD_RUN_NOW=false

  # ── Harness: required, numbered single-select (glob order; default claude) ──
  _w_h_ids=()
  for _w_dir in "$_w_root"/blocks/*/; do
    [ -f "$_w_dir/meta" ] || continue
    if [ "$(meta_get "$_w_dir" KIND)" = "harness" ]; then
      _w_h_ids+=("$(basename "$_w_dir")")
    fi
  done
  _w_n=${#_w_h_ids[@]}
  if [ "$_w_n" -eq 0 ]; then
    error "no harness blocks found under $_w_root/blocks"
    return 1
  fi

  printf "\n  Which agent should launch? %s(required)%s\n\n" "$DIM" "$RESET"
  _w_default_num=1
  _w_i=0
  while [ "$_w_i" -lt "$_w_n" ]; do
    _w_id="${_w_h_ids[$_w_i]}"
    [ "$_w_id" = "claude-cli" ] && _w_default_num=$((_w_i + 1))
    _w_dir="$(block_dir "$_w_root" "$_w_id")"
    printf "    %s%s)%s %s%s%s  %s\n" \
      "$BOLD" "$((_w_i + 1))" "$RESET" "$BOLD" "$_w_id" "$RESET" "$(meta_get "$_w_dir" DESC)"
    _w_i=$((_w_i + 1))
  done

  printf "\n  Choose %s[%s]%s: " "$YELLOW" "$_w_default_num" "$RESET"
  if ! IFS= read -r _w_choice; then
    printf "\n"
    error "No answers on stdin — the wizard needs a terminal. Run '--list' to browse blocks, then paste 'vibe _ <id>...'."
    return 1
  fi
  case "$_w_choice" in
    "")        _w_num="$_w_default_num" ;;
    *[!0-9]*)  error "Not a number: $_w_choice"; return 1 ;;
    *)         _w_num="$_w_choice" ;;
  esac
  if [ "$_w_num" -lt 1 ] || [ "$_w_num" -gt "$_w_n" ]; then
    error "Choose a number between 1 and $_w_n."
    return 1
  fi
  WIZARD_IDS+=("${_w_h_ids[$((_w_num - 1))]}")

  # ── Optional blocks: per-block y/N, grouped by kind (harness/preset skipped) ─
  _w_decorated=""
  for _w_dir in "$_w_root"/blocks/*/; do
    [ -f "$_w_dir/meta" ] || continue
    _w_kind="$(meta_get "$_w_dir" KIND)"
    case "$_w_kind" in harness|preset) continue ;; esac
    _w_decorated="$_w_decorated$(_kind_rank "$_w_kind") $(basename "$_w_dir")
"
  done

  printf "\n  Add optional blocks — %sy%s to include, Enter to skip:\n" "$BOLD" "$RESET"
  _w_last=""
  for _w_id in $(printf '%s' "$_w_decorated" | sort -k1,1n -k2,2 | cut -d' ' -f2); do
    _w_dir="$(block_dir "$_w_root" "$_w_id")"
    _w_kind="$(meta_get "$_w_dir" KIND)"
    if [ "$_w_kind" != "$_w_last" ]; then
      printf "\n  %s%s%s\n" "$BOLD" "$_w_kind" "$RESET"
      _w_last="$_w_kind"
    fi
    printf "    %s%s%s  %s %s[y/N]%s " \
      "$BOLD" "$_w_id" "$RESET" "$(meta_get "$_w_dir" DESC)" "$YELLOW" "$RESET"
    read -r _w_reply || _w_reply=""
    case "$_w_reply" in
      [Yy]*) WIZARD_IDS+=("$_w_id") ;;
    esac
  done

  # ── Validate + preview: reuse the exact plan (and guards) the novice sees ────
  if ! resolve "$_w_root" ${WIZARD_IDS[@]+"${WIZARD_IDS[@]}"}; then
    error "$PLAN_ERROR"
    return 1
  fi
  render_plan full

  emit_paste_command "${WIZARD_IDS[@]}"

  # ── Offer to apply now ───────────────────────────────────────────────────────
  printf "  Run this setup now? %s[y/N]%s " "$YELLOW" "$RESET"
  read -r _w_run || _w_run=""
  case "$_w_run" in
    [Yy]*) WIZARD_RUN_NOW=true ;;
  esac
  return 0
}
