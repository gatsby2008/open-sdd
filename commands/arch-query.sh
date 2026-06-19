#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

ARCH_HOME="${OPEN_SDD_ARCH_HOME:-}"
if [ -z "$ARCH_HOME" ]; then
  echo "OPEN_SDD_ARCH_HOME is not set."
  echo ""
  echo "Set it to the path of your architecture design docs, e.g.:"
  echo "  export OPEN_SDD_ARCH_HOME=\$HOME/team/architecture"
  exit 0
fi

if [ ! -d "$ARCH_HOME" ]; then
  echo "Architecture directory not found at:"
  echo "  $ARCH_HOME"
  echo ""
  echo "Clone the architecture repo and point OPEN_SDD_ARCH_HOME at it."
  exit 0
fi

# ---- collect all markdown files -----------------------------------------------

FILES=()
while IFS= read -r f; do
  FILES+=("$f")
done < <(find "$ARCH_HOME" -name '*.md' -type f 2>/dev/null)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No markdown documents found in $ARCH_HOME/"
  exit 0
fi

# ---- scope narrowing ----------------------------------------------------------

ARG="${1:-}"
SCOPED_DIRS=()
AGGREGATE=false

# List available project areas (top-level subdirectories + root files)
echo "Available project areas in architecture repo:"
for d in "$ARCH_HOME"/*/; do
  [ -d "$d" ] || continue
  echo "  $(basename "$d")"
done
# Also show top-level .md files
root_docs=$(find "$ARCH_HOME" -maxdepth 1 -name '*.md' -type f | sort)
if [ -n "$root_docs" ]; then
  echo "  (root documents)"
fi
echo ""

if [ -n "$ARG" ]; then
  for d in "$ARCH_HOME"/*/; do
    [ -d "$d" ] || continue
    area=$(basename "$d")
    area_norm="$(echo "$area" | tr '-' ' ' | tr '[:upper:]' '[:lower:]')"
    arg_norm="$(echo "$ARG" | tr '[:upper:]' '[:lower:]')"
    # Match if area name (without hyphens) appears in argument,
    # or any word from argument appears in area name
    if echo "$arg_norm" | grep -q "$area_norm"; then
      SCOPED_DIRS+=("$d")
    else
      for word in $arg_norm; do
        if echo "$area_norm" | grep -qw "$word"; then
          SCOPED_DIRS+=("$d")
          break
        fi
      done
    fi
  done

  for word in "all" "every" "across" "compare" "the registry" "list"; do
    if echo "$ARG" | grep -qiE "$word"; then
      AGGREGATE=true
      break
    fi
  done
fi

# ---- decide scope and print ---------------------------------------------------

print_file() {
  local f="$1" prefix="$2"
  local rel="${f#$ARCH_HOME/}"
  echo "==== ${prefix}${rel} ===="
  cat "$f"
  echo ""
}

DECIDED=false

if [ -n "$ARG" ] && [ "$AGGREGATE" = false ] && [ ${#SCOPED_DIRS[@]} -eq 1 ]; then
  area=$(basename "${SCOPED_DIRS[0]}")
  echo "Target area: $area"
  echo ""
  # Include root files that mention the area name
  for f in "${FILES[@]}"; do
    rel="${f#$ARCH_HOME/}"
    if echo "$rel" | grep -qi "^$area/"; then
      print_file "$f" "$area/"
    elif [[ "$rel" != *"/"* ]] && grep -qi "$area" "$f" 2>/dev/null; then
      print_file "$f" ""
    fi
  done
  echo ""
  echo "Question: $ARG"
  echo "Use the documents above to answer. Cite the source file (relative to architecture repo) for every claim."
  DECIDED=true

elif [ -n "$ARG" ] && [ "$AGGREGATE" = false ] && [ ${#SCOPED_DIRS[@]} -gt 1 ]; then
  echo "Target areas:"
  for d in "${SCOPED_DIRS[@]}"; do echo "  $(basename "$d")"; done
  echo ""
  for d in "${SCOPED_DIRS[@]}"; do
    area=$(basename "$d")
    for f in "$d"*.md "$d"*/*.md; do
      [ -f "$f" ] || continue
      print_file "$f" "$area/"
    done
  done
  echo ""
  echo "Question: $ARG"
  echo "Use the documents above to answer. Cite the source file (relative to architecture repo) for every claim."
  DECIDED=true
fi

if [ "$DECIDED" = false ]; then
  echo "Reading all architecture documents:"
  for f in "${FILES[@]}"; do
    rel="${f#$ARCH_HOME/}"
    echo "  $rel"
  done
  echo ""
  for f in "${FILES[@]}"; do
    rel="${f#$ARCH_HOME/}"
    echo "========================================"
    echo "FILE: $rel"
    echo "========================================"
    cat "$f"
    echo ""
  done
  echo ""
  echo "Question: ${1:-}"
  echo "Use the documents above to answer. Cite the source file (relative to architecture repo) for every claim."
fi
