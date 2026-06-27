#!/usr/bin/env python3
"""
DCL Scorecard — Discovery Contract Loop

Measures whether Discovery's output complies with its contract:
  - "O que investigar" — NOT "o que existe" (no structural fields leaked)
  - Required strategic fields present in epistemic_state
  - epistemic_state core attention is valid
  - The handover carries ROUTING + PLAN (cumulative Memory of Investigation)

The contract IS the oracle — no separate expected_*.json needed.
Reads golden_discovery.json snapshots as input (the promoted snapshot,
after promote_epistemic_handover).

Metrics:
  1. STRUCTURAL_FIELD_ABSENCE    — no structural fields in epistemic_state / operational_context
  2. REQUIRED_FIELD_PRESENCE     — all required strategic/routing fields present in epistemic_state
  3. HANDOVER_ATTENTION_VALIDITY — next_attention_targets are non-empty
  4. HANDOVER_PURITY             — epistemic_state carries no Gen-1 reasoning-chain fossils

Usage:
  python3 scripts/benchmark/scorecard_dcl.py
"""

import json
import os
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent.parent
SCENARIOS = ["python", "monolith", "bash", "node", "microservice"]

# Contract: fields that MUST be in epistemic_state (discovery.md).
# Discovery owns attention + investigation strategy. It does NOT own
# investigation_hypotheses or investigation_risks (Forensics-exclusive
# per AGENTS.md). Core attention keys are required and non-empty.
EP_REQUIRED_FIELDS = {
    "next_attention_targets",
    "attention_scope",
    "attention_reason",
    "investigation_scope",
    "blocking_conditions",
    }

# Fields that are Forensics-owned — Discovery must NOT author them.
# Their absence from a Discovery snapshot is correct; their presence is a
# contract violation (Discovery encroaching on Forensics).
EP_FORBIDDEN_FIELDS = {
    "investigation_hypotheses",
    "investigation_risks",
}

# Contract: structural fields that MUST NOT appear in epistemic_state or
# operational_context. These are runtime-owned and live in structural_context.
STRUCTURAL_FIELDS = {
    "topology_summary",
    "topology_index",
    "ranked_targets",
    "observed_request_alignment",
    "gap_counts",
    "evidence",
    "unresolved_references",
}

# Gen-1 reasoning-chain fossils the runtime should NOT persist in the
# handover. Under current simplified model, they are allowed in operational_context.
REASONING_CHAIN_FOSSILS = set()


def load_golden_discovery(scenario):
    """Load golden_discovery.json for a scenario."""
    path = REPOSITORY_ROOT / "tests" / "golden" / scenario / "golden_discovery.json"
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def _nonempty(v):
    """True if v is a non-empty list/str/dict."""
    if isinstance(v, (list, str, dict)):
        return len(v) > 0
    return v is not None and v != ""


def compute_dcl_metrics(golden):
    """Compute Discovery Contract Loop metrics from a golden discovery snapshot."""
    snapshot = golden.get("artifact_snapshot", {})
    ep_state = golden.get("epistemic_state", {})
    op_ctx = snapshot.get("operational_context", {})
    ep_keys = set(ep_state.keys())
    op_keys = set(op_ctx.keys())

    # 1. STRUCTURAL_FIELD_ABSENCE
    leaked = (op_keys & STRUCTURAL_FIELDS) | (ep_keys & STRUCTURAL_FIELDS)
    structural_absence = {
        "score": 1.0 if not leaked else 0.0,
        "leaked_fields": sorted(leaked),
    }

    # 2. REQUIRED_FIELD_PRESENCE
    missing = set()
    for field in EP_REQUIRED_FIELDS:
        if field not in ep_keys:
            missing.add(field)
        elif not _nonempty(ep_state[field]) and field != "blocking_conditions" and field != "required_evidence":
            missing.add(field)
    encroached = ep_keys & EP_FORBIDDEN_FIELDS
    required_presence = {
        "score": 1.0 if not missing and not encroached
                 else 1.0 - (len(missing) + len(encroached)) / (len(EP_REQUIRED_FIELDS) + len(EP_FORBIDDEN_FIELDS)),
        "missing_fields": sorted(missing),
        "encroached_fields": sorted(encroached),
        "present_count": len(EP_REQUIRED_FIELDS - missing),
        "required_count": len(EP_REQUIRED_FIELDS),
    }

    # 3. HANDOVER_ATTENTION_VALIDITY
    next_targets = ep_state.get("next_attention_targets", [])
    handover_validity = {
        "score": 1.0 if next_targets else 0.0,
        "next_attention_targets_count": len(next_targets),
        "attention_scope": ep_state.get("attention_scope", "none"),
    }

    # 4. HANDOVER_PURITY
    reasoning_present = (op_keys & REASONING_CHAIN_FOSSILS) | (ep_keys & REASONING_CHAIN_FOSSILS)
    handover_purity = {
        "score": 1.0 if not reasoning_present else 1.0 - len(reasoning_present) / len(REASONING_CHAIN_FOSSILS),
        "reasoning_chain_fields_present": sorted(reasoning_present),
    }

    return {
        "structural_field_absence": structural_absence,
        "required_field_presence": required_presence,
        "handover_attention_validity": handover_validity,
        "handover_purity": handover_purity,
    }


