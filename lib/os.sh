# shellcheck shell=bash
# os.sh: current-OS detection. The {mac,win,linux} token set (and its MAC|WIN|
# LINUX cell-suffix uppercasing) is the CONTRACT mirrored by lib/os.ps1 in
# slice 2, so a block's per-OS command cell is keyed the same on both spines.
# Sourced, not executed. bash-3.2-clean (case, not ${v^^}).

# vibe_os — echo mac|win|linux, derived from uname -s. Unknown systems fall back
# to linux (the safest POSIX-ish default) rather than erroring.
vibe_os() {
  case "$(uname -s)" in
    Darwin)                          printf 'mac' ;;
    CYGWIN*|MINGW*|MSYS*|Windows_NT) printf 'win' ;;
    Linux)                           printf 'linux' ;;
    *)                               printf 'linux' ;;
  esac
}

# vibe_os_key — echo MAC|WIN|LINUX, the meta cell suffix for the current OS.
vibe_os_key() {
  case "$(vibe_os)" in
    mac)   printf 'MAC' ;;
    win)   printf 'WIN' ;;
    linux) printf 'LINUX' ;;
  esac
}
