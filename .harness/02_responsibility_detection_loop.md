# Responsibility Detection Loop (RDL)

## Purpose

Continuously improve the runtime's ability to mechanically classify
files by their architectural responsibility — transforming observation
from purely topological (who connects to whom) to architectural (what
role each file plays).

The RDL is a sibling to the DEL (Discovery Evolution Loop). The DEL
measures topological correctness; the RDL measures classification
correctness. Both share the same benchmark infrastructure.

## Principle

Detection is **mechanical** — deterministic signals (path segments,
file naming, extensions, content patterns) — without LLM. The
classification base is runtime-owned; the LLM may refine but not
invent.

## Taxonomy

9 responsibility classes, ordered by classification priority:

| Priority | Class | Strong signals | Confidence |
|---|---|---|---|
| 1 | `test` | `tests/` dir, `test_*`/`*_test`/`.test`/`.spec` | high |
| 2 | `config` | `.yml`/`.json`/`.env` ext, `config/` dir, tooling files | high |
| 3 | `entrypoint` | `main.py`/`index.ts`/`main.go` basename, shebang, `__main__`, `bin/` | high |
| 4 | `controller` | `controllers/`/`api/`/`routes/` dir, `_controller` suffix, route decorators | high |
| 5 | `model` | `models/`/`entities/` dir, `_model` suffix, ORM class, name `db`/`schema` | high/medium |
| 6 | `view` | `.html`/`.ejs` ext, `views/`/`templates/` dir, name `ui`/`view` | high/medium |
| 7 | `service` | `services/`/`service_*` dir, `_service` suffix, domain names | medium |
| 8 | `utility` | `lib/`/`utils/` dir, name `utils`/`core`/`common` | medium |
| 9 | `module` | fallback (no signal detected) | low |

## Output

Each file in `node_index` receives three fields:

```json
{
  "responsibility": "entrypoint",
  "responsibility_signals": ["basename:main.py"],
  "responsibility_confidence": "high"
}
```

- `responsibility` — the class (string)
- `responsibility_signals` — which detectors fired (auditability)
- `responsibility_confidence` — "high" (strong signal), "medium" (weaker signal), "low" (fallback)

## Metrics

| Metric | Description | Target |
|---|---|---|
| CLASSIFICATION_ACCURACY | % of files classified correctly | 100% |
| CLASSIFICATION_PRECISION | Per-class TP/(TP+FP) | High per class |
| CLASSIFICATION_RECALL | Per-class TP/(TP+FN) | High per class |
| SIGNAL_AUDITABILITY | % of classifications with non-empty signals | High |

## Architecture

```
extract_responsibilities.sh (mechanical signal detection)
    ↓
structural.builder (adds responsibility to node_index)
    ↓
node_index[file].responsibility → Forensics/Repair/Optimize
    ↓
scorecard_rdl.py (compares against oracle)
    ↓
scorecard_rdl.json
```

## Files

| Path | Role |
|---|---|
| `.harness/02_responsibility_detection_loop.md` | This document |
| `scripts/capabilities/filesystem/extract_responsibilities.sh` | Mechanical detector |
| `scripts/benchmark/scorecard_rdl.py` | RDL scorecard |
| `tests/golden/<scenario>/expected_responsibilities.json` | Oracle per scenario |

## Relationship to DEL

The RDL and DEL share the same benchmark runner (`run_benchmark.sh`)
and iteration storage. The DEL scorecard (`scorecard.py`) measures
topological metrics; the RDL scorecard (`scorecard_rdl.py`) measures
classification metrics. Both run against the same artifacts.
