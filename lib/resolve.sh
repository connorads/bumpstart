# shellcheck shell=bash
# resolve.sh: PURE CORE. Given a repo root + an id list, produce a Plan (the
# PLAN_* globals below) or a domain error (PLAN_ERROR + non-zero return).
#
# No network, no installs, no filesystem writes — resolution is a pure function
# of the ids and the blocks' metadata, so the whole list is validated to a Plan
# BEFORE any effect. Depends on meta.sh (block_dir, meta_get). bash-3.2-clean:
# no associative arrays; set membership is a space-padded string match.
#
# Plan outputs (globals):
#   PLAN_STEP_IDS[]    ordered block ids to apply (presets dropped)
#   PLAN_STEP_KINDS[]  parallel: each step's KIND
#   PLAN_STEP_DESCS[]  parallel: each step's DESC
#   PLAN_DEFAULT_HARNESS   AGENT of the harness to launch (last-in-list-wins)
#   PLAN_TARGETS[]     harness-native instruction paths to symlink at the
#                      canonical file (one per harness present, deduped)
#   PLAN_ERROR         set on failure

# Kind ordering: lower runs first; launch happens after all steps.
_kind_rank() {
  case "$1" in
    harness)      echo 10 ;;
    app)          echo 15 ;;
    auth)         echo 20 ;;
    tool)         echo 30 ;;
    mcp)          echo 40 ;;
    skill)        echo 50 ;;
    instructions) echo 60 ;;
    preset)       echo 99 ;;
    *)            echo 90 ;;
  esac
}

# _expand <root> <id> <stack> — append the fully-expanded ids (INCLUDEs first,
# self last) to the _EXPANDED string. Deps land before dependents; a block's own
# id follows its includes. Sets PLAN_ERROR + returns 1 on unknown id or cycle.
_expand() {
  # These MUST be local: _expand recurses, and a clobbered id/dir/inc from an
  # inner call would corrupt the outer frame (e.g. node -> mise mise).
  local _ex_root="$1" _ex_id="$2" _ex_stack="$3" _ex_dir _ex_inc
  case " $_ex_stack " in
    *" $_ex_id "*) PLAN_ERROR="include cycle:$_ex_stack -> $_ex_id"; return 1 ;;
  esac
  _ex_dir="$(block_dir "$_ex_root" "$_ex_id")" || {
    PLAN_ERROR="unknown block: $_ex_id"; return 1
  }
  for _ex_inc in $(meta_get "$_ex_dir" INCLUDE); do
    _expand "$_ex_root" "$_ex_inc" "$_ex_stack $_ex_id" || return 1
  done
  _EXPANDED="$_EXPANDED $_ex_id"
  return 0
}

# resolve <root> <id>... — populate the PLAN_* globals or return 1 (PLAN_ERROR).
resolve() {
  _r_root="$1"; shift
  PLAN_ERROR=""
  PLAN_DEFAULT_HARNESS=""
  PLAN_STEP_IDS=(); PLAN_STEP_KINDS=(); PLAN_STEP_DESCS=(); PLAN_TARGETS=()
  _EXPANDED=""

  if [ $# -eq 0 ]; then
    PLAN_ERROR="no blocks requested"
    return 1
  fi

  for _r_id in "$@"; do
    _expand "$_r_root" "$_r_id" "" || return 1
  done

  # default-harness = the AGENT declared by the last id in the expanded
  # (input-order) list that declares one. Computed before kind-reordering, so it
  # is genuinely last-in-list-wins. The value is the agent's own name — the
  # binary to launch, the trust dispatch key (trust.sh), and the "Agent to
  # launch" line all want <agent>, never the block id.
  for _r_id in $_EXPANDED; do
    _r_dir="$(block_dir "$_r_root" "$_r_id")"
    _r_agent="$(meta_get "$_r_dir" AGENT)"
    if [ -n "$_r_agent" ]; then
      PLAN_DEFAULT_HARNESS="$_r_agent"
    fi
  done
  if [ -z "$PLAN_DEFAULT_HARNESS" ]; then
    PLAN_ERROR="no harness in plan (add e.g. 'claude' or 'codex')"
    return 1
  fi

  # Dedupe (first occurrence) and drop presets, decorating each surviving id with
  # "<rank> <index> <id>" so a stable numeric sort orders by kind then input.
  _r_seen=""; _r_i=0; _r_decorated=""
  for _r_id in $_EXPANDED; do
    case " $_r_seen " in *" $_r_id "*) continue ;; esac
    _r_seen="$_r_seen $_r_id"
    _r_dir="$(block_dir "$_r_root" "$_r_id")"
    _r_kind="$(meta_get "$_r_dir" KIND)"
    [ "$_r_kind" = "preset" ] && continue
    _r_decorated="$_r_decorated$(_kind_rank "$_r_kind") $_r_i $_r_id
"
    _r_i=$((_r_i + 1))
  done

  while read -r _r_rank _r_idx _r_id; do
    [ -z "$_r_id" ] && continue
    _r_dir="$(block_dir "$_r_root" "$_r_id")"
    PLAN_STEP_IDS+=("$_r_id")
    PLAN_STEP_KINDS+=("$(meta_get "$_r_dir" KIND)")
    PLAN_STEP_DESCS+=("$(meta_get "$_r_dir" DESC)")
  done < <(printf '%s' "$_r_decorated" | sort -k1,1n -k2,2n)

  # Instruction targets = the native TARGET of each harness present, deduped in
  # order — the paths we symlink at the canonical file. Only meaningful when some
  # step ships a content.md (that is what the canonical file is assembled from).
  # No content.md anywhere → nothing is written and nothing is linked, so we
  # leave PLAN_TARGETS empty and the preview stays honest.
  _r_n=${#PLAN_STEP_IDS[@]}
  _r_writes=false
  _r_i=0
  while [ "$_r_i" -lt "$_r_n" ]; do
    _r_dir="$(block_dir "$_r_root" "${PLAN_STEP_IDS[$_r_i]}")"
    # A per-OS content.<os>.md counts as content too (Windows node guidance).
    if [ -f "$_r_dir/content.md" ] || [ -f "$_r_dir/content.$(vibe_os).md" ]; then
      _r_writes=true; break
    fi
    _r_i=$((_r_i + 1))
  done
  [ "$_r_writes" != true ] && return 0

  _r_seen=""
  _r_i=0
  while [ "$_r_i" -lt "$_r_n" ]; do
    if [ "${PLAN_STEP_KINDS[$_r_i]}" = "harness" ]; then
      _r_dir="$(block_dir "$_r_root" "${PLAN_STEP_IDS[$_r_i]}")"
      _r_target="$(meta_get "$_r_dir" TARGET)"
      if [ -n "$_r_target" ]; then
        case " $_r_seen " in
          *" $_r_target "*) : ;;
          *) _r_seen="$_r_seen $_r_target"; PLAN_TARGETS+=("$_r_target") ;;
        esac
      fi
    fi
    _r_i=$((_r_i + 1))
  done

  return 0
}
