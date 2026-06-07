#!/usr/bin/env bash
# /spec-publish — publish a feature spec.md to the central spec registry so
# /spec-query can read it. Publish-only counterpart to /f-mr (which publishes
# automatically inside the pipeline). For hand-written or standalone specs.
#
#   $OPEN_SDD_DOC_HOME/spec-registry/<service>/<slug>-spec.md
#
# Modes:
#   spec-publish <path>   publish the given spec file
#   spec-publish          auto-detect the active .specwork spec, else usage
#   spec-publish list     list specs already in the registry
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/spec-registry"

# ---- list mode ----------------------------------------------------------------

if [ "${1:-}" = "list" ]; then
  if ! find "$REGISTRY" -name '*-spec.md' -type f 2>/dev/null | head -1 | grep -q .; then
    echo "Spec registry is empty."
    echo "Publish a spec with /spec-publish <path>, or run the pipeline through /f-mr."
    exit 0
  fi
  echo "Registered specs in $REGISTRY:"
  echo ""
  for svc_dir in "$REGISTRY"/*/; do
    [ -d "$svc_dir" ] || continue
    ls "$svc_dir"*-spec.md >/dev/null 2>&1 || continue
    echo "  $(basename "$svc_dir")/"
    for spec in "$svc_dir"*-spec.md; do
      echo "    $(basename "$spec")"
    done
  done
  echo ""
  echo "Use /spec-query to ask feature/spec questions across services."
  exit 0
fi

# ---- resolve the spec file ----------------------------------------------------

SPEC="${1:-}"

if [ -n "$SPEC" ]; then
  [ -f "$SPEC" ] || die "Spec file not found: $SPEC
Pass the path to a spec markdown file: /spec-publish docs/my-feature-spec.md"
else
  SPEC="$(find .specwork -name '*-spec.md' -type f 2>/dev/null | head -1)"
  [ -n "$SPEC" ] || die "Nothing to publish. Pass a spec file path:

  /spec-publish docs/my-feature-spec.md

Or run this from a project with an active pipeline (.specwork/ spec)."
fi

# ---- resolve service + destination name ---------------------------------------

SERVICE="$(resolve_service_name)"

# /spec-query only discovers *-spec.md, so the destination name must end in it.
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

# ---- publish ------------------------------------------------------------------

DEST="$REGISTRY/$SERVICE"
mkdir -p "$DEST"
cp "$SPEC" "$DEST/$DEST_NAME"

echo "Published: $SPEC -> $DEST/$DEST_NAME"
echo ""
echo "$SERVICE now has:"
ls -1 "$DEST"/*-spec.md 2>/dev/null | xargs -n1 basename | sort | sed 's/^/  /'

# Nudge toward the canonical sections /spec-query reads, without failing.
if ! grep -qE '^## (Summary|Behavior)' "$SPEC" 2>/dev/null; then
  echo ""
  echo "Tip: /spec-query reads ## Summary, ## Behavior, ## Scope, ## Safe Constraints,"
  echo "and ## Open Questions — add them for richer answers."
fi

echo ""
echo "Run /spec-query to ask feature/spec questions across services."
