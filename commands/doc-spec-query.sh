#!/usr/bin/env bash
# Deprecated: /doc-spec-query is now /doc-ask type:spec (see docs/reviews/2026-11-doc-ask-plan.md).
# Kept for one release so existing habits and notes keep working; it delegates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "⚠ /doc-spec-query is deprecated — use /doc-ask type:spec <question>, or just /doc-ask <question>."
echo ""
exec bash "$SCRIPT_DIR/doc-ask.sh" "type:spec" "$@"
