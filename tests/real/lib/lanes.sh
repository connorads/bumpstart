# shellcheck shell=bash
# lanes.sh: reading the lane matrix, which is DATA.
#
# One parser, at the boundary, because `IFS=$'\t' read` CANNOT REPRESENT an empty
# field. Tab is IFS whitespace, so a `\t\t` run collapses and every later field
# shifts left:
#
#   $ printf 'a\tb\t\td\n' | { IFS=$'\t' read -r w x y z; echo "$w $x $y $z"; }
#   a b d
#
# An empty `deps` cell therefore put the paste ids in the deps column, and
# guests/container.sh executed them as a root provisioning command — reported as
# class 2, "infrastructure", forever. Spelling every empty cell `-` is what keeps
# the file readable at all, and it was a convention asserted nowhere.
#
# So: awk splits, a field count and an emptiness check run BEFORE anything reads the
# values, and only then is the cheap tab-read safe.
#
# Sourced, not executed. bash-3.2-clean.

LANE_ADAPTER=""
LANE_IMAGE=""
LANE_AXIS=""
LANE_ENTRY=""
LANE_PASTE=""
LANE_DEPS=""
LANE_ERROR=""

# The columns, in order. A row that does not have exactly this many is a typo, and
# the most likely typo is the one that used to be invisible.
LANE_COLUMNS=7

# lane_row <lanes.tsv> <lane> — 0 with LANE_* set, or non-zero with LANE_ERROR set.
lane_row() {
  LANE_ADAPTER=""; LANE_IMAGE=""; LANE_AXIS=""
  LANE_ENTRY=""; LANE_PASTE=""; LANE_DEPS=""; LANE_ERROR=""
  _lr_tsv="$1"
  _lr_lane="$2"
  _lr_tab="$(printf '\t')"

  if [ ! -r "$_lr_tsv" ]; then
    LANE_ERROR="no lane matrix at $_lr_tsv"
    return 1
  fi

  # awk validates and emits; bash only ever reads a row already known to be whole.
  # `=` / `!` says which, so a value that happens to start with either is harmless.
  _lr_out="$(awk -F'\t' -v l="$_lr_lane" -v want="$LANE_COLUMNS" '
    NR > 1 && $1 == l {
      if (NF != want) {
        printf "!\t%d columns, not %d — an empty cell is spelled -, never left blank\n", NF, want
        exit
      }
      for (i = 1; i <= NF; i++) {
        if ($i == "") {
          printf "!\tcolumn %d is empty - spell an empty cell -, so no later column shifts into it\n", i
          exit
        }
        # Columns 1-6 are interpolated into single-quoted guest command strings, so
        # a quote of their own would close that string and run the remainder as
        # shell. The deps column is exempt because it IS shell by design: the bare
        # minimum for the image, run as a root provisioning command.
        if (i < want && index($i, "\047")) {
          printf "!\tcolumn %d contains a single quote, and only the deps column may\n", i
          exit
        }
      }
      printf "=\t%s\t%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, $6, $7
      exit
    }' "$_lr_tsv")"

  if [ -z "$_lr_out" ]; then
    LANE_ERROR="no lane '$_lr_lane' in $_lr_tsv"
    return 1
  fi
  case "$_lr_out" in
    '!'*)
      LANE_ERROR="lane '$_lr_lane': ${_lr_out#!"$_lr_tab"}"
      return 1 ;;
  esac

  # Safe now, and only now: every field is known non-empty, so nothing can collapse.
  IFS="$_lr_tab" read -r LANE_ADAPTER LANE_IMAGE LANE_AXIS LANE_ENTRY LANE_PASTE LANE_DEPS <<EOF
${_lr_out#="$_lr_tab"}
EOF
  return 0
}

# lane_names <lanes.tsv> <adapter>... — the lanes driven by any of these adapters,
# one per line. The filter is by ADAPTER rather than a hardcoded list, so a new row
# joins the local driver and CI with no code change.
lane_names() {
  _ln_tsv="$1"
  shift
  awk -F'\t' -v want=" $* " '
    NR > 1 && $1 !~ /^#/ && index(want, " " $2 " ") { print $1 }' "$_ln_tsv"
}
