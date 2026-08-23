# shellcheck shell=bash
# build.sh: the author-facing wizard. Assembles a valid bundle interactively —
# one question per AXIS — previews the exact plan the novice will see, and emits
# the shareable one-paste command. Read-only: run_wizard sets WIZARD_IDS[] +
# WIZARD_RUN_NOW for the caller to optionally apply. Depends on meta.sh,
# resolve.sh, plan.sh, common.sh. bash-3.2-clean.
#
# The wizard asks nothing it isn't told. Each dir under <root>/axes declares a
# question: LABEL (the wording), ORDER (when it is asked), SELECT (one = a
# required numbered pick, multi = per-row y/N) and, for a single-select, DEFAULT
# (the pre-selected id, so a member sorting alphabetically first can't silently
# move it). A block or preset joins a question by declaring AXIS. Adding a block
# — or a whole axis — is data; nothing here changes.
#
# Every answer loop iterates a pre-sorted id list with a plain `for` (ids never
# contain whitespace) rather than `while read < <(…)`, so the interactive `read`
# inside the loop reads the operator's answers on fd 0, not the list.

# emit_paste_command <id>... — print the README one-liner for these ids and copy
# it to the clipboard when pbcopy exists. Inherits the run's ref: prefixes
# "BUMP_REF=<ref> " only when the ref is not the default main (the bootstrap URL
# stays /main/, matching the documented pin pattern).
#
# The fetcher is per-OS, because the paste has to run on the machine it is handed
# to: macOS always has curl, but Ubuntu Desktop ships only wget, so the Linux form
# is the dual `curl … || wget …` the README documents.
emit_paste_command() {
  _e_ref="${BUMP_REF:-main}"
  _e_prefix=""
  [ "$_e_ref" != "main" ] && _e_prefix="BUMP_REF=$_e_ref "
  _e_url="https://raw.githubusercontent.com/connorads/bumpstart/main/bumpstart"
  if [ "$(bump_os)" = linux ]; then
    _e_get="curl -fsSL $_e_url 2>/dev/null || wget -qO- $_e_url"
  else
    _e_get="curl -fsSL $_e_url"
  fi
  _e_cmd="${_e_prefix}/bin/bash -c \"\$($_e_get)\" _ $*"

  printf "\n  Share this one-paste command:\n\n    %s\n\n" "$_e_cmd"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$_e_cmd" | pbcopy && info "Copied to clipboard."
  fi
}

# _axis_members <root> <axis> — echo the ids that declare this AXIS, presets
# first (the coarse, ready-made choice leads) then alphabetically.
_axis_members() {
  _am_dec=""
  for _am_dir in "$1"/blocks/*/ "$1"/presets/*/; do
    [ -f "$_am_dir/meta" ] || continue
    [ "$(meta_get "$_am_dir" AXIS)" = "$2" ] || continue
    if [ "$(meta_get "$_am_dir" KIND)" = preset ]; then _am_rank=0; else _am_rank=1; fi
    _am_dec="$_am_dec$_am_rank $(basename "$_am_dir")
"
  done
  printf '%s' "$_am_dec" | sort -k1,1n -k2,2 | cut -d' ' -f2
}

