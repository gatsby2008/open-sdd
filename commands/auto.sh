#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }
die() { echo "$*" >&2; exit 1; }

# ---- parse args -------------------------------------------------------------

# Only the ticket key or free-text description — nothing else. No --with-tests
# flag: whether the costly test steps run is a decision the user makes when a
# concrete risk signal fires (see step 2b), keeping the call as simple as the
# rest of the pipeline: /f-auto <ticket-or-text>.
case "${1:-}" in
  --help|-h) echo "Usage: f-auto <ticket-or-text>"; exit 0 ;;
esac

TICKET="$*"
[ -n "$TICKET" ] || die "Usage: f-auto <ticket-or-text>"

# Filled in after f-spec (step 2b) from the spec's concrete risk signals.
RISK_SIGNALS=""

export SDD_NON_INTERACTIVE=1

echo "============================================"
echo " SDD Auto-Pilot  |  Non-Interactive Mode"
echo "============================================"
echo "  Ticket:  $TICKET"
echo "============================================"
echo ""

# ---- step 1: start ----------------------------------------------------------

echo "--- [1/4] f-start / pipeline detect ---"
if engine precheck >/dev/null 2>&1; then
  echo "Existing pipeline detected — skipping /f-start and keeping current branch."
else
  bash "$SCRIPT_DIR/start.sh" "$TICKET" --confirm-branch || die "f-start failed"
fi
echo ""

# ---- step 2: spec -----------------------------------------------------------

echo "--- [2/4] f-spec ---"
bash "$SCRIPT_DIR/spec.sh" || die "f-spec failed"
echo ""

# ---- step 2b: check for blocking Open Questions -----------------------------

SLUG=$(engine resolve-slug 2>/dev/null || true)
if [ -n "$SLUG" ]; then
  OQ_OUTPUT=$(engine check "$SLUG" 2>&1 || true)
  if echo "$OQ_OUTPUT" | grep -q "UNRESOLVED_OQS"; then
    echo ""
    echo "============================================"
    echo "  BLOCKING — Unresolved Open Questions"
    echo "============================================"
    echo "$OQ_OUTPUT" | grep -A 20 "UNRESOLVED_OQS" || echo "$OQ_OUTPUT"
    echo ""
    echo "Resolve Open Questions in .specwork/_spec/${SLUG}-spec.md,"
    echo "then re-run /f-auto or continue manually."
    exit 1
  fi

  # Concrete risk signals (deterministic keyword matches — db-migration, auth,
  # data-destructive, concurrency, breaking-api), NOT the fuzzy triage tier. If
  # any fired, the LLM pauses before commit and asks whether to run the (costly)
  # test steps. No signal → flow straight through to commit/mr.
  RISK_SIGNALS=$(engine risk-signals "$SLUG" 2>/dev/null || true)
fi

# ---- step 3: plan -----------------------------------------------------------

echo "--- [3/4] f-plan ---"
bash "$SCRIPT_DIR/plan.sh" || die "f-plan failed"
echo ""

# ---- step 4: implement (display) --------------------------------------------

echo "--- [4/4] f-implement ---"
bash "$SCRIPT_DIR/implement.sh" || die "f-implement failed"
echo ""

# ---- step 5: commit ----------------------------------------------------------

echo "--- [5/6] f-commit ---"
if [ -n "$RISK_SIGNALS" ]; then
  echo "Risk signals detected; skipping optional /f-test-* steps in auto mode:"
  while IFS= read -r _sig; do
    [ -n "$_sig" ] && echo "  - $_sig"
  done <<EOF
$RISK_SIGNALS
EOF
fi
bash "$SCRIPT_DIR/commit.sh" || die "f-commit failed"
echo ""

# ---- step 6: mr --------------------------------------------------------------

echo "--- [6/6] f-mr ---"
bash "$SCRIPT_DIR/mr.sh" || die "f-mr failed"
echo ""

# ---- done --------------------------------------------------------------------

echo "============================================"
echo "  Auto mode complete"
echo "============================================"
echo "  Branch:  $(git rev-parse --abbrev-ref HEAD)"
echo "  Slug:    ${SLUG:-unknown}"
echo "  Spec:    .specwork/_spec/${SLUG:-?}-spec.md"
echo "  Plan:    .specwork/_plan/${SLUG:-?}-plan.md"
echo "============================================"
echo ""
echo "Stopped at open merge request."
echo "Do NOT run /f-close until the MR is merged."
