#!/usr/bin/env python3
"""
DEL Phase 2 — Scorecard

Reads builder artifacts produced by run_benchmark.sh and calculates metrics.

3 deterministic metrics (from builder output, no LLM needed):
  1. STRUCTURAL_CONSISTENCY — are 5 runs of the builder identical?
  2. TOPOLOGY_COVERAGE      — resolved_edges / (resolved + unresolved)
  3. CAPABILITY_UTILIZATION — consumed_ok / (consumed_ok + missing + failed)

3 pending metrics (require LLM artifact, marked as pending):
  4. SCOPE_ACCURACY
  5. SIGNAL_TO_NOISE
  6. UNCERTAINTY_CORRECTNESS

Also computes oracle-based accuracy metrics (precision/recall of bridges,
boundaries, hotspots, entrypoints against expected_topology.json) as
informational — these are not gated yet but provide signal for future
iterations.

Output: tests/benchmark/iterations/iteration_N/scorecard.json

Usage:
  python3 scripts/benchmark/scorecard.py --iteration 1
"""

import argparse
import json
import os
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent.parent
SCENARIOS = ["python", "monolith", "bash", "node", "microservice", "cycle", "hub", "multi_surface"]
RUNS_PER_SCENARIO = 5


def load_builder_payload(path):
    """Load a structural_builder.json and return its .payload, or None."""
    try:
        with open(path) as f:
            data = json.load(f)
        return data.get("payload")
    except (json.JSONDecodeError, FileNotFoundError, KeyError):
        return None


def load_seed_payload(path):
    """Load a run_N_seed.json (attention_seed output) and return its .payload, or None."""
    try:
        with open(path) as f:
            data = json.load(f)
        return data.get("payload")
    except (json.JSONDecodeError, FileNotFoundError, KeyError):
        return None


def extract_topology_sets(payload):
    """Extract sets of bridges, boundaries, hotspots, entrypoints from a builder payload."""
    ti = payload.get("topology_index", {})

    # Bridges are treated as undirected pairs for oracle comparison:
    # the structural fact is "these two files are connected by a bridge",
    # not "the import direction is X". Direction is builder metadata.
    bridges = set()
    for b in ti.get("bridges", []):
        f, t = b.get("from", ""), b.get("to", "")
        bridges.add(frozenset((f, t)))

    boundaries = set()
    for b in ti.get("boundaries", []):
        boundaries.add(b.get("file", ""))

    hotspots = set()
    for h in ti.get("hotspots", []):
        hotspots.add(h.get("file", ""))

    entrypoints = set()
    for e in ti.get("entrypoints", []):
        entrypoints.add(e.get("file", ""))

    surfaces = set()
    for s in ti.get("surfaces", []):
        # Skip standalone summary surfaces — they are statistical
        # aggregations of isolated nodes, not real structural surfaces.
        # They have surface_kind="standalone" and typically empty members.
        if s.get("surface_kind") == "standalone":
            continue
        members = frozenset(s.get("members", []))
        # Skip surfaces with no actual members (empty summary)
        if not members:
            continue
        surfaces.add(members)

    return {
        "bridges": bridges,
        "boundaries": boundaries,
        "hotspots": hotspots,
        "entrypoints": entrypoints,
        "surfaces": surfaces,
    }


def load_oracle(scenario):
    """Load expected_topology.json for a scenario."""
    oracle_path = REPOSITORY_ROOT / "tests" / "golden" / scenario / "expected_topology.json"
    if not oracle_path.exists():
        return None
    with open(oracle_path) as f:
        return json.load(f)


