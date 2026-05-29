#!/usr/bin/env bash
set -euo pipefail

SLUG="${1:-}"
SPEC_FILE=".specwork/_spec/${SLUG}-spec.md"
STATE_FILE=".specwork/_state/${SLUG}-state.json"
OUT_FILE=".specwork/_state/${SLUG}-path.json"

if [ -z "$SLUG" ] || [ ! -f "$SPEC_FILE" ]; then
  echo "Usage: ./commands/triage.sh <slug>  (internal — run by /f-spec, not a user command)"
  echo "Requires: .specwork/_spec/<slug>-spec.md"
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"

python3 - "$SPEC_FILE" "$STATE_FILE" "$OUT_FILE" "$SLUG" <<'PY'
import json, re, sys
from pathlib import Path

spec       = Path(sys.argv[1]).read_text(encoding="utf-8")
state      = Path(sys.argv[2])
out        = Path(sys.argv[3])
slug       = sys.argv[4]

def section(name, src):
    m = re.search(rf'(?ms)^## {re.escape(name)}\b(.*?)(?=^## |\Z)', src)
    return m.group(1).strip() if m else ""

behavior = section("Behavior", spec).lower()
impl_ctx = section("Implementation Context", spec).lower()
scope    = section("Expected Change Scope", spec).lower()

HIGH_KW = (
    "async", "completablefuture", "executorservice", "@async",
    "transactional", "retry", "retrytemplate",
    "event", "sns", "sqs", "kafka", "consumer", "producer",
    "auth", "authentication", "authorization", "security",
    "migration", "flyway", "liquibase", "breaking", "concurrency",
)
TRIVIAL_KW = ("typo", "rename", "copy change", "wording", "message change")

matched_high = [k for k in HIGH_KW if k in behavior or k in impl_ctx]
matched_triv = [k for k in TRIVIAL_KW if k in behavior]

known_layers = ("service", "controller", "repository", "config", "tests", "integration")
layers_match = re.search(r"expected layers[^\n]*?:\s*([^\n]+)", scope)
layers = [L for L in known_layers if layers_match and L in layers_match.group(1)]
num_layers = len(layers)

files_match = re.search(r"expected files touched[^\n]*?:\s*(\d+)(?:\s*-\s*(\d+))?", scope)
if files_match:
    lo = int(files_match.group(1))
    hi = int(files_match.group(2)) if files_match.group(2) else lo
    files_estimate = (lo + hi) // 2
else:
    files_estimate = 0

if matched_triv and not matched_high and num_layers <= 1 and files_estimate <= 2:
    ticket_type, complexity = "trivial", "LOW"
    path = ["f-commit", "f-mr"]
    skip = ["f-plan", "f-implement", "f-test-design", "f-test-impl"]
elif matched_high or num_layers >= 4 or files_estimate >= 7:
    ticket_type, complexity = "high-risk", "HIGH"
    path = ["f-plan", "f-implement", "f-test-design", "f-test-impl", "f-commit", "f-mr"]
    skip = []
elif num_layers >= 2 or files_estimate >= 3:
    ticket_type, complexity = "standard", "MEDIUM"
    path = ["f-plan", "f-implement", "f-commit", "f-mr"]
    skip = ["f-test-design", "f-test-impl"]
else:
    ticket_type, complexity = "focused", "LOW"
    path = ["f-implement", "f-commit", "f-mr"]
    skip = ["f-plan", "f-test-design", "f-test-impl"]

signals = []
if matched_high:
    signals.append("high-risk keywords: " + ", ".join(matched_high[:3]))
if matched_triv and ticket_type == "trivial":
    signals.append("trivial-change keywords: " + ", ".join(matched_triv[:3]))
if num_layers:
    signals.append(f"{num_layers} layer(s): {', '.join(layers)}")
if files_estimate:
    signals.append(f"~{files_estimate} files expected")

reason = " · ".join(signals) if signals else "default"

payload = {
    "schema_version": 1,
    "id": slug,
    "ticket_type": ticket_type,
    "complexity": complexity,
    "recommended_path": path,
    "skip": skip,
    "signals": signals,
    "reason": reason,
}
out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

# Update ticket_type and complexity in state.json so the state machine uses
# the correct flow (focused → no plan, trivial → no spec/plan, etc.).
if state.exists():
    try:
        data = json.loads(state.read_text(encoding="utf-8"))
        data["ticket_type"] = ticket_type
        data["complexity"]  = complexity
        state.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except Exception:
        pass  # non-fatal — path.json was already written

# Print triage summary on stderr so the caller gets human-readable output
# even when stdout is consumed programmatically.
print(f"Triage: {ticket_type} ({complexity}) — {reason}", file=sys.stderr)
PY

echo ".specwork/_state/${SLUG}-path.json written" >&2
cat ".specwork/_state/${SLUG}-path.json"
