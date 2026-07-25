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
  _render_expectations
  printf "\n"
}

# _render_expectations: set honest expectations once, from the resolved plan plus
# a couple of cheap probes. No pricing claims (tiers change); no duplicate of the
# just-in-time password narration (that fires at the prompt itself).
_render_expectations() {
  printf "\n  %sWhat will happen%s\n" "$BOLD" "$RESET"
  # Homebrew's install prompts for the Mac password once; a cold Mac without the
  # Command Line Tools also fetches them, which can be slow.
  if ! command -v brew >/dev/null 2>&1; then
    _exp "macOS will ask for your Mac password once."
    if ! xcode-select -p >/dev/null 2>&1; then
      _exp "A one-time download may take ~10-15 min."
    fi
  fi
  # GitHub sign-in needs an account a from-zero person may not have yet.
  case " ${PLAN_STEP_IDS[*]} " in
    *" gh-auth "*)
      _exp "You'll also sign into GitHub - create a free account first if you don't have one." ;;
  esac
  # Account sign-in — harness-accurate wording, no pricing.
  case "$PLAN_DEFAULT_HARNESS" in
    claude) _p_acct="Claude" ;;
    codex)  _p_acct="Codex" ;;
    *)      _p_acct="$PLAN_DEFAULT_HARNESS" ;;
  esac
  _exp "At the end you'll sign into your $_p_acct account in the browser - create one first if you don't have it."
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
