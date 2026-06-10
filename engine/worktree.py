"""Working-tree cleanliness checks (engine layer).

Centralizes the ``git status --porcelain`` checks previously inlined across
close.sh, pause.sh, resume.sh, status.sh, start.sh and spec.sh — including the
"clean except agent files" variant. The porcelain parser is pure (testable
without a repo); thin wrappers shell out to git.
"""
import subprocess
from pathlib import PurePosixPath

# Per-tool instruction files that don't count as "real" changes for some gates.
AGENT_FILES = ("AGENTS.md", "CLAUDE.md", "GEMINI.md")


def parse_porcelain(output: str, exclude_agent_files: bool = False) -> list[str]:
    """Changed file paths from ``git status --porcelain`` output.

    Handles rename entries (``orig -> new`` keeps ``new``). When
    ``exclude_agent_files`` is set, drops top-level agent instruction files.
    """
    files = []
    for line in output.splitlines():
        if not line.strip():
            continue
        path = line[3:].strip()  # porcelain v1: 2 status chars + space, then path
        if " -> " in path:
            path = path.split(" -> ", 1)[1].strip()
        files.append(path)
    if exclude_agent_files:
        files = [f for f in files if PurePosixPath(f).name not in AGENT_FILES]
    return files


def _git_porcelain() -> str:
    return subprocess.check_output(["git", "status", "--porcelain"]).decode()


def dirty_files(exclude_agent_files: bool = False) -> list[str]:
    return parse_porcelain(_git_porcelain(), exclude_agent_files)


def is_clean(exclude_agent_files: bool = False) -> bool:
    return not dirty_files(exclude_agent_files)
