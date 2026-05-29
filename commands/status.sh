#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

# ---- resolve context --------------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
SLUG=$(resolve_slug 2>/dev/null || echo "")
echo "Branch: $BRANCH"

# ---- locate artifacts -------------------------------------------------------

STATE_FILE=""
SPEC_FILE=""
PLAN_FILE=""
SPEC_ABS=""
PLAN_ABS=""

if [ -n "$SLUG" ]; then
  STATE_FILE=".specwork/_state/${SLUG}-state.json"
  SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
  PLAN_FILE=".specwork/_plan/${SLUG}-plan.md"
fi

# Count open / resolved OQs in a given markdown file
count_oqs() {
  local file="$1"
  [ -f "$file" ] || { echo "0 0"; return 0; }
  python3 - "$file" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Open Questions\b(.*?)(?=^## |\Z)', text)
if not m:
    print("0 0")
    sys.exit(0)
section = m.group(1)
open_count = len(re.findall(r'^\s*-\s*\[\s\]', section, re.MULTILINE))
resolved_count = len(re.findall(r'^\s*-\s*\[[xX]\]', section, re.MULTILINE))
print(f"{open_count} {resolved_count}")
PY
}

# ---- render status lines ----------------------------------------------------

# Spec
if [ -n "$SPEC_FILE" ] && [ -f "$SPEC_FILE" ]; then
  read -r spec_open spec_resolved <<< "$(count_oqs "$SPEC_FILE")"
  SPEC_ABS="$(cd "$(dirname "$SPEC_FILE")" 2>/dev/null && pwd)/$(basename "$SPEC_FILE")"
  if [ "$spec_open" -gt 0 ]; then
    spec_line=$(grep -n "^## Open Questions" "$SPEC_FILE" | head -1 | cut -d: -f1)
    echo "Spec:   ✓ $(basename "$SPEC_FILE") (${spec_open} open / ${spec_resolved} resolved OQs)"
    [ -n "$spec_line" ] && echo "        \`${SPEC_ABS}:${spec_line}\`  ← Open Questions"
  else
    echo "Spec:   ✓ $(basename "$SPEC_FILE") (${spec_resolved} resolved OQs)"
  fi
else
  echo "Spec:   ×"
fi

# Plan
if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
  read -r plan_open plan_resolved <<< "$(count_oqs "$PLAN_FILE")"
  PLAN_ABS="$(cd "$(dirname "$PLAN_FILE")" 2>/dev/null && pwd)/$(basename "$PLAN_FILE")"
  if [ "$plan_open" -gt 0 ]; then
    plan_line=$(grep -n "^## Open Questions" "$PLAN_FILE" | head -1 | cut -d: -f1)
    echo "Plan:   ✓ $(basename "$PLAN_FILE") (${plan_open} open / ${plan_resolved} resolved OQs)"
    [ -n "$plan_line" ] && echo "        \`${PLAN_ABS}:${plan_line}\`  ← Open Questions"
  else
    echo "Plan:   ✓ $(basename "$PLAN_FILE") (${plan_resolved} resolved OQs)"
  fi
else
  echo "Plan:   ×"
fi

# Review verdict
REVIEW_DIR=".specwork/_review"
if [ -d "$REVIEW_DIR" ]; then
  VERDICT_FILE=$(find "$REVIEW_DIR" -type f -name "*.md" 2>/dev/null | head -1)
  if [ -n "$VERDICT_FILE" ]; then
    VERDICT=$(grep -iE "^(verdict|review|result):" "$VERDICT_FILE" 2>/dev/null | head -1 | cut -d: -f2- | xargs || true)
    if [ -n "$VERDICT" ]; then
      echo "Review: $(echo "$VERDICT" | tr '[:lower:]' '[:upper:]')"
    else
      echo "Review: ✓"
    fi
  fi
fi

# Git tree status
GIT_TREE=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$GIT_TREE" -eq 0 ]; then
  echo "Tree:   clean"
else
  echo "Tree:   ${GIT_TREE} dirty"
fi

# Recent commits
RECENT=$(git log --oneline -3 2>/dev/null || true)
if [ -n "$RECENT" ]; then
  echo ""
  echo "Recent commits:"
  echo "$RECENT" | while IFS= read -r line; do echo "  $line"; done
fi

# ---- read ticket_type (from triage; used to bias recommendation) ------------

TICKET_TYPE=""
if [ -f "$STATE_FILE" ]; then
  TICKET_TYPE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('ticket_type',''))" 2>/dev/null || echo "")
  : "${TICKET_TYPE:=feature}"
  echo ""
  echo "Flow:   ${TICKET_TYPE}"
