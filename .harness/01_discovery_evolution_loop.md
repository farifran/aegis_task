# Discovery Evolution Loop (DEL v1)

## Purpose

Continuously improve Discovery's ability to observe repository structure
mechanically, identify meaningful attention targets, prioritize evidence
collection, detect uncertainty correctly, generalize across repository
types, and minimize unsupported conclusions.

Discovery is NOT allowed to optimize for self-evaluation.
Success is determined exclusively through benchmark performance and
falsification.

---

## Architecture

The DEL is a measurement infrastructure, not a mode or capability.
It sits outside the runtime execution path and operates on builder
artifacts produced by the structural builder.

```
structural.builder
    ↓ (5 runs per scenario)
run_benchmark.sh
    ↓
scorecard.py
    ↓
scorecard.json
    ↓
diff_iterations.sh
    ↓
delta report (IMPROVED / REGRESSED / UNCHANGED)
```

The builder is the subject of measurement, not the object of change.
The DEL measures; the operator improves based on the measurements.

---

## Phases

### Phase 0 — Load Baseline

Load the current Discovery implementation, previous best benchmark
results, and previous iteration metrics. Establish the current baseline.

If no baseline exists, create Iteration 0.

### Phase 1 — Execute Benchmark Suite

Run the structural.builder against all benchmark scenarios:

**Training scenarios:**
- `python` — Python with imports
- `bash` — Shell with source
- `node` — TypeScript with imports

**Validation scenarios:**
- `monolith` — Rails-style monolith
- `microservice` — Go microservice (degenerate topology)

**Hidden scenarios (future):**
- External repositories
- Previously unseen repositories
- Synthetic adversarial repositories

Collect from each run:
- `topology_summary`
- `topology_index` (bridges, boundaries, hotspots, entrypoints, surfaces, node_index)
- `evidence_summary` (coverage, payload_status)
- `unresolved_references`
- `gap_counts`

Store artifacts under `tests/benchmark/iterations/iteration_N/`.

### Phase 2 — Scorecard

Calculate metrics (see Metrics section below).

### Phase 3 — Falsification

Attempt to invalidate Discovery's output:
- Can hotspot selection be shown wrong?
- Can attention targets be shown irrelevant?
- Can topology extraction be shown incomplete?

Produce a FALSIFICATION_REPORT.

### Phase 4 — Root Cause Analysis

Classify every weakness:
- Topology extraction issue
- Ranking issue
- Attention issue
- Capability issue
- Runtime issue
- Prompt issue
- Validation issue
- Benchmark issue

### Phase 5 — Improvement Generation

Generate candidate improvements. Each MUST:
- be mechanically testable
- be measurable
- preserve constitutional constraints
- preserve runtime sovereignty
- reduce epistemic risk

Reject speculative improvements.

### Phase 6 — Implementation

Apply only the smallest change required to test the hypothesis.
One experiment. One hypothesis. No bundled changes.

### Phase 7 — Re-evaluation

Run the full benchmark suite again. Collect all metrics.

### Phase 8 — Diff Analysis

Compare against baseline. Produce:
- IMPROVEMENTS
- REGRESSIONS
- UNCHANGED_AREAS

### Phase 9 — Regression Gate

If REGRESSION_COUNT > 0, STOP optimization.
Enter REGRESSION_ANALYSIS_MODE.
Determine root cause, affected metrics, severity.

If regression remains unexplained, ROLLBACK to previous best iteration.

### Phase 10 — Strategy Adaptation

If progress stalls for 3 iterations, change strategy:
- Improve topology extraction
- Improve hotspot ranking
- Improve evidence prioritization
- Improve uncertainty calibration
- Improve capability utilization
- Improve attention selection

---

## Metrics

### Deterministic metrics (computed from builder output, no LLM)

| # | Metric | Formula | Target | Status |
|---|---|---|---|---|
| 1 | STRUCTURAL_CONSISTENCY | 5 runs identical → 100% | Stable (100%) | ✅ Active |
| 2 | TOPOLOGY_COVERAGE | resolved / (resolved + unresolved) | Increasing trend | ✅ Active |
| 3 | CAPABILITY_UTILIZATION | consumed_ok / (ok + missing + failed) | High (100%) | ✅ Active |

