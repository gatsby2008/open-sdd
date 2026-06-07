#!/usr/bin/env bash
set -euo pipefail
#
# Publish a feature spec to the central spec registry, keyed by service:
#   $OPEN_SDD_DOC_HOME/spec-registry/<service>/<slug>-spec.md
#
# Called by /f-mr after the MR is created, with the path to the spec artifact
# as $1. /f-mr also runs standalone (no .specwork/ pipeline) — when the spec
# artifact does not exist this exits 0 silently so /f-mr keeps going. It must
# never fail the MR flow over a missing spec.
#
# Registry root is resolved exactly like /doc-publish, /adr-publish, /doc-query
# and /adr-query, so spec-registry/<service>/ sits beside service-catalog/ and
# adr-registry/<service>/ under the same root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=service-name.sh
. "$SCRIPT_DIR/service-name.sh"

SPEC="${1:-}"
REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/spec-registry"

# No spec artifact → standalone / vibe-coding flow. Skip silently; do not fail.
[ -n "$SPEC" ] && [ -f "$SPEC" ] || exit 0

SERVICE="$(resolve_service_name)"

DEST="$REGISTRY/$SERVICE"
mkdir -p "$DEST"
cp "$SPEC" "$DEST/$(basename "$SPEC")"

echo "Spec published -> $DEST/$(basename "$SPEC")"
