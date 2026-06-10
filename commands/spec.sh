#!/usr/bin/env bash
set -euo pipefail

# Capture argc before `set -- $@` consumers (the input-parse loop) drain it.
# Drives the no-op path below: /f-spec with no args in refine mode is idempotent.
ARGC=$#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

# ---- step 0: pipeline precondition ------------------------------------------

engine precheck >/dev/null 2>&1 \
  || die "No active pipeline (.specwork/ missing or uninitialized). Run /f-start first."

# ---- step 1: resolve slug ---------------------------------------------------

SLUG=$(resolve_slug 2>/dev/null || echo "")
[ -n "$SLUG" ] || die "Could not resolve slug from current branch. Run /f-start first."

source "$LIB_DIR/non_interactive.sh"
hydrate_non_interactive_from_state "$SLUG"

STATE_FILE=".specwork/_state/${SLUG}-state.json"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
SOURCE_FILE=".specwork/_spec/${SLUG}-source.md"
CACHE_FILE=".specwork/_state/${SLUG}-implementation-cache.json"

[ -f "$STATE_FILE" ] || die "Missing state file: $STATE_FILE. Run /f-start first."

echo "Slug: $SLUG"

# ---- step 2: detect mode (draft vs refine) ----------------------------------

# /f-start does NOT create spec.md — it only writes source.md and the state
# files. /f-spec owns spec.md: draft mode (file missing) generates it from
# source.md + templates/spec.md + optional args; refine mode (file exists)
# integrates new context. To reset the spec, delete the file and re-run /f-spec.
if [ ! -f "$SPEC_FILE" ]; then
  MODE="draft"
else
  MODE="refine"
fi

echo "Mode: $MODE"

# ---- step 2.5: no-op path (refine without args is idempotent) ---------------

# In refine mode with no arguments there is nothing to integrate — exit cleanly
# without bumping spec_write_timestamp and without printing INSTRUCTIONS.
# /f-spec called twice in a row should be a no-op the second time.
if [ "$MODE" = "refine" ] && [ "$ARGC" -eq 0 ]; then
  echo ""
  echo "==================================================="
  echo " SPEC NO-OP"
  echo "==================================================="
  echo ""
  echo "spec.md is already drafted ($SPEC_FILE)."
  echo "No arguments passed — nothing to refine, nothing changed."
  echo ""
  echo "To refine the spec, pass additional context:"
  echo "  /f-spec <file> [<file> ...]        — add file context"
  echo "  /f-spec jira <TICKET>              — add Jira ticket context"
  echo "  /f-spec \"free text\"                — add free text"
  echo "  /f-spec <file> jira <TICKET> \"...\" — combine sources"
  echo ""
  TICKET_TYPE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('ticket_type',''))" 2>/dev/null || echo "")
  echo "Next:"
  if [ "$TICKET_TYPE" = "high-risk" ] || [ "$TICKET_TYPE" = "standard" ]; then
    echo "  /f-plan        (required — discover target files)"
  else
    echo "  /f-plan        (discover target files)"
    echo "  /f-implement   (start implementing directly)"
  fi
  exit 0
fi

# ---- step 3: verify required artifacts --------------------------------------

MISSING=""
for f in "$STATE_FILE" ".specwork/_state/${SLUG}-rules.json" "$CACHE_FILE" "$SOURCE_FILE"; do
  [ -f "$f" ] || MISSING+="  $f"$'\n'
done

if [ -n "$MISSING" ]; then
  die "Missing required artifacts (all written by /f-start):
${MISSING}Run /f-start first."
fi

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

for f in "${INPUT_FILES[@]+"${INPUT_FILES[@]}"}"; do
  if [ -f "$f" ]; then
    CONTEXT_SECTIONS+="--- File: $f ---"$'\n'
    CONTEXT_SECTIONS+="$(cat "$f")"$'\n'$'\n'
  else
    CONTEXT_SECTIONS+="--- File not found: $f ---"$'\n'$'\n'
  fi
done

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

if [ -n "$INPUT_TEXT" ]; then
  CONTEXT_SECTIONS+="--- Free text ---"$'\n'
  CONTEXT_SECTIONS+="$INPUT_TEXT"$'\n'$'\n'
fi

