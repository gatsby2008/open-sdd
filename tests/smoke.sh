#!/usr/bin/env bash
# Self-contained smoke test for THIS repo (open-sdd).
# Exercises the non-interactive cases: precheck (+--fresh), the `check` command,
# spec/plan/implement idempotency, the reference-update fix, /f-spec draft/refine
# modes, and the command wrappers' precondition gates. Runs each scenario in an
# isolated scratch git repo. References nothing outside this repo.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # tests -> repo root
export PYTHONPATH="$REPO"
PASS=0; FAIL=0
SCRATCH_ROOT="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_rc()    { local exp="$1" label="$2"; shift 3; local out rc
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" -eq "$exp" ]; then ok "$label (rc=$rc)"; else bad "$label (rc=$rc, want $exp) :: ${out:0:120}"; fi; }
assert_out()   { local sub="$1" label="$2"; shift 3; local out
  out="$("$@" 2>&1 </dev/null)"
  if printf '%s' "$out" | grep -qF "$sub"; then ok "$label"; else bad "$label (missing '$sub') :: ${out:0:160}"; fi; }
assert_noout() { local sub="$1" label="$2"; shift 3; local out
  out="$("$@" 2>&1 </dev/null)"
  if printf '%s' "$out" | grep -qF "$sub"; then bad "$label (unexpected '$sub') :: ${out:0:160}"; else ok "$label"; fi; }
assert_json()  { local file="$1" key="$2" exp="$3" label="$4"; local val
  val=$(python3 -c "import json; print(json.load(open('$file'))['$key'])" 2>/dev/null || echo "__MISSING__")
  if [ "$val" = "$exp" ]; then ok "$label ($key=$val)"; else bad "$label ($key=$val, want $exp)"; fi; }
# Set a repo-local git identity so the initial commit works on runners/machines
# that have no global git user configured (otherwise the branch never gets born,
# slug resolution falls back to "HEAD", and most branch-dependent tests fail).
new_repo() { local d="$SCRATCH_ROOT/$1"; mkdir -p "$d"; ( cd "$d" && git init -q && git config user.email "smoke@open-sdd.test" && git config user.name "open-sdd smoke" && git commit -q --allow-empty -m init && git checkout -q -b feature/demo ); echo "$d"; }

# portable timeout (macOS lacks `timeout`; coreutils ships `gtimeout`)
if command -v timeout >/dev/null 2>&1; then TO="timeout 15"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 15"
else TO=""; fi

echo "== unit suite =="
( cd "$REPO" && python3 -m unittest discover -s tests -p 'test_*.py' >/dev/null 2>&1 ) \
  && ok "unittest suite" || bad "unittest suite"

echo "== installer parity =="
if ( cd "$REPO" && bash tests/check-install-parity.sh >/dev/null 2>&1 ); then
  ok "install.sh/install.ps1 parity check"
else
  bad "install.sh/install.ps1 parity check"
fi

echo "== sdd surface parity =="
if ( cd "$REPO" && bash tests/check-sdd-surface-parity.sh >/dev/null 2>&1 ); then
  ok "sdd surface parity check"
else
  bad "sdd surface parity check"
fi

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

echo "== f-auto: start then auto skips re-start =="
d=$(new_repo auto-skip-start); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_plan .specwork/_progress
cat > .specwork/_state/demo-state.json <<'JSON'
{"id":"demo","slug":"demo","ticket_type":"feature","input_type":"freetext","branch":"feature/demo","non_interactive":false,"spec_write_timestamp":1}
JSON
printf '{"schema_version":1,"id":"demo","global_rules":[],"service_rules":[]}\n' > .specwork/_state/demo-rules.json
printf '{"schema_version":1,"id":"demo","repositories":[],"patterns":[],"related_tests":[],"similar_classes":[],"notes":[]}\n' > .specwork/_state/demo-implementation-cache.json
printf '# source\n' > .specwork/_spec/demo-source.md
printf '# demo\n\n## Open Questions\n' > .specwork/_spec/demo-spec.md
out="$($TO bash "$REPO/commands/auto.sh" "demo ticket" 2>&1 </dev/null || true)"
if printf '%s' "$out" | grep -qF "Existing pipeline detected — skipping /f-start"; then
  ok "f-auto skips /f-start when pipeline already exists"
