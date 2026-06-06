#!/usr/bin/env bash
# /f-undo — discard uncommitted code changes, reversibly, without touching .specwork/.
#
# Works in a pipeline (preserves .specwork/ so you can re-spec) and standalone
# for vibe coding (just cleans the working tree). `.specwork/` is gitignored, so
# it never enters a stash and `git clean -fd` skips it — this script never passes
# -x, so ignored paths always survive.
#
#   undo.sh              reversible: git stash push --include-untracked
#   undo.sh --restore    pop the newest f-undo stash (redo)
#   undo.sh --hard       irreversible: git restore . + git clean -fd (needs --force)
#   undo.sh --preview    list what would be discarded
#   undo.sh --list       list recoverable f-undo stashes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

die() { echo "$*" >&2; exit 1; }

UNDO_PREFIX="f-undo: "

MODE="undo"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --restore) MODE="restore" ;;
    --hard)    MODE="hard" ;;
    --preview) MODE="preview" ;;
    --list)    MODE="list" ;;
    --force)   FORCE=1 ;;
    *) die "Unknown argument: $arg (use --restore | --hard | --preview | --list)" ;;
  esac
done

# Count / list of paths git would touch. Porcelain excludes gitignored files,
# so .specwork/ never appears here.
affected_count() { git status --porcelain 2>/dev/null | wc -l | tr -d ' '; }
print_affected() { git status --porcelain 2>/dev/null | sed 's/^.../  /'; }

# Newest f-undo stash ref. git stores the subject as "On <branch>: f-undo: <slug>",
# so match the marker anywhere in the line, not just at the start.
newest_undo_stash() {
  git stash list --format='%gd %s' 2>/dev/null | grep -m1 "$UNDO_PREFIX" | awk '{print $1}'
}

SLUG=$(resolve_slug 2>/dev/null || echo "")
[ -n "$SLUG" ] || SLUG="wip"

next_steps() {
  if [ -d ".specwork" ]; then
    cat <<EOF

Pipeline preserved. Next:
  /f-spec <correction>   # refine the spec (resolve/append Open Questions)
  /f-plan                # re-run: the spec is now newer than the plan (stale gate)
  /f-implement

Undid by mistake? /f-undo --restore
EOF
  else
    cat <<EOF

Working tree clean. Keep coding, then /f-commit when ready.
Undid by mistake? /f-undo --restore
EOF
  fi
}

case "$MODE" in
  preview)
    n=$(affected_count)
    [ "$n" -eq 0 ] && { echo "(clean — nothing to undo)"; exit 1; }
    echo "Would discard $n change(s):"
    print_affected
    ;;

  list)
    git stash list --format='%gd %s' 2>/dev/null | grep "$UNDO_PREFIX" || echo "(no f-undo stashes)"
    ;;

  restore)
    ref=$(newest_undo_stash)
    [ -n "$ref" ] || die "No f-undo stash to restore."
    git stash pop "$ref"
    echo "Restored $ref."
    ;;

  undo)
    n=$(affected_count)
    [ "$n" -eq 0 ] && die "Nothing to undo — the working tree is already clean."
    git stash push --include-untracked --message "${UNDO_PREFIX}${SLUG}"
    echo "Stashed $n change(s) as '${UNDO_PREFIX}${SLUG}'."
    next_steps
    ;;

  hard)
    n=$(affected_count)
    [ "$n" -eq 0 ] && die "Nothing to undo — the working tree is already clean."
    if [ "$FORCE" -ne 1 ]; then
      echo "This will PERMANENTLY discard $n change(s):"
      print_affected
      echo ""
      echo "Irreversible — .specwork/ is preserved, code is not. To confirm:"
      echo "  /f-undo --hard --force"
      exit 2
    fi
    git restore .
    git clean -fd
    echo "Reverted working tree ($n change(s) discarded; .specwork/ preserved)."
    next_steps
    ;;
esac
