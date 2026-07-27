#!/usr/bin/env bats
#
# meta.sh schema: the per-OS command-cell fields resolve, an unset field is "" (so
# set -u never trips on a block that omits it), and every command cell in the real
# blocks is single-quoted + backtick-free — the value convention that keeps a cell
# inert at source time (no pipe/||/$() runs during a Mac read; no pwsh backtick
# executes either). Positive reads use a synthetic block so this suite is green
# independent of which real blocks have been converted to cells.

load helpers/common

setup() {
  setup_isolated_env
  BLK="$BATS_TEST_TMPDIR/blk"
  mkdir -p "$BLK"
}

# mg <dir> <field> — read one meta field via meta_get under the isolated bash.
mg() { run bash -c '. "'"$REPO_ROOT"'/lib/meta.sh"; meta_get "$1" "$2"' _ "$@"; }

@test "meta_get reads a per-OS INSTALL cell verbatim" {
  printf "%s\n" "INSTALL_MAC='curl -fsSL https://example/install.sh | bash'" > "$BLK/meta"
  mg "$BLK" INSTALL_MAC
  [ "$status" -eq 0 ]
  [ "$output" = 'curl -fsSL https://example/install.sh | bash' ]
}

@test "meta_get reads a per-OS CHECK cell verbatim" {
  printf "%s\n" "CHECK_MAC='command -v mise >/dev/null 2>&1'" > "$BLK/meta"
  mg "$BLK" CHECK_MAC
  [ "$status" -eq 0 ]
  [ "$output" = 'command -v mise >/dev/null 2>&1' ]
}

@test "an unset per-OS cell yields the empty string (set -u safe)" {
  printf "%s\n" "KIND=tool" > "$BLK/meta"
  mg "$BLK" INSTALL_WIN
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  mg "$BLK" SATISFIED_LINUX
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a single-quoted cell is inert at source time (no pipe/subshell runs)" {
  # If the value were double-quoted, $(…) would execute during meta_get's source.
  printf "%s\n" 'INSTALL_MAC='\''echo $(touch "'"$BLK"'/RAN")'\''' > "$BLK/meta"
  mg "$BLK" INSTALL_MAC
  [ "$status" -eq 0 ]
  [ ! -e "$BLK/RAN" ]
}

@test "every command cell in the real blocks is single-quoted and backtick-free" {
  for f in "$REPO_ROOT"/blocks/*/meta; do
    while IFS= read -r line; do
      case "$line" in
        CHECK_*=*|INSTALL_*=*|SATISFIED_*=*)
          val="${line#*=}"
          case "$val" in
            "'"*) : ;;
            *) printf 'not single-quoted: %s (%s)\n' "$line" "$f" >&2; return 1 ;;
          esac
          case "$val" in
            *'`'*) printf 'backtick in: %s (%s)\n' "$line" "$f" >&2; return 1 ;;
          esac ;;
      esac
    done < "$f"
  done
}

@test "every declared AXIS names a real axis directory" {
  # AXIS is otherwise unvalidated: both spines read a missing axis dir as "no
  # axis", so a typo yields a block that silently never appears in --build and
  # lands in --list's dependencies group instead. ADR 0001 nominates this file
  # for the guard once the catalogue grows. Declaring NO axis stays legal — mise
  # is deliberately dependency-only.
  for f in "$REPO_ROOT"/blocks/*/meta "$REPO_ROOT"/presets/*/meta; do
    axis="$(bash -c '. "'"$REPO_ROOT"'/lib/meta.sh"; meta_get "$1" AXIS' _ "$(dirname "$f")")"
    [ -n "$axis" ] || continue
    if [ ! -d "$REPO_ROOT/axes/$axis" ]; then
      printf 'AXIS=%s has no axes/%s directory (%s)\n' "$axis" "$axis" "$f" >&2
      return 1
    fi
  done
}

@test "WIN/LINUX command cells use inner double-quotes only (no inner single quote)" {
  # A bash single-quoted string can't contain a single quote, so a WIN/LINUX cell
  # that needs quotes must use double quotes inside. Strip the outer single quotes
  # and fail if any single quote remains.
  for f in "$REPO_ROOT"/blocks/*/meta; do
    while IFS= read -r line; do
      case "$line" in
        CHECK_WIN=*|INSTALL_WIN=*|SATISFIED_WIN=*|CHECK_LINUX=*|INSTALL_LINUX=*|SATISFIED_LINUX=*)
          val="${line#*=}"
          inner="${val#\'}"; inner="${inner%\'}"
          case "$inner" in
            *"'"*) printf 'inner single-quote in: %s (%s)\n' "$line" "$f" >&2; return 1 ;;
          esac ;;
      esac
    done < "$f"
  done
}
