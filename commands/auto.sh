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

# ---- done — hand off to the LLM ---------------------------------------------

echo ""
echo "============================================"
echo "  Pipeline setup complete"
echo "============================================"
echo "  Branch:  $(git rev-parse --abbrev-ref HEAD)"
echo "  Slug:    ${SLUG:-unknown}"
echo "  Spec:    .specwork/_spec/${SLUG:-?}-spec.md"
echo "  Plan:    .specwork/_plan/${SLUG:-?}-plan.md"
echo "============================================"
echo ""
echo "Implement all targets from the plan above."
echo "After each target, run:  implement.sh --done N"
echo ""
if [ -n "$RISK_SIGNALS" ]; then
echo "============================================"
echo "  RISK SIGNAL — decide on tests before commit"
echo "============================================"
echo "  Concrete risk signals in this spec:"
while IFS= read -r _sig; do
  [ -n "$_sig" ] && echo "    - $_sig"
done <<EOF
$RISK_SIGNALS
EOF
echo ""
echo "  When all targets are done, STOP and ask the user:"
echo "    run test-design.sh + test-impl.sh now, or skip to commit?"
echo "  Do NOT run the test steps without the user's go-ahead — they are costly."
echo "  Then:  commit.sh  ->  mr.sh   <-- auto mode ends here"
else
echo "No concrete risk signals — proceed straight through when targets are done:"
echo "  1. commit.sh"
echo "  2. mr.sh   <-- auto mode ends here"
fi
echo ""
echo "Auto mode stops at the open merge request. Do NOT run close.sh"
echo "(deletes the branch; post-merge) or mr-address.sh (needs review comments)."
echo "Hand control back to the user for review / merge / close."
echo ""
echo "All commands run in non-interactive mode."
echo "Export SDD_NON_INTERACTIVE=1 if calling manually."
