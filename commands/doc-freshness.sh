#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }
warn() { echo "  [DRIFT] $*"; }
ok()   { echo "  [OK] $*"; }

PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR"

# ---- git checks ---------------------------------------------------------------

has_git=false
if git rev-parse --show-toplevel &>/dev/null; then
  has_git=true
  ROOT="$(git rev-parse --show-toplevel)"
  cd "$ROOT"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
  LAST_COMMIT=$(git log -1 --format='%ad' --date=short 2>/dev/null || echo "unknown")
else
  ROOT="$PROJECT_DIR"
  BRANCH="(no git)"
  LAST_COMMIT="unknown"
fi

echo "=== doc-freshness ==="
echo "Repo: $ROOT"
echo "Branch: $BRANCH"
echo "Last commit: $LAST_COMMIT"
echo ""

# ---- file structure checks ---------------------------------------------------

DRIFT_COUNT=0

echo "--- Cross-reference validity ---"
INDEX_FILES=0
if [ -f docs/index.md ]; then
  INDEX_FILES=$(grep -cE '\[.*\]\(.*\)' docs/index.md 2>/dev/null || true)
  # Check each markdown link
  BROKEN=0
  while IFS= read -r link; do
    target=$(echo "$link" | sed 's/.*\[.*\](//;s/).*//' | sed 's/#.*//')
    [ -z "$target" ] && continue
    # Handle relative links from docs/
    if echo "$target" | grep -qE '^\.\./|^/|^http'; then
      continue  # skip external or absolute
    fi
    if [ ! -f "docs/$target" ] && [ ! -f "$target" ] && [ ! -f "docs/${target#./}" ]; then
      warn "Broken link in index.md -> $target"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
      BROKEN=$((BROKEN + 1))
    fi
  done < <(grep -oE '\[.*\]\([^)]+\)' docs/index.md 2>/dev/null || true)
  if [ "$BROKEN" -eq 0 ]; then
    ok "All $INDEX_FILES links in index.md resolve"
  fi
else
  warn "No docs/index.md found"
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
fi

echo ""

# ---- orphan docs check -------------------------------------------------------

echo "--- Orphan docs (not referenced in index.md) ---"
ORPHANS=0
while IFS= read -r f; do
  base=$(basename "$f")
  rel="docs${f#*docs}"
  rel="${rel#./}"
  if [ -f docs/index.md ]; then
    if ! grep -q "$base" docs/index.md 2>/dev/null; then
      warn "Not listed in index.md: $rel"
      ORPHANS=$((ORPHANS + 1))
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    fi
  fi
done < <(find docs -name '*.md' -type f 2>/dev/null | grep -v index.md | grep -v '/archive/')
if [ "$ORPHANS" -eq 0 ]; then
  ok "All .md files are referenced in index.md"
fi

echo ""

# ---- version drift -----------------------------------------------------------

echo "--- Version drift ---"

# Extract version from build file
BUILD_VERSION=""
if [ -f build.gradle ]; then
  BUILD_VERSION=$(grep -m1 "^version\s*=" build.gradle 2>/dev/null | sed "s/version\s*=\s*['\"]//;s/['\"]//" || true)
elif [ -f pom.xml ]; then
  BUILD_VERSION=$(grep -m1 '<version>' pom.xml 2>/dev/null | sed 's/.*<version>//;s/<\/version>.*//' || true)
elif [ -f package.json ]; then
  BUILD_VERSION=$(grep -m1 '"version"' package.json 2>/dev/null | sed 's/.*"version": *"//;s/".*//' || true)
fi

# Extract version claims from index.md title
INDEX_VERSION=""
if [ -f docs/index.md ]; then
  INDEX_VERSION=$(head -1 docs/index.md | grep -oiE 'V[0-9]+\.[0-9]+' | head -1 || true)
fi

if [ -n "$BUILD_VERSION" ] && [ -n "$INDEX_VERSION" ]; then
  if echo "$BUILD_VERSION" | grep -qiE "$INDEX_VERSION|${INDEX_VERSION#V}"; then
    ok "Version matches: docs says $INDEX_VERSION, build says $BUILD_VERSION"
  else
    warn "Version mismatch: docs/index.md says $INDEX_VERSION, build says $BUILD_VERSION"
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
  fi
elif [ -z "$BUILD_VERSION" ]; then
  ok "No build version detected (SNAPSHOT/unversioned) — skipping version check"
