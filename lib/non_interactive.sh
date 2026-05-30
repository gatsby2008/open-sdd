#!/usr/bin/env bash

# Hydrates SDD_NON_INTERACTIVE from pipeline state when available.
# Safe no-op when no state exists.

hydrate_non_interactive_from_state() {
  # Explicit env always wins.
  if [ "${SDD_NON_INTERACTIVE:-0}" = "1" ]; then
    return 0
  fi

  local slug="${1:-}"
  local state_file=""

  if [ -n "$slug" ] && [ -f ".specwork/_state/${slug}-state.json" ]; then
    state_file=".specwork/_state/${slug}-state.json"
  else
    state_file=$(find .specwork/_state -maxdepth 1 -type f -name "*-state.json" 2>/dev/null | sort | head -1 || true)
  fi

  [ -n "$state_file" ] || return 0
  [ -f "$state_file" ] || return 0

  local mode
  mode=$(python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print("1" if d.get("non_interactive") else "0")
except Exception:
    print("0")
' "$state_file" 2>/dev/null || echo "0")

  if [ "$mode" = "1" ]; then
    export SDD_NON_INTERACTIVE=1
  fi
}
