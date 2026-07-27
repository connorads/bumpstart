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
    app)          printf '%s' "$MAGENTA" ;;
    auth)         printf '%s' "$YELLOW" ;;
    tool)         printf '%s' "$CYAN" ;;
    mcp)          printf '%s' "$BLUE" ;;
    skill)        printf '%s' "$GREEN" ;;
    *)            printf '%s' "$DIM" ;;
  esac
}

# _step_satisfied <id>: mirror each block's own cheap check-then-act probe so the
# gate can dim steps already in place on a warm Mac. Reads the block's gate
# predicate from meta — SATISFIED_<os> (the richer gate-only escape hatch, e.g.
# gh signed-in or git identity set) else CHECK_<os> (the install skip predicate,
# also the default gate). The VIBE_APPS_DIR *-desktop test seam now lives inside
# those cells. Read-only; eval'd via if/else (never bare) under the applier's
# set -e. Returns 0 = satisfied (done), 1 = actionable but not done, 2 = unmapped
# (no cell -> rendered neutral). Instruction blocks are deliberately unmapped —
# "is this guidance already present" is the canonical-file question
# _render_expectations answers holistically, not per step. A wrong ✓ is worse
# than a neutral row, which is why the gate-only SATISFIED cell exists: a block
# whose "done" differs from "binary present" spells it out rather than overclaim.
_step_satisfied() {
  _ss_dir="$(block_dir "$ROOT" "$1")" || return 2
  _ss_cell="$(meta_get "$_ss_dir" "SATISFIED_$(vibe_os_key)")"
  [ -n "$_ss_cell" ] || _ss_cell="$(meta_get "$_ss_dir" "CHECK_$(vibe_os_key)")"
  [ -n "$_ss_cell" ] || return 2
  if eval "$_ss_cell"; then return 0; else return 1; fi
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
  # Probe each step once as we render it, so the confirm gate reflects the real
  # delta on a warm Mac (a re-run or a partly set-up machine) rather than the
  # cold-Mac forecast. Capture done/actionable counts for the reassurance line so
  # the probes run once, not twice.
  _p_done=0; _p_actionable=0
  # Instruction blocks silently back off when the canonical file already exists
  # (assemble_instructions in lib/instructions.sh). Compute that predicate once —
  # a single canonical_path call — so the skipped-row tag below and the Tier 1
  # "leaves it as-is" bullet share one source of truth and can never disagree.
  PLAN_INSTR_BACKOFF=false
  if [ ${#PLAN_TARGETS[@]} -gt 0 ] && [ "${FORCE:-false}" != true ] && [ -e "$(canonical_path)" ]; then
    PLAN_INSTR_BACKOFF=true
  fi
  while [ "$_p_i" -lt "$_p_n" ]; do
    _p_kind="${PLAN_STEP_KINDS[$_p_i]}"
    # Render-rule: a block with no cell for this OS and no script tail (e.g. mise
    # on Windows, pulled in but node-installs-via-winget there) is a dead row —
    # skip it unless it is an instructions block. Mac-invariant: every mac
    # non-instruction block has an INSTALL_MAC, so nothing is skipped here.
    if [ "$_p_kind" != instructions ] && ! _block_runs "$ROOT" "${PLAN_STEP_IDS[$_p_i]}"; then
      _p_i=$((_p_i + 1)); continue
    fi
    # `if` guard, not a bare call — _step_satisfied returns non-zero by design and
    # the applier runs under `set -e`, which would otherwise abort the render.
    if _step_satisfied "${PLAN_STEP_IDS[$_p_i]}"; then _p_rc=0; else _p_rc=$?; fi
    case "$_p_rc" in
      0) _p_actionable=$((_p_actionable+1)); _p_done=$((_p_done+1)) ;;
      1) _p_actionable=$((_p_actionable+1)) ;;
    esac
    # Will this row's guidance be merged? Keyed on *carries content*, not on KIND:
    # a tool block stacks a section into the canonical file too, and on a warm Mac
    # where we back off, its "✓ already set up" (a binary probe) would otherwise
    # imply guidance that was silently not merged. So say so on any row that
    # contributes content, and keep the pure-instruction wording it already had.
    _p_tag=""
    if [ "$PLAN_INSTR_BACKOFF" = true ] &&
       block_has_content "$(block_dir "$ROOT" "${PLAN_STEP_IDS[$_p_i]}")"; then
      if [ "$_p_kind" = instructions ]; then
        _p_tag="↷ skipped (file exists)"
      else
        _p_tag="↷ guidance skipped"
      fi
    fi
    # The trailing state text, from two independent facts: is the step already
    # done, and will its guidance land. ANSI lives in this string and never in the
    # %-14s badge arg, so colour bytes stay out of the badge's width count (the
    # longest PLAIN badge is "[instructions]" = 14).
    _p_state=""
    [ "$_p_rc" -eq 0 ] && _p_state="${GREEN}✓ already set up${RESET}"
    if [ -n "$_p_tag" ]; then
      [ -n "$_p_state" ] && _p_state="$_p_state ${DIM}·${RESET} "
      _p_state="${_p_state}${DIM}${_p_tag}${RESET}"
    fi
    if [ -n "$_p_state" ] && { [ "$_p_rc" -eq 0 ] || [ "$_p_kind" = instructions ]; }; then
      # A done step, or a pure instruction row that is a whole no-op: DIM the row,
      # a calm "nothing happens here" distinct from an actionable one.
      printf "    %s%-14s %s%s  %s\n" \
        "$DIM" "[$_p_kind]" "${PLAN_STEP_DESCS[$_p_i]}" "$RESET" "$_p_state"
    elif [ -n "$_p_state" ]; then
      # Still actionable, but its guidance won't land — keep the kind colour.
      printf "    %s%-14s%s %s  %s\n" \
        "$(_kind_colour "$_p_kind")" "[$_p_kind]" "$RESET" "${PLAN_STEP_DESCS[$_p_i]}" "$_p_state"
    else
      printf "    %s%-14s%s %s\n" \
        "$(_kind_colour "$_p_kind")" "[$_p_kind]" "$RESET" "${PLAN_STEP_DESCS[$_p_i]}"
    fi
    _p_i=$((_p_i + 1))
  done
  PLAN_STEPS_DONE=$_p_done
  PLAN_STEPS_ACTIONABLE=$_p_actionable
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
      claude) printf "    %s  (marks first-project trusted, and skips Claude's first-run onboarding screen)\n" "$HOME/.claude.json" ;;
      codex)  printf "    %s  (marks first-project trusted)\n" "$HOME/.codex/config.toml" ;;
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

