#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fmt_dim()  { printf '\033[2m%s\033[0m\n' "$1"; }

# ---- resolve context --------------------------------------------------------

RECHECK=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --recheck) RECHECK=true ;;
    *) ARGS+=("$arg") ;;
  esac
done

SLUG=$(resolve_slug 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
STACK=$(detect_stack)

[ -n "$SLUG" ] && echo "Slug: $SLUG"
echo "Stack: $STACK"
echo "Branch: $BRANCH"
echo "Mode: $([ "$RECHECK" = true ] && echo 'recheck' || echo 'normal')"

# ---- collect diff -----------------------------------------------------------

DIFF=$(git diff HEAD --unified=5 2>/dev/null || true)

if [ -z "$DIFF" ]; then
  die "No diff found — nothing to review.

Make sure there are staged or unstaged changes on the current branch."
fi

# ---- test coverage check ----------------------------------------------------

COVERAGE_SECTION=""

java_coverage() {
  local prod_files new_files modified_gaps new_gaps
  prod_files=$(echo "$DIFF" | grep '^diff --git a/' | sed -E 's|^diff --git a/||;s| b/.*$||' \
    | grep '^src/main/java/' | grep '\.java$' \
    | grep -vE '(Test|IT|IntTest|IntegrationTest)\.java$' || true)

  new_files=""
  modified_gaps=""
  new_gaps=""

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base=$(basename "$f" .java)
    dir=$(dirname "$f" | sed 's|^src/main/java|src/test/java|')
    it_dir=$(dirname "$f" | sed 's|^src/main/java|src/intTest/java|')

    # Skip DTOs, Configs, Properties, constants
    if echo "$base" | grep -qE '(Config|Properties|Constants?)' || \
       echo "$base" | grep -qi 'dto'; then
      continue
    fi

    # Check if new or modified
    if git cat-file -e "HEAD:$f" 2>/dev/null; then
      # Modified — check if test is also in diff
      test_in_diff=""
      for suffix in "Test" "IntTest" "IT" "IntegrationTest"; do
        candidate="${dir}/${base}${suffix}.java"
        candidate_it="${it_dir}/${base}${suffix}.java"
        if echo "$DIFF" | grep -qE "diff --git a/(${candidate}|${candidate_it}) "; then
          test_in_diff="yes"
          break
        fi
      done
      [ -z "$test_in_diff" ] && modified_gaps="${modified_gaps}  ${f} → ${base}Test not in diff"$'\n'
    else
      # New — check if any test exists at all
      test_exists=""
      for suffix in "Test" "IntTest" "IT" "IntegrationTest"; do
        for d in "$dir" "$it_dir"; do
          [ -f "${d}/${base}${suffix}.java" ] && test_exists="yes" && break
        done
        [ -n "$test_exists" ] && break
      done
      # Also check if test is in the diff
      for suffix in "Test" "IntTest" "IT" "IntegrationTest"; do
        candidate="${dir}/${base}${suffix}.java"
        candidate_it="${it_dir}/${base}${suffix}.java"
        if echo "$DIFF" | grep -qE "diff --git a/(${candidate}|${candidate_it}) "; then
          test_exists="yes"
          break
        fi
      done
      [ -z "$test_exists" ] && new_gaps="${new_gaps}  ${f} → no test found in diff"$'\n'
    fi
  done <<< "$prod_files"

  OUTPUT=""
  [ -n "$modified_gaps" ] && OUTPUT+="⚠  Modified classes without updated tests:"$'\n'"${modified_gaps}"$'\n'
  [ -n "$new_gaps" ] && OUTPUT+="⚠  New classes without any test:"$'\n'"${new_gaps}"$'\n'
  echo "$OUTPUT"
}

frontend_coverage() {
  local prod_files new_files modified_gaps new_gaps
  prod_files=$(echo "$DIFF" | grep '^diff --git a/' | sed -E 's|^diff --git a/||;s| b/.*$||' \
    | grep -E '\.ts$|\.tsx$' \
    | grep -vE '\.test\.ts|\.test\.tsx|\.d\.ts|\.stories\.tsx|\.spec\.ts' || true)

  modified_gaps=""
  new_gaps=""

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base=$(basename "$f" | sed 's/\.[^.]*$//')
    dir=$(dirname "$f")

    # Skip type-only files, pure style, constants, index re-exports
    if echo "$base" | grep -qiE '(constants?|styles?|index)$'; then
      continue
    fi

    test_in_diff=""
    for ext in "test.ts" "test.tsx" "spec.ts" "spec.tsx"; do
      candidate="${dir}/${base}.${ext}"
      if echo "$DIFF" | grep -qF "diff --git a/$candidate "; then
        test_in_diff="yes"
        break
      fi
      candidate_alt="${dir}/__tests__/${base}.${ext}"
      if echo "$DIFF" | grep -qF "diff --git a/$candidate_alt "; then
        test_in_diff="yes"
        break
      fi
    done

    if git cat-file -e "HEAD:$f" 2>/dev/null; then
      [ -z "$test_in_diff" ] && modified_gaps="${modified_gaps}  ${f} → test not in diff"$'\n'
    else
      test_exists=""
      for ext in "test.ts" "test.tsx" "spec.ts" "spec.tsx"; do
        [ -f "${dir}/${base}.${ext}" ] && test_exists="yes" && break
        [ -f "${dir}/__tests__/${base}.${ext}" ] && test_exists="yes" && break
      done
      if [ -z "$test_exists" ] && [ -z "$test_in_diff" ]; then
        new_gaps="${new_gaps}  ${f} → no test found"$'\n'
      fi
    fi
  done <<< "$prod_files"

  OUTPUT=""
  [ -n "$modified_gaps" ] && OUTPUT+="⚠  Modified classes without updated tests:"$'\n'"${modified_gaps}"$'\n'
  [ -n "$new_gaps" ] && OUTPUT+="⚠  New classes without any test:"$'\n'"${new_gaps}"$'\n'
  echo "$OUTPUT"
}

case "$STACK" in
  java)  COVERAGE_SECTION=$(java_coverage) ;;
  node)  COVERAGE_SECTION=$(frontend_coverage) ;;
