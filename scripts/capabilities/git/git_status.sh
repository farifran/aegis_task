#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXECUTION_ID="${AEGIS_EXECUTION_ID:-unknown}"

readonly GENERATED_AT="$(
  date -u +"%Y-%m-%dT%H:%M:%SZ"
)"

fail() {
  local error_type="$1"
  local target="${2:-.}"

  jq -n \
    --arg capability "git.status" \
    --arg classification "readonly" \
    --arg execution_id "${EXECUTION_ID}" \
    --arg generated_at "${GENERATED_AT}" \
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

if ! STATUS_OUTPUT="$(
  git status --short
)"; then
  fail "git_status_failed"
  exit 1
fi

jq -n \
  --arg capability "git.status" \
  --arg classification "readonly" \
  --arg execution_id "${EXECUTION_ID}" \
  --arg generated_at "${GENERATED_AT}" \
  --arg status "${STATUS_OUTPUT}" \
  '{
    success: true,
    capability: $capability,
    classification: $classification,
    execution_id: $execution_id,
    generated_at: $generated_at,
    payload: {
      status: $status
    },
    error: null
  }'