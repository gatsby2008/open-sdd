#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"

source "$LIB_DIR/jira.sh"

# ---- helpers ----------------------------------------------------------------

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

detect_ticket() {
  local input="$1"
  if [[ "$input" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
    echo "jira"
  else
    echo "freetext"
  fi
}

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

tree_is_clean() {
  git status --porcelain 2>/dev/null | grep -q . && return 1 || return 0
}

# ---- main -------------------------------------------------------------------

BRANCH_FLAG=""
CUSTOM_BRANCH=""
INPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)    BRANCH_FLAG="keep"; shift ;;
    --branch)  BRANCH_FLAG="branch"; shift; CUSTOM_BRANCH="${1:-}"; [ -z "$CUSTOM_BRANCH" ] && { echo "Error: --branch requires a name"; exit 1; }; shift ;;
    *)         INPUT="$1"; shift ;;
  esac
done

[ -z "$INPUT" ] && {
  echo "Usage: /f-start <TICKET-123|description> [--branch <name>] [--keep]"
  exit 1
}

INPUT_TYPE=$(detect_ticket "$INPUT")
if [ "$INPUT_TYPE" = "jira" ]; then
  SLUG=$(slugify "$INPUT")
  SUGGESTED_BRANCH="feature/${SLUG}"
  TICKET="$INPUT"
else
  SLUG=$(slugify "$INPUT" | sed -E 's/^-+//; s/-+$//')
  SUGGESTED_BRANCH="feature/${SLUG}"
  TICKET=""
fi

BASE_BRANCH=""
CURRENT=$(current_branch)

echo "Input:        $INPUT"
echo "Type:         $INPUT_TYPE"
echo "Slug:         $SLUG"
echo "Current branch: $CURRENT"

# ---- pre-flight -------------------------------------------------------------

if [ -z "$CURRENT" ]; then
  echo "Not in a git repository."
  exit 1
fi

case "$CURRENT" in
  main|master|develop|development)
    if ! tree_is_clean; then
      echo "Working tree has changes on $CURRENT. Commit or stash first."
      exit 1
    fi
    BASE_BRANCH="$CURRENT"
    ;;
  *)
    BASE_BRANCH="$CURRENT"
    ;;
esac

# ---- clean stale .specwork/ -------------------------------------------------

if [ -d ".specwork" ]; then
  echo "Found existing .specwork/. Cleaning merged artifacts from prior features."
  rm -rf .specwork
fi

# ---- branch decision --------------------------------------------------------

if [ "$BRANCH_FLAG" = "branch" ]; then
  BRANCH="$CUSTOM_BRANCH"
  git checkout -b "$BRANCH"
  SLUG=$(slugify "$(echo "$BRANCH" | sed 's/^feature\///; s/^bugfix\///; s/^hotfix\///; s/^release\///')")
elif [ "$BRANCH_FLAG" = "keep" ]; then
  BRANCH="$CURRENT"
  echo "Staying on $BRANCH."
else
  CHOICE="A"
  if [ -t 0 ]; then
    echo ""
    echo "Suggested branch: $SUGGESTED_BRANCH"
    echo ""
    echo "  A) Create '$SUGGESTED_BRANCH' from current HEAD ($BASE_BRANCH)"
    echo "  B) Enter a custom branch name"
    echo "  C) Keep working on current branch ($CURRENT)"
    echo ""
    printf "Choice [A/B/C]: "
    read -r CHOICE
  fi
  case "$CHOICE" in
    A|a)
      BRANCH="$SUGGESTED_BRANCH"
      git checkout -b "$BRANCH"
      ;;
    B|b)
      printf "Enter branch name: "
      read -r BRANCH
      git checkout -b "$BRANCH"
      SLUG=$(slugify "$(echo "$BRANCH" | sed 's/^feature\///; s/^bugfix\///; s/^hotfix\///; s/^release\///')")
      ;;
    C|c)
      BRANCH="$CURRENT"
      echo "Staying on $BRANCH."
      ;;
    *)
      echo "Invalid choice."
      exit 1
      ;;
  esac
fi

echo "Working branch: $BRANCH"

# ---- bootstrap project setup (on feature branch, no commit) -----------------

if [ ! -f "AGENTS.md" ]; then
  cp "$TEMPLATES_DIR/AGENTS.md" "AGENTS.md" 2>/dev/null && echo "Created AGENTS.md"
fi
if [ ! -d ".opensdd" ]; then
  mkdir -p ".opensdd"
  cp "$TEMPLATES_DIR/service-rules.md" ".opensdd/service-rules.md" 2>/dev/null && echo "Created .opensdd/service-rules.md"
fi

# ---- scaffold .specwork/ ----------------------------------------------------

mkdir -p ".specwork/_spec"
mkdir -p ".specwork/_state"
mkdir -p ".specwork/_progress"
mkdir -p ".specwork/_plan"

# ---- fetch source -----------------------------------------------------------

SOURCE_FILE=".specwork/_spec/${SLUG}-source.md"
SOURCE_CONTENT=""

