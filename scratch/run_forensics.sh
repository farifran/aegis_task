#!/usr/bin/env bash
export AEGIS_INVESTIGATION_INPUT="adicione uma funcao quadratica"
export AEGIS_MODE="forensics"
export AEGIS_SKILL_FILE=".skills/forensics.md"
export AEGIS_SKILL_CONTRACT="$(cat "${AEGIS_SKILL_FILE}")"
export AEGIS_EPISTEMIC_HANDOVER_FILE=".harness/runtime/epistemic_handover.json"
export AEGIS_CAPABILITY_PAYLOAD_DIR=".harness/runtime/capability_payloads"
export AEGIS_CAPABILITY_ENV_DIR=".harness/runtime/capability_env"
export AEGIS_EXECUTION_SURFACE_PATH=".harness/execution_surfaces/forensics"
export AEGIS_EXECUTION_ID="12345_test"
export AEGIS_EXECUTION_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export AEGIS_CAPABILITY_MANIFEST="$(bash scripts/capabilities/generate_manifest.sh)"

mkdir -p "${AEGIS_CAPABILITY_ENV_DIR}"
mkdir -p "${AEGIS_CAPABILITY_PAYLOAD_DIR}"

bash scripts/execute_mode.sh \
  "${AEGIS_SKILL_FILE}" \
  "${AEGIS_MODE}" \
  "${AEGIS_EPISTEMIC_HANDOVER_FILE}" > /Users/rafaelfarias/.gemini/antigravity-ide/brain/267a0583-7b5a-421b-953b-2a6fc5d2926b/scratch/forensics_stdout.log 2> /Users/rafaelfarias/.gemini/antigravity-ide/brain/267a0583-7b5a-421b-953b-2a6fc5d2926b/scratch/forensics_stderr.log || true
