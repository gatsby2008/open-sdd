#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/investigation-registry"

# ---- check registry exists ---------------------------------------------------

if ! find "$REGISTRY" -name "*.md" -type f 2>/dev/null | head -1 | grep -q .; then
  echo "No investigations found in $REGISTRY/"
  echo ""
  echo "Capture one with /doc-investigation after researching code, then re-run this query."
  exit 0
fi

echo "Available investigation services in $REGISTRY:"
ls -1 "$REGISTRY/" 2>/dev/null
echo ""

# ---- scope narrowing ---------------------------------------------------------

ARG="${1:-}"
SCOPED_SUBDIRS=()
AGGREGATE=false

if [ -n "$ARG" ]; then
  for dir in "$REGISTRY"/*/; do
    [ -d "$dir" ] || continue
    svc=$(basename "$dir")
    if echo "$ARG" | grep -qi "$svc"; then
      SCOPED_SUBDIRS+=("$dir")
    fi
  done

  for word in "all services" "all investigations" "every" "across" "compare" "which services" "ever" "before" "have we seen" "the registry"; do
    if echo "$ARG" | grep -qiE "$word"; then
      AGGREGATE=true
      break
    fi
  done
fi

# ---- decide scope ------------------------------------------------------------

DECIDED=false

if [ -n "$ARG" ]; then
  if [ ${#SCOPED_SUBDIRS[@]} -eq 1 ] && [ "$AGGREGATE" = false ]; then
    echo "Target service: $(basename "${SCOPED_SUBDIRS[0]}")"
    echo ""
    for d in "${SCOPED_SUBDIRS[@]}"; do
      svc=$(basename "$d")
      count=$(ls -1 "$d"*.md 2>/dev/null | wc -l | tr -d ' ')
      echo "--- $svc ($count investigations) ---"
      for f in "$d"*.md; do
        echo "==== $svc/$(basename "$f") ===="
        cat "$f"
        echo ""
      done
    done
    echo ""
    echo "Question: $ARG"
    echo "Use the investigations above to answer. Cite every claim as <service>/<file>."
    DECIDED=true
  elif [ ${#SCOPED_SUBDIRS[@]} -gt 1 ] && [ "$AGGREGATE" = false ]; then
    echo "Target services:"
    for d in "${SCOPED_SUBDIRS[@]}"; do echo "  $(basename "$d")"; done
    echo ""
    for d in "${SCOPED_SUBDIRS[@]}"; do
      svc=$(basename "$d")
      count=$(ls -1 "$d"*.md 2>/dev/null | wc -l | tr -d ' ')
      echo "--- $svc ($count investigations) ---"
      for f in "$d"*.md; do echo "  $(basename "$f")"; done
      echo ""
    done
    for d in "${SCOPED_SUBDIRS[@]}"; do
      svc=$(basename "$d")
      for f in "$d"*.md; do
        echo "==== $svc/$(basename "$f") ===="
        cat "$f"
        echo ""
      done
    done
    echo ""
    echo "Question: $ARG"
    echo "Use the investigations above to answer. Cite every claim as <service>/<file>."
    DECIDED=true
  fi
fi

# ---- full registry read ------------------------------------------------------

if [ "$DECIDED" = false ]; then
  echo "Reading the full investigation registry:"
  for dir in "$REGISTRY"/*/; do
    [ -d "$dir" ] || continue
    svc=$(basename "$dir")
    count=$(ls -1 "$dir"*.md 2>/dev/null | wc -l | tr -d ' ')
    printf "  %-30s  (%s investigations)\n" "$svc" "$count"
  done
  echo ""

  for dir in "$REGISTRY"/*/; do
    [ -d "$dir" ] || continue
    svc=$(basename "$dir")
    for f in "$dir"*.md; do
      echo "==== $svc/$(basename "$f") ===="
      cat "$f"
      echo ""
    done
  done

  echo ""
  echo "Question: ${1:-}"
  echo "Use the investigations above to answer. Cite every claim as <service>/<file>."
fi
