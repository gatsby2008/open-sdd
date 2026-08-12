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
  MR_JSON_FILE=".specwork/_state/${SLUG}-mr.json"
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

# Stale leftovers: pipelines from OTHER branches whose work already landed.
# .specwork/ is gitignored, so a merged feature whose /f-close was never run
# keeps sitting here and later blocks /f-start. Surface it while orienting
# rather than letting it be discovered as a refusal. Printed only when there is
# something to report, and never as a blocker — Next: is unaffected.
STALE=$(PYTHONPATH="$(cd "$SCRIPT_DIR/.." && pwd)" python3 - <<'PY' 2>/dev/null || true
import json, subprocess, sys
try:
    out = subprocess.run([sys.executable, "-m", "engine.cli", "pipeline-inventory"],
                         capture_output=True, text=True, timeout=15)
    closable = (json.loads(out.stdout or "{}") or {}).get("closable") or []
except Exception:
    closable = []
if closable:
    n = len(closable)
    print("Stale:  %d orphan pipeline%s in .specwork/ — %s work already landed"
          % (n, "" if n == 1 else "s", "its" if n == 1 else "their"))
    for p in closable:
        why = ("merged into %s" % p["base_branch"]) if p["merge_status"] == "merged" \
              else "branch no longer exists locally"
        print("        • %s (%s) — %s" % (p["slug"], p["branch"] or "?", why))
    print("        Clear %s from its own branch, or from its base, with /f-close."
          % ("it" if n == 1 else "each"))
PY
)
[ -n "$STALE" ] && printf '%s\n' "$STALE"

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
#   working tree dirty (staged or unstaged)               → /f-commit
#   working tree clean + commits ahead of base (no MR)    → /f-mr
#   working tree clean + commits ahead of base (MR exists)→ /f-mr-address
#   otherwise                                             → /f-implement

NEXT=""

PLAN_STALE=false
if [ -f "$PLAN_FILE" ] && [ -f "$STATE_FILE" ]; then
  P_MTIME=$(stat -c %Y "$PLAN_FILE" 2>/dev/null || stat -f %m "$PLAN_FILE" 2>/dev/null || echo "0")
  S_TS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('spec_write_timestamp',0))" 2>/dev/null || echo "0")
  if [ "$P_MTIME" != "0" ] && [ "$S_TS" != "0" ] && [ "$P_MTIME" -lt "$S_TS" ]; then
    PLAN_STALE=true
  fi
fi

MR_URL=""
if [ -f "${MR_JSON_FILE:-}" ]; then
  MR_URL=$(python3 -c "import json; print(json.load(open('${MR_JSON_FILE}')).get('url',''))" 2>/dev/null || echo "")
fi

if [ ! -f "$STATE_FILE" ]; then
  NEXT="/f-start"
elif [ -f "${MR_JSON_FILE:-}" ]; then
  # Priority 1: MR already created — address it before anything else
  NEXT="/f-mr-address"
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
  NEXT="/f-commit"
else
  BASE_BRANCH=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('base_branch','development'))" 2>/dev/null || echo "development")
  COMMITS_AHEAD=$(git log --oneline "${BRANCH}" ^"origin/${BASE_BRANCH}" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
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
  /f-plan)
    echo "Next:   $NEXT (recommended, can skip)"
    echo "        /f-implement"
    ;;
  /f-implement|/f-test-design|/f-test-impl|/f-commit|/f-start|/f-spec)
    echo "Next:   $NEXT"
    ;;
  /f-mr-address)
    echo "Next:   $NEXT"
    [ -n "$MR_URL" ] && echo "MR:     $MR_URL"
    ;;
  /f-mr)
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
