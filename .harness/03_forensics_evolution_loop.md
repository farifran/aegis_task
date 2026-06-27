# Forensics Evolution Loop (FEL)

## Purpose

Continuously improve Forensics' ability to **interpret** runtime-exposed
structural evidence — transforming observations into evidence-backed
meaning — while staying strictly within the interpretation role.

Forensics is the "what it means" layer of the three-layer epistemic
separation:

| Layer | Mode | Role | Loop |
|---|---|---|---|
| what exists | structural.builder | mechanical topology facts | DEL |
| what to investigate | discovery | routing, attention, scope | DCL |
| what it means | forensics | evidence-backed interpretation | **FEL** |

Forensics must NOT:
- re-observe what the builder already established (degrees, bridges,
  boundaries as raw facts) — that is the builder's role;
- re-route investigation or re-select attention targets — that is
  discovery's role;
- treat epistemic handover as evidence — the handover is transient
  attention, not evidence;
- copy structural fields into its own output — the builder owns "what
  exists".

Forensics must:
- produce interpretations anchored to concrete files (`target`);
- back every interpretation with capability-payload evidence, never the
  epistemic handover file;
- emit non-empty `investigation_hypotheses` and `investigation_risks`;
- emit `repair_candidates` whose `id` is a repository-relative file path
  within routed targets, never a topology identifier.

The FEL measures alignment to this contract. It does not optimize for
self-evaluation; success is determined exclusively through contract
compliance and falsification.

---

## Principle

**The contract IS the oracle.** Forensics' output contract (in
`.skills/forensics.md`) defines what compliance means. The FEL scorecard
checks that contract mechanically against produced artifacts — no
separate human oracle is required for contract metrics.

A second, informational oracle layer (`expected_forensics.json`) declares
which files SHOULD be interpreted and which SHOULD be repair candidates,
derived from structural ground truth. This measures interpretation
accuracy (did Forensics interpret the right things?) without judging the
prose.

---

## Architecture

The FEL is a measurement infrastructure, not a mode or capability. It
sits outside the runtime execution path and operates on Forensics
artifact snapshots.

```
forensics LLM artifact (golden_forensics.json)
    ↓
scorecard_fel.py
    ├── contract metrics   (contract IS oracle, mechanical)
    ├── oracle metrics     (expected_forensics.json, informational)
    ↓
fel_scorecard.json
    ↓
diff_iterations.sh  (cross-iteration delta + regression gate)
```

Forensics is the subject of measurement, not the object of change.
The FEL measures; the operator improves Forensics (the skill / prompt /
runtime routing) based on the measurements.

---

## Canonical Interpretation Shape

Each element of `interpretations` MUST use the target-anchored shape:

```json
{
  "id": "interp_001",
  "target": "src/index.ts",
  "interpretation": "evidence-backed statement of what this node means",
  "confidence": "low|medium|high",
  "evidence_refs": ["filesystem.read:src/index.ts"]
}
```

- `target` — a repository-relative file path (anchors interpretation to
  a concrete node, enforcing evidence-backed interpretation);
- `interpretation` — what the node MEANS (risk, propagation, coupling,
  coverage gap), NOT a restatement of degrees or bridge counts;
- `evidence_refs` — runtime-exposed capability payloads only. References
  to the epistemic handover file are forbidden (handover is not evidence).

Alternative shapes (`type`/`description`, `finding`) are non-compliant.
The `target` field is what ties interpretation to evidence.

---

## Metrics

### Contract metrics (mechanical, contract IS oracle)