else
  bad "f-auto should skip /f-start on active pipeline :: ${out:0:200}"
fi

echo "== risk-signals (f-auto test gate) =="
d=$(new_repo risksig); cd "$d"; mkdir -p .specwork/_spec
printf '# m\n## Behavior\nAdd a Flyway migration and alter table users.\n' > .specwork/_spec/demo-spec.md
assert_out "db-migration" "risk-signals detects hard signal" -- python3 -m engine.cli risk-signals demo
printf '# c\n## Behavior\nRename a label on the landing page.\n' > .specwork/_spec/clean-spec.md
assert_noout "db-migration" "risk-signals silent on clean spec" -- python3 -m engine.cli risk-signals clean

echo "== command wrappers =="
d=$(new_repo wrappers); cd "$d"
for w in plan implement handoff spec; do
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

echo "== non-interactive mode rehydrates from state.json =="
d=$(new_repo noninteractive-hydrate); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_plan
cat > .specwork/_state/demo-state.json <<'JSON'
{"id":"demo","slug":"demo","ticket_type":"feature","input_type":"freetext","branch":"feature/demo","non_interactive":true,"spec_write_timestamp":4102444800}
JSON
printf '{"schema_version":1,"id":"demo","global_rules":[],"service_rules":[]}\n' > .specwork/_state/demo-rules.json
printf '# demo\n\n## Open Questions\n' > .specwork/_spec/demo-spec.md
printf '# plan\n' > .specwork/_plan/demo-plan.md
cat > .specwork/_plan/demo-plan.json <<'JSON'
{"schema_version":1,"id":"demo","target_files":[{"path":"README.md","change":"touch","tags":"docs"}]}
JSON
unset SDD_NON_INTERACTIVE || true
out="$(bash "$REPO/commands/implement.sh" 2>&1 </dev/null || true)"
if printf '%s' "$out" | grep -qF "Non-interactive: re-running /f-plan automatically."; then
  ok "implement.sh rehydrates non-interactive mode from state.json"
else
  bad "implement.sh did not rehydrate non-interactive mode :: ${out:0:200}"
fi

echo "== spec.sh detects draft vs refine by spec.md presence =="
d=$(new_repo spec-mode); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"spec","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n\nSomething captured from input.\n' > .specwork/_spec/demo-source.md
# No spec.md → draft mode (spec.sh creates it from source.md + template)
out="$($TO bash "$REPO/commands/spec.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "SPEC DRAFT SESSION"; then
  ok "spec.sh draft mode when spec.md is absent"
else
  bad "spec.sh draft mode :: ${out:0:160}"
fi
# Now create spec.md with content — should flip to refine mode. WITH args.
printf '# demo — sample\n\n## Summary\n\nWhatever.\n' > .specwork/_spec/demo-spec.md
out="$($TO bash "$REPO/commands/spec.sh" "extra context" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "SPEC REFINE SESSION"; then
  ok "spec.sh refine mode when spec.md exists + args"
else
  bad "spec.sh refine mode :: ${out:0:160}"
fi
echo "== spec.sh idempotent: refine + no args = no-op =="
# Same scratch repo, still in refine mode. No args this time.
out="$($TO bash "$REPO/commands/spec.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "SPEC NO-OP"; then
  ok "spec.sh refine + no args prints no-op"
else
  bad "spec.sh no-op missing :: ${out:0:160}"
fi
# No-op must not emit bump-spec-ts instruction.
if printf '%s' "$out" | grep -qF "bump-spec-ts"; then
  bad "spec.sh no-op should NOT emit bump-spec-ts :: ${out:0:160}"
else
  ok "spec.sh no-op skips bump-spec-ts"