esac

# ---- pack hints detection ---------------------------------------------------

PACK_HINTS=""

if [ "$STACK" = "java" ]; then
  if echo "$DIFF" | grep -qE '@Entity\b|@Repository\b|JOIN FETCH|@EntityGraph|@Transactional\b|@Query\b'; then
    PACK_HINTS+="- Diff touches \`@Entity\` / \`@Repository\` — consider JPA patterns review (N+1, fetch strategies, query parameterization)."$'\n'
  fi
  if echo "$DIFF" | grep -qE '@Async\b|CompletableFuture|synchronized\b|volatile\b|ExecutorService|Thread\.ofVirtual'; then
    PACK_HINTS+="- Diff touches \`@Async\` / virtual threads — consider concurrency review for thread safety and modern patterns."$'\n'
  fi
  if echo "$DIFF" | grep -qE '@RestController|@RequestMapping|@(Get|Post|Put|Patch|Delete)Mapping'; then
    PACK_HINTS+="- Diff touches REST controllers — consider API contract review for HTTP semantics, versioning, and request validation."$'\n'
  fi
  if echo "$DIFF" | grep -qE 'org\.slf4j|@Slf4j|MDC\.|logback\b|feign\.client\.config'; then
    PACK_HINTS+="- Diff touches logging — consider logging patterns review for structured logging, PII redaction, and Feign DEBUG hygiene."$'\n'
  fi
fi

# ---- write report -----------------------------------------------------------

REVIEW_DIR=".specwork/_review"
mkdir -p "$REVIEW_DIR"
REVIEW_FILE="${REVIEW_DIR}/${SLUG}-code-review.md"

if [ "$RECHECK" = true ] && [ -f "$REVIEW_FILE" ]; then
  # Read previous report for recheck context
  PREV_REPORT=$(cat "$REVIEW_FILE")
else
  PREV_REPORT=""
fi

