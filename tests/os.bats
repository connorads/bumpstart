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

@test "bump_os maps Darwin to mac" {
  make_fake uname 'printf "Darwin\n"'
  os bump_os
  [ "$status" -eq 0 ]
  [ "$output" = mac ]
}

@test "bump_os maps Linux to linux" {
  make_fake uname 'printf "Linux\n"'
  os bump_os
  [ "$output" = linux ]
}

@test "bump_os maps a Windows-ish uname to win" {
  make_fake uname 'printf "MINGW64_NT-10.0\n"'
  os bump_os
  [ "$output" = win ]
}

@test "an unknown uname falls back to linux" {
  make_fake uname 'printf "Plan9\n"'
  os bump_os
  [ "$output" = linux ]
}

@test "bump_os_key is the uppercase OS token" {
  make_fake uname 'printf "Darwin\n"'
  os bump_os_key
  [ "$output" = MAC ]
}

@test "bump_wsl reads a WSL 2 kernel release as 2" {
  # The real string from a current WSL 2 kernel.
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '5.15.153.1-microsoft-standard-WSL2\n' > "$BUMP_OSRELEASE_FILE"
  os bump_wsl
  [ "$output" = 2 ]
}

@test "bump_wsl reads an older WSL 2 kernel (no WSL2 suffix) as 2" {
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '5.10.102.1-microsoft-standard\n' > "$BUMP_OSRELEASE_FILE"
  os bump_wsl
  [ "$output" = 2 ]
}

@test "bump_wsl reads a WSL 1 kernel release as 1" {
  # WSL 1 reports the Windows build with a capital-M "-Microsoft" suffix. Matching
  # the WSL 2 patterns first is what keeps a WSL 2 machine from reading as WSL 1.
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '4.4.0-19041-Microsoft\n' > "$BUMP_OSRELEASE_FILE"
  os bump_wsl
  [ "$output" = 1 ]
}

@test "bump_wsl is empty on a plain Linux kernel" {
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/osrelease"
  printf '6.8.0-51-generic\n' > "$BUMP_OSRELEASE_FILE"
  os bump_wsl
  [ -z "$output" ]
}

@test "bump_wsl is empty (not an error) when the release file is absent" {
  # macOS has no /proc, which is the common case for this branch.
  export BUMP_OSRELEASE_FILE="$BATS_TEST_TMPDIR/does-not-exist"
  os bump_wsl
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an explicit BUMP_OS override wins over uname (the cross-spine test seam)" {
  make_fake uname 'printf "Darwin\n"'
  export BUMP_OS=win   # exported so the helper's `bash -c` subshell inherits it
  os bump_os
  [ "$output" = win ]
  os bump_os_key
  [ "$output" = WIN ]
}
