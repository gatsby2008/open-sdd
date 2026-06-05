#!/usr/bin/env bash
set -euo pipefail

die() { echo "$*" >&2; exit 1; }

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# ---- check pipeline exists ---------------------------------------------------

if [ ! -d ".specwork" ] || [ -z "$(find .specwork/_state -name '*-state.json' -maxdepth 1 2>/dev/null | head -1)" ]; then
  echo "No active pipeline found in .specwork/."
  echo "Nothing to close."
  exit 0
fi

# ---- resolve parent branch from state ---------------------------------------

PARENT=""
STATE_FILE=$(find .specwork/_state -name '*-state.json' -maxdepth 1 2>/dev/null | head -1)
if [ -n "$STATE_FILE" ]; then
  PARENT=$(python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get('base_branch', ''))
" "$STATE_FILE" 2>/dev/null || true)
fi
if [ -z "$PARENT" ]; then
  PARENT=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")
fi

echo "Closing feature pipeline on branch '$BRANCH' ..."
echo ""

# ---- revert all local changes -----------------------------------------------

if [ -n "$(git status --porcelain)" ]; then
  echo "Reverting all local changes..."
  # Preserve .gitignore modifications (start.sh may have added entries for
  # .specwork/, .opensdd/, AGENTS.md, etc. to protect them from git clean).
  GITIGNORE_SAVED=$(cat .gitignore 2>/dev/null || true)
  # Revert all tracked files to committed state
  git restore .
  # Re-apply .gitignore so pipeline entries are not lost
  [ -n "$GITIGNORE_SAVED" ] && printf '%s\n' "$GITIGNORE_SAVED" > .gitignore
  # Remove untracked implementation files, preserving non-pipeline configs
  git clean -fd --exclude=.opencode --exclude=AGENTS.md --exclude=CLAUDE.md --exclude=GEMINI.md
  echo "Done."
  echo ""
fi

# ---- delete pipeline artifacts (.specwork + .opensdd) -----------------------

if [ -d ".specwork" ]; then
  echo "Deleting .specwork/ ..."
  rm -rf .specwork/
  if [ -d ".specwork" ]; then
    die "Could not fully remove .specwork/ — remove it manually before retrying."
  fi
  echo "Done."
  echo ""
fi
if [ -d ".opensdd" ]; then
  echo "Deleting .opensdd/ ..."
  rm -rf .opensdd/
  echo "Done."
  echo ""
fi

# ---- branch cleanup ---------------------------------------------------------

# Switch to the parent branch, checking it out from origin if it only exists
# remotely. Returns non-zero (without exiting) when the parent cannot be found,
# so the dialog can fall back to keeping the current branch instead of dying.
checkout_parent() {
  if git rev-parse --verify --quiet "refs/heads/$PARENT" >/dev/null; then
    git checkout "$PARENT"
  elif git rev-parse --verify --quiet "refs/remotes/origin/$PARENT" >/dev/null; then
    git checkout -b "$PARENT" "origin/$PARENT"
  else
    echo "Parent branch '$PARENT' not found locally or on origin." >&2
    return 1
  fi
}

# /f-close is always human-driven — it is never reached by /f-auto's
# non-interactive flow, so branch deletion stays an explicit interactive choice.
if [ "$BRANCH" != "$PARENT" ]; then
  echo "Branch '$BRANCH' is not the parent ($PARENT)."
  echo ""
  echo "  d) Delete local branch and switch to $PARENT"
  echo "  k) Keep branch, switch to $PARENT"
  echo "  s) Stay on branch"
  echo "  q) Quit"
  read -r choice
  case "$choice" in
    d|D)
      if checkout_parent; then
        git branch -D "$BRANCH"
        echo "Branch '$BRANCH' deleted. Switched to $PARENT."
      else
        echo "Staying on '$BRANCH' — branch not deleted."
      fi
      ;;
    k|K)
      if checkout_parent; then
        echo "Switched to $PARENT. Branch preserved."
      else
        echo "Staying on '$BRANCH'. Branch preserved."
      fi
      ;;
    s|S)
      echo "Staying on branch '$BRANCH'."
      ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

echo ""
echo "Feature pipeline closed."
