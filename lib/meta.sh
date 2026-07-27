# shellcheck shell=bash
# meta.sh: read block metadata without jq/yq. A `meta` file is plain shell
# (KIND=… DESC=… AGENT=… TARGET=… INCLUDE=…); we source it inside a subshell so
# its assignments never leak into the caller. bash-3.2-clean.
#
# The same reader serves axes/<id>/meta (LABEL/ORDER/SELECT/DEFAULT), which is
# why the axis manifest costs no parsing code: an axis dir is just another dir
# with a `meta` in it.

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
# the meta file cannot reference our internals. This pre-declaration is the set -u
# linchpin: every field the resolver, runner, or plan may read — including the
# per-OS command cells (CHECK/INSTALL/SATISFIED × MAC/WIN/LINUX) and the per-OS
# targets — must be listed here or a block that omits it would fail. TARGET_MAC is
# declared but never set by a block: mac's target is the plain TARGET, and a
# TARGET_<OS>-then-TARGET read is what makes one code path serve all three OSes.
# LINUX/WIN cells are reserved now, authored in slice 3+; MAC is live. AXIS is
# the human taxonomy (which question a block answers, if any); ORDER/SELECT/
# DEFAULT belong to the axes themselves, read through this same function.
meta_get() {
  (
    KIND=""; DESC=""; AGENT=""; ACCOUNT=""; TARGET=""; INCLUDE=""; LABEL=""
    AXIS=""; ORDER=""; SELECT=""; DEFAULT=""
    TARGET_MAC=""; TARGET_WIN=""; TARGET_LINUX=""
    LINK_MAC=""; LINK_WIN=""; LINK_LINUX=""
    CHECK_MAC=""; INSTALL_MAC=""; SATISFIED_MAC=""
    CHECK_WIN=""; INSTALL_WIN=""; SATISFIED_WIN=""
    CHECK_LINUX=""; INSTALL_LINUX=""; SATISFIED_LINUX=""
    # shellcheck source=/dev/null
    . "$1/meta" || exit 1
    printf '%s' "${!2}"
  )
}
