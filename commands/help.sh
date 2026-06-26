#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- overview mode ----------------------------------------------------------

if [ "${1:-}" = "overview" ]; then
  cat <<OVERVIEW
Feature Development Pipeline
═════════════════════════════════════════════════════════════════

SETUP (once per project)
  Clone open-sdd and run ./install.sh or configure the commands path.

─────────────────────────────────────────────────────────────────

FEATURE PIPELINE

  /f-start <ticket-or-text>
    Initialize the pipeline, create/select the working branch,
    and write .specwork metadata plus source.md. Does NOT create
    spec.md — that is /f-spec's job.

  /f-spec [files | jira <ticket> | free text]
    Draft the spec (first call) or refine it (subsequent calls).
    Idempotent; bumps spec_write_timestamp on every write.

  /f-plan
    Discover target files and write an implementation plan (optional).

  /f-implement
    Implement the next piece with inline tests.

  /f-commit
    Stage changes, propose a semantic commit message, confirm.

  /f-test-design
    [optional] Design test cases for the current changes.

  /f-test-impl
    [optional] Implement test files from the design.

  /f-code-review
    [optional] Stack-aware code quality and security review.

  /f-mr-review <branch | mr-url | mr-iid>
    [optional] Stack-aware peer review of someone else's branch or MR.
    Read-only — resolves a remote diff and never touches your working tree.

  /f-mr
    Generate MR description, push, create/update MR.

  /f-mr-address
    Work through MR review comments (after /f-mr receives feedback).

  /f-close
    Delete .specwork/ after merge.

  /f-handoff
    [optional] Package spec + rules + context into an execution pack
    for another agent/model.

─────────────────────────────────────────────────────────────────

UTILITIES

  /f-status     Full pipeline status.
  /f-help       This. Shows contextual next step or overview.
  /f-auto       Run the pipeline non-interactively through to the open MR.
  /f-pause      Stash all work (including .specwork/) to switch context.
  /f-resume     List paused branches and restore one.
  /f-undo       Discard uncommitted changes, reversibly (--restore to recover, --hard --force to discard).
  /f-resync     Resync artifacts with current branch (use --rename-branch to rename + sync).

─────────────────────────────────────────────────────────────────

ARTIFACTS (live in .specwork/, gitignored)

  _spec/<slug>-spec.md        Feature specification
  _plan/<slug>-plan.md        Implementation plan
  _state/<slug>-state.json    Pipeline metadata
  _review/<slug>-*.md         Code review reports
  _handoff/<slug>-*.md        Execution handoff packs
OVERVIEW
  exit 0
fi

# ---- resolve context --------------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
SLUG=$(resolve_slug 2>/dev/null || echo "")

STATE_FILE=""
SPEC_FILE=""
PLAN_FILE=""

if [ -n "$SLUG" ]; then
  STATE_FILE=".specwork/_state/${SLUG}-state.json"
  SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
  PLAN_FILE=".specwork/_plan/${SLUG}-plan.md"
fi

# ---- state evaluation -------------------------------------------------------

STATE_EXISTS=false
SPEC_EXISTS=false
BRANCH_MATCHES=false
SPEC_OQS_OPEN=0
PLAN_OQS_OPEN=0
TREE_DIRTY=false
COMMITS_AHEAD=false
BASE=""

if [ -n "$SLUG" ] && [ -f "$STATE_FILE" ]; then
  STATE_EXISTS=true

  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(d.get("branch", ""))
PYEOF
  RECORDED_BRANCH=$(python3 "$PY_SCRIPT" "$STATE_FILE" 2>/dev/null || echo "")
  rm -f "$PY_SCRIPT"

  [ "$RECORDED_BRANCH" = "$BRANCH" ] && BRANCH_MATCHES=true

  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(d.get("base_branch", ""))
PYEOF
  BASE=$(python3 "$PY_SCRIPT" "$STATE_FILE" 2>/dev/null || echo "")
  rm -f "$PY_SCRIPT"
fi

