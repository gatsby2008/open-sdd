#!/usr/bin/env bash
# /doc-ask — one query over the four doc registries (catalogs, ADRs, specs,
# investigations) under $OPEN_SDD_DOC_HOME. Prints an index of every doc, the
# best-matching docs (trimmed to their matching sections when large) up to a
# budget, the other matches by path, and reading hints. The model answers from
# that output, citing paths. Logic: engine/registry.py.
#
# Usage: doc-ask.sh "<question> [type:catalog|adr|spec|investigation] [service:<name>]"
#        doc-ask.sh --type adr --service leads-service "<question>"
# Budget: OPEN_SDD_ASK_BUDGET (characters, default 60000) or --budget N.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -eq 0 ] || [ -z "${*// /}" ]; then
  echo "Usage: /doc-ask <question> [type:catalog|adr|spec|investigation] [service:<name>]"
  echo ""
  echo "Examples:"
  echo "  /doc-ask who consumes ApplicationStageChangeEvent?"
  echo "  /doc-ask why did we migrate to aws sdk v2?"
  echo "  /doc-ask type:spec which specs have open questions?"
  echo "  /doc-ask service:leads-service have we seen ReportToken reuse before?"
  exit 0
fi

PYTHONPATH="$SCRIPT_DIR/.." exec python3 -m engine.cli ask "$@"