### LLM-dependent metrics (require Discovery artifact)

| # | Metric | Description | Target | Status |
|---|---|---|---|---|
| 4 | SCOPE_ACCURACY | scope_targets ⊆ resolved_paths | 100% | ⏳ Pending |
| 5 | SIGNAL_TO_NOISE | useful observations / total output | Increasing trend | ⏳ Pending |
| 6 | UNCERTAINTY_CORRECTNESS | admits uncertainty when evidence insufficient | High | ⏳ Pending |

### Oracle-based metrics (require expected_topology.json)

| # | Metric | Description | Target | Status |
|---|---|---|---|---|
| 7 | HOTSPOT_PRECISION | selected hotspot confirmed structurally important | 90% | 📊 Informational |
| 8 | ATTENTION_YIELD | meaningful findings from selected targets | Increasing trend | 📊 Informational |
| 9 | EVIDENCE_QUALITY | required_evidence produces high-value info | High | 📊 Informational |
| 10 | INFORMATION_GAIN | new knowledge / evidence consumed | Increasing trend | 📊 Informational |
| 11 | ESCALATION_ACCURACY | stops and requests evidence appropriately | High | 📊 Informational |
| 12 | GENERALIZATION_SCORE | average score across all repositories | Increasing trend | 📊 Informational |

Oracle-based metrics currently compute precision/recall/F1 of bridges,
boundaries, hotspots, entrypoints, and surfaces against
`expected_topology.json`. These are informational — they expose the gap
between what the builder produces and what a human declares correct.

---

## Success Conditions

Discovery is considered IDEAL only if:
- Scope Accuracy = 100%
- Stable across repeated runs
- Hotspot Precision high
- Attention Yield high
- Information Gain high
- Signal-to-Noise high
- Uncertainty Correctness high
- Escalation Accuracy high
- No unexplained regressions
- Generalization Score high
- Validation scenarios pass
- Hidden scenarios pass

---

## Current Implementation Status

### Active (Phase 1-2, builder-only)

- `scripts/benchmark/run_benchmark.sh` — multi-scenario runner (5 scenarios × 5 runs)
- `scripts/benchmark/scorecard.py` — 3 deterministic metrics + oracle precision/recall (informational)
- `scripts/benchmark/diff_iterations.sh` — cross-iteration delta with regression gate
- `tests/golden/<scenario>/expected_topology.json` — human-authored oracle for 5 scenarios

### Pending (requires LLM artifact)

Metrics 4-6 (SCOPE_ACCURACY, SIGNAL_TO_NOISE, UNCERTAINTY_CORRECTNESS)
require the Discovery cognitive artifact (produced by the LLM substrate).
Activating these requires:
1. Running Discovery with a valid API key against benchmark scenarios
2. Collecting the operational_context from each run
3. Extending scorecard.py to compute cognitive metrics

### Future (requires oracle-gated scoring)

Metrics 7-12 are informational today (precision/recall computed but not
gated). Making them gated requires:
1. Oracle validation pass (confirm expected_topology.json matches human intent)
2. Threshold setting per metric
3. Regression gate integration in diff_iterations.sh

---

## Files

| Path | Role |
|---|---|
| `.harness/01_discovery_evolution_loop.md` | This document (DEL spec) |
| `scripts/benchmark/run_benchmark.sh` | Phase 1 — benchmark runner |
| `scripts/benchmark/scorecard.py` | Phase 2 — metric calculation |
| `scripts/benchmark/diff_iterations.sh` | Phase 8 — delta analysis + regression gate |
| `tests/golden/<scenario>/expected_topology.json` | Oracle — human-authored ground truth |
| `tests/benchmark/iterations/iteration_N/` | Artifact storage (run_1-5.json, scorecard.json) |

---

## npm Integration

```bash
npm run aegis:benchmark       # run benchmark + scorecard
npm run aegis:benchmark:diff  # compare latest two iterations
```
