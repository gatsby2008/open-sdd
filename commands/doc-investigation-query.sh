#!/usr/bin/env bash
# Deprecated: /doc-investigation-query is now /doc-ask type:investigation (see docs/reviews/2026-11-doc-ask-plan.md).
# Kept for one release so existing habits and notes keep working; it delegates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "⚠ /doc-investigation-query is deprecated — use /doc-ask type:investigation <question>, or just /doc-ask <question>."
echo ""
exec bash "$SCRIPT_DIR/doc-ask.sh" "type:investigation" "$@"
