#!/usr/bin/env python3
"""
FEL Scorecard — Forensics Evolution Loop

Measures whether Forensics' output complies with its contract:
  - "O que significa" (what it means) — interpretation, NOT re-observation
  - interpretations are target-anchored and evidence-backed (capability
    payloads, NEVER the epistemic handover file)
  - repair candidates are valid file paths within routed targets
  - cognitive fields (investigation_hypotheses, investigation_risks) are
    present and non-empty
  - no structural fields leaked (the builder owns "what exists")

Contract compliance is mechanical — the contract IS the oracle.
Interpretation accuracy uses expected_forensics.json (informational).

Reads golden_forensics.json snapshots as input (the promoted artifact,
the same surface DCL reads for discovery).

Metrics:
  Contract (mechanical):
    1. STRUCTURAL_FIELD_ABSENCE     — no structural fields in operational_context
    2. INTERPRETATION_PRESENCE      — interpretations non-empty, canonical shape
    3. EVIDENCE_LEGITIMACY          — evidence_refs cite capability payloads, not handover
    4. REPAIR_CANDIDATE_VALIDITY    — ids are file paths within routed targets
    5. COGNITIVE_FIELD_PRESENCE     — hypotheses & risks non-empty
    6. HANDOVER_ATTENTION_VALIDITY  — next_attention_targets / scope / reason present
  Oracle (expected_forensics.json, informational):
    7. INTERPRETATION_TARGET_PRECISION
    8. INTERPRETATION_TARGET_RECALL
    9. REPAIR_CANDIDATE_PRECISION
   10. REPAIR_CANDIDATE_RECALL

Usage:
  python3 scripts/benchmark/scorecard_fel.py
  python3 scripts/benchmark/scorecard_fel.py --verbose
"""

import argparse
import json
import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent.parent
SCENARIOS = ["python", "monolith", "bash", "node", "microservice"]

# Contract: structural fields that MUST NOT appear in operational_context.
# Forensics consumes these from structural_context; it must not copy them
# into its own output (the builder owns "what exists").
# NOTE: "evidence" is a legitimate Forensics output field (the evidence
# list in the required JSON shape), so it is NOT treated as leaked here.
STRUCTURAL_FIELDS = {
    "topology_summary",
    "topology_index",
    "ranked_targets",
    "observed_request_alignment",
    "gap_counts",
    "unresolved_references",
    "bridge_data",
    "boundary_data",
    "hotspot_data",
    "entrypoints",
    "evidence_summary",
}

# Canonical interpretation element shape (forensics.md).
INTERPRETATION_REQUIRED_FIELDS = {"id", "target", "interpretation", "confidence", "evidence_refs"}

# Topology identifiers are NOT valid repair candidate ids.
TOPOLOGY_ID_RE = re.compile(r"^(bridge|boundary|hotspot|entrypoint|surface_cluster|surface_standalone)_\d+$")

# References to the epistemic handover are forbidden as evidence.
HANDOVER_RE = re.compile(r"handover", re.IGNORECASE)

# Discovery's cognitive/observation fields. Forensics must NOT re-emit these —
# re-observation is work duplication across modes and violates the epistemic
# separation (Discovery = what to investigate; Forensics = what it means).
# Gen-1 reasoning-chain fossils that must NOT reappear in Forensics'
# operational_context or epistemic_state. These are legacy fields from a
# prior architecture generation; Forensics interprets, it does not re-emit
# Discovery's old observation fields. (recommended_next_actions is NOT a
# fossil — it is a legitimate Discovery-owned epistemic_state field.)
DISCOVERY_OBSERVATION_FIELDS = {
    "operational_observations",
    "rationale",
    "escalation_reason",
    "confidence_drivers",
    "evidence_priorities",
    "required_evidence",
}


