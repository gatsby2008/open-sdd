#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/adr-registry"

case "${1:-}" in
  list)
    if [ ! -d "$REGISTRY" ] || [ -z "$(ls -A "$REGISTRY" 2>/dev/null)" ]; then
      echo "ADR registry is empty."
      echo "Run /doc-adr to create ADRs, then /adr-publish in a service repo to populate it."
      exit 0
    fi
    echo "Registered ADRs in $REGISTRY:"
    for dir in "$REGISTRY"/*/; do
      [ -d "$dir" ] || continue
      service="$(basename "$dir")"
      count="$(ls -1 "$dir"*.md 2>/dev/null | wc -l | tr -d ' ')"
      printf "  %-30s  (%s ADRs)\n" "$service" "$count"
      ls -1 "$dir"*.md 2>/dev/null | xargs -n1 basename | sort | sed 's/^/      /'
    done
    echo ""
    echo "Use /adr-query to ask questions across the registry."
    exit 0
    ;;
  ""|publish)
    ;;
  *)
    die "Usage: /adr-publish [list]

  /adr-publish      Publish docs/adr/*.md to the registry
  /adr-publish list  List registered ADRs"
    ;;
esac

[ -d docs/adr ] && find docs/adr -maxdepth 1 -name "*.md" -type f | head -1 | grep -q . \
  || die "docs/adr/ contains no ADR files.
Run /doc-adr first to create an ADR."

SERVICE=""
if [ -f docs/service-info.md ] && head -1 docs/service-info.md | grep -qE '^# '; then
  SERVICE=$(head -1 docs/service-info.md | sed 's/^# \s*//;s/[ _]/-/g' | tr '[:upper:]' '[:lower:]')
fi
if [ -z "$SERVICE" ]; then
  SERVICE=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
fi

DEST="$REGISTRY/$SERVICE"
mkdir -p "$REGISTRY"
rm -rf "$DEST"
mkdir -p "$DEST"
cp docs/adr/*.md "$DEST"/

COUNT=$(ls -1 "$DEST"/*.md 2>/dev/null | wc -l | tr -d ' ')
echo "Published $COUNT ADRs from docs/adr/ -> $DEST/"
echo ""
echo "Synced:"
ls -1 "$DEST"/*.md 2>/dev/null | xargs -n1 basename | sort
echo ""
echo "Run /adr-query to ask questions across the registry."
