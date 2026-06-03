#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$ROOT_DIR/install.sh"
README="$ROOT_DIR/README.md"

[ -f "$INSTALL_SH" ] || { echo "Missing install.sh" >&2; exit 1; }
[ -f "$README" ] || { echo "Missing README.md" >&2; exit 1; }

# Ensure removed legacy command stays removed.
if grep -q 'install_cmd "refine"' "$INSTALL_SH"; then
  echo "PARITY FAIL: install.sh still registers refine" >&2
  exit 1
fi

# Ensure cleanup of stale installed command remains.
grep -q 'f-refine.md' "$INSTALL_SH" || {
  echo "PARITY FAIL: install.sh should clean stale f-refine.md" >&2
  exit 1
}

# Ensure key doc/adr command registrations exist.
for cmd in doc-catalog doc-publish doc-query doc-adr adr-publish adr-query doc-freshness; do
  grep -q "install_doc_cmd_directive \"$cmd\"" "$INSTALL_SH" || {
    echo "PARITY FAIL: missing registration for $cmd in install.sh" >&2
    exit 1
  }
done

# Keep README and installer visible count aligned.
readme_count="$(grep -Eo 'Registers all [0-9]+ commands' "$README" | head -1 | grep -Eo '[0-9]+' || true)"
install_count="$(grep -Eo 'open-sdd: [0-9]+ commands installed' "$INSTALL_SH" | head -1 | grep -Eo '[0-9]+' || true)"

[ -n "$readme_count" ] || { echo "PARITY FAIL: could not parse command count from README" >&2; exit 1; }
[ -n "$install_count" ] || { echo "PARITY FAIL: could not parse command count from install.sh" >&2; exit 1; }
[ "$readme_count" = "$install_count" ] || {
  echo "PARITY FAIL: README count=$readme_count differs from install.sh count=$install_count" >&2
  exit 1
}

echo "SDD surface parity OK (legacy removed, command surface aligned)."