def norm_path(p):
    """Normalize a file path for comparison: strip a leading input/ prefix.

    golden_forensics.json snapshots were produced with paths prefixed by
    the scenario content dir (e.g. input/src/main.py). The topology
    oracles use the canonical builder form (src/main.py). Stripping the
    leading input/ makes both forms comparable.
    """
    if not isinstance(p, str):
        return ""
    p = p.strip()
    if p.startswith("input/"):
        p = p[len("input/"):]
    return p


def load_golden_forensics(scenario):
    """Load golden_forensics.json for a scenario."""
    path = REPOSITORY_ROOT / "tests" / "golden" / scenario / "golden_forensics.json"
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def load_oracle(scenario):
    """Load expected_forensics.json for a scenario, or None."""
    path = REPOSITORY_ROOT / "tests" / "golden" / scenario / "expected_forensics.json"
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def load_golden_discovery(scenario):
    """Load golden_discovery.json for a scenario, or None.

    Used to check Forensics does not re-observe what Discovery already
    investigated (cross-mode non-redundancy).
    """
    path = REPOSITORY_ROOT / "tests" / "golden" / scenario / "golden_discovery.json"
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def routed_targets(golden):
    """Collect the set of valid file targets Forensics was routed to.

    Drawn from structural_context (runtime-owned): node_index keys,
    ranked_targets files, observed_request_alignment.resolved_paths,
    and the topology_index member files.
    """
    targets = set()
    snapshot = golden.get("artifact_snapshot", {})
    sc = snapshot.get("structural_context", {})
    ni = sc.get("topology_index", {}).get("node_index", {})
    targets.update(norm_path(f) for f in ni.keys())

    for rt in sc.get("ranked_targets", []):
        if isinstance(rt, dict) and rt.get("type") == "explicit_request" and rt.get("file"):
            targets.add(norm_path(rt["file"]))

    ora = sc.get("observed_request_alignment", {})
    for rp in ora.get("resolved_paths", []):
        targets.add(norm_path(rp))

    tidx = sc.get("topology_index", {})
    for b in tidx.get("bridges", []):
        if isinstance(b, dict):
            targets.add(norm_path(b.get("from", "")))
            targets.add(norm_path(b.get("to", "")))
    for b in tidx.get("boundaries", []):
        if isinstance(b, dict):
            targets.add(norm_path(b.get("file", "")))
    for h in tidx.get("hotspots", []):
        if isinstance(h, dict):
            targets.add(norm_path(h.get("file", "")))
    for e in tidx.get("entrypoints", []):
        if isinstance(e, dict):
            targets.add(norm_path(e.get("file", "")))
    for s in tidx.get("surfaces", []):
        if isinstance(s, dict):
            for m in s.get("members", []):
                targets.add(norm_path(m))

    targets.discard("")
    return targets


def is_legitimate_ref(ref):
    """A reference is legitimate evidence if it cites a capability payload
    and does NOT cite the epistemic handover."""
    if not isinstance(ref, str) or not ref.strip():
        return False
    if HANDOVER_RE.search(ref):
        return False
    return True


# ---------------------------------------------------------------------------
# Contract metrics
# ---------------------------------------------------------------------------

def m_structural_field_absence(op_ctx, ep_state=None):
    """Structural fields must not leak into operational_context or epistemic_state."""
    op_keys = set(op_ctx.keys()) if isinstance(op_ctx, dict) else set()
    ep_keys = set(ep_state.keys()) if isinstance(ep_state, dict) else set()
    leaked = (op_keys & STRUCTURAL_FIELDS) | (ep_keys & STRUCTURAL_FIELDS)
    return {
        "score": 1.0 if not leaked else 0.0,
        "leaked_fields": sorted(leaked),
    }


