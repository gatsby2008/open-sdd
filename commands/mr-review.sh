#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fmt_dim()  { printf '\033[2m%s\033[0m\n' "$1"; }

cleanup() {
  rm -f /tmp/f-mr-review-mr.json /tmp/f-mr-review.diff
}
trap cleanup EXIT

# ---- provider detection ------------------------------------------------------

detect_provider() {
  local provider="${OPEN_SDD_MR_PROVIDER:-}"
  if [ -z "$provider" ]; then
    local origin_url
    origin_url=$(git remote get-url origin 2>/dev/null || echo "")
    case "$origin_url" in
      *github.com*) provider="github" ;;
      *gitlab*)     provider="gitlab" ;;
      *)            provider="github" ;;  # default when ambiguous
    esac
  fi
  echo "$provider"
}

# ---- arg parsing ------------------------------------------------------------

ARG="${1:-}"
[ -z "$ARG" ] && die "Usage: ./mr-review.sh <branch | mr-url | pr-url | iid>

  ./mr-review.sh feature/MYYES-15518
  ./mr-review.sh https://gitlab.com/grp/proj/-/merge_requests/123
  ./mr-review.sh https://github.com/owner/repo/pull/123
  ./mr-review.sh 123"

# ---- classify arg -----------------------------------------------------------

MODE="branch"
MR_ID=""
PROVIDER=""

if echo "$ARG" | grep -q '/-/merge_requests/'; then
  MODE="mr"
  PROVIDER="gitlab"
  MR_ID="$ARG"
elif echo "$ARG" | grep -qE 'github\.com.*/pull/[0-9]+'; then
  MODE="mr"
  PROVIDER="github"
  MR_ID="$(echo "$ARG" | grep -oE '[0-9]+$')"
elif echo "$ARG" | grep -qE '^!?[0-9]+$'; then
  MODE="mr"
  PROVIDER="$(detect_provider)"
  MR_ID="$(echo "$ARG" | sed 's/^!//')"
fi

# ---- resolve diff -----------------------------------------------------------

DIFF=""

if [ "$MODE" = "mr" ]; then
  if [ "$PROVIDER" = "github" ]; then
    command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for GitHub PR review mode. Install: https://cli.github.com/"
    gh auth status >/dev/null 2>&1 || die "Not authenticated with GitHub CLI. Run: gh auth login"

    gh pr view "$MR_ID" --json headRefName,baseRefName,title,number > /tmp/f-mr-review-mr.json 2>/dev/null || \
      die "Failed to fetch PR info. Check that 'gh auth status' passes and the PR exists."

    IID=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['number'])" 2>/dev/null || echo "")
    SOURCE_BRANCH=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['headRefName'])" 2>/dev/null || echo "")
    TARGET_BRANCH=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['baseRefName'])" 2>/dev/null || echo "")
    MR_TITLE=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['title'])" 2>/dev/null || echo "")

    [ -z "$IID" ] && die "Could not parse PR info."

    echo "PR #$IID — $MR_TITLE"
    echo "Source: $SOURCE_BRANCH → Target: $TARGET_BRANCH"
    echo ""

    gh pr diff "$IID" --color never > /tmp/f-mr-review.diff 2>/dev/null || true

    if [ ! -s /tmp/f-mr-review.diff ]; then
      echo "gh pr diff failed or returned empty — falling back to branch diff."
      if [ -n "$SOURCE_BRANCH" ] && [ -n "$TARGET_BRANCH" ]; then
        git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
        git fetch origin "$SOURCE_BRANCH" --quiet 2>/dev/null || true
        git diff "origin/$TARGET_BRANCH...origin/$SOURCE_BRANCH" > /tmp/f-mr-review.diff 2>/dev/null || true
      fi
    fi

    SLUG="pr-${IID}"
    DIFF_FILE="/tmp/f-mr-review.diff"
  else
    command -v glab >/dev/null 2>&1 || die "glab is required for GitLab MR review mode. Install it ('brew install glab' or 'glab auth login') and authenticate, or pass a branch name instead."

    glab mr view "$MR_ID" -F json > /tmp/f-mr-review-mr.json 2>/dev/null || \
      die "Failed to fetch MR info. Check that 'glab auth status' passes and the MR exists."

    IID=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['iid'])" 2>/dev/null || echo "")
    SOURCE_BRANCH=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['source_branch'])" 2>/dev/null || echo "")
    TARGET_BRANCH=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['target_branch'])" 2>/dev/null || echo "")
    MR_TITLE=$(python3 -c "import json; print(json.load(open('/tmp/f-mr-review-mr.json'))['title'])" 2>/dev/null || echo "")

    [ -z "$IID" ] && die "Could not parse MR info."

    echo "MR #$IID — $MR_TITLE"
    echo "Source: $SOURCE_BRANCH → Target: $TARGET_BRANCH"
    echo ""

    glab mr diff "$IID" --color never > /tmp/f-mr-review.diff 2>/dev/null || true

    if [ ! -s /tmp/f-mr-review.diff ]; then
      echo "glab mr diff failed or returned empty — falling back to branch diff."
      if [ -n "$SOURCE_BRANCH" ] && [ -n "$TARGET_BRANCH" ]; then
        git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
        git fetch origin "$SOURCE_BRANCH" --quiet 2>/dev/null || true
        git diff "origin/$TARGET_BRANCH...origin/$SOURCE_BRANCH" > /tmp/f-mr-review.diff 2>/dev/null || true
      fi
    fi

    SLUG="mr-${IID}"
    DIFF_FILE="/tmp/f-mr-review.diff"
  fi
