#!/usr/bin/env bash

# =========================================================
# AEGIS HARNESS — AIDER MUTATION SUBSTRATE
# =========================================================
#
# Version: 1.0
# Layer: Mutation Substrate
# Status: Operational
#
# Responsibilities:
#
# - resolve mutation targets from epistemic handover
#   and observed_request_alignment capability payload
# - build bounded aider invocation inside git worktree
# - capture git diff as mutation evidence
# - emit bounded mutation artifact (diff JSON)
#
# This substrate intentionally:
#
# - does not commit, push, or manage git state (runtime owns)
# - does not apply mutations to the main worktree
# - does not inherit implicit repository awareness
# - exposes only the diff as an artifact candidate
# - delegates promotion decisions to the runtime
#
# =========================================================

set -Eeuo pipefail

# =========================================================
# ROOT RESOLUTION
# =========================================================

readonly AEGIS_AIDER_SUBSTRATE_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
)"

cd "${AEGIS_AIDER_SUBSTRATE_ROOT}"

# =========================================================
# CONFIGURATION
# =========================================================

[[ -f ".harness/config.sh" ]] || {
  echo "[AEGIS][AIDER][FATAL] missing_config" >&2
  exit 1
}

source ".harness/config.sh"

# =========================================================
# INPUTS
# =========================================================

readonly AIDER_SKILL_FILE="${1:-}"
readonly AIDER_CAPABILITY_PAYLOAD_DIR="${2:-}"

# =========================================================
# LOGGING
# =========================================================

aider_log() {
  echo "[AEGIS][AIDER] $*" >&2
}

aider_warn() {
  echo "[AEGIS][AIDER][WARN] $*" >&2
}

aider_fatal() {
  echo "[AEGIS][AIDER][FATAL] $*" >&2
  exit 1
}

# =========================================================
# VALIDATION
# =========================================================

validate_aider_substrate_inputs() {

  [[ -n "${AEGIS_EXECUTION_SURFACE_PATH:-}" ]] \
    || aider_fatal "missing_execution_surface_path"

  [[ -d "${AEGIS_EXECUTION_SURFACE_PATH}" ]] \
    || aider_fatal "execution_surface_not_materialized"

  [[ -n "${AEGIS_INVESTIGATION_INPUT:-}" ]] \
    || aider_fatal "missing_investigation_input"

  [[ -n "${AEGIS_MODE:-}" ]] \
    || aider_fatal "missing_execution_mode"

  [[ -n "${AEGIS_EXECUTION_ID:-}" ]] \
    || aider_fatal "missing_execution_id"

  [[ -n "${AEGIS_MUTATION_MODEL:-}" ]] \
    || aider_fatal "missing_mutation_model"

  [[ -f "${AIDER_SKILL_FILE}" ]] \
    || aider_fatal "missing_skill_file"

  [[ -d "${AIDER_CAPABILITY_PAYLOAD_DIR}" ]] \
    || aider_fatal "missing_capability_payload_directory"

  command -v git >/dev/null 2>&1 \
    || aider_fatal "missing_dependency_git"

  [[ -f ".venv/bin/aider" ]] \
    || aider_fatal "missing_aider_binary"
}

# =========================================================
# TARGET RESOLUTION
# =========================================================

# Resolve mutation targets from:
# 1. observed_request_alignment.resolved_paths (builder payload) — highest priority
# 2. epistemic_state.next_attention_targets (epistemic handover)
# 3. filesystem.search_symbol payload matches — fallback

