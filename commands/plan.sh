#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

source "$LIB_DIR/gates.sh"

# ---- state ------------------------------------------------------------------

SLUG=""
STACK=""
SPEC_FILE=""
CACHE_FILE=""
PLAN_DIR=".specwork/_plan"

TARGET_FILES=()         # array of "path|change|tags"
RISK_HITS=""
CONSISTENCY_ISSUES=()

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

# ---- step 0: pipeline precondition gate -------------------------------------

engine precheck >/dev/null 2>&1 \
  || die "No active pipeline (.specwork/ missing or uninitialized). Run ./commands/start.sh first."

# ---- step 1: resolve slug ---------------------------------------------------

SLUG=$(resolve_slug) || die "Could not resolve slug from current branch."
echo "Slug: $SLUG"

# /f-plan is idempotent — no step gate. Re-invocation is allowed at any time
# (e.g. after /f-spec adds context mid-implement). Artifact gates below
# (check_required_artifacts, check_open_questions) enforce the real
# preconditions; current_step is just a UX hint, not a hard gate.

# ---- step 2: check required artifacts ---------------------------------------

check_required_artifacts "$SLUG" || die "Required artifacts missing. Run ./commands/start.sh first."

SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
CACHE_FILE=".specwork/_state/${SLUG}-implementation-cache.json"

# ---- step 3: Open Questions gate --------------------------------------------

if ! check_open_questions "$SLUG"; then
  echo ""
  echo "Cannot plan — unresolved Open Questions in spec."
  echo "Resolve them first, then re-run ./commands/plan.sh"
  exit 1
fi

# ---- step 3.5: no-op when plan is already fresh -----------------------------

# Idempotency: if plan.md exists and is newer than spec_write_timestamp
# (the canonical "spec changed" marker bumped by /f-spec), there is nothing
# to regenerate. We compare against the state.json timestamp — NOT against
# rules.json or cache.json mtimes — because plan.sh itself writes cache.json
# as a side effect, which would falsely invalidate the no-op on every re-run.
# Force regeneration: run /f-spec <args> (bumps ts) or delete plan.md.
PLAN_FILE=".specwork/_plan/${SLUG}-plan.md"

if [ -f "$PLAN_FILE" ]; then
  PLAN_MTIME=$(stat -f %m "$PLAN_FILE" 2>/dev/null || stat -c %Y "$PLAN_FILE" 2>/dev/null || echo "0")
  SPEC_TS=$(python3 -c "
import json, sys
from pathlib import Path
p = Path('.specwork/_state/${SLUG}-state.json')
print(json.loads(p.read_text(encoding='utf-8')).get('spec_write_timestamp', 0) if p.exists() else 0)
" 2>/dev/null || echo "0")
  if [ "$PLAN_MTIME" != "0" ] && [ "$SPEC_TS" != "0" ] && [ "$PLAN_MTIME" -ge "$SPEC_TS" ]; then
    echo ""
    echo "==================================================="
    echo " PLAN NO-OP"
    echo "==================================================="
    echo ""
    echo "plan.md is up to date — spec_write_timestamp has not been bumped"
    echo "since the plan was written."
    echo "  Plan:        $PLAN_FILE  (mtime=$PLAN_MTIME)"
    echo "  Spec write:  state.json::spec_write_timestamp=$SPEC_TS"
    echo ""
    echo "To force a regeneration, either:"
    echo "  - run ./commands/spec.sh <args> to bump spec_write_timestamp, or"
    echo "  - delete the plan: rm $PLAN_FILE"
    echo ""
    echo "Next:"
    echo "  ./commands/implement.sh"
    exit 0
  fi
fi

# ---- step 4: detect stack ---------------------------------------------------

STACK=$(detect_stack)
echo "Stack: $STACK"

# ---- step 5: load spec, extract candidates ----------------------------------

# Extract Implementation Context section (class names, file hints)
CANDIDATES=$(python3 - "$SPEC_FILE" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# Extract ## Implementation Context
m = re.search(r'(?ms)^## Implementation Context\b(.*?)(?=^## |\Z)', text)
if m:
    section = m.group(1)
    # Find all backticked words (class names, file paths)
    tokens = re.findall(r'`([^`]+)`', section)
    for t in tokens:
        print(t)
PY
)

echo "Candidates from spec:"
for c in $CANDIDATES; do echo "  $c"; done

# ---- step 6: targeted discovery per stack -----------------------------------

# -- 6a: cross-cutting infrastructure ----------------------------------------

find_infra() {
  local stack="$1"
  local found=()
  case "$stack" in
    java)
      while IFS= read -r -d '' f; do
        found+=("$f")
      done < <(find src/main -type f \( -name "*ExceptionHandler.java" -o -name "*ControllerAdvice.java" -o -name "*Advice.java" \) 2>/dev/null || true)
      ;;
    node)
      # Express error middleware: files containing app.use(*err,*req,*res)
      while IFS= read -r f; do
        found+=("$f")
      done < <(grep -rEl "app\.use\(.*err.*req.*res" src/ --include="*.js" --include="*.ts" 2>/dev/null || true)
      # NestJS exception filters
      while IFS= read -r f; do
        found+=("$f")
      done < <(find src -type f \( -name "*exception-filter.ts" -o -name "*exception-filter.js" \) 2>/dev/null || true)
      ;;
  esac
  for f in "${found[@]+"${found[@]}"}"; do
    echo "$f"
  done
}