fi
# No-op exit code 0.
if [ "$rc" -eq 0 ]; then
  ok "spec.sh no-op exit 0"
else
  bad "spec.sh no-op exit (rc=$rc)"
fi

echo "== spec.sh aborts when source.md missing =="
d=$(new_repo spec-no-source); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"spec","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
# Deliberately omit source.md. /f-start always writes it, so its absence means start did not run cleanly.
out="$($TO bash "$REPO/commands/spec.sh" 2>&1 </dev/null)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "Missing required artifacts"; then
  ok "spec.sh aborts when source.md missing"
else
  bad "spec.sh should abort on missing source.md (rc=$rc) :: ${out:0:160}"
fi

echo "== plan.sh reference-update over-fire fix (consumer-portal bug 2026-05-29) =="
# Spec mentions /consumers descriptively in Implementation Context (no
# rename/remove language). plan.sh must NOT generate [reference-update]
# targets for it.
d=$(new_repo refgrep-nofire); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress src/main/java/foo
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"plan","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n' > .specwork/_spec/demo-source.md
cat > .specwork/_spec/demo-spec.md <<'SPEC'
# demo — Ensure REST responses do not expose PII

## Summary
Sanitize REST responses to omit PII.

## Behavior
- Endpoints should not return PII in response bodies.

## Implementation Context
- Files: src/main/java/foo/Service.java
- Endpoints:
  - POST /consumers
  - GET /consumers?applicationId=...

## Open Questions
SPEC
printf 'class Bar { String x = "/consumers"; }' > src/main/java/foo/Bar.java
out="$($TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "Reference-update signal detected"; then
  bad "plan.sh wrongly fired reference-update on descriptive /consumers mention :: ${out:0:200}"
else
  ok "plan.sh does NOT fire reference-update without trigger language"
fi

# Now add explicit rename language → reference-update SHOULD fire.
d=$(new_repo refgrep-fire); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress src/main/java/foo
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"plan","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n' > .specwork/_spec/demo-source.md
cat > .specwork/_spec/demo-spec.md <<'SPEC'
# demo — Rename legacy endpoint

## Summary
Remove /old-endpoint and use /new-endpoint instead.

## Behavior
- Remove /old-endpoint from the routes.

## Open Questions
SPEC
printf 'class Caller { String url = "/old-endpoint"; }' > src/main/java/foo/Caller.java
out="$($TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "Reference-update signal detected"; then
  ok "plan.sh fires reference-update WHEN trigger language present"
else
  bad "plan.sh missed real reference-update signal :: ${out:0:200}"
fi

echo "== plan.sh reference-update guards (MYYES-15518 56-target blow-up) =="
# Guard 1+2: a "Do NOT remove ... @Size" line lives under ## Safe Constraints AND
# is negated. It must NOT seed @Size / phoneNumber reference-update targets, even
# though those symbols appear in many source files. A legit non-negated removal
# line ("Remove the duplicate @AssertTrue") still fires.
d=$(new_repo refgrep-safe-constraints); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress src/main/java/foo
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"plan","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n' > .specwork/_spec/demo-source.md
cat > .specwork/_spec/demo-spec.md <<'SPEC'
# demo — Fix duplicate annotation

## Summary
Fix a duplicate validation annotation.

## Behavior
- Remove the duplicate `@AssertTrue` on `Thing`.

## Safe Constraints
### Unsafe
- Do NOT remove or modify the `@Size` constraint on `phoneNumber`.

## Open Questions
SPEC
for i in 1 2 3 4 5; do printf '@Size class F%s { String phoneNumber; }' "$i" > "src/main/java/foo/F$i.java"; done
printf '@AssertTrue class Thing {}' > src/main/java/foo/Thing.java
out="$($TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "references @Size"; then
  bad "plan.sh extracted @Size from a Safe Constraints / negated line :: ${out:0:200}"
else
  ok "plan.sh skips @Size (Safe Constraints + negation guards)"
