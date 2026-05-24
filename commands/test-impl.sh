#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
fmt_dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

# ---- support: dry-run mode --------------------------------------------------

DRY_RUN=false
if [ "${1:-}" = "list" ]; then
  DRY_RUN=true
fi

# ---- resolve context --------------------------------------------------------

SLUG=$(resolve_slug) || SLUG=""
STACK=$(detect_stack)
echo "Stack: $STACK"

if [ -n "$SLUG" ]; then
  STATE_FILE=".specwork/_state/${SLUG}-state.json"
  SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
  echo "Slug: $SLUG"
fi

# ---- detect changed source files --------------------------------------------

CHANGED_FILES=$(git diff --name-only --diff-filter=ACMRT 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo ""
  echo "No implementation changes detected on this branch."
  echo "Run ./commands/implement.sh first, then re-run ./commands/test-impl.sh."
  exit 1
fi

echo ""

# ---- map changed files to expected test paths -------------------------------

python3 - "$CHANGED_FILES" "$STACK" <<'PY' 2>/dev/null || true
import sys, os, re

files = sys.argv[1].splitlines()
stack = sys.argv[2]

def resolve_test_path(src_path, stack):
    """Resolve a source file to its corresponding test file path."""
    if stack == "java":
        # src/main/java/com/example/Foo.java → src/test/java/com/example/FooTest.java
        # src/main/java/com/example/Foo.java → src/intTest/java/com/example/FooIntTest.java
        m = re.match(r"src/main/java/(.+)\.java$", src_path)
        if not m:
            return []
        pkg_path = m.group(1)
        class_name = pkg_path.split("/")[-1]
        pkg_dir = "/".join(pkg_path.split("/")[:-1])
        results = []
        for test_root in ["src/test/java", "src/intTest/java", "src/integrationTest/java"]:
            for suffix in ["Test", "IntTest", "IT", "Tests"]:
                candidate = f"{test_root}/{pkg_dir}/{class_name}{suffix}.java"
                results.append(candidate)
        return results
    elif stack == "node":
        # src/Foo.ts → src/__tests__/Foo.test.ts, src/Foo.test.ts, etc.
        for ext in [".ts", ".tsx", ".js", ".jsx"]:
            if src_path.endswith(ext):
                base = src_path[: -len(ext)]
                candidates = [
                    src_path.replace(ext, ".test" + ext),
                    src_path.replace(ext, ".spec" + ext),
                    os.path.join(os.path.dirname(src_path), "__tests__",
                                 os.path.basename(base) + ".test" + ext),
                ]
                return candidates
    return []

def find_existing_tests(src_path, stack):
    candidates = resolve_test_path(src_path, stack)
    return [c for c in candidates if os.path.isfile(c)]

all_planned = []
new_tests = []
existing_tests = []

for sf in files:
    if stack == "java" and not sf.endswith(".java"):
        continue
    if stack == "node" and not any(sf.endswith(e) for e in [".ts", ".tsx", ".js", ".jsx"]):
        continue
    if "/test/" in sf or "/intTest/" in sf or "/integrationTest/" in sf or "/__tests__/" in sf:
        continue  # skip test files themselves

    existing = find_existing_tests(sf, stack)
    if existing:
        for t in existing:
            if t not in existing_tests:
                existing_tests.append(t)
    else:
        candidates = resolve_test_path(sf, stack)
        for c in candidates:
            if c not in new_tests:
                new_tests.append(c)

print(f"Existing test files to update: {len(existing_tests)}")
for t in existing_tests:
    print(f"  UPDATE: {t}")

print(f"New test files to create: {len(new_tests)}")
for t in new_tests:
    print(f"  CREATE: {t}")
PY

echo ""

# ---- dry-run: list mode -----------------------------------------------------

if $DRY_RUN; then
  echo "Dry-run mode — no files written."
  echo "Re-run without 'list' to implement."
  exit 0
fi

# ---- print implementation instructions --------------------------------------

cat <<INSTRUCTIONS

===================================================
 TEST IMPLEMENTATION SESSION
===================================================

You have loaded the optional test implementation step.
Create test files for the changed source files listed below.

STACK:    $STACK
SLUG:     ${SLUG:-"(no pipeline)"}
${SPEC_FILE:+SPEC:     $SPEC_FILE}

===================================================

HARD RULES — Behavior-Based Assertions

Generated tests MUST verify behavior, not just that code doesn't explode.
Before writing any test method, read the implementation file and extract:

| Facet | What to extract | Asserted with |
|-------|-----------------|---------------|
| Return value | Type, fields populated, derived computations | \`assertThat(result.getStatus()).isEqualTo(OPEN)\` — concrete value |
| Persistence | \`repository.save(...)\` — what entity, which fields | \`verify(repository).save(argThat(c -> c.getName().equals("X")))\` |
| Events / messages | \`publishEvent(...)\`, \`sqsTemplate.send(...)\` | \`verify(publisher).publishEvent(any(ConsentCreatedEvent.class))\` |
| Outbound calls | Feign / RestTemplate invocations | \`verify(feignClient).fetchUser(eq(userId))\` |
| Exceptions | Specific exception class thrown | \`assertThatThrownBy(...).isInstanceOf(NotFoundException.class)\` |

FORBIDDEN patterns (defects — pass even when behavior is wrong):
  \`assertThat(result).isNotNull()\`               — says nothing about behavior
  \`verify(repository).save(any())\`               — doesn't validate WHAT was saved
  \`assertThat(result.getItems()).isNotEmpty()\`    — doesn't check content

A non-null check is acceptable ONLY as a precondition before a content assertion.

| Stack | Unit tests | Integration tests |
|-------|-----------|-------------------|
| Java | \`*Test.java\` (@ExtendWith(MockitoExtension)) | \`*IntTest.java\` / \`*IT.java\` (@WebMvcTest / @DataJpaTest) |
| Frontend | \`*.test.ts\` (Jest/Vitest) | \`*.test.tsx\` (RTL + MSW) |

Next: run ./commands/commit.sh to stage and commit the test files.
INSTRUCTIONS
