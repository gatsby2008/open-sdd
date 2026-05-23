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
CACHE_FILE=""

TARGETS=()              # array of "path|change|tags"
CURRENT_INDEX=0

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }

fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
fmt_dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

# ---- load context -----------------------------------------------------------

SLUG=$(resolve_slug) || die "Could not resolve slug from current branch."
echo "Slug: $SLUG"

STATE_FILE=".specwork/_state/${SLUG}-state.json"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
PLAN_JSON_FILE=".specwork/_plan/${SLUG}-plan.json"
CACHE_FILE=".specwork/_state/${SLUG}-implementation-cache.json"

# ---- pre-flight gates -------------------------------------------------------

check_required_artifacts "$SLUG" || die "Missing artifacts. Run ./commands/start.sh then ./commands/plan.sh."

if ! check_open_questions "$SLUG"; then
  echo ""
  echo "Cannot implement — unresolved Open Questions in spec."
  echo "Resolve them first, then re-run."
  exit 1
fi

if [ ! -f "$PLAN_JSON_FILE" ]; then
  echo "No plan found at $PLAN_JSON_FILE"
  echo "Run ./commands/plan.sh first."
  exit 1
fi

# Plan staleness gate: spec modified after plan was written?
PLAN_JSON_MTIME=$(stat -f %m "$PLAN_JSON_FILE" 2>/dev/null || stat -c %Y "$PLAN_JSON_FILE" 2>/dev/null || echo "0")
SPEC_STATE=$(python3 - "$STATE_FILE" <<'PY' 2>/dev/null || echo "0"
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(state.get("spec_write_timestamp", 0))
PY
)

if [ "$PLAN_JSON_MTIME" != "0" ] && [ "$SPEC_STATE" != "0" ] && [ "$PLAN_JSON_MTIME" -lt "$SPEC_STATE" ]; then
  echo ""
  echo "Plan is stale — spec was modified after plan was created."
  echo "  Spec last written: $(date -r "$SPEC_STATE" 2>/dev/null || echo "epoch $SPEC_STATE")"
  echo "  Plan last written: $(date -r "$PLAN_JSON_MTIME" 2>/dev/null || echo "epoch $PLAN_JSON_MTIME")"
  echo "Run ./commands/plan.sh to regenerate."
  echo ""
  echo "  y) Re-run plan.sh now"
  echo "  n) Proceed with stale plan (not recommended)"
  echo "  q) Quit"
  read -r choice
  case "$choice" in
    y|Y) exec "$SCRIPT_DIR/plan.sh" ;;
    n|N) echo "Proceeding with stale plan." ;;
    *) exit 1 ;;
  esac
fi

# ---- load plan --------------------------------------------------------------

echo ""
fmt_bold "Loading implementation plan..."
echo ""

PLAN_DATA=$(python3 - "$PLAN_JSON_FILE" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for target in data.get("target_files", []):
    path = target.get("path", "")
    change = target.get("change", "")
    tags = target.get("tags", "")
    if path:
        print(f"{path}|{change}|{tags}")
PY
)

TARGETS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  TARGETS+=("$line")
done <<< "$PLAN_DATA"

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No target files in plan. Nothing to implement."
  exit 0
fi

echo "Plan has ${#TARGETS[@]} target files."
echo ""

# ---- determine resume point -------------------------------------------------

CURRENT_INDEX=$(python3 - "$PLAN_JSON_FILE" -c '
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for i, t in enumerate(data.get("target_files", [])):
    if t.get("status") not in ("done", "skip"):
        print(i)
        sys.exit(0)
print(len(data.get("target_files", [])))
')

# ---- instructions for the LLM -----------------------------------------------

# Handle --done flag early to skip display
if [ "${1:-}" = "--done" ]; then
  TARGET_NUM="${2:-}"
  if [ -z "$TARGET_NUM" ]; then
    die "Usage: ./commands/implement.sh --done N  (where N is 1-based target number)"
  fi
  IDX=$((TARGET_NUM - 1))
  if [ "$IDX" -lt 0 ] || [ "$IDX" -ge "${#TARGETS[@]}" ]; then
    die "Invalid target number $TARGET_NUM (valid: 1-${#TARGETS[@]})"
  fi

  python3 - "$PLAN_JSON_FILE" "$IDX" <<'PY'
import json, sys
from pathlib import Path
filepath = Path(sys.argv[1])
idx = int(sys.argv[2])
data = json.loads(filepath.read_text(encoding="utf-8"))

# Mark target as done
targets = data.get("target_files", [])
if 0 <= idx < len(targets):
    targets[idx]["status"] = "done"
    data["target_files"] = targets

    # Update implementation-cache.json with the file that was just completed
    cache_path = Path(".specwork/_state") / f'{data["slug"]}-implementation-cache.json'
    if cache_path.exists():
        import subprocess as sp
        pass  # cache is updated separately

filepath.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"Target #{idx + 1} marked done.")
PY

  # Also update implementation-cache.json
  python3 - "$CACHE_FILE" "${TARGETS[$IDX]}" <<'PY'
