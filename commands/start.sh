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

# Strip the conventional prefix (feature/, bugfix/, hotfix/, release/) and
# slugify what remains. Used whenever the slug must reflect the WORKING BRANCH
# (--keep, --branch <name>, interactive B/C) rather than the raw input — which
# could be a long free-text description that would produce an unusable slug.
slug_from_branch() {
  slugify "$(echo "$1" | sed 's|^feature/||; s|^bugfix/||; s|^hotfix/||; s|^release/||')"
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

# ---- precondition: refuse to re-init over an active pipeline ----------------

if ! PYTHONPATH="$(cd "$SCRIPT_DIR/.." && pwd)" python3 -m engine.cli precheck --fresh >/dev/null 2>&1; then
  echo "✗ Pipeline already active here — not re-initializing." >&2
  echo "  • Next step:       run ./commands/status.sh to see the next pending step" >&2
  echo "  • Change the spec: run ./commands/spec.sh" >&2
  echo "  • Start over:      run ./commands/close.sh first, then start.sh" >&2
  exit 1
fi

# ---- branch decision --------------------------------------------------------

if [ "$BRANCH_FLAG" = "branch" ]; then
  BRANCH="$CUSTOM_BRANCH"
  git checkout -b "$BRANCH"
  SLUG=$(slug_from_branch "$BRANCH")
elif [ "$BRANCH_FLAG" = "keep" ]; then
  BRANCH="$CURRENT"
  SLUG=$(slug_from_branch "$BRANCH")
  echo "Staying on $BRANCH (slug: $SLUG)."
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
      SLUG=$(slug_from_branch "$BRANCH")
      ;;
    C|c)
      BRANCH="$CURRENT"
      SLUG=$(slug_from_branch "$BRANCH")
      echo "Staying on $BRANCH (slug: $SLUG)."
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
  # Bake the absolute open-sdd path into the template (same as install.sh) so the
  # command paths resolve even when $OPEN_SDD_ROOT is not exported in the shell.
  OPEN_SDD_ROOT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
  if sed "s|\$OPEN_SDD_ROOT|$OPEN_SDD_ROOT_PATH|g" "$TEMPLATES_DIR/AGENTS.md" > "AGENTS.md"; then
    echo "Created AGENTS.md"
  fi
fi
if [ ! -d ".opensdd" ]; then
  mkdir -p ".opensdd"
fi
if [ ! -f ".opensdd/service-rules.md" ]; then
  if cp "$TEMPLATES_DIR/service-rules.md" ".opensdd/service-rules.md"; then
    echo "Created .opensdd/service-rules.md"
  fi
fi
if [ ! -f ".opensdd/mr-config.json" ]; then
  if cp "$TEMPLATES_DIR/mr-config.json" ".opensdd/mr-config.json"; then
    echo "Created .opensdd/mr-config.json"
  fi
fi

# ---- scaffold .specwork/ ----------------------------------------------------

mkdir -p ".specwork/_spec"
mkdir -p ".specwork/_state"
mkdir -p ".specwork/_progress"
mkdir -p ".specwork/_plan"

# ---- ensure .specwork/ is gitignored ----------------------------------------

# .specwork/ is transient runtime state — must never be committed. start.sh
# guarantees this by appending to (or creating) .gitignore. If files were
# already tracked from a prior bad setup, warn with the exact untrack command
# (we cannot run `git rm --cached` automatically — too destructive without
# the user's intent).
GITIGNORE=".gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qE '^\.specwork(/|$)' "$GITIGNORE" 2>/dev/null; then
    printf '\n# open-sdd pipeline state (transient)\n.specwork/\n' >> "$GITIGNORE"
    echo "Appended '.specwork/' to .gitignore"
  fi
else
  printf '# open-sdd pipeline state (transient)\n.specwork/\n' > "$GITIGNORE"
  echo "Created .gitignore with '.specwork/' entry"
fi

# Warn if .specwork files are already tracked from a previous bad setup.
TRACKED_SPECWORK=$(git ls-files .specwork 2>/dev/null | head -3)
if [ -n "$TRACKED_SPECWORK" ]; then
  echo ""
  echo "⚠  Warning: .specwork/ files are already tracked in git from a prior"
  echo "   setup. .gitignore alone will not untrack them. To fix:"
  echo ""
  echo "     git rm -r --cached .specwork/"
  echo "     git commit -m 'chore: untrack .specwork/ (pipeline state is transient)'"
  echo ""
fi

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

# ---- write state.json -------------------------------------------------------

SPEC_WRITE_TIMESTAMP=$(date +%s)

cat > ".specwork/_state/${SLUG}-state.json" <<ENDJSON
{
  "schema_version": 1,
  "id": "${SLUG}",
  "slug": "${SLUG}",
  "ticket_type": "feature",
  "current_step": "spec",
  "step_index": 0,
  "retries": 0,
  "max_retries": 2,
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

# /f-start does not create spec.md — that is /f-spec's job. /f-spec reads
# source.md (written above) plus templates/spec.md and writes spec.md from
# scratch on the first call, then refines it on subsequent calls.
#
# Downstream gates (check_required_artifacts in /f-plan, /f-implement) require
# spec.md, so they naturally block until /f-spec has run. No extra check needed.
#
# current_step stays at "spec"; /f-spec advances to "plan" once the spec is
# drafted and Open Questions resolved.

echo ""
echo "============================================================"
echo "Pipeline initialized."
echo "  Branch:      $BRANCH"
echo "  Slug:        $SLUG"
echo "  State:       .specwork/_state/${SLUG}-state.json"
echo "  Source:      $SOURCE_FILE"
echo ""
echo "Next:"
echo "  ./commands/spec.sh                         (draft spec.md from source)"
echo "  ./commands/spec.sh <files|jira ID|text>    (draft with extra context)"
echo ""
echo "  After the spec is drafted and Open Questions resolved:"
echo "    /f-plan       (optional — for 3+ files)"
echo "    /f-implement   (start implementing)"
echo "============================================================"