if [ "$INPUT_TYPE" = "jira" ] && jira_is_configured; then
  echo "Fetching Jira ticket $TICKET..."
  if jira_write_issue_markdown "$TICKET" "$SOURCE_FILE" 2>/dev/null; then
    echo "Jira data written to $SOURCE_FILE"
    SOURCE_CONTENT=$(cat "$SOURCE_FILE")
    TITLE=$(printf '%s' "$SOURCE_CONTENT" | head -1 | sed 's/^# //')
  else
    echo "Jira fetch failed; falling back to manual source."
    INPUT_TYPE="freetext"
    TICKET=""
    printf '# %s\n\n%s\n' "$INPUT" "$INPUT" > "$SOURCE_FILE"
    SOURCE_CONTENT=$(cat "$SOURCE_FILE")
  fi
else
  printf '# %s\n\n%s\n' "$INPUT" "$INPUT" > "$SOURCE_FILE"
  SOURCE_CONTENT=$(cat "$SOURCE_FILE")
fi

# ---- determine source_title -------------------------------------------------

if [ -z "${TITLE:-}" ]; then
  TITLE="$INPUT"
fi

# ---- resolve slug from actual branch (in case B was chosen) -----------------

BRANCH_SLUG=$(echo "$BRANCH" | sed 's/^feature\///; s/^bugfix\///; s/^hotfix\///; s/^release\///')
if [ "$INPUT_TYPE" = "jira" ] && [[ "$BRANCH_SLUG" =~ ^[A-Za-z]+-[0-9] ]]; then
  # If the custom branch still has a ticket prefix, re-derive
  :
fi

# ---- write state.json -------------------------------------------------------

SPEC_WRITE_TIMESTAMP=$(date +%s)

cat > ".specwork/_state/${SLUG}-state.json" <<ENDJSON
{
  "schema_version": 1,
  "id": "${SLUG}",
  "branch": "${BRANCH}",
  "base_branch": "${BASE_BRANCH}",
  "ticket": $( [ -n "$TICKET" ] && echo "\"${TICKET}\"" || echo "null" ),
  "input_type": "${INPUT_TYPE}",
  "source_title": $(printf '%s' "$TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
  "spec_file": ".specwork/_spec/${SLUG}-spec.md",
  "source_file": ".specwork/_spec/${SLUG}-source.md",
  "rules_file": ".specwork/_state/${SLUG}-rules.json",
  "cache_file": ".specwork/_state/${SLUG}-implementation-cache.json",
  "metrics_mode": "${METRICS_MODE:-none}",
  "spec_write_timestamp": ${SPEC_WRITE_TIMESTAMP}
}
ENDJSON

# ---- write rules.json -------------------------------------------------------

if [ -f ".opensdd/service-rules.md" ]; then
  echo "Loading service rules from .opensdd/service-rules.md..."
  python3 - "$SLUG" "$TEMPLATES_DIR/rules.md" <<'PY'
import json, sys
from pathlib import Path

slug = sys.argv[1]
rules_md_path = Path(sys.argv[2])

rules_md = Path(".opensdd/service-rules.md").read_text(encoding="utf-8")

global_rules = []
if rules_md_path.exists():
    global_rules = [rules_md_path.read_text(encoding="utf-8")]

rules = {
    "schema_version": 1,
    "id": slug,
    "global_rules": global_rules,
    "service_rules": [rules_md],
}

Path(f".specwork/_state/{slug}-rules.json").write_text(
    json.dumps(rules, indent=2) + "\n", encoding="utf-8"
)
PY
else
  cat > ".specwork/_state/${SLUG}-rules.json" <<ENDJSON
{
  "schema_version": 1,
  "id": "${SLUG}",
  "global_rules": [],
  "service_rules": []
}
ENDJSON
fi

# ---- write implementation-cache.json ----------------------------------------

cat > ".specwork/_state/${SLUG}-implementation-cache.json" <<ENDJSON
{
  "schema_version": 1,
  "id": "${SLUG}",
  "repositories": [],
  "patterns": [],
  "related_tests": [],
  "similar_classes": [],
  "notes": []
}
ENDJSON

# ---- draft spec.md ----------------------------------------------------------

SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"

cat > "$SPEC_FILE" <<ENDSPEC
# ${SLUG} — ${TITLE}

$( [ -n "$TICKET" ] && echo "> Source: ${TICKET}" || echo "> Source: free-text input" )

## Summary

One-sentence description of what this feature does.

## Scope

### In scope

- What the feature will do

### Out of scope

- What the feature will NOT do

## Behavior

Detailed behavioral specification. Each requirement should be testable.

## Implementation Context

Files, classes, endpoints, repositories, and services relevant to this feature.

## Expected Change Scope

Concrete estimate of files and layers touched.

## Safe Constraints

### Safe

- Things the implementation MUST do

### Unsafe

- Things the implementation MUST NOT do

## Open Questions

- [ ] **#1** *Add your first open question here*
ENDSPEC

echo "Spec written to $SPEC_FILE"
echo ""
echo "============================================================"
echo "Pipeline initialized."
echo "  Branch:      $BRANCH"
echo "  Slug:        $SLUG"
echo "  State:       .specwork/_state/${SLUG}-state.json"
echo "  Spec:        $SPEC_FILE"
echo "  Source:      $SOURCE_FILE"
echo ""
echo "Next:"
echo "  Edit the spec to fill in ## Behavior, ## Implementation Context,"
echo "  and resolve ## Open Questions."
echo ""
echo "  Then run:"
echo "    /f-plan       (optional — for 3+ files)"
echo "    /f-implement   (start implementing)"
echo "============================================================"
