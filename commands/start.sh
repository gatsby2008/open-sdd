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

# Agent harnesses drop a project-memory file at the repo root: opencode's /init
# (and proactive models) write AGENTS.md, Claude writes CLAUDE.md, Gemini writes
# GEMINI.md. These are legitimate, version-controllable context — not feature WIP
# — so they must not block /f-start on a base branch. git checkout -b carries them
# onto the new feature branch, where they get committed with the rest of the work.
tree_is_clean() {
  git status --porcelain -- . \
    ':(exclude)AGENTS.md' ':(exclude)CLAUDE.md' ':(exclude)GEMINI.md' \
    2>/dev/null | grep -q . && return 1 || return 0
}

# ---- main -------------------------------------------------------------------

BRANCH_FLAG=""
CUSTOM_BRANCH=""
CHOOSE_OVERRIDE=""
INPUT=""        # full raw positional input (ticket + free text), for diagnostics
FIRST_POS=""    # first positional token — used to detect a leading Jira ticket
DESC=""         # supplementary free text typed after a ticket (or, when there
                # is no ticket, the whole description)
INPUT_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)    BRANCH_FLAG="keep"; shift ;;
    --branch)  BRANCH_FLAG="branch"; shift; CUSTOM_BRANCH="${1:-}"; [ -z "$CUSTOM_BRANCH" ] && { echo "Error: --branch requires a name"; exit 1; }; shift ;;
    --choose)  BRANCH_FLAG="choose"; shift; CHOOSE_OVERRIDE="${1:-}"; [ -z "$CHOOSE_OVERRIDE" ] && { echo "Error: --choose requires A, C, or a branch name"; exit 1; }; shift ;;
    --input-file) shift; INPUT_FILE="${1:-}"; [ -z "$INPUT_FILE" ] && { echo "Error: --input-file requires a file path"; exit 1; }; shift ;;
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

# --input-file overrides positional args: reads full text from file,
# bypassing shell quoting issues with special characters.
if [ -n "$INPUT_FILE" ]; then
  [ ! -f "$INPUT_FILE" ] && { echo "Error: --input-file not found: $INPUT_FILE"; exit 1; }
  INPUT=$(cat "$INPUT_FILE")
  FIRST_POS=$(head -1 "$INPUT_FILE")
fi

[ -z "$INPUT" ] && {
  echo "Usage: /f-start <TICKET-123|description> [extra description] [--branch <name>] [--keep] [--input-file <path>]"
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
      echo "Working tree has changes on $CURRENT. Commit or stash first." >&2
      echo "(Agent-memory files like AGENTS.md/CLAUDE.md/GEMINI.md are exempt and" >&2
      echo " do not block /f-start — they ride onto the new feature branch.)" >&2
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

# ---- Jira preflight (before creating any artifacts) -------------------------

JIRA_JSON=""
if [ "$INPUT_TYPE" = "jira" ]; then
  if ! jira_is_configured; then
    echo "" >&2
    echo "✗ Jira is not configured. Set the following environment variables and retry:" >&2
    echo "" >&2
    echo "  export JIRA_BASE_URL=https://<your-domain>.atlassian.net" >&2
    echo "  export JIRA_USER=your@email.com" >&2
    echo "  export JIRA_TOKEN=<personal-access-token>" >&2
    echo "" >&2
    echo "Run /f-start again once Jira is configured." >&2
    exit 1
  fi
  echo "Fetching Jira ticket $TICKET..."
  JIRA_JSON=$(jira_fetch_issue_json "$TICKET") || {
    echo "" >&2
    echo "✗ Cannot reach Jira for ticket $TICKET. No pipeline artifacts were created." >&2
    echo "  Fix the connection or credentials and run /f-start again." >&2
    exit 1
  }
fi

# ---- branch decision --------------------------------------------------------

if [ "$BRANCH_FLAG" = "choose" ]; then
  # Agent-driven choice: --choose A|C|<branch-name>. Avoids needing a TTY.
  case "$CHOOSE_OVERRIDE" in
    A|a)
      BRANCH="$SUGGESTED_BRANCH"
      git checkout -b "$BRANCH"
      ;;
    C|c)
      BRANCH="$CURRENT"
      SLUG=$(slug_from_branch "$BRANCH")
      echo "Staying on $BRANCH (slug: $SLUG)."
      ;;
    *)
      # Treat as a branch name directly (e.g. --choose feature/my-fix)
      BRANCH="$CHOOSE_OVERRIDE"
      git checkout -b "$BRANCH"
      SLUG=$(slug_from_branch "$BRANCH")
      ;;
  esac