def m_interpretation_presence(op_ctx):
    interps = op_ctx.get("interpretations", [])
    if not isinstance(interps, list):
        return {"score": 0.0, "count": 0, "malformed": [], "reason": "interpretations not a list"}
    if not interps:
        return {"score": 0.0, "count": 0, "malformed": [], "reason": "interpretations empty"}
    malformed = []
    for idx, i in enumerate(interps):
        if not isinstance(i, dict):
            malformed.append({"index": idx, "reason": "not an object"})
            continue
        keys = set(i.keys())
        missing = INTERPRETATION_REQUIRED_FIELDS - keys
        if missing:
            malformed.append({"index": idx, "missing": sorted(missing), "keys": sorted(keys)})
            continue
        # target must be a non-empty string (a file path)
        if not isinstance(i.get("target"), str) or not i["target"].strip():
            malformed.append({"index": idx, "reason": "target is not a non-empty file path"})
            continue
        # interpretation must be a non-empty string (meaning, not a fact restatement)
        if not isinstance(i.get("interpretation"), str) or not i["interpretation"].strip():
            malformed.append({"index": idx, "reason": "interpretation text empty"})
    score = 1.0 if not malformed else 1.0 - len(malformed) / len(interps)
    return {
        "score": round(score, 4),
        "count": len(interps),
        "malformed_count": len(malformed),
        "malformed": malformed,
    }


def m_evidence_legitimacy(op_ctx):
    interps = op_ctx.get("interpretations", [])
    if not isinstance(interps, list) or not interps:
        return {"score": 0.0, "legitimate": 0, "total": 0, "handover_refs": [], "reason": "no interpretations"}
    legitimate = 0
    handover_refs = []
    empty_refs = 0
    for i in interps:
        if not isinstance(i, dict):
            continue
        refs = i.get("evidence_refs", [])
        if not isinstance(refs, list) or not refs:
            empty_refs += 1
            continue
        all_legit = True
        for r in refs:
            if HANDOVER_RE.search(r or ""):
                handover_refs.append(r)
                all_legit = False
        if all_legit:
            legitimate += 1
    total = len(interps)
    score = legitimate / total if total else 0.0
    return {
        "score": round(score, 4),
        "legitimate": legitimate,
        "total": total,
        "empty_refs": empty_refs,
        "handover_refs": sorted(set(handover_refs)),
    }


def m_repair_candidate_validity(op_ctx, targets):
    candidates = op_ctx.get("repair_candidates", [])
    if not isinstance(candidates, list):
        return {"score": 0.0, "count": 0, "invalid": [], "reason": "repair_candidates not a list"}
    # Empty is contract-legal ("be omitted when no evidence-backed target exists").
    if not candidates:
        return {"score": 1.0, "count": 0, "invalid": [], "reason": "omitted (no evidence-backed target)"}
    invalid = []
    for idx, c in enumerate(candidates):
        if not isinstance(c, dict):
            invalid.append({"index": idx, "reason": "not an object"})
            continue
        cid = c.get("id")
        if not isinstance(cid, str) or not cid.strip():
            invalid.append({"index": idx, "reason": "id missing"})
            continue
        if TOPOLOGY_ID_RE.match(cid):
            invalid.append({"index": idx, "id": cid, "reason": "id is a topology identifier, not a file path"})
            continue
        if not c.get("reason"):
            invalid.append({"index": idx, "id": cid, "reason": "reason missing"})
            continue
        if not c.get("evidence_refs"):
            invalid.append({"index": idx, "id": cid, "reason": "evidence_refs missing"})
            continue
        if norm_path(cid) not in targets:
            invalid.append({"index": idx, "id": cid, "reason": "id not within routed targets"})
    score = 1.0 if not invalid else 1.0 - len(invalid) / len(candidates)
    return {
        "score": round(score, 4),
        "count": len(candidates),
        "invalid_count": len(invalid),
        "invalid": invalid,
    }


