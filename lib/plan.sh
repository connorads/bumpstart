# shellcheck shell=bash
# plan.sh: render the resolved Plan as a plain-language preview, and the single
# confirm gate. Reads the PLAN_* globals populated by resolve.sh; depends on the
# colour helpers in common.sh. bash-3.2-clean (index loops, guarded array
# expansion — never expand a possibly-empty array under set -u).

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
  printf "\n  This will set up:\n\n"
  while [ "$_p_i" -lt "$_p_n" ]; do
    printf "    %s[%s]%s %s\n" \
      "$DIM" "${PLAN_STEP_KINDS[$_p_i]}" "$RESET" "${PLAN_STEP_DESCS[$_p_i]}"
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
  printf "\n  %sWhat will happen:%s\n" "$BOLD" "$RESET"
  # Homebrew's install prompts for the Mac password once; a cold Mac without the
  # Command Line Tools also fetches them, which can be slow.
  if ! command -v brew >/dev/null 2>&1; then
    printf "    - macOS will ask for your Mac password once.\n"
    if ! xcode-select -p >/dev/null 2>&1; then
      printf "    - A one-time download may take ~10-15 min.\n"
    fi
  fi
  # GitHub sign-in needs an account a from-zero person may not have yet.
  case " ${PLAN_STEP_IDS[*]} " in
    *" gh-auth "*)
      printf "    - You'll also sign into GitHub - create a free account first if you don't have one.\n" ;;
  esac
  # Account sign-in — harness-accurate wording, no pricing.
  case "$PLAN_DEFAULT_HARNESS" in
    claude) _p_acct="Claude" ;;
    codex)  _p_acct="Codex" ;;
    *)      _p_acct="$PLAN_DEFAULT_HARNESS" ;;
  esac
  printf "    - At the end you'll sign into your %s account in the browser - create one first if you don't have it.\n" "$_p_acct"
  # Where it works + the safety habit.
  printf "    - The agent works in %s and asks before changing files or running commands.\n" \
    "${STARTER_DIR:-$HOME/git/first-project}"
}

# confirm_plan: the one interactive gate. 0 = proceed, 1 = abort. Non-tty (no
# keyboard) aborts rather than guessing — callers pass --yes for headless runs.
confirm_plan() {
  if [ ! -t 0 ]; then
    error "No terminal to confirm. Re-run with --yes to proceed non-interactively."
    return 1
  fi
  printf "  %sPress Enter to set up, or Ctrl-C to cancel.%s " "$YELLOW" "$RESET"
  read -r _p_reply
  case "$_p_reply" in
    ""|[Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}