| # | Metric | Description | Target | Status |
|---|---|---|---|---|
| 1 | STRUCTURAL_FIELD_ABSENCE | no structural fields leaked into operational_context | 100% | ✅ Active |
| 2 | INTERPRETATION_PRESENCE | interpretations non-empty; each has canonical shape {id,target,interpretation,confidence,evidence_refs} | 100% | ✅ Active |
| 3 | EVIDENCE_LEGITIMACY | every interpretation backed by non-empty evidence_refs that cite capability payloads, never the epistemic handover | 100% | ✅ Active |
| 4 | REPAIR_CANDIDATE_VALIDITY | each repair_candidate.id is a file path (not a topology ID), within routed targets, with reason + evidence_refs | 100% | ✅ Active |
| 5 | COGNITIVE_FIELD_PRESENCE | investigation_hypotheses and investigation_risks are non-empty | 100% | ✅ Active |
| 6 | HANDOVER_ATTENTION_VALIDITY | next_attention_targets non-empty; attention_scope and attention_reason present | 100% | ✅ Active |
| 7 | OBSERVATION_NON_REDUNDANCY | Forensics does not re-observe what Discovery already investigated (no reasoning-chain fields carried; observations not near-paraphrases of Discovery's operational_observations) | 100% | ✅ Active |

### Oracle metrics (expected_forensics.json — informational)

| # | Metric | Description | Target | Status |
|---|---|---|---|---|
| 8 | INTERPRETATION_TARGET_PRECISION | interpreted files that match oracle expected targets | High | 📊 Informational |
| 9 | INTERPRETATION_TARGET_RECALL | oracle targets that Forensics interpreted | High | 📊 Informational |
| 10 | REPAIR_CANDIDATE_PRECISION | predicted candidates matching oracle expected candidates | High | 📊 Informational |
| 11 | REPAIR_CANDIDATE_RECALL | oracle candidates that Forensics nominated | High | 📊 Informational |

Oracle targets/candidates are derived from structural ground truth
(`expected_topology.json`): topology-significant files (bridge endpoints,
boundaries, hotspots, entrypoints) and structurally risky files
(uncovered hotspots/boundaries/entrypoints, isolated test files).

---

## Separation Enforcement

The FEL enforces the three-layer separation through its metrics:

| Violation | Detected by |
|---|---|
| Forensics re-observes raw topology (copies structural fields) | STRUCTURAL_FIELD_ABSENCE |
| Forensics re-states degrees/bridges instead of meaning | INTERPRETATION_PRESENCE (target + interpretation, not type/description) |
| Forensics treats handover as evidence | EVIDENCE_LEGITIMACY |
| Forensics nominates topology IDs as repair targets | REPAIR_CANDIDATE_VALIDITY |
| Forensics omits hypotheses/risks (no interpretation depth) | COGNITIVE_FIELD_PRESENCE |
| Forensics leaves next mode without routed attention | HANDOVER_ATTENTION_VALIDITY |
| Forensics re-observes what Discovery already investigated (echo / reasoning-chain fields) | OBSERVATION_NON_REDUNDANCY |

---

## Phases

### Phase 0 — Load Baseline
Load current Forensics implementation, previous FEL scorecard, previous
iteration metrics. Establish baseline. If none exists, Iteration 0.

### Phase 1 — Collect Artifact
Forensics is LLM-produced (unlike the deterministic builder). The
`golden_forensics.json` snapshots are the measured artifacts. A fresh
snapshot requires running Forensics with a valid API key against a
benchmark scenario.

### Phase 2 — Scorecard
Calculate all 6 contract metrics + 4 oracle metrics
(`scorecard_fel.py`).

### Phase 3 — Falsification
Attempt to invalidate Forensics' output:
- Can an interpretation be shown unevidenced?
- Can a repair candidate be shown outside routed targets?
- Can evidence_refs be shown to cite the handover?
Produce a FALSIFICATION_REPORT.

### Phase 4 — Root Cause Analysis
Classify every weakness:
- contract issue (skill does not declare the shape/rule)
- prompt issue (LLM not following the contract)
- runtime issue (handover promoted as evidence, routing incomplete)
- evidence issue (capability payloads not exposed to Forensics)
- oracle issue (expected_forensics.json mis-declares ground truth)

### Phase 5 — Improvement Generation
Generate candidate improvements. Each MUST:
- be mechanically testable via the FEL scorecard;
- be measurable;
- preserve constitutional constraints (runtime sovereignty, bounded
  mutation, epistemic separation);
- reduce epistemic risk.

### Phase 6 — Implementation
Apply only the smallest change required to test the hypothesis. One
experiment. One hypothesis. No bundled changes.

### Phase 7 — Re-evaluation
Re-run Forensics against benchmark scenarios, collect fresh
`golden_forensics.json`, re-run the scorecard.

### Phase 8 — Diff Analysis
Compare against baseline via `diff_iterations.sh`. Produce
IMPROVEMENTS / REGRESSIONS / UNCHANGED_AREAS.

### Phase 9 — Regression Gate
If any contract metric REGRESSES, STOP. Enter REGRESSION_ANALYSIS_MODE.
If regression remains unexplained, ROLLBACK.

### Phase 10 — Strategy Adaptation
If progress stalls for 3 iterations, change strategy:
- tighten the contract (forensics.md)
- improve evidence exposure (which payloads Forensics sees)
- improve routing (which targets Forensics receives)
- improve prompt adherence

---

## Success Conditions

Forensics is considered IDEAL only if:
- All 6 contract metrics = 100%
- Interpretation target precision/recall high
- Repair candidate precision/recall high
- No unexplained regressions
- Generalization across all repository types

---

## Files

| Path | Role |
|---|---|
| `.harness/03_forensics_evolution_loop.md` | This document (FEL spec) |
| `scripts/benchmark/scorecard_fel.py` | Phase 2 — metric calculation |
| `scripts/benchmark/diff_iterations.sh` | Phase 8 — delta analysis + regression gate (shared) |
| `tests/golden/<scenario>/golden_forensics.json` | Measured artifact (LLM-produced snapshot) |
| `tests/golden/<scenario>/expected_forensics.json` | Oracle — interpretation targets + repair candidates |
| `tests/benchmark/fel_scorecard.json` | Latest scorecard output |

## Relationship to DEL / DCL / RDL

The FEL is a sibling to the DEL, DCL, and RDL. They share the benchmark
runner and iteration storage. Together they align the three-layer
separation:

- **DEL** — builder topology correctness (what exists)
- **RDL** — responsibility classification correctness (what role each file plays)
- **DCL** — discovery contract compliance (what to investigate)
- **FEL** — forensics contract compliance (what it means)

All four measure; the operator improves based on the measurements.

## npm Integration

```bash
npm run aegis:benchmark:fel   # run FEL scorecard against golden forensics artifacts
```
