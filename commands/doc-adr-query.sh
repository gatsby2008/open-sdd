#!/usr/bin/env bash
# Deprecated: /doc-adr-query is now /doc-ask type:adr (see docs/reviews/2026-11-doc-ask-plan.md).
# Kept for one release so existing habits and notes keep working; it delegates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "⚠ /doc-adr-query is deprecated — use /doc-ask type:adr <question>, or just /doc-ask <question>."
echo ""
exec bash "$SCRIPT_DIR/doc-ask.sh" "type:adr" "$@"