def oracle_to_sets(oracle):
    """Convert oracle JSON to comparable sets."""
    # Bridges as undirected frozenset pairs (matching builder comparison)
    bridges = set()
    for b in oracle.get("expected_bridges", []):
        bridges.add(frozenset((b["from"], b["to"])))

    boundaries = set(b["file"] for b in oracle.get("expected_boundaries", []))
    hotspots = set(h["file"] for h in oracle.get("expected_hotspots", []))
    entrypoints = set(e["file"] for e in oracle.get("expected_entrypoints", []))

    surfaces = set()
    for s in oracle.get("expected_surfaces", []):
        surfaces.add(frozenset(s["members"]))

    return {
        "bridges": bridges,
        "boundaries": boundaries,
        "hotspots": hotspots,
        "entrypoints": entrypoints,
        "surfaces": surfaces,
    }


def precision_recall(predicted, expected):
    """Compute precision, recall, F1 for two sets."""
    if len(expected) == 0 and len(predicted) == 0:
        return {"precision": 1.0, "recall": 1.0, "f1": 1.0,
                "true_positives": 0, "false_positives": 0, "false_negatives": 0}
    if len(expected) == 0:
        return {"precision": 0.0, "recall": 1.0, "f1": 0.0,
                "true_positives": 0, "false_positives": len(predicted), "false_negatives": 0}
    if len(predicted) == 0:
        return {"precision": 1.0, "recall": 0.0, "f1": 0.0,
                "true_positives": 0, "false_positives": 0, "false_negatives": len(expected)}

    tp = len(predicted & expected)
    fp = len(predicted - expected)
    fn = len(expected - predicted)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    return {"precision": round(precision, 4), "recall": round(recall, 4), "f1": round(f1, 4),
            "true_positives": tp, "false_positives": fp, "false_negatives": fn}


def compute_structural_consistency(runs):
    """Metric 1: Are all runs structurally identical?"""
    if len(runs) < 2:
        return {"score": 1.0, "consistent": True, "runs_compared": len(runs)}

    baseline = extract_topology_sets(runs[0])
    for run in runs[1:]:
        current = extract_topology_sets(run)
        if current != baseline:
            return {"score": 0.0, "consistent": False, "runs_compared": len(runs),
                    "divergence": "topology_index differs between runs"}

    return {"score": 1.0, "consistent": True, "runs_compared": len(runs)}


def compute_topology_coverage(payload):
    """Metric 2: resolved_edges / (resolved + unresolved)."""
    ts = payload.get("topology_summary", {})
    resolved = ts.get("resolved_edge_count", 0)
    unresolved = ts.get("unresolved_edge_count", 0)
    total = resolved + unresolved
    if total == 0:
        ratio = 1.0  # No edges at all — vacuously full coverage
    else:
        ratio = resolved / total
    return {
        "score": round(ratio, 4),
        "resolved_edge_count": resolved,
        "unresolved_edge_count": unresolved,
        "total_edges": total
    }


def compute_capability_utilization(payload):
    """Metric 3: consumed_ok / (consumed_ok + missing + failed)."""
    evidence = payload.get("evidence", {})
    # payload_status is a sibling of coverage under evidence, not nested inside it.
    payload_status = evidence.get("payload_status", {})
    ok = payload_status.get("consumed_payload_ok_count", 0)
    # Support both naming conventions for robustness.
    missing = payload_status.get("consumed_payload_missing_count",
                                 payload_status.get("missing_payload_count", 0))
    failed = payload_status.get("consumed_payload_failed_count",
                                payload_status.get("failed_payload_count", 0))
    total = ok + missing + failed
    if total == 0:
        ratio = 0.0
    else:
        ratio = ok / total
    return {
        "score": round(ratio, 4),
        "consumed_ok": ok,
        "missing": missing,
        "failed": failed
    }


def compute_oracle_accuracy(payload, oracle_sets):
    """Compute precision/recall against oracle for each topology type."""
    predicted = extract_topology_sets(payload)
    return {
        "bridges": precision_recall(predicted["bridges"], oracle_sets["bridges"]),
        "boundaries": precision_recall(predicted["boundaries"], oracle_sets["boundaries"]),
        "hotspots": precision_recall(predicted["hotspots"], oracle_sets["hotspots"]),
        "entrypoints": precision_recall(predicted["entrypoints"], oracle_sets["entrypoints"]),
        "surfaces": precision_recall(predicted["surfaces"], oracle_sets["surfaces"]),
    }


