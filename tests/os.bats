#!/usr/bin/env bats
#
# lib/os.sh: current-OS token detection. The {mac,win,linux} token set (uppercased
# to MAC|WIN|LINUX cell suffixes) is the contract mirrored by lib/os.ps1 in
# slice 2. uname is faked so the mapping is asserted deterministically, host OS
# regardless.

load helpers/common

setup() { setup_isolated_env; }

# os <fn> — source os.sh under the isolated PATH (fake uname first) and run fn.
os() { run bash -c '. "'"$REPO_ROOT"'/lib/os.sh"; '"$1"; }

@test "vibe_os maps Darwin to mac" {
  make_fake uname 'printf "Darwin\n"'
  os vibe_os
  [ "$status" -eq 0 ]
  [ "$output" = mac ]
}

@test "vibe_os maps Linux to linux" {
  make_fake uname 'printf "Linux\n"'
  os vibe_os
  [ "$output" = linux ]
}

@test "vibe_os maps a Windows-ish uname to win" {
  make_fake uname 'printf "MINGW64_NT-10.0\n"'
  os vibe_os
  [ "$output" = win ]
}

@test "an unknown uname falls back to linux" {
  make_fake uname 'printf "Plan9\n"'
  os vibe_os
  [ "$output" = linux ]
}

@test "vibe_os_key is the uppercase OS token" {
  make_fake uname 'printf "Darwin\n"'
  os vibe_os_key
  [ "$output" = MAC ]
}

@test "an explicit VIBE_OS override wins over uname (the cross-spine test seam)" {
  make_fake uname 'printf "Darwin\n"'
  export VIBE_OS=win   # exported so the helper's `bash -c` subshell inherits it
  os vibe_os
  [ "$output" = win ]
  os vibe_os_key
  [ "$output" = WIN ]
}
