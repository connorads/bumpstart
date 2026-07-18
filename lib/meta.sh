# shellcheck shell=bash
# meta.sh: read block metadata without jq/yq. A `meta` file is plain shell
# (KIND=… DESC=… SLOT=… TARGET=… INCLUDE=…); we source it inside a subshell so
# its assignments never leak into the caller. bash-3.2-clean.

# block_dir <root> <id> — echo the path to a block or preset dir, or return 1.
block_dir() {
  if [ -f "$1/blocks/$2/meta" ]; then
    printf '%s' "$1/blocks/$2"
  elif [ -f "$1/presets/$2/meta" ]; then
    printf '%s' "$1/presets/$2"
  else
    return 1
  fi
}

# meta_get <block_dir> <FIELD> — echo a single field. Fields are pre-declared
# empty so an unset field yields "" (never a set -u failure) and stray shell in
# the meta file cannot reference our internals.
meta_get() {
  (
    KIND=""; DESC=""; SLOT=""; TARGET=""; INCLUDE=""
    # shellcheck source=/dev/null
    . "$1/meta" || exit 1
    printf '%s' "${!2}"
  )
}
