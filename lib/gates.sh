#!/usr/bin/env bash

# gates.sh — shared validation gates for SDD pipeline.
# All functions exit non-zero on failure.
# Fixed: mtime comparison uses state.json stored timestamp, not filesystem mtime.

resolve_slug() {
  local branch state_file matched_slug
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$branch" ] || return 1

  # Prefer the slug stored in state.json that matches our branch.
  # Write a small python script to a temp file to avoid heredoc nesting issues.
  state_file=$(find .specwork/_state -maxdepth 1 -type f -name "*-state.json" 2>/dev/null | head -1)
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    matched_slug=$(python3 -c "
import json,sys
s=json.load(open(sys.argv[1]))
if s.get('branch')==sys.argv[2]:
  print(s.get('id',''))
" "$state_file" "$branch" 2>/dev/null || true)
    if [ -n "$matched_slug" ]; then
      printf '%s' "$matched_slug"
      return 0
    fi
  fi

  # Fallback: derive slug from branch name
  branch="${branch#*/}"
  printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

resolve_state_file() {
  local slug="$1"
  if [ -z "$slug" ]; then
    slug=$(resolve_slug)
  fi
  if [ -n "$slug" ] && [ -f ".specwork/_state/${slug}-state.json" ]; then
    printf '%s\n' ".specwork/_state/${slug}-state.json"
    return 0
  fi
  local state
  state=$(find .specwork/_state -type f -name "*-state.json" 2>/dev/null | sort | head -1)
  [ -n "$state" ] || return 1
  printf '%s\n' "$state"
}

# ---------------------------------------------------------------------------
# Open Questions gate
# Scans ## Open Questions section in spec.md and optionally plan.md.
# Exits 1 if any unresolved `- [ ]` items exist.
# ---------------------------------------------------------------------------
check_open_questions() {
  local slug="$1"
  local spec_file=".specwork/_spec/${slug}-spec.md"
  local plan_file=".specwork/_plan/${slug}-plan.md"

  python3 - <<'PY' "$spec_file" "$plan_file"
import re, sys
from pathlib import Path

blockers = []
for path_str in sys.argv[1:]:
    p = Path(path_str)
    if not p.exists():
        continue
    text = p.read_text(encoding="utf-8")
    m = re.search(r'(?ms)^## Open Questions\b(.*?)(?=^## |\Z)', text)
    section = m.group(1) if m else ""
    unresolved = [l.strip() for l in section.splitlines() if re.match(r'^\s*-\s*\[\s\]', l)]
    if unresolved:
        blockers.append((path_str, unresolved))

for path, items in blockers:
    print(f"--- {path}")
    for l in items:
        print(l)

sys.exit(1 if blockers else 0)
PY
}

# ---------------------------------------------------------------------------
# Plan staleness gate
# Fixed: compares plan.md mtime against stored spec_write_timestamp in
# state.json, NOT against spec.md filesystem mtime.
# Previously: stat( spec.md ) > stat( plan.md ) → fragile after stash/restore.
# ---------------------------------------------------------------------------
check_plan_staleness() {
  local slug="$1"
  local plan_file=".specwork/_plan/${slug}-plan.md"
  local state_file=".specwork/_state/${slug}-state.json"

  [ -f "$plan_file" ] || return 0
  [ -f "$state_file" ] || return 0

  python3 - <<'PY' "$plan_file" "$state_file"
import json, sys
from pathlib import Path

plan_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])

plan_mtime = plan_path.stat().st_mtime

try:
    state = json.loads(state_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

spec_ts = state.get("spec_write_timestamp")
if spec_ts is None:
    # No recorded timestamp — fall back to spec.md filesystem mtime for
    # backward compatibility, but warn.
    spec_path = state.get("spec_file", "")
    if spec_path and Path(spec_path).exists():
        spec_ts = Path(spec_path).stat().st_mtime
    else:
        sys.exit(0)

if plan_mtime < spec_ts:
    print(f"PLAN_STALE spec_ts={spec_ts} plan_mtime={plan_mtime}")
    sys.exit(1)

sys.exit(0)
PY
}

# ---------------------------------------------------------------------------
# Required artifacts check
# ---------------------------------------------------------------------------
check_required_artifacts() {
  local slug="$1"
  local missing=0
  for f in \
    ".specwork/_state/${slug}-state.json" \
    ".specwork/_state/${slug}-rules.json" \
    ".specwork/_spec/${slug}-spec.md"; do
    if [ ! -f "$f" ]; then
      echo "Missing: $f"
      missing=1
    fi
  done
  return $missing
}

# ---------------------------------------------------------------------------
# Branch match check
# Verifies current branch matches state.json's recorded branch.
# ---------------------------------------------------------------------------
check_branch_match() {
  local slug="$1"
  local state_file=".specwork/_state/${slug}-state.json"
  [ -f "$state_file" ] || return 1

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  python3 - <<'PY' "$state_file" "$current_branch"
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
recorded = state.get("branch", "")
current = sys.argv[2]
if recorded and recorded != current:
    print(f"BRANCH_MISMATCH recorded={recorded} current={current}")
    sys.exit(1)
sys.exit(0)
PY
}

# ---------------------------------------------------------------------------
# Stack detection
# Returns: "java" if build.gradle/pom.xml exists, "node" if package.json
# exists, "unknown" otherwise.
# ---------------------------------------------------------------------------
detect_stack() {
  if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] || [ -f "pom.xml" ]; then
    echo "java"
  elif [ -f "package.json" ]; then
    echo "node"
  else
    echo "unknown"
  fi
}

