#!/usr/bin/env bash

# =========================================================
# AEGIS RUN ORCHESTRATOR (KISS)
# =========================================================
#
# OPERATOR GUIDE
#
# ---------------------------------------------------------
# FULL MUTATION PIPELINE
# ---------------------------------------------------------
#
# ./run_aegis.sh
#
# Executes:
#
# discovery
# -> forensics
# -> repair
# -> optimize
# -> adversarial
# -> validation
#
#
# ---------------------------------------------------------
# READONLY PIPELINE
# ---------------------------------------------------------
#
# ./run_aegis.sh readonly
#
# Executes:
#
# discovery
# -> forensics
#
#
# ---------------------------------------------------------
# RESUME PIPELINE
# ---------------------------------------------------------
#
# ./run_aegis.sh --resume
#
# Reads:
#
# .harness/runtime/epistemic_handover.json
#
# Continues from next mode.
#
#
# ---------------------------------------------------------
# TARGET REPOSITORY
# ---------------------------------------------------------
#
# ./run_aegis.sh \
#   --target tests/scenarios/python
#
#
# ---------------------------------------------------------
# FAIL FAST
# ---------------------------------------------------------
#
# Any failure immediately aborts execution.
#
#
# ---------------------------------------------------------
# REPORT
# ---------------------------------------------------------
#
# Shows:
#
# - mode timings
# - total duration
# - final mode
# - final attention targets
# - status
#
# =========================================================

set -Eeuo pipefail

readonly HANDOVER_FILE=".harness/runtime/epistemic_handover.json"

# Tracks whether the Isolated Workspace was successfully initialized.
# Used by the cleanup trap to avoid removing a workspace that was never created.
WORKSPACE_INITIALIZED=false

declare -A PIPELINES=(
  [readonly]="discovery forensics"
  [mutation]="discovery forensics repair optimize adversarial validation"
)

PIPELINE="mutation"
TARGET=""
RESUME=false
UNTIL=""
ISSUE_NUMBER=""
ISSUE_PATH=""
INVESTIGATION_INPUT=""
declare -a POSITIONAL=()

declare -A MODE_TIMINGS
declare -a EXECUTION_MODES

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[RUN][FATAL] missing dependency: $1" >&2
    exit 1
  }
}

pipeline_contains_mutation() {
  [[ "${PIPELINE}" == "mutation" ]]
}

check_dependencies() {

  echo
  echo "Checking requirements..."
  echo

  require jq
  echo "jq           ✓"

  require git
  echo "git          ✓"

  if pipeline_contains_mutation; then
    require aider
    echo "aider        ✓"
  fi

  echo
}

next_mode() {

  case "$1" in
    discovery)   echo forensics ;;
    forensics)   echo repair ;;
    repair)      echo optimize ;;
    optimize)    echo adversarial ;;
    adversarial) echo validation ;;
    *)           echo "" ;;
  esac

}

resolve_resume() {

  [[ -f "${HANDOVER_FILE}" ]] || {
    echo "[RUN][FATAL] handover not found"
    exit 1
  }

  local last_mode

  last_mode="$(
    jq -r '.artifact_snapshot.mode // empty' \
      "${HANDOVER_FILE}"
  )"

  local resume_from

  resume_from="$(next_mode "${last_mode}")"

  [[ -n "${resume_from}" ]] || {
    echo "[RUN] nothing to resume"
    exit 0
  }

  local found=false
  local mode

  for mode in ${PIPELINES[$PIPELINE]}; do

    if [[ "${mode}" == "${resume_from}" ]]; then
      found=true
    fi

    $found && EXECUTION_MODES+=("${mode}")
  done

}

build_mode_list() {

  local mode

  for mode in ${PIPELINES[$PIPELINE]}; do
    EXECUTION_MODES+=("${mode}")
  done

}

run_mode() {

  local mode="$1"

  echo
  echo "================================================="
  echo "MODE: ${mode}"
  echo "================================================="

  local start
  local end
  local duration

  start=$(date +%s)

  local cmd=(bash runtime_aegis.sh "${mode}")
  if [[ -n "${TARGET}" ]]; then
    cmd+=("--target" "${TARGET}")
  fi
  if [[ -n "${ISSUE_NUMBER}" ]]; then
    cmd+=("--issue" "${ISSUE_NUMBER}")
  fi
  if [[ -n "${INVESTIGATION_INPUT}" ]]; then
    cmd+=("${INVESTIGATION_INPUT}")
  fi

  "${cmd[@]}"

  end=$(date +%s)

  duration=$((end-start))

  MODE_TIMINGS["${mode}"]="${duration}"

}

