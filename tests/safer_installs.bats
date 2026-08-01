#!/usr/bin/env bats
#
# The safer-installs tail: it turns on each package manager's own release-age
# gate. Driven directly (like the other apply.sh tails) against an isolated HOME,
# so every write is observable and nothing touches the real config. The last test
# is static: the one wait is spelled in four different units, so it checks they
# still agree.

load helpers/common

setup() {
  setup_isolated_env
  export XDG_CONFIG_HOME="$HOME/.config"
  MISE_CFG="$XDG_CONFIG_HOME/mise/config.toml"
  NPMRC="$HOME/.npmrc"
  # XDG_CONFIG_HOME is set here, so this is where pnpm looks — on every platform.
  PNPM_CFG="$XDG_CONFIG_HOME/pnpm/config.yaml"
}

apply_block() {
  run env BUMP_LIB="$REPO_ROOT/lib" BUMP_ROOT="$REPO_ROOT" \
    BUMP_BLOCK_DIR="$REPO_ROOT/blocks/safer-installs" BUMP_BLOCK_ID=safer-installs \
    bash "$REPO_ROOT/blocks/safer-installs/apply.sh"
}

@test "writes the npm age gate and the two code-execution routes" {
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq "min-release-age=4" "$NPMRC"
  grep -Fxq "allow-git=none" "$NPMRC"
  grep -Fxq "allow-remote=none" "$NPMRC"
}

@test "creates mise's config with the tool-release wait when absent" {
  apply_block
  [ "$status" -eq 0 ]
  grep -Fq '[settings]' "$MISE_CFG"
  grep -Fq 'minimum_release_age = "4d"' "$MISE_CFG"
}

@test "a second run changes nothing (both files byte-identical)" {
  apply_block
  before_npm="$(cat "$NPMRC")"
  before_mise="$(cat "$MISE_CFG")"
  apply_block
  [ "$status" -eq 0 ]
  [ "$(cat "$NPMRC")" = "$before_npm" ]
  [ "$(cat "$MISE_CFG")" = "$before_mise" ]
  [[ "$output" == *"already"* ]]
}

@test "never rewrites a value the user already chose" {
  printf 'min-release-age=30\n' > "$NPMRC"
  mkdir -p "$(dirname "$MISE_CFG")"
  printf '[settings]\nminimum_release_age = "14d"\n' > "$MISE_CFG"
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq "min-release-age=30" "$NPMRC"
  ! grep -Fq "min-release-age=4" "$NPMRC"
  grep -Fq 'minimum_release_age = "14d"' "$MISE_CFG"
  ! grep -Fq '"4d"' "$MISE_CFG"
}

@test "inserts under an existing [settings] header, leaving other lines intact" {
  mkdir -p "$(dirname "$MISE_CFG")"
  printf '[tools]\nnode = "lts"\n\n[settings]\nexperimental = true\n' > "$MISE_CFG"
  apply_block
  [ "$status" -eq 0 ]
  grep -Fq 'minimum_release_age = "4d"' "$MISE_CFG"
  # the user's own lines survive untouched
  grep -Fxq '[tools]' "$MISE_CFG"
  grep -Fxq 'node = "lts"' "$MISE_CFG"
  grep -Fxq 'experimental = true' "$MISE_CFG"
  # exactly one [settings] section
  [ "$(grep -c -Fx '[settings]' "$MISE_CFG")" -eq 1 ]
}

@test "adds a [settings] section to a config that has none" {
  mkdir -p "$(dirname "$MISE_CFG")"
  printf '[tools]\nnode = "lts"\n' > "$MISE_CFG"
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq '[settings]' "$MISE_CFG"
  grep -Fq 'minimum_release_age = "4d"' "$MISE_CFG"
  grep -Fxq 'node = "lts"' "$MISE_CFG"
}

@test "appends to an npmrc that lacks a trailing newline without joining lines" {
  printf 'registry=https://example.test' > "$NPMRC"   # no trailing newline
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq "registry=https://example.test" "$NPMRC"
  grep -Fxq "min-release-age=4" "$NPMRC"
}

@test "leaves pnpm alone when pnpm is not installed" {
  apply_block
  [ "$status" -eq 0 ]
  [ ! -e "$PNPM_CFG" ]
}

@test "gates pnpm strictly, at the path pnpm reads when XDG_CONFIG_HOME is set" {
  # pnpm honours XDG_CONFIG_HOME on EVERY platform, macOS included, and this suite
  # sets it. Writing the mac preferences dir here would be a gate pnpm never reads.
  make_fake pnpm
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq "minimumReleaseAge: 5760" "$PNPM_CFG"
  # pnpm's default is advisory: without strict it silently falls back to the
  # next-oldest satisfying version instead of refusing.
  grep -Fxq "minimumReleaseAgeStrict: true" "$PNPM_CFG"
  [ ! -e "$HOME/Library/Preferences/pnpm/config.yaml" ]
}

@test "with XDG_CONFIG_HOME unset, macOS gets the native preferences dir" {
  unset XDG_CONFIG_HOME
  export BUMP_OS=mac
  make_fake pnpm
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq "minimumReleaseAge: 5760" "$HOME/Library/Preferences/pnpm/config.yaml"
  # ~/.config/pnpm is the non-mac default; pnpm would never read it here
  [ ! -e "$HOME/.config/pnpm/config.yaml" ]
}

@test "with XDG_CONFIG_HOME unset, Linux gets ~/.config/pnpm" {
  unset XDG_CONFIG_HOME
  export BUMP_OS=linux
  make_fake pnpm
  apply_block
  [ "$status" -eq 0 ]
  grep -Fxq "minimumReleaseAge: 5760" "$HOME/.config/pnpm/config.yaml"
  grep -Fxq "minimumReleaseAgeStrict: true" "$HOME/.config/pnpm/config.yaml"
  # the mac path is not a plausible place for a Linux pnpm to look
  [ ! -e "$HOME/Library/Preferences/pnpm/config.yaml" ]
}

@test "the one wait agrees across all four units it is spelled in" {
  # npm counts days, mise takes a duration string, pnpm counts minutes. One
  # number in three notations drifts silently; normalise each to days.
  src="$REPO_ROOT/blocks/safer-installs/apply.sh"
  # cut the trailing comment before the digits: it names the unit, in digits.
  val() { grep -E "^$1=" "$src" | head -1 | cut -d= -f2 | cut -d'#' -f1 | tr -dc '0-9'; }
  days="$(val DAYS)"
  npm="$(val NPM_AGE)"
  mise="$(val MISE_AGE)"
  pnpm_min="$(val PNPM_AGE)"
  [ -n "$days" ] && [ -n "$npm" ] && [ -n "$mise" ] && [ -n "$pnpm_min" ]
  [ "$npm" -eq "$days" ]
  [ "$mise" -eq "$days" ]
  [ "$pnpm_min" -eq $((days * 24 * 60)) ]
}
