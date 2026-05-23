#!/usr/bin/env bash

# SDD metrics helper.
# Output under .specwork/_metrics/:
# - <slug>-metrics.json (timing + token summary in one file)

derive_slug_from_branch() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$branch" ] || return 1
  branch="${branch#*/}"
  printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

resolve_state_file() {
  local slug state
  slug=$(derive_slug_from_branch 2>/dev/null || true)
  if [ -n "$slug" ] && [ -f ".specwork/_state/${slug}-state.json" ]; then
    printf '%s\n' ".specwork/_state/${slug}-state.json"
    return 0
  fi
  state=$(find .specwork/_state -type f -name "*-state.json" 2>/dev/null | sort | head -1)
  [ -n "$state" ] || return 1
  printf '%s\n' "$state"
}

resolve_metrics_file() {
  local feature_id
  feature_id=$(get_feature_id 2>/dev/null || true)
  if [ -n "$feature_id" ]; then
    printf '%s\n' ".specwork/_metrics/${feature_id}-metrics.json"
    return 0
  fi
  feature_id=$(derive_slug_from_branch 2>/dev/null || true)
  if [ -n "$feature_id" ]; then
    printf '%s\n' ".specwork/_metrics/${feature_id}-metrics.json"
    return 0
  fi
  printf '%s\n' ".specwork/_metrics/unknown-metrics.json"
}

get_feature_id() {
  local state_file
  state_file=$(resolve_state_file) || return 1
  python3 - "$state_file" <<'PY'
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    value = data.get("id", "")
    if isinstance(value, str) and value:
        print(value)
except Exception:
    pass
PY
}

get_metrics_mode() {
  local state_file
  state_file=$(resolve_state_file 2>/dev/null || true)
  if [ -z "$state_file" ]; then
    echo "all"
    return 0
  fi
  python3 - "$state_file" <<'PY'
import json, sys
from pathlib import Path
mode = "all"
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    value = data.get("metrics_mode", "all")
    if value in ("heavy", "all", "none"):
        mode = value
except Exception:
    pass
print(mode)
PY
}

is_metrics_enabled_for_skill() {
  local skill="$1" mode
  mode=$(get_metrics_mode)
  case "$mode" in
    none) return 1 ;;
    heavy)
      case "$skill" in
        f-start|f-plan|f-implement) return 0 ;;
        *) return 1 ;;
      esac ;;
    all|*) return 0 ;;
  esac
}

estimate_tokens() {
  local text="$1" char_count
  char_count=$(printf '%s' "$text" | wc -c | tr -d ' ')
  echo $((char_count / 4))
}

warn_metrics() {
  printf 'metrics: %s\n' "$*" >&2
}

resolve_spec_file() {
  local explicit="$1"
  local state_file spec_path slug
  if [ -n "$explicit" ] && [ -f "$explicit" ]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  state_file=$(resolve_state_file 2>/dev/null || true)
  if [ -n "$state_file" ]; then
    spec_path=$(python3 - "$state_file" <<'PY'
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    value = data.get("spec_file", "")
    if isinstance(value, str):
        print(value)
except Exception:
    pass
PY
)
    if [ -n "$spec_path" ] && [ -f "$spec_path" ]; then
      printf '%s\n' "$spec_path"
      return 0
    fi
  fi
  slug=$(derive_slug_from_branch 2>/dev/null || true)
  if [ -n "$slug" ] && [ -f ".specwork/_spec/${slug}-spec.md" ]; then
    printf '%s\n' ".specwork/_spec/${slug}-spec.md"
    return 0
  fi
  spec_path=$(find .specwork/_spec -type f -name "*-spec.md" 2>/dev/null | sort | head -1)
  [ -n "$spec_path" ] && printf '%s\n' "$spec_path"
}

metrics_start() {
  mkdir -p ".specwork/_metrics"
  date +%s > ".specwork/_metrics/.start_ts"
  rm -f ".specwork/_metrics/.scanned_files"
}

