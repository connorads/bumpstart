#!/usr/bin/env bats
#
# git block: install git (once) and configure a GitHub-flavoured identity,
# backing off from any config the user already has. Fakes gh (the identity
# source) and git (config reads/writes) so we assert the exact commands run,
# hermetically. bash-3.2-clean.

load helpers/common

setup() { setup_isolated_env; }

run_block() {
  id="$1"; shift
  run env BUMP_LIB="$REPO_ROOT/lib" BUMP_ROOT="$REPO_ROOT" \
    BUMP_BLOCK_DIR="$REPO_ROOT/blocks/$id" BUMP_BLOCK_ID="$id" \
    bash "$REPO_ROOT/blocks/$id/apply.sh" "$@"
}

# Fake bodies are literal strings; run-time $-expansions inside them are
# deferred, so single quotes are correct there.
# shellcheck disable=SC2016

# fake gh: authenticated, and `api user --jq <field>` returns the octocat
# profile. The profile name is baked in at build time ("" for the blank case).
make_fake_gh_octocat() {
  _name="${1-The Octocat}"
  make_fake gh \
    'if [ "$1 ${2:-}" = "auth status" ]; then exit 0; fi' \
    'if [ "$1 ${2:-}" = "api user" ]; then' \
    '  case "$4" in' \
    '    .login) printf "octocat\n" ;;' \
    '    .id)    printf "583231\n" ;;' \
    "    *)      printf '%s\n' '$_name' ;;" \
    '  esac' \
    '  exit 0' \
    'fi'
}

# fake git: logs every call; `config --global --get <key>` reports the key
# UNSET (exit 1) so the block's set-when-unset branch fires and the writes show.
make_fake_git_unset() {
  make_fake git 'if [ "$1 $2 $3" = "config --global --get" ]; then exit 1; fi'
}

# fake git that reports identity already SET: `--get` prints a value and exits 0
# so the block backs off and writes nothing.
make_fake_git_set() {
  make_fake git \
    'if [ "$1 $2 $3" = "config --global --get" ]; then' \
    '  case "$4" in' \
    '    user.name)  printf "Existing Name\n" ;;' \
    '    user.email) printf "me@example.com\n" ;;' \
    '    *)          printf "main\n" ;;' \
    '  esac' \
    '  exit 0' \
    'fi'
}

@test "git block configures name + noreply email from the GitHub profile" {
  make_fake_gh_octocat
  make_fake_git_unset
  run_block git
  [ "$status" -eq 0 ]
  fake_logged "git config --global user.name The Octocat"
  fake_logged "git config --global user.email 583231+octocat@users.noreply.github.com"
}

@test "a blank GitHub name without a terminal falls back to the login" {
  make_fake_gh_octocat ""
  make_fake_git_unset
  run_block git
  [ "$status" -eq 0 ]
  fake_logged "git config --global user.name octocat"
}

@test "an identity already set is left untouched" {
  make_fake_gh_octocat
  make_fake_git_set
  run_block git
  [ "$status" -eq 0 ]
  refute_fake_logged "git config --global user.name The Octocat"
  refute_fake_logged "git config --global user.email 583231+octocat"
  [[ "$output" == *"already knows you"* ]]
}

@test "no GitHub sign-in skips identity, non-fatal" {
  make_fake gh 'if [ "$1 ${2:-}" = "auth status" ]; then exit 1; fi'
  make_fake git
  run_block git
  [ "$status" -eq 0 ]
  refute_fake_logged "git config --global user.name"
  refute_fake_logged "git config --global user.email"
  [[ "$output" == *"Not signed into GitHub"* ]]
}
