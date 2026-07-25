# shellcheck shell=bash
# plan.sh: render the resolved Plan as a plain-language preview, and the single
# confirm gate. Reads the PLAN_* globals populated by resolve.sh; depends on the
# colour helpers in common.sh. bash-3.2-clean (index loops, guarded array
# expansion — never expand a possibly-empty array under set -u).

# _kind_colour <kind>: the accent colour for a step's [kind] badge. Kept close
# to the kind ordering so the preview reads as a coloured legend.
_kind_colour() {
  case "$1" in
    harness)      printf '%s' "$MAGENTA" ;;
    auth)         printf '%s' "$YELLOW" ;;
    tool)         printf '%s' "$CYAN" ;;
    mcp)          printf '%s' "$BLUE" ;;
    skill)        printf '%s' "$GREEN" ;;
    *)            printf '%s' "$DIM" ;;
  esac
}

# render_plan [full]: print the ordered steps, the agent that will launch, and a
# short "what will happen" heads-up so the confirm promise ("one prompt that
# stays") survives contact with a cold Mac. In "full" mode (the --plan dry-run
# and the author wizard) it also prints the canonical instructions file and the
# harness paths linked to it — author/debug detail that is noise to a beginner at
# the confirm gate, so the plain confirm view omits it.
render_plan() {
  _p_mode="${1:-}"
  _p_n=${#PLAN_STEP_IDS[@]}
  _p_i=0
  printf "\n  This will set up:\n"
  hrule
  printf "\n"
  while [ "$_p_i" -lt "$_p_n" ]; do
    _p_kind="${PLAN_STEP_KINDS[$_p_i]}"
    # Pad the PLAIN badge text (longest is "[instructions]" = 14) and wrap the
    # colour in separate %s args, so ANSI bytes never enter the width count.
    printf "    %s%-14s%s %s\n" \
      "$(_kind_colour "$_p_kind")" "[$_p_kind]" "$RESET" "${PLAN_STEP_DESCS[$_p_i]}"
    _p_i=$((_p_i + 1))
  done
  printf "\n  Agent to launch: %s%s%s\n" "$BOLD" "$PLAN_DEFAULT_HARNESS" "$RESET"
  if [ "$_p_mode" = full ] && [ ${#PLAN_TARGETS[@]} -gt 0 ]; then
    printf "  Instructions file: %s\n" "$(canonical_path)"
    printf "  linked from:\n"
    for _p_t in "${PLAN_TARGETS[@]}"; do
      printf "    %s\n" "$_p_t"
    done
  fi
  # Exact paths of the material persistent files — author/debug detail earned in
  # full mode (--plan and the wizard), never shown at the novice confirm gate.
  # Not PLAN_TARGETS-guarded: a codex-alone plan still writes ~/.codex/config.toml.
  if [ "$_p_mode" = full ]; then
    printf "\n  %sFiles this will create or change%s\n" "$BOLD" "$RESET"
    case "$PLAN_DEFAULT_HARNESS" in
      claude|claude-cli) printf "    %s  (marks first-project trusted, and skips Claude's first-run onboarding screen)\n" "$HOME/.claude.json" ;;
      codex|codex-cli)   printf "    %s  (marks first-project trusted)\n" "$HOME/.codex/config.toml" ;;
    esac
    case " ${PLAN_STEP_IDS[*]} " in
      *" git "*) printf "    %s  (your name, email, and default branch)\n" "$HOME/.gitconfig" ;;
    esac
    case " ${PLAN_STEP_IDS[*]} " in
      *" node "*|*" pnpm "*) printf "    %s  (mise tool versions)\n" "$HOME/.config/mise/config.toml" ;;
    esac
  fi
  _render_expectations
  printf "\n"
}

# _render_expectations: set honest expectations once, from the resolved plan plus
# a couple of cheap probes. No pricing claims (tiers change); no duplicate of the
# just-in-time password narration (that fires at the prompt itself).
_render_expectations() {
  # Account label first — harness-accurate wording, no pricing. Assigned before
  # any use because the trust bullet below reuses it. The -cli ids compose with
  # the harness split (a bundle resolves its default-harness to <name>-cli).
  case "$PLAN_DEFAULT_HARNESS" in
    claude|claude-cli) _p_acct="Claude" ;;
    codex|codex-cli)   _p_acct="Codex" ;;
    *)                 _p_acct="$PLAN_DEFAULT_HARNESS" ;;
  esac

  printf "\n  %sWhat will happen%s\n" "$BOLD" "$RESET"
  # Homebrew's install prompts for the Mac password once; a cold Mac without the
  # Command Line Tools also fetches them, which can be slow.
  if ! command -v brew >/dev/null 2>&1; then
    _exp "Installs Homebrew (a trusted tool installer) so the tools above can be added - macOS asks for your Mac password once."
    if ! xcode-select -p >/dev/null 2>&1; then
      _exp "A one-time download may take ~10-15 min."
    fi
  fi
  # Central persistent effects the applier performs (not per-block), disclosed in
  # plain language. Present-intent verbs stay honest on idempotent re-runs where
  # the effect is skipped.
  if [ ${#PLAN_TARGETS[@]} -gt 0 ]; then
    _exp "Keeps your agent guidance in one instructions file that your agent reads every session."
  fi
  _exp "Marks your first-project folder as trusted, so $_p_acct won't keep asking permission to work there."
  case " ${PLAN_STEP_IDS[*]} " in
    *" git "*)
      _exp "Sets your git name and email (from your GitHub account) and makes 'main' the default branch for new projects." ;;
  esac
  case " ${PLAN_STEP_IDS[*]} " in
    *" node "*|*" pnpm "*)
      _exp "Sets up mise to manage your tool versions, saving a small config in your home folder." ;;
  esac
  # GitHub sign-in needs an account a from-zero person may not have yet.
  case " ${PLAN_STEP_IDS[*]} " in
    *" gh-auth "*)
      _exp "You'll also sign into GitHub - create a free account first if you don't have one." ;;
  esac
  _exp "At the end you'll sign into your $_p_acct account in the browser - create one first if you don't have it."
  if [ "${FORCE:-false}" = true ]; then
    _exp "Because you passed --force, an existing instructions or agent-config file will be backed up (.bak) and replaced."
  fi
  # Where it works + the safety habit.
  _exp "The agent works in ${STARTER_DIR:-$HOME/git/first-project} and asks before changing files or running commands."
}

# _exp <text>: one expectation bullet, restyled to the dim › glyph.
_exp() { printf "    %s›%s %s\n" "$DIM" "$RESET" "$1"; }

# confirm_plan: the one interactive gate. 0 = proceed, 1 = abort. Non-tty (no
# keyboard) aborts rather than guessing — callers pass --yes for headless runs.
confirm_plan() {
  if [ ! -t 0 ]; then
    error "No terminal to confirm. Re-run with --yes to proceed non-interactively."
    return 1
  fi
  printf "\n  %sPress Enter to set up%s %s·%s %sCtrl-C to cancel%s " \
    "$BOLD" "$RESET" "$DIM" "$RESET" "$DIM" "$RESET"
  read -r _p_reply
  case "$_p_reply" in
    ""|[Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}
