#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/adr-registry"

if ! find "$REGISTRY" -name "*.md" -type f 2>/dev/null | head -1 | grep -q .; then
  echo "No ADRs found in $REGISTRY/"
  echo ""
  echo "Run /doc-adr to create ADRs in a project, then /adr-publish to register them."
  exit 0
fi

echo "Available ADR services in $REGISTRY:"
ls -1 "$REGISTRY"/ 2>/dev/null
echo ""

# Try to narrow scope based on argument
SCOPED_SUBDIRS=()
ARG="${1:-}"
if [ -n "$ARG" ]; then
  for dir in "$REGISTRY"/*/; do
    [ -d "$dir" ] || continue
    svc=$(basename "$dir")
    # Check if the service name appears in the argument
    if echo "$ARG" | grep -qi "$svc"; then
      SCOPED_SUBDIRS+=("$dir")
    fi
  done

  AGGREGATE=false
  for word in "all services" "all ADRs" "every" "across" "compare" "which services"; do
    if echo "$ARG" | grep -qiE "$word"; then
      AGGREGATE=true
      break
    fi
  done

  if [ ${#SCOPED_SUBDIRS[@]} -eq 1 ] && [ "$AGGREGATE" = false ]; then
    echo "Target service: $(basename "${SCOPED_SUBDIRS[0]}")"
    echo ""
    for d in "${SCOPED_SUBDIRS[@]}"; do
      svc=$(basename "$d")
      count=$(ls -1 "$d"*.md 2>/dev/null | wc -l | tr -d ' ')
      echo "--- $svc ($count ADRs) ---"
      for f in "$d"*.md; do
        echo "==== $svc/$(basename "$f") ===="
        cat "$f"
        echo ""
      done
    done
    echo ""
    echo "Question: $ARG"
    echo "Cite every claim as <service>/<ADR-file>."
    exit 0
  fi

  if [ ${#SCOPED_SUBDIRS[@]} -gt 1 ] && [ "$AGGREGATE" = false ]; then
    echo "Target services:"
    for d in "${SCOPED_SUBDIRS[@]}"; do echo "  $(basename "$d")"; done
    echo ""
    for d in "${SCOPED_SUBDIRS[@]}"; do
      svc=$(basename "$d")
      count=$(ls -1 "$d"*.md 2>/dev/null | wc -l | tr -d ' ')
      echo "--- $svc ($count ADRs) ---"
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
    echo "Cite every claim as <service>/<ADR-file>."
    exit 0
  fi
fi

# Full registry read (no scope narrowing or aggregate question)
echo "Reading the full ADR registry:"
for dir in "$REGISTRY"/*/; do
  [ -d "$dir" ] || continue
  svc=$(basename "$dir")
  count=$(ls -1 "$dir"*.md 2>/dev/null | wc -l | tr -d ' ')
  printf "  %-30s  (%s ADRs)\n" "$svc" "$count"
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
echo "Question: $ARG"
echo "Cite every claim as <service>/<ADR-file>."
