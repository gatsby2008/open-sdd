#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- state ------------------------------------------------------------------

SLUG=""
STACK=""
SPEC_FILE=""

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
fmt_dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

# ---- resolve context --------------------------------------------------------

SLUG=$(resolve_slug) || SLUG=""
STACK=$(detect_stack)
echo "Stack: $STACK"

if [ -n "$SLUG" ]; then
  SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
  echo "Slug: $SLUG"
fi

# ---- detect changed files ---------------------------------------------------

CHANGED_FILES=$(git diff --name-only --diff-filter=ACMRT 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo ""
  echo "No implementation changes detected on this branch."
  echo "Run ./commands/implement.sh first, then re-run ./commands/test-design.sh."
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

# ---- print design instructions ----------------------------------------------

cat <<INSTRUCTIONS

===================================================
 TEST DESIGN SESSION
===================================================

You have loaded the optional test design step.
Analyze the code changes below and design test cases.

STACK:    $STACK
FRAMEWORK: $FRAMEWORK
SLUG:     ${SLUG:-"(no pipeline)"}
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


Next: run ./commands/test-impl.sh to implement the test files.
INSTRUCTIONS
