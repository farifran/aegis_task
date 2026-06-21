#!/usr/bin/env bash
set -euo pipefail

# DEL Phase 1 — Benchmark Runner
#
# Runs the structural.builder against all benchmark scenarios, 5 runs each
# (for STRUCTURAL_CONSISTENCY metric). Does NOT invoke the LLM — the builder
# is deterministic and needs no API key.
#
# Artifacts are stored under:
#   tests/benchmark/iterations/iteration_N/<scenario>/run_{1-5}.json
#
# Usage:
#   bash scripts/benchmark/run_benchmark.sh              # auto-increment iteration
#   bash scripts/benchmark/run_benchmark.sh --iteration 3  # explicit iteration number

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPOSITORY_ROOT}"

# shellcheck source=/dev/null
source ".harness/config.sh"

SCENARIOS=("python" "monolith" "bash" "node" "microservice" "cycle" "hub" "multi_surface")
RUNS_PER_SCENARIO=5

ITERATION_NUMBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iteration)
      ITERATION_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Auto-increment iteration if not specified
if [[ -z "${ITERATION_NUMBER}" ]]; then
  ITERATIONS_DIR="tests/benchmark/iterations"
  EXISTING=()
  if [[ -d "${ITERATIONS_DIR}" ]]; then
    for d in "${ITERATIONS_DIR}"/iteration_*; do
      [[ -d "${d}" ]] && EXISTING+=("${d}")
    done
  fi
  NEXT_NUM=$(( ${#EXISTING[@]} + 1 ))
  ITERATION_NUMBER="${NEXT_NUM}"
fi

ITERATION_DIR="tests/benchmark/iterations/iteration_${ITERATION_NUMBER}"

echo "=== DEL Benchmark Runner — Iteration ${ITERATION_NUMBER} ==="
echo "Output: ${ITERATION_DIR}/"
echo ""

mkdir -p "${ITERATION_DIR}"

FAILURES=0

for scenario in "${SCENARIOS[@]}"; do
  SCENARIO_DIR="${ITERATION_DIR}/${scenario}"
  mkdir -p "${SCENARIO_DIR}"

  SCENARIO_INPUT="tests/scenarios/${scenario}/input"

  echo "  [${scenario}] running builder ${RUNS_PER_SCENARIO}x..."

  for run in $(seq 1 "${RUNS_PER_SCENARIO}"); do
    RUN_FILE="${SCENARIO_DIR}/run_${run}.json"

    # Prepare a clean payload directory for this run
    PAYLOAD_DIR="${AEGIS_CAPABILITY_PAYLOAD_DIR:-.harness/runtime/capability_payloads}"
    mkdir -p "${PAYLOAD_DIR}"
    find "${PAYLOAD_DIR}" -type f -delete 2>/dev/null || true

    # Run extractors first (builder depends on them, but can self-materialize;
    # running them explicitly ensures consistent dependency state)
    export AEGIS_EXECUTION_ID="bench_${scenario}_run${run}"
    export AEGIS_INVESTIGATION_INPUT="analyze repository topology"

    for cap in extract_import_graph extract_reference_graph extract_symbols extract_entrypoints extract_test_relationships extract_configuration_structure; do
      bash "scripts/capabilities/filesystem/${cap}.sh" "${SCENARIO_INPUT}" \
        > "${PAYLOAD_DIR}/filesystem_${cap}.json" 2>/dev/null || true
    done

    # Run the builder — write to both the run file (for benchmark artifacts)
    # and the payload dir (for attention_seed to consume)
    if bash "scripts/capabilities/structural/builder.sh" "${SCENARIO_INPUT}" \
        > "${RUN_FILE}" 2>/dev/null; then
      # Copy builder output to payload dir so attention_seed can read it
      cp "${RUN_FILE}" "${PAYLOAD_DIR}/structural_builder.json"

      # Run attention_seed (deterministic, no LLM) — produces the
      # scope_targets / scope_confidence / attention_targets that
      # Discovery would copy verbatim. Captured for LLM-equivalent metrics.
      SEED_FILE="${SCENARIO_DIR}/run_${run}_seed.json"
      bash "scripts/capabilities/runtime/attention_seed.sh" "${SCENARIO_INPUT}" \
        > "${SEED_FILE}" 2>/dev/null || true
    else
      echo "    [FAIL] run ${run}: builder exited non-zero"
      FAILURES=$(( FAILURES + 1 ))
    fi
  done

  echo "    [OK] ${RUNS_PER_SCENARIO} runs stored"
done

echo ""
echo "=== Benchmark complete ==="
echo "  Iteration: ${ITERATION_NUMBER}"
echo "  Scenarios: ${#SCENARIOS[@]}"
echo "  Runs per scenario: ${RUNS_PER_SCENARIO}"
echo "  Total runs: $(( ${#SCENARIOS[@]} * RUNS_PER_SCENARIO ))"
echo "  Failures: ${FAILURES}"
echo ""
echo "Artifacts at: ${ITERATION_DIR}/"
echo "Next: python3 scripts/benchmark/scorecard.py --iteration ${ITERATION_NUMBER}"

# Clean up payload directory
find "${PAYLOAD_DIR}" -type f -delete 2>/dev/null || true

exit 0