show_final_report() {

  local total=0
  local mode

  echo
  echo "══════════════════════════════"
  echo "AEGIS RUN REPORT"
  echo "══════════════════════════════"
  echo

  for mode in "${EXECUTION_MODES[@]}"; do

    local timing="${MODE_TIMINGS[$mode]:-0}"

    printf "%-12s ✓ %ss\n" \
      "${mode^}" \
      "${timing}"

    total=$((total + timing))
  done

  echo
  echo "Total: ${total}s"
  echo

  if [[ -f "${HANDOVER_FILE}" ]]; then

    echo "Final Mode:"
    jq -r '.artifact_snapshot.mode // "unknown"' \
      "${HANDOVER_FILE}"

    echo

    echo "Final Attention:"

    jq -r '
      .epistemic_state.next_attention_targets[]?
    ' "${HANDOVER_FILE}"

    echo

    if jq -e '
      .artifact_snapshot.operational_context.verdict?
    ' "${HANDOVER_FILE}" >/dev/null 2>&1; then

      echo "Verdict:"

      jq -r '
        .artifact_snapshot.operational_context.verdict
      ' "${HANDOVER_FILE}"

      echo
    fi

  fi

  echo "Pipeline Status:"
  echo "SUCCESS"

  echo
  echo "══════════════════════════════"

}

resolve_default_target() {

  [[ -n "${TARGET:-}" ]] && return

  if [[ -d "src" ]]; then
    TARGET="src"
  else
    TARGET="."
  fi
}

# =========================================================
# PHASE 0.1 — EXECUTION BOUNDARY
# =========================================================
#
# Invokes runtime_aegis.sh inside a clean environment containing
# only the constitutionally authorized variables. No Bootstrap-layer
# state (PIPELINE, RESUME, UNTIL, TARGET, ISSUE_PATH, etc.) passes
# through. The Runtime sources everything else from .harness/config.sh
# and .harness/local.env at startup.
#
# The authorized boundary is:
#   PATH, HOME, TERM, USER        — system requirements
#   AEGIS_INVESTIGATION_INPUT     — active task text
#   AEGIS_EVIDENCE_TARGET_PATH    — workspace path (Phase 0.2)
#   OPENAI_API_KEY, OPENAI_API_BASE — provider credentials (if set)
#
# The exit code of runtime_aegis.sh is the Validated Result signal
# consumed by execute_issue() (Phase 0.3).

run_bounded_mode() {

  local mode="$1"
  local task="$2"
  local workspace="$3"

  echo
  echo "================================================="
  echo "MODE: ${mode}"
  echo "================================================="

  local start end duration
  start=$(date +%s)

  # Build the boundary environment: only authorized variables cross.
  # Runtime sources .harness/config.sh and .harness/local.env itself.
  env -i \
    PATH="${PATH}" \
    HOME="${HOME}" \
    TERM="${TERM:-xterm}" \
    USER="${USER:-}" \
    AEGIS_INVESTIGATION_INPUT="${task}" \
    AEGIS_EVIDENCE_TARGET_PATH="${workspace}" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    OPENAI_API_BASE="${OPENAI_API_BASE:-}" \
    bash runtime_aegis.sh "${mode}"

  end=$(date +%s)
  duration=$((end - start))
  MODE_TIMINGS["${mode}"]="${duration}"
}

# =========================================================
# BOOTSTRAP — PLAN PARSING
# =========================================================

# Resolve the first unchecked task from the Engineering Plan.
# Outputs the task text, or empty string if none remain.
resolve_next_task() {
  local plan="$1"
  grep -m 1 '^[[:space:]]*- \[ \]' "${plan}" \
    | sed -E 's/^[[:space:]]*- \[ \] //'
}

# Mark the first unchecked task as completed.
check_next_task() {
  local plan="$1"
  # Portable: replace first occurrence of '- [ ]' with '- [x]'
  sed -i.bak -e '0,/^[[:space:]]*- \[ \]/s/^\([[:space:]]*\)- \[ \]/\1- [x]/' "${plan}"
  rm -f "${plan}.bak"
}