INFRA_FILES=$(find_infra "$STACK" || true)
if [ -n "$INFRA_FILES" ]; then
  echo "Infrastructure files found:"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    echo "  $f"
    TARGET_FILES+=("$f|[infra] May need updates for changed HTTP status codes or error behavior|infra")
  done <<< "$INFRA_FILES"
fi

# -- 6b: blast radius mock-consumer -------------------------------------------

find_mock_consumers() {
  local stack="$1"
  local found=()
  case "$stack" in
    java)
      while IFS= read -r -d '' f; do
        local class_name
        class_name=$(basename "$f" .java)
        while IFS= read -r test_file; do
          if grep -qE "(mock|spy|verify|when|given|stub|doReturn|doThrow|doNothing|doAnswer)\s*\(|@(Mock|Spy|MockBean|SpyBean|MockitoBean|MockitoSpyBean|InjectMocks)" "$test_file" 2>/dev/null; then
            found+=("$test_file|$class_name")
          fi
        done < <(grep -rlE "\b${class_name}\b" src/test src/intTest 2>/dev/null || true)
      done < <(find . -path "*/src/main/*" \( -name "*Service.java" -o -name "*Repository.java" -o -name "*Client.java" \) 2>/dev/null || true)
      ;;
    node)
      while IFS= read -r -d '' f; do
        local class_name
        class_name=$(basename "$f" | sed 's/\.[^.]*$//')
        while IFS= read -r test_file; do
          if grep -qE "(jest\.(mock|fn|spyOn)|vi\.(mock|fn|spyOn)|jest\.mock|vi\.mock)" "$test_file" 2>/dev/null; then
            found+=("$test_file|$class_name")
          fi
        done < <(grep -rlE "\b${class_name}\b" . --include="*.test.ts" --include="*.spec.ts" --include="*.test.tsx" --include="*.spec.tsx" --include="*.test.js" 2>/dev/null || true)
      done < <(find . -path "*/src/*" \( -name "*Service.ts" -o -name "*Repository.ts" -o -name "*Client.ts" -o -name "*Controller.ts" \) 2>/dev/null || true)
      ;;
  esac

  for entry in "${found[@]+"${found[@]}"}"; do
    echo "$entry"
  done
}

MOCK_FILES=$(find_mock_consumers "$STACK" || true)
if [ -n "$MOCK_FILES" ]; then
  echo "Mock consumer tests found:"
  while IFS='|' read -r path class_name; do
    [ -z "$path" ] && continue
    echo "  $path (mocks $class_name)"
    TARGET_FILES+=("$path|[mock-consumer] Update mocks of $class_name to match new signature|mock-consumer")
  done <<< "$MOCK_FILES"
fi

# -- 6c: test naming guard ----------------------------------------------------

resolve_test_path() {
  local class_path="$1"
  local class_name
  class_name=$(basename "$class_path" | sed 's/\.[^.]*$//')

  case "$STACK" in
    java)
      find src/test src/intTest src/integrationTest -type f \( \
        -name "${class_name}Test.java" -o -name "${class_name}IT.java" \
        -o -name "${class_name}Tests.java" \) 2>/dev/null | head -1 || true
      ;;
    node)
      local test_result
      test_result=$(find . -path "*/__tests__/*" -o -path "*/test/*" -o -path "*/tests/*" 2>/dev/null | head -1 || true)
      if [ -z "$test_result" ]; then
        test_result=$(find . -type f \( \
          -name "${class_name}.test.ts" -o -name "${class_name}.spec.ts" \
          -o -name "${class_name}.test.tsx" -o -name "${class_name}.spec.tsx" \
          -o -name "${class_name}.test.js" -o -name "${class_name}.spec.js" \) 2>/dev/null | head -1 || true)
      fi
      echo "$test_result"
      ;;
  esac
}

