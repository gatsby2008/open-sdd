#!/usr/bin/env bash
# Self-contained smoke test for THIS repo (open-sdd).
# Exercises the non-interactive cases: precheck (+--fresh), the `check` command,
# step-tracking (out-of-sequence + advance + schema preservation), and the
# command wrappers' precondition gates. Runs each scenario in an isolated scratch
# git repo. References nothing outside this repo.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # tests -> repo root
export PYTHONPATH="$REPO"
PASS=0; FAIL=0
SCRATCH_ROOT="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_rc()  { local exp="$1" label="$2"; shift 3; local out rc
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" -eq "$exp" ]; then ok "$label (rc=$rc)"; else bad "$label (rc=$rc, want $exp) :: ${out:0:120}"; fi; }
assert_out() { local sub="$1" label="$2"; shift 3; local out
  out="$("$@" 2>&1 </dev/null)"
  if printf '%s' "$out" | grep -qF "$sub"; then ok "$label"; else bad "$label (missing '$sub') :: ${out:0:160}"; fi; }
new_repo() { local d="$SCRATCH_ROOT/$1"; mkdir -p "$d"; ( cd "$d" && git init -q && git commit -q --allow-empty -m init && git checkout -q -b feature/demo ); echo "$d"; }

# portable timeout (macOS lacks `timeout`; coreutils ships `gtimeout`)
if command -v timeout >/dev/null 2>&1; then TO="timeout 15"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 15"
else TO=""; fi

echo "== unit suite =="
( cd "$REPO" && python3 -m unittest discover -s tests -p 'test_*.py' >/dev/null 2>&1 ) \
  && ok "unittest suite" || bad "unittest suite"

echo "== precheck =="
d=$(new_repo precheck); cd "$d"
assert_rc 1 "no .specwork rejects" -- python3 -m engine.cli precheck
assert_rc 0 "--fresh clean passes" -- python3 -m engine.cli precheck --fresh
mkdir -p .specwork/_state
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"implement","input_type":"jira","source_file":"x"}' > .specwork/_state/demo-state.json
assert_rc 0 "initialized passes" -- python3 -m engine.cli precheck
assert_rc 1 "--fresh active pipeline rejects (start refuses)" -- python3 -m engine.cli precheck --fresh
assert_out "already initialized" "--fresh refusal message" -- python3 -m engine.cli precheck --fresh

echo "== check bug fixed =="
assert_out "MISSING" "check command reachable" -- python3 -m engine.cli check demo

echo "== step-tracking =="
assert_out "Out of sequence" "out-of-sequence message" -- python3 -m engine.cli expected-step commit demo
assert_out "Run next: implement" "suggests next" -- python3 -m engine.cli expected-step commit demo
python3 -m engine.cli advance-step demo >/dev/null 2>&1
assert_out '"input_type"' "advance preserves start.sh keys" -- cat .specwork/_state/demo-state.json
assert_out '"current_step": "commit"' "advance moves implement -> commit (no generic test step)" -- cat .specwork/_state/demo-state.json

echo "== optional-step skip (high-risk) =="
printf '{"slug":"hr","ticket_type":"high-risk","current_step":"test-design"}' > .specwork/_state/hr-state.json
assert_rc 0 "commit reachable by skipping optional steps" -- python3 -m engine.cli expected-step commit hr
assert_rc 1 "backward move blocked" -- python3 -m engine.cli expected-step implement hr
python3 -m engine.cli advance-step hr commit >/dev/null 2>&1
assert_out '"current_step": "mr"' "advance anchored on commit lands on mr" -- cat .specwork/_state/hr-state.json

echo "== command wrappers =="
d=$(new_repo wrappers); cd "$d"
for w in plan implement handoff; do
  out="$($TO bash "$REPO/commands/$w.sh" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "No active pipeline"; then
    ok "$w.sh rejects without pipeline"
  else
    bad "$w.sh reject path (rc=$rc) :: ${out:0:120}"
  fi
done
out="$($TO bash "$REPO/commands/status.sh" 2>&1 </dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "/f-start"; then
  ok "status.sh graceful without pipeline"
else
  bad "status.sh graceful path (rc=$rc) :: ${out:0:120}"
fi

echo "== commit standalone; test-* require a pipeline =="
# commit.sh must pass the pipeline gate standalone (git-only mode) and only fail
# later at check.sh — never at the gate.
d=$(new_repo standalone-commit); cd "$d"
out="$($TO bash "$REPO/commands/commit.sh" 2>&1 </dev/null)"
if printf '%s' "$out" | grep -qiF "No pipeline"; then
  bad "commit.sh blocks standalone (should be git-only mode)"
else
  ok "commit.sh works standalone (no pipeline gate)"
fi
# test-design / test-impl now require a pipeline (R2: no standalone mode).
for w in test-design test-impl; do
  d=$(new_repo "pipeline-required-$w"); cd "$d"
  out="$($TO bash "$REPO/commands/$w.sh" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiF "No pipeline"; then
    ok "$w.sh requires a pipeline"
  else
    bad "$w.sh pipeline-required path (rc=$rc) :: ${out:0:120}"
  fi
done

echo "------------------------------------------------------------------"
printf " RESULT: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