{
  echo "# Code Review: ${SLUG}"
  echo ""
  echo "> Generated by open-sdd review.sh"
  echo "> Stack: $STACK"
  echo "> Branch: $BRANCH"
  echo "> Mode: $([ "$RECHECK" = true ] && echo 'recheck' || echo 'normal')"
  echo ""

  if [ "$RECHECK" = true ]; then
    echo "## Verdict"
    echo "<!-- Update after review -->"
    echo ""
    echo "## Resolved Findings"
    echo "<!-- List findings from previous report that are now fixed -->"
    echo ""
    echo "## Still Open"
    echo "<!-- List findings from previous report still present in diff -->"
    echo ""
    echo "## New Findings"
    echo "<!-- List findings in current diff that were not in previous report -->"
  else
    echo "## Verdict"
    echo "PASS | PASS WITH WARNINGS | FAIL"
    echo ""
    echo "## Summary"
    echo "- up to 8 bullets"
    echo ""

    if [ -n "$COVERAGE_SECTION" ]; then
      echo "## Test Coverage"
      echo "$COVERAGE_SECTION"
      echo ""
    fi

    echo "## Security Findings"
    echo "| ID | Severity | File:Line | Finding |"
    echo "|----|----------|-----------|---------|"
    echo ""
    echo "## Quality Findings"
    echo "| ID | Severity | File:Line | Finding |"
    echo "|----|----------|-----------|---------|"
    echo ""
    echo "## Action Plan"
    echo "1. [ ] F-001 — ..."
    echo "2. [ ] F-002 — ..."
    echo ""
    echo "## Questions / Uncertainties"
    echo "- ..."
  fi

  echo ""
  if [ -n "$PACK_HINTS" ]; then
    echo "## Suggested Follow-ups"
    echo "$PACK_HINTS"
  fi
} > "$REVIEW_FILE"

echo "Report written to $REVIEW_FILE"
echo ""

# ---- print instructions -----------------------------------------------------

echo "==================================================="
echo " CODE REVIEW SESSION"
echo "==================================================="
echo ""
fmt_bold "Context"
echo "  Stack:   $STACK"
echo "  Branch:  $BRANCH"
echo "  Slug:    ${SLUG:-(no pipeline)}"
echo "  Report:  $REVIEW_FILE"
echo "  Mode:    $([ "$RECHECK" = true ] && echo 'recheck — compare against previous report' || echo 'normal — first-pass review')"
echo ""

if [ -n "$COVERAGE_SECTION" ]; then
  echo "==================================================="
  echo " TEST COVERAGE GAPS"
  echo "==================================================="
  echo "$COVERAGE_SECTION"
  echo ""
fi

if [ "$RECHECK" = true ] && [ -n "$PREV_REPORT" ]; then
  echo "Previous report exists at $REVIEW_FILE"
  echo "Read it, then compare the current diff against previous findings."
  echo ""
fi

cat <<INSTRUCTIONS

===================================================
 REVIEW INSTRUCTIONS
===================================================

Review only the code in the diff below. Keep findings specific, ranked,
and minimal. Do not suggest formatting-only changes unless they fix a
cited finding.

Focus areas:

| Area | What to check |
|------|---------------|
| Security | Injection, auth bypass, data exposure, hardcoded secrets |
| Quality | Error handling, edge cases, null safety, performance |
| Testing | Missing test coverage for new/modified behavior |
| Architecture | Layering violations, coupling, cohesion |

EVIDENCE-BASED: Each finding must cite the exact file:line and explain
why it matters. No vague complaints.

After reviewing, update the report file at $REVIEW_FILE with:
- Verdict (PASS / PASS WITH WARNINGS / FAIL)
- Summary (up to 8 bullets)
- Findings tables with ID, Severity, File:Line, Finding
- Action Plan (numbered checklist)
- Questions / Uncertainties

Do NOT edit any source files until the user approves the action plan.

INSTRUCTIONS

# ---- print stack routing -----------------------------------------------------

case "$STACK" in
  java)
    echo "Stack routing: Java"
    echo "  Focus: security (Spring Boot), quality (error handling, N+1, transactions)"
    echo ""
    ;;
  node)
    echo "Stack routing: Frontend"
    echo "  Focus: quality (React/Vue patterns), a11y, test coverage"
    echo ""
    ;;
  *)
    echo "Stack routing: Unknown"
    echo "  Focus: generic quality review"
    echo ""
    ;;
esac

# ---- print pack hints -------------------------------------------------------

if [ -n "$PACK_HINTS" ]; then
  echo "==================================================="
  echo " SUGGESTED FOLLOW-UPS"
  echo "==================================================="
  echo "$PACK_HINTS"
  echo ""
  echo "These are deeper standalone reviews the user can opt into."
  echo "Do NOT load them into this review session."
  echo ""
fi

# ---- print diff -------------------------------------------------------------

echo "==================================================="
echo " DIFF"
echo "==================================================="
echo ""
echo "$DIFF"
echo ""
echo "==================================================="
echo " End of diff"
echo "==================================================="
echo ""
echo "Review complete? Update $REVIEW_FILE and show the report."
echo "Then ask the user for approval before making changes."