if [ -f "$SPEC_FILE" ]; then
  SPEC_EXISTS=true
  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Open Questions\b(.*?)(?=^## |\Z)', text)
if m:
    open_count = len(re.findall(r'^\s*-\s*\[\s\]', m.group(1), re.MULTILINE))
    print(f"{open_count} 0")
else:
    print("0 0")
PYEOF
  read -r spec_open _ < <(python3 "$PY_SCRIPT" "$SPEC_FILE" 2>/dev/null || echo "0 0")
  rm -f "$PY_SCRIPT"
  SPEC_OQS_OPEN=$spec_open
fi

if [ -f "$PLAN_FILE" ]; then
  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Open Questions\b(.*?)(?=^## |\Z)', text)
if m:
    open_count = len(re.findall(r'^\s*-\s*\[\s\]', m.group(1), re.MULTILINE))
    print(f"{open_count} 0")
else:
    print("0 0")
PYEOF
  read -r plan_open _ < <(python3 "$PY_SCRIPT" "$PLAN_FILE" 2>/dev/null || echo "0 0")
  rm -f "$PY_SCRIPT"
  PLAN_OQS_OPEN=$plan_open
fi

DIRTY_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "$DIRTY_COUNT" -gt 0 ] && TREE_DIRTY=true

if [ -n "$BASE" ] && [ -n "$BRANCH" ]; then
  AHEAD=$(git rev-list --count "origin/${BASE}..HEAD" 2>/dev/null || echo "0")
  [ "$AHEAD" -gt 0 ] && COMMITS_AHEAD=true
fi

MR_JSON_FILE=""
MR_OPENED=false
if [ -n "$SLUG" ]; then
  MR_JSON_FILE=".specwork/_state/${SLUG}-mr.json"
fi
[ -f "${MR_JSON_FILE:-}" ] && MR_OPENED=true

# ---- determine state --------------------------------------------------------

STATE_LABEL="setup"
STATE_REASON=""

if ! $STATE_EXISTS; then
  STATE_LABEL="setup"
  STATE_REASON="No pipeline state detected."
elif ! $BRANCH_MATCHES; then
  STATE_LABEL="blocked"
  STATE_REASON="Current branch does not match recorded pipeline branch."
elif ! $SPEC_EXISTS; then
  STATE_LABEL="blocked"
  STATE_REASON="Spec is missing."
elif [ "$SPEC_OQS_OPEN" -gt 0 ] || [ "$PLAN_OQS_OPEN" -gt 0 ]; then
  STATE_LABEL="blocked"
  STATE_REASON="${SPEC_OQS_OPEN} unresolved Open Question(s) in spec"
  [ "$PLAN_OQS_OPEN" -gt 0 ] && STATE_REASON+=", ${PLAN_OQS_OPEN} in plan"
elif $TREE_DIRTY; then
  STATE_LABEL="in-progress"
  STATE_REASON="Working tree has uncommitted changes."
elif $COMMITS_AHEAD; then
  STATE_LABEL="review-ready"
  STATE_REASON="Branch has commits ahead of base."
else
  STATE_LABEL="ready"
  STATE_REASON="Pipeline initialized, ready to implement."
fi

# ---- print pipeline diagram -------------------------------------------------

echo ""
fmt_bold "Pipeline: ${BRANCH}  [${STATE_LABEL}]"
echo "──────────────────────────────────────"

pipeline_steps=(
  "/f-start:state + spec written"
  "/f-plan (optional)"
  "/f-implement:implement and test inline"
  "/f-test-design (optional)"
  "/f-test-impl (optional)"
  "/f-code-review (optional)"
  "/f-mr"
  "/f-mr-address"
  "/f-close"
)

for step in "${pipeline_steps[@]}"; do
  name="${step%%:*}"
  label="${step#*:}"

  case "$name" in
    "/f-start")
      if $STATE_EXISTS && $SPEC_EXISTS; then
        echo "✓  $name         $label"
      elif $STATE_EXISTS; then
        echo "✗  $name         spec missing"
      else
        echo "○  $name"
      fi
      ;;
    "/f-plan"*)
      if [ -f "$PLAN_FILE" ]; then
        echo "✓  $name"
      elif [ "$STATE_LABEL" = "blocked" ] || [ "$STATE_LABEL" = "setup" ]; then
        echo "○  $name"
      elif $TREE_DIRTY || $COMMITS_AHEAD; then
        echo "-  $name        (skipped — already implementing)"
      else
        echo "→  $name        (recommended)"
      fi
      ;;
    "/f-implement"*)
      if [ "$STATE_LABEL" = "blocked" ]; then
        echo "✗  $name  blocked — ${STATE_REASON}"
      elif $TREE_DIRTY; then
        echo "→  $name  in progress"
      elif $COMMITS_AHEAD || [ -f "$PLAN_FILE" ]; then
        echo "✓  $name  done"
      else
        echo "○  $name"
      fi
      ;;
    "/f-test-design"*)
      echo "○  $name"
      ;;
    "/f-test-impl"*)
      echo "○  $name"
      ;;
    "/f-code-review"*)
      echo "○  $name"
      ;;
    "/f-mr")
      if $MR_OPENED; then
        echo "✓  $name               MR open"
      elif $COMMITS_AHEAD; then
        echo "→  $name               ready to open"
      else
        echo "○  $name"
      fi
      ;;
    "/f-mr-address")
      if $MR_OPENED; then
        echo "→  $name"
      else
        echo "○  $name"
      fi
      ;;
    "/f-close")
      echo "○  $name"
      ;;
  esac
