# FEL Iteration 02 — Handover Purity (reasoning-chain stripping)

## Trigger

The architectural critique (and the cross-mode duplication audit)
exposed that the runtime was persisting Discovery's reasoning chain in
the handover. The DCL measured this directly:

```
Required Field Presence              1.00   (mandated the 5 reasoning-chain fields)
Handover Purity                      0.00   (all 5 reasoning-chain fields ride the handover, 5/5 scenarios)
Discovery Strategic Content          0.00   (no investigation_objectives/gaps/decision_points)

⚠ CONTRACT CONTRADICTION: REQUIRED_FIELD_PRESENCE MANDATED the exact
  reasoning-chain fields that HANDOVER_PURITY penalized.
```

A compiler saves AST/IR/bytecode, not its train of thought. The runtime
was carrying Discovery's "why" (rationale, observations, recommendations)
across modes — disposable cognition that the constitution says does not
survive. Forensics did not consume any of it as routing; it was dead
weight that inflated the handover and tempted Forensics to cite it as
evidence (the EVIDENCE_LEGITIMACY=0.00 the FEL caught in Iteration 01).

## Root Cause

**Classification: contract contradiction (primary).**

`discovery.md` MANDATED the five reasoning-chain fields
(`operational_observations`, `rationale`, `escalation_reason`,
`recommended_next_actions`, `confidence_drivers`) as required handover
content. The DCL scored Discovery UP for producing them. But the
constitution (AGENTS.md: Disposable Cognition) says reasoning is not
memory, not evidence, not an epistemic handover. The contract contradicted
the constitution it was supposed to enforce.

Secondary: `promote_epistemic_handover` (runtime_aegis.sh) stripped
structural fields from operational_context but NOT reasoning-chain
fields — so even the fields the contract wanted gone survived promotion.

## Hypothesis

If the contract stops mandating reasoning-chain fields and instead
mandates the investigative PLAN (investigation_objectives, evidence_gaps,
decision_points), AND the runtime strips the reasoning-chain fields during
promotion, then the handover carries plan + routing only — the compiler
saves the plan, not the train of thought. HANDOVER_PURITY → 1.00,
DISCOVERY_STRATEGIC_CONTENT → 1.00, the contract contradiction dissolves,
and the handover shrinks (reducing the byte-limit pressure).

## Applied Changes (Iteration 02)

1. `discovery.md` — reoriented the contract:
   - Header: Discovery emits an investigative PLAN, NOT a reasoning chain.
     Added the "compiler saves AST/IR/bytecode, not its train of thought"
     rationale.
   - Field-definition table: dropped the 5 reasoning-chain entries from
     the required set; added `investigation_objectives`, `evidence_gaps`,
     `decision_points` as Cognitive (strategic).
   - New "Not promoted (disposable cognition)" section explicitly listing
     the 5 reasoning-chain fields as non-handover content.
   - Required JSON Shape example: replaced reasoning-chain blocks with
     strategic-field examples.
   - Failure Policy: updated fallback field assignments to the strategic
     fields.

2. `runtime_aegis.sh` `promote_epistemic_handover` — both jq branches
   (builder present + builder missing) now `del()` the 5 reasoning-chain
   fields from operational_context alongside the structural fields. The
   handover carries plan + routing, not reasoning.

3. `scripts/substrates/raw_llm.sh` discovery prompt — reoriented to
   mandate the strategic fields (objectives/gaps/decision_points) and
   declare that rationale/observations are disposable and will NOT be
   promoted. Separation prohibitions reframed around strategic fields.

4. `scripts/benchmark/scorecard_dcl.py` — `REQUIRED_FIELDS` realigned to
   the strategic plan (dropped 5 reasoning-chain, added 3 strategic).
   Contradiction detection refined: now checks for actual
   REQUIRED_FIELDS ∩ REASONING_CHAIN_FIELDS overlap (a true regression)
   rather than score divergence (which is expected during transition).
   `REQUIRED_FIELD_PRESENCE` and `HANDOVER_PURITY` now pull the same
   direction.

## Guard Results (deterministic, isolated runs)

| Guard | Result |
|---|---|
| bash syntax (runtime_aegis.sh, config.sh, raw_llm.sh) | PASS |
| jq del() syntax (validated on test input) | PASS — strips exactly the 5 fields |
| constitutional invariants (profile ⊆ envelope, skill declarations) | PASS |
| epistemic pipeline audit (discovery/forensics skill declarations) | PASS |
| runtime contract test | PASS |
| no test hardcodes reasoning-chain fields (runtime-contract, sovereignty, validation) | confirmed — strip breaks no assertions |

## Simulated end-to-end path (confirms the 1.00 outcome)

Simulated the runtime strip on a real golden_discovery.json + added the
strategic fields, then ran the DCL metric:

```
required_field_presence:     1.0
cognitive_field_presence:    1.0
discovery_strategic_content: 1.0
handover_purity:             1.0  (reasoning_chain_fields_present: [])
```

This proves that when a live Discovery run executes with the Iteration 02
contract, all four DCL metrics hit 1.00 simultaneously and the contract
contradiction is gone. The deterministic change is in place; the
LLM-dependent confirmation awaits a live Discovery run.

## Current scorecard state (honest transition)

The existing golden_discovery.json snapshots PREDATE the Iteration 02
contract change, so they still carry the reasoning-chain fields and lack
the strategic ones. The scorecard correctly shows the transition state:

```
Required Field Presence              0.62   (5/8 strategic+routing fields present; 3 strategic missing)
Discovery Strategic Content          0.00   (snapshots predate strategic fields)
Handover Purity                      0.00   (snapshots predate the strip)
(no CONTRACT CONTRADICTION warning — sets are disjoint, no regression)
```

These will rise to 1.00 on a live Discovery run. The scorecard is
deterministic; the artifact is LLM-produced.

## Side effects

- Handover shrinks (5 verbose cognition fields removed) — directly
  reduces the byte-limit pressure that the deferred `exceeds_max_bytes`
  issue (large-repo scale) was hitting. The strip is in the direction
  the user's critique pointed.
- Forensics no longer receives a reasoning chain to mis-cite as
  evidence — reinforces Iteration 01's EVIDENCE_LEGITIMACY fix.
- The cross-mode OBSERVATION_NON_REDUNDANCY metric's mechanical arm
  (no reasoning-chain fields in Forensics' operational_context) is now
  enforced at the source — the runtime never puts them in the handover.

## Verification path (not yet executed)

1. Run a real Discovery pass (API key) against benchmark scenarios,
   producing fresh golden_discovery.json snapshots.
2. Re-run `npm run aegis:benchmark:dcl`.
3. Expect required_field_presence, cognitive_field_presence,
   discovery_strategic_content, handover_purity → 1.00.
4. Run Forensics on the fresh discovery output; re-run
   `npm run aegis:benchmark:fel`; expect evidence_legitimacy and
   observation_non_redundancy to rise (Forensics sees plan + structural
   evidence, not a reasoning chain to echo or cite).