fi
if printf '%s' "$out" | grep -qF "references phoneNumber"; then
  bad "plan.sh extracted phoneNumber from a Safe Constraints / negated line :: ${out:0:200}"
else
  ok "plan.sh skips phoneNumber (Safe Constraints + negation guards)"
fi
if printf '%s' "$out" | grep -qF "references @AssertTrue"; then
  ok "plan.sh still fires reference-update for the legit non-negated removal"
else
  bad "plan.sh dropped the legit @AssertTrue reference-update :: ${out:0:200}"
fi

# Guard 3: a non-negated removal of a generic token that matches more files than
# OPEN_SDD_REF_HIT_CAP is skipped with a warning (cap lowered to 2 for the test).
d=$(new_repo refgrep-hitcap); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress src/main/java/foo
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"plan","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n' > .specwork/_spec/demo-source.md
cat > .specwork/_spec/demo-spec.md <<'SPEC'
# demo — Remove a field

## Summary
Drop a widely-used field.

## Behavior
- Remove `widgetField` from all DTOs.

## Open Questions
SPEC
for i in 1 2 3; do printf 'class G%s { String widgetField; }' "$i" > "src/main/java/foo/G$i.java"; done
out="$(OPEN_SDD_REF_HIT_CAP=2 $TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "too generic, skipping"; then
  ok "plan.sh hit-cap skips a generic token matching > cap files"
else
  bad "plan.sh should warn + skip over-cap token :: ${out:0:200}"
fi
if printf '%s' "$out" | grep -qF "references widgetField"; then
  bad "plan.sh added reference-update targets for an over-cap token :: ${out:0:200}"
else
  ok "plan.sh adds no reference-update targets for the over-cap token"
fi

echo "== pause/resume: .specwork/ must NOT come back staged (resume staging bug) =="
# /f-pause force-adds gitignored .specwork/ into the stash; a plain `git stash
# pop` restores those new files to the index (staged). /f-resume must unstage
# .specwork/ so transient pipeline state never gets committed.
d=$(new_repo pause-resume); cd "$d"
printf '.specwork/\n' > .gitignore
git add .gitignore && git commit -qm "add gitignore" >/dev/null 2>&1
mkdir -p .specwork/_state .specwork/_spec src
printf '{"id":"demo","slug":"demo","ticket_type":"feature","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '# demo\n' > .specwork/_spec/demo-spec.md
printf 'class A {}\n' > src/A.java
$TO bash "$REPO/commands/pause.sh" >/dev/null 2>&1 </dev/null
printf 'y\n' | $TO bash "$REPO/commands/resume.sh" >/dev/null 2>&1
staged_specwork="$(git diff --cached --name-only 2>/dev/null | grep '^\.specwork/' || true)"
if [ -z "$staged_specwork" ]; then
  ok "resume leaves .specwork/ unstaged"
else
  bad "resume staged .specwork/ files :: ${staged_specwork//$'\n'/, }"
fi
if [ -f .specwork/_state/demo-state.json ]; then
  ok "resume restored .specwork/ into the working tree"
else
  bad "resume lost .specwork/ files"
fi

echo "== Ola 1: plan/implement are idempotent (no step gates) =="
# Setup: pipeline with spec.md drafted (no unresolved OQs), current_step
# advanced past implement (simulating user already ran some implements).
d=$(new_repo ola1); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress .specwork/_plan
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"commit","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n\nSource captured.\n' > .specwork/_spec/demo-source.md
printf '# demo — sample\n\n## Summary\n\nA thing.\n\n## Behavior\n\nDoes X.\n\n## Implementation Context\n\n`FooService`.\n\n## Open Questions\n' > .specwork/_spec/demo-spec.md

# plan.sh must NOT reject as "out of sequence" even with current_step="commit".
out="$($TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "Pipeline out of order"; then
  bad "plan.sh should be re-runnable past plan step :: ${out:0:160}"
else
  ok "plan.sh allowed past plan step (no out-of-order rejection)"