# -- 6d: reference grep detection ---------------------------------------------

# Trigger AND extract in one pass, **scoped to lines that carry rename/remove
# language**. A spec that merely mentions `/consumers` in Implementation
# Context (without intending to rename or remove it) must NOT produce
# [reference-update] targets — that was the bug consumer-portal hit
# 2026-05-29 where every file referencing /consumers got flagged.
#
# Mirrors claude-tools/lib/f-plan.py:reference_grep. Symbols extracted:
# - backticked tokens  `Foo`, `OrderService`
# - /-prefixed paths   /api/v1/x, /consumers
extract_reference_targets() {
  python3 - "$1" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
trigger = re.compile(
    r'\b(renam\w*|remov\w*|delet\w*|deprecat\w*|replac\w*|migrat\w*|drop|retire|legacy)\b',
    re.IGNORECASE,
)
symbols = set()
for line in text.splitlines():
    if not trigger.search(line):
        continue
    symbols.update(re.findall(r'`([^`]+)`', line))
    symbols.update(re.findall(r'/[a-zA-Z][\w\-/{}]*', line))
# Only emit candidates that look like real symbols
candidates = sorted(s for s in symbols if len(s) >= 3 and ' ' not in s)
for s in candidates:
    print(s)
PY
}

REFERENCE_PATHS=$(extract_reference_targets "$SPEC_FILE")
if [ -n "$REFERENCE_PATHS" ]; then
  echo "Reference-update signal detected in spec (symbols scoped to trigger lines)."
  for old_path in $REFERENCE_PATHS; do
    [ -z "$old_path" ] && continue
    hits=
    case "$STACK" in
      java)
        hits=$(grep -rlF "$old_path" src/ --include='*.java' --include='*.kt' --include='*.properties' --include='*.yml' --include='*.yaml' 2>/dev/null || true)
        ;;
      node)
        hits=$(grep -rlF "$old_path" src/ --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.json' 2>/dev/null || true)
        ;;
      *)
        hits=$(grep -rlF "$old_path" src/ 2>/dev/null || true)
        ;;
    esac
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      already=false
      for entry in "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}"; do
        if [[ "$entry" == "$hit|"* ]]; then
          already=true; break
        fi
      done
      if ! $already; then
        echo "  $hit (references $old_path)"
        TARGET_FILES+=("$hit|[reference-update] Update reference to removed/renamed $old_path|reference-update")
      fi
    done <<< "$hits"
  done
fi

# -- 6e: spec consistency check -----------------------------------------------

CONSISTENCY_OUTPUT=$(check_spec_consistency "$SPEC_FILE" || true)
if [ -n "$CONSISTENCY_OUTPUT" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    CONSISTENCY_ISSUES+=("$line")
    echo "Spec consistency issue: $line"
  done <<< "$CONSISTENCY_OUTPUT"
fi

# -- 6f: primary targets from spec candidates ---------------------------------

for candidate in $CANDIDATES; do
  [ -z "$candidate" ] && continue
  if [ -f "$candidate" ]; then
    already=false
    for entry in "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}"; do
      if [[ "$entry" == "$candidate|"* ]]; then
        already=true; break
      fi
    done
    if ! $already; then
      TARGET_FILES+=("$candidate|Primary target from spec context|primary")
    fi
  else
    found_file=""
    case "$STACK" in
      java)
        found_file=$(find src -name "${candidate}.java" 2>/dev/null | head -1 || true)
        ;;
      node)
        found_file=$(find src -name "${candidate}.ts" -o -name "${candidate}.tsx" -o -name "${candidate}.js" 2>/dev/null | head -1 || true)
        ;;
    esac
    if [ -n "$found_file" ]; then
      already=false
      for entry in "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}"; do
        if [[ "$entry" == "$found_file|"* ]]; then
          already=true; break
        fi
      done
      if ! $already; then
        TARGET_FILES+=("$found_file|Primary target from spec context|primary")
      fi
      test_path=$(resolve_test_path "$found_file")
      if [ -n "$test_path" ]; then
        already=false
        for entry in "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}"; do
          if [[ "$entry" == "$test_path|"* ]]; then
            already=true; break
          fi
        done
        if ! $already; then
          TARGET_FILES+=("$test_path|Modify existing test for ${candidate}|test")
        fi
      fi
    fi
  fi
