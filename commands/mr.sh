#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

source "$LIB_DIR/gates.sh"

# ---- state ------------------------------------------------------------------

SLUG=""
STATE_FILE=""
SPEC_FILE=""
PLAN_JSON_FILE=""

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- resolve slug -----------------------------------------------------------

SLUG=$(resolve_slug) || die "Could not resolve slug."
STATE_FILE=".specwork/_state/${SLUG}-state.json"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
PLAN_JSON_FILE=".specwork/_plan/${SLUG}-plan.json"

# /f-mr is artifact-driven and re-runnable. Standalone (git-only) mode allowed
# when no pipeline state exists — MR description is generated from git history.

# ---- pre-flight -------------------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Determine the target branch for the MR.
# Priority: 1) .opensdd/mr-config.json, 2) origin/HEAD, 3) remote query, 4) main.
DEFAULT_BRANCH=""
CONFIG_FILE=".opensdd/mr-config.json"
if [ -f "$CONFIG_FILE" ]; then
  DEFAULT_BRANCH=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('target_branch',''))" 2>/dev/null || true)
fi
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
fi
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' || true)
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"

# An MR from the default branch to itself is meaningless.
if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  die "You are on the default branch ('$DEFAULT_BRANCH'). Create a feature branch before opening an MR."
fi

# Verify this branch has commits the base does not — otherwise the MR is empty.
# Prefer the remote base ref; fall back to a local one.
if git rev-parse --verify --quiet "origin/$DEFAULT_BRANCH" >/dev/null; then
  BASE_REF="origin/$DEFAULT_BRANCH"
elif git rev-parse --verify --quiet "$DEFAULT_BRANCH" >/dev/null; then
  BASE_REF="$DEFAULT_BRANCH"
else
  BASE_REF=""
fi
# If the base cannot be resolved we cannot prove the MR is non-empty; refuse rather
# than run the quality gate (and open an MR) blindly.
if [ -z "$BASE_REF" ]; then
  die "Could not resolve base branch '$DEFAULT_BRANCH' (no origin/$DEFAULT_BRANCH or local $DEFAULT_BRANCH). Fetch it first: git fetch origin $DEFAULT_BRANCH"
fi
AHEAD=$(git rev-list --count "$BASE_REF..HEAD" 2>/dev/null || echo 0)
if [ "$AHEAD" -eq 0 ]; then
  echo "No commits on '$BRANCH' beyond '$BASE_REF' — nothing to open an MR for."
  echo "Commit your work first (/f-commit)."
  exit 1
fi

# ---- determine the host provider --------------------------------------------
# The target host is the project's own remote, NOT where open-sdd lives. An
# explicit OPEN_SDD_MR_PROVIDER (github|gitlab) wins; otherwise infer from origin.

PROVIDER="${OPEN_SDD_MR_PROVIDER:-}"
if [ -z "$PROVIDER" ]; then
  ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
  case "$ORIGIN_URL" in
    *github.com*) PROVIDER="github" ;;
    *gitlab*)     PROVIDER="gitlab" ;;
    *) die "Could not determine the git host from origin ('${ORIGIN_URL:-none}').
Set OPEN_SDD_MR_PROVIDER=github|gitlab to choose explicitly." ;;
  esac
fi
echo "Host: $PROVIDER"

case "$PROVIDER" in
  github)
    command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required but not installed. Install: https://cli.github.com/"
    gh auth status >/dev/null 2>&1 || die "Not authenticated with GitHub CLI. Run: gh auth login" ;;
  gitlab)
    command -v glab >/dev/null 2>&1 || die "GitLab CLI (glab) is required but not installed. Install: https://gitlab.com/gitlab-org/cli"
    glab auth status >/dev/null 2>&1 || die "Not authenticated with GitLab CLI. Run: glab auth login" ;;
  *)
    die "Unknown provider '$PROVIDER'. Use OPEN_SDD_MR_PROVIDER=github|gitlab." ;;
esac

# ---- quality gate: run tests (skip if HEAD was already validated by f-commit) -

HEAD_SHA=$(git rev-parse HEAD)
CHECKED_SHA=""
if [ -f "$STATE_FILE" ]; then
  CHECKED_SHA=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('checked_sha',''))" "$STATE_FILE" 2>/dev/null || true)
