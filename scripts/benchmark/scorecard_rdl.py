#!/usr/bin/env python3
"""
RDL Scorecard — Responsibility Detection Loop

Reads builder artifacts (which now include responsibility fields in
node_index) and compares against expected_responsibilities.json oracles.

Metrics:
  1. CLASSIFICATION_ACCURACY  — % of files classified correctly
  2. CLASSIFICATION_PRECISION  — per class (TP / (TP + FP))
  3. CLASSIFICATION_RECALL     — per class (TP / (TP + FN))
  4. SIGNAL_AUDITABILITY       — % of classifications with non-empty signals

Output: tests/benchmark/iterations/iteration_N/scorecard_rdl.json

Usage:
  python3 scripts/benchmark/scorecard_rdl.py --iteration 17
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent.parent
SCENARIOS = ["python", "monolith", "bash", "node", "microservice",
             "cycle", "hub", "multi_surface"]


def load_builder_node_index(path):
    """Load a run_N.json and return its node_index, or None."""
    try:
        with open(path) as f:
            data = json.load(f)
        return data.get("payload", {}).get("topology_index", {}).get("node_index", {})
    except (json.JSONDecodeError, FileNotFoundError, KeyError):
        return None


def load_oracle(scenario):
    """Load expected_responsibilities.json for a scenario."""
    oracle_path = REPOSITORY_ROOT / "tests" / "golden" / scenario / "expected_responsibilities.json"
    if not oracle_path.exists():
        return None
    with open(oracle_path) as f:
        return json.load(f)


def compute_classification_metrics(predicted, expected):
    """Compute accuracy, per-class precision/recall, and signal auditability.

    predicted: dict {file: {responsibility, responsibility_signals, responsibility_confidence}}
    expected:  list [{file, responsibility, confidence}]
    """
    # Build expected lookup
    expected_map = {e["file"]: e["responsibility"] for e in expected}

    # All files that appear in either predicted or expected
    all_files = set(predicted.keys()) | set(expected_map.keys())

    # Per-class counts
    tp_by_class = defaultdict(int)
    fp_by_class = defaultdict(int)
    fn_by_class = defaultdict(int)
    all_classes = set()

    correct = 0
    total = 0

    for f in all_files:
        pred_resp = predicted.get(f, {}).get("responsibility", "module")
        exp_resp = expected_map.get(f, "module")
        all_classes.add(pred_resp)
        all_classes.add(exp_resp)
        total += 1

        if pred_resp == exp_resp:
            correct += 1
            tp_by_class[exp_resp] += 1
        else:
            fp_by_class[pred_resp] += 1
            fn_by_class[exp_resp] += 1

    accuracy = correct / total if total > 0 else 0.0

    # Per-class precision/recall
    per_class = {}
    for cls in sorted(all_classes):
        tp = tp_by_class[cls]
        fp = fp_by_class[cls]
        fn = fn_by_class[cls]
        precision = tp / (tp + fp) if (tp + fp) > 0 else 1.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 1.0
        per_class[cls] = {
            "precision": round(precision, 4),
            "recall": round(recall, 4),
            "tp": tp,
            "fp": fp,
            "fn": fn,
        }

    # Signal auditability
    with_signals = sum(1 for f, v in predicted.items() if v.get("responsibility_signals"))
    signal_auditability = with_signals / len(predicted) if predicted else 0.0

    return {
        "accuracy": round(accuracy, 4),
        "correct": correct,
        "total": total,
        "per_class": per_class,
        "signal_auditability": round(signal_auditability, 4),
        "misclassified": [
            {"file": f,
             "predicted": predicted.get(f, {}).get("responsibility", "module"),
             "expected": expected_map.get(f, "module")}
            for f in sorted(all_files)
            if predicted.get(f, {}).get("responsibility", "module") != expected_map.get(f, "module")
        ],
    }


def main():
    parser = argparse.ArgumentParser(description="RDL Scorecard")
    parser.add_argument("--iteration", required=True, help="Iteration number")
    args = parser.parse_args()

    iteration_dir = REPOSITORY_ROOT / "tests" / "benchmark" / "iterations" / f"iteration_{args.iteration}"

    if not iteration_dir.exists():
        print(f"ERROR: iteration directory not found: {iteration_dir}", file=sys.stderr)
        sys.exit(1)

    scorecard = {
        "iteration": int(args.iteration),
        "loop": "rdl",
        "timestamp": __import__("datetime").datetime.now().isoformat() + "Z",
        "scenarios": {},
        "summary": {},
    }

    all_correct = 0
    all_total = 0
    all_tp = defaultdict(int)
    all_fp = defaultdict(int)
    all_fn = defaultdict(int)
    all_with_signals = 0
    all_predicted_count = 0

    for scenario in SCENARIOS:
        scenario_dir = iteration_dir / scenario
        if not scenario_dir.exists():
            scorecard["scenarios"][scenario] = {"status": "missing"}
            continue

        # Load run_1 as representative (responsibility detection is deterministic)
        node_index = load_builder_node_index(scenario_dir / "run_1.json")
        if node_index is None:
            scorecard["scenarios"][scenario] = {"status": "no_node_index"}
            continue

        oracle = load_oracle(scenario)
        if oracle is None:
            scorecard["scenarios"][scenario] = {"status": "no_oracle"}
            continue

        # Build predicted dict from node_index
        predicted = {}
        for f, facts in node_index.items():
            predicted[f] = {
                "responsibility": facts.get("responsibility", "module"),
                "responsibility_signals": facts.get("responsibility_signals", []),
                "responsibility_confidence": facts.get("responsibility_confidence", "low"),
            }

        metrics = compute_classification_metrics(predicted, oracle.get("expected", []))
        scorecard["scenarios"][scenario] = {
            "status": "ok",
            "metrics": metrics,
        }

        all_correct += metrics["correct"]
        all_total += metrics["total"]
        all_with_signals += sum(1 for v in predicted.values() if v["responsibility_signals"])
        all_predicted_count += len(predicted)
        for cls, m in metrics["per_class"].items():
            all_tp[cls] += m["tp"]
            all_fp[cls] += m["fp"]
            all_fn[cls] += m["fn"]

    # Aggregate summary
    if all_total > 0:
        overall_accuracy = all_correct / all_total
        overall_signal_audit = all_with_signals / all_predicted_count if all_predicted_count else 0.0

        all_classes = set(all_tp.keys()) | set(all_fp.keys()) | set(all_fn.keys())
        overall_per_class = {}
        for cls in sorted(all_classes):
            tp = all_tp[cls]
            fp = all_fp[cls]
            fn = all_fn[cls]
            precision = tp / (tp + fp) if (tp + fp) > 0 else 1.0
            recall = tp / (tp + fn) if (tp + fn) > 0 else 1.0
            overall_per_class[cls] = {
                "precision": round(precision, 4),
                "recall": round(recall, 4),
                "tp": tp, "fp": fp, "fn": fn,
            }

        scorecard["summary"] = {
            "scenarios_evaluated": sum(1 for s in scorecard["scenarios"].values()
                                       if s.get("status") == "ok"),
            "classification_accuracy": round(overall_accuracy, 4),
            "signal_auditability": round(overall_signal_audit, 4),
            "correct": all_correct,
            "total": all_total,
            "per_class": overall_per_class,
        }
    else:
        scorecard["summary"] = {"scenarios_evaluated": 0, "error": "no_valid_scenarios"}

    # Write scorecard
    scorecard_path = iteration_dir / "scorecard_rdl.json"
    with open(scorecard_path, "w") as f:
        json.dump(scorecard, f, indent=2, sort_keys=True)

    # Print summary
    print(f"=== RDL Scorecard — Iteration {args.iteration} ===")
    print()
    summary = scorecard.get("summary", {})
    print(f"Scenarios evaluated:    {summary.get('scenarios_evaluated', 0)}")
    print(f"Classification accuracy: {summary.get('classification_accuracy', 'N/A')}")
    print(f"Signal auditability:    {summary.get('signal_auditability', 'N/A')}")
    print(f"Correct:                {summary.get('correct', 0)}/{summary.get('total', 0)}")
    print()
    print("Per-class precision/recall:")
    for cls, m in summary.get("per_class", {}).items():
        print(f"  {cls:15s}: P={m['precision']} R={m['recall']} tp={m['tp']} fp={m['fp']} fn={m['fn']}")
    print()

    # Show misclassifications
    for scenario, data in scorecard["scenarios"].items():
        if data.get("status") != "ok":
            continue
        misc = data["metrics"].get("misclassified", [])
        if misc:
            print(f"Misclassifications in {scenario}:")
            for m in misc:
                print(f"  {m['file']:40s} predicted={m['predicted']:12s} expected={m['expected']}")

    print()
    print(f"Scorecard written to: {scorecard_path}")


if __name__ == "__main__":
    main()