# Extract the plan title (first # heading) for display.
resolve_plan_title() {
  local plan="$1"
  grep -m 1 '^# ' "${plan}" | sed 's/^# //'
}

# Extract the plan description (first non-heading, non-task paragraph).
resolve_plan_description() {
  local plan="$1"
  awk '/^# /{found=1; next} found && /^[^-#[:space:]]/{print; exit}' "${plan}"
}

# Display the current plan contents for review.
show_plan_review() {
  local plan="$1"
  echo
  echo "════════════════════════════════════════"
  echo "  ENGINEERING PLAN"
  echo "════════════════════════════════════════"
  cat "${plan}"
  echo
  echo "════════════════════════════════════════"
  echo
}

# Invoke the Planning Translator skill (issue_refiner) via raw_llm.
refine_plan_with_ai() {
  local plan="$1"
  local skill=".skills/bootstrap/issue_refiner.md"

  [[ -f "${skill}" ]] || {
    echo "[BOOTSTRAP][WARN] issue_refiner skill not found — skipping refinement."
    return 0
  }

  [[ -f "scripts/substrates/raw_llm.sh" ]] || {
    echo "[BOOTSTRAP][WARN] raw_llm substrate not found — skipping refinement."
    return 0
  }

  local plan_content
  plan_content="$(cat "${plan}")"

  local refined
  refined="$(
    AEGIS_ACTIVE_TASK="" \
    AEGIS_ISSUE_DESCRIPTION="${plan_content}" \
    bash scripts/substrates/raw_llm.sh "${skill}"
  )" || {
    echo "[BOOTSTRAP][WARN] Refinement failed — keeping original plan."
    return 0
  }

  if [[ -n "${refined}" ]]; then
    printf '%s\n' "${refined}" > "${plan}"
    echo "[BOOTSTRAP] Plan refined."
  fi
}

# Interactive Bootstrap review loop.
prepare_issue() {
  local plan="$1"

  while true; do
    show_plan_review "${plan}"
    echo "How do you want to continue?"
    echo "  1) Execute"
    echo "  2) Edit"
    echo "  3) Improve with AI"
    echo "  4) Cancel"
    echo
    read -r -p "> " choice

    case "${choice}" in
      1) return 0 ;;
      2)
        local editor="${EDITOR:-vi}"
        "${editor}" "${plan}"
        ;;
      3)
        refine_plan_with_ai "${plan}"
        ;;
      4)
        echo "[BOOTSTRAP] Cancelled."
        exit 0
        ;;
      *)
        echo "[BOOTSTRAP] Invalid choice. Please enter 1, 2, 3 or 4."
        ;;
    esac
  done
}

# =========================================================
# BOOTSTRAP — WORKSPACE LIFECYCLE
# =========================================================

ISSUE_WORKSPACE_PATH=".harness/execution_surfaces/issue_workspace"

initialize_workspace() {
  echo
  echo "[BOOTSTRAP] Initializing Isolated Workspace..."

  # Remove stale worktree if exists
  if [[ -d "${ISSUE_WORKSPACE_PATH}" ]]; then
    git worktree remove --force "${ISSUE_WORKSPACE_PATH}" 2>/dev/null || true
  fi

  git worktree add --detach "${ISSUE_WORKSPACE_PATH}" HEAD

  export AEGIS_WORKSPACE_PATH="${ISSUE_WORKSPACE_PATH}"
  echo "[BOOTSTRAP] Workspace ready: ${ISSUE_WORKSPACE_PATH}"
}

finalize_workspace() {
  local plan="$1"

  echo
  echo "════════════════════════════════════════"
  echo "  ALL TASKS COMPLETE"
  echo "════════════════════════════════════════"
  echo
  echo "How do you want to continue?"
  echo "  1) Commit"
  echo "  2) Add new tasks"
  echo "  3) Close without commit"
  echo
  read -r -p "> " choice

  case "${choice}" in
    1)
      _promote_workspace "${plan}"
      ;;
    2)
      local editor="${EDITOR:-vi}"
      "${editor}" "${plan}"
      # Return 1 — execute_issue() loop will pick up new tasks.
      return 1
      ;;
    3)
      echo "[BOOTSTRAP] Closed without commit."
      ;;
    *)
      echo "[BOOTSTRAP] Invalid choice. Closing without commit."
      ;;
  esac

  # Workspace teardown is handled by the EXIT trap.
  return 0
}

