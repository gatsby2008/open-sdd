#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- state ------------------------------------------------------------------

SLUG=""
STATE_FILE=""
SPEC_FILE=""

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- resolve slug -----------------------------------------------------------

SLUG=$(resolve_slug) || die "Could not resolve slug."
STATE_FILE=".specwork/_state/${SLUG}-state.json"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"

# ---- check for changes ------------------------------------------------------

if ! git diff --cached --quiet 2>/dev/null; then
  # There are already staged changes — skip staging step
  fmt_bold "Staged changes detected. Proceeding with commit."
elif ! git diff --quiet 2>/dev/null; then
  echo "Unstaged work-in-progress changes found."
  echo ""
  echo "Stage all tracked changes and commit? [y/N]"
  read -r choice
  if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
    git add -u
    echo "Tracked files staged."
  else
    echo "Aborted."
    exit 1
  fi
else
  echo "No changes to commit."
  exit 1
fi

# ---- load context for commit message ----------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD)
CHANGED_FILES=$(git diff --cached --stat --name-only | paste -sd ", " -)

# Read spec for description
SPEC_TITLE=$(head -1 "$SPEC_FILE" 2>/dev/null | sed 's/^# //' || echo "$SLUG")
python3 - "$SPEC_FILE" "$SLUG" <<'PY' 2>/dev/null || true
import re, sys
from pathlib import Path
spec_file = sys.argv[1]
slug = sys.argv[2]
text = Path(spec_file).read_text(encoding="utf-8")
# Try title
title_match = re.search(r'(?m)^#\s+(.+)$', text)
title = title_match.group(1).strip() if title_match else slug
# Try first paragraph of Description section
desc_match = re.search(r'(?ms)^## Description\s*\n+(.*?)(?=\n## |\Z)', text)
desc = ""
if desc_match:
    para = desc_match.group(1).strip().split("\n\n")[0].strip()
    desc = para[:200]
if desc:
    print(f"{title}: {desc}")
else:
    print(title)
PY

# ---- build commit message ---------------------------------------------------

echo ""
fmt_bold "Generating commit message..."
echo ""
echo "Context:"
echo "  Branch:   $BRANCH"
echo "  Spec:     $SPEC_TITLE"
echo "  Files:    $CHANGED_FILES"
echo ""

COMMIT_MSG_FILE=".specwork/_state/${SLUG}-commit-msg.txt"

# Read state.json for optional ticket reference
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
  echo "  Ticket:   $TICKET"
fi

echo ""
echo "========================================================"
echo "Proposed commit message:"
echo "========================================================"

# Build message from spec title + ticket
MSG_LINE=$(python3 - "$SPEC_FILE" "$SLUG" <<'PY' 2>/dev/null
import re, sys
from pathlib import Path
spec_file = sys.argv[1]
slug = sys.argv[2]
text = Path(spec_file).read_text(encoding="utf-8")
title_match = re.search(r'(?m)^#\s+(.+)$', text)
title = title_match.group(1).strip() if title_match else slug
print(title[:72])
PY
)

cat > "$COMMIT_MSG_FILE" <<EOF
${TICKET:+[$TICKET] }$MSG_LINE

EOF

cat "$COMMIT_MSG_FILE"

echo ""
echo "========================================================"
echo ""
echo "You can:"
echo "  1) Accept this message and commit     [Enter]"
echo "  2) Edit the message manually           [e]"
echo "  3) Abort                               [q]"
echo ""
read -r choice

case "$choice" in
  e|E)
    # Open in editor or inline edit
    echo "Type the new commit message (first line is subject):"
    read -r new_msg
    echo "$new_msg" > "$COMMIT_MSG_FILE"
    git commit -F "$COMMIT_MSG_FILE"
    echo "Committed."
    ;;
  q|Q)
    echo "Aborted."
    rm -f "$COMMIT_MSG_FILE"
    exit 1
    ;;
  *)
    git commit -F "$COMMIT_MSG_FILE"
    echo "Committed."
    rm -f "$COMMIT_MSG_FILE"
    ;;
esac

# ---- update state.json with last commit sha ---------------------------------

LAST_COMMIT=$(git rev-parse HEAD)
python3 - "$STATE_FILE" "$LAST_COMMIT" <<'PY'
import json, sys
from pathlib import Path
fp = Path(sys.argv[1])
sha = sys.argv[2]
data = json.loads(fp.read_text(encoding="utf-8"))
commits = data.get("commits", [])
if sha not in commits:
    commits.append(sha)
data["commits"] = commits
data["last_commit"] = sha
fp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "State updated with commit $LAST_COMMIT"
echo ""
echo "Next: ./commands/mr.sh"