def compute_scope_accuracy(builder_payload, seed_payload):
    """Metric 4: SCOPE_ACCURACY — scope_targets ⊆ (resolved_paths ∪ topology_files).

    All attention targets selected by the seed must be files that exist
    in the structural graph — either as explicitly resolved paths or
    as topology-derived files (bridge endpoints, boundaries, hotspots,
    entrypoints, surface members). A target outside this set means the
    seed selected something the builder never observed.
    """
    if seed_payload is None:
        return {"status": "no_seed"}

    scope_targets = set(seed_payload.get("investigation_scope", {}).get("scope_targets", []))
    if not scope_targets:
        return {"score": 1.0, "scope_targets": [], "in_scope": True,
                "note": "empty scope_targets — vacuously in scope"}

    # Build the universe of valid files from the builder
    valid_files = set()

    # resolved_paths from observed_request_alignment
    ora = builder_payload.get("observed_request_alignment", {})
    valid_files.update(ora.get("resolved_paths", []))

    # topology_files from topology_index
    ti = builder_payload.get("topology_index", {})
    for b in ti.get("bridges", []):
        valid_files.add(b.get("from", ""))
        valid_files.add(b.get("to", ""))
    for b in ti.get("boundaries", []):
        valid_files.add(b.get("file", ""))
    for h in ti.get("hotspots", []):
        valid_files.add(h.get("file", ""))
    for e in ti.get("entrypoints", []):
        valid_files.add(e.get("file", ""))
    for s in ti.get("surfaces", []):
        valid_files.update(s.get("members", []))

    # node_index keys are all known files
    valid_files.update(ti.get("node_index", {}).keys())

    out_of_scope = scope_targets - valid_files
    in_scope = len(out_of_scope) == 0
    score = 1.0 if in_scope else len(scope_targets & valid_files) / len(scope_targets)

    return {
        "score": round(score, 4),
        "scope_targets": sorted(scope_targets),
        "out_of_scope": sorted(out_of_scope),
        "in_scope": in_scope
    }


def compute_signal_to_noise(builder_payload, seed_payload):
    """Metric 5: SIGNAL_TO_NOISE — attention_targets / ranked_targets.

    Ratio of targets the seed actually selected for attention vs the
    total number of ranked targets the builder produced. Lower is
    better (tighter focus): the seed selected few targets from many
    candidates. Higher means diffusion (selected almost everything).

    Reported as a ratio where lower = better focus. The scorecard
    tracks the trend: decreasing is improvement.
    """
    if seed_payload is None:
        return {"status": "no_seed"}

    attention_targets = seed_payload.get("attention_targets", [])
    # Also include scope_targets as they represent the full attention set
    scope_targets = seed_payload.get("investigation_scope", {}).get("scope_targets", [])
    selected = set(attention_targets) | set(scope_targets)

    ranked_targets = builder_payload.get("ranked_targets", [])
    ranked_count = len(ranked_targets)

    if ranked_count == 0:
        return {"score": 0.0, "selected_count": len(selected),
                "ranked_count": 0, "note": "no ranked targets — ratio undefined"}

    ratio = len(selected) / ranked_count
    return {
        "score": round(ratio, 4),
        "selected_count": len(selected),
        "ranked_count": ranked_count
    }