# ---- step 6: downstream staleness detection (refine mode only) --------------

WARNINGS=""

if [ "$MODE" = "refine" ]; then
  PLAN_FILE=".specwork/_plan/${SLUG}-plan.md"
  if [ -f "$PLAN_FILE" ]; then
    if ! engine implement-check "$SLUG" >/dev/null 2>&1; then
      # Use a more focused staleness check — implement-check also fails on OQs.
      # We only want to warn about plan staleness here, so re-check via gates.
      PLAN_MTIME=$(stat -c %Y "$PLAN_FILE" 2>/dev/null || stat -f %m "$PLAN_FILE" 2>/dev/null || echo "0")
      SPEC_TS=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['spec_write_timestamp'])" 2>/dev/null || echo "0")
      if [ "$PLAN_MTIME" != "0" ] && [ "$SPEC_TS" != "0" ] && [ "$PLAN_MTIME" -lt "$SPEC_TS" ]; then
        WARNINGS+="⚠  .specwork/_plan/${SLUG}-plan.md is older than the spec"$'\n'
        WARNINGS+="    Run /f-plan to regenerate (it is idempotent)."$'\n'
      fi
    fi
  fi
fi

DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ] && [ "$MODE" = "refine" ]; then
  WARNINGS+="⚠  Working tree has uncommitted changes"$'\n'
  WARNINGS+="    Review them against the new spec before committing."$'\n'
fi

# ---- step 7: print session header -------------------------------------------

echo ""
echo "==================================================="
if [ "$MODE" = "draft" ]; then
  echo " SPEC DRAFT SESSION"
else
  echo " SPEC REFINE SESSION"
fi
echo "==================================================="
echo ""
fmt_bold "Context"
echo "  Slug:    $SLUG"
echo "  Spec:    $SPEC_FILE"
echo "  Source:  $SOURCE_FILE"
echo "  Cache:   $CACHE_FILE"
echo ""

# ---- step 8: print source (draft mode) or current spec (refine mode) --------

if [ "$MODE" = "draft" ]; then
  echo "==================================================="
  echo " SOURCE (immutable, set by /f-start)"
  echo "==================================================="
  echo ""
  if [ -f "$SOURCE_FILE" ]; then
    cat "$SOURCE_FILE"
  else
    echo "(no source.md found)"
  fi
  echo ""

  echo "==================================================="
  echo " SPEC TEMPLATE (canonical section structure)"
  echo "==================================================="
  echo ""
  cat "$TEMPLATES_DIR/spec.md"
  echo ""
else
  echo "==================================================="
  echo " CURRENT SPEC"
  echo "==================================================="
  echo ""
  cat "$SPEC_FILE"
  echo ""
fi

# ---- step 9: print new context ----------------------------------------------

if [ -n "$CONTEXT_SECTIONS" ]; then
  echo "==================================================="
  echo " NEW CONTEXT"
  echo "==================================================="
  echo "$CONTEXT_SECTIONS"
  echo ""
fi

# ---- step 10: print warnings ------------------------------------------------

if [ -n "$WARNINGS" ]; then
  echo "==================================================="
  echo " DOWNSTREAM WARNINGS"
  echo "==================================================="
  echo "$WARNINGS"
  echo ""
fi

# ---- step 11: emit instructions ---------------------------------------------

ABS_SPEC=""
if [ -f "$SPEC_FILE" ]; then
  ABS_SPEC="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
fi

if [ "$MODE" = "draft" ]; then
  cat <<INSTRUCTIONS

===================================================
 INTEGRATION INSTRUCTIONS (DRAFT)
===================================================

Write the first version of the spec at $SPEC_FILE using the
SOURCE above as the authoritative input and the SPEC TEMPLATE
as the section structure.

Rules:
1. Use the title from the source (slug + summary).
2. Fill every section the source supports with concrete content;
   for any section you cannot fill from source/context, leave a
   single Open Question rather than inventing detail.
