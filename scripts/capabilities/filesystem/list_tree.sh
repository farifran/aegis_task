#!/usr/bin/env bash

# =========================================================
# AEGIS CAPABILITY — filesystem.list_tree
# =========================================================
#
# Classification:
# readonly
#
# Responsibilities:
#
# - bounded filesystem topology inspection
# - deterministic tree generation
# - capability evidence generation
# - payload provenance emission
#
# This capability intentionally:
#
# - exposes observable repository structure;
# - avoids implicit repository inheritance;
# - emits deterministic JSON payloads;
# - propagates execution identity;
# - prunes high-noise directories.
#
# =========================================================

set -Eeuo pipefail

# =========================================================
# INPUTS
# =========================================================

readonly TARGET_PATH="${1:-.}"
readonly MAX_DEPTH="${AEGIS_LIST_TREE_MAX_DEPTH:-4}"

# =========================================================
# CONFIGURATION
# =========================================================

[[ -f ".harness/config.sh" ]] || {
  echo "[AEGIS][CAPABILITY][FATAL] missing_config" >&2
  exit 1
}

# shellcheck disable=SC1091
source ".harness/config.sh"

# =========================================================
# HELPERS
# =========================================================

fail() {
  local error_type="$1"
  local target="${2:-}"

  jq -n \
    --arg capability "filesystem.list_tree" \
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

build_prune_expression() {
  local expr=()
  local prune_path

  for prune_path in "${AEGIS_FILESYSTEM_PRUNE_PATHS[@]}"; do
    case "${prune_path}" in
      node_modules)
        expr+=( -path "*/node_modules" )
        ;;
      .git)
        expr+=( -path "*/.git" )
        ;;
      .harness/execution_surfaces)
        expr+=( -path "*/.harness/execution_surfaces" )
        ;;
      .harness/runtime)
        expr+=( -path "*/.harness/runtime" )
        ;;
      *)
        expr+=( -path "*/${prune_path}" )
        ;;
    esac

    expr+=( -o )
  done

  # Remove trailing -o
  unset 'expr[${#expr[@]}-1]'

  printf '%s\0' "${expr[@]}"
}

# =========================================================
# VALIDATION
# =========================================================

if [[ ! -d "${TARGET_PATH}" ]]; then
  fail "missing_directory" "${TARGET_PATH}"
  exit 1
fi

declare -p AEGIS_FILESYSTEM_PRUNE_PATHS >/dev/null 2>&1 || {
  fail "missing_prune_policy"
  exit 1
}

# =========================================================
# TREE GENERATION
# =========================================================

TMP_TREE_FILE="$(
  mktemp
)"

cleanup() {
  rm -f "${TMP_TREE_FILE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The prune expression is sourced from config and applied before output.
# We keep -maxdepth before the expression to avoid GNU find warnings.
mapfile -d '' PRUNE_EXPR < <(build_prune_expression)

# Use a grouped prune expression to avoid descending into noisy directories.
# The tree output remains deterministic via sorting.
find "${TARGET_PATH}" \
  -maxdepth "${MAX_DEPTH}" \
  \( "${PRUNE_EXPR[@]}" \) \
  -prune \
  -o \
  -print \
  | sort \
  > "${TMP_TREE_FILE}"

# Remove the root prefix noise if present; keep "." as the root entry.
# (No additional normalization is done to preserve determinism.)

# =========================================================
# JSON EMISSION
# =========================================================

jq -n \
  --arg capability "filesystem.list_tree" \
  --arg classification "readonly" \
  --arg execution_id "${AEGIS_EXECUTION_ID:-unknown}" \
  --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg target "${TARGET_PATH}" \
  --argjson max_depth "${MAX_DEPTH}" \
  --rawfile tree "${TMP_TREE_FILE}" \
  '{
    success: true,
    capability: $capability,
    classification: $classification,
    execution_id: $execution_id,
    generated_at: $generated_at,
    payload: {
      target: $target,
      max_depth: $max_depth,
      tree: $tree
    },
    error: null
  }'