import json, sys
from pathlib import Path
cache_path = Path(sys.argv[1])
target_raw = sys.argv[2]
parts = target_raw.split("|", 2)
if len(parts) < 2:
    sys.exit(0)
path = parts[0]
tags = parts[2] if len(parts) > 2 else ""

if not cache_path.exists():
    sys.exit(0)

try:
    cache = json.loads(cache_path.read_text(encoding="utf-8"))
except Exception:
    cache = {}

notes_key = "notes"
existing = cache.get(notes_key, [])
note = f"implemented: {path}"
if note not in existing:
    existing.append(note)
cache[notes_key] = existing

cache_path.write_text(json.dumps(cache, indent=2) + "\n", encoding="utf-8")
PY

  REMAINING=$(( ${#TARGETS[@]} - TARGET_NUM ))
  if [ "$REMAINING" -le 0 ]; then
    echo ""
    echo "All targets implemented!"
    echo "Next: ./commands/commit.sh"
  else
    echo "$REMAINING target(s) remaining."
    echo "Continue with: ./commands/implement.sh"
  fi
  exit 0
fi

# ---- display spec and plan (non-done path) ----------------------------------

cat <<INSTRUCTIONS

===================================================
 IMPLEMENTATION SESSION
===================================================

You have loaded the Spec-Driven Development pipeline's implement step.
Below is the context you need to make changes.

SPEC:    $SPEC_FILE
PLAN:    $PLAN_JSON_FILE
STATE:   $STATE_FILE
CACHE:   $CACHE_FILE
STACK:   $(detect_stack)
SLUG:    $SLUG

Resuming at target #$((CURRENT_INDEX + 1)) of ${#TARGETS[@]}.

===================================================

INSTRUCTIONS

echo "====== SPEC ======"
cat "$SPEC_FILE"
echo ""
echo "=================="
echo ""

PLAN_MD_FILE=".specwork/_plan/${SLUG}-plan.md"
if [ -f "$PLAN_MD_FILE" ]; then
  echo "====== PLAN (approach) ======"
  python3 - "$PLAN_MD_FILE" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'(?ms)^## Approach\b(.*?)(?=^## |\Z)', text)
if m:
    print(m.group(1).strip())
PY
  echo ""
  echo "=============================="
fi

echo ""
fmt_bold "Target files to modify:"

for i in "${!TARGETS[@]}"; do
  IFS='|' read -r path change _ <<< "${TARGETS[$i]}"
  if [ "$i" -lt "$CURRENT_INDEX" ]; then
    echo "  [$((i+1))] $path  — $change  [DONE]"
  else
    echo "  [$((i+1))] $path  — $change"
  fi
done

echo ""
fmt_bold "Instructions"
echo ""
echo "1. Read each target file above."
echo "2. For each file, implement the change described."
echo "3. After implementing each file, run:"
echo "     ./commands/implement.sh --done N"
echo "4. When all files are done, commit with:"
echo "     ./commands/commit.sh"
echo ""

# ---- show source context for first remaining target -------------------------

if [ "$CURRENT_INDEX" -lt "${#TARGETS[@]}" ]; then
  IFS='|' read -r first_path first_change _ <<< "${TARGETS[$CURRENT_INDEX]}"
  echo ""
  fmt_bold "=== First target: $first_path ==="
  echo "Change: $first_change"
  echo ""

  # Print key lines if file exists  
  if [ -f "$first_path" ]; then
    FIRST_LINE=$(grep -n "^[a-zA-Z]" "$first_path" 2>/dev/null | head -20 || true)
    echo "Key structural lines:"
    echo "$FIRST_LINE"
  else
    echo "(File does not exist yet — will be created.)"
  fi
fi

echo ""
fmt_bold "Ready. Follow the instructions above to implement each target."
echo "After each file, run: ./commands/implement.sh --done N"
