#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# ---- step 1: prerequisites --------------------------------------------------

if [ ! -d ".specwork/_state" ]; then
  echo "No SDD pipeline found in .specwork/. Nothing to resync."
  exit 0
fi

shopt -s nullglob 2>/dev/null
STATE_FILES=(.specwork/_state/*-state.json)
if [ ${#STATE_FILES[@]} -eq 0 ]; then
  echo "No state.json found under .specwork/_state/. Nothing to resync."
  exit 0
fi

# ---- step 2: parse arguments ------------------------------------------------

if [ $# -gt 1 ]; then
  die "Usage:
  /f-resync                          Sync pipeline with current branch (no git ops).
  /f-resync feature/IR-70-foo        Rename branch then sync (atomic)."
fi

ATOMIC=false
if [ $# -eq 1 ]; then
  ATOMIC=true
  NEW_BRANCH="$1"
fi

# ---- step 3: rename branch (atomic mode) ------------------------------------

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "$ATOMIC" = true ]; then
  if [ "$CURRENT_BRANCH" != "$NEW_BRANCH" ]; then
    echo "Renaming branch: $CURRENT_BRANCH → $NEW_BRANCH"
    git branch -m "$NEW_BRANCH"
    CURRENT_BRANCH=$NEW_BRANCH
  fi
fi

# ---- step 4: derive slug, ticket, input_type --------------------------------

# Write derivation script to temp file to avoid heredoc-in-$(...) issues
PY_SCRIPT=$(mktemp)
cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys
branch = sys.argv[1]
unprefixed = re.sub(r'^(feature|hotfix|release|bugfix)/', '', branch)
slug = re.sub(r'-+', '-', re.sub(r'[^a-z0-9]+', '-', unprefixed.lower())).strip('-')
strict = re.match(r'^([A-Z]+-[0-9]+)(?:-|$)', unprefixed.upper())
loose  = re.match(r'^([A-Z]+-[0-9.]+)(?:-|$)', unprefixed.upper())
if strict:
    ticket, input_type = strict.group(1), "jira"
elif loose:
    ticket, input_type = loose.group(1), "freetext"
else:
    ticket, input_type = "", "freetext"
print(f"slug={slug}")
print(f"ticket={ticket}")
print(f"input_type={input_type}")
PYEOF

DERIVED=$(python3 "$PY_SCRIPT" "$CURRENT_BRANCH" 2>/dev/null)
rm -f "$PY_SCRIPT"

NEW_SLUG=$(echo "$DERIVED" | grep "^slug=" | cut -d= -f2-)
TICKET=$(echo "$DERIVED" | grep "^ticket=" | cut -d= -f2-)
INPUT_TYPE=$(echo "$DERIVED" | grep "^input_type=" | cut -d= -f2-)

if [ -z "$NEW_SLUG" ]; then
  die "Could not derive a valid slug from branch name '$CURRENT_BRANCH'."
fi

# ---- step 5: identify old slug & collision check ----------------------------

PY_SCRIPT=$(mktemp)
cat > "$PY_SCRIPT" <<'PYEOF'
import glob, json, sys
states = sorted(glob.glob(".specwork/_state/*-state.json"))
if not states:
    sys.exit("No state.json files found.")
current = sys.argv[1]
matches = []
for s in states:
    try:
        if json.load(open(s)).get('branch') == current:
            matches.append(s)
    except Exception:
        pass
if matches:
    print(matches[0])
elif len(states) == 1:
    print(states[0])
else:
    sys.exit(f"Multiple state.json files and none matches current branch '{current}'.")
PYEOF

OLD_STATE_PY=$(python3 "$PY_SCRIPT" "$CURRENT_BRANCH" 2>/dev/null || true)
rm -f "$PY_SCRIPT"

[ -n "$OLD_STATE_PY" ] || die "Could not identify active state.json."

OLD_STATE="$OLD_STATE_PY"
OLD_SLUG=$(basename "$OLD_STATE" | sed -E 's/-state\.json$//')

# Collision check
if [ "$OLD_SLUG" != "$NEW_SLUG" ] && [ -f ".specwork/_state/${NEW_SLUG}-state.json" ]; then
  die "Refusing to resync — a different pipeline already exists at slug '${NEW_SLUG}'.
Run /f-close on one of them first, or pick a different branch name."
fi

# ---- step 6: rename files ---------------------------------------------------

RENAMED_COUNT=0
RENAMED_FILES=""

if [ "$OLD_SLUG" != "$NEW_SLUG" ]; then
  while IFS= read -r -d '' f; do
    dir=$(dirname "$f")
    base=$(basename "$f")
    new_base="${NEW_SLUG}${base#"$OLD_SLUG"}"
    mv "$f" "$dir/$new_base"
    RENAMED_FILES+="  .specwork/${dir#.specwork/}/$new_base"$'\n'
    RENAMED_COUNT=$((RENAMED_COUNT + 1))
  done < <(find .specwork -type f -name "${OLD_SLUG}-*" -print0 2>/dev/null || true)
fi

# ---- step 7: update state.json content --------------------------------------

NEW_STATE=".specwork/_state/${NEW_SLUG}-state.json"

if [ -f "$NEW_STATE" ]; then
  python3 - "$NEW_STATE" "$NEW_SLUG" "$OLD_SLUG" "$CURRENT_BRANCH" "$TICKET" "$INPUT_TYPE" <<'PY'
import json, sys
from pathlib import Path

path, new_slug, old_slug, branch, ticket, input_type = (
    Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
)

d = json.loads(path.read_text(encoding="utf-8"))

# Rewrite paths referencing old slug
for k, v in list(d.items()):
    if isinstance(v, str) and old_slug in v:
        d[k] = v.replace(old_slug, new_slug)

# Set explicit fields
d["id"] = new_slug
d["branch"] = branch
d["ticket"] = ticket if ticket else None
d["input_type"] = input_type

path.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
PY
fi

# ---- step 8: print summary --------------------------------------------------

# Read old ticket/type from state for display
PY_SCRIPT=$(mktemp)
cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(d.get("ticket") or "null")
print(d.get("input_type", ""))
PYEOF

OLD_TICKET=$(python3 "$PY_SCRIPT" "$NEW_STATE" 2>/dev/null || echo "")
rm -f "$PY_SCRIPT"

OLD_TICKET_VAL=$(echo "$OLD_TICKET" | head -1)
OLD_TYPE_VAL=$(echo "$OLD_TICKET" | tail -1)

echo ""
echo "Resync complete."
echo ""

# Detect what actually changed
CHANGED=false

if [ "$OLD_SLUG" != "$NEW_SLUG" ]; then
  CHANGED=true
  echo "Branch:  $([ "$ATOMIC" = true ] && echo "${CURRENT_BRANCH}" || echo "${CURRENT_BRANCH}")"
  echo "Slug:    $OLD_SLUG  →  $NEW_SLUG"
fi

if [ "$OLD_TICKET_VAL" != "$TICKET" ]; then
  CHANGED=true
  echo "Ticket:  $OLD_TICKET_VAL  →  ${TICKET:-null}"
fi

if [ "$OLD_TYPE_VAL" != "$INPUT_TYPE" ]; then
  CHANGED=true
  echo "Type:    $OLD_TYPE_VAL  →  $INPUT_TYPE"
fi

if [ "$RENAMED_COUNT" -gt 0 ]; then
  echo "Files renamed: $RENAMED_COUNT"
  echo "$RENAMED_FILES"
fi

if [ "$CHANGED" = false ]; then
  echo "Already in sync."
  exit 0
fi

echo ""
echo "Next:"
echo "  - source_title in state.json still reflects the original input."
echo "    Edit it manually or rerun /f-start if you want it to match the new ticket."
echo "  - If the old branch was pushed to origin, push the new branch and delete the old:"
echo "      git push -u origin HEAD"
echo "      git push origin --delete <old-branch>"
