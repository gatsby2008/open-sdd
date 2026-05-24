#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- step 1: resolve slug ---------------------------------------------------

SLUG=""
if [ $# -ge 1 ]; then
  SLUG="$1"
else
  SLUG=$(resolve_slug 2>/dev/null || echo "")
fi

if [ -z "$SLUG" ]; then
  die "Could not resolve slug.
Usage: ./commands/handoff.sh [slug]"
fi

echo "Slug: $SLUG"

# ---- step 2: check required artifacts ---------------------------------------

STATE_FILE=".specwork/_state/${SLUG}-state.json"
RULES_FILE=".specwork/_state/${SLUG}-rules.json"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
CACHE_FILE=".specwork/_state/${SLUG}-implementation-cache.json"
PLAN_FILE=".specwork/_plan/${SLUG}-plan.md"
CONTEXT_FILE=".specwork/_progress/${SLUG}-context.md"
ESCALATIONS_FILE=".specwork/_progress/escalations.md"

MISSING=false
for f in "$STATE_FILE" "$RULES_FILE" "$SPEC_FILE"; do
  if [ ! -f "$f" ]; then
    echo "Missing: $f"
    MISSING=true
  fi
done

if [ "$MISSING" = true ]; then
  die "
No handoff generated.

Required:
  .specwork/_state/<slug>-state.json
  .specwork/_state/<slug>-rules.json
  .specwork/_spec/<slug>-spec.md

Run ./commands/start.sh first."
fi

# ---- step 3: Open Questions gate --------------------------------------------

check_oqs_file() {
  local file="$1"
  local label="$2"
  [ ! -f "$file" ] && return 0
  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
file = sys.argv[1]
label = sys.argv[2]
text = Path(file).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Open Questions\b(.*?)(?=^## |\Z)', text)
if not m:
    sys.exit(0)
section = m.group(1)
open_items = [l.strip() for l in section.splitlines() if re.match(r'^\s*-\s*\[\s\]', l)]
if open_items:
    print(f"  - {label}  ({len(open_items)} items)")
    for item in open_items:
        print(f"    {item}")
PYEOF
  python3 "$PY_SCRIPT" "$file" "$label" 2>/dev/null || true
  rm -f "$PY_SCRIPT"
}

SPEC_BLOCKERS=$(check_oqs_file "$SPEC_FILE" ".specwork/_spec/${SLUG}-spec.md")
PLAN_BLOCKERS=""
[ -f "$PLAN_FILE" ] && PLAN_BLOCKERS=$(check_oqs_file "$PLAN_FILE" ".specwork/_plan/${SLUG}-plan.md")

if [ -n "$SPEC_BLOCKERS" ] || [ -n "$PLAN_BLOCKERS" ]; then
  echo ""
  echo "No handoff generated."
  echo ""
  echo "Unresolved Open Questions:"
  [ -n "$SPEC_BLOCKERS" ] && echo "$SPEC_BLOCKERS"
  [ -n "$PLAN_BLOCKERS" ] && echo "$PLAN_BLOCKERS"
  echo ""
  die "Resolve them before creating an execution pack."
fi

# ---- step 4: load artifacts -------------------------------------------------

CACHE_CONTENT=""
[ -f "$CACHE_FILE" ] && CACHE_CONTENT=$(cat "$CACHE_FILE")

PLAN_CONTENT=""
[ -f "$PLAN_FILE" ] && PLAN_CONTENT=$(cat "$PLAN_FILE")

CONTEXT_TEXT=""
[ -f "$CONTEXT_FILE" ] && CONTEXT_TEXT=$(cat "$CONTEXT_FILE")

ESCALATIONS_TEXT=""
[ -f "$ESCALATIONS_FILE" ] && ESCALATIONS_TEXT=$(cat "$ESCALATIONS_FILE")

# ---- step 4.5: worktree freshness check (for plan) --------------------------

if [ -f "$PLAN_FILE" ]; then
  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'## Target Files\s*\n(.*?)(?=\n## |\Z)', text, re.DOTALL)
if not m:
    sys.exit(0)
new_hints = re.compile(r'\(new\)|\bnew file\b|\bcreate[sd]?\b|\bbrand[- ]new\b', re.IGNORECASE)
issues = []
for line in m.group(1).splitlines():
    if not line.startswith('|') or set(line.replace('|', '').replace(' ', '')) <= {'-', ':'}:
        continue
    parts = [c.strip() for c in line.split('|')[1:-1]]
    if len(parts) < 2 or parts[0].lower() == 'file':
        continue
    pm = re.search(r'`([^`]+)`', parts[0])
    if not pm:
        continue
    path = pm.group(1)
    if '[UNVERIFIED]' in parts[1]:
        continue
    is_new = bool(new_hints.search(parts[1]))
    exists = Path(path).exists()
    if is_new and exists:
        issues.append(f"  - `{path}` marked as new but already exists")
    elif not is_new and not exists:
        issues.append(f"  - `{path}` expected to exist but not found")
if issues:
    print("DIVERGE")
    for i in issues:
        print(i)
PYEOF
  FRESHNESS=$(python3 "$PY_SCRIPT" "$PLAN_FILE" 2>/dev/null || echo "FAIL")
  rm -f "$PY_SCRIPT"

  if echo "$FRESHNESS" | grep -q "DIVERGE"; then
    echo "Worktree diverges from plan — pack not generated."
    echo "$FRESHNESS" | grep -v "DIVERGE" || true
    echo ""
    die "Run ./commands/plan.sh to regenerate, then re-run ./commands/handoff.sh."
  fi
fi

# ---- step 5: build execution pack -------------------------------------------

HANDOFF_DIR=".specwork/_handoff"
mkdir -p "$HANDOFF_DIR"
PACK_FILE="${HANDOFF_DIR}/${SLUG}-execution-pack.md"

# Extract summary from spec
PY_SCRIPT=$(mktemp)
cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Summary\s*\n(.*?)(?=\n## |\Z)', text)
print(m.group(1).strip()[:200] if m else "[UNKNOWN]")
PYEOF
SUMMARY=$(python3 "$PY_SCRIPT" "$SPEC_FILE" 2>/dev/null || echo "[UNKNOWN]")
rm -f "$PY_SCRIPT"

# Extract primary class
PY_SCRIPT=$(mktemp)
cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Implementation Context\s*\n(.*?)(?=\n## |\Z)', text)
if m:
    tokens = re.findall(r'`([^`]+)`', m.group(1))
    if tokens:
        print(tokens[0])
    else:
        print("[UNKNOWN]")
else:
    print("[UNKNOWN]")
PYEOF
PRIMARY_CLASS=$(python3 "$PY_SCRIPT" "$SPEC_FILE" 2>/dev/null || echo "[UNKNOWN]")
rm -f "$PY_SCRIPT"

# Detect behavioral change signals
PY_SCRIPT=$(mktemp)
cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
spec = Path(sys.argv[1]).read_text(encoding="utf-8").lower()
signals = []
pairs = [
    ("idempotent", r'\bidempotent(ly)?\b'),
    ("no-op", r'\bno[- ]op\b'),
    ("no longer", r'\bno longer\b'),
    ("instead of", r'\binstead of\b'),
    ("remove existing", r'\bremove[s]?\s+(the\s+)?existing\b'),
    ("short-circuit", r'\bshort[- ]circuit\b'),
    ("replace the", r'\breplace[sd]?\s+the\s+\w+'),
]
for label, pat in pairs:
    if re.search(pat, spec):
        signals.append(label)
for s in signals:
    print(s)
PYEOF
BEHAVIOR_SIGNALS=$(python3 "$PY_SCRIPT" "$SPEC_FILE" 2>/dev/null || true)
rm -f "$PY_SCRIPT"

BEHAVIOR_WARNING=""
if [ -n "$BEHAVIOR_SIGNALS" ]; then
  BEHAVIOR_WARNING="true"
fi

# Write the pack
{
  echo "# Execution Pack: ${SLUG}"
  echo ""
  echo "> Generated by open-sdd handoff.sh"
  echo "> Purpose: model-agnostic implementation capsule"
  echo ""
  echo "## Role"
  echo ""
  echo "You are implementing an existing feature spec in an existing codebase."
  echo "Do not re-analyze the problem from scratch."
  echo "Do not infer missing business rules."
  echo "If something is ambiguous, stop and report Open Questions."
  echo ""

  if [ -n "$BEHAVIOR_WARNING" ]; then
    echo "## Behavioral Change Warning"
    echo ""
    echo "⚠ This spec implies modifications to existing behavior. Detected signals:"
    echo "$BEHAVIOR_SIGNALS" | while IFS= read -r signal; do
      echo "- $signal"
    done
    echo ""
  fi

  echo "## Execution Summary"
  echo ""
  echo "**Goal**: $SUMMARY"
  echo "**Primary class/service**: $PRIMARY_CLASS"
  echo ""
  echo "**Main behavior**:"
  # Extract Behavior section
  python3 - "$SPEC_FILE" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Behavior\s*\n(.*?)(?=\n## |\Z)', text)
if m:
    lines = m.group(1).strip().splitlines()
    for l in lines[:15]:
        print(l)
PY
  echo ""

  echo "## Known Architecture Context"
  echo ""
  if [ -n "$CACHE_CONTENT" ]; then
    python3 - "$CACHE_FILE" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
cls = d.get("similar_classes", [])
repos = d.get("repositories", [])
tests = d.get("related_tests", [])
patterns = d.get("patterns", [])
if cls: print(f"**Primary classes**: {', '.join(cls[:5])}")
if repos: print(f"**Repositories**: {', '.join(repos[:5])}")
if patterns: print(f"**Patterns**:")
for p in patterns[:5]: print(f"- {p}")
if tests: print(f"**Related tests**:")
for t in tests[:5]: print(f"- {t}")
if not cls and not repos: print("No prior implementation context cached.")
PY
  else
    echo "No prior implementation context cached."
  fi
  echo ""

  echo "## Expected Change Scope"
  echo ""
  python3 - "$SPEC_FILE" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Expected Change Scope\s*\n(.*?)(?=\n## |\Z)', text)
if m: print(m.group(1).strip())
else: print("(not specified)")
PY
  echo ""

  echo "## Safe Constraints"
  echo ""
  python3 - "$SPEC_FILE" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Safe Constraints\s*\n(.*?)(?=\n## |\Z)', text)
if m: print(m.group(1).strip())
else: print("(not specified)")
PY
  echo ""

  echo "## Execution Budget"
  echo ""
  echo "- Avoid repository-wide scans."
  echo "- Avoid broad refactors."
  echo "- Prefer focused diffs."
  echo "- Escalate if the implementation expands beyond Expected Change Scope."
  echo ""

  echo "## Failure Handling"
  echo ""
  echo "- Retry direct implementation failures: max 2 attempts."
  echo "- Test setup failures: max 1 retry."
  echo "- Escalate infrastructure/environment failures immediately."
  echo "- Never rewrite unrelated infrastructure to make a test pass."
  echo ""

  echo "## Plan"
  echo ""
  if [ -n "$PLAN_CONTENT" ]; then
    echo "$PLAN_CONTENT"
  else
    echo "_(No plan — proceed from spec directly)_"
  fi
  echo ""

  echo "## Spec"
  echo ""
  echo "$SPEC_CONTENT"
  echo ""

  if [ -n "$CONTEXT_TEXT" ]; then
    echo "## Focused Context"
    echo ""
    echo "$CONTEXT_TEXT"
    echo ""
  fi

  if [ -n "$ESCALATIONS_TEXT" ]; then
    echo "## Known Blockers / Escalations"
    echo ""
    echo "$ESCALATIONS_TEXT"
    echo ""
  fi

  echo "## Expected Response From Executor"
  echo ""
  echo "Return:"
  echo ""
  echo "1. Files changed (paths)"
  echo "2. Summary of implementation (≤5 lines)"
  echo "3. Tests added or updated"
  echo "4. Tests executed and results"
  echo "5. Assumptions made (if any)"
  echo "6. Any unresolved questions or blockers"
} > "$PACK_FILE"

# ---- step 6: build JSON summary ---------------------------------------------

PACK_SIZE=$(wc -c < "$PACK_FILE" | tr -d ' ')

JSON_FILE="${HANDOFF_DIR}/${SLUG}-execution-pack.json"

cat > "$JSON_FILE" <<ENDJSON
{
  "id": "${SLUG}",
  "state_file": "${STATE_FILE}",
  "rules_file": "${RULES_FILE}",
  "spec_file": "${SPEC_FILE}",
  "plan_file": $( [ -f "$PLAN_FILE" ] && echo "\"${PLAN_FILE}\"" || echo "null" ),
  "cache_file": $( [ -f "$CACHE_FILE" ] && echo "\"${CACHE_FILE}\"" || echo "null" ),
  "execution_pack_file": "${PACK_FILE}",
  "pack_size_bytes": ${PACK_SIZE},
  "status": "ready",
  "open_questions_resolved": true,
  "sections_included": {
    "known_architecture_context": $( [ -n "$CACHE_CONTENT" ] && echo "true" || echo "false" ),
    "plan": $( [ -n "$PLAN_CONTENT" ] && echo "true" || echo "false" ),
    "behavioral_change_warning": $( [ -n "$BEHAVIOR_WARNING" ] && echo "true" || echo "false" ),
    "focused_context": $( [ -n "$CONTEXT_TEXT" ] && echo "true" || echo "false" ),
    "escalations": $( [ -n "$ESCALATIONS_TEXT" ] && echo "true" || echo "false" )
  },
  "worktree_freshness": "ok"
}
ENDJSON

# ---- step 7: summary --------------------------------------------------------

echo ""
echo "Handoff pack created."
echo ""
echo "  Pack:  $PACK_FILE"
echo "  JSON:  $JSON_FILE"
echo "  Size:  ${PACK_SIZE} bytes"
echo ""
echo "Use this pack with another agent/LLM as an implementation contract."
echo "Paste the contents of $PACK_FILE into the executor's context."
