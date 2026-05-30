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
CONFIRM_BRANCH=0
INPUT=""        # full raw positional input (ticket + free text), for diagnostics
FIRST_POS=""    # first positional token — used to detect a leading Jira ticket
DESC=""         # supplementary free text typed after a ticket (or, when there
                # is no ticket, the whole description)
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)    BRANCH_FLAG="keep"; shift ;;
    --branch)  BRANCH_FLAG="branch"; shift; CUSTOM_BRANCH="${1:-}"; [ -z "$CUSTOM_BRANCH" ] && { echo "Error: --branch requires a name"; exit 1; }; shift ;;
    --confirm-branch) CONFIRM_BRANCH=1; shift ;;
    *)
      if [ -z "$FIRST_POS" ]; then
        FIRST_POS="$1"
        INPUT="$1"
      else
        INPUT="$INPUT $1"
        DESC="${DESC:+$DESC }$1"
      fi
      shift ;;
  esac
done

[ -z "$INPUT" ] && {
  echo "Usage: /f-start <TICKET-123|description> [extra description] [--branch <name>] [--keep]"
  exit 1
}

# A leading token like IR-94 is a Jira ticket; everything after it is free-text
# context (DESC). When the first token is not a ticket, the whole input is DESC.
INPUT_TYPE=$(detect_ticket "$FIRST_POS")
if [ "$INPUT_TYPE" = "jira" ]; then
  TICKET="$FIRST_POS"
  SLUG=$(slugify "$TICKET")
else
  TICKET=""
  DESC="$INPUT"
  SLUG=$(slugify "$INPUT" | sed -E 's/^-+//; s/-+$//')
fi
SUGGESTED_BRANCH="feature/${SLUG}"

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
  echo "  • Next step:       run /f-status to see the next pending step" >&2
  echo "  • Change the spec: run /f-spec" >&2
  echo "  • Start over:      run /f-close first, then /f-start" >&2
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
  if [ -t 0 ] && { [ "${SDD_NON_INTERACTIVE:-0}" != "1" ] || [ "$CONFIRM_BRANCH" = "1" ]; }; then
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

# ---- ensure transient/generated artifacts are gitignored --------------------

# Pipeline artifacts are local to each developer and must not be committed:
#   - .specwork/  transient pipeline runtime state
#   - .opensdd/   per-developer pipeline config (service-rules.md, mr-config.json)
GITIGNORE=".gitignore"
[ -f "$GITIGNORE" ] || : > "$GITIGNORE"

if ! grep -qE '^\.specwork(/|$)' "$GITIGNORE" 2>/dev/null; then
  printf '\n# open-sdd pipeline state (transient)\n.specwork/\n' >> "$GITIGNORE"
  echo "Appended '.specwork/' to .gitignore"
fi
if ! grep -qE '^\.opensdd(/|$)' "$GITIGNORE" 2>/dev/null; then
  printf '\n# open-sdd pipeline config (local to each developer)\n.opensdd/\n' >> "$GITIGNORE"
  echo "Appended '.opensdd/' to .gitignore"
fi

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

TRACKED_OPENSDD=$(git ls-files .opensdd 2>/dev/null | head -3)
if [ -n "$TRACKED_OPENSDD" ]; then
  echo ""
  echo "⚠  Warning: .opensdd/ files are already tracked in git. Pipeline config"
  echo "   is local to each developer. .gitignore alone will not untrack them."
  echo "   To untrack while keeping the local files:"
  echo ""
  echo "     git rm -r --cached .opensdd/"
  echo "     git commit -m 'chore: untrack .opensdd/ (local pipeline config)'"
  echo ""
fi

# ---- fetch source -----------------------------------------------------------

SOURCE_FILE=".specwork/_spec/${SLUG}-source.md"
SOURCE_CONTENT=""

if [ "$INPUT_TYPE" = "jira" ] && jira_is_configured; then
  echo "Fetching Jira ticket $TICKET..."
  if jira_write_issue_markdown "$TICKET" "$SOURCE_FILE" 2>/dev/null; then
    echo "Jira data written to $SOURCE_FILE"
    # Preserve any supplementary free text the user passed alongside the ticket.
    if [ -n "$DESC" ]; then
      printf '\n## Additional context (from /f-start)\n\n%s\n' "$DESC" >> "$SOURCE_FILE"
    fi
    SOURCE_CONTENT=$(cat "$SOURCE_FILE")
    TITLE=$(printf '%s' "$SOURCE_CONTENT" | head -1 | sed 's/^# //')
  else
    echo "Jira fetch failed; falling back to manual source."
    # Never lose the user's input: keep the ticket id as the title and use the
    # free-text description (if any) as the body. The ticket reference is kept in
    # state.json so /f-mr and others can still link it.
    printf '# %s\n\n%s\n' "$TICKET" "${DESC:-$TICKET}" > "$SOURCE_FILE"
    INPUT_TYPE="freetext"
    TITLE="$TICKET"
    SOURCE_CONTENT=$(cat "$SOURCE_FILE")
  fi
elif [ -n "$TICKET" ]; then
  # Ticket given but Jira is not configured — keep the id as title and the
  # free text as the body so nothing the user typed is dropped.
  printf '# %s\n\n%s\n' "$TICKET" "${DESC:-$TICKET}" > "$SOURCE_FILE"
  INPUT_TYPE="freetext"
  TITLE="$TICKET"
  SOURCE_CONTENT=$(cat "$SOURCE_FILE")
else
  printf '# %s\n\n%s\n' "$INPUT" "$DESC" > "$SOURCE_FILE"
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
  "branch": "${BRANCH}",
  "base_branch": "${BASE_BRANCH}",
  "ticket": $( [ -n "$TICKET" ] && echo "\"${TICKET}\"" || echo "null" ),
  "input_type": "${INPUT_TYPE}",
  "non_interactive": $( [ "${SDD_NON_INTERACTIVE:-0}" = "1" ] && echo "true" || echo "false" ),
  "source_title": $(printf '%s' "$TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
  "spec_file": ".specwork/_spec/${SLUG}-spec.md",
  "source_file": ".specwork/_spec/${SLUG}-source.md",
  "rules_file": ".specwork/_state/${SLUG}-rules.json",
  "cache_file": ".specwork/_state/${SLUG}-implementation-cache.json",
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
# spec.md, so they naturally block until /f-spec has run. The pipeline is
# artifact-driven — no current_step tracking, no state machine.

echo ""
echo "============================================================"
echo "Pipeline initialized."
echo "  Branch:      $BRANCH"
echo "  Slug:        $SLUG"
echo "  State:       .specwork/_state/${SLUG}-state.json"
echo "  Source:      $SOURCE_FILE"
echo ""
echo "Next:"
echo "  /f-spec                          (draft spec.md from source)"
echo "  /f-spec <files|jira ID|text>     (draft with extra context)"
echo ""
echo "  After the spec is drafted and Open Questions resolved:"
echo "    /f-plan       (optional — for 3+ files)"
echo "    /f-implement   (start implementing)"
echo "============================================================"