def compute_uncertainty_correctness(builder_payload, seed_payload):
    """Metric 6: UNCERTAINTY_CORRECTNESS — scope_confidence vs unresolved_references.

    The seed must report lower confidence when the topology has
    unresolved references (evidence gaps). Alignment is correct when:
      - unresolved_references non-empty → confidence is "low" or "medium"
      - unresolved_references empty → confidence can be "high"

    Returns 1.0 for correct alignment, 0.0 for incorrect.
    """
    if seed_payload is None:
        return {"status": "no_seed"}

    scope_confidence = seed_payload.get("investigation_scope", {}).get("scope_confidence", "none")
    unresolved_refs = builder_payload.get("unresolved_references", [])
    has_unresolved = len(unresolved_refs) > 0

    if has_unresolved:
        # Should NOT be "high" when there are unresolved references
        correct = scope_confidence != "high"
        expected = "low or medium"
    else:
        # Can be "high" when no unresolved references (but "medium"/"low" is also acceptable)
        correct = True
        expected = "any"

    return {
        "score": 1.0 if correct else 0.0,
        "scope_confidence": scope_confidence,
        "unresolved_reference_count": len(unresolved_refs),
        "has_unresolved": has_unresolved,
        "expected_confidence": expected,
        "aligned": correct
    }


PENDING_METRICS = {
    "scope_accuracy": {
        "status": "active",
        "description": "scope_targets ⊆ (resolved_paths ∪ topology_files) — all attention targets exist in the structural graph"
    },
    "signal_to_noise": {
        "status": "active",
        "description": "selected_targets / ranked_targets — lower is better (tighter focus)"
    },
    "uncertainty_correctness": {
        "status": "active",
        "description": "scope_confidence aligned with unresolved_references presence"
    },
}