resolve_mutation_targets() {

  local targets=()

  # Source 1: structural.builder payload → observed_request_alignment
  # (Available only if capability payloads were NOT cleaned up between modes)
  local builder_payload="${AIDER_CAPABILITY_PAYLOAD_DIR}/structural_builder.json"
  if [[ -f "${builder_payload}" ]]; then
    local resolved_paths
    resolved_paths="$(
      jq -r '
        .payload.observed_request_alignment.resolved_paths[]? // empty
      ' "${builder_payload}" 2>/dev/null || true
    )"
    while IFS= read -r path; do
      [[ -z "${path}" ]] && continue
      targets+=("${path}")
    done <<< "${resolved_paths}"
  fi

  # Source 2: epistemic handover → artifact_snapshot.observed_request_alignment
  # (The discovery artifact is stored here in full; resolved_paths survives cleanup)
  if [[ "${#targets[@]}" -eq 0 ]] && [[ -f "${AEGIS_EPISTEMIC_HANDOVER_FILE}" ]]; then
    local snapshot_paths
    snapshot_paths="$(
      jq -r '
        .artifact_snapshot.observed_request_alignment.resolved_paths[]? // empty
      ' "${AEGIS_EPISTEMIC_HANDOVER_FILE}" 2>/dev/null || true
    )"
    while IFS= read -r path; do
      [[ -z "${path}" ]] && continue
      targets+=("${path}")
    done <<< "${snapshot_paths}"
  fi

  # Source 3: epistemic handover → artifact_snapshot.ranked_targets (explicit_request)
  if [[ "${#targets[@]}" -eq 0 ]] && [[ -f "${AEGIS_EPISTEMIC_HANDOVER_FILE}" ]]; then
    local ranked_files
    ranked_files="$(
      jq -r '
        .artifact_snapshot.ranked_targets[]?
        | select(.type == "explicit_request")
        | .file // empty
      ' "${AEGIS_EPISTEMIC_HANDOVER_FILE}" 2>/dev/null || true
    )"
    while IFS= read -r path; do
      [[ -z "${path}" ]] && continue
      targets+=("${path}")
    done <<< "${ranked_files}"
  fi

  # Source 4: epistemic handover → epistemic_state.next_attention_targets
  if [[ "${#targets[@]}" -eq 0 ]] && [[ -f "${AEGIS_EPISTEMIC_HANDOVER_FILE}" ]]; then
    local handover_targets
    handover_targets="$(
      jq -r '
        .epistemic_state.next_attention_targets[]? // empty
      ' "${AEGIS_EPISTEMIC_HANDOVER_FILE}" 2>/dev/null || true
    )"
    while IFS= read -r path; do
      [[ -z "${path}" ]] && continue
      # Only include targets that look like file paths (contain a dot or slash)
      if [[ "${path}" == *"."* ]] || [[ "${path}" == *"/"* ]]; then
        targets+=("${path}")
      fi
    done <<< "${handover_targets}"
  fi

  # Source 5: search_symbol payload — extract file paths from matches
  if [[ "${#targets[@]}" -eq 0 ]]; then
    local search_payload="${AIDER_CAPABILITY_PAYLOAD_DIR}/filesystem_search_symbol.json"
    if [[ -f "${search_payload}" ]]; then
      local search_files
      search_files="$(
        jq -r '
          .payload.matches[]?.file? // empty
        ' "${search_payload}" 2>/dev/null | sort -u || true
      )"
      while IFS= read -r path; do
        [[ -z "${path}" ]] && continue
        targets+=("${path}")
      done <<< "${search_files}"
    fi
  fi

  # Deduplicate while preserving order
  local seen=()
  local unique_targets=()
  for t in "${targets[@]}"; do
    local found=0
    for s in "${seen[@]:-}"; do
      [[ "${s}" == "${t}" ]] && found=1 && break
    done
    if [[ "${found}" -eq 0 ]]; then
      seen+=("${t}")
      unique_targets+=("${t}")
    fi
  done

  printf '%s\n' "${unique_targets[@]:-}"
}

# =========================================================
# TEMP FILE CLEANUP
# =========================================================

_AIDER_TMP_FILES=()

aider_mktemp() {
  local tmp
  tmp="$(mktemp)"
  _AIDER_TMP_FILES+=("${tmp}")
  printf '%s' "${tmp}"
}

cleanup_aider_substrate() {
  set +e
  for f in "${_AIDER_TMP_FILES[@]:-}"; do
    rm -f "${f}" >/dev/null 2>&1 || true
  done
  set -e
}

trap cleanup_aider_substrate EXIT
trap 'aider_warn "Interrupted"; exit 130' INT TERM

# =========================================================
# MUTATION PROMPT ASSEMBLY
# =========================================================

assemble_mutation_prompt() {

  local prompt_file="$1"

  cat > "${prompt_file}" << EOF
You are executing inside Aegis Harness in bounded mutation mode.

Mode: ${AEGIS_MODE}
Execution ID: ${AEGIS_EXECUTION_ID}

Skill contract:
$(cat "${AIDER_SKILL_FILE}")

---

Investigation input (operator mutation demand):
${AEGIS_INVESTIGATION_INPUT}

---

Apply the minimal sufficient mutation described in the investigation input.
Preserve runtime sovereignty, protocol integrity, and containment integrity.
Do not introduce speculative changes beyond what is explicitly requested.
Do not add explanations or narration.
Apply the change and stop.
EOF
}

# =========================================================
# AIDER INVOCATION
# =========================================================

