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

# ---- promote durable rules (interactive only) -------------------------------
# The spec is about to be deleted. Before it goes, offer to promote what the
# feature taught about the service into the team's rules (rules/ — neutral home,
# with .claude/rules/ as legacy fallback), so the next pipeline starts with it.
# Two passes: the first prints the candidates' source and stops (nothing
# deleted); the agent asks the user and re-runs with --promote '<json>'
# (approved rules) or --no-promote.

SPEC_FILE=".specwork/_spec/${RECORDED_SLUG}-spec.md"
PROMOTE_JSON=""
PROMOTE_DECIDED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --promote)    PROMOTE_JSON="${2:-}"; PROMOTE_DECIDED=1; shift 2 || shift ;;
    --no-promote) PROMOTE_DECIDED=1; shift ;;
    *) shift ;;
  esac
done

if [ -z "$PROMOTE_DECIDED" ] && [ "${SDD_NON_INTERACTIVE:-0}" != "1" ] && [ -f "$SPEC_FILE" ]; then
  echo "==================================================="
  echo " PROMOTE DURABLE RULES (before closing)"
  echo "==================================================="
  echo ""
  python3 - "$SPEC_FILE" <<'PY'
import re, sys
from pathlib import Path
spec = Path(sys.argv[1]).read_text(encoding="utf-8")
def section(name):
    m = re.search(rf'(?ms)^## {re.escape(name)}\b(.*?)(?=^## |\Z)', spec)
    return m.group(1).strip() if m else ""
print("## Safe Constraints (from the spec)")
print(section("Safe Constraints") or "(empty)")
print("")
print("## Resolved Open Questions")
resolved = [l for l in section("Open Questions").splitlines() if l.lstrip().startswith("- [x]")]
print("\n".join(resolved) if resolved else "(none)")
PY
  echo ""
  echo "## Existing rules files"
  RULES_HOME=""
  if ls rules/*.md >/dev/null 2>&1; then
    RULES_HOME="rules"
  elif ls .claude/rules/*.md >/dev/null 2>&1; then
    RULES_HOME=".claude/rules"
  fi
  if [ -n "$RULES_HOME" ]; then
    for f in ${RULES_HOME}/*.md; do
      echo "  $f: $(grep -E '^#{1,6} ' "$f" | sed -E 's/^#+ //' | paste -sd '|' - | sed 's/|/ | /g')"
    done
  else
    echo "  (none — approved rules go to rules/service-rules.md)"
  fi
  cat <<INSTRUCTIONS

Nothing has been deleted yet. Read only the two spec sections above — not the
diff, not the code — and:

1. Pick at most 4 feature-agnostic, durable invariants: business rules,
   ownership/identity rules, idempotency or fallback contracts, the *why*
   behind a design choice. Drop ticket-only decisions, dates, rollout notes,
   and anything the rules files already state. Zero is a normal outcome.
2. Choose a target per candidate: the rules/<topic>.md (or legacy
   .claude/rules/<topic>.md) whose subject matches, and a section heading in
   it. With no rules files, target rules/service-rules.md and one of: Business
   Invariants, Fallback and Idempotency, Architecture Constraints, Historical
   Constraints.
3. A candidate that contradicts an existing rule is NOT a write — ask the user
   which one holds. Existing rules are never edited, reworded, or removed.
4. Ask the user once to approve each candidate (none pre-approved).
5. Re-run /f-close with the approved ones (or --no-promote when none):

     /f-close --promote '[{"file": "rules/<topic>.md", "section": "<section>", "rule": "<rule>"}]'

   The rules are appended with a provenance marker
   (\`- <rule> _(from spec ${RECORDED_SLUG}, <date>)_\`); the write is refused if
   any existing line would change. They stay as uncommitted changes to commit
   on the parent branch.
INSTRUCTIONS
  exit 0
fi

if [ -n "$PROMOTE_JSON" ]; then
  PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli promote-apply "$RECORDED_SLUG" "$PROMOTE_JSON" --dry-run \
    || die "Rule promotion rejected (see above) — nothing was closed or deleted."
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

# ---- write the approved rules (after the revert, so it can't undo them) -----

if [ -n "$PROMOTE_JSON" ]; then
  PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli promote-apply "$RECORDED_SLUG" "$PROMOTE_JSON" \
    || die "Rule promotion failed — .specwork/ kept; nothing deleted."
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