fi

# ---- Check for ADR warnings -------------------------------------------------

ADR_WARN=""
if [ -d "docs/adr" ]; then
  ADR_UNCOMMITTED=$(git status --porcelain "docs/adr/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$ADR_UNCOMMITTED" -gt 0 ] && ADR_WARN="true"
fi

# ---- Next step determination (artifact-driven) ------------------------------
#
# Decision tree based on which artifacts exist + git state. No current_step:
# the pipeline derives "what's next" from the file graph, not a state machine.
#
#   .specwork/ missing           → /f-start
#   no spec.md                   → /f-spec  (drafting)
#   spec.md has open OQs         → resolve_oqs
#   no plan.md AND ticket needs plan (high-risk/standard) → /f-plan
#   no plan.md AND ticket can skip plan                   → /f-implement
#   plan.md stale (spec ts > plan mtime)                  → /f-plan (refresh)
#   plan.md has open OQs                                  → resolve_oqs
#   working tree dirty + staged                           → /f-commit
#   working tree dirty + unstaged                         → /f-implement
#   working tree clean + commits ahead of base            → /f-mr
#   otherwise                                             → /f-implement

NEXT=""

PLAN_STALE=false
if [ -f "$PLAN_FILE" ] && [ -f "$STATE_FILE" ]; then
  P_MTIME=$(stat -f %m "$PLAN_FILE" 2>/dev/null || stat -c %Y "$PLAN_FILE" 2>/dev/null || echo "0")
  S_TS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('spec_write_timestamp',0))" 2>/dev/null || echo "0")
  if [ "$P_MTIME" != "0" ] && [ "$S_TS" != "0" ] && [ "$P_MTIME" -lt "$S_TS" ]; then
    PLAN_STALE=true
  fi
fi

if [ ! -f "$STATE_FILE" ]; then
  NEXT="/f-start"
elif [ ! -f "$SPEC_FILE" ]; then
  NEXT="/f-spec"
elif [ "${spec_open:-0}" -gt 0 ] || [ "${plan_open:-0}" -gt 0 ]; then
  NEXT="resolve_oqs"
elif [ ! -f "$PLAN_FILE" ]; then
  if [ "$TICKET_TYPE" = "high-risk" ] || [ "$TICKET_TYPE" = "standard" ]; then
    NEXT="/f-plan"
  else
    NEXT="/f-implement"
  fi
elif [ "$PLAN_STALE" = "true" ]; then
  NEXT="/f-plan (refresh — spec is newer)"
elif [ "$GIT_TREE" -gt 0 ]; then
  STAGED=$(git diff --cached --stat 2>/dev/null | wc -l | tr -d ' ')
  if [ "$STAGED" -gt 0 ]; then
    NEXT="/f-commit"
  else
    NEXT="/f-implement"
  fi
else
  COMMITS_AHEAD=$(git log --oneline "${BRANCH}" ^"$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo origin/main)" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [ "$COMMITS_AHEAD" -gt 0 ]; then
    NEXT="/f-mr"
  else
    NEXT="/f-implement"
  fi
fi

# ---- print next step ---------------------------------------------------------

echo ""
case "$NEXT" in
  resolve_oqs)
    if [ -n "$SPEC_ABS" ] && [ -n "${spec_line:-}" ]; then
      echo "Next:   Resolve Open Questions at \`${SPEC_ABS}:${spec_line}\`"
    elif [ -n "$PLAN_ABS" ] && [ -n "${plan_line:-}" ]; then
      echo "Next:   Resolve Open Questions at \`${PLAN_ABS}:${plan_line}\`"
    else
      echo "Next:   Resolve Open Questions first"
    fi
    ;;
  /f-plan|/f-implement|/f-test-design|/f-test-impl|/f-commit|/f-mr|/f-start)
    echo "Next:   $NEXT"
    ;;
  *)
    echo "Next:   $NEXT"
    ;;
esac

# ADR warning
if [ -n "$ADR_WARN" ]; then
  echo ""
  echo "ADR:    Uncommitted files in docs/adr/"
fi
