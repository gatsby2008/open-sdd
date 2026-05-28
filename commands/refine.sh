#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- step 1: resolve slug ---------------------------------------------------

SLUG=""
STATE_FILE=""
SPEC_FILE=""
CACHE_FILE=""

SLUG=$(resolve_slug 2>/dev/null || echo "")

if [ -n "$SLUG" ]; then
  STATE_FILE=".specwork/_state/${SLUG}-state.json"
  SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
  CACHE_FILE=".specwork/_state/${SLUG}-implementation-cache.json"
fi

if [ -z "$SLUG" ] || [ ! -f "$STATE_FILE" ]; then
  die "No SDD pipeline state found.
Run ./commands/start.sh first to initialize the pipeline."
fi

echo "Slug: $SLUG"

# ---- step 2: verify required artifacts --------------------------------------

MISSING=""
for f in "$SPEC_FILE" "$STATE_FILE" ".specwork/_state/${SLUG}-rules.json" "$CACHE_FILE"; do
  [ -f "$f" ] || { MISSING+="  $f"$'\n'; }
done

if [ -n "$MISSING" ]; then
  die "Missing required artifacts:
${MISSING}Run ./commands/start.sh first."
fi

# ---- step 3: load spec for reference ----------------------------------------

SPEC_CONTENT=$(cat "$SPEC_FILE")

# ---- step 4: collect input context ------------------------------------------

INPUT_FILES=()
INPUT_JIRA=""
INPUT_TEXT=""

for arg in "$@"; do
  if [ "$arg" = "jira" ]; then
    INPUT_JIRA="pending"
  elif [ "$INPUT_JIRA" = "pending" ]; then
    INPUT_JIRA="$arg"
  elif [ -f "$arg" ]; then
    INPUT_FILES+=("$arg")
  else
    INPUT_TEXT+=" $arg"
  fi
done

INPUT_TEXT=$(echo "$INPUT_TEXT" | xargs)

# ---- step 5: fetch input content --------------------------------------------

CONTEXT_SECTIONS=""

# Files
for f in "${INPUT_FILES[@]+"${INPUT_FILES[@]}"}"; do
  if [ -f "$f" ]; then
    CONTENT=$(cat "$f")
    CONTEXT_SECTIONS+="--- File: $f ---"$'\n'
    CONTEXT_SECTIONS+="$CONTENT"$'\n'
    CONTEXT_SECTIONS+=""$'\n'
  else
    CONTEXT_SECTIONS+="--- File not found: $f ---"$'\n'$'\n'
  fi
done

# Jira
if [ -n "$INPUT_JIRA" ] && [ "$INPUT_JIRA" != "pending" ]; then
  TICKET_CONTENT=""
  if [ -f "$LIB_DIR/jira.sh" ]; then
    source "$LIB_DIR/jira.sh"
    if jira_is_configured 2>/dev/null; then
      TMP_FILE=$(mktemp)
      if jira_write_issue_markdown "$INPUT_JIRA" "$TMP_FILE" 2>/dev/null; then
        TICKET_CONTENT=$(cat "$TMP_FILE")
      fi
      rm -f "$TMP_FILE"
    fi
  fi
  if [ -n "$TICKET_CONTENT" ]; then
    CONTEXT_SECTIONS+="--- Jira: $INPUT_JIRA ---"$'\n'
    CONTEXT_SECTIONS+="$TICKET_CONTENT"$'\n'$'\n'
  else
    CONTEXT_SECTIONS+="--- Jira: $INPUT_JIRA (not available — configure JIRA_USER + JIRA_TOKEN) ---"$'\n'$'\n'
  fi
fi

# Free text
if [ -n "$INPUT_TEXT" ]; then
  CONTEXT_SECTIONS+="--- Free text ---"$'\n'
  CONTEXT_SECTIONS+="$INPUT_TEXT"$'\n'$'\n'
fi

# ---- step 6: downstream staleness detection ---------------------------------

PLAN_FILE=".specwork/_plan/${SLUG}-plan.md"
WARNINGS=""

if [ -f "$PLAN_FILE" ]; then
  PLAN_MTIME=$(stat -f %m "$PLAN_FILE" 2>/dev/null || stat -c %Y "$PLAN_FILE" 2>/dev/null || echo "0")
  SPEC_MTIME=$(stat -f %m "$SPEC_FILE" 2>/dev/null || stat -c %Y "$SPEC_FILE" 2>/dev/null || echo "0")
  if [ "$PLAN_MTIME" != "0" ] && [ "$SPEC_MTIME" != "0" ] && [ "$SPEC_MTIME" -gt "$PLAN_MTIME" ]; then
    WARNINGS+="⚠  .specwork/_plan/${SLUG}-plan.md is older than the spec"$'\n'
    WARNINGS+="    Run ./commands/plan.sh to regenerate (it is idempotent)."$'\n'
  fi