3. Preserve the section order and headings from the template.
4. Open Questions are numbered (#1, #2, ...) and use the format
   \`- [ ] **#N** <question>\`. List every unresolved ambiguity
   you would otherwise have to guess.
5. NEVER touch .specwork/_spec/${SLUG}-source.md — it is immutable.

If new context (files, jira, free text) was supplied above, fold
it into the relevant sections.

INSTRUCTIONS
else
  cat <<INSTRUCTIONS

===================================================
 INTEGRATION INSTRUCTIONS (REFINE)
===================================================

Integrate the NEW CONTEXT above into the CURRENT SPEC at $SPEC_FILE.

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

INSTRUCTIONS
fi

cat <<INSTRUCTIONS
After writing the spec, run the following so downstream gates
(./commands/implement.sh) detect this update:

  PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli bump-spec-ts $SLUG

INSTRUCTIONS

if [ "$MODE" = "draft" ]; then
  cat <<INSTRUCTIONS
On the first draft, run triage now that the spec body has real content
(triage reads ## Behavior and ## Implementation Context — until /f-spec
creates spec.md, triage has nothing to classify):

  ./commands/triage.sh $SLUG

Print the triage result (type, complexity, path, reason). The path is
advisory — the developer can override at any step.

If Open Questions remain, re-run ./commands/spec.sh with more context to
resolve them before continuing.

Next:
  /f-plan       (recommended for 3+ files)
  /f-implement   (small / obvious changes — inline discovery)

INSTRUCTIONS
else
  # Refine mode + args. Spec changes are detected downstream via
  # spec_write_timestamp (artifact-driven gates), no state machine to update.
  PLAN_EXISTS=false
  [ -f ".specwork/_plan/${SLUG}-plan.md" ] && PLAN_EXISTS=true

  cat <<INSTRUCTIONS
Downstream gates detect the bump above via spec_write_timestamp and will
block until either:
  - plan.md is refreshed (./commands/plan.sh, idempotent), or
  - plan.md is removed and /f-implement falls back to inline discovery.

If the refine resolved Open Questions that were previously open, mention
that in the summary so the developer knows the gate path is now clear.

Next:
INSTRUCTIONS

  if [ "$PLAN_EXISTS" = "true" ]; then
    cat <<INSTRUCTIONS
  /f-plan       (recommended — plan.md is now stale relative to the new spec)
  /f-implement   (will block on staleness until /f-plan refreshes plan.md,
                  or delete plan.md to fall back to inline discovery)

INSTRUCTIONS
  else
    cat <<INSTRUCTIONS
  /f-plan       (optional — for 3+ files)
  /f-implement   (inline discovery from the spec)

INSTRUCTIONS
  fi
fi

if [ -f "$SPEC_FILE" ] && [ -n "$ABS_SPEC" ]; then
  OQ_LINE=$(grep -n "^## Open Questions" "$SPEC_FILE" 2>/dev/null | head -1 | cut -d: -f1 || echo "")
  if [ -n "$OQ_LINE" ]; then
    echo "Open Questions are at: \`${ABS_SPEC}:${OQ_LINE}\`"
    echo ""
  fi
fi

if [ "${SDD_NON_INTERACTIVE:-0}" = "1" ]; then
  cat <<INSTRUCTIONS

--- Non-interactive mode: mandatory continuation ---
After writing the spec, run these steps in order without pausing:

1. PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli bump-spec-ts $SLUG

2. PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli check $SLUG
   - UNRESOLVED_OQS  → report them and STOP. Re-run /f-spec with the answers.
   - GATES_PASSED    → continue:

3. bash $SCRIPT_DIR/plan.sh

4. bash $SCRIPT_DIR/implement.sh

5. Set the auto-MR flag in state.json:
       python3 -c "
import json
from pathlib import Path
p = Path('.specwork/_state/${SLUG}-state.json')
if p.exists():
    d = json.loads(p.read_text())
    d['auto_open_mr_after_commit'] = True
    p.write_text(json.dumps(d, indent=2) + '\n')
"

6. Run /f-commit — it runs the coverage gate, commits, and (with the flag set
   above) continues automatically to /f-mr. STOP at the open MR.

Do NOT run /f-close or /f-mr-address — those are post-merge, human-gated steps.
INSTRUCTIONS
fi

if [ -n "$WARNINGS" ]; then
  echo "NOTE: $WARNINGS"
fi

echo "Also update ${CACHE_FILE} with any newly confirmed classes,"
echo "repositories, or tests (append-only, deduped)."
echo ""
echo "After updating the spec, print a summary of what changed."
