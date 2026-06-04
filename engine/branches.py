"""Branch classification and base-branch resolution (engine layer).

Centralizes the "what kind of branch / must the tree be clean / what is the
parent branch" decisions previously inlined in start.sh, spec.sh and mr-review.sh.
"""
import re

_PREFIX_RE = re.compile(r"^(feature|hotfix|release|bugfix)/")
_SHARED_BASE = {"main", "master", "develop", "development"}


def classify_branch(branch: str) -> str:
    """Return ``feature|hotfix|release|bugfix|main|develop|other``."""
    m = _PREFIX_RE.match(branch)
    if m:
        return m.group(1)
    if branch in ("main", "master"):
        return "main"
    if branch in ("develop", "development"):
        return "develop"
    return "other"


def is_feature_branch(branch: str) -> bool:
    """True for the prefixed working-branch kinds (feature/hotfix/release/bugfix)."""
    return classify_branch(branch) in ("feature", "hotfix", "release", "bugfix")


def requires_clean_tree(branch: str) -> bool:
    """True for shared base branches where /f-start must branch off a clean tree."""
    return branch in _SHARED_BASE


def detect_base_branch(branch: str, state_base: str = "", default: str = "development") -> str:
    """Resolve the parent/base branch: the value recorded in state wins, else default."""
    return state_base or default