def m_cognitive_field_presence(ep_state):
    """Forensics owns investigation_hypotheses and investigation_risks in epistemic_state."""
    es = ep_state if isinstance(ep_state, dict) else {}
    hyp = es.get("investigation_hypotheses", [])
    risks = es.get("investigation_risks", [])
    hyp_ok = isinstance(hyp, list) and len(hyp) > 0
    risks_ok = isinstance(risks, list) and len(risks) > 0
    score = (int(hyp_ok) + int(risks_ok)) / 2
    return {
        "score": round(score, 4),
        "hypotheses_count": len(hyp) if isinstance(hyp, list) else 0,
        "risks_count": len(risks) if isinstance(risks, list) else 0,
        "hypotheses_nonempty": hyp_ok,
        "risks_nonempty": risks_ok,
    }


def m_handover_attention_validity(golden, op_ctx):
    # The runtime promotes the mode's epistemic_state to top-level epistemic_state.
    # Forensics emits epistemic_state (not handover_attention); the runtime
    # merges it over the previous state. Read from epistemic_state.
    es = golden.get("epistemic_state", {})
    next_targets = es.get("next_attention_targets", [])
    scope = es.get("attention_scope")
    reason = es.get("attention_reason")
    checks = {
        "next_attention_targets_nonempty": isinstance(next_targets, list) and len(next_targets) > 0,
        "attention_scope_present": isinstance(scope, str) and bool(scope.strip()),
        "attention_reason_present": isinstance(reason, str) and bool(reason.strip()),
    }
    score = sum(checks.values()) / len(checks)
    return {
        "score": round(score, 4),
        **checks,
        "next_attention_targets_count": len(next_targets) if isinstance(next_targets, list) else 0,
    }


def _flatten_text(v):
    """Flatten a value (str / list / dict) into a single lowercase string."""
    if v is None:
        return ""
    if isinstance(v, str):
        return v.lower()
    if isinstance(v, (list, dict)):
        return json.dumps(v, ensure_ascii=False).lower()
    return str(v).lower()


def _word_ngrams(text, n=3):
    """Return the set of word n-grams from text (content-bearing similarity)."""
    words = re.findall(r"[a-z_]{3,}", text)
    if len(words) < n:
        return set()
    return {tuple(words[i:i + n]) for i in range(len(words) - n + 1)}


