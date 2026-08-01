#!/usr/bin/env bats
#
# bump_fetch (common.sh) — one fetch helper over whichever downloader the machine
# has. Ubuntu Desktop 24.04/26.04 ship wget but NOT curl, so a curl-only install
# cell is a silent no-op there; these cases pin the fallback, the failure message,
# and the `export -f` that lets an INSTALL cell call it through `bash -c`.
#
# PATH is narrowed to $FAKES ALONE (not the isolated PATH the other suites use),
# because the real /usr/bin/curl would otherwise make "curl absent" untestable.
# bump_fetch needs no external command beyond the fetcher itself, so an empty PATH
# is enough; bash is invoked by absolute path since PATH can't find it.

load helpers/common

setup() { setup_isolated_env; }

# fetch <url> — run bump_fetch with ONLY the fakes dir on PATH.
fetch() {
  run env PATH="$FAKES" /bin/bash -c \
    '. "'"$REPO_ROOT"'/lib/common.sh"; bump_fetch "$1"' _ "$1"
}

@test "bump_fetch uses curl when curl is present" {
  make_fake curl
  make_fake wget
  fetch https://example.test/x
  [ "$status" -eq 0 ]
  fake_logged "curl -fsSL https://example.test/x"
  refute_fake_logged "wget"
}

@test "bump_fetch falls back to wget when curl is absent" {
  make_fake wget
  fetch https://example.test/x
  [ "$status" -eq 0 ]
  fake_logged "wget -qO- https://example.test/x"
}

@test "bump_fetch passes the fetched body through on stdout" {
  make_fake wget 'printf "BODY\n"'
  fetch https://example.test/x
  [ "$status" -eq 0 ]
  [[ "$output" == *BODY* ]]
}

@test "with neither curl nor wget it fails loudly rather than piping nothing" {
  fetch https://example.test/x
  [ "$status" -ne 0 ]
  [[ "$output" == *"curl or wget"* ]]
}

@test "an install cell can call bump_fetch: export -f reaches a bash -c child" {
  # This is the contract the Linux INSTALL cells rely on — a cell is run by
  # run_cell as `bash -c "<cell>"`, a child process, so the function must be
  # exported, not merely defined.
  make_fake wget 'printf "BODY\n"'
  # run_cell finds `bash` on PATH; this suite's PATH is only $FAKES, so put it there.
  ln -s /bin/bash "$FAKES/bash"
  run env PATH="$FAKES" /bin/bash -c \
    '. "'"$REPO_ROOT"'/lib/common.sh"; export -f bump_fetch; bash -c "bump_fetch https://example.test/x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *BODY* ]]
}

@test "the bumpstart bootstrap and install.sh carry the same fallback inline" {
  # Both run before lib/common.sh exists, so they cannot use bump_fetch. The
  # duplication is deliberate; this keeps it from silently becoming curl-only.
  for f in "$REPO_ROOT/bumpstart" "$REPO_ROOT/install.sh"; do
    grep -Fq 'wget -qO-' "$f"
    grep -Fq 'curl -fsSL' "$f"
  done
}