else
  BRANCH="$ARG"
  echo "Branch: $BRANCH"
  echo ""

  git fetch origin "$BRANCH" --quiet 2>/dev/null || \
    die "Branch '$BRANCH' not found on origin."

  BASE="main"

  if ! git ls-remote --exit-code --heads origin "$BASE" >/dev/null 2>&1; then
    if [ "$BASE" = "main" ]; then
      OTHER="development"
    else
      OTHER="main"
    fi
    if git ls-remote --exit-code --heads origin "$OTHER" >/dev/null 2>&1; then
      BASE="$OTHER"
    else
      die "Could not detect base branch. Neither '$BASE' nor '$OTHER' exist on origin."
    fi
  fi

  git fetch origin "$BASE" --quiet 2>/dev/null || true
  git diff "origin/$BASE...origin/$BRANCH" > /tmp/f-mr-review.diff 2>/dev/null || true

  SLUG="$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9_-]/-/g')"
  DIFF_FILE="/tmp/f-mr-review.diff"
fi

DIFF=$(cat "$DIFF_FILE" 2>/dev/null || true)

if [ -z "$DIFF" ]; then
  die "Nothing to review — the diff between the branches is empty."
fi

# ---- detect stack from diff paths -------------------------------------------

detect_stack_from_diff() {
  local diff_content="$1"

  if echo "$diff_content" | grep -qE '^diff --git a/.*\.java' && \
     (echo "$diff_content" | grep -qE '^diff --git a/(build\.gradle|pom\.xml)' || \
      echo "$diff_content" | grep -qE '^\+.*public (class|interface|enum|@interface)'); then
    echo "java"
  elif echo "$diff_content" | grep -qE '^diff --git a/.*\.(tsx?|jsx?)' && \
       (echo "$diff_content" | grep -qE '^diff --git a/(package\.json|vite\.config|next\.config|angular\.json|nuxt\.config|svelte\.config)'); then
    echo "frontend"
  elif echo "$diff_content" | grep -qE '^diff --git a/.*\.(ts|js|mjs)'; then
    echo "node"
  else
    echo "unknown"
  fi
}

STACK=$(detect_stack_from_diff "$DIFF")
echo "Stack: $STACK"
echo ""

# ---- test coverage check (from diff) ----------------------------------------

COVERAGE_SECTION=""