append_metrics_run() {
  local skill="$1" step="$2" timestamp="$3" mode="$4"
  local files_scanned="$5" files_changed="$6" full_scan="$7"
  local duration="$8" spec_tokens="$9" output_tokens="${10}"
  local total_tokens="${11}" source="${12}" metrics_file feature_id
  metrics_file=$(resolve_metrics_file)
  feature_id=$(get_feature_id 2>/dev/null || echo "unknown")
  python3 - "$metrics_file" "$feature_id" "$skill" "$step" "$timestamp" "$mode" "$files_scanned" "$files_changed" "$full_scan" "$duration" "$spec_tokens" "$output_tokens" "$total_tokens" "$source" <<'PY'
import json, sys
from pathlib import Path
metrics_file = Path(sys.argv[1])
feature_id = sys.argv[2]
skill = sys.argv[3]
step = sys.argv[4]
timestamp = sys.argv[5]
mode = sys.argv[6]
files_scanned = int(sys.argv[7])
files_changed = int(sys.argv[8])
full_scan_raw = sys.argv[9].strip().lower()
full_scan = full_scan_raw in ("true", "1", "yes")
duration = int(sys.argv[10])
spec_tokens = int(sys.argv[11])
output_tokens = int(sys.argv[12])
total_tokens = int(sys.argv[13])
source = sys.argv[14]
if metrics_file.exists():
    try:
        data = json.loads(metrics_file.read_text(encoding="utf-8"))
    except Exception:
        data = {}
else:
    data = {}
if not isinstance(data, dict):
    data = {}
for item in data.get("runs", []):
    if isinstance(item, dict) and "spec_tokens" not in item and "brief_tokens" in item:
        item["spec_tokens"] = int(item.get("brief_tokens", 0))
        item.pop("brief_tokens", None)
data.setdefault("schema_version", 1)
data.setdefault("feature_id", feature_id)
data.setdefault("runs", [])
data.setdefault("summary", {"total_runs": 0, "total_tokens": 0, "by_skill": {}, "estimated_cost_sonnet": 0.00})
run = {
    "skill": skill, "timestamp": timestamp, "source": source, "mode": mode,
    "files_scanned": files_scanned, "files_changed": files_changed,
    "full_scan": full_scan, "duration_seconds": duration,
    "spec_tokens": spec_tokens, "output_tokens": output_tokens,
    "total_tokens": total_tokens,
}
if step:
    try:
        run["step"] = int(step)
    except ValueError:
        run["step"] = step
data["runs"].append(run)
total_runs = len(data["runs"])
total_tokens_acc = 0
by_skill = {}
for item in data["runs"]:
    skill_name = item.get("skill", "unknown")
    item_tokens = int(item.get("total_tokens", 0))
    total_tokens_acc += item_tokens
    if skill_name not in by_skill:
        by_skill[skill_name] = {"runs": 0, "total_tokens": 0}
    by_skill[skill_name]["runs"] += 1
    by_skill[skill_name]["total_tokens"] += item_tokens
data["summary"] = {
    "total_runs": total_runs,
    "total_tokens": total_tokens_acc,
    "by_skill": by_skill,
    "estimated_cost_sonnet": round(total_tokens_acc * 9 / 1_000_000, 2),
}
metrics_file.parent.mkdir(parents=True, exist_ok=True)
metrics_file.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

metrics_end() {
  local skill="$1" mode="${2:-focused}" files_scanned="${3:-0}" files_changed="${4:-0}" full_scan="${5:-false}"
  local now duration timestamp spec_file spec_tokens
  local diff_chars untracked_chars output_chars output_tokens git_files_changed
  is_metrics_enabled_for_skill "$skill" || return 0
  now=$(date +%s)
  if [ -f ".specwork/_metrics/.start_ts" ]; then
    START_TS=$(cat ".specwork/_metrics/.start_ts" 2>/dev/null || echo "$now")
    duration=$((now - START_TS))
    rm -f ".specwork/_metrics/.start_ts"
  elif [ -n "${METRICS_START_TS:-}" ]; then
    duration=$((now - METRICS_START_TS))
  else
    duration=0
  fi
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  case "$files_scanned" in ''|*[!0-9]*) files_scanned=0 ;; esac
  case "$files_changed" in ''|*[!0-9]*) files_changed=0 ;; esac
  if [ -f ".specwork/_metrics/.scanned_files" ]; then
    files_scanned=$(sort -u ".specwork/_metrics/.scanned_files" 2>/dev/null | wc -l | tr -d ' ')
    rm -f ".specwork/_metrics/.scanned_files"
  fi
  spec_tokens=0
  spec_file=$(resolve_spec_file "" 2>/dev/null || true)
  if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
    spec_tokens=$(estimate_tokens "$(cat "$spec_file" 2>/dev/null)")
  fi
  output_tokens=0
  git_files_changed=0
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    git_files_changed=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    diff_chars=$(git diff HEAD 2>/dev/null | wc -c | tr -d ' ')
    untracked_chars=$(git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
      [ -f "$f" ] && cat "$f" 2>/dev/null
    done | wc -c | tr -d ' ')
    output_chars=$((diff_chars + untracked_chars))
    output_tokens=$((output_chars / 4))
  fi
  if [ "$git_files_changed" -gt 0 ]; then
    files_changed=$git_files_changed
  fi
  append_metrics_run "$skill" "" "$timestamp" "$mode" "$files_scanned" "$files_changed" "$full_scan" "$duration" "$spec_tokens" "$output_tokens" "$((spec_tokens + output_tokens))" "metrics_end"
}

record_tokens() {
  local skill="$1" step="${2:-}" spec_file_arg="${3:-}" output_tokens="${4:-0}"
  local spec_file spec_tokens total_tokens timestamp
  is_metrics_enabled_for_skill "$skill" || return 0
  spec_file=$(resolve_spec_file "$spec_file_arg" 2>/dev/null || true)
  spec_tokens=0
  if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
    spec_tokens=$(estimate_tokens "$(cat "$spec_file" 2>/dev/null)")
  fi
  case "$output_tokens" in
    ''|*[!0-9]*) output_tokens=0 ;;
  esac
  if [ -z "$spec_file" ] && [ "$output_tokens" -eq 0 ]; then
    warn_metrics "skipping token record for ${skill}: no spec file resolved and no output token estimate provided"
    return 0
  fi
  total_tokens=$((spec_tokens + output_tokens))
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  append_metrics_run "$skill" "$step" "$timestamp" "focused" "0" "0" "false" "0" "$spec_tokens" "$output_tokens" "$total_tokens" "record_tokens"
}
