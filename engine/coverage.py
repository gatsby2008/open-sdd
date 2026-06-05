"""Test-coverage gate: flag changed production classes that have no matching test.

Deterministic, hard-blocking complement to the prose "Test Coverage" step in
``/implement``. The pure functions decide, for a given stack, whether a changed
source file (a) is a *testable* production class and (b) has a matching test
anywhere in the repo. The thin git wrappers and the ``commands/commit.sh`` wiring
turn that into a commit gate.

Escape hatch: a class with no testable surface (a pure DTO, a Spring config, a
barrel file) is waived explicitly — with a written reason — in
``.specwork/_test/<slug>-coverage-waivers.json`` (pipeline) or
``.sdd-coverage-waivers.json`` at the repo root (standalone). Waived paths are
excluded from the gate.

Conventions enforced:

  Java       src/main/.../FooService.java  ->  FooService{Test,Tests,IT,ITCase}.java
                                               (basename match anywhere in src/test)
  Frontend   Foo.tsx                        ->  Foo.{test,spec}.tsx
                                               or __tests__/Foo.{test,spec}.*
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path, PurePosixPath

# ---------------------------------------------------------------------------
# Java heuristics
# ---------------------------------------------------------------------------

# Stem suffixes that mark a Java type as a data holder / wiring / boilerplate
# with no behavior worth a dedicated unit test. Conservative on purpose: a hard
# block must not fire on a legitimately untestable class.
_JAVA_SKIP_SUFFIXES = (
    "Application", "Config", "Configuration", "Properties",
    "Dto", "Request", "Response", "Entity", "Constants",
    "Exception", "Mapper",
)
_JAVA_SKIP_DIRS = (
    "dto", "dtos", "config", "configuration", "entity", "entities",
    "model", "models", "exception", "exceptions", "constants",
)
_JAVA_SKIP_BASENAMES = ("package-info.java", "module-info.java")
_JAVA_TEST_SUFFIXES = ("Test", "Tests", "IT", "ITCase")

# ---------------------------------------------------------------------------
# Frontend heuristics
# ---------------------------------------------------------------------------

_FE_SOURCE_EXTS = (".ts", ".tsx", ".js", ".jsx")
_FE_SKIP_STEM_SUFFIXES = ("types", "constants", "styles", "config", "d")
_FE_TEST_INFIXES = ("test", "spec")


def _basename(path: str) -> str:
    return PurePosixPath(path).name


def _java_stem(path: str) -> str:
    name = _basename(path)
    return name[:-5] if name.endswith(".java") else name


def is_testable_source(path: str, stack: str) -> bool:
    """True when ``path`` is a production class that should carry a test."""
    p = path.replace("\\", "/")
    name = _basename(p)
    lowered = p.lower()

    if stack == "java":
        if not p.endswith(".java"):
            return False
        if "/src/main/" not in p and not p.startswith("src/main/"):
            return False
        if name in _JAVA_SKIP_BASENAMES:
            return False
        if any(seg in _JAVA_SKIP_DIRS for seg in lowered.split("/")):
            return False
        stem = _java_stem(p)
        if stem.endswith(_JAVA_TEST_SUFFIXES):
            return False
        if stem.endswith(_JAVA_SKIP_SUFFIXES):
            return False
        return True

    if stack == "frontend":
        if not any(p.endswith(ext) for ext in _FE_SOURCE_EXTS):
            return False
        if p.endswith(".d.ts"):
            return False
        if _is_frontend_test(p):
            return False
        stem = name.rsplit(".", 1)[0]
        parts = stem.split(".")
        if parts[-1].lower() in _FE_SKIP_STEM_SUFFIXES and len(parts) > 1:
            return False
        if parts[0].lower() == "index":
            return False
        if ".config" in name or ".stories" in name or name.startswith("setupTests"):
            return False
        return True

    return False


def _is_frontend_test(path: str) -> bool:
    name = _basename(path).lower()
    if "/__tests__/" in path.replace("\\", "/").lower():
        return True
    stem = name.rsplit(".", 1)[0]
    parts = stem.split(".")
    return len(parts) > 1 and parts[-1] in _FE_TEST_INFIXES


def has_matching_test(prod_path: str, test_paths: list[str], stack: str) -> bool:
    """True when some path in ``test_paths`` is a test for ``prod_path``."""
    if stack == "java":
        stem = _java_stem(prod_path)
        wanted = {stem + suf for suf in _JAVA_TEST_SUFFIXES}
        for t in test_paths:
            if t.endswith(".java") and _java_stem(t) in wanted:
                return True
        return False

    if stack == "frontend":
        stem = _basename(prod_path).rsplit(".", 1)[0]
        for t in test_paths:
            tp = t.replace("\\", "/")
            if not _is_frontend_test(tp):
                continue
            tstem = _basename(tp).rsplit(".", 1)[0]
            parts = tstem.split(".")
            if parts and parts[0] == stem:
                return True
        return False

    return False


def is_test_path(path: str, stack: str) -> bool:
    """True when ``path`` is itself a test file (not production)."""
    if stack == "java":
        return path.endswith(".java") and _java_stem(path).endswith(_JAVA_TEST_SUFFIXES)
    if stack == "frontend":
        return _is_frontend_test(path)
    return False


def classes_missing_tests(
    changed_files: list[str], all_files: list[str], stack: str, waived=()
) -> list[str]:
    """Sorted changed production classes with no matching test (waived excluded)."""
    waived_set = set(waived)
    test_paths = [f for f in all_files if is_test_path(f, stack)]
    offenders = []
    for f in changed_files:
        nf = f.replace("\\", "/")
        if nf in waived_set:
            continue
        if not is_testable_source(nf, stack):
            continue
        if not has_matching_test(nf, test_paths, stack):
            offenders.append(nf)
    return sorted(set(offenders))


# ---------------------------------------------------------------------------
# Thin git / fs wrappers (impure)
# ---------------------------------------------------------------------------

def _git_lines(args: list[str]) -> list[str]:
    try:
        out = subprocess.check_output(["git"] + args, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    return [l for l in out.decode("utf-8", "replace").splitlines() if l.strip()]


def changed_files() -> list[str]:
    """Union of staged, unstaged, and untracked file paths in the working tree."""
    paths = set()
    paths.update(_git_lines(["diff", "--name-only"]))
    paths.update(_git_lines(["diff", "--cached", "--name-only"]))
    paths.update(_git_lines(["ls-files", "--others", "--exclude-standard"]))
    return sorted(paths)


def all_repo_files() -> list[str]:
    """Tracked files plus untracked (so a brand-new test counts)."""
    paths = set()
    paths.update(_git_lines(["ls-files"]))
    paths.update(_git_lines(["ls-files", "--others", "--exclude-standard"]))
    return sorted(paths)


def waiver_paths(slug) -> list[str]:
    """Candidate waiver files: per-feature (pipeline) and repo-root (standalone)."""
    paths = []
    if slug:
        paths.append(".specwork/_test/{}-coverage-waivers.json".format(slug))
    paths.append(".sdd-coverage-waivers.json")
    return paths


def _read_waiver_file(path: str) -> set:
    p = Path(path)
    if not p.exists():
        return set()
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return set()
    if isinstance(data, dict):
        return {k.replace("\\", "/") for k in data.keys()}
    if isinstance(data, list):
        return {str(x).replace("\\", "/") for x in data}
    return set()


def load_waivers(slug=None) -> set:
    """Waived paths from the per-feature file and/or the repo-root fallback."""
    waived = set()
    for path in waiver_paths(slug):
        waived |= _read_waiver_file(path)
    return waived