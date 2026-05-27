FLOW_MAP: dict[str, list[str]] = {
    "feature":      ["spec", "plan", "implement", "commit", "mr", "close"],
    "bugfix":       ["spec", "implement", "commit", "mr", "close"],
    "refactor":     ["plan", "implement", "commit", "mr", "close"],
    "chore":        ["implement", "commit", "mr", "close"],
    "high-risk":    ["plan", "implement", "test-design", "test-impl", "commit", "mr", "close"],
    "standard":     ["plan", "implement", "commit", "mr", "close"],
    "focused":      ["implement", "commit", "mr", "close"],
    "trivial":      ["commit", "mr", "close"],
    "security_fix": ["spec", "implement", "commit", "mr", "close"],
}

# Steps the developer may skip. The gate lets a later step run while the pipeline
# sits on one of these, and advancing past a completed step jumps over any that
# follow. test-impl additionally enforces its own dependency on test-design's
# artifact (a skipped test-design leaves no artifact, so test-impl refuses).
# Code review is an independent command, not a tracked flow step (matches
# claude-tools).
OPTIONAL_STEPS: set[str] = {"test-design", "test-impl"}


def is_optional(step: str) -> bool:
    return step in OPTIONAL_STEPS


def next_step(ticket_type: str, current_step: str, retries: int, max_retries: int = 2) -> str:
    flow = FLOW_MAP.get(ticket_type, FLOW_MAP["feature"])
    if current_step not in flow:
        return flow[0]
    idx = flow.index(current_step)
    if retries < max_retries:
        return current_step
    next_idx = idx + 1
    if next_idx >= len(flow):
        return "done"
    return flow[next_idx]


def flow_for(ticket_type: str) -> list[str]:
    return FLOW_MAP.get(ticket_type, FLOW_MAP["feature"])