done

echo ""

# ---- print next step --------------------------------------------------------

echo "Next step:"
echo ""

if [ "$STATE_LABEL" = "setup" ]; then
  echo "  /f-start <ticket-or-text>"
  echo ""
  echo "  Initialize the pipeline. No SDD state exists yet."
elif [ "$STATE_LABEL" = "blocked" ] && ! $BRANCH_MATCHES; then
  PY_SCRIPT=$(mktemp)
  cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("branch", "unknown"))
PYEOF
  RECORDED=$(python3 "$PY_SCRIPT" "$STATE_FILE" 2>/dev/null || echo "unknown")
  rm -f "$PY_SCRIPT"
  echo "  Switch back to the branch recorded in state:"
  echo "    git switch $RECORDED"
  echo ""
  echo "  The active .specwork state belongs to a different branch."
elif $MR_OPENED; then
  echo "  /f-mr-address"
  echo ""
  echo "  MR is open. Address review comments, then /f-close after it merges."
elif [ "$STATE_LABEL" = "blocked" ] && ! $SPEC_EXISTS; then
  echo "  /f-spec"
  echo ""
  echo "  Pipeline is initialized but no spec exists. Draft the spec next."
elif [ "$STATE_LABEL" = "blocked" ] && [ "$SPEC_OQS_OPEN" -gt 0 ]; then
  ABS_SPEC="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
  OQ_LINE=$(grep -n "^## Open Questions" "$SPEC_FILE" | head -1 | cut -d: -f1 || echo "")
  SPEC_PATH="\`${ABS_SPEC}:${OQ_LINE}\`"
  echo "  Resolve Open Questions in ${SPEC_PATH}"
  echo ""
  echo "  Then run /f-plan or /f-implement"
elif [ "$STATE_LABEL" = "blocked" ] && [ "$PLAN_OQS_OPEN" -gt 0 ]; then
  ABS_PLAN="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"
  OQ_LINE=$(grep -n "^## Open Questions" "$PLAN_FILE" | head -1 | cut -d: -f1 || echo "")
  PLAN_PATH="\`${ABS_PLAN}:${OQ_LINE}\`"
  echo "  Resolve Open Questions in ${PLAN_PATH}"
  echo ""
  echo "  Then run /f-plan"
elif $TREE_DIRTY; then
  echo "  /f-implement"
  echo ""
  echo "  Working tree has uncommitted changes. Continue implementing."
elif $COMMITS_AHEAD; then
  echo "  /f-mr"
  echo ""
  echo "  Branch is clean and has commits ahead of base. Open the MR."
elif [ -f "$PLAN_FILE" ]; then
  echo "  /f-implement"
  echo ""
  echo "  Plan is ready. Start implementing."
else
  echo "  /f-plan (or /f-implement for simple changes)"
  echo ""
  echo "  Pipeline initialized. Discover target files or start implementing directly."
fi
