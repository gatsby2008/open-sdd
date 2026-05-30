#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

# ---- helpers ----------------------------------------------------------------

section() { echo ""; echo "=== $1 ==="; }

# ---- stack detection --------------------------------------------------------

STACK="unknown"
SERVICE_NAME=""

if [ -f pom.xml ]; then
  STACK="java"
  SERVICE_NAME=$(grep -m1 '<artifactId>' pom.xml 2>/dev/null | sed 's/.*<artifactId>//;s/<\/artifactId>.*//' || true)
elif [ -f build.gradle ]; then
  STACK="java"
  SERVICE_NAME=$(basename "$(pwd)")
elif [ -f package.json ]; then
  STACK="frontend"
  SERVICE_NAME=$(grep -m1 '"name"' package.json 2>/dev/null | sed 's/.*"name": *"//;s/".*//' || true)
fi

if [ -z "$SERVICE_NAME" ]; then
  SERVICE_NAME=$(basename "$(pwd)")
fi

echo "Stack: $STACK"
echo "Service: $SERVICE_NAME"
echo "Updated: $(date '+%Y-%m-%d')"
echo ""

# ---- Java scanning ----------------------------------------------------------

if [ "$STACK" = "java" ]; then
  section "ENDPOINTS"
  # Grep for REST controllers and their mappings
  while IFS=: read -r file line; do
    [ -z "$file" ] && continue
    class_path=$(echo "$file" | sed 's|^\./||')
    class_base=$(echo "$class_path" | sed 's/\.java$//')
    # class-level mapping
    class_map=$(grep -E '@(RequestMapping|GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping)' "$file" 2>/dev/null | head -1 | sed "s/.*'(//;s/)'.*//;s/\"//g;s/value = //" || true)
    # method-level mappings
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

  section "SQS LISTENERS"
  grep -rn '@SqsListener' src/main/java/ 2>/dev/null | head -50 || echo "(none)"

  section "SNS PUBLISHERS"
  grep -rn 'SnsTemplate\.\|SnsClient\.\|AmazonSNS\.\|sendNotification\|convertAndSend' src/main/java/ 2>/dev/null | grep -v '/build/' | head -30 || echo "(none)"

  section "FEIGN CLIENTS"
  grep -rn '@FeignClient' src/main/java/ 2>/dev/null | head -20 || echo "(none)"

  section "SCHEDULED JOBS"
  grep -rn '@Scheduled' src/main/java/ 2>/dev/null | head -20 || echo "(none)"

  section "DTO CLASSES"
  find src/main/java -name '*DTO*.java' -o -name '*Request*.java' -o -name '*Response*.java' -o -name '*Event*.java' 2>/dev/null | head -30 || echo "(none)"

  section "CONFIGURATION"
  for cfg in src/main/resources/application.yml src/main/resources/application.yaml src/main/resources/application.properties; do
    [ -f "$cfg" ] && echo "--- $cfg ---" && head -50 "$cfg"
  done
fi

# ---- Frontend scanning ------------------------------------------------------

if [ "$STACK" = "frontend" ]; then
  section "FRAMEWORK"
  if grep -q '"next"' package.json 2>/dev/null; then echo "Next.js"
  elif grep -q '"vue"' package.json 2>/dev/null; then echo "Vue"
  elif grep -q '"react"' package.json 2>/dev/null; then echo "React"
  else echo "Unknown JS framework"; fi

  section "ROUTES / PAGES"
  find app -name 'page.tsx' -o -name 'page.jsx' 2>/dev/null | sort | head -30 || true
  find pages -name '*.tsx' -o -name '*.jsx' 2>/dev/null | sort | head -30 || true
  find src -name '*.tsx' -o -name '*.jsx' 2>/dev/null | grep -iE '(router|route|page)' | head -20 || true

  section "API CALLS"
  grep -rn 'fetch\|axios\|useQuery\|useMutation' src/ app/ pages/ 2>/dev/null | grep -vE 'node_modules|\.test\.' | grep -oE '["'\'']https?://[^"'\'']*|["'\''][A-Za-z_]+/api/[^"'\'']*' | head -30 || true

  section "EXTERNAL INTEGRATIONS"
  grep -E '"@?@?(aws-amplify|auth0|stripe|firebase|datadog|launchdarkly|growthbook|segment|sentry)' package.json 2>/dev/null | head -10 || echo "(none)"

  section "FEATURE FLAGS"
  grep -rn 'FEATURE_\|useFlags\|useFeature\|process\.env\.NEXT_PUBLIC_FEATURE\|import\.meta\.env\.VITE_FEATURE' src/ app/ pages/ 2>/dev/null | head -20 || echo "(none)"

  section "ENVIRONMENT VARIABLES"
  for f in .env.example next.config.ts next.config.js vite.config.ts vite.config.js; do
    [ -f "$f" ] && echo "--- $f ---" && cat "$f"
  done
fi

echo ""
echo "---"
echo "Use the scan output above to generate docs/service-info.md."
echo "If the file already exists, merge changes preserving <!-- manual --> sections."
echo "Ask the user for confirmation before writing."
