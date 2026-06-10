"""Pipeline stash filtering for pause/resume (engine layer).

/f-pause stores work with a ``f-pause: <branch>`` stash message. This parses
``git stash list``, keeps only pipeline stashes, extracts the branch, and
deduplicates (newest per branch kept; older ones are stale duplicates to drop).
Parsers are pure; the wrapper shells out to git.
"""
import subprocess

PAUSE_PREFIX = "f-pause: "


def parse_stash_list(output: str) -> list[tuple[str, str]]:
    """Parse ``git stash list --format='%gd %s'`` into ``[(ref, message), ...]``."""
    entries = []
    for line in output.splitlines():
        line = line.rstrip()
        if not line:
            continue
        ref, _, msg = line.partition(" ")
        entries.append((ref, msg))
    return entries


def pipeline_stashes(output: str) -> list[tuple[str, str]]:
    """``[(ref, branch), ...]`` for f-pause stashes, in input order (newest-first).

    Matches ``f-pause: `` anywhere in the message — git prefixes the stash subject
    with ``On <branch>: ``, so the marker is not at the start (the original shell
    used a substring ``grep``).
    """
    out = []
    for ref, msg in parse_stash_list(output):
        idx = msg.find(PAUSE_PREFIX)
        if idx != -1:
            out.append((ref, msg[idx + len(PAUSE_PREFIX):].strip()))
    return out


def deduplicate(
    pipeline_list: list[tuple[str, str]],
) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Return ``(kept, stale)``: first (newest) per branch kept, the rest are stale."""
    seen = set()
    kept, stale = [], []
    for ref, branch in pipeline_list:
        if branch in seen:
            stale.append((ref, branch))
        else:
            seen.add(branch)
            kept.append((ref, branch))
    return kept, stale


def _git_stash_list() -> str:
    try:
        return subprocess.check_output(["git", "stash", "list", "--format=%gd %s"]).decode()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def list_kept_and_stale() -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Live ``(kept, stale)`` pipeline stashes from the current repo."""
    return deduplicate(pipeline_stashes(_git_stash_list()))