elif [ "$BRANCH_FLAG" = "branch" ]; then
  BRANCH="$CUSTOM_BRANCH"
  git checkout -b "$BRANCH"
  SLUG=$(slug_from_branch "$BRANCH")
elif [ "$BRANCH_FLAG" = "keep" ]; then
  BRANCH="$CURRENT"
  SLUG=$(slug_from_branch "$BRANCH")
  echo "Staying on $BRANCH (slug: $SLUG)."
else
  if [ ! -t 0 ]; then
    echo "✗ No branch flag given and no interactive terminal to prompt for one." >&2
    echo "  Re-run with one of:" >&2
    echo "    --choose A           # create the suggested branch ($SUGGESTED_BRANCH)" >&2
    echo "    --choose C | --keep  # stay on the current branch ($CURRENT)" >&2
    echo "    --branch <name>      # create a custom branch" >&2
    exit 1
  fi
  echo ""
  echo "Suggested branch: $SUGGESTED_BRANCH"
  echo ""
  echo "  A) Create '$SUGGESTED_BRANCH' from current HEAD ($BASE_BRANCH)"
  echo "  B) Enter a custom branch name"
  echo "  C) Keep working on current branch ($CURRENT)"
  echo ""
  printf "Choice [A/B/C]: "
  read -r CHOICE
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
# Service rules: prefer the team's shared, committed per-topic rules under
# .claude/rules/*.md. When present, sync them into the personal (gitignored)
# .opensdd/service-rules.md inside a managed block; content outside the block is
# preserved for personal, local-only rules. Fall back to the template only when
# neither the shared rules nor a personal file exists.
if ls .claude/rules/*.md >/dev/null 2>&1; then
  python3 - <<'PY'
from pathlib import Path

BEGIN = "<!-- BEGIN imported from .claude/rules (auto-generated by open-sdd; do not edit this block) -->"
END = "<!-- END imported from .claude/rules -->"

parts = []
for p in sorted(Path(".claude/rules").glob("*.md")):
    if p.name.lower() == "readme.md" or p.name.startswith("_"):
        continue
    parts.append(f"<!-- source: {p.as_posix()} -->\n{p.read_text(encoding='utf-8').rstrip()}")
block = BEGIN + "\n\n" + "\n\n".join(parts) + "\n\n" + END

target = Path(".opensdd/service-rules.md")
existing = target.read_text(encoding="utf-8") if target.exists() else ""

# Preserve personal content outside any previous managed block.
personal = existing
if BEGIN in existing and END in existing:
    head, rest = existing.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    personal = head + tail
personal = personal.strip()

target.write_text(block + ("\n\n" + personal + "\n" if personal else "\n"), encoding="utf-8")
print("Synced .opensdd/service-rules.md from .claude/rules/")
PY
elif [ ! -f ".opensdd/service-rules.md" ]; then
  if cp "$TEMPLATES_DIR/service-rules.md" ".opensdd/service-rules.md"; then
    echo "Created .opensdd/service-rules.md"
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
#   - .opensdd/   per-developer pipeline config (service-rules.md)
#   - AGENTS.md / CLAUDE.md / GEMINI.md  per-developer agent memory config
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
for AGENT_FILE in AGENTS.md CLAUDE.md GEMINI.md; do
  if [ -f "$AGENT_FILE" ] && ! grep -qxF "$AGENT_FILE" "$GITIGNORE" 2>/dev/null; then
    printf '%s\n' "$AGENT_FILE" >> "$GITIGNORE"
    echo "Appended '$AGENT_FILE' to .gitignore"
  fi
done

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
for AGENT_FILE in AGENTS.md CLAUDE.md GEMINI.md; do
  TRACKED_FILE=$(git ls-files "$AGENT_FILE" 2>/dev/null | head -1)
  if [ -n "$TRACKED_FILE" ]; then
    echo ""
    echo "⚠  Warning: $AGENT_FILE is already tracked in git. Agent-memory files"
    echo "   are local to each developer. .gitignore alone will not untrack it."
    echo "   To untrack while keeping the local file:"
    echo ""
    echo "     git rm --cached $AGENT_FILE"
    echo "     git commit -m 'chore: untrack $AGENT_FILE (local agent config)'"
    echo ""
  fi
done

# ---- fetch source -----------------------------------------------------------

SOURCE_FILE=".specwork/_spec/${SLUG}-source.md"
SOURCE_CONTENT=""

if [ "$INPUT_TYPE" = "jira" ]; then
  # JIRA_JSON was fetched and validated before branch creation
  printf '%s\n' "$JIRA_JSON" | jira_render_issue_markdown > "$SOURCE_FILE"
  echo "Jira data written to $SOURCE_FILE"
  if [ -n "$DESC" ]; then
    printf '\n## Additional context (from /f-start)\n\n%s\n' "$DESC" >> "$SOURCE_FILE"
  fi
  SOURCE_CONTENT=$(cat "$SOURCE_FILE")
  TITLE=$(printf '%s' "$SOURCE_CONTENT" | head -1 | sed 's/^# //')
elif [ -n "$INPUT_FILE" ]; then
  # --input-file: source is the file content verbatim (no shell quoting issues)
  cp "$INPUT_FILE" "$SOURCE_FILE"
  SOURCE_CONTENT=$(cat "$SOURCE_FILE")
  echo "Input file copied to $SOURCE_FILE"
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
  "source_has_body": $( [ -n "$(printf '%s' "$SOURCE_CONTENT" | tail -n +3 | tr -d '[:space:]')" ] && echo "true" || echo "false" ),
  "source_title": $(printf '%s' "$TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
  "spec_file": ".specwork/_spec/${SLUG}-spec.md",
  "source_file": ".specwork/_spec/${SLUG}-source.md",
  "rules_file": ".specwork/_state/${SLUG}-rules.json",
  "cache_file": ".specwork/_state/${SLUG}-implementation-cache.json",
  "spec_write_timestamp": ${SPEC_WRITE_TIMESTAMP}
}
ENDJSON

# ---- write rules.json -------------------------------------------------------

python3 - "$SLUG" "$TEMPLATES_DIR/rules.md" <<'PY'
import json, sys
from pathlib import Path

slug = sys.argv[1]
rules_md_path = Path(sys.argv[2])

# Collect service rules: legacy single file + optional .opensdd/rules/*.md directory.
service_rules = []
legacy = Path(".opensdd/service-rules.md")
if legacy.exists():
    service_rules.append(legacy.read_text(encoding="utf-8"))
rules_dir = Path(".opensdd/rules")
if rules_dir.is_dir():
    for f in sorted(rules_dir.glob("*.md")):
        service_rules.append(f.read_text(encoding="utf-8"))

global_rules = []
if rules_md_path.exists():
    global_rules = [rules_md_path.read_text(encoding="utf-8")]

rules = {
    "schema_version": 1,
    "id": slug,
    "global_rules": global_rules,
    "service_rules": service_rules,
}
Path(f".specwork/_state/{slug}-rules.json").write_text(
    json.dumps(rules, indent=2) + "\n", encoding="utf-8"
)
PY
if [ -f ".opensdd/service-rules.md" ] || { [ -d ".opensdd/rules" ] && ls .opensdd/rules/*.md >/dev/null 2>&1; }; then
  echo "Service rules loaded."
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
