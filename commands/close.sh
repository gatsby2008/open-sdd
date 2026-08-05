#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# ---- resolve pipeline & verify it's safe to close here (STRICT) -------------
# .specwork/ is gitignored and survives `git checkout`, so it commonly still
# holds a *different* branch's pipeline (e.g. an in-review feature branch)
# while you're on and closing something else entirely. The old check here —
# "does .specwork/_state have *any* state.json" via `find | head -1` — did not
# ask whose pipeline it was, so it would silently: (a) run `git restore .` +
# `git clean -fd` against THIS branch's own uncommitted work below, thinking
# it was reverting the other pipeline's changes, (b) delete that unrelated
# pipeline without ever checking its MR status, and (c) offer to delete/switch
# THIS branch based on that pipeline's base_branch. Ask explicitly instead.

STATUS_VARS=$(PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli pipeline-branch-status "$BRANCH" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("has_any_pipeline", "owns_pipeline", "is_base_branch", "slug", "recorded_branch", "recorded_base_branch"):
    v = d[k]
    if isinstance(v, bool):
        v = "1" if v else ""
    print(f"{k}={v}")
')

HAS_ANY_PIPELINE=$(echo "$STATUS_VARS" | grep "^has_any_pipeline=" | cut -d= -f2-)
OWNS_PIPELINE=$(echo "$STATUS_VARS" | grep "^owns_pipeline=" | cut -d= -f2-)
IS_BASE_BRANCH=$(echo "$STATUS_VARS" | grep "^is_base_branch=" | cut -d= -f2-)
RECORDED_SLUG=$(echo "$STATUS_VARS" | grep "^slug=" | cut -d= -f2-)
RECORDED_BRANCH=$(echo "$STATUS_VARS" | grep "^recorded_branch=" | cut -d= -f2-)
PARENT=$(echo "$STATUS_VARS" | grep "^recorded_base_branch=" | cut -d= -f2-)

if [ -z "$HAS_ANY_PIPELINE" ]; then
  echo "No active pipeline found in .specwork/."
  echo "Nothing to close."
  exit 0
fi

if [ -z "$OWNS_PIPELINE" ] && [ -z "$IS_BASE_BRANCH" ]; then
  die "✗ Cannot close here.

.specwork/ belongs to '$RECORDED_BRANCH' (slug '$RECORDED_SLUG'), not '$BRANCH'
or its base. It's gitignored and didn't move when you switched branches — it
is still on disk, but it is not this branch's pipeline to close.

  • To close it: switch to '$RECORDED_BRANCH' and run /f-close there.
  • To pause it instead: switch to '$RECORDED_BRANCH' and run /f-pause.
  • This branch itself has no pipeline of its own — /f-start to begin one."
fi

if [ -z "$PARENT" ]; then
  PARENT=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")
fi

echo "Closing feature pipeline on branch '$BRANCH' ..."
echo ""

# ---- revert all local changes -----------------------------------------------

if ! PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli worktree-clean 2>/dev/null; then
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