# =========================================================
# PHASE 0.4 — GIT PROMOTION
# =========================================================
#
# Promotion flow:
#   1. Commit all workspace changes inside the worktree → get SHA.
#   2. cherry-pick that SHA onto the main repo.
#
# This is the only correct way to promote from a detached-HEAD worktree.
# git merge/cherry-pick require a commit ref, not a filesystem path.

_promote_workspace() {
  local plan="$1"
  local title
  title="$(resolve_plan_title "${plan}")"

  echo "[BOOTSTRAP] Committing workspace changes..."

  local commit_sha
  commit_sha="$(
    cd "${ISSUE_WORKSPACE_PATH}" &&
    git add -A &&
    git diff --cached --quiet && {
      echo "[BOOTSTRAP] No changes to commit." >&2
      echo ""
    } || {
      git commit -m "${title}" --quiet &&
      git rev-parse HEAD
    }
  )" || {
    echo "[BOOTSTRAP][WARN] Workspace commit failed. No changes promoted."
    return 0
  }

  if [[ -z "${commit_sha}" ]]; then
    echo "[BOOTSTRAP] Nothing to promote."
    return 0
  fi

  echo "[BOOTSTRAP] Promoting commit ${commit_sha} to main repository..."

  git cherry-pick "${commit_sha}" || {
    echo "[BOOTSTRAP][WARN] cherry-pick failed. Resolve conflicts manually."
    git cherry-pick --abort 2>/dev/null || true
    return 0
  }

  echo "[BOOTSTRAP] Promotion complete."
}

# =========================================================
# BOOTSTRAP — ISSUE EXECUTION LOOP
# =========================================================

# =========================================================
# PHASE 0.3 — VALIDATED RESULT
# =========================================================
#
# execute_issue() no longer inspects the handover file or
# iterates over pipeline modes. Bootstrap's role is:
#   1. Select next Task.
#   2. Build Execution Context.
#   3. Invoke the Runtime pipeline via run_bounded_mode() per mode.
#   4. Receive the Validated Result (exit code).
#   5. On success: mark task. On failure: halt.
#
# The repair-candidate precondition is enforced by runtime_aegis.sh
# validate_mode_preconditions() — not by Bootstrap.

execute_issue() {
  local plan="$1"

  while true; do

    local active_task
    active_task="$(resolve_next_task "${plan}")"

    if [[ -z "${active_task}" ]]; then
      # All tasks complete — delegate finalization to Bootstrap.
      finalize_workspace "${plan}" && break || continue
    fi

    echo
    echo "════════════════════════════════════════"
    echo "  ACTIVE TASK"
    echo "  ${active_task}"
    echo "════════════════════════════════════════"
    echo

    # Build Execution Context: Bootstrap constructs, Runtime consumes.
    local workspace="${AEGIS_WORKSPACE_PATH}"

    build_mode_list
    EXECUTION_MODES=()
    build_mode_list

    # PHASE 0.3: Run each mode via the Execution Boundary.
    # Exit code from run_bounded_mode() is the Validated Result signal.
    local validated_result=0
    local mode
    for mode in "${EXECUTION_MODES[@]}"; do

      run_bounded_mode "${mode}" "${active_task}" "${workspace}" || {
        validated_result=$?
        echo "[BOOTSTRAP] Runtime returned non-zero exit (${validated_result}). Halting task."
        break
      }

      if [[ -n "${UNTIL:-}" ]] && [[ "${mode}" == "${UNTIL}" ]]; then
        echo "[BOOTSTRAP] Stopped at mode ${mode} due to --until limit."
        break
      fi
    done

    # PHASE 0.3: Bootstrap receives Validated Result and decides.
    if [[ "${validated_result}" -eq 0 ]]; then
      check_next_task "${plan}"
      echo "[BOOTSTRAP] Task completed and marked."
    else
      echo "[BOOTSTRAP] Task failed (Validated Result: ${validated_result}). Halting issue execution."
      break
    fi

    show_final_report
    EXECUTION_MODES=()

  done
}

# =========================================================
# CLI PARSING
# =========================================================

