#!/usr/bin/env bash
set -euo pipefail

# check.sh — stack-detecting test runner.
# Detects the project stack and runs the standard test/check command.
# Exit code mirrors the test command (0 = pass, non-zero = fail).
#
# Usage:
#   bash commands/check.sh
#   CI=true bash commands/check.sh          # quiet mode, no extra output

die() { echo "$*" >&2; exit 1; }

QUIET="${CI:-false}"

detect_cmd() {
  if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "./gradlew check"
  elif [ -f "pom.xml" ]; then
    echo "mvn verify"
  elif [ -f "package.json" ]; then
    if [ -f "pnpm-lock.yaml" ]; then
      echo "pnpm test"
    elif [ -f "yarn.lock" ]; then
      echo "yarn test"
    else
      echo "npm test"
    fi
  elif [ -f "Cargo.toml" ]; then
    echo "cargo test"
  elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ]; then
    echo "pytest"
  elif [ -f "go.mod" ]; then
    echo "go test ./..."
  else
    echo ""
  fi
}

CMD=$(detect_cmd)

if [ -z "$CMD" ]; then
  die "No detectable test command for this project.
Open an issue: https://github.com/anomalyco/open-sdd/issues"
fi

if [ "$QUIET" = "false" ]; then
  echo "Stack detected — running: $CMD"
  echo ""
fi

$CMD
STATUS=$?

if [ "$QUIET" = "false" ]; then
  if [ "$STATUS" -eq 0 ]; then
    echo ""
    echo "All checks passed."
  else
    echo ""
    echo "Checks failed (exit $STATUS)."
  fi
fi

exit $STATUS
