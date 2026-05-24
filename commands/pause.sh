#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

# ---- resolve context --------------------------------------------------------

SLUG=$(resolve_slug 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# ---- step 1: verify pipeline state ------------------------------------------

STATE_FILE=""
[ -n "$SLUG" ] && STATE_FILE=".specwork/_state/${SLUG}-state.json"

if [ -z "$SLUG" ] || [ ! -f "$STATE_FILE" ]; then
  die "No active pipeline state found for this branch.
Run ./commands/start.sh first or switch to the branch that owns .specwork/."
fi

echo "Branch: $BRANCH"
echo "Slug:   $SLUG"

# ---- step 2: check for actual changes ---------------------------------------

HAS_CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ "$HAS_CHANGES" -eq 0 ] && [ ! -d ".specwork" ]; then
  die "Nothing to pause — working tree is clean and no .specwork/ artifacts found."
fi

# ---- step 3: save Jira credentials state if exist ---------------------------

# Git will not capture Jira tokens even with --all (they're in the stash
# message itself). For Jira state, just warn the user if needed.

# ---- step 4: stash all work including .specwork/ ----------------------------

echo ""
echo "Staging all changes + pipeline state..."

# Stage everything tracked + untracked (but not gitignored)
git add -A 2>/dev/null || true

# Force-add gitignored .specwork/ so it gets captured by stash
if [ -d ".specwork" ]; then
  git add -f .specwork/ 2>/dev/null || true
fi

echo "Stashing with label: f-pause: $BRANCH"
git stash push --message "f-pause: $BRANCH"

# ---- step 5: confirm --------------------------------------------------------

echo ""
echo "Paused $BRANCH → stash saved."
echo ""
echo "You can now switch to any branch you need."
echo "Resume later with: ./commands/resume.sh"
