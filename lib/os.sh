# shellcheck shell=bash
# os.sh: current-OS detection. The {mac,win,linux} token set (and its MAC|WIN|
# LINUX cell-suffix uppercasing) is the CONTRACT mirrored by lib/os.ps1 in
# slice 2, so a block's per-OS command cell is keyed the same on both spines.
# Sourced, not executed. bash-3.2-clean (case, not ${v^^}).

# vibe_os — echo mac|win|linux. An explicit $VIBE_OS override wins (the test seam,
# mirrored by os.ps1 where the mac-hosted Windows e2e depends on it); otherwise
# derived from uname -s. Unknown systems fall back to linux (the safest POSIX-ish
# default) rather than erroring.
vibe_os() {
  if [ -n "${VIBE_OS:-}" ]; then printf '%s' "$VIBE_OS"; return 0; fi
  case "$(uname -s)" in
    Darwin)                          printf 'mac' ;;
    CYGWIN*|MINGW*|MSYS*|Windows_NT) printf 'win' ;;
    Linux)                           printf 'linux' ;;
    *)                               printf 'linux' ;;
  esac
}

# vibe_wsl — echo 2, 1 or nothing: which WSL version this is, if any. Reads the
# kernel release string ($VIBE_OSRELEASE_FILE is the test seam) rather than
# $WSL_DISTRO_NAME, because the kernel name is present in every WSL release and
# survives into a container running inside WSL, where the env var may not.
#
# WSL 2 kernels are named "…-microsoft-standard-WSL2" (older builds: just
# "…-microsoft-standard"); WSL 1 reports the Windows build as "…-Microsoft". So the
# specific WSL 2 patterns are tested FIRST — the reverse order would call every
# WSL 2 machine WSL 1. Case-insensitive via tr (not ${v,,}: bash-3.2-clean), so the
# answer never hinges on a capital M.
#
# Two callers only: the WSL 1 refusal in both platform guards (WSL 1 cannot exec
# the agent binaries at all, anthropics/claude-code#38788, and only the spine can
# refuse — a CHECK cell runs per-block and far too late), and clipboard selection.
vibe_wsl() {
  _vw_file="${VIBE_OSRELEASE_FILE:-/proc/sys/kernel/osrelease}"
  [ -r "$_vw_file" ] || return 0
  _vw_rel="$(tr '[:upper:]' '[:lower:]' < "$_vw_file" 2>/dev/null)" || return 0
  case "$_vw_rel" in
    *wsl2*|*microsoft-standard*) printf '2' ;;
    *microsoft*)                 printf '1' ;;
  esac
  return 0
}

# vibe_os_key — echo MAC|WIN|LINUX, the meta cell suffix for the current OS.
vibe_os_key() {
  case "$(vibe_os)" in
    mac)   printf 'MAC' ;;
    win)   printf 'WIN' ;;
    linux) printf 'LINUX' ;;
  esac
}

# block_has_content <block_dir> — true when this block stacks a section into the
# canonical instructions file on the current OS: a per-OS content.<os>.md, else
# the neutral content.md. The one answer to "does this block carry guidance",
# shared by the resolver (are there targets to link?), the catalogue (--show) and
# the plan (is guidance being skipped?), so the three can never disagree.
#
# Lives here, not in run.sh, because it takes a block DIR and needs only vibe_os:
# the resolve drivers source meta + os + resolve alone, and a predicate in run.sh
# would break them. bash-3.2-clean.
block_has_content() {
  [ -f "$1/content.$(vibe_os).md" ] && return 0
  [ -f "$1/content.md" ] && return 0
  return 1
}