def m_observation_non_redundancy(golden_discovery, op_ctx, ep_state=None):
    """Forensics must not re-observe what Discovery already investigated.

    Two checks:
      (a) MECHANICAL — Forensics' operational_context and epistemic_state
          must not carry Gen-1 reasoning-chain fossils
          (operational_observations, rationale, escalation_reason,
          confidence_drivers, evidence_priorities, required_evidence).
          Forensics interprets; it does not re-emit Discovery's old fields.
      (b) SEMANTIC — Forensics' observations must not be near-paraphrases of
          Discovery's epistemic_state investigation model (evidence_gaps,
          investigation_objectives, investigation_strategy). A shared n-gram
          Jaccard above the threshold flags re-statement (echo), not
          legitimate shared vocabulary (which is mostly single-word
          topology terms).

    golden_discovery may be None (no discovery snapshot); then only (a) runs.
    """
    op_keys = set(op_ctx.keys()) if isinstance(op_ctx, dict) else set()
    ep_keys = set(ep_state.keys()) if isinstance(ep_state, dict) else set()
    redundant_fields = (op_keys & DISCOVERY_OBSERVATION_FIELDS) | (ep_keys & DISCOVERY_OBSERVATION_FIELDS)
    field_score = 1.0 if not redundant_fields else 1.0 - len(redundant_fields) / len(DISCOVERY_OBSERVATION_FIELDS)

    # Semantic echo check against Discovery's epistemic_state investigation model.
    semantic = {
        "max_jaccard": 0.0,
        "echo_pairs": [],
        "threshold": 0.6,
        "checked": golden_discovery is not None,
    }
    if golden_discovery is not None:
        d_es = golden_discovery.get("epistemic_state", {})
        d_obs = []
        for k in ("evidence_gaps", "investigation_objectives", "recommended_next_actions"):
            d_obs.extend(d_es.get(k, []) if isinstance(d_es.get(k), list) else [])
        d_obs.append(d_es.get("investigation_strategy", ""))
        d_obs_texts = [_flatten_text(o) for o in d_obs if o]
        d_obs_ngrams = [ng for t in d_obs_texts if (ng := _word_ngrams(t))]
        # Forensics observations can be strings or {target, observation} dicts.
        f_obs = op_ctx.get("observations", []) if isinstance(op_ctx, dict) else []
        f_obs_texts = []
        for o in f_obs:
            if isinstance(o, dict):
                f_obs_texts.append(_flatten_text(o.get("observation", "")) + " " + _flatten_text(o.get("target", "")))
            else:
                f_obs_texts.append(_flatten_text(o))
        max_j = 0.0
        echoes = []
        for f_t, f_ng in ((t, _word_ngrams(t)) for t in f_obs_texts):
            if not f_ng:
                continue
            for d_idx, d_ng in enumerate(d_obs_ngrams):
                if not d_ng:
                    continue
                inter = len(f_ng & d_ng)
                union = len(f_ng | d_ng)
                j = inter / union if union else 0.0
                if j > max_j:
                    max_j = j
                if j >= semantic["threshold"]:
                    echoes.append({"jaccard": round(j, 3), "forensics": f_t[:120], "discovery_index": d_idx})
        semantic["max_jaccard"] = round(max_j, 3)
        semantic["echo_pairs"] = echoes

    semantic_score = 1.0
    if semantic["checked"]:
        # Penalize proportionally to how far above threshold the worst echo is.
        max_j = semantic["max_jaccard"]
        if max_j >= semantic["threshold"]:
            semantic_score = max(0.0, 1.0 - (max_j - semantic["threshold"]) / (1.0 - semantic["threshold"]))

    # Composite: both must hold. A field leak OR a semantic echo is a failure.
    score = min(field_score, semantic_score)
    return {
        "score": round(score, 4),
        "field_score": round(field_score, 4),
        "semantic_score": round(semantic_score, 4),
        "redundant_fields_present": sorted(redundant_fields),
        "semantic": semantic,
    }


# ---------------------------------------------------------------------------
# Oracle metrics
# ---------------------------------------------------------------------------

def precision_recall(predicted, expected):
    pred = set(predicted)
    exp = set(expected)
    if not pred and not exp:
        return 1.0, 1.0, 0, 0, 0
    tp = len(pred & exp)
    precision = tp / len(pred) if pred else 0.0
    recall = tp / len(exp) if exp else 0.0
    return round(precision, 4), round(recall, 4), tp, len(pred), len(exp)


def m_interpretation_targets(op_ctx, oracle):
    expected = [norm_path(t) for t in oracle.get("expected_interpretation_targets", [])]
    interps = op_ctx.get("interpretations", [])
    predicted = []
    for i in interps:
        if isinstance(i, dict) and isinstance(i.get("target"), str):
            t = norm_path(i["target"])
            if t:
                predicted.append(t)
    p, r, tp, pc, ec = precision_recall(predicted, expected)
    return {
        "precision": p,
        "recall": r,
        "tp": tp,
        "predicted_count": pc,
        "expected_count": ec,
        "predicted": sorted(set(predicted)),
        "expected": sorted(set(expected)),
        "missed": sorted(set(expected) - set(predicted)),
        "extra": sorted(set(predicted) - set(expected)),
    }