fi

if [ -n "$CHECKED_SHA" ] && [ "$HEAD_SHA" = "$CHECKED_SHA" ]; then
  echo "Skipping pre-push checks — HEAD already validated by f-commit ($HEAD_SHA)."
else
  echo "Running pre-push checks..."
  CHECK_SCRIPT="$SCRIPT_DIR/check.sh"
  if [ -f "./commands/check.sh" ]; then
    CHECK_SCRIPT="./commands/check.sh"
    echo "Using project-local commands/check.sh"
  fi
  bash "$CHECK_SCRIPT" || { echo "Checks failed. Fix issues before pushing."; exit 1; }
fi
echo ""

# ---- build MR body ----------------------------------------------------------

echo ""
fmt_bold "Building merge request..."

PLAN_TEXT=""
if [ -f "$PLAN_JSON_FILE" ]; then
  PLAN_TEXT=$(python3 - "$PLAN_JSON_FILE" "$SPEC_FILE" -c '
import json, sys
from pathlib import Path
plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
spec = Path(sys.argv[2]).read_text(encoding="utf-8")

import re
desc_match = re.search(r"(?ms)^## Description\s*\n+(.*?)(?=\n## |\Z)", spec)
description = desc_match.group(1).strip() if desc_match else ""
if len(description) > 500:
    description = description[:500] + "..."

ctx_match = re.search(r"(?ms)^## Implementation Context\s*\n+(.*?)(?=\n## |\Z)", spec)
context = ctx_match.group(1).strip() if ctx_match else ""

targets = plan.get("target_files", [])
target_lines = "\n".join(f"- `{t[\"path\"]}` - {t.get(\"change\", \"\")}" for t in targets)

risk_lines = ""
risk = plan.get("risk_signals", {})
if risk:
    risk_lines = "\n**Risk signals detected during planning:**\n"
    for sig, matches in risk.items():
        risk_lines += f"- {sig}: {matches}\n"

body = f"""## Description

{description}

## Changes

{target_lines}

## Implementation Context

{context}
{risk_lines}
## Checklist

- [ ] Spec-driven implementation
- [ ] Code builds locally
- [ ] Tests pass
- [ ] Self-review completed
"""
print(body)
')
else
  PLAN_TEXT="No plan file found."
fi

# ---- publish spec to docs/specs/ (in-repo, pipeline mode only) --------------
# Snapshot the final spec into the repo and commit it BEFORE push, so it lands
# inside the MR diff and history. Standalone-safe (skips when no .specwork spec)
# and idempotent (only commits when the file is new or changed). Independent of
# and complementary to the external spec-registry publish below — both run.

if [ -n "${SPEC_FILE:-}" ] && [ -f "$SPEC_FILE" ]; then
  mkdir -p docs/specs
  cp "$SPEC_FILE" "docs/specs/${SLUG}-spec.md"
  git add "docs/specs/${SLUG}-spec.md"
  if ! git diff --cached --quiet -- "docs/specs/${SLUG}-spec.md"; then
    git commit -m "docs: publish spec to docs/specs/${SLUG}-spec.md"
    echo "Published spec to docs/specs/${SLUG}-spec.md"
  fi
fi

# ---- push branch ------------------------------------------------------------

echo ""
echo "Pushing branch $BRANCH to origin..."
git push -u origin "$BRANCH" 2>&1 || echo "(push may have already been done)"

# ---- determine MR title -----------------------------------------------------

SPEC_TITLE=$(head -1 "$SPEC_FILE" 2>/dev/null | sed 's/^# //' || echo "$SLUG")
TICKET=$(python3 - "$STATE_FILE" 2>/dev/null || true)
python3 - "$STATE_FILE" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
tid = state.get("ticket_id", "")
if tid:
    print(tid)
PY

if [ -n "$TICKET" ]; then
  MR_TITLE="[$TICKET] $SPEC_TITLE"
else
  MR_TITLE="$SPEC_TITLE"
fi

# Write MR body to a temp file (gh reads it via --body-file; glab via cat)
MR_BODY_FILE=$(mktemp)
echo "$PLAN_TEXT" > "$MR_BODY_FILE"

# ---- fix MR title format ----------------------------------------------------

TICKET=$(echo "$BRANCH" | sed -n 's/.*\/\([A-Z][A-Z0-9]*-[0-9]*\).*/\1/p')
if [ -n "$TICKET" ]; then
  MR_TITLE="[$TICKET] feat: $SPEC_TITLE"
else
  MR_TITLE="feat: $SPEC_TITLE"
fi

# ---- create or update MR ----------------------------------------------------

echo ""
fmt_bold "Looking for existing MR..."

if [ "$PROVIDER" = "github" ]; then
  EXISTING_MR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -n "$EXISTING_MR" ]; then
    echo "Found existing MR #$EXISTING_MR. Updating..."
    gh pr edit "$EXISTING_MR" --title "$MR_TITLE" --body-file "$MR_BODY_FILE" 2>&1
    MR_URL=$(gh pr view "$EXISTING_MR" --json url --jq '.url' 2>/dev/null || echo "#$EXISTING_MR")
    echo "Updated: $MR_URL"
  else
    echo "Creating new MR..."
    MR_URL=$(gh pr create --base "$DEFAULT_BRANCH" --head "$BRANCH" \
      --title "$MR_TITLE" --body-file "$MR_BODY_FILE" 2>&1)
    echo "Created: $MR_URL"
  fi