fi

DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  WARNINGS+="⚠  Working tree has uncommitted changes"$'\n'
  WARNINGS+="    Review them against the new spec before committing."$'\n'
fi

# ---- step 7: print instructions ---------------------------------------------

OQ_LINE=$(grep -n "^## Open Questions" "$SPEC_FILE" 2>/dev/null | head -1 | cut -d: -f1 || echo "")

echo ""
echo "==================================================="
echo " SPEC REFINE SESSION"
echo "==================================================="
echo ""
fmt_bold "Context"
echo "  Slug:   $SLUG"
echo "  Spec:   $SPEC_FILE"
echo "  Cache:  $CACHE_FILE"
echo ""

if [ -z "$CONTEXT_SECTIONS" ]; then
  echo "No input provided. Usage:"
  echo ""
  echo "  ./commands/refine.sh <files> jira <ticket> <free text>"
  echo ""
  echo "  Files:    paths to source files (e.g. src/.../OrderController.java)"
  echo "  Jira:     jira MYYES-1234"
  echo "  Free text: any natural-language sentence"
  echo ""
  echo "You can combine inputs:"
  echo "  ./commands/refine.sh OrderController.java jira IR-122 \"use UUID for personId\""
  echo ""
  exit 1
fi

# ---- current spec -----------------------------------------------------------

echo "==================================================="
echo " CURRENT SPEC"
echo "==================================================="
echo ""
echo "$SPEC_CONTENT"
echo ""

# ---- new context ------------------------------------------------------------

echo "==================================================="
echo " NEW CONTEXT"
echo "==================================================="
echo "$CONTEXT_SECTIONS"
echo ""

# ---- staleness warnings -----------------------------------------------------

if [ -n "$WARNINGS" ]; then
  echo "==================================================="
echo " DOWNSTREAM WARNINGS"
echo "==================================================="
echo "$WARNINGS"
echo ""
fi

# ---- integration instructions -----------------------------------------------

ABS_SPEC=""
OQ_LINE_OUT=""
if [ -f "$SPEC_FILE" ]; then
  ABS_SPEC="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
  OQ_LINE=$(grep -n "^## Open Questions" "$SPEC_FILE" 2>/dev/null | head -1 | cut -d: -f1 || echo "")
  [ -n "$OQ_LINE" ] && OQ_LINE_OUT="\`${ABS_SPEC}:${OQ_LINE}\`"
fi

cat <<INSTRUCTIONS

===================================================
 INTEGRATION INSTRUCTIONS
===================================================

Integrate the NEW CONTEXT above into the CURRENT SPEC at ${SPEC_FILE}.

Rules:
1. NEVER delete user-authored content. Resolutions append; they do not remove.
2. NEVER modify ## Summary or the spec title unless the input explicitly contradicts them.
3. NEVER touch .specwork/_spec/${SLUG}-source.md. The original source is immutable.
4. Preserve section order and heading text exactly.

Mapping guidance:

| If the input is... | Then... |
|--------------------|---------|
| A file with a class / endpoint / service | Add to ## Implementation Context. If it answers an open OQ, mark it resolved. |
| A Jira ticket | Extract behaviors → ## Behavior. Constraints → ## Safe Constraints. Scope → ## Expected Change Scope. |
| Free text that answers an OQ (#N) | Flip - [ ] to - [x] and append " — resolved: <answer>". |
| Free text with a new rule | Add to ## Safe Constraints (Safe or Unsafe). |
| Anything ambiguous | Append a new Open Question. Do not guess. |

OQ format: flip \`- [ ] **#N**\` → \`- [x] **#N** — resolved: <answer>\`
New OQ: \`- [ ] **#N** <question>\`  (N = next available number)

After integrating, write the updated spec back to $SPEC_FILE.

After writing the spec, bump spec_write_timestamp so downstream
staleness checks (./commands/implement.sh) detect the refine:

  PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli bump-spec-ts $SLUG

INSTRUCTIONS

if [ -n "$OQ_LINE_OUT" ]; then
  echo "Open Questions are at: $OQ_LINE_OUT"
  echo ""
fi

if [ -n "$WARNINGS" ]; then
  echo "NOTE: $WARNINGS"
  echo ""
fi

echo "Also update ${CACHE_FILE} with any newly confirmed classes,"
echo "repositories, or tests (append-only, deduped)."
echo ""
echo "After updating the spec, print a summary of what changed."
