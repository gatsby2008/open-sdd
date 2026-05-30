#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"

case "${1:-}" in
  list)
    if [ ! -d "$REGISTRY" ] || ! ls "$REGISTRY"/*.md >/dev/null 2>&1; then
      echo "Service catalog registry is empty."
      echo "Run /doc-catalog then /doc-publish in a service repo to populate it."
      exit 0
    fi
    echo "Registered services in $REGISTRY:"
    ls -lt "$REGISTRY"/*.md 2>/dev/null | while read -r line; do
      name="$(echo "$line" | awk '{print $NF}' | xargs basename)"
      mtime="$(echo "$line" | awk '{print $6, $7, $8}')"
      printf "  %-40s  (last updated %s)\n" "$name" "$mtime"
    done
    echo ""
    echo "Use /doc-query to ask cross-service questions against this registry."
    exit 0
    ;;
  ""|publish)
    ;;
  *)
    die "Usage: /doc-publish [list]

  /doc-publish      Publish docs/service-info.md to the registry
  /doc-publish list  List registered catalogs"
    ;;
esac

[ -f docs/service-info.md ] || die "docs/service-info.md not found.
Run /doc-catalog first to generate the service catalog."

SERVICE_NAME=""
if head -1 docs/service-info.md | grep -qE '^# '; then
  SERVICE_NAME=$(head -1 docs/service-info.md | sed 's/^# \s*//;s/[ _]/-/g' | tr '[:upper:]' '[:lower:]')
fi
if [ -z "$SERVICE_NAME" ]; then
  SERVICE_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
fi

mkdir -p "$REGISTRY"
cp "docs/service-info.md" "$REGISTRY/$SERVICE_NAME.md"

echo "Published: docs/service-info.md -> $REGISTRY/$SERVICE_NAME.md"
echo ""
echo "Registry now contains:"
ls -1 "$REGISTRY"/*.md 2>/dev/null | xargs -n1 basename | sort
echo ""
echo "Run /doc-query to ask cross-service questions."
