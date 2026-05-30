#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

append_escalation() {
  local area="$1" error_text="$2" attempted_fixes="$3" recommended="$4"
  local progress_dir=".specwork/_progress"
  local escalations_file="$progress_dir/escalations.md"
  local today
  today="$(date '+%Y-%m-%d')"

  mkdir -p "$progress_dir"
  cat >> "$escalations_file" <<EOF
## ${today} — ${area}

- Failing test/component: ${area}
- Error: ${error_text}
- Attempted fixes: ${attempted_fixes}
- Recommended: ${recommended}

EOF

  echo ""
  echo "Escalation logged to: $escalations_file"
}

# ---- step 0: pipeline precondition gate -------------------------------------

engine precheck >/dev/null 2>&1 \
  || die "No active pipeline (.specwork/ missing or uninitialized). Run /f-start first."

# ---- load context -----------------------------------------------------------

SLUG=$(engine resolve-slug 2>/dev/null || true)
[ -n "$SLUG" ] || die "Could not resolve slug from current branch."
echo "Slug: $SLUG"

SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"

# ---- escalation logging mode -------------------------------------------------

if [ "${1:-}" = "--escalate" ]; then
  AREA="${2:-}"
  ERROR_TEXT="${3:-persistent failure (details not provided)}"
  ATTEMPTED_FIXES="${4:-n/a}"
  RECOMMENDED="${5:-human review}"

  [ -n "$AREA" ] || die "Usage: ./commands/implement.sh --escalate \"<failing area>\" [\"<error excerpt>\"] [\"<attempted fixes>\"] [\"<recommended next step>\"]"
  append_escalation "$AREA" "$ERROR_TEXT" "$ATTEMPTED_FIXES" "$RECOMMENDED"
  exit 0
fi

# /f-implement is re-runnable. Artifact gates below (implement-check: spec
# exists, no unresolved OQs, plan not stale) are the only preconditions.
# Calling /f-implement again after /f-commit (to add more steps) or after
# /f-spec refresh (bumps spec_write_ts → triggers staleness gate) is fine.

# ---- pre-flight gates via engine -------------------------------------------

GATES_RESULT=$(engine implement-check "$SLUG" 2>&1) || {
  case "$GATES_RESULT" in
    *MISSING*)
      die "Missing artifacts. Run /f-start then /f-plan."
      ;;
    *UNRESOLVED_OQS*)
      echo ""
      echo "Cannot implement — unresolved Open Questions in spec."
      echo "$GATES_RESULT"
      echo "Resolve them first, then re-run."
      exit 1
      ;;
    *PLAN_STALE*)
      echo ""
      echo "Plan is stale — spec was modified after plan was created."
      if [ "${SDD_NON_INTERACTIVE:-0}" = "1" ]; then
        echo "Non-interactive: re-running /f-plan automatically."
        exec "$SCRIPT_DIR/plan.sh"
      fi
      echo "Run /f-plan to regenerate."
      echo ""
      echo "  y) Re-run /f-plan now"
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

NO_PLAN_MODE=false
if [ ${#TARGETS[@]} -eq 0 ]; then
  # No plan present (or plan exists but has no targets). Switch to no-plan
  # workflow: the LLM does inline discovery from the spec instead of following
  # a target table. Common path for small/obvious changes that skipped /f-plan.
  NO_PLAN_MODE=true
  echo "No plan present — entering no-plan workflow (inline discovery from spec)."
else
  echo "Plan has ${#TARGETS[@]} target files."
fi

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
    echo ""
    echo "All targets implemented!"
    echo "Next: /f-test-impl (or skip to /f-commit)"
  else
    echo "$REMAINING target(s) remaining."
    echo "Continue with: /f-implement"
  fi
  exit 0
fi

# ---- display spec and plan (non-done path) ----------------------------------

if [ "$NO_PLAN_MODE" = "true" ]; then
  cat <<INSTRUCTIONS

===================================================
 IMPLEMENTATION SESSION (no-plan workflow)
===================================================

You have loaded the Spec-Driven Development pipeline's implement step.
There is no plan.json — discover target files inline from the spec.

SPEC:    $SPEC_FILE
STATE:   .specwork/_state/${SLUG}-state.json
CACHE:   .specwork/_state/${SLUG}-implementation-cache.json
STACK:   $(engine detect-stack)
SLUG:    $SLUG

===================================================

INSTRUCTIONS
else
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
fi

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

if [ "$NO_PLAN_MODE" = "true" ]; then
  fmt_bold "Instructions (no-plan workflow)"
  echo ""
  echo "1. Read the spec above end-to-end, especially ## Implementation Context"
  echo "   and ## Behavior."
  echo "2. Identify target files by following symbols, paths, and class names"
  echo "   referenced in the spec. Use targeted grep/find on src/ — do NOT scan"
  echo "   the whole repo."
  echo "3. Implement one focused change at a time. Read only the sections you need."
  echo "4. Add/update tests for every changed behavior."
  echo "5. When the spec's acceptance criteria are met, commit with:"
  echo "     ./commands/commit.sh"
  echo ""
  echo "If discovery surfaces enough complexity to warrant a tracked plan,"
  echo "exit and run ./commands/plan.sh instead, then re-run ./commands/implement.sh."
  echo ""
else
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
fi

# ---- show source context for first remaining target -------------------------

if [ "$NO_PLAN_MODE" = "false" ] && [ "$CURRENT_INDEX" -lt "${#TARGETS[@]}" ]; then
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
echo "On persistent failure, log escalation with:"
echo "  ./commands/implement.sh --escalate \"<area>\" \"<error>\" \"<attempted fixes>\" \"<recommended>\""
