# shellcheck shell=bash
# catalogue.sh: author-facing discovery. render_catalogue lists every block and
# preset grouped by AXIS — the same grouping, in the same order, that --build
# asks its questions in, so the catalogue and the wizard speak one vocabulary.
# render_block zooms in on one. Both are pure reads via meta_get (meta.sh) and
# mirror render_plan's visual style (2-space headings, 4-space rows, DIM detail,
# colours from common.sh). bash-3.2-clean: index loops, no associative arrays.

# render_catalogue <root> — every block and preset under a heading per axis, in
# the axes' declared ORDER, presets first inside each (the coarse choice leads).
# KIND drops to a DIM tag: it is how the applier orders work, not a question a
# human answers. Blocks with no AXIS are never offered on their own, so they get
# a final group that says exactly that. Non-preset rows show their INCLUDE inline
# as "(pulls in: …)"; preset rows show their expansion.
render_catalogue() {
  _c_root="$1"
  printf "\n  Blocks you can compose — paste %sbumpstart _ <id>...%s\n" "$BOLD" "$RESET"

  # Decorate each id with "<axis-order> <axis> <preset-rank> <id>" so one sort
  # groups by axis, orders the axes by ORDER, and leads each group with presets.
  _c_decorated=""
  for _c_dir in "$_c_root"/blocks/*/ "$_c_root"/presets/*/; do
    [ -f "$_c_dir/meta" ] || continue
    _c_id="$(basename "$_c_dir")"
    _c_axis="$(meta_get "$_c_dir" AXIS)"
    if [ -n "$_c_axis" ] && [ -f "$_c_root/axes/$_c_axis/meta" ]; then
      _c_ord="$(meta_get "$_c_root/axes/$_c_axis" ORDER)"
      [ -n "$_c_ord" ] || _c_ord=99
    else
      _c_axis="-"
      _c_ord=999
    fi
    if [ "$(meta_get "$_c_dir" KIND)" = preset ]; then _c_rank=0; else _c_rank=1; fi
    _c_decorated="$_c_decorated$_c_ord $_c_axis $_c_rank $_c_id
"
  done

  _c_last=""
  while read -r _c_ord _c_axis _c_rank _c_id; do
    [ -z "$_c_id" ] && continue
    _c_dir="$(block_dir "$_c_root" "$_c_id")"
    _c_kind="$(meta_get "$_c_dir" KIND)"
    _c_desc="$(meta_get "$_c_dir" DESC)"
    _c_inc="$(meta_get "$_c_dir" INCLUDE)"
    if [ "$_c_axis" != "$_c_last" ]; then
      if [ "$_c_axis" = "-" ]; then
        printf "\n  %sdependencies%s %s— pulled in by the blocks above, never asked about%s\n" \
          "$BOLD" "$RESET" "$DIM" "$RESET"
      else
        printf "\n  %s%s%s %s— %s%s\n" \
          "$BOLD" "$_c_axis" "$RESET" "$DIM" "$(meta_get "$_c_root/axes/$_c_axis" LABEL)" "$RESET"
      fi
      _c_last="$_c_axis"
    fi
    if [ "$_c_kind" = "preset" ]; then
      printf "    %s%-14s%s %s[%s]%s %s\n" \
        "$BOLD" "$_c_id" "$RESET" "$DIM" "$_c_kind" "$RESET" "$_c_desc"
      printf "    %sexpands to: %s%s\n" "$DIM" "$_c_inc" "$RESET"
    elif [ -n "$_c_inc" ]; then
      printf "    %s%-14s%s %s[%s]%s %s %s(pulls in: %s)%s\n" \
        "$BOLD" "$_c_id" "$RESET" "$DIM" "$_c_kind" "$RESET" "$_c_desc" "$DIM" "$_c_inc" "$RESET"
    else
      printf "    %s%-14s%s %s[%s]%s %s\n" \
        "$BOLD" "$_c_id" "$RESET" "$DIM" "$_c_kind" "$RESET" "$_c_desc"
    fi
  done < <(printf '%s' "$_c_decorated" | sort -k1,1n -k2,2 -k3,3n -k4,4)
  printf "\n"
}

# render_block <root> <id> — print one block's detail (id, kind, axis, desc,
# deps, and the harness instruction TARGET when set). Unknown id -> error + 1.
render_block() {
  _b_root="$1"; _b_id="$2"
  _b_dir="$(block_dir "$_b_root" "$_b_id")" || {
    error "unknown block: $_b_id"
    return 1
  }
  _b_kind="$(meta_get "$_b_dir" KIND)"
  _b_axis="$(meta_get "$_b_dir" AXIS)"
  _b_desc="$(meta_get "$_b_dir" DESC)"
  _b_inc="$(meta_get "$_b_dir" INCLUDE)"
  _b_target="$(meta_get "$_b_dir" "TARGET_$(bump_os_key)")"
  [ -n "$_b_target" ] || _b_target="$(meta_get "$_b_dir" TARGET)"

  printf "\n  %s%s%s  %s[%s]%s\n" "$BOLD" "$_b_id" "$RESET" "$DIM" "$_b_kind" "$RESET"
  printf "    %s\n" "$_b_desc"
  # Which question this block answers in --build (and under which --list heading).
  if [ -n "$_b_axis" ]; then
    printf "    %saxis:%s %s\n" "$DIM" "$RESET" "$_b_axis"
  else
    printf "    %sno axis — pulled in as a dependency, never offered on its own%s\n" "$DIM" "$RESET"
  fi
  if [ -n "$_b_inc" ]; then
    if [ "$_b_kind" = "preset" ]; then
      printf "    %sexpands to:%s %s\n" "$DIM" "$RESET" "$_b_inc"
    else
      printf "    %spulls in:%s %s\n" "$DIM" "$RESET" "$_b_inc"
    fi
  fi
  if [ -n "$_b_target" ]; then
    printf "    %sinstructions written to:%s %s\n" "$DIM" "$RESET" "$_b_target"
  fi
  # Content means this block also stacks guidance into the canonical file.
  if block_has_content "$_b_dir"; then
    printf "    %sadds agent guidance%s\n" "$DIM" "$RESET"
  fi
  printf "\n"
}
