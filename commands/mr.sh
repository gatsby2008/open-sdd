#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

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

# ---- pre-flight -------------------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Check for pushed commits
CURRENT_SHA=$(git rev-parse HEAD)
ORIGIN_SHA=$(git rev-parse "@{upstream}" 2>/dev/null || echo "")

if [ "$CURRENT_SHA" = "$ORIGIN_SHA" ]; then
  echo "No new commits to push. Did you forget to commit?"
  echo "Run ./commands/commit.sh first."
  exit 1
fi

# Check gh is installed
if ! command -v gh &>/dev/null; then
  echo "GitHub CLI (gh) is required but not installed."
  echo "Install: https://cli.github.com/"
  exit 1
fi

# Check gh auth
if ! gh auth status 2>/dev/null; then
  echo "Not authenticated with GitHub CLI."
  echo "Run: gh auth login"
  exit 1
fi

# ---- determine default branch -----------------------------------------------

DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")

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

# Write MR body to temp file for use with gh
MR_BODY_FILE=$(mktemp)
echo "$PLAN_TEXT" > "$MR_BODY_FILE"

# ---- create or update MR ----------------------------------------------------

echo ""
fmt_bold "Looking for existing MR..."

EXISTING_MR=$(gh pr list --head "$BRANCH" --json number,title --jq '.[0].number // empty' 2>/dev/null || true)

if [ -n "$EXISTING_MR" ]; then
  echo "Found existing MR #$EXISTING_MR. Updating..."
  gh pr edit "$EXISTING_MR" \
    --title "$MR_TITLE" \
    --body-file "$MR_BODY_FILE" 2>&1
  MR_URL=$(gh pr view "$EXISTING_MR" --json url --jq '.url' 2>/dev/null || echo "#$EXISTING_MR")
  echo "Updated: $MR_URL"
else
  echo "Creating new MR..."
  MR_URL=$(gh pr create \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH" \
    --title "$MR_TITLE" \
    --body-file "$MR_BODY_FILE" 2>&1)
  echo "Created: $MR_URL"
fi

rm -f "$MR_BODY_FILE"

# ---- update state.json with MR URL ------------------------------------------

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
echo ""
echo "Next steps:"
echo "  - Review the MR at $MR_URL"
echo "  - After merge, run: ./commands/close.sh"
