#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"
WITH_DOCS=false
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --with-docs) WITH_DOCS=true ;;
    list) ARGS=("list") ;;
    *) ARGS+=("$arg") ;;
  esac
done

# ---- list mode ----------------------------------------------------------------

if [ "${ARGS[0]:-}" = "list" ]; then
  if [ ! -d "$REGISTRY" ] || ! ls "$REGISTRY"/*.md >/dev/null 2>&1; then
    echo "Service catalog registry is empty."
    echo "Run /doc-catalog then /doc-publish in a service repo to populate it."
    exit 0
  fi
  echo "Registered in $REGISTRY:"
  echo ""
  for f in "$REGISTRY"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    mtime="$(stat -f '%Sm' -t '%b %d %H:%M' "$f" 2>/dev/null || stat -c '%y' "$f" 2>/dev/null || echo "")"
    printf "  %-40s  (last updated %s)\n" "$name" "$mtime"
  done
  echo ""
  if [ -d "$REGISTRY/docs" ]; then
    echo "Extra docs published for:"
    for d in "$REGISTRY/docs"/*/; do
      [ -d "$d" ] || continue
      svc=$(basename "$d")
      count=$(find "$d" -name '*.md' -type f | wc -l | tr -d ' ')
      echo "  $svc ($count extra docs)"
    done
  fi
  echo ""
  echo "Use /doc-query to ask cross-service questions against this registry."
  exit 0
fi

# ---- publish mode -------------------------------------------------------------

[ -f docs/service-info.md ] || die "docs/service-info.md not found.
Run /doc-catalog first to generate the service catalog."

SERVICE_NAME="$(resolve_service_name)"

mkdir -p "$REGISTRY"
cp "docs/service-info.md" "$REGISTRY/$SERVICE_NAME.md"

echo "Published: docs/service-info.md -> $REGISTRY/$SERVICE_NAME.md"

# ---- extra docs ---------------------------------------------------------------

if [ "$WITH_DOCS" = true ]; then
  DOCS_DIR="$REGISTRY/docs/$SERVICE_NAME"
  mkdir -p "$DOCS_DIR"
  count=0
  if [ -d docs/architecture ]; then
    cp docs/architecture/*.md "$DOCS_DIR/" 2>/dev/null || true
    for f in docs/architecture/*.md; do
      [ -f "$f" ] && count=$((count + 1))
    done
  fi
  if [ -d docs/features ]; then
    while IFS= read -r f; do
      cp "$f" "$DOCS_DIR/" 2>/dev/null || true
      count=$((count + 1))
    done < <(find docs/features -name '*.md' -type f 2>/dev/null)
  fi
  if [ -d docs/product ]; then
    cp docs/product/*.md "$DOCS_DIR/" 2>/dev/null || true
    for f in docs/product/*.md; do
      [ -f "$f" ] && count=$((count + 1))
    done
  fi
  if [ -d docs/security ]; then
    cp docs/security/*.md "$DOCS_DIR/" 2>/dev/null || true
    for f in docs/security/*.md; do
      [ -f "$f" ] && count=$((count + 1))
    done
  fi
  for f in docs/*.md; do
    base=$(basename "$f")
    [ "$base" = "service-info.md" ] && continue
    [ -f "$f" ] && cp "$f" "$DOCS_DIR/" && count=$((count + 1))
  done
  echo "Published $count extra docs to $DOCS_DIR/"
fi

echo ""
echo "Registry now contains:"
ls -1 "$REGISTRY"/*.md 2>/dev/null | xargs -n1 basename | sort
[ -d "$REGISTRY/docs" ] && echo "  + docs/"
echo ""
echo "Run /doc-query to ask cross-service questions."
