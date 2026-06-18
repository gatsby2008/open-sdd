#!/usr/bin/env bash
# /doc-spec — store a feature spec.md in the central spec registry so
# /doc-spec-query can read it. Publish-only counterpart to /f-mr (which publishes
# automatically inside the pipeline). For hand-written or standalone specs.
#
#   $OPEN_SDD_DOC_HOME/spec-registry/<service>/<slug>-spec.md
#
# Modes:
#   doc-spec <path>   store the given spec file
#   doc-spec          auto-detect the active .specwork spec, else usage
#   doc-spec list     list specs already in the registry
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/spec-registry"

# ---- list mode ----------------------------------------------------------------

if [ "${1:-}" = "list" ]; then
  SERVICE_NAME="$(resolve_service_name)"
  SPEC_DIR="$REGISTRY/$SERVICE_NAME"
  if [ -d "$SPEC_DIR" ]; then
    specs=("$SPEC_DIR"/*-spec.md)
    if [ ${#specs[@]} -gt 0 ] && [ -f "${specs[0]}" ]; then
      echo "Specs for $SERVICE_NAME:"
      for spec in "${specs[@]}"; do
        echo "  $(basename "$spec")"
      done
    else
      echo "No specs found for $SERVICE_NAME."
    fi
  else
    echo "No specs found for $SERVICE_NAME."
    echo "Store a spec with /doc-spec <path>, or run the pipeline through /f-mr."
  fi
  exit 0
fi

# ---- resolve the spec file ----------------------------------------------------

SPEC="${1:-}"

if [ -n "$SPEC" ]; then
  [ -f "$SPEC" ] || die "Spec file not found: $SPEC
Pass the path to a spec markdown file: /doc-spec docs/my-feature-spec.md"
else
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  slug="${branch##*/}"
  if [ -n "$slug" ] && [ "$slug" != "HEAD" ]; then
    SPEC="$(find .specwork -name "${slug}-spec.md" -type f 2>/dev/null | head -1)"
  fi
  [ -n "$SPEC" ] || SPEC="$(find .specwork -name '*-spec.md' -type f 2>/dev/null | head -1)"
  [ -n "$SPEC" ] || die "Nothing to store. Pass a spec file path:

  /doc-spec docs/my-feature-spec.md

Or run this from a project with an active pipeline (.specwork/ spec)."
fi

# ---- resolve service + destination name ---------------------------------------

SERVICE="$(resolve_service_name)"
echo "Service: $SERVICE"
echo "Spec file: $SPEC"
echo ""

# /doc-spec-query only discovers *-spec.md, so the destination name must end in it.
base="$(basename "$SPEC")"
if [ "${base%-spec.md}" != "$base" ]; then
  DEST_NAME="$base"
else
  stem="${base%.md}"
  if [ "$stem" = "spec" ] || [ -z "$stem" ]; then
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    slug="${branch##*/}"
    [ -n "$slug" ] && [ "$slug" != "HEAD" ] \
      || die "Cannot derive a spec slug. Rename the file to <slug>-spec.md and retry."
    DEST_NAME="${slug}-spec.md"
  else
    DEST_NAME="${stem}-spec.md"
  fi
fi

echo "Destination: $REGISTRY/$SERVICE/$DEST_NAME"
echo ""

# ---- instructions ------------------------------------------------------------

echo "---"
echo "Instructions:"
echo ""
echo "1. Store the spec STRAIGHT in the registry — no confirmation prompt:"
echo "   mkdir -p \"$REGISTRY/$SERVICE\""
echo "   cp \"$SPEC\" \"$REGISTRY/$SERVICE/$DEST_NAME\""
echo ""
echo "2. List the registry to confirm, and print the stored path:"
echo "   ls -1 \"$REGISTRY/$SERVICE/\"*-spec.md 2>/dev/null | xargs -n1 basename | sort"
echo ""

# Nudge toward the canonical sections /doc-spec-query reads, without failing.
if ! grep -qE '^## (Summary|Behavior)' "$SPEC" 2>/dev/null; then
  echo "Tip: /doc-spec-query reads ## Summary, ## Behavior, ## Scope, ## Safe Constraints,"
  echo "and ## Open Questions — add them for richer answers."
  echo ""
fi

echo "Run /doc-spec-query to ask feature/spec questions across services."