coverage_from_diff() {
  local diff_content="$1"
  local stack="$2"

  local prod_files
  if [ "$stack" = "java" ]; then
    prod_files=$(echo "$diff_content" | grep '^diff --git b/' | sed 's|^diff --git b/||' \
      | grep -v 'dev/null' \
      | grep '^src/main/java/' | grep '\.java$' \
      | grep -vE '(Test|IT|IntTest|IntegrationTest)\.java$' || true)
  else
    prod_files=$(echo "$diff_content" | grep '^diff --git b/' | sed 's|^diff --git b/||' \
      | grep -v 'dev/null' \
      | grep -E '\.ts$|\.tsx$' \
      | grep -vE '\.test\.ts|\.test\.tsx|\.d\.ts|\.stories\.tsx|\.spec\.ts' || true)
  fi

  local gaps=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base=$(basename "$f" | sed 's/\.[^.]*$//')

    # Skip known non-production files
    if [ "$stack" = "java" ]; then
      if echo "$base" | grep -qE '(Config|Properties|Constants?)' || echo "$base" | grep -qi 'dto'; then
        continue
      fi
    else
      if echo "$base" | grep -qiE '(constants?|styles?|index)$'; then
        continue
      fi
    fi

    # Resolve expected test path
    local test_paths=()
    if [ "$stack" = "java" ]; then
      local dir=$(dirname "$f" | sed 's|^src/main/java|src/test/java|')
      test_paths+=("${dir}/${base}Test.java" "${dir}/${base}IT.java" "${dir}/${base}IntTest.java" "${dir}/${base}IntegrationTest.java")
      local it_dir=$(dirname "$f" | sed 's|^src/main/java|src/intTest/java|')
      test_paths+=("${it_dir}/${base}Test.java" "${it_dir}/${base}IT.java")
    else
      local dir=$(dirname "$f")
      test_paths+=("${dir}/${base}.test.ts" "${dir}/${base}.test.tsx" "${dir}/${base}.spec.ts" "${dir}/${base}.spec.tsx")
      test_paths+=("${dir}/__tests__/${base}.test.ts" "${dir}/__tests__/${base}.test.tsx")
    fi

    local found=""
    for tp in "${test_paths[@]}"; do
      if echo "$diff_content" | grep -qF "diff --git b/$tp"; then
        found="yes"
        break
      fi
    done

    [ -z "$found" ] && gaps="${gaps}  ${f} → no test coverage in diff"$'\n'
  done <<< "$prod_files"

  [ -n "$gaps" ] && echo "⚠  Files without test coverage in diff:"$'\n'"${gaps}"
}

case "$STACK" in
  java)     COVERAGE_SECTION=$(coverage_from_diff "$DIFF" "java") ;;
  node)     COVERAGE_SECTION=$(coverage_from_diff "$DIFF" "node") ;;
  frontend) COVERAGE_SECTION=$(coverage_from_diff "$DIFF" "frontend") ;;
esac

# ---- pack hints detection (same as code-review.sh) --------------------------

PACK_HINTS=""

if [ "$STACK" = "java" ]; then
  if echo "$DIFF" | grep -qE '@Entity\b|@Repository\b|JOIN FETCH|@EntityGraph|@Transactional\b|@Query\b'; then
    PACK_HINTS+="- Diff touches JPA annotations — consider JPA patterns review (N+1, fetch strategies, query parameterization)."$'\n'
  fi
  if echo "$DIFF" | grep -qE '@Async\b|CompletableFuture|synchronized\b|volatile\b|ExecutorService|Thread\.ofVirtual'; then
    PACK_HINTS+="- Diff touches concurrency primitives — consider concurrency review for thread safety and modern patterns."$'\n'
  fi
  if echo "$DIFF" | grep -qE '@RestController|@RequestMapping|@(Get|Post|Put|Patch|Delete)Mapping'; then
    PACK_HINTS+="- Diff touches REST controllers — consider API contract review for HTTP semantics, versioning, and request validation."$'\n'
  fi
  if echo "$DIFF" | grep -qE 'org\.slf4j|@Slf4j|MDC\.|logback\b|feign\.client\.config'; then
    PACK_HINTS+="- Diff touches logging — consider logging patterns review for structured logging, PII redaction, and Feign DEBUG hygiene."$'\n'
  fi