done

# ---- step 7: risk assessment ------------------------------------------------

RISK_HITS=$(detect_risk_signals "$SPEC_FILE" || true)

# ---- step 8: write plan.md + plan.json --------------------------------------

mkdir -p "$PLAN_DIR"

PLAN_FILE="$PLAN_DIR/${SLUG}-plan.md"

{
  echo "# ${SLUG} — Implementation Plan"
  echo ""
  echo "> Generated by open-sdd plan.sh"
  echo "> Stack: $STACK"
  echo "> The plan is **living**: implement.sh may append target files if drift is detected."
  echo ""
  echo "## Target Files"
  echo ""
  echo "| File | Change |"
  echo "|------|--------|"

  for entry in "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}"; do
    IFS='|' read -r path change tags <<< "$entry"
    echo "| \`$path\` | $change |"
  done

  if [ ${#TARGET_FILES[@]} -eq 0 ]; then
    echo "| _No files discovered automatically._ | Review the spec's Implementation Context and add targets manually. |"
  fi

  echo ""
  echo "## Approach"
  echo ""
  echo "<!-- LLM: generate ordered steps from the spec's ## Behavior section -->"
  echo "<!-- Use the Target Files table above as the file inventory -->"
  echo ""
  echo "1. <describe first change>"
  echo "2. <describe second change>"
  echo ""
  echo "## Out-of-Plan Files"
  echo ""
  echo "Files explicitly excluded (from spec's ## Scope > Out of scope):"
  echo ""
  echo "- _(none specified)_"
  echo ""

  # Open Questions section
  echo "## Open Questions"
  echo ""
  OQ_COUNT=0
  for issue in "${CONSISTENCY_ISSUES[@]+"${CONSISTENCY_ISSUES[@]}"}"; do
    OQ_COUNT=$((OQ_COUNT + 1))
    echo "- [ ] **#$OQ_COUNT** Spec consistency — \"$issue\". Both signals appear in the spec but in separate paragraphs, with no explicit reconciliation. Resolve in the spec (clarify which behavior wins), then mark this resolved."
  done
  if [ "$OQ_COUNT" -eq 0 ]; then
    echo "_None._"
  fi
  echo ""

  # Risk Assessment
  if [ -n "$RISK_HITS" ] && [ "$RISK_HITS" != "{}" ]; then
    echo "## Risk Assessment"
    echo ""
    echo "Signals detected:"
    echo "$RISK_HITS" | python3 -c "
import json, sys
try:
    hits = json.loads(sys.stdin.read())
    for signal, matches in hits.items():
        print(f'- **{signal}** — spec: {matches}')
except: pass
"
    echo ""
    echo "Recommended: commit risky steps in isolation, run tests locally after each."
    echo ""
  fi

  echo "## Risks / Constraints"
  echo ""
  echo "- _(add notes as needed)_"
  echo ""

} > "$PLAN_FILE"

echo "Plan written to $PLAN_FILE"

# ---- write plan.json for machine consumption --------------------------------

PLAN_JSON_FILE="$PLAN_DIR/${SLUG}-plan.json"
python3 - "$PLAN_JSON_FILE" "$SLUG" <<'PY' \
  "$(printf '%s\n' "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}")" \
  "$RISK_HITS" \
  "$(printf '%s\n' "${CONSISTENCY_ISSUES[@]+"${CONSISTENCY_ISSUES[@]}"}")"
import json, sys
from pathlib import Path

filepath = Path(sys.argv[1])
slug = sys.argv[2]
target_files_raw = sys.argv[3]
risk_hits_raw = sys.argv[4]
consistency_raw = sys.argv[5]

target_files = []
for line in target_files_raw.splitlines():
    if not line.strip():
        continue
    parts = line.split("|", 2)
    if len(parts) == 3:
        target_files.append({"path": parts[0], "change": parts[1], "tags": parts[2]})

risk_signals = {}
if risk_hits_raw and risk_hits_raw != "{}":
    try:
        risk_signals = json.loads(risk_hits_raw)
    except json.JSONDecodeError:
        pass

consistency_issues = [l for l in consistency_raw.splitlines() if l.strip()]

plan = {
    "schema_version": 1,
    "slug": slug,
    "stack": "",
    "target_files": target_files,
    "risk_signals": risk_signals,
    "consistency_issues": consistency_issues,
    "open_questions": [f"Spec consistency — {issue}" for issue in consistency_issues],
}
filepath.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
PY

echo "Plan JSON written to $PLAN_JSON_FILE"

# ---- step 9: update implementation cache ------------------------------------

python3 - "$CACHE_FILE" <<'PY' \
  "$(printf '%s\n' "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}")"
