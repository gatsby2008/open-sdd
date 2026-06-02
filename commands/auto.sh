#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }
die() { echo "$*" >&2; exit 1; }

# ---- parse args -------------------------------------------------------------

# Only the ticket key or free-text description — nothing else. No --with-tests
# flag: auto mode always pauses before commit for manual review, so whether to
# run the costly test steps is a decision the user makes during that handoff —
# keeping the call as simple as the rest of the pipeline: /f-auto <ticket-or-text>.
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

echo "--- [1/5] f-start / pipeline detect ---"
# start.sh's --confirm-branch prompt is TTY-gated, so it only fires for a human
# running this script in a terminal. An agent driving /f-auto must confirm the
# branch itself FIRST (see the /auto section in agent/PIPELINE.md) and run
# start.sh; by the time it gets here a pipeline exists and precheck skips start.
if engine precheck >/dev/null 2>&1; then
  echo "Existing pipeline detected — skipping /f-start and keeping current branch."
else
  bash "$SCRIPT_DIR/start.sh" "$TICKET" --confirm-branch || die "f-start failed"
fi
echo ""

# ---- step 2: spec -----------------------------------------------------------

echo "--- [2/5] f-spec ---"
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
  # data-destructive, concurrency, breaking-api), NOT the fuzzy triage tier.
  # Auto mode always pauses before commit, so these are surfaced informationally
  # at the handoff to help the user decide whether to run the (costly) test steps.
  RISK_SIGNALS=$(engine risk-signals "$SLUG" 2>/dev/null || true)
fi

# ---- step 3: plan -----------------------------------------------------------

echo "--- [3/5] f-plan ---"
bash "$SCRIPT_DIR/plan.sh" || die "f-plan failed"
echo ""

# ---- step 4: implement (display) --------------------------------------------

echo "--- [4/5] f-implement ---"
bash "$SCRIPT_DIR/implement.sh" || die "f-implement failed"
echo ""

# ---- step 5: handoff to commit+mr -------------------------------------------

echo "--- [5/5] handoff: stop before f-commit ---"
if [ -n "$SLUG" ] && [ -f ".specwork/_state/${SLUG}-state.json" ]; then
  python3 - "$SLUG" <<'PY'
import json, sys
from pathlib import Path
slug = sys.argv[1]
state_path = Path(".specwork/_state") / f"{slug}-state.json"
d = json.loads(state_path.read_text(encoding="utf-8"))
d["auto_open_mr_after_commit"] = True
state_path.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
PY
fi
if [ -n "$RISK_SIGNALS" ]; then
  echo "Risk signals detected during spec analysis:"
  while IFS= read -r _sig; do
    [ -n "$_sig" ] && echo "  - $_sig"
  done <<EOF
$RISK_SIGNALS
EOF
fi
echo "Auto mode paused before /f-commit so you can review changes."
echo ""

# ---- done --------------------------------------------------------------------

echo "============================================"
echo "  Auto mode paused"
echo "============================================"
echo "  Branch:  $(git rev-parse --abbrev-ref HEAD)"
echo "  Slug:    ${SLUG:-unknown}"
echo "  Spec:    .specwork/_spec/${SLUG:-?}-spec.md"
echo "  Plan:    .specwork/_plan/${SLUG:-?}-plan.md"
echo "============================================"
echo ""
echo "Next: run /f-commit after your review."
echo "When this run comes from /f-auto, /f-commit will open/update the MR automatically."
echo "Do NOT run /f-close until the MR is merged."
