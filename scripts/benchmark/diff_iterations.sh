#!/usr/bin/env bash
set -euo pipefail

# DEL Phase 8 — Diff Analysis
#
# Compares scorecard.json between two iterations.
# Reports metric deltas as IMPROVED / REGRESSED / UNCHANGED.
# Exit code 1 if any regression detected.
#
# Usage:
#   bash scripts/benchmark/diff_iterations.sh                    # compare latest two iterations
#   bash scripts/benchmark/diff_iterations.sh 2 1                 # compare iteration 2 vs 1
#   bash scripts/benchmark/diff_iterations.sh --current 2         # compare 2 vs 1 (explicit)

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPOSITORY_ROOT}"

ITERATIONS_DIR="tests/benchmark/iterations"

# Resolve iteration numbers
if [[ $# -eq 2 ]]; then
  CURRENT="$1"
  PREVIOUS="$2"
elif [[ $# -eq 0 ]]; then
  # Auto-detect latest two iterations
  IFS=$'\n' read -r -d '' -a ALL_ITERATIONS < <(ls -1 "${ITERATIONS_DIR}" 2>/dev/null | sort -t_ -k2 -n; echo "")
  if [[ ${#ALL_ITERATIONS[@]} -lt 2 ]]; then
    echo "Not enough iterations to compare (need at least 2, found ${#ALL_ITERATIONS[@]})"
    if [[ ${#ALL_ITERATIONS[@]} -eq 1 ]]; then
      echo "Only iteration: ${ALL_ITERATIONS[0]}"
      echo "Run another benchmark iteration to enable comparison."
    fi
    exit 0
  fi
  CURRENT_ITER="${ALL_ITERATIONS[-1]#iteration_}"
  PREVIOUS_ITER="${ALL_ITERATIONS[-2]#iteration_}"
  CURRENT="${CURRENT_ITER}"
  PREVIOUS="${PREVIOUS_ITER}"
else
  echo "Usage: $0 [current_iteration] [previous_iteration]" >&2
  exit 1
fi

CURRENT_FILE="${ITERATIONS_DIR}/iteration_${CURRENT}/scorecard.json"
PREVIOUS_FILE="${ITERATIONS_DIR}/iteration_${PREVIOUS}/scorecard.json"

if [[ ! -f "${CURRENT_FILE}" ]]; then
  echo "ERROR: current iteration scorecard not found: ${CURRENT_FILE}" >&2
  exit 1
fi
if [[ ! -f "${PREVIOUS_FILE}" ]]; then
  echo "ERROR: previous iteration scorecard not found: ${PREVIOUS_FILE}" >&2
  exit 1
fi

echo "=== DEL Diff Analysis — Iteration ${CURRENT} vs ${PREVIOUS} ==="
echo ""

# Use Python for the comparison (jq is awkward for delta logic)
python3 - "$CURRENT_FILE" "$PREVIOUS_FILE" "$CURRENT" "$PREVIOUS" <<'PY'
import json
import sys

current_path = sys.argv[1]
previous_path = sys.argv[2]
current_iter = sys.argv[3]
previous_iter = sys.argv[4]

with open(current_path) as f:
    current = json.load(f)
with open(previous_path) as f:
    previous = json.load(f)

cur_summary = current.get("summary", {})
prev_summary = previous.get("summary", {})

# Metrics to compare (numeric summary metrics)
# Format: (metric_name, target_value_or_None, lower_is_better_bool)
METRICS = [
    ("structural_consistency", 1.0, False),    # target: 100%
    ("topology_coverage", None, False),         # target: increasing trend
    ("capability_utilization", 1.0, False),     # target: high (100%)
    ("scope_accuracy", 1.0, False),             # target: 100%
    ("signal_to_noise", None, True),            # target: decreasing (lower = better focus)
    ("uncertainty_correctness", 1.0, False),    # target: 100% alignment
]

regressions = 0
improvements = 0
unchanged = 0

print(f"{'metric':30s} {'previous':>10s} {'current':>10s} {'delta':>10s} {'status':>12s}")
print("-" * 76)

for metric, target, lower_better in METRICS:
    cur_val = cur_summary.get(metric)
    prev_val = prev_summary.get(metric)

    if cur_val is None or prev_val is None:
        print(f"  {metric:28s} {'N/A':>10s} {'N/A':>10s} {'N/A':>10s} {'MISSING':>12s}")
        continue

    delta = cur_val - prev_val
    if abs(delta) < 0.0001:
        status = "UNCHANGED"
        unchanged += 1
    elif (delta > 0 and not lower_better) or (delta < 0 and lower_better):
        status = "IMPROVED"
        improvements += 1
    else:
        status = "REGRESSED"
        regressions += 1

    print(f"  {metric:28s} {prev_val:>10.4f} {cur_val:>10.4f} {delta:>+10.4f} {status:>12s}")

# Oracle F1 comparison
print()
print("Oracle F1 deltas:")
oracle_cur = cur_summary.get("oracle_f1_average", {})
oracle_prev = prev_summary.get("oracle_f1_average", {})

for key in ["bridges", "boundaries", "hotspots", "entrypoints", "surfaces"]:
    cur_f1 = oracle_cur.get(key)
    prev_f1 = oracle_prev.get(key)
    if cur_f1 is None or prev_f1 is None:
        print(f"  {key:15s}: {'N/A':>8s} → {'N/A':>8s}")
        continue
    delta = cur_f1 - prev_f1
    if abs(delta) < 0.0001:
        status = "UNCHANGED"
    elif delta > 0:
        status = "IMPROVED"
        improvements += 1
    else:
        status = "REGRESSED"
        regressions += 1
    print(f"  {key:15s}: {prev_f1:>8.4f} → {cur_f1:>8.4f} ({status})")

# Per-scenario comparison
print()
print("Per-scenario metric deltas:")
cur_scenarios = current.get("scenarios", {})
prev_scenarios = previous.get("scenarios", {})

for scenario in sorted(set(list(cur_scenarios.keys()) + list(prev_scenarios.keys()))):
    cur_s = cur_scenarios.get(scenario, {})
    prev_s = prev_scenarios.get(scenario, {})

    if cur_s.get("status") != "ok" or prev_s.get("status") != "ok":
        print(f"  {scenario}: status changed {prev_s.get('status','?')} → {cur_s.get('status','?')}")
        continue

    cur_m = cur_s.get("metrics", {})
    prev_m = prev_s.get("metrics", {})

    deltas = []
    for metric in ["structural_consistency", "topology_coverage", "capability_utilization"]:
        c = cur_m.get(metric, {}).get("score")
        p = prev_m.get(metric, {}).get("score")
        if c is not None and p is not None:
            d = c - p
            if abs(d) > 0.0001:
                deltas.append(f"{metric}:{'+' if d > 0 else ''}{d:.4f}")

    if deltas:
        print(f"  {scenario}: {', '.join(deltas)}")
    else:
        print(f"  {scenario}: all metrics unchanged")

# Summary
print()
print("=" * 76)
print(f"Improvements: {improvements}")
print(f"Regressions:  {regressions}")
print(f"Unchanged:    {unchanged}")

if regressions > 0:
    print()
    print("⚠ REGRESSION DETECTED — review before proceeding")
    sys.exit(1)
else:
    print()
    print("✓ No regressions detected")
    sys.exit(0)
PY
