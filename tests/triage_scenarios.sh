#!/usr/bin/env bash
# Exercises every triage classification branch and the state.json update.
# Each scenario runs in an isolated scratch repo.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="$REPO"
PASS=0; FAIL=0
SCRATCH_ROOT="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

ok()  { printf '  \033[32mPASS\033[0m %s\n'   "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n'   "$1"; FAIL=$((FAIL+1)); }

assert_rc() {
  local exp="$1" label="$2"; shift 3; local out rc
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" -eq "$exp" ]; then ok "$label (rc=$rc)"; else bad "$label (rc=$rc, want $exp) :: ${out:0:200}"; fi
}

assert_json_val() {
  local file="$1" key="$2" exp="$3" label="$4"; local val
  val=$(python3 -c "import json; print(json.load(open('$file'))['$key'])" 2>/dev/null || echo "__MISSING__")
  if [ "$val" = "$exp" ]; then ok "$label ($key=$val)"; else bad "$label ($key=$val, want $exp)"; fi
}

assert_not_json_val() {
  local file="$1" key="$2" label="$3"
  if python3 -c "import json; d=json.load(open('$file')); assert '$key' not in d, f'unexpected key: $key'" 2>/dev/null; then
    ok "$label ($key absent)"
  else
    bad "$label ($key unexpectedly present)"
  fi
}

assert_json_arr() {
  local file="$1" key="$2" idx="$3" exp="$4" label="$5"; local val
  val=$(python3 -c "import json; print(json.load(open('$file'))['$key'][$idx])" 2>/dev/null || echo "__MISSING__")
  if [ "$val" = "$exp" ]; then ok "$label ($key[$idx]=$val)"; else bad "$label ($key[$idx]=$val, want $exp)"; fi
}

assert_out() {
  local sub="$1" label="$2"; shift 3; local out
  out="$("$@" 2>&1 </dev/null)"
  if printf '%s' "$out" | grep -qF "$sub"; then ok "$label"; else bad "$label (missing '$sub') :: ${out:0:200}"; fi
}

new_repo() {
  local d="$SCRATCH_ROOT/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q && git commit -q --allow-empty -m init && git checkout -q -b feature/demo )
  echo "$d"
}

# portable timeout
if command -v timeout >/dev/null 2>&1; then TO="timeout 15"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 15"
else TO=""; fi

setup_env() {
  local d="$1" slug="$2"
  mkdir -p "$d/.specwork/_spec" "$d/.specwork/_state"
  printf '{"id":"%s","slug":"%s","ticket_type":"feature","complexity":"MEDIUM","current_step":"spec","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1}\n' "$slug" "$slug" > "$d/.specwork/_state/${slug}-state.json"
}

write_spec() {
  local d="$1" slug="$2" behavior="$3" impl_ctx="$4" scope="$5"
  cat > "$d/.specwork/_spec/${slug}-spec.md" <<SPEC
# ${slug} — test

## Summary

Test scenario.

## Behavior

${behavior}

## Implementation Context

${impl_ctx}

## Expected Change Scope

${scope}
SPEC
}

echo "== triage scenarios =="

# -------------------------------------------------------
# 1) trivial — typo in behavior, 1 layer, ~1 file
# -------------------------------------------------------
d=$(new_repo triage-trivial)
setup_env "$d" "trivial-test"
write_spec "$d" "trivial-test" \
  "Fix a typo in the greeting message" \
  "One service file" \
  "Expected layers touched: service\nExpected files touched: 1"
cd "$d"
assert_rc 0 "trivial exit 0" -- $TO bash "$REPO/commands/triage.sh" trivial-test
assert_json_val ".specwork/_state/trivial-test-path.json"   "ticket_type" "trivial"     "trivial path.json ticket_type"
assert_json_val ".specwork/_state/trivial-test-path.json"   "complexity"  "LOW"         "trivial path.json complexity"
assert_json_val ".specwork/_state/trivial-test-state.json"  "ticket_type" "trivial"     "trivial state.json ticket_type"
assert_json_val ".specwork/_state/trivial-test-state.json"  "complexity"  "LOW"         "trivial state.json complexity"

# -------------------------------------------------------
# 2) focused — basic change, no high-risk, 1 layer, ~2 files
# -------------------------------------------------------
d=$(new_repo triage-focused)
setup_env "$d" "focused-test"
write_spec "$d" "focused-test" \
  "Add a new validation method to the service layer" \
  "Existing service class" \
  "Expected layers touched: service\nExpected files touched: 2"
cd "$d"
assert_rc 0 "focused exit 0" -- $TO bash "$REPO/commands/triage.sh" focused-test
assert_json_val ".specwork/_state/focused-test-path.json"   "ticket_type" "focused"     "focused path.json ticket_type"
assert_json_val ".specwork/_state/focused-test-path.json"   "complexity"  "LOW"         "focused path.json complexity"
assert_json_val ".specwork/_state/focused-test-state.json"  "ticket_type" "focused"     "focused state.json ticket_type"
assert_json_val ".specwork/_state/focused-test-state.json"  "complexity"  "LOW"         "focused state.json complexity"

# -------------------------------------------------------
# 3) standard — 2 layers, ~3 files
# -------------------------------------------------------
d=$(new_repo triage-standard)
setup_env "$d" "standard-test"
write_spec "$d" "standard-test" \
  "Add search endpoint" \
  "Service + controller wiring" \
  "Expected layers touched: controller, service\nExpected files touched: 3-4"
cd "$d"
assert_rc 0 "standard exit 0" -- $TO bash "$REPO/commands/triage.sh" standard-test
assert_json_val ".specwork/_state/standard-test-path.json"   "ticket_type" "standard"     "standard path.json ticket_type"
assert_json_val ".specwork/_state/standard-test-path.json"   "complexity"  "MEDIUM"       "standard path.json complexity"
assert_json_val ".specwork/_state/standard-test-state.json"  "ticket_type" "standard"     "standard state.json ticket_type"
assert_json_val ".specwork/_state/standard-test-state.json"  "complexity"  "MEDIUM"       "standard state.json complexity"

# -------------------------------------------------------
# 4) high-risk — "async" keyword triggers HIGH
# -------------------------------------------------------
d=$(new_repo triage-highrisk)
setup_env "$d" "highrisk-test"
write_spec "$d" "highrisk-test" \
  "Send an event asynchronously after lead creation" \
  "Async method with CompletableFuture, transactional" \
  "Expected layers touched: service, controller, repository, config\nExpected files touched: 5-7"
cd "$d"
assert_rc 0 "high-risk exit 0" -- $TO bash "$REPO/commands/triage.sh" highrisk-test
assert_json_val ".specwork/_state/highrisk-test-path.json"   "ticket_type" "high-risk"     "high-risk path.json ticket_type"
assert_json_val ".specwork/_state/highrisk-test-path.json"   "complexity"  "HIGH"          "high-risk path.json complexity"
assert_json_val ".specwork/_state/highrisk-test-state.json"  "ticket_type" "high-risk"     "high-risk state.json ticket_type"
assert_json_val ".specwork/_state/highrisk-test-state.json"  "complexity"  "HIGH"          "high-risk state.json complexity"

# -------------------------------------------------------
# 5) state.json missing — non-fatal, path.json still written
# -------------------------------------------------------
d=$(new_repo triage-no-state)
mkdir -p "$d/.specwork/_spec"
write_spec "$d" "no-state-test" \
  "Add a simple log statement" \
  "One service file" \
  "Expected layers touched: service\nExpected files touched: 1"
cd "$d"
assert_rc 0 "no-state exit 0" -- $TO bash "$REPO/commands/triage.sh" no-state-test
assert_json_val ".specwork/_state/no-state-test-path.json"   "ticket_type" "focused"   "no-state path.json ticket_type (fallback)"
# state.json was never created — triage should not crash, and should not write it
if [ ! -f ".specwork/_state/no-state-test-state.json" ]; then
  ok "no-state state.json not created when absent"
else
  bad "no-state state.json should not be created (non-existent on input)"
fi

# -------------------------------------------------------
# 6) spec.md missing — triage.sh rejects
# -------------------------------------------------------
d=$(new_repo triage-no-spec)
setup_env "$d" "no-spec-test"
# Deliberately omit spec.md
cd "$d"
assert_rc 1 "no-spec exit 1" -- $TO bash "$REPO/commands/triage.sh" no-spec-test
assert_out "Requires" "no-spec prints usage" -- $TO bash "$REPO/commands/triage.sh" no-spec-test

# -------------------------------------------------------
# 7) focused path.json — verify recommended_path and skip
# -------------------------------------------------------
d=$(new_repo triage-focused-path)
setup_env "$d" "fpath-test"
write_spec "$d" "fpath-test" \
  "Add a utility method to the config module" \
  "One config file" \
  "Expected layers touched: config\nExpected files touched: 1-2"
cd "$d"
$TO bash "$REPO/commands/triage.sh" fpath-test >/dev/null 2>&1
assert_json_arr ".specwork/_state/fpath-test-path.json" "recommended_path" 0 "f-implement" "focused path starts with implement"
assert_json_arr ".specwork/_state/fpath-test-path.json" "skip" 0             "f-plan"      "focused path skips plan"

echo "------------------------------------------------------------------"
printf " RESULT: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
