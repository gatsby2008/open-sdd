#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

source "$LIB_DIR/gates.sh"
source "$SCRIPT_DIR/../lib/non_interactive.sh"

# ---- helpers ----------------------------------------------------------------

SLUG=""
STATE_FILE=""
SPEC_FILE=""

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# Extract ticket ID from branch name: feature/JIRA-123-foo -> JIRA-123
extract_ticket() {
  local branch="$1"
  echo "$branch" | sed -n 's/.*\/\([A-Z][A-Z0-9]*-[0-9]*\).*/\1/p'
}

# ---- resolve slug -----------------------------------------------------------

SLUG=$(resolve_slug) || die "Could not resolve slug."
STATE_FILE=".specwork/_state/${SLUG}-state.json"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
hydrate_non_interactive_from_state "$SLUG"

# /f-commit is artifact-driven and re-runnable. No step gate. Standalone
# (git-only / vibe-coding) mode is allowed when no pipeline state exists.

# ---- check for changes (before running the quality gate) --------------------
# Detect / stage changes first so a no-op commit exits immediately instead of
# paying for the full test suite (e.g. ./gradlew check) only to find nothing.

HAS_STAGED=false
if ! git diff --cached --quiet 2>/dev/null; then
  HAS_STAGED=true
  fmt_bold "Staged changes detected."
elif ! git diff --quiet 2>/dev/null; then
  echo "Unstaged changes found."
  if [ -t 0 ]; then
    echo ""
    echo "Stage all tracked changes? [y/N]"
    read -r choice
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
      git add -u
      HAS_STAGED=true
      echo "Tracked files staged."
    else
      echo "Aborted."
      exit 1
    fi
  else
    git add -u
    HAS_STAGED=true
    echo "Tracked files staged."
  fi
else
  echo "No changes to commit."
  exit 1
fi

# ---- quality gate: run tests ------------------------------------------------
# Only reached when there is something to commit.

echo "Running pre-commit checks..."
CHECK_SCRIPT="$SCRIPT_DIR/check.sh"
if [ -f "./commands/check.sh" ]; then
  CHECK_SCRIPT="./commands/check.sh"
  echo "Using project-local commands/check.sh"
fi
bash "$CHECK_SCRIPT" || die "Checks failed. Fix issues before committing."

# ---- print context ----------------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD)
TICKET=$(extract_ticket "$BRANCH")
CHANGED_FILES=$(git diff --cached --name-only | paste -sd ", " -)
SPEC_TITLE=$(head -1 "$SPEC_FILE" 2>/dev/null | sed 's/^# //' || echo "$SLUG")
DIFF_STAT=$(git diff --cached --stat 2>/dev/null || echo "")

echo ""
echo "========================================================"
echo "Commit context"
echo "========================================================"
echo "  Branch:   $BRANCH"
echo "  Ticket:   ${TICKET:-none}"
echo "  Spec:     $SPEC_TITLE"
echo "  Files:    $CHANGED_FILES"
echo ""
echo "Diff stats:"
echo "$DIFF_STAT" | sed 's/^/  /'
echo "========================================================"
echo ""
echo "Commit format: [TICKET-ID] <type>: <description>"
echo "  Types: feat | fix | refactor | docs | test | perf"
echo ""

# ---- commit: interactive or auto --------------------------------------------

COMMIT_MSG_FILE=".specwork/_state/${SLUG}-commit-msg.txt"

if [ -n "$TICKET" ]; then
  PROPOSED="[$TICKET] feat: $SPEC_TITLE"
else
  PROPOSED="feat: $SPEC_TITLE"
fi

commit_and_update() {
  echo "$PROPOSED" > "$COMMIT_MSG_FILE"
  git commit -F "$COMMIT_MSG_FILE"
  echo "Committed."
  rm -f "$COMMIT_MSG_FILE"

  LAST_COMMIT=$(git rev-parse HEAD)
  if [ -f "$STATE_FILE" ]; then
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
data["checked_sha"] = sha
fp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
    echo "State updated with commit $LAST_COMMIT"
  fi
}

if [ "$HAS_STAGED" = true ]; then
  if [ "${SDD_NON_INTERACTIVE:-0}" = "1" ]; then
    echo "Non-interactive: accepting proposed commit message automatically."
    echo "  $PROPOSED"
    commit_and_update
  elif [ -t 0 ]; then
    echo "Proposed message:"
    echo "  $PROPOSED"
    echo ""
    echo "  1) Accept and commit     [Enter]"
    echo "  2) Edit message           [e]"
    echo "  3) Abort                  [q]"
    read -r choice

    case "$choice" in
      e|E)
        echo "Type the new commit message (first line is subject):"
        read -r new_msg
        echo "$new_msg" > "$COMMIT_MSG_FILE"
        git commit -F "$COMMIT_MSG_FILE"
        echo "Committed."
        rm -f "$COMMIT_MSG_FILE"
        ;;
      q|Q)
        echo "Aborted."
        exit 1
        ;;
      *)
        commit_and_update
        ;;
    esac
  fi
fi
