"""Commit / MR title formatting (engine layer).

The mechanical parts — extracting the ticket from the branch and assembling the
``[TICKET] <type>: <summary>`` string — live here (ticket extraction reuses
gates.ticket_from_branch). The ``<type>`` and ``<summary>`` remain the model's
judgment; this module only formats what it is given.
"""
from engine.gates import ticket_from_branch


def ticket(branch: str) -> str:
    """Canonical ticket key from a branch (e.g. ``MYYES-123``), or ``""``."""
    return ticket_from_branch(branch)[0]


def commit_subject(branch: str, change_type: str, summary: str) -> str:
    """``[TICKET] <type>: <summary>`` — ``[NO-TICKET]`` when the branch has none."""
    key = ticket(branch) or "NO-TICKET"
    return f"[{key}] {change_type}: {summary}"


def mr_title(branch: str, change_type: str, summary: str) -> str:
    """``[TICKET] <type>: <summary>``, or ``<type>: <summary>`` when no ticket."""
    key = ticket(branch)
    prefix = f"[{key}] " if key else ""
    return f"{prefix}{change_type}: {summary}"