# _axes_in_order <root> — echo the axis ids that have at least one member, by
# their declared ORDER. An axis nothing declares is not a question worth asking.
_axes_in_order() {
  _ao_dec=""
  for _ao_dir in "$1"/axes/*/; do
    [ -f "$_ao_dir/meta" ] || continue
    _ao_id="$(basename "$_ao_dir")"
    [ -n "$(_axis_members "$1" "$_ao_id")" ] || continue
    _ao_ord="$(meta_get "$_ao_dir" ORDER)"
    [ -n "$_ao_ord" ] || _ao_ord=99
    _ao_dec="$_ao_dec$_ao_ord $_ao_id
"
  done
  printf '%s' "$_ao_dec" | sort -k1,1n -k2,2 | cut -d' ' -f2
}

# _axis_detail <root> <id> — echo " (pulls in: …)" for a block that includes
# others, else "". The same containment detail render_catalogue prints: without
# it `starter`, `web` and `github` read as three unrelated ticks.
_axis_detail() {
  _ad_inc="$(meta_get "$(block_dir "$1" "$2")" INCLUDE)"
  [ -n "$_ad_inc" ] && printf ' (pulls in: %s)' "$_ad_inc"
  return 0
}

# _ask_one <root> <label> <default> <id>... — a required numbered single-select.
# Appends the pick to WIZARD_ONE[]. Returns 1 on EOF (headless) or a bad answer.
_ask_one() {
  _q1_root="$1"; _q1_label="$2"; _q1_default="$3"; shift 3
  _q1_ids=("$@")
  _q1_n=$#

  printf "\n  %s %s(required)%s\n\n" "$_q1_label" "$DIM" "$RESET"
  _q1_num=1
  _q1_i=0
  while [ "$_q1_i" -lt "$_q1_n" ]; do
    _q1_id="${_q1_ids[$_q1_i]}"
    [ "$_q1_id" = "$_q1_default" ] && _q1_num=$((_q1_i + 1))
    _q1_dir="$(block_dir "$_q1_root" "$_q1_id")"
    printf "    %s%s)%s %s%-14s%s %s%s%s%s\n" \
      "$BOLD" "$((_q1_i + 1))" "$RESET" "$BOLD" "$_q1_id" "$RESET" \
      "$(meta_get "$_q1_dir" DESC)" "$DIM" "$(_axis_detail "$_q1_root" "$_q1_id")" "$RESET"
    _q1_i=$((_q1_i + 1))
  done

  printf "\n  Choose %s[%s]%s: " "$YELLOW" "$_q1_num" "$RESET"
  if ! IFS= read -r _q1_choice; then
    printf "\n"
    error "No answers on stdin — the wizard needs a terminal. Run '--list' to browse blocks, then paste 'bumpstart _ <id>...'."
    return 1
  fi
  case "$_q1_choice" in
    "")        : ;;
    *[!0-9]*)  error "Not a number: $_q1_choice"; return 1 ;;
    *)         _q1_num="$_q1_choice" ;;
  esac
  if [ "$_q1_num" -lt 1 ] || [ "$_q1_num" -gt "$_q1_n" ]; then
    error "Choose a number between 1 and $_q1_n."
    return 1
  fi
  WIZARD_ONE+=("${_q1_ids[$((_q1_num - 1))]}")
  return 0
}

# _ask_many <root> <label> <id>... — per-row y/N opt-in. Appends every yes to
# WIZARD_MULTI[]. EOF ends the question; a required single-select then reports it.
_ask_many() {
  _qm_root="$1"; _qm_label="$2"; shift 2
  printf "\n  %s %sy to include, Enter to skip%s\n\n" "$_qm_label" "$DIM" "$RESET"
  for _qm_id in "$@"; do
    _qm_dir="$(block_dir "$_qm_root" "$_qm_id")"
    printf "    %s%-14s%s %s%s%s%s %s[y/N]%s " \
      "$BOLD" "$_qm_id" "$RESET" "$(meta_get "$_qm_dir" DESC)" \
      "$DIM" "$(_axis_detail "$_qm_root" "$_qm_id")" "$RESET" "$YELLOW" "$RESET"
    read -r _qm_reply || break
    case "$_qm_reply" in
      [Yy]*) WIZARD_MULTI+=("$_qm_id") ;;
    esac
  done
  return 0
}

# run_wizard <root> — drive the interactive build: one question per axis, in the
# axes' declared ORDER. Populates WIZARD_IDS[] (the chosen ids) and
# WIZARD_RUN_NOW (true iff the operator asked to apply now). Returns 1 on no
# answers (EOF/headless) or an invalid choice.
run_wizard() {
  _w_root="$1"
  WIZARD_IDS=()
  WIZARD_ONE=()
  WIZARD_MULTI=()
  WIZARD_RUN_NOW=false

  _w_axes="$(_axes_in_order "$_w_root")"
  if [ -z "$_w_axes" ]; then
    error "no axis has any members — nothing to ask about under $_w_root/axes"
    return 1
  fi

  for _w_axis in $_w_axes; do
    _w_adir="$_w_root/axes/$_w_axis"
    _w_ids="$(_axis_members "$_w_root" "$_w_axis")"
    # word-splitting $_w_ids is the point — ids never contain whitespace
    if [ "$(meta_get "$_w_adir" SELECT)" = one ]; then
      # shellcheck disable=SC2086
      _ask_one "$_w_root" "$(meta_get "$_w_adir" LABEL)" "$(meta_get "$_w_adir" DEFAULT)" $_w_ids || return 1
    else
      # shellcheck disable=SC2086
      _ask_many "$_w_root" "$(meta_get "$_w_adir" LABEL)" $_w_ids
    fi
  done

  # The required single choice leads the emitted list: it is what launches, and
  # it keeps the paste in the shape the README documents (`claude starter`), so
  # swapping agent is swapping the first word. The opt-ins follow in axis order.
  WIZARD_IDS=(${WIZARD_ONE[@]+"${WIZARD_ONE[@]}"} ${WIZARD_MULTI[@]+"${WIZARD_MULTI[@]}"})

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
