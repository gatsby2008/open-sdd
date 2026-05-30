#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_INSTALL="$ROOT_DIR/install.sh"
PS_INSTALL="$ROOT_DIR/install.ps1"

[ -f "$BASH_INSTALL" ] || { echo "Missing $BASH_INSTALL" >&2; exit 1; }
[ -f "$PS_INSTALL" ] || { echo "Missing $PS_INSTALL" >&2; exit 1; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

bash_defs="$workdir/bash_defs.txt"
ps_defs="$workdir/ps_defs.txt"

grep -E '^(install_cmd|install_cmd_directive|install_doc_cmd_directive) "[^"]+" "[^"]+"' "$BASH_INSTALL" \
  | sed -E 's/^(install_cmd|install_cmd_directive|install_doc_cmd_directive) "([^"]+)" "([^"]+)".*/\1|\2|\3/' \
  | sort > "$bash_defs"

grep -E '^(Install-Cmd|Install-CmdDirective|Install-DocCmdDirective) -Name "[^"]+" -Description "[^"]+"' "$PS_INSTALL" \
  | sed -E 's/^(Install-Cmd|Install-CmdDirective|Install-DocCmdDirective) -Name "([^"]+)" -Description "([^"]+)".*/\1|\2|\3/' \
  | sed -E 's/^Install-Cmd\|/install_cmd|/; s/^Install-CmdDirective\|/install_cmd_directive|/; s/^Install-DocCmdDirective\|/install_doc_cmd_directive|/' \
  | sort > "$ps_defs"

if ! diff -u "$bash_defs" "$ps_defs"; then
  echo ""
  echo "Install parity check failed: command definitions differ." >&2
  exit 1
fi

bash_count="$(grep -Eo 'open-sdd: [0-9]+ commands installed' "$BASH_INSTALL" | head -1 | grep -Eo '[0-9]+' || true)"
ps_count="$(grep -Eo 'open-sdd: [0-9]+ commands installed' "$PS_INSTALL" | head -1 | grep -Eo '[0-9]+' || true)"

if [ -z "$bash_count" ] || [ -z "$ps_count" ]; then
  echo "Could not parse installed-command counters from installers." >&2
  exit 1
fi

if [ "$bash_count" != "$ps_count" ]; then
  echo "Counter mismatch: install.sh=$bash_count, install.ps1=$ps_count" >&2
  exit 1
fi

echo "Install parity OK (definitions and counters match: $bash_count)."