invoke_aider() {

  local prompt_file="$1"
  shift
  local file_args=("$@")

  local aider_bin="${AEGIS_AIDER_SUBSTRATE_ROOT}/.venv/bin/aider"
  local mutation_conf="${AEGIS_AIDER_SUBSTRATE_ROOT}/.aider.mutation.conf.yml"

  local aider_cmd=(
    "${aider_bin}"
    "--config" "${mutation_conf}"
    "--model" "${AEGIS_MUTATION_MODEL}"
    "--openai-api-base" "${OPENAI_API_BASE}"
    "--message-file" "${prompt_file}"
    "--yes-always"
    "--no-auto-commits"
    "--no-git"
    "--no-stream"
    "--no-pretty"
  )

  # Add mutation target files
  for f in "${file_args[@]:-}"; do
    aider_cmd+=("--file" "${f}")
  done

  aider_log "Invoking aider mutation substrate..."
  aider_log "Model: ${AEGIS_MUTATION_MODEL}"
  aider_log "Targets: ${file_args[*]:-<none>}"

  # Run aider inside the worktree
  (
    cd "${AEGIS_EXECUTION_SURFACE_PATH}"

    # Pass API key through env; aider reads OPENAI_API_KEY
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      "${aider_cmd[@]}" >/dev/null 2>&1 || true
  )
}

# =========================================================
# DIFF CAPTURE
# =========================================================

capture_worktree_diff() {

  local diff_output

  diff_output="$(
    git \
      --git-dir="${AEGIS_AIDER_SUBSTRATE_ROOT}/.git" \
      --work-tree="${AEGIS_EXECUTION_SURFACE_PATH}" \
      diff \
      HEAD \
      -- \
      2>/dev/null || true
  )"

  printf '%s' "${diff_output}"
}

# =========================================================
# ARTIFACT EMISSION
# =========================================================

emit_mutation_artifact() {

  local diff_content="$1"
  shift
  local mutation_targets=("$@")

  local files_changed
  files_changed="$(
    printf '%s\n' "${diff_content}" \
      | grep '^+++ b/' \
      | sed 's|^+++ b/||' \
      | jq -R . \
      | jq -sc '.'
  )"

  [[ -n "${files_changed}" ]] \
    || files_changed='[]'

  local primary_target="${mutation_targets[0]:-unknown}"

  local attention_targets_json
  if [[ "${#mutation_targets[@]}" -gt 0 ]]; then
    attention_targets_json="$(
      printf '%s\n' "${mutation_targets[@]}" | jq -R . | jq -sc '.'
    )"
  else
    attention_targets_json='[]'
  fi

  local artifact_tmp
  artifact_tmp="$(aider_mktemp)"

  local diff_tmp
  diff_tmp="$(aider_mktemp)"
  printf '%s' "${diff_content}" > "${diff_tmp}"

  jq -n \
    --arg mode "${AEGIS_MODE}" \
    --arg execution_id "${AEGIS_EXECUTION_ID}" \
    --arg mutation_target "${primary_target}" \
    --rawfile diff "${diff_tmp}" \
    --argjson files_changed "${files_changed}" \
    --argjson next_attention_targets "${attention_targets_json}" \
    '{
      mode: $mode,
      execution_id: $execution_id,
      mutation_target: $mutation_target,
      diff: $diff,
      files_changed: $files_changed,
      handover_attention: {
        next_attention_targets: $next_attention_targets,
        attention_scope: "mutation_applied",
        attention_reason: ("repair applied mutation to: " + $mutation_target)
      }
    }' > "${artifact_tmp}"

  echo "${AEGIS_ARTIFACT_BEGIN_MARKER}"
  cat "${artifact_tmp}"
  echo "${AEGIS_ARTIFACT_END_MARKER}"
}

# =========================================================
# MAIN
# =========================================================

main() {

  validate_aider_substrate_inputs

  aider_log "Resolving mutation targets..."

  local mutation_targets=()
  while IFS= read -r target; do
    [[ -z "${target}" ]] && continue
    mutation_targets+=("${target}")
  done < <(resolve_mutation_targets)

  if [[ "${#mutation_targets[@]}" -eq 0 ]]; then
    aider_warn "no_mutation_targets_resolved — using investigation input only"
  else
    aider_log "Mutation targets: ${mutation_targets[*]}"
  fi

  local prompt_file
  prompt_file="$(aider_mktemp)"
  assemble_mutation_prompt "${prompt_file}"

  invoke_aider "${prompt_file}" "${mutation_targets[@]:-}"

  aider_log "Capturing worktree diff..."

  local diff_content
  diff_content="$(capture_worktree_diff)"

  if [[ -z "${diff_content}" ]]; then
    aider_warn "empty_diff — aider produced no changes"
    diff_content="(no changes)"
  fi

  aider_log "Emitting mutation artifact..."

  emit_mutation_artifact "${diff_content}" "${mutation_targets[@]:-}"

  aider_log "Aider mutation substrate completed"
}

main "$@"