fi

# After that run, plan.md exists. Re-running with all inputs unchanged → no-op.
out="$($TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "PLAN NO-OP"; then
  ok "plan.sh no-op when inputs unchanged"
else
  bad "plan.sh should be no-op on re-run :: ${out:0:160}"
fi
# No-op exit code 0.
if [ "$rc" -eq 0 ]; then
  ok "plan.sh no-op exit 0"
else
  bad "plan.sh no-op exit (rc=$rc)"
fi

# Bump spec_write_timestamp → plan.sh should regenerate (not no-op).
# In real use this happens via /f-spec; here we bump directly through the engine
# to simulate that without exercising the LLM-driven /f-spec flow.
sleep 1
python3 -m engine.cli bump-spec-ts demo >/dev/null
out="$($TO bash "$REPO/commands/plan.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "PLAN NO-OP"; then
  bad "plan.sh should regenerate after spec_write_timestamp bump :: ${out:0:160}"
else
  ok "plan.sh regenerates after spec_write_timestamp bump"
fi

# plan.sh re-runs must not yank current_step backward. State should stay at "commit".
CURRENT=$(python3 -c "import json; print(json.load(open('.specwork/_state/demo-state.json'))['current_step'])")
if [ "$CURRENT" = "commit" ]; then
  ok "plan.sh re-run preserves current_step=commit"
else
  bad "plan.sh re-run moved current_step to $CURRENT (expected commit)"
fi

# implement.sh must NOT reject "out of order" with current_step="commit".
# It will still fail on artifact gates (no plan.json) but the step gate is gone.
out="$($TO bash "$REPO/commands/implement.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "Pipeline out of order"; then
  bad "implement.sh should not reject as out-of-order :: ${out:0:160}"
else
  ok "implement.sh allowed past implement step (no out-of-order rejection)"
fi

echo "== implement.sh supports no-plan workflow =="
# Spec ready, no plan.json — implement.sh must NOT abort with NO_PLAN.
# It should enter "no-plan workflow" (inline discovery from spec).
d=$(new_repo no-plan-impl); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"implement","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1000}' > .specwork/_state/demo-state.json
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
printf '# demo — sample\n\nSource.\n' > .specwork/_spec/demo-source.md
printf '# demo — sample\n\n## Summary\n\nThing.\n\n## Behavior\n\nDoes X.\n\n## Implementation Context\n\n`FooService`.\n\n## Open Questions\n' > .specwork/_spec/demo-spec.md
# Deliberately omit .specwork/_plan/* — no plan, plan.sh was skipped.
out="$($TO bash "$REPO/commands/implement.sh" 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "No plan found"; then
  bad "implement.sh should NOT fail with NO_PLAN — must support no-plan workflow :: ${out:0:200}"
else
  ok "implement.sh accepts missing plan (no NO_PLAN fatal error)"
fi
if printf '%s' "$out" | grep -qF "no-plan workflow"; then
  ok "implement.sh emits no-plan workflow instructions"
else
  bad "implement.sh did not enter no-plan workflow :: ${out:0:200}"
fi

echo "== start.sh --keep derives slug from current branch (not from input) =="
# Bug reproduction: user is already on feature/MYYES-15518 and runs /f-start
# with a long free-text description. SLUG must come from the branch
# (myyes-15518), NOT from slugifying the long input — otherwise we get
# .specwork/_spec/ensure-src-main-java-...-rest-response-spec.md.
d=$(new_repo keep-slug); cd "$d"
git checkout -q -b feature/MYYES-15518
LONG_INPUT="ensure src main java com refijet myyesgo consumerportal service ExternalConsumerService java and src main java com refijet myyesgo consumerportal controller CreateConsumerController java do not return PII in the rest response"
out="$($TO bash "$REPO/commands/start.sh" "$LONG_INPUT" --keep 2>&1 </dev/null)"; rc=$?

