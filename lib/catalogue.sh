# shellcheck shell=bash
# catalogue.sh: author-facing discovery. render_catalogue lists every block and
# preset grouped by kind; render_block zooms in on one. Both are pure reads via
# meta_get (meta.sh) + _kind_rank (resolve.sh) and mirror render_plan's visual
# style (2-space headings, 4-space rows, DIM detail, colours from common.sh).
# bash-3.2-clean: index loops, no associative arrays.

# render_catalogue <root> — print every block then every preset, grouped under a
# heading per kind and ordered by _kind_rank (presets last). Non-preset rows show
# their INCLUDE inline as "(pulls in: …)"; preset rows show their expansion.
render_catalogue() {
  _c_root="$1"
  # Decorate each id with "<rank> <id>" so a numeric sort groups by kind then id.
  _c_decorated=""
  for _c_dir in "$_c_root"/blocks/*/ "$_c_root"/presets/*/; do
    [ -f "$_c_dir/meta" ] || continue
    _c_id="$(basename "$_c_dir")"
    _c_kind="$(meta_get "$_c_dir" KIND)"
    _c_decorated="$_c_decorated$(_kind_rank "$_c_kind") $_c_id
"
  done

  printf "\n  Blocks you can compose — paste %svibe _ <id>...%s\n" "$BOLD" "$RESET"

  _c_last=""
  while read -r _c_rank _c_id; do
    [ -z "$_c_id" ] && continue
    _c_dir="$(block_dir "$_c_root" "$_c_id")"
    _c_kind="$(meta_get "$_c_dir" KIND)"
    _c_desc="$(meta_get "$_c_dir" DESC)"
    _c_inc="$(meta_get "$_c_dir" INCLUDE)"
    if [ "$_c_kind" != "$_c_last" ]; then
      printf "\n  %s%s%s\n" "$BOLD" "$_c_kind" "$RESET"
      _c_last="$_c_kind"
    fi
    if [ "$_c_kind" = "preset" ]; then
      printf "    %s%-12s%s %s\n" "$BOLD" "$_c_id" "$RESET" "$_c_desc"
      printf "    %sexpands to: %s%s\n" "$DIM" "$_c_inc" "$RESET"
    elif [ -n "$_c_inc" ]; then
      printf "    %s%-12s%s %s %s(pulls in: %s)%s\n" \
        "$BOLD" "$_c_id" "$RESET" "$_c_desc" "$DIM" "$_c_inc" "$RESET"
    else
      printf "    %s%-12s%s %s\n" "$BOLD" "$_c_id" "$RESET" "$_c_desc"
    fi
  done < <(printf '%s' "$_c_decorated" | sort -k1,1n -k2,2)
  printf "\n"
}

# render_block <root> <id> — print one block's detail (id, kind, desc, deps, and
# the harness instruction TARGET when set). Unknown id -> error + return 1.
render_block() {
  _b_root="$1"; _b_id="$2"
  _b_dir="$(block_dir "$_b_root" "$_b_id")" || {
    error "unknown block: $_b_id"
    return 1
  }
  _b_kind="$(meta_get "$_b_dir" KIND)"
  _b_desc="$(meta_get "$_b_dir" DESC)"
  _b_inc="$(meta_get "$_b_dir" INCLUDE)"
  _b_target="$(meta_get "$_b_dir" TARGET)"

  printf "\n  %s%s%s  %s[%s]%s\n" "$BOLD" "$_b_id" "$RESET" "$DIM" "$_b_kind" "$RESET"
  printf "    %s\n" "$_b_desc"
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
  # A content.md means this block also merges guidance into the harness file.
  if [ -f "$_b_dir/content.md" ]; then
    printf "    %sadds agent guidance%s\n" "$DIM" "$RESET"
  fi
  printf "\n"
}
