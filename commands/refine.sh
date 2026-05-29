#!/usr/bin/env bash
set -euo pipefail

# Deprecated. Both /f-refine and /f-spec-refine have been folded into /f-spec.
# This wrapper exists for backwards compatibility with older docs, agent
# instructions, and external memories. It will be removed in a future release.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat >&2 <<'WARN'
⚠  /f-refine and /f-spec-refine are deprecated. Use /f-spec instead.

   ./commands/spec.sh handles both first-time drafting (when spec.md is
   absent) and refining (when spec.md exists), and bumps
   spec_write_timestamp on every write.

   Forwarding to ./commands/spec.sh now.

WARN

exec "$SCRIPT_DIR/spec.sh" "$@"