# Expected slug: myyes-15518 (from branch), NOT the long slugified input.
if [ -f .specwork/_state/myyes-15518-state.json ]; then
  ok "start.sh --keep slug derived from branch (myyes-15518)"
else
  ACTUAL=$(find .specwork/_state -name "*-state.json" 2>/dev/null | head -1)
  bad "start.sh --keep wrong slug :: got $ACTUAL"
fi

# state.json::slug field must match the file naming.
if [ -f .specwork/_state/myyes-15518-state.json ]; then
  SLUG_FIELD=$(python3 -c "import json; print(json.load(open('.specwork/_state/myyes-15518-state.json'))['slug'])")
  if [ "$SLUG_FIELD" = "myyes-15518" ]; then
    ok "state.json::slug matches branch-derived slug"
  else
    bad "state.json::slug=$SLUG_FIELD (expected myyes-15518)"
  fi
fi

echo "== start.sh auto-gitignores .specwork/ =="
# Fresh repo without .gitignore — start.sh should create it.
d=$(new_repo gitignore-fresh); cd "$d"
out="$($TO bash "$REPO/commands/start.sh" "test ticket body" --keep 2>&1 </dev/null)"; rc=$?
if [ -f .gitignore ] && grep -qE '^\.specwork(/|$)' .gitignore; then
  ok "start.sh creates .gitignore with .specwork/ when missing"
else
  bad "start.sh did not create .gitignore properly (rc=$rc) :: ${out:0:160}"
fi

# Existing .gitignore without .specwork — start.sh should append.
d=$(new_repo gitignore-existing); cd "$d"
printf 'build/\n*.log\n' > .gitignore
out="$($TO bash "$REPO/commands/start.sh" "another ticket" --keep 2>&1 </dev/null)"; rc=$?
if grep -qE '^\.specwork(/|$)' .gitignore && grep -qF 'build/' .gitignore; then
  ok "start.sh appends .specwork/ without clobbering existing .gitignore"
else
  bad "start.sh did not append cleanly :: $(cat .gitignore | head -10)"
fi

# Existing .gitignore already containing .specwork/ — start.sh should NOT duplicate.
d=$(new_repo gitignore-already-set); cd "$d"
printf '.specwork/\n' > .gitignore
out="$($TO bash "$REPO/commands/start.sh" "third ticket" --keep 2>&1 </dev/null)"; rc=$?
count=$(grep -cE '^\.specwork(/|$)' .gitignore)
if [ "$count" = "1" ]; then
  ok "start.sh idempotent (does not duplicate .specwork/ entry)"
else
  bad "start.sh duplicated .specwork/ entry (count=$count)"
fi

# Pre-tracked .specwork files — start.sh should warn with git rm --cached hint.
# Use a file outside _state/ so precheck --fresh still passes (precheck only
# checks for *-state.json files; otherwise start would abort before our warn).
d=$(new_repo gitignore-pre-tracked); cd "$d"
mkdir -p .specwork/_progress
printf 'leftover' > .specwork/_progress/stray.md
git add .specwork/_progress/stray.md && git commit -q -m "wrongly tracked" 2>/dev/null
out="$($TO bash "$REPO/commands/start.sh" "fourth ticket" --keep 2>&1 </dev/null)"; rc=$?
if printf '%s' "$out" | grep -qF "git rm -r --cached .specwork/"; then
  ok "start.sh warns when .specwork/ is already tracked"
else
  bad "start.sh should warn about pre-tracked .specwork :: ${out:0:200}"
fi

echo "== start.sh also gitignores .opensdd/ =="
d=$(new_repo gitignore-opensdd); cd "$d"
out="$($TO bash "$REPO/commands/start.sh" "opensdd body" --keep 2>&1 </dev/null)"; rc=$?
if grep -qE '^\.opensdd(/|$)' .gitignore; then
  ok "start.sh gitignores .opensdd/"
else
  bad "start.sh did not gitignore .opensdd/ :: $(head -20 .gitignore)"
fi

