#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"
WITH_DOCS=false

# ---- argument parsing --------------------------------------------------------

LIST_MODE=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    list) LIST_MODE=true ;;
    --with-docs) WITH_DOCS=true ;;
    *) ARGS+=("$arg") ;;
  esac
done

# ---- list mode ---------------------------------------------------------------

if [ "$LIST_MODE" = true ]; then
  SERVICE_NAME="$(resolve_service_name)"
  CATALOG_FILE="$REGISTRY/$SERVICE_NAME.md"
  if [ -f "$CATALOG_FILE" ]; then
    echo "Service: $SERVICE_NAME"
    mtime="$(stat -f '%Sm' -t '%b %d %H:%M' "$CATALOG_FILE" 2>/dev/null || stat -c '%y' "$CATALOG_FILE" 2>/dev/null || echo "")"
    echo "  $SERVICE_NAME.md  (last updated $mtime)"
    if [ -d "$REGISTRY/docs/$SERVICE_NAME" ]; then
      count=$(find "$REGISTRY/docs/$SERVICE_NAME" -name '*.md' -type f | wc -l | tr -d ' ')
      echo "  Extra docs: $count file(s)"
    fi
  else
    echo "No catalog found for $SERVICE_NAME in $REGISTRY"
    echo "Run /doc-catalog in this repo to create and publish it."
  fi
  exit 0
fi

# ---- stack detection ---------------------------------------------------------

STACK="unknown"
if [ -f pom.xml ] || [ -f build.gradle ]; then
  STACK="java"
elif [ -f package.json ]; then
  STACK="frontend"
fi

SERVICE_NAME="$(resolve_service_name)"

echo "Stack: $STACK"
echo "Service: $SERVICE_NAME"
echo "Updated: $(date '+%Y-%m-%d')"
echo ""

# ---- Java scanning -----------------------------------------------------------

if [ "$STACK" = "java" ]; then
  echo "=== ENDPOINTS ==="
  while IFS=: read -r file line; do
    [ -z "$file" ] && continue
    class_path=$(echo "$file" | sed 's|^\./||')
    class_base=$(echo "$class_path" | sed 's/\.java$//')
    class_map=$(grep -E '@(RequestMapping|GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping)' "$file" 2>/dev/null | head -1 | sed "s/.*'(//;s/)'.*//;s/\"//g;s/value = //" || true)
    grep -nE '@(GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping)\b' "$file" 2>/dev/null | while read -r line_match; do
      method_line=$(echo "$line_match" | grep -oE '[0-9]+' | head -1)
      method=$(echo "$line_match" | grep -oE 'GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping')
      path=$(echo "$line_match" | sed "s/.*'(//;s/)'.*//;s/\"//g;s/value = //" | head -1)
      full_path="${class_map}${path}"
      full_path="${full_path//\$\{*}/}"
      http_method="GET"
      case "$method" in
        PostMapping) http_method="POST" ;;
        PutMapping) http_method="PUT" ;;
        DeleteMapping) http_method="DELETE" ;;
        PatchMapping) http_method="PATCH" ;;
      esac
      echo "$http_method $full_path $class_base"
    done
  done < <(find src/main/java -name '*.java' 2>/dev/null | xargs grep -l '@\(Rest\)\?Controller' 2>/dev/null || true)

  echo ""
  echo "=== SQS LISTENERS ==="
  grep -rn '@SqsListener' src/main/java/ 2>/dev/null | head -50 || echo "(none)"

  echo ""
  echo "=== SNS PUBLISHERS ==="
  grep -rn 'SnsTemplate\.\|SnsClient\.\|AmazonSNS\.\|sendNotification\|convertAndSend' src/main/java/ 2>/dev/null | grep -v '/build/' | head -30 || echo "(none)"

  echo ""
  echo "=== FEIGN CLIENTS ==="
  grep -rn '@FeignClient' src/main/java/ 2>/dev/null | head -20 || echo "(none)"

  echo ""
  echo "=== SCHEDULED JOBS ==="
  grep -rn '@Scheduled' src/main/java/ 2>/dev/null | head -20 || echo "(none)"

  echo ""
  echo "=== DTO CLASSES ==="
  find src/main/java -name '*DTO*.java' -o -name '*Request*.java' -o -name '*Response*.java' -o -name '*Event*.java' 2>/dev/null | head -30 || echo "(none)"

  echo ""
  echo "=== CONFIGURATION ==="
  for cfg in src/main/resources/application.yml src/main/resources/application.yaml src/main/resources/application.properties; do
    [ -f "$cfg" ] && echo "--- $cfg ---" && head -50 "$cfg"
  done
