#!/usr/bin/env bash
set -e

scenario="$1"

AEGIS_INVESTIGATION_INPUT="analyze repository topology" \
bash runtime_aegis.sh discovery \
"tests/scenarios/${scenario}"

cp .harness/runtime/epistemic_handover.json \
"/tmp/${scenario}_discovery.json"

bash runtime_aegis.sh forensics

cp .harness/runtime/epistemic_handover.json \
"/tmp/${scenario}_forensics.json"

diff \
  <(jq -S 'del(.. | .generated_at?, .summary?, .observations?, .findings?, .interpretations?, .unresolved_questions?, .reason?, .attention_reason?, .attention_scope?, .operational_observations?, .rationale?, .recommended_next_actions?, .required_evidence?, .escalation_reason?, .repair_candidates?, .next_attention_targets?, .confidence?, .status?, .investigation_hypotheses?, .investigation_risks?, .evidence_priorities?, .confidence_drivers?)' "/tmp/${scenario}_discovery.json") \
  <(jq -S 'del(.. | .generated_at?, .summary?, .observations?, .findings?, .interpretations?, .unresolved_questions?, .reason?, .attention_reason?, .attention_scope?, .operational_observations?, .rationale?, .recommended_next_actions?, .required_evidence?, .escalation_reason?, .repair_candidates?, .next_attention_targets?, .confidence?, .status?, .investigation_hypotheses?, .investigation_risks?, .evidence_priorities?, .confidence_drivers?)' "tests/golden/${scenario}/golden_discovery.json")

diff \
  <(jq -S 'del(.. | .generated_at?, .summary?, .observations?, .findings?, .interpretations?, .unresolved_questions?, .reason?, .attention_reason?, .attention_scope?, .operational_observations?, .rationale?, .recommended_next_actions?, .required_evidence?, .escalation_reason?, .repair_candidates?, .next_attention_targets?, .confidence?, .status?, .investigation_hypotheses?, .investigation_risks?, .evidence_priorities?, .confidence_drivers?)' "/tmp/${scenario}_forensics.json") \
  <(jq -S 'del(.. | .generated_at?, .summary?, .observations?, .findings?, .interpretations?, .unresolved_questions?, .reason?, .attention_reason?, .attention_scope?, .operational_observations?, .rationale?, .recommended_next_actions?, .required_evidence?, .escalation_reason?, .repair_candidates?, .next_attention_targets?, .confidence?, .status?, .investigation_hypotheses?, .investigation_risks?, .evidence_priorities?, .confidence_drivers?)' "tests/golden/${scenario}/golden_forensics.json")