def m_repair_candidates(op_ctx, oracle):
    expected = [norm_path(t) for t in oracle.get("expected_repair_candidates", [])]
    candidates = op_ctx.get("repair_candidates", [])
    predicted = []
    for c in candidates:
        if isinstance(c, dict) and isinstance(c.get("id"), str):
            cid = norm_path(c["id"])
            if cid and not TOPOLOGY_ID_RE.match(c["id"]):
                predicted.append(cid)
    p, r, tp, pc, ec = precision_recall(predicted, expected)
    return {
        "precision": p,
        "recall": r,
        "tp": tp,
        "predicted_count": pc,
        "expected_count": ec,
        "predicted": sorted(set(predicted)),
        "expected": sorted(set(expected)),
        "missed": sorted(set(expected) - set(predicted)),
        "extra": sorted(set(predicted) - set(expected)),
    }


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def compute_fel_metrics(golden, oracle, golden_discovery=None):
    snapshot = golden.get("artifact_snapshot", {})
    op_ctx = snapshot.get("operational_context", {})
    ep_state = golden.get("epistemic_state", {})
    ep_state = golden.get("epistemic_state", {})
    targets = routed_targets(golden)

    contract = {
        "structural_field_absence": m_structural_field_absence(op_ctx, ep_state),
        "interpretation_presence": m_interpretation_presence(op_ctx),
        "evidence_legitimacy": m_evidence_legitimacy(op_ctx),
        "repair_candidate_validity": m_repair_candidate_validity(op_ctx, targets),
        "cognitive_field_presence": m_cognitive_field_presence(ep_state),
        "handover_attention_validity": m_handover_attention_validity(golden, op_ctx),
        "observation_non_redundancy": m_observation_non_redundancy(golden_discovery, op_ctx, ep_state),
    }

    result = {
        "contract": contract,
        "routed_target_count": len(targets),
    }

    if oracle is not None:
        result["oracle"] = {
            "interpretation_targets": m_interpretation_targets(op_ctx, oracle),
            "repair_candidates": m_repair_candidates(op_ctx, oracle),
        }
    else:
        result["oracle"] = {"status": "no_oracle"}

    return result