# ---------------------------------------------------------------------------
# Risk signal detection (spec body)
# Pure regex — language-agnostic.
# ---------------------------------------------------------------------------
detect_risk_signals() {
  local spec_file="$1"
  [ -f "$spec_file" ] || return 0
  python3 - <<'PY' "$spec_file"
import json, re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8").lower()
signals = {
    "db-migration":     r'\b(migration|flyway|liquibase|alter\s+table|drop\s+(table|column)|create\s+table|schema\s+change|add\s+column|rename\s+column)\b',
    "auth-security":    r'\b(authentication|authorization|oauth|jwt|security\s+config|credential|permission|role-based|access\s+control|token\s+validation|password\s+hash)\b',
    "breaking-api":     r'\b(breaking\s+change|remove\s+endpoint|deprecate\s+endpoint|change\s+response\s+(format|shape)|change\s+contract|api\s+version\s+bump)\b',
    "data-destructive": r'\b(delete\s+data|purge|wipe|cleanup\s+data|production\s+data|truncate)\b',
    "concurrency":      r'\b(@transactional|distributed\s+transaction|race\s+condition|two-phase\s+commit|optimistic\s+lock|pessimistic\s+lock)\b',
}
hits = {}
for label, pattern in signals.items():
    matches = re.findall(pattern, text)
    if matches:
        hits[label] = sorted(set(matches))[:3]
print(json.dumps(hits))
PY
}

# ---------------------------------------------------------------------------
# Spec consistency check (internal contradictions)
# Language-agnostic — pure regex on spec text.
# ---------------------------------------------------------------------------
check_spec_consistency() {
  local spec_file="$1"
  [ -f "$spec_file" ] || return 0
  python3 - <<'PY' "$spec_file"
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
pairs = [
    ("idempotent + per-call side effect",
     r'\bidempotent(ly|cy)?\b',
     r'\b(log|audit|notify|publish|emit)\b[^.\n]{0,40}\b(on|in|per|for)\s+(each|every)\s+(call|invocation|request)\b',
     None),
    ("remove + still-referenced",
     r'\b(remove|delete|drop)\s+(the\s+)?(endpoint|method|class|column|field|constant)\b',
     r'\bstill\s+(referenced|used|in[- ]use)\b',
     None),
    ("atomic + multi-step",
     r'\batomic\b',
     r'\bmulti[- ]step\b',
     r'\b(transaction|saga|two[- ]phase|coordinator|orchestrat)\w*'),
    ("cache + always fresh",
     r'\bcach(e|ing)\b',
     r'\b(always|fully)\s+(fresh|real[- ]time|up[- ]to[- ]date|current)\b',
     r'\b(invalidat|expir|ttl|evict|refresh\s+strategy)\w*'),
]
paragraphs = [p for p in re.split(r'\n\s*\n', text) if p.strip()]
flagged = []
for label, pat_a, pat_b, resolver in pairs:
    in_a = {i for i, p in enumerate(paragraphs) if re.search(pat_a, p, re.IGNORECASE)}
    in_b = {i for i, p in enumerate(paragraphs) if re.search(pat_b, p, re.IGNORECASE)}
    if not in_a or not in_b:
        continue
    if in_a & in_b:
        continue
    if resolver and re.search(resolver, text, re.IGNORECASE):
        continue
    flagged.append(label)
for label in flagged:
    print(label)
PY
}