import json, sys
from pathlib import Path

cache_path = Path(sys.argv[1])
target_files_raw = sys.argv[2]

keys = ("repositories", "patterns", "related_tests", "similar_classes", "notes")
cache = {"schema_version": 1, "id": cache_path.stem.replace("-implementation-cache", ""), **{k: [] for k in keys}}
if cache_path.exists():
    try:
        cache.update(json.loads(cache_path.read_text(encoding="utf-8")))
    except Exception:
        pass

new_facts = {"similar_classes": [], "related_tests": [], "repositories": []}
for line in target_files_raw.splitlines():
    if not line.strip():
        continue
    parts = line.split("|", 2)
    if len(parts) < 2:
        continue
    path = parts[0]
    tags = parts[2] if len(parts) > 2 else ""
    if "primary" in tags:
        new_facts["similar_classes"].append(path)
    elif "test" in tags or "mock-consumer" in tags:
        new_facts["related_tests"].append(path)

for k in keys:
    merged = [*(cache.get(k) or []), *(new_facts.get(k) or [])]
    cache[k] = list(dict.fromkeys(x.strip() for x in merged if isinstance(x, str) and x.strip()))

cache_path.write_text(json.dumps(cache, indent=2) + "\n", encoding="utf-8")
PY

echo "Cache updated."

# ---- step 10: print summary -------------------------------------------------

PRIMARY_COUNT=0
INFRA_COUNT=0
MOCK_COUNT=0
REF_COUNT=0

for entry in "${TARGET_FILES[@]+"${TARGET_FILES[@]}"}"; do
  IFS='|' read -r _ _ tags <<< "$entry"
  case "$tags" in
    *primary*) PRIMARY_COUNT=$((PRIMARY_COUNT + 1)) ;;
    *infra*) INFRA_COUNT=$((INFRA_COUNT + 1)) ;;
    *mock-consumer*) MOCK_COUNT=$((MOCK_COUNT + 1)) ;;
    *reference-update*) REF_COUNT=$((REF_COUNT + 1)) ;;
  esac
done

echo ""
echo "============================================================"
echo "Plan created."
echo "  Plan:         $PLAN_FILE"
echo "  Plan JSON:    $PLAN_JSON_FILE"
echo ""
echo "  Target files: ${#TARGET_FILES[@]} total"
echo "    Primary:              $PRIMARY_COUNT"
echo "    [infra]:              $INFRA_COUNT"
echo "    [mock-consumer]:      $MOCK_COUNT"
echo "    [reference-update]:   $REF_COUNT"
echo "  Cache updated."
if [ ${#CONSISTENCY_ISSUES[@]} -gt 0 ]; then
  echo "  Spec consistency issues: ${#CONSISTENCY_ISSUES[@]} → plan OQs added"
fi
if [ -n "$RISK_HITS" ] && [ "$RISK_HITS" != "{}" ]; then
  echo "  ⚠ Risk signals detected — see plan for details."
fi

# advance pipeline state: plan → implement, but only on the natural transition.
# If current_step has already moved past plan (user re-ran /f-plan after some
# /f-implement steps), leave it alone — re-runs must not yank the state
# machine backward or forward unexpectedly.
CURRENT_STEP=$(python3 -c "
import json, sys
from pathlib import Path
p = Path('.specwork/_state/${SLUG}-state.json')
print(json.loads(p.read_text(encoding='utf-8')).get('current_step','') if p.exists() else '')
" 2>/dev/null || echo "")
if [ "$CURRENT_STEP" = "spec" ] || [ "$CURRENT_STEP" = "plan" ]; then
  engine advance-step "$SLUG" plan >/dev/null 2>&1 || true
fi

echo ""
echo "Next:"
echo "  Review the plan, then run:"
echo "    ./commands/implement.sh"
echo "============================================================"