# _agent_account <agent> — the brand a person signs into for an agent, read from
# the harness block that declares that AGENT (its ACCOUNT cell). Data, not a
# lookup table, so a new harness block names itself with no code change. Falls
# back to the agent name for a block that declares no ACCOUNT.
_agent_account() {
  _aa_out="$1"
  for _aa_dir in "$ROOT"/blocks/*/; do
    [ -f "$_aa_dir/meta" ] || continue
    [ "$(meta_get "$_aa_dir" AGENT)" = "$1" ] || continue
    _aa_cell="$(meta_get "$_aa_dir" ACCOUNT)"
    [ -n "$_aa_cell" ] && _aa_out="$_aa_cell"
    break
  done
  printf '%s' "$_aa_out"
}

# _render_expectations: set honest expectations once, from the resolved plan plus
# a couple of cheap probes. No pricing claims (tiers change); no duplicate of the
# just-in-time password narration (that fires at the prompt itself).
_render_expectations() {
  # Account label first — the brand actually signed into, not the CLI's name (a
  # Codex sign-in is a ChatGPT account). Assigned before any use because the
  # trust bullet below reuses it.
  _p_acct="$(_agent_account "$PLAN_DEFAULT_HARNESS")"

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
  # plain language. Idempotent verbs stay honest on re-runs where the effect is a
  # skip; the two effects that silently BACK OFF on a warm Mac (the instructions
  # file and Claude's trust) are made state-aware so the gate never promises a
  # change that won't happen.
  if [ ${#PLAN_TARGETS[@]} -gt 0 ]; then
    if [ "${FORCE:-false}" = true ]; then
      _exp "Rebuilds your one instructions file, backing up any existing one to .bak."
    elif [ "$PLAN_INSTR_BACKOFF" = true ]; then
      _exp "You already have an instructions file - vibe leaves it as-is and won't merge in new guidance (re-run with --force to rebuild it)."
    else
      _exp "Creates one instructions file that your agent reads every session."
    fi
  fi
  if [ "$PLAN_DEFAULT_HARNESS" = claude ] && [ -e "$HOME/.claude.json" ]; then
    _exp "You already have a Claude config, so vibe won't change its trust settings - you may see a one-time 'trust this folder?' prompt."
  else
    _exp "Marks your first-project folder as trusted, so $_p_acct won't keep asking permission to work there."
  fi
  case " ${PLAN_STEP_IDS[*]} " in
    *" git "*)
      _exp "Makes sure git has your name and email (from your GitHub account) and makes 'main' the default branch for new projects." ;;
  esac
  case " ${PLAN_STEP_IDS[*]} " in
    *" node "*|*" pnpm "*)
      _exp "Uses mise to manage your tool versions, keeping a small config in your home folder." ;;
  esac
  # GitHub sign-in needs an account a from-zero person may not have yet.
  case " ${PLAN_STEP_IDS[*]} " in
    *" gh-auth "*)
      _exp "You'll also sign into GitHub - create a free account first if you don't have one." ;;
  esac
  # gh and GitHub Desktop keep separate credential stores, so a plan with both
  # means two GitHub sign-ins. The second is not on this paste's critical path —
  # it happens whenever the app is first opened — so name it and say when.
  case " ${PLAN_STEP_IDS[*]} " in
    *" github-desktop "*)
      _exp "GitHub Desktop asks for its own GitHub sign-in the first time you open it - it can't reuse the terminal's." ;;
  esac
  _exp "At the end you'll sign into your $_p_acct account in the browser - create one first if you don't have it."
  # Which agent to install is not a tooling choice — it follows the subscription
  # the person already pays for, and a mismatch otherwise only surfaces at that
  # browser sign-in, after a cold-Mac install. So name the alternative here,
  # while Ctrl-C is still cheap. Only when the plan installs exactly one agent:
  # someone who asked for both has already answered the question. Generic — a new
  # harness block appears in this line with no code change.
  _p_harnesses=0
  _p_i=0
  while [ "$_p_i" -lt ${#PLAN_STEP_KINDS[@]} ]; do
    [ "${PLAN_STEP_KINDS[$_p_i]}" = harness ] && _p_harnesses=$((_p_harnesses + 1))
    _p_i=$((_p_i + 1))
  done
  if [ "$_p_harnesses" -eq 1 ]; then
    for _p_dir in "$ROOT"/blocks/*/; do
      [ -f "$_p_dir/meta" ] || continue
      _p_alt="$(meta_get "$_p_dir" AGENT)"
      [ -n "$_p_alt" ] || continue
      [ "$_p_alt" = "$PLAN_DEFAULT_HARNESS" ] && continue
      _exp "Use $(_agent_account "$_p_alt") instead? Press Ctrl-C and re-run with '$_p_alt' in place of '$PLAN_DEFAULT_HARNESS'."
    done
  fi
  # Warm-Mac reassurance: when every installable step is already in place, say so
  # plainly. Reads the counts captured by the render_plan step loop above.
  if [ "${PLAN_STEPS_ACTIONABLE:-0}" -gt 0 ] && [ "${PLAN_STEPS_DONE:-0}" -eq "${PLAN_STEPS_ACTIONABLE:-0}" ]; then
    _exp "Everything installable is already in place - vibe will just link things up and drop you into $_p_acct."
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
