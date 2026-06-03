#!/usr/bin/env bash
set -euo pipefail
#
# Publish a feature spec to the central spec registry, keyed by service:
#   $CLAUDE_DOC_HOME/spec-registry/<service>/<slug>-spec.md
#
# Called by /f-mr after the MR is created, with the path to the spec artifact
# as $1. /f-mr also runs standalone (no .specwork/ pipeline) — when the spec
# artifact does not exist this exits 0 silently so /f-mr keeps going. It must
# never fail the MR flow over a missing spec.
#
# <service> is derived exactly like /doc-publish and /adr-publish, so the
# spec-registry/<service>/ key lines up with adr-registry/<service>/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=service-name.sh
. "$SCRIPT_DIR/service-name.sh"

SPEC="${1:-}"
REGISTRY="${OPEN_SDD_DOC_HOME:-$HOME/.claude}/spec-registry"

# No spec artifact → standalone / vibe-coding flow. Skip silently; do not fail.
[ -n "$SPEC" ] && [ -f "$SPEC" ] || exit 0

SERVICE="$(resolve_service_name)"

DEST="$REGISTRY/$SERVICE"
mkdir -p "$DEST"
cp "$SPEC" "$DEST/$(basename "$SPEC")"

echo "Spec published -> $DEST/$(basename "$SPEC")"