def main():
    parser = argparse.ArgumentParser(description="FEL Scorecard — Forensics Evolution Loop")
    parser.add_argument("--verbose", action="store_true", help="show per-scenario detail")
    args = parser.parse_args()

    import datetime
    scorecard = {
        "loop": "fel",
        "timestamp": datetime.datetime.now().isoformat() + "Z",
        "scenarios": {},
        "summary": {},
    }

    contract_keys = [
        "structural_field_absence", "interpretation_presence", "evidence_legitimacy",
        "repair_candidate_validity", "cognitive_field_presence", "handover_attention_validity",
        "observation_non_redundancy",
    ]
    oracle_keys = ["interpretation_targets", "repair_candidates"]

    all_contract = {k: [] for k in contract_keys}
    all_oracle_p = {k: [] for k in oracle_keys}
    all_oracle_r = {k: [] for k in oracle_keys}

    for scenario in SCENARIOS:
        golden = load_golden_forensics(scenario)
        if golden is None:
            scorecard["scenarios"][scenario] = {"status": "no_golden"}
            continue
        oracle = load_oracle(scenario)
        golden_discovery = load_golden_discovery(scenario)
        metrics = compute_fel_metrics(golden, oracle, golden_discovery)
        scorecard["scenarios"][scenario] = {"status": "ok", "metrics": metrics}

        for k in contract_keys:
            all_contract[k].append(metrics["contract"][k]["score"])
        if metrics.get("oracle", {}).get("status") != "no_oracle":
            for k in oracle_keys:
                all_oracle_p[k].append(metrics["oracle"][k]["precision"])
                all_oracle_r[k].append(metrics["oracle"][k]["recall"])

    summary = {"contract": {}, "oracle": {}}
    for k, scores in all_contract.items():
        summary["contract"][k] = round(sum(scores) / len(scores), 4) if scores else None
    for k in oracle_keys:
        ps = all_oracle_p[k]
        rs = all_oracle_r[k]
        summary["oracle"][f"{k}_precision"] = round(sum(ps) / len(ps), 4) if ps else None
        summary["oracle"][f"{k}_recall"] = round(sum(rs) / len(rs), 4) if rs else None
    scorecard["summary"] = summary

    # Write
    output_path = REPOSITORY_ROOT / "tests" / "benchmark" / "fel_scorecard.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(scorecard, f, indent=2, sort_keys=True)

    # Print
    print("=== FEL Scorecard — Forensics Evolution Loop ===")
    print("  Epistemic role: 'O que significa' (what it means)")
    print()
    print("  Contract metrics (mechanical, contract IS oracle):")
    print(f"  {'metric':42s} {'score':>6s}")
    print("  " + "-" * 50)
    for k, v in summary["contract"].items():
        label = k.replace("_", " ").title()
        print(f"  {label:42s} {v:>6.2f}" if v is not None else f"  {label:42s} {'N/A':>6s}")
    print()
    print("  Oracle metrics (expected_forensics.json, informational):")
    print(f"  {'metric':42s} {'score':>6s}")
    print("  " + "-" * 50)
    for k, v in summary["oracle"].items():
        label = k.replace("_", " ").title()
        print(f"  {label:42s} {v:>6.2f}" if v is not None else f"  {label:42s} {'N/A':>6s}")
    print()

    # Per-scenario flags
    print("  Per-scenario:")
    for scenario, data in scorecard["scenarios"].items():
        if data.get("status") != "ok":
            print(f"    {scenario:15s}: {data['status']}")
            continue
        m = data["metrics"]
        c = m["contract"]
        flags = []
        if c["structural_field_absence"]["score"] < 1.0:
            flags.append(f"LEAKED:{c['structural_field_absence']['leaked_fields']}")
        if c["interpretation_presence"]["score"] < 1.0:
            flags.append(f"INTERP_MALFORMED:{c['interpretation_presence']['malformed_count']}")
        if c["evidence_legitimacy"]["score"] < 1.0:
            hr = c["evidence_legitimacy"].get("handover_refs", [])
            er = c["evidence_legitimacy"].get("empty_refs", 0)
            if hr:
                flags.append(f"HANDOVER_AS_EVIDENCE({len(hr)})")
            if er:
                flags.append(f"EMPTY_EVIDENCE({er})")
        if c["repair_candidate_validity"]["score"] < 1.0:
            flags.append(f"BAD_CANDIDATES:{c['repair_candidate_validity']['invalid_count']}")
        if c["cognitive_field_presence"]["score"] < 1.0:
            if not c["cognitive_field_presence"]["hypotheses_nonempty"]:
                flags.append("NO_HYPOTHESES")
            if not c["cognitive_field_presence"]["risks_nonempty"]:
                flags.append("NO_RISKS")
        if c["handover_attention_validity"]["score"] < 1.0:
            flags.append("HANDOVER_INCOMPLETE")
        onr = c.get("observation_non_redundancy", {})
        if onr.get("score", 1.0) < 1.0:
            if onr.get("redundant_fields_present"):
                flags.append(f"RE_OBSERVES_DISCOVERY_FIELDS:{onr['redundant_fields_present']}")
            sem = onr.get("semantic", {})
            if sem.get("echo_pairs"):
                flags.append(f"OBSERVATION_ECHO(jaccard={sem['max_jaccard']},{len(sem['echo_pairs'])} pairs)")
        status = "✅" if not flags else "❌"
        print(f"    {status} {scenario:15s}: {'  '.join(flags) if flags else 'contract compliant'}")

    if args.verbose:
        print()
        for scenario, data in scorecard["scenarios"].items():
            if data.get("status") != "ok":
                continue
            m = data["metrics"]
            o = m.get("oracle", {})
            if o.get("status") == "no_oracle":
                continue
            print(f"  --- {scenario} oracle ---")
            it = o.get("interpretation_targets", {})
            print(f"    interp targets: P={it.get('precision')} R={it.get('recall')} "
                  f"missed={it.get('missed')} extra={it.get('extra')}")
            rc = o.get("repair_candidates", {})
            print(f"    repair cand:    P={rc.get('precision')} R={rc.get('recall')} "
                  f"missed={rc.get('missed')} extra={rc.get('extra')}")

    print()
    print(f"  Scorecard: {output_path}")


if __name__ == "__main__":
    main()