elif [ -z "$INDEX_VERSION" ]; then
  ok "No version in index.md title — skipping version check"
fi

echo ""

# ---- doc last-updated check --------------------------------------------------

echo "--- Doc staleness (last update) ---"
if [ "$has_git" = true ]; then
  STALE=0
  while IFS= read -r f; do
    doc_date=$(grep -oiE '\*\*Date:\*\*\s+\S+|\*Date:\*\s+\S+|^>\s+\*\*Date:\*\*\s+\S+' "$f" 2>/dev/null | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    if [ -n "$doc_date" ]; then
      doc_epoch=$(date -j -f "%Y-%m-%d" "$doc_date" +%s 2>/dev/null || echo "0")
      repo_epoch=$(date -j -f "%Y-%m-%d" "$LAST_COMMIT" +%s 2>/dev/null || echo "0")
      if [ "$doc_epoch" -lt "$repo_epoch" ] 2>/dev/null; then
        days=$(( (repo_epoch - doc_epoch) / 86400 ))
        if [ "$days" -gt 30 ]; then
          base=$(basename "$f")
          warn "$base claims $doc_date — repo last commit is $LAST_COMMIT ($days days stale)"
          STALE=$((STALE + 1))
          DRIFT_COUNT=$((DRIFT_COUNT + 1))
        fi
      fi
    fi
  done < <(find docs -name '*.md' -type f 2>/dev/null)
  if [ "$STALE" -eq 0 ]; then
    ok "All dated docs are fresh (within 30 days of last commit)"
  fi
else
  ok "No git repo — skipping staleness check"
fi

echo ""

# ---- endpoint drift (Java projects only) -------------------------------------

if ls src/main/java 2>/dev/null | grep -q .; then
  echo "--- Endpoint drift (documented vs code) ---"
  # Extract documented paths from architecture/*.md
  if [ -d docs/architecture ]; then
    DOC_PATHS=$(grep -noiE '(GET|POST|PUT|DELETE|PATCH)\s+/([a-z0-9_/-]|:|\{|\})+' docs/architecture/*.md 2>/dev/null || true)
    CLEAN_PATHS=""
    while IFS=: read -r file line content; do
      [ -z "$content" ] && continue
      path=$(echo "$content" | grep -oE '/[a-z0-9_/-]+' || true)
      [ -z "$path" ] && continue
      # Filter out non-API paths (markdown links, file refs, common words)
      skip=false
      for ignore in ".md" "docs/" "architecture/" "http://" "https://" "src/" "target/" "build/" "node_modules/"; do
        if echo "$path" | grep -qiF "$ignore"; then skip=true; break; fi
      done
      # Only keep paths that look like API routes (start with /api/, /admin/, /v\d+/, /internal/, /external/, /public/)
      if [ "$skip" = false ]; then
        if echo "$path" | grep -qiE '^/(api|admin|v[0-9]+|internal|external|public|private|health|actuator|management)'; then
          CLEAN_PATHS="$CLEAN_PATHS"$'\n'"$path"
        fi
      fi
    done <<< "$DOC_PATHS"
    CLEAN_PATHS=$(echo "$CLEAN_PATHS" | sort -u | sed '/^$/d')
    if [ -n "$CLEAN_PATHS" ]; then
      CODE_PATHS=$(find src/main/java -name '*.java' -type f 2>/dev/null | xargs grep -ohE '/[a-z0-9_/-]+' 2>/dev/null | sort -u || true)
      MISSING=0
      while IFS= read -r dp; do
        [ -z "$dp" ] && continue
        if ! echo "$CODE_PATHS" | grep -qF "$dp"; then
          dp_last=$(echo "$dp" | grep -oE '[^/]+$' || true)
          if [ -n "$dp_last" ] && ! echo "$CODE_PATHS" | grep -qE "$dp_last"; then
            warn "Path in docs not found in code: $dp"
            MISSING=$((MISSING + 1))
            DRIFT_COUNT=$((DRIFT_COUNT + 1))
          fi
        fi
      done <<< "$CLEAN_PATHS"
      if [ "$MISSING" -eq 0 ]; then
        ok "All documented endpoint paths found in code"
      fi
    else
      ok "No API endpoint paths found in architecture docs"
    fi
  fi
fi

echo ""
echo "--- Summary ---"
echo "Drift items found: $DRIFT_COUNT"