else
  # gitlab — glab accepts a branch name in place of an MR id
  MR_DESC=$(cat "$MR_BODY_FILE")
  if glab mr view "$BRANCH" -F json >/dev/null 2>&1; then
    echo "Found existing MR for '$BRANCH'. Updating..."
    glab mr update "$BRANCH" --title "$MR_TITLE" --description "$MR_DESC" 2>&1
    MR_URL=$(glab mr view "$BRANCH" -F json 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("web_url",""))' 2>/dev/null || echo "")
    echo "Updated: ${MR_URL:-$BRANCH}"
  else
    echo "Creating new MR..."
    MR_URL=$(glab mr create --source-branch "$BRANCH" --target-branch "$DEFAULT_BRANCH" \
      --title "$MR_TITLE" --description "$MR_DESC" --yes 2>&1 \
      | grep -Eo 'https?://[^[:space:]]+' | tail -1)
    echo "Created: ${MR_URL:-(see glab output above)}"
  fi
fi

rm -f "$MR_BODY_FILE"

# ---- publish spec to central registry (pipeline mode only) ------------------
# Inlined from the removed lib/spec-publish.sh (merged into doc-spec).

if [ -n "${SPEC_FILE:-}" ] && [ -f "$SPEC_FILE" ]; then
  . "$LIB_DIR/service-name.sh"
  REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/spec-registry"
  SERVICE="$(resolve_service_name)"
  DEST="$REGISTRY/$SERVICE"
  mkdir -p "$DEST"
  if [ -f "$DEST/$(basename "$SPEC_FILE")" ]; then
    echo "  Spec already exists at $DEST/$(basename "$SPEC_FILE") — skipping publish."
  else
    cp "$SPEC_FILE" "$DEST/$(basename "$SPEC_FILE")"
    echo "  Spec published -> $DEST/$(basename "$SPEC_FILE")"
  fi
fi || true

# ---- update state.json with MR URL (pipeline mode only) ---------------------

if [ -f "$STATE_FILE" ]; then
  python3 - "$STATE_FILE" "$MR_URL" <<'PY'
import json, sys
from pathlib import Path
fp = Path(sys.argv[1])
url = sys.argv[2]
data = json.loads(fp.read_text(encoding="utf-8"))
data["mr_url"] = url
fp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  echo "State updated with MR URL."
fi

# ---- ADR hint -----------------------------------------------------------------

if [ -f "$SPEC_FILE" ]; then
  RESOLVED_OQS=$(grep -c '^- \[x\]' "$SPEC_FILE" 2>/dev/null || true)
  if [ "$RESOLVED_OQS" -gt 0 ]; then
    echo ""
    echo "Tip: this spec had Open Questions resolved during planning."
    echo "Consider running: /doc-adr open-questions"
    echo "to capture those decisions as ADRs in docs/adr/ before the MR is merged."
  fi
fi

echo ""
echo "Next steps:"
echo "  - Review the MR at $MR_URL"
echo "  - After merge, run: /f-close"