elif [ "$STACK" = "frontend" ]; then
  if echo "$DIFF" | grep -qE 'useEffect|useLayoutEffect|componentDidMount|componentWillUnmount'; then
    PACK_HINTS+="- Diff touches lifecycle hooks — consider review of cleanup, dependency arrays, and memory leaks."$'\n'
  fi
  if echo "$DIFF" | grep -qE 'useState|useReducer|redux|zustand|context'; then
    PACK_HINTS+="- Diff touches state management — consider review of immutability, selector optimization, and re-render scope."$'\n'
  fi
  if echo "$DIFF" | grep -qE 'aria-|role=|tabIndex|keyboard|focus|screen.?reader'; then
    PACK_HINTS+="- Diff touches accessibility patterns — consider a11y review for ARIA and keyboard navigation."$'\n'
  fi
  if echo "$DIFF" | grep -qE 'Route|Router|useRouter|navigate|redirect'; then
    PACK_HINTS+="- Diff touches routing — consider review of navigation guards, side effects, and error states."$'\n'
  fi
  if echo "$DIFF" | grep -qE 'getServerSideProps|getStaticProps|getStaticPaths|useSWR|useQuery|useMutation'; then
    PACK_HINTS+="- Diff touches data fetching — consider review of caching, error handling, and loading states."$'\n'
  fi
fi

# ---- write report skeleton --------------------------------------------------

if [ -d ".specwork/_review" ]; then
  REVIEW_DIR=".specwork/_review"
  REVIEW_FILE="${REVIEW_DIR}/${SLUG}-peer-review.md"
else
  REVIEW_DIR="docs/review"
  mkdir -p "$REVIEW_DIR"
  REVIEW_FILE="${REVIEW_DIR}/${SLUG}-$(date +%Y%m%d).md"
fi

{
  echo "# Peer Review: ${SLUG}"
  echo ""
  echo "> Generated by open-sdd mr-review.sh"
  if [ "$MODE" = "mr" ]; then
    echo "> MR #${IID}: ${MR_TITLE:-}"
    echo "> Source: ${SOURCE_BRANCH:-} → Target: ${TARGET_BRANCH:-}"
  else
    echo "> Branch: ${ARG}"
    echo "> Base: ${BASE:-main}"
  fi
  echo "> Provider: ${PROVIDER:-git}"
  echo "> Stack: $STACK"
  echo ""

  echo "## Verdict"
  echo "PASS | PASS WITH WARNINGS | FAIL"
  echo ""

  echo "## Summary"
  echo "- up to 8 bullets"
  echo ""

  if [ -n "$COVERAGE_SECTION" ]; then
    echo "## Test Coverage"
    echo "⚠  Note: diff-based analysis — coverage gaps are advisory."
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
  echo ""
  echo "## Questions / Uncertainties"
  echo "- ..."
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
echo " PEER REVIEW SESSION"
echo "==================================================="
echo ""
fmt_bold "Context"
if [ "$MODE" = "mr" ]; then
  echo "  ${PROVIDER^^}:  #${IID} — ${MR_TITLE:-}"
  echo "  Branch:   ${SOURCE_BRANCH:-} → ${TARGET_BRANCH:-}"
else
  echo "  Branch:   ${ARG}"
  echo "  Base:     ${BASE:-main}"
fi
echo "  Stack:    $STACK
  Report:   $REVIEW_FILE"
echo "  Report:   $REVIEW_FILE"
echo ""

if [ -n "$COVERAGE_SECTION" ]; then
  echo "==================================================="
  echo " TEST COVERAGE GAPS"
  echo "==================================================="
  echo "$COVERAGE_SECTION"
  echo ""
fi

cat <<INSTRUCTIONS

===================================================
 REVIEW INSTRUCTIONS
===================================================

Review only the diff below. Keep findings specific, ranked,
and minimal. Do not suggest formatting-only changes.

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

Do NOT edit any source files — this is a read-only peer review.

INSTRUCTIONS

# ---- print stack routing ----------------------------------------------------

case "$STACK" in
  java)
    echo "Stack routing: Java"
    echo "  Focus: security (Spring Boot), quality (error handling, N+1, transactions)"
    echo ""
    ;;
  frontend)
    echo "Stack routing: Frontend"
    echo "  Focus: quality (React/Vue patterns), a11y, performance, state management"
    echo ""
    ;;
  node)
    echo "Stack routing: Node (backend)"
    echo "  Focus: security (Express/NestJS), error handling, type safety"
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
echo "Ask the user for approval before suggesting any fixes."
