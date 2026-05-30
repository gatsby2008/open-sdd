#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }

source "$LIB_DIR/gates.sh"

# ---- state ------------------------------------------------------------------

SLUG=""
STACK=""
SPEC_FILE=""

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
fmt_dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

# ---- resolve context (pipeline required) ------------------------------------

SLUG=$(resolve_slug) || die "No pipeline found. Run /f-start first — test-design runs inside a pipeline."
[ -f ".specwork/_state/${SLUG}-state.json" ] || die "No pipeline state for '$SLUG'. Run /f-start first."
STACK=$(detect_stack)
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
echo "Stack: $STACK"
echo "Slug: $SLUG"

# Artifact gates only — /f-test-design is re-runnable. It is an optional
# step regardless of flow; the spec/diff are the inputs and the design file
# is the output.

# ---- detect changed files ---------------------------------------------------

CHANGED_FILES=$(git diff --name-only --diff-filter=ACMRT 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo ""
  echo "No implementation changes detected on this branch."
  echo "Run /f-implement first, then re-run /f-test-design."
  exit 1
fi

echo ""
fmt_bold "Changed files:"
echo "$CHANGED_FILES"
echo ""

# ---- determine test patterns from stack -------------------------------------

case "$STACK" in
  java)
    UNIT_PATTERN="*Test.java (@ExtendWith(MockitoExtension))"
    INT_PATTERN="*IntTest.java / *IT.java (@WebMvcTest / @DataJpaTest)"
    E2E_PATTERN="—"
    FRAMEWORK="JUnit + Mockito"
    ;;
  node)
    UNIT_PATTERN="*.test.ts (Jest/Vitest + MSW)"
    INT_PATTERN="*.test.tsx (RTL + MSW, full component tree)"
    E2E_PATTERN="Playwright/Cypress skeleton"
    FRAMEWORK="Jest/Vitest + RTL + Playwright"
    ;;
  frontend)
    UNIT_PATTERN="*.test.ts (Jest/Vitest)"
    INT_PATTERN="*.test.tsx (RTL + MSW, full component tree)"
    E2E_PATTERN="Playwright/Cypress skeleton"
    FRAMEWORK="Jest/Vitest + RTL + Playwright + Storybook"
    ;;
  *)
    UNIT_PATTERN="Standard unit tests"
    INT_PATTERN="Standard integration tests"
    E2E_PATTERN="E2E tests"
    FRAMEWORK="auto-detected"
    ;;
esac

# ---- detect endpoints / listener / jobs for integration coverage ------------

INT_CANDIDATES=$(python3 - "$CHANGED_FILES" <<'PY' 2>/dev/null || true
import sys, re
files = sys.argv[1].splitlines()
for f in files:
    lower = f.lower()
    if any(kw in lower for kw in ["controller", "resource", "endpoint", "listener",
                                   "consumer", "handler", "job", "scheduler",
                                   "route", "page", "screen", "component"]):
        print(f)
PY
)

# ---- write the test-design artifact -----------------------------------------
# test-impl depends on this file: its existence is the proof test-design ran.
# The script seeds the header + context; the design itself is filled in below.

TEST_DIR=".specwork/_test"
mkdir -p "$TEST_DIR"
TEST_DESIGN_FILE="$TEST_DIR/${SLUG}-test-design.md"
{
  echo "# Test Design — $SLUG"
  echo ""
  echo "_Seeded by test-design. Fill in the designed cases under \"Designed test cases\"._"
  echo "_test-impl reads this file and refuses to run if it is missing._"
  echo ""
  echo "## Changed files"
  echo '```'
  echo "$CHANGED_FILES"
  echo '```'
  if [ -n "$INT_CANDIDATES" ]; then
    echo ""
    echo "## Integration entry points"
    echo '```'
    echo "$INT_CANDIDATES"
    echo '```'
  fi
  echo ""
  echo "## Designed test cases"
  echo ""
  echo "<!-- Group by unit / integration / edge cases / missing coverage, with"
  echo "     concrete class/component names from the diff. -->"
} > "$TEST_DESIGN_FILE"
echo "Wrote $TEST_DESIGN_FILE"

# ---- print design instructions ----------------------------------------------

cat <<INSTRUCTIONS

===================================================
 TEST DESIGN SESSION
===================================================

You have loaded the optional test design step.
Analyze the code changes below and design test cases, then WRITE them into:

    $TEST_DESIGN_FILE

under the "## Designed test cases" heading. test-impl reads that file.

STACK:    $STACK
FRAMEWORK: $FRAMEWORK
SLUG:     $SLUG
${SPEC_FILE:+SPEC:     $SPEC_FILE}

===================================================

GROUP TEST CASES BY CATEGORY (unit / integration / edge cases / missing coverage)
with concrete class/component names extracted from the diff.

Required coverage: every design output must include at least one integration-level
scenario per touched endpoint, listener, scheduled job, or top-level component.
If the diff has no plausible integration entry point (pure helper, isolated library
code), call this out under *Missing Coverage* — silently omitting integration tests
is treated as a defect.

| Category | $STACK |
|----------|--------|
| Unit     | $UNIT_PATTERN |
| Integration | $INT_PATTERN |
| E2E      | $E2E_PATTERN |
| Framework | $FRAMEWORK |

INSTRUCTIONS

echo "Changed files:"
echo "$CHANGED_FILES"
echo ""

if [ -n "$INT_CANDIDATES" ]; then
  echo "Integration entry points detected:"
  echo "$INT_CANDIDATES"
  echo ""
fi

if [ -n "$SPEC_FILE" ] && [ -f "$SPEC_FILE" ]; then
  echo "====== SPEC ======"
  cat "$SPEC_FILE"
  echo ""
  echo "=================="
fi

cat <<INSTRUCTIONS


Next: run ./commands/test-impl.sh to implement the test files,
or skip straight to ./commands/commit.sh (test-impl is optional).
INSTRUCTIONS