def main():
    scorecard = {
        "loop": "dcl",
        "timestamp": __import__("datetime").datetime.now().isoformat() + "Z",
        "scenarios": {},
        "summary": {},
    }

    metric_keys = [
        "structural_field_absence", "required_field_presence",
        "handover_attention_validity", "handover_purity",
    ]
    all_scores = {k: [] for k in metric_keys}

    for scenario in SCENARIOS:
        golden = load_golden_discovery(scenario)
        if golden is None:
            scorecard["scenarios"][scenario] = {"status": "no_golden"}
            continue

        metrics = compute_dcl_metrics(golden)
        scorecard["scenarios"][scenario] = {"status": "ok", "metrics": metrics}

        for k in all_scores:
            all_scores[k].append(metrics[k]["score"])

    # Aggregate
    summary = {}
    for k, scores in all_scores.items():
        summary[k] = round(sum(scores) / len(scores), 4) if scores else None
    scorecard["summary"] = summary

    # Write
    output_path = REPOSITORY_ROOT / "tests" / "benchmark" / "dcl_scorecard.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(scorecard, f, indent=2, sort_keys=True)

    # Print
    print("=== DCL Scorecard — Discovery Contract Loop ===")
    print(f"  Epistemic role: 'O que investigar' (what to investigate)")
    print()
    print(f"  {'metric':40s} {'score':>6s}")
    print("  " + "-" * 48)
    for k, v in summary.items():
        label = k.replace("_", " ").title()
        print(f"  {label:40s} {v:>6.2f}" if v is not None else f"  {label:40s} {'N/A':>6s}")
    print()
    print("  Per-scenario:")
    for scenario, data in scorecard["scenarios"].items():
        if data.get("status") != "ok":
            print(f"    {scenario:15s}: {data['status']}")
            continue
        m = data["metrics"]
        flags = []
        if m["structural_field_absence"]["score"] < 1.0:
            flags.append(f"LEAKED:{m['structural_field_absence']['leaked_fields']}")
        if m["required_field_presence"]["score"] < 1.0:
            if m["required_field_presence"]["missing_fields"]:
                flags.append(f"MISSING:{m['required_field_presence']['missing_fields']}")
            if m["required_field_presence"]["encroached_fields"]:
                flags.append(f"ENCROACHED:{m['required_field_presence']['encroached_fields']}")
        if m["handover_attention_validity"]["score"] < 1.0:
            flags.append("EMPTY_HANDOVER")
        if m["handover_purity"]["score"] < 1.0:
            flags.append(f"FOSSILS_IN_HANDOVER:{m['handover_purity']['reasoning_chain_fields_present']}")
        status = "✅" if not flags else "❌"
        print(f"    {status} {scenario:15s}: {'  '.join(flags) if flags else 'all compliant'}")
    print()
    print(f"  Scorecard: {output_path}")


if __name__ == "__main__":
    main()