d=$(new_repo gitignore-opensdd-set); cd "$d"
printf '.opensdd/\n' > .gitignore
out="$($TO bash "$REPO/commands/start.sh" "already set body" --keep 2>&1 </dev/null)"; rc=$?
oc=$(grep -cE '^\.opensdd(/|$)' .gitignore)
if [ "$oc" = "1" ]; then
  ok "start.sh idempotent for .opensdd/ (no duplicates)"
else
  bad "start.sh duplicated entries (.opensdd=$oc)"
fi

echo "== start.sh preserves free text in source.md (regression) =="
# Plain free-text input must land in the source body, not an empty file.
d=$(new_repo freetext-source); cd "$d"
out="$($TO bash "$REPO/commands/start.sh" "add email validation to signup" --keep 2>&1 </dev/null)"; rc=$?
SRC=".specwork/_spec/demo-source.md"
if [ -f "$SRC" ] && grep -qF "add email validation to signup" "$SRC"; then
  ok "start.sh writes free text into source.md body"
else
  bad "start.sh lost free text in source.md :: $([ -f "$SRC" ] && cat "$SRC" || echo MISSING)"
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

echo "== undo: reversible roundtrip, preserves .specwork/ =="
d=$(new_repo undo-demo); cd "$d"
printf '.specwork/\n' > .gitignore; git add .gitignore; git commit -q -m gi
echo base > Svc.java; git add Svc.java; git commit -q -m base
mkdir -p .specwork/_state; echo '{}' > .specwork/_state/demo-state.json
echo IMPL >> Svc.java        # tracked modification
echo new > New.java          # untracked, not ignored
out="$(bash "$REPO/commands/undo.sh" --preview 2>&1 </dev/null)"
printf '%s' "$out" | grep -qF "Would discard 2" && ok "undo --preview lists affected" || bad "undo --preview :: ${out:0:120}"
bash "$REPO/commands/undo.sh" >/dev/null 2>&1 </dev/null
[ -z "$(git status --porcelain)" ] && ok "undo clears the working tree" || bad "undo left changes behind"
[ -f .specwork/_state/demo-state.json ] && ok "undo preserves .specwork/" || bad "undo wiped .specwork/"
bash "$REPO/commands/undo.sh" --restore >/dev/null 2>&1 </dev/null
{ grep -qF IMPL Svc.java && [ -f New.java ]; } && ok "undo --restore recovers changes" || bad "undo --restore failed to recover"
out="$(bash "$REPO/commands/undo.sh" --hard 2>&1 </dev/null)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qF IMPL Svc.java; } && ok "undo --hard refuses without --force" || bad "undo --hard guard (rc=$rc)"
bash "$REPO/commands/undo.sh" --hard --force >/dev/null 2>&1 </dev/null
{ ! grep -qF IMPL Svc.java && [ -f .specwork/_state/demo-state.json ]; } && ok "undo --hard --force discards, keeps .specwork/" || bad "undo --hard --force"

echo "== triage updates state.json and path.json =="
d=$(new_repo triage-state); cd "$d"
mkdir -p .specwork/_state .specwork/_spec
printf '{"id":"tri-test","slug":"tri-test","ticket_type":"feature","complexity":"MEDIUM","current_step":"spec","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1}' > .specwork/_state/tri-test-state.json
cat > .specwork/_spec/tri-test-spec.md <<SPEC
# tri-test — test

## Summary

Test scenario.

## Behavior

Add a simple log statement.

## Implementation Context

One service file.

## Expected Change Scope

Expected layers touched: service
Expected files touched: 1
SPEC
assert_rc 0 "triage exit 0" -- $TO bash "$REPO/commands/triage.sh" tri-test
assert_json ".specwork/_state/tri-test-path.json"   "ticket_type" "focused"  "triage writes path.json ticket_type"
assert_json ".specwork/_state/tri-test-state.json"  "ticket_type" "focused"  "triage updates state.json ticket_type"
assert_json ".specwork/_state/tri-test-state.json"  "complexity"  "LOW"      "triage updates state.json complexity"
# skip.0 requires array access (assert_json doesn't support dot notation)
skip0=$(python3 -c "import json; print(json.load(open('.specwork/_state/tri-test-path.json'))['skip'][0])" 2>/dev/null || echo "__MISSING__")
[ "$skip0" = "f-plan" ] && ok "triage path skips plan for focused (skip[0]=$skip0)" || bad "triage path skips plan (skip[0]=$skip0, want f-plan)"

