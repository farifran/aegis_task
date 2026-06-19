#!/usr/bin/env bash

# =========================================================
# AEGIS CAPABILITY — filesystem.read
# =========================================================
#
# Classification:
# readonly
#
# Responsibilities:
#
# - bounded file inspection
# - deterministic evidence generation
# - payload provenance emission
# - bounded output truncation
#
# This capability intentionally:
#
# - exposes only file content as evidence;
# - avoids implicit repository inheritance;
# - propagates execution identity;
# - enforces evidence-size budgets.
#
# =========================================================

set -Eeuo pipefail

# =========================================================
# INPUTS
# =========================================================

readonly TARGET_FILE="${1:-}"

# =========================================================
# LIMITS
# =========================================================

max_read_bytes="${AEGIS_FILE_CONTENT_MAX_BYTES:-50000}"
if [[ "$(basename "${TARGET_FILE}")" == "epistemic_handover.json" ]]; then
  max_read_bytes="${AEGIS_EPISTEMIC_HANDOVER_MAX_BYTES:-100000}"
fi
readonly MAX_READ_BYTES="${max_read_bytes}"

# =========================================================
# VALIDATION
# =========================================================

fail() {
  local error_type="$1"
  local target="${2:-}"

  jq -n \
    --arg capability "filesystem.read" \
    --arg classification "readonly" \
    --arg execution_id "${AEGIS_EXECUTION_ID:-unknown}" \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg error_type "${error_type}" \
    --arg target "${target}" \
    '{
      success: false,
      capability: $capability,
      classification: $classification,
      execution_id: $execution_id,
      generated_at: $generated_at,
      payload: null,
      error: {
        type: $error_type,
        target: $target
      }
    }'
}

if [[ -z "${TARGET_FILE}" ]]; then
  fail "missing_target_file"
  exit 1
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
  fail "file_not_found" "${TARGET_FILE}"
  exit 1
fi

# =========================================================
# PAYLOAD GENERATION
# =========================================================

TMP_CONTENT_FILE="$(mktemp)"
cleanup() {
  rm -f "${TMP_CONTENT_FILE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! cat "${TARGET_FILE}" > "${TMP_CONTENT_FILE}"; then
  fail "read_failure" "${TARGET_FILE}"
  exit 1
fi

CONTENT_SIZE_BYTES="$(
  wc -c < "${TMP_CONTENT_FILE}"
)"

TRUNCATED="false"

if [[ "${CONTENT_SIZE_BYTES}" -gt "${MAX_READ_BYTES}" ]]; then
  head -c "${MAX_READ_BYTES}" "${TMP_CONTENT_FILE}" > "${TMP_CONTENT_FILE}.bounded"
  printf '\n[AEGIS][TRUNCATED]\n' >> "${TMP_CONTENT_FILE}.bounded"
  mv "${TMP_CONTENT_FILE}.bounded" "${TMP_CONTENT_FILE}"
  TRUNCATED="true"
fi

# =========================================================
# JSON EMISSION
# =========================================================

jq -n \
  --arg capability "filesystem.read" \
  --arg classification "readonly" \
  --arg execution_id "${AEGIS_EXECUTION_ID:-unknown}" \
  --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg target "${TARGET_FILE}" \
  --argjson content_size_bytes "${CONTENT_SIZE_BYTES}" \
  --argjson max_read_bytes "${MAX_READ_BYTES}" \
  --argjson truncated "${TRUNCATED}" \
  --rawfile content "${TMP_CONTENT_FILE}" \
  '{
    success: true,
    capability: $capability,
    classification: $classification,
    execution_id: $execution_id,
    generated_at: $generated_at,
    payload: {
      target: $target,
      content_size_bytes: $content_size_bytes,
      max_read_bytes: $max_read_bytes,
      truncated: $truncated,
      content: $content
    },
    error: null
  }'