fi

# ---- Frontend scanning -------------------------------------------------------

if [ "$STACK" = "frontend" ]; then
  echo "=== FRAMEWORK ==="
  if grep -q '"next"' package.json 2>/dev/null; then echo "Next.js"
  elif grep -q '"vue"' package.json 2>/dev/null; then echo "Vue"
  elif grep -q '"react"' package.json 2>/dev/null; then echo "React"
  else echo "Unknown JS framework"; fi

  echo ""
  echo "=== ROUTES / PAGES ==="
  find app -name 'page.tsx' -o -name 'page.jsx' 2>/dev/null | sort | head -30 || true
  find pages -name '*.tsx' -o -name '*.jsx' 2>/dev/null | sort | head -30 || true
  find src -name '*.tsx' -o -name '*.jsx' 2>/dev/null | grep -iE '(router|route|page)' | head -20 || true

  echo ""
  echo "=== API CALLS ==="
  grep -rn 'fetch\|axios\|useQuery\|useMutation' src/ app/ pages/ 2>/dev/null | grep -vE 'node_modules|\.test\.' | grep -oE '["'\'']https?://[^"'\'']*|["'\''][A-Za-z_]+/api/[^"'\'']*' | head -30 || true

  echo ""
  echo "=== EXTERNAL INTEGRATIONS ==="
  grep -E '"@?@?(aws-amplify|auth0|stripe|firebase|datadog|launchdarkly|growthbook|segment|sentry)' package.json 2>/dev/null | head -10 || echo "(none)"

  echo ""
  echo "=== FEATURE FLAGS ==="
  grep -rn 'FEATURE_\|useFlags\|useFeature\|process\.env\.NEXT_PUBLIC_FEATURE\|import\.meta\.env\.VITE_FEATURE' src/ app/ pages/ 2>/dev/null | head -20 || echo "(none)"

  echo ""
  echo "=== ENVIRONMENT VARIABLES ==="
  for f in .env.example next.config.ts next.config.js vite.config.ts vite.config.js; do
    [ -f "$f" ] && echo "--- $f ---" && cat "$f"
  done
fi

echo ""
echo "---"
echo "Instructions:"
echo ""
echo "1. Use the scan output above to generate the service catalog (Markdown)."
echo "   Add frontmatter: service: $SERVICE_NAME, updated: $(date '+%Y-%m-%d')."
echo "   If a catalog already exists at the destination below, merge changes"
echo "   preserving any <!-- manual --> sections."
echo ""
echo "2. Write it STRAIGHT to the registry — no copy in the repo, no confirmation prompt:"
echo "   mkdir -p \"$REGISTRY\""
echo "   # write the catalog to \"$REGISTRY/$SERVICE_NAME.md\""
echo ""

if [ "$WITH_DOCS" = true ]; then
  echo "3. Also publish extra docs to the registry under $REGISTRY/docs/$SERVICE_NAME/:"
  echo "   - docs/architecture/*.md"
  echo "   - docs/features/*.md"
  echo "   - docs/product/*.md"
  echo "   - docs/security/*.md"
  echo "   - docs/*.md (excluding service-info.md)"
  echo ""
fi

echo "Then list the registry to confirm, and print the stored path:"
echo "   ls -1 \"$REGISTRY\"/*.md 2>/dev/null | xargs -n1 basename | sort"
echo ""
echo "Run /doc-catalog-query to ask cross-service questions."
