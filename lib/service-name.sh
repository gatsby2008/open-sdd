#!/usr/bin/env bash
#
# Shared service-name resolver for the doc/spec/ADR publish scripts.
# Source this file, then call `resolve_service_name`.
#
# Resolution order (first hit wins), so every registry agrees on one key:
#   1. spring.application.name from application.yml/.yaml (authoritative for
#      Spring services — the value is the deployed service name)
#   2. spring.application.name from application.properties
#   3. first "# Heading" of docs/service-info.md (kebab-cased)
#   4. git repo basename
#   5. "unknown"
#
# Output is lowercased kebab-case to match what is already in the registry
# (e.g. leads-service, consumer-portal-service).
#
# Portable: POSIX awk (busybox/alpine ok), no interval expressions, no yq.

_spring_app_name_yaml() {
  awk '
    function ind(s,   n) { n = 0; while (substr(s, n + 1, 1) == " ") n++; return n }
    {
      raw = $0
      sub(/#.*/, "", raw)            # strip inline comments
      if (raw ~ /^[ \t]*$/) next     # skip blank lines
      i = ind(raw)
      k = raw; sub(/^[ \t]*/, "", k) # key/value with leading space removed
    }
    i == 0 && k ~ /^spring:/  { in_s = 1; next }
    i == 0 && k !~ /^spring:/ { in_s = 0; in_a = 0; next }
    in_s && !in_a && k ~ /^application:/ { in_a = 1; ai = i; next }
    in_s && in_a && i <= ai { in_a = 0 }
    in_s && in_a && k ~ /^name:/ {
      v = k; sub(/^name:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      print v; exit
    }
  ' "$1"
}

resolve_service_name() {
  local name="" yml

  for yml in src/main/resources/application.yml src/main/resources/application.yaml \
             application.yml application.yaml; do
    [ -f "$yml" ] || continue
    name="$(_spring_app_name_yaml "$yml")"
    [ -n "$name" ] && break
  done

  if [ -z "$name" ] && [ -f src/main/resources/application.properties ]; then
    name="$(grep -E '^[[:space:]]*spring\.application\.name[[:space:]]*=' \
              src/main/resources/application.properties 2>/dev/null \
            | head -1 | sed 's/^[^=]*=[[:space:]]*//')"
  fi

  if [ -z "$name" ] && [ -f docs/service-info.md ] && head -1 docs/service-info.md | grep -qE '^# '; then
    name="$(head -1 docs/service-info.md | sed 's/^# *//;s/^Service: *//i;s/[ _]/-/g')"
  fi

  if [ -z "$name" ]; then
    name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")"
  fi

  [ -n "$name" ] || name="unknown"

  name="${name%\'}"; name="${name#\'}"
  name="${name%\"}"; name="${name#\"}"
  printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]'
}