def main():
    parser = argparse.ArgumentParser(description="DEL Scorecard")
    parser.add_argument("--iteration", required=True, help="Iteration number")
    args = parser.parse_args()

    iteration_dir = REPOSITORY_ROOT / "tests" / "benchmark" / "iterations" / f"iteration_{args.iteration}"

    if not iteration_dir.exists():
        print(f"ERROR: iteration directory not found: {iteration_dir}", file=sys.stderr)
        sys.exit(1)

    scorecard = {
        "iteration": int(args.iteration),
        "timestamp": __import__("datetime").datetime.now().isoformat() + "Z",
        "scenarios": {},
        "summary": {},
        "pending_metrics": dict(PENDING_METRICS),
    }

    for scenario in SCENARIOS:
        scenario_dir = iteration_dir / scenario
        if not scenario_dir.exists():
            scorecard["scenarios"][scenario] = {"status": "missing"}
            continue

        # Load all runs
        runs = []
        seeds = []
        for run_num in range(1, RUNS_PER_SCENARIO + 1):
            run_file = scenario_dir / f"run_{run_num}.json"
            payload = load_builder_payload(run_file)
            if payload is None:
                continue
            runs.append(payload)

            seed_file = scenario_dir / f"run_{run_num}_seed.json"
            seed_payload = load_seed_payload(seed_file)
            seeds.append(seed_payload)

        if not runs:
            scorecard["scenarios"][scenario] = {"status": "no_valid_runs"}
            continue

        # Use run_1 as representative for non-consistency metrics
        rep = runs[0]
        rep_seed = seeds[0] if seeds else None

        scenario_result = {
            "status": "ok",
            "runs_collected": len(runs),
            "metrics": {
                "structural_consistency": compute_structural_consistency(runs),
                "topology_coverage": compute_topology_coverage(rep),
                "capability_utilization": compute_capability_utilization(rep),
                "scope_accuracy": compute_scope_accuracy(rep, rep_seed),
                "signal_to_noise": compute_signal_to_noise(rep, rep_seed),
                "uncertainty_correctness": compute_uncertainty_correctness(rep, rep_seed),
            }
        }

        # Oracle accuracy (informational, not gated)
        oracle = load_oracle(scenario)
        if oracle is not None:
            oracle_sets = oracle_to_sets(oracle)
            scenario_result["oracle_accuracy"] = compute_oracle_accuracy(rep, oracle_sets)
        else:
            scenario_result["oracle_accuracy"] = {"status": "no_oracle"}

        scorecard["scenarios"][scenario] = scenario_result

    # Compute aggregate summary
    valid_scenarios = [s for s in SCENARIOS
                       if scorecard["scenarios"].get(s, {}).get("status") == "ok"]

    if valid_scenarios:
        avg_consistency = sum(
            scorecard["scenarios"][s]["metrics"]["structural_consistency"]["score"]
            for s in valid_scenarios
        ) / len(valid_scenarios)
        avg_coverage = sum(
            scorecard["scenarios"][s]["metrics"]["topology_coverage"]["score"]
            for s in valid_scenarios
        ) / len(valid_scenarios)
        avg_utilization = sum(
            scorecard["scenarios"][s]["metrics"]["capability_utilization"]["score"]
            for s in valid_scenarios
        ) / len(valid_scenarios)

        # LLM-equivalent metrics (from attention_seed)
        avg_scope = []
        avg_sn = []
        avg_unc = []
        for s in valid_scenarios:
            m = scorecard["scenarios"][s]["metrics"]
            if "score" in m.get("scope_accuracy", {}):
                avg_scope.append(m["scope_accuracy"]["score"])
            if "score" in m.get("signal_to_noise", {}):
                avg_sn.append(m["signal_to_noise"]["score"])
            if "score" in m.get("uncertainty_correctness", {}):
                avg_unc.append(m["uncertainty_correctness"]["score"])

        # Oracle accuracy averages
        oracle_f1s = {"bridges": [], "boundaries": [], "hotspots": [], "entrypoints": [], "surfaces": []}
        for s in valid_scenarios:
            oa = scorecard["scenarios"][s].get("oracle_accuracy", {})
            if isinstance(oa, dict) and "status" not in oa:
                for k in oracle_f1s:
                    if k in oa:
                        oracle_f1s[k].append(oa[k]["f1"])

        avg_oracle_f1 = {}
        for k, vals in oracle_f1s.items():
            if vals:
                avg_oracle_f1[k] = round(sum(vals) / len(vals), 4)
            else:
                avg_oracle_f1[k] = None

        scorecard["summary"] = {
            "scenarios_evaluated": len(valid_scenarios),
            "structural_consistency": round(avg_consistency, 4),
            "topology_coverage": round(avg_coverage, 4),
            "capability_utilization": round(avg_utilization, 4),
            "scope_accuracy": round(sum(avg_scope) / len(avg_scope), 4) if avg_scope else None,
            "signal_to_noise": round(sum(avg_sn) / len(avg_sn), 4) if avg_sn else None,
            "uncertainty_correctness": round(sum(avg_unc) / len(avg_unc), 4) if avg_unc else None,
            "oracle_f1_average": avg_oracle_f1,
        }
    else:
        scorecard["summary"] = {"scenarios_evaluated": 0, "error": "no_valid_scenarios"}

    # Write scorecard
    scorecard_path = iteration_dir / "scorecard.json"
    with open(scorecard_path, "w") as f:
        json.dump(scorecard, f, indent=2, sort_keys=True)

    # Print summary
    print(f"=== DEL Scorecard — Iteration {args.iteration} ===")
    print()
    summary = scorecard.get("summary", {})
    print(f"Scenarios evaluated: {summary.get('scenarios_evaluated', 0)}")
    print(f"Structural consistency:  {summary.get('structural_consistency', 'N/A')}")
    print(f"Topology coverage:       {summary.get('topology_coverage', 'N/A')}")
    print(f"Capability utilization:  {summary.get('capability_utilization', 'N/A')}")
    print(f"Scope accuracy:          {summary.get('scope_accuracy', 'N/A')}")
    print(f"Signal-to-noise:         {summary.get('signal_to_noise', 'N/A')}  (lower = better focus)")
    print(f"Uncertainty correctness: {summary.get('uncertainty_correctness', 'N/A')}")
    print()
    print("Oracle F1 (informational):")
    for k, v in summary.get("oracle_f1_average", {}).items():
        print(f"  {k:15s}: {v}")
    print()
    print(f"Scorecard written to: {scorecard_path}")


if __name__ == "__main__":
    main()