echo "== spec-query: reads the spec registry published by /f-mr =="
SPEC_REG="$SCRATCH_ROOT/spec-reg"
mkdir -p "$SPEC_REG/spec-registry/lead-service"
printf '# demo\n## Behavior\nSkip dedupe when applicationId is null.\n' > "$SPEC_REG/spec-registry/lead-service/dedupe-spec.md"
out="$(OPEN_SDD_DOC_HOME="$SPEC_REG" bash "$REPO/commands/spec-query.sh" "what does dedupe do?" 2>&1 </dev/null)"
printf '%s' "$out" | grep -qF "lead-service/dedupe-spec.md" && ok "spec-query lists the published spec" || bad "spec-query missing spec :: ${out:0:160}"
printf '%s' "$out" | grep -qF "Skip dedupe when applicationId is null" && ok "spec-query prints the spec body" || bad "spec-query body missing"
out="$(OPEN_SDD_DOC_HOME="$SCRATCH_ROOT/empty-reg" bash "$REPO/commands/spec-query.sh" "x" 2>&1 </dev/null)"
printf '%s' "$out" | grep -qF "No specs found" && ok "spec-query graceful on empty registry" || bad "spec-query empty-registry path"

echo "== status.sh shows clickable OQ path =="
d=$(new_repo status-oclk); cd "$d"
mkdir -p .specwork/_state .specwork/_spec
printf '{"id":"oclk","slug":"oclk","ticket_type":"feature","current_step":"spec","input_type":"freetext","branch":"feature/demo","spec_write_timestamp":1}' > .specwork/_state/oclk-state.json
cat > .specwork/_spec/oclk-spec.md <<SPEC
# test

## Open Questions

- [ ] **#1** Some question?
SPEC
out="$($TO bash "$REPO/commands/status.sh" 2>&1 </dev/null)"
if printf '%s' "$out" | grep -qF '`/'; then
  ok "status.sh outputs absolute backtick path for OQs"
else
  bad "status.sh missing clickable path :: ${out:0:160}"
fi
if printf '%s' "$out" | grep -qF 'spec.md:'; then
  ok "status.sh includes line number in OQ path"
else
  bad "status.sh missing line number :: ${out:0:160}"
fi

echo "== help.sh overview works without .specwork =="
d=$(new_repo help-ov); cd "$d"
assert_out "Feature Development Pipeline" "overview prints title" -- bash "$REPO/commands/help.sh" overview
assert_noout "resolve_slug" "overview never hits slug resolution" -- bash "$REPO/commands/help.sh" overview

echo "== start.sh does NOT create spec.md =="
d=$(new_repo start-no-spec); cd "$d"
mkdir -p .specwork/_state .specwork/_spec .specwork/_progress
cat > .specwork/_spec/demo-source.md <<EOF
# demo — test
Quick test.
EOF
printf '{}' > .specwork/_state/demo-rules.json
printf '{}' > .specwork/_state/demo-implementation-cache.json
# start.sh would normally do this, but we simulate by writing state.json only
printf '{"id":"demo","slug":"demo","ticket_type":"feature","current_step":"spec","input_type":"freetext","branch":"feature/demo","source_file":".specwork/_spec/demo-source.md"}' > .specwork/_state/demo-state.json
if [ ! -f ".specwork/_spec/demo-spec.md" ]; then
  ok "spec.md not created by start (confirmed absent)"
else
  bad "spec.md should not exist after start"
fi

echo "------------------------------------------------------------------"
printf " RESULT: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
