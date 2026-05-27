#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- step 0: pipeline precondition gate -------------------------------------

engine precheck >/dev/null 2>&1 \
  || die "No active pipeline (.specwork/ missing or uninitialized). Run ./commands/start.sh first."

# ---- load context -----------------------------------------------------------

SLUG=$(engine resolve-slug 2>/dev/null || true)
[ -n "$SLUG" ] || die "Could not resolve slug from current branch."
echo "Slug: $SLUG"

SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"

# ---- pipeline step gate ----------------------------------------------------

# Skip step gate for --done subcommand (it's a sub-operation, not a step)
if [ "${1:-}" != "--done" ]; then
  STEP_RESULT=$(engine expected-step implement "$SLUG" 2>&1) || {
    case "$STEP_RESULT" in
      NO_STATE*) die "Pipeline state missing. Run ./commands/start.sh first." ;;
      WRONG_STEP*) die "Pipeline out of order: $STEP_RESULT — run the expected step or 'engine.cli set-step implement' to override." ;;
      STEP_NOT_IN_FLOW*) die "Step 'implement' not in flow for current ticket_type: $STEP_RESULT" ;;
      *) die "Step gate failed: $STEP_RESULT" ;;
    esac
  }
fi

# ---- pre-flight gates via engine -------------------------------------------

GATES_RESULT=$(engine implement-check "$SLUG" 2>&1) || {
  case "$GATES_RESULT" in
    *MISSING*)
      die "Missing artifacts. Run ./commands/start.sh then ./commands/plan.sh."
      ;;
    *UNRESOLVED_OQS*)
      echo ""
      echo "Cannot implement — unresolved Open Questions in spec."
      echo "$GATES_RESULT"
      echo "Resolve them first, then re-run."
      exit 1
      ;;
    *NO_PLAN*)
      echo "No plan found. Run ./commands/plan.sh first."
      exit 1
      ;;
    *PLAN_STALE*)
      echo ""
      echo "Plan is stale — spec was modified after plan was created."
      echo "Run ./commands/plan.sh to regenerate."
      echo ""
      echo "  y) Re-run plan.sh now"
      echo "  n) Proceed with stale plan (not recommended)"
      echo "  q) Quit"
      read -r choice
      case "$choice" in
        y|Y) exec "$SCRIPT_DIR/plan.sh" ;;
        n|N) echo "Proceeding with stale plan." ;;
        *) exit 1 ;;
      esac
      ;;
    *)
      die "Pre-flight failed: $GATES_RESULT"
      ;;
  esac
}

# ---- load plan via engine ---------------------------------------------------

PLAN_JSON=$(engine implement-plan "$SLUG") || die "Failed to load plan."
TARGET_COUNT=$(printf '%s' "$PLAN_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
CURRENT_INDEX=$(printf '%s' "$PLAN_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['resume_index'])")
RESUME_TARGET=$(printf '%s' "$PLAN_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['resume_target'])")

TARGETS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  TARGETS+=("$line")
done < <(printf '%s' "$PLAN_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data['targets']:
    p = t.get('path', '')
    c = t.get('change', '')
    g = t.get('tags', '')
    if p:
        print(f'{p}|{c}|{g}')
")

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No target files in plan. Nothing to implement."
  exit 0
fi

echo "Plan has ${#TARGETS[@]} target files."

# ---- instructions for the LLM -----------------------------------------------

# ---- handle --done via engine ------------------------------------------------
if [ "${1:-}" = "--done" ]; then
  TARGET_NUM="${2:-}"
  [ -n "$TARGET_NUM" ] || die "Usage: ./commands/implement.sh --done N  (where N is 1-based target number)"

  DONE_RESULT=$(engine implement-done "$SLUG" "$TARGET_NUM" 2>&1) || {
    die "Failed: $DONE_RESULT"
  }

  REMAINING=$(printf '%s' "$DONE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['remaining'])")
  STATUS=$(printf '%s' "$DONE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")

  echo "Target #$TARGET_NUM marked done."
  if [ "$STATUS" = "ALL_DONE" ]; then
    # advance pipeline state: implement → test
    engine advance-step "$SLUG" >/dev/null 2>&1 || true
    echo ""
    echo "All targets implemented!"
    echo "Next: ./commands/test-impl.sh (or skip to ./commands/commit.sh)"
  else
    echo "$REMAINING target(s) remaining."
    echo "Continue with: ./commands/implement.sh"
  fi
  exit 0
fi

# ---- display spec and plan (non-done path) ----------------------------------

cat <<INSTRUCTIONS

===================================================
 IMPLEMENTATION SESSION
===================================================

You have loaded the Spec-Driven Development pipeline's implement step.
Below is the context you need to make changes.

SPEC:    $SPEC_FILE
PLAN:    .specwork/_plan/${SLUG}-plan.json
STATE:   .specwork/_state/${SLUG}-state.json
CACHE:   .specwork/_state/${SLUG}-implementation-cache.json
STACK:   $(engine detect-stack)
SLUG:    $SLUG

Resuming at target #$((CURRENT_INDEX + 1)) of ${#TARGETS[@]}.

===================================================

INSTRUCTIONS

echo "====== SPEC ======"
cat "$SPEC_FILE"
echo ""
echo "=================="
echo ""

PLAN_MD_FILE=".specwork/_plan/${SLUG}-plan.md"
if [ -f "$PLAN_MD_FILE" ]; then
  echo "====== PLAN (approach) ======"
  python3 - "$PLAN_MD_FILE" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Approach\b(.*?)(?=^## |\Z)', text)
if m:
    print(m.group(1).strip())
PY
  echo ""
  echo "=============================="
fi

echo ""
fmt_bold "Target files to modify:"

for i in "${!TARGETS[@]}"; do
  IFS='|' read -r path change _ <<< "${TARGETS[$i]}"
  if [ "$i" -lt "$CURRENT_INDEX" ]; then
    echo "  [$((i+1))] $path  — $change  [DONE]"
  else
    echo "  [$((i+1))] $path  — $change"
  fi
done

echo ""
fmt_bold "Instructions"
echo ""
echo "1. Read each target file above."
echo "2. For each file, implement the change described."
echo "3. After implementing each file, run:"
echo "     ./commands/implement.sh --done N"
echo "4. When all files are done, commit with:"
echo "     ./commands/commit.sh"
echo ""

# ---- show source context for first remaining target -------------------------

if [ "$CURRENT_INDEX" -lt "${#TARGETS[@]}" ]; then
  IFS='|' read -r first_path first_change _ <<< "${TARGETS[$CURRENT_INDEX]}"
  echo ""
  fmt_bold "=== First target: $first_path ==="
  echo "Change: $first_change"
  echo ""

  # Print key lines if file exists  
  if [ -f "$first_path" ]; then
    FIRST_LINE=$(grep -n "^[a-zA-Z]" "$first_path" 2>/dev/null | head -20 || true)
    echo "Key structural lines:"
    echo "$FIRST_LINE"
  else
    echo "(File does not exist yet — will be created.)"
  fi
fi

echo ""
fmt_bold "Ready. Follow the instructions above to implement each target."
echo "After each file, run: ./commands/implement.sh --done N"