parse_cli() {

  while [[ $# -gt 0 ]]; do

    case "$1" in

      readonly)
        PIPELINE="readonly"
        ;;

      --pipeline)
        shift
        [[ $# -gt 0 ]] || { echo "[RUN][FATAL] missing pipeline value" >&2; exit 1; }
        PIPELINE="$1"
        ;;

      --until)
        shift
        [[ $# -gt 0 ]] || { echo "[RUN][FATAL] missing until value" >&2; exit 1; }
        UNTIL="$1"
        ;;

      --resume)
        RESUME=true
        ;;

      --target)
        shift
        [[ $# -gt 0 ]] || { echo "[RUN][FATAL] missing target value" >&2; exit 1; }
        TARGET="$1"
        ;;

      --issue)
        shift
        [[ $# -gt 0 ]] || { echo "[RUN][FATAL] missing issue value" >&2; exit 1; }
        ISSUE_NUMBER="$1"
        ;;

      --plan)
        shift
        [[ $# -gt 0 ]] || { echo "[RUN][FATAL] missing plan value" >&2; exit 1; }
        ISSUE_PATH="$1"
        ;;

      -*)
        echo "[RUN][FATAL] unknown argument: $1" >&2
        exit 1
        ;;

      *)
        # Auto-detect: if argument is a readable .md file, treat as Engineering Plan
        if [[ -f "$1" ]] && [[ "$1" == *.md ]]; then
          ISSUE_PATH="$1"
        else
          POSITIONAL+=("$1")
        fi
        ;;

    esac

    shift
  done

}

main() {

  parse_cli "$@"

  resolve_default_target

  [[ -n "${PIPELINES[$PIPELINE]:-}" ]] || {
    echo "[RUN][FATAL] unknown pipeline: ${PIPELINE}" >&2
    exit 1
  }

  check_dependencies

  # -------------------------------------------------------
  # PLANNING-CENTRIC PATH: Engineering Plan provided
  # -------------------------------------------------------
  if [[ -n "${ISSUE_PATH}" ]]; then

    [[ -f "${ISSUE_PATH}" ]] || {
      echo "[RUN][FATAL] Engineering Plan not found: ${ISSUE_PATH}" >&2
      exit 1
    }

    # PHASE 0.5 — CLEANUP TRAP
    # Registered only for the issue-centric path.
    # WORKSPACE_INITIALIZED guards against removing a workspace
    # that was never created (e.g. crash before initialize_workspace).
    _cleanup_workspace() {
      if [[ "${WORKSPACE_INITIALIZED}" == "true" ]]; then
        echo "[BOOTSTRAP] Cleaning up Isolated Workspace..." >&2
        git worktree remove --force "${ISSUE_WORKSPACE_PATH}" >/dev/null 2>&1 || true
        git worktree prune >/dev/null 2>&1 || true
      fi
    }
    trap '_cleanup_workspace' EXIT INT TERM

    prepare_issue "${ISSUE_PATH}"
    initialize_workspace
    WORKSPACE_INITIALIZED=true
    execute_issue "${ISSUE_PATH}"
    return 0
  fi

  # -------------------------------------------------------
  # LEGACY PATH: single-run prompt execution (unchanged)
  # -------------------------------------------------------

  # Resolve investigation input priority
  if [[ -n "${ISSUE_NUMBER}" ]]; then
    INVESTIGATION_INPUT=""
  elif [[ "${#POSITIONAL[@]}" -gt 0 ]]; then
    INVESTIGATION_INPUT="${POSITIONAL[*]}"
  else
    INVESTIGATION_INPUT="Analyze repository"
  fi

  if $RESUME; then
    resolve_resume
  else
    build_mode_list
  fi

  local mode

  for mode in "${EXECUTION_MODES[@]}"; do
    if [[ "${mode}" == "repair" ]] && [[ -f "${HANDOVER_FILE}" ]]; then
      local candidate_count
      candidate_count="$(
        jq -r '.artifact_snapshot.operational_context.repair_candidates | length // 0' \
          "${HANDOVER_FILE}" 2>/dev/null || echo 0
      )"
      if [[ "${candidate_count}" -eq 0 ]]; then
        echo
        echo "[RUN] No repair candidates proposed. Halting pipeline to collect more evidence."
        break
      fi
    fi

    run_mode "${mode}"
    if [[ -n "${UNTIL:-}" ]] && [[ "${mode}" == "${UNTIL}" ]]; then
      echo "[RUN] Stopped at mode ${mode} due to --until limit."
      break
    fi
  done

  show_final_report
}

main "$@"
