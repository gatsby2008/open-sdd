"""Single source of truth for deriving a pipeline slug from a branch name.

The slug names every ``.specwork/`` file (``<slug>-state.json``, ``<slug>-spec.md``…),
so every caller must derive it the same way: ``/f-start`` and ``/f-resync`` when
they create or rename the files, and ``resolve_slug`` (Python and ``lib/gates.sh``)
when no state file records the branch yet. Before this module each one carried
its own regex and they disagreed on prefixes (``chore/foo`` → ``chore-foo`` in
start.sh, ``foo`` in resolve_slug).

Rules: strip one conventional prefix (``feature/``, ``bugfix/``, ``hotfix/``,
``release/``), lowercase, collapse every run of non-alphanumerics into ``-``, and
trim leading/trailing ``-``.

    feature/PROJ-123        -> proj-123
    feature/IR-70.1         -> ir-70-1
    feature/my_slug         -> my-slug
    chore/foo               -> chore-foo
"""
from __future__ import annotations

import re

_PREFIX = re.compile(r"^(feature|bugfix|hotfix|release)/")


def normalize(text: str) -> str:
    """Lowercase ``text`` and turn every run of non-alphanumerics into a single ``-``."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def slug_from_branch(branch: str) -> str:
    """Slug for ``branch``: conventional prefix stripped, then :func:`normalize`."""
    return normalize(_PREFIX.sub("", branch.strip()))
