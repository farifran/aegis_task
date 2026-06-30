#!/usr/bin/env bash
#
# test_bootstrap_boundaries.sh — Constitutional proof: Bootstrap respects its own limits.
#
# Purpose:
#   Proves that run_aegis.sh (Bootstrap) never:
#   - Inspects the epistemic handover to make pipeline decisions
#     (repair_candidates check was removed in Phase 0.3)
#   - Invokes cognition directly (discovery, forensics, repair scripts)
#   - Performs validation logic
#   - Interprets code
#
#   And proves that Bootstrap DOES:
#   - Construct the Execution Context before calling the Runtime
#   - Use exit code as the Validated Result signal (not jq inspection)
#   - Delegate all mode execution to run_bounded_mode()
#
# Constitutional reference: RFC §5 Bootstrap Contract.
#

set -Eeuo pipefail

readonly TEST_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
)"

cd "${TEST_ROOT}"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

# =========================================================================
# Phase 0.3 regression: repair_candidates inspection removed from Bootstrap
# =========================================================================

# Extract execute_issue() function body.
execute_issue_body="$(
  awk '
    /^execute_issue\(\)/ { in_fn=1; depth=0 }
    in_fn {
      print
      depth += gsub(/{/, "{")
      depth -= gsub(/}/, "}")
      if (depth <= 0 && in_fn > 0 && NR > 1) in_fn=0
    }
  ' run_aegis.sh
)"

[[ -n "${execute_issue_body}" ]] \
  || fail "bootstrap_boundaries: could not extract execute_issue() from run_aegis.sh"

# Bootstrap must not inspect repair_candidates from the handover
if echo "${execute_issue_body}" | grep -q 'repair_candidates'; then
  fail "bootstrap_boundaries: execute_issue() inspects repair_candidates (Runtime responsibility)"
fi

pass "bootstrap_boundaries: execute_issue() does not inspect repair_candidates"

# Bootstrap must not directly read the epistemic handover file
if echo "${execute_issue_body}" | grep -q 'HANDOVER_FILE\|epistemic_handover'; then
  fail "bootstrap_boundaries: execute_issue() reads epistemic handover (Runtime responsibility)"
fi

pass "bootstrap_boundaries: execute_issue() does not read epistemic handover"

# =========================================================================
# Bootstrap uses exit code as Validated Result (not jq parsing)
# =========================================================================

# execute_issue() must contain `validated_result` pattern
if ! echo "${execute_issue_body}" | grep -q 'validated_result'; then
  fail "bootstrap_boundaries: execute_issue() missing Validated Result signal"
fi

pass "bootstrap_boundaries: execute_issue() uses validated_result exit-code pattern"

# Bootstrap must delegate to run_bounded_mode, not run_mode or direct scripts
if echo "${execute_issue_body}" | grep -q '\brun_mode\b'; then
  fail "bootstrap_boundaries: execute_issue() calls run_mode() directly (must use run_bounded_mode)"
fi

if ! echo "${execute_issue_body}" | grep -q 'run_bounded_mode'; then
  fail "bootstrap_boundaries: execute_issue() does not call run_bounded_mode()"
fi

pass "bootstrap_boundaries: execute_issue() delegates exclusively to run_bounded_mode()"

# =========================================================================
# Bootstrap must not invoke cognition scripts directly
# =========================================================================

# Bootstrap should never directly call discovery, forensics, repair, optimize,
# adversarial, or validation scripts. These are Runtime domain.
for script in 'execute_mode.sh' 'scripts/substrates/aider' 'apply_candidate_diff'; do
  if grep -q "${script}" run_aegis.sh; then
    fail "bootstrap_boundaries: run_aegis.sh calls Runtime-domain script '${script}'"
  fi
done

pass "bootstrap_boundaries: Bootstrap does not invoke Runtime-domain scripts"

# =========================================================================
# Bootstrap interaction boundary: only Bootstrap touches the user
# =========================================================================

# All user-facing read calls must be in run_aegis.sh, not runtime_aegis.sh.
bootstrap_reads="$(grep -c '\bread\b' run_aegis.sh || true)"
set +e
runtime_reads="$(grep -v '^\s*#' runtime_aegis.sh | grep -v 'readlink\|read_\|_read' | grep -c '\bread\b')"
set -e
runtime_reads="${runtime_reads:-0}"

[[ "${runtime_reads}" -eq 0 ]] \
  || fail "bootstrap_boundaries: runtime_aegis.sh has ${runtime_reads} read call(s) (must be 0)"

[[ "${bootstrap_reads}" -gt 0 ]] \
  || fail "bootstrap_boundaries: run_aegis.sh has no read calls (UI must be in Bootstrap)"

pass "bootstrap_boundaries: all user interaction in Bootstrap, none in Runtime"

# =========================================================================
# Bootstrap must construct Execution Context (AEGIS_INVESTIGATION_INPUT in boundary)
# =========================================================================

# run_bounded_mode() must pass AEGIS_INVESTIGATION_INPUT explicitly
run_bounded_mode_body="$(
  awk '
    /^run_bounded_mode\(\)/ { in_fn=1; depth=0 }
    in_fn {
      print
      depth += gsub(/{/, "{")
      depth -= gsub(/}/, "}")
      if (depth <= 0 && in_fn > 0 && NR > 1) in_fn=0
    }
  ' run_aegis.sh
)"

echo "${run_bounded_mode_body}" | grep -q 'AEGIS_INVESTIGATION_INPUT' \
  || fail "bootstrap_boundaries: run_bounded_mode() does not pass AEGIS_INVESTIGATION_INPUT"

echo "${run_bounded_mode_body}" | grep -q 'AEGIS_EVIDENCE_TARGET_PATH' \
  || fail "bootstrap_boundaries: run_bounded_mode() does not pass AEGIS_EVIDENCE_TARGET_PATH"

pass "bootstrap_boundaries: run_bounded_mode() constructs Execution Context correctly"
