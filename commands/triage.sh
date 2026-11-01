#!/usr/bin/env bash
set -euo pipefail

# Usage: triage.sh <slug> [--tier <trivial|focused|standard|high-risk|auto> "<reason>"]
# Internal — run by /f-spec after the first draft, never standalone.
# Classifies the spec and writes .specwork/_state/<slug>-path.json (and the tier
# into state.json). --tier forces the tier (stored as an `override` block,
# sticky across later runs); a reason is mandatory. --tier auto drops it.
# The logic lives in engine/triage.py; this is a thin wrapper.

ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SLUG="${1:-}"
if [ -z "$SLUG" ] || [ ! -f ".specwork/_spec/${SLUG}-spec.md" ]; then
  echo "Usage: ./commands/triage.sh <slug> [--tier <tier|auto> \"<reason>\"]  (internal — run by /f-spec, not a user command)"
  echo "Requires: .specwork/_spec/<slug>-spec.md"
  exit 1
fi

PYTHONPATH="$ENGINE_ROOT" exec python3 -m engine.cli triage "$@"
