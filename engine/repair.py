"""Repair loop for a red ``commands/check.sh`` in ``/f-mr``: state, attempt cap and metric guard.

When ``check.sh`` fails before a push, ``/f-mr`` may repair the code: fix,
re-check, at most ``MAX_ATTEMPTS``. ``check.sh`` is the loop's metric, and a loop
is only as good as a metric it cannot edit — "fixing" a red build by deleting an
assertion, skipping a test or deselecting it in a config raises the number
without fixing the code.

The guard compares the working tree with ``base`` (``HEAD`` when the loop
opened) and rejects:

  - any change to ``commands/check.sh``;
  - any change to a test-runner config (``pytest.ini``, ``conftest.py``,
    ``jest.config.*``, ``.mocharc*`` …);
  - in shared build files (``pyproject.toml``, ``package.json``, ``pom.xml``,
    ``build.gradle`` …), an added line that excludes or deselects tests;
  - a removed or modified line in an existing test file, or a deleted one
    (renames count as deletions — conservative on purpose);
  - a skip/disable/focus marker on an added test line (``@Disabled``,
    ``pytest.mark.skipif``, ``assumeTrue(``, ``it.only(``, ``t.Skip(`` …).

State lives in the git dir, one file per branch
(``open-sdd-repair-<branch>-<hash>.json``), never in ``.specwork/`` and never
committed: ``base``, ``attempts``, ``untracked_at_open`` (ignored by the guard
and by ``green``), ``checked_tree`` (re-checking the same red content costs no
attempt) and ``green_tree``. ``commands/mr.sh``
— the only place that pushes — drives it: it runs ``pre`` before ``check.sh``
(guard + attempt count), ``red`` on a failure and ``green`` on a pass, and
pushes only after ``green`` closed the loop. While a loop is open it also skips
the rebase, so the base never moves under the guard.

This raises the bar; it is not tamper-proof (a human can ``repair-reset``, and
nothing stops a raw ``git push``).

Wired as ``python3 -m engine.cli repair-<cmd>``:
  repair-red             check.sh failed: open the loop (or count the failure); rc 3 = attempts exhausted
  repair-pre             before check.sh: guard + count; prints NONE | RUN_CHECK | SKIP_CHECK;
                         rc 1 = guard violation or exhausted
  repair-green           check.sh passed: rc 0 = closed, push may proceed · 4 = commit first · 1 = violation
  repair-reset           drop the loop (a human decided to fix it by hand)
  repair-status          print the state JSON, or "none"
  repair-guard <base>    just the guard: rc 0 clean · 1 violations · 2 bad ref
"""
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

MAX_ATTEMPTS = 3
STATE_PREFIX = "open-sdd-repair"
CHECK_SCRIPT = "commands/check.sh"

# Test-runner configs: any change is rejected.
TEST_CONFIG_NAMES = {"pytest.ini", "conftest.py", "junit-platform.properties", ".rspec"}
TEST_CONFIG_PREFIXES = ("jest.config.", "vitest.config.", ".mocharc", "karma.conf.",
                        "playwright.config.", "cypress.config.", "phpunit.xml")
# Shared build files: only added lines that exclude/deselect tests are rejected.
BUILD_FILES = {"pyproject.toml", "setup.cfg", "tox.ini", "package.json", "pom.xml",
               "build.gradle", "build.gradle.kts"}
TEST_EXCLUSION = re.compile(
    r"deselect|--ignore|\baddopts\b|testPathIgnorePatterns|modulePathIgnorePatterns|testIgnore"
    r"|\bexcludes?\b|skipTests|maven\.test\.skip|passWithNoTests|--testNamePattern|\s-[km]\s",
    re.IGNORECASE,
)
SKIP_MARKER = re.compile(
    r"@Disabled\b|@Ignore\b|@pytest\.mark\.(?:skip|skipif|xfail)\b|@unittest\.skip|@unittest\.expectedFailure"
    r"|@expectedFailure\b|\bpytest\.(?:skip|importorskip)\(|\bself\.skipTest\(|\bSkipTest\("
    r"|\bAssume\.assume|\bassume(?:True|False|That)\("
    r"|\b(?:it|test|describe|context)\.(?:skip|todo|only)\(|\b[xf](?:it|describe|test)\("
    r"|\bt\.Skip(?:Now|f)?\(|#\[ignore\]"
)


# ---------------------------------------------------------------------------
# Pure functions
# ---------------------------------------------------------------------------

def parse_name_status(text):
    """``git diff --name-status -z --no-renames`` output → ``{path: status}``."""
    parts = [p for p in text.split("\0") if p]
    return {parts[i + 1]: parts[i][0] for i in range(0, len(parts) - 1, 2)}


def parse_hunks(diff_text):
    """(removed, added) lines of a single-file ``git diff -U0``; headers before the first ``@@`` are skipped."""
    removed, added = [], []
    in_hunks = False
    for line in diff_text.splitlines():
        if line.startswith("@@"):
            in_hunks = True
            continue
        if not in_hunks:
            continue
        if line.startswith("-"):
            removed.append(line[1:])
        elif line.startswith("+"):
            added.append(line[1:])
    return removed, added


def skip_markers(lines):
    """The lines that skip, disable or focus tests."""
    return [line.strip() for line in lines if SKIP_MARKER.search(line)]


def is_test_config(path):
    name = PurePosixPath(path).name
    return name in TEST_CONFIG_NAMES or name.startswith(TEST_CONFIG_PREFIXES)


def is_build_file(path):
    return PurePosixPath(path).name in BUILD_FILES


def violations(changes, is_test):
    """Violation messages for ``changes`` = ``{path: {"status": A|M|D, "removed": [...], "added": [...]}}``."""
    found = []
    for path in sorted(changes):
        change = changes[path]
        status, removed, added = change["status"], change["removed"], change["added"]
        if path == CHECK_SCRIPT:
            found.append("{} was modified — the repair loop may not change its own metric".format(path))
            continue
        if is_test_config(path):
            found.append("{}: test-runner config changed".format(path))
            continue
        if is_build_file(path):
            for line in added:
                if TEST_EXCLUSION.search(line):
                    found.append("{}: test exclusion added — {}".format(path, line.strip()))
            continue
        if not is_test(path):
            continue
        if status == "D":
            found.append("{}: existing test file deleted (or renamed)".format(path))
            continue
        if status == "M" and removed:
            found.append("{}: {} existing line(s) removed or modified".format(path, len(removed)))
        for marker in skip_markers(added):
            found.append("{}: skip marker added — {}".format(path, marker))
    return found


def state_name(branch):
    """Per-branch state file name: sanitized branch + a short hash, so ``a/b`` and ``a_b`` never collide."""
    safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in branch)
    return "{}-{}-{}.json".format(STATE_PREFIX, safe, hashlib.sha1(branch.encode("utf-8")).hexdigest()[:8])


def counts_attempt(state, worktree_tree):
    """A re-check costs an attempt only when the content changed since the last red check."""
    return state.get("checked_tree") != worktree_tree


def uncommitted(tracked, untracked, preexisting):
    """Paths still to commit: changed tracked files plus untracked ones that were not there when the loop opened."""
    before = set(preexisting)
    return sorted(set(tracked) | {p for p in untracked if p not in before})


def next_step(state, worktree_tree):
    """What ``pre`` decides for an open loop: ``SKIP_CHECK`` (this exact tree already passed),
    ``EXHAUSTED`` (no attempts left) or ``RUN_CHECK``."""
    if state.get("green_tree") and state["green_tree"] == worktree_tree:
        return "SKIP_CHECK"
    if state.get("attempts", 0) >= MAX_ATTEMPTS:
        return "EXHAUSTED"
    return "RUN_CHECK"


# ---------------------------------------------------------------------------
# Thin git / fs wrappers (impure)
# ---------------------------------------------------------------------------

def _git(args, env=None):
    out = subprocess.run(["git"] + args, capture_output=True, check=True, env=env)
    return out.stdout.decode("utf-8", "replace")


def _detect_stack():
    try:
        from engine.gates import detect_stack
        return detect_stack()
    except Exception:
        return "unknown"


def current_branch():
    return _git(["rev-parse", "--abbrev-ref", "HEAD"]).strip() or "HEAD"


def state_file():
    """One loop per branch: ``<git-dir>/open-sdd-repair-<branch>-<hash>.json``."""
    return Path(_git(["rev-parse", "--git-path", state_name(current_branch())]).strip())


def load_state():
    try:
        data = json.loads(state_file().read_text(encoding="utf-8"))
    except (ValueError, OSError, subprocess.CalledProcessError):
        return None
    return data if isinstance(data, dict) and data.get("base") else None


def save_state(state):
    state_file().write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def clear_state():
    try:
        state_file().unlink()
    except (OSError, subprocess.CalledProcessError):
        pass


def worktree_tree():
    """Tree sha of the working tree as ``git add -A`` would stage it (gitignored files excluded)."""
    fd, index = tempfile.mkstemp(prefix="open-sdd-repair-index-")
    os.close(fd)
    try:
        env = dict(os.environ, GIT_INDEX_FILE=index)
        _git(["read-tree", "HEAD"], env=env)
        _git(["add", "-A"], env=env)
        return _git(["write-tree"], env=env).strip()
    finally:
        os.unlink(index)


def tracked_changes():
    """Tracked paths that differ from HEAD, staged or not."""
    return [p for p in _git(["diff", "--name-only", "-z", "HEAD"]).split("\0") if p]


def untracked_files():
    return [p for p in _git(["ls-files", "--others", "--exclude-standard", "-z"]).split("\0") if p]


def collect_changes(base, preexisting=()):
    """``{path: {status, removed, added}}`` from ``base`` to the working tree.

    Untracked files count as added, except ``preexisting`` ones (untracked before
    the loop opened — not part of the repair, and not worth reading).
    """
    before = set(preexisting)
    changes = {}
    for path, status in parse_name_status(_git(["diff", "--name-status", "-z", "--no-renames", base])).items():
        removed, added = parse_hunks(_git(["diff", "-U0", "--no-color", "--no-renames", base, "--", path]))
        changes[path] = {"status": status, "removed": removed, "added": added}
    for path in untracked_files():
        if path in before:
            continue
        try:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        changes[path] = {"status": "A", "removed": [], "added": text.splitlines()}
    return changes


def guard(base, preexisting=()):
    """Violations of the working tree against ``base``. Raises ValueError on an unknown ref."""
    from engine.conformance import is_test_file

    try:
        _git(["rev-parse", "--verify", "--quiet", base + "^{commit}"])
    except subprocess.CalledProcessError:
        raise ValueError("unknown ref {!r}".format(base))
    stack = _detect_stack()
    return violations(collect_changes(base, preexisting), lambda p: is_test_file(p, stack))


# ---------------------------------------------------------------------------
# Loop steps
# ---------------------------------------------------------------------------

def _print_violations(found):
    print("✗ Repair rejected — the change touches the metric:")
    for v in found:
        print("  - " + v)
    print("  Nothing is pushed while the repair is open. Revert those changes, or")
    print("  have a human decide (`python3 -m engine.cli repair-reset` drops the loop).")


def red():
    """check.sh failed. Opens the loop on the first failure. rc 0 = attempts left · 3 = exhausted."""
    state = load_state()
    if state is None:
        state = {"base": _git(["rev-parse", "HEAD"]).strip(), "attempts": 0,
                 "branch": current_branch(), "untracked_at_open": untracked_files(),
                 "checked_tree": worktree_tree(), "opened_at": datetime.now(timezone.utc).isoformat()}
        save_state(state)
        print("REPAIR_BASE={}".format(state["base"]))
        print("Repair loop opened — up to {} attempts.".format(MAX_ATTEMPTS))
        return 0
    state.pop("green_tree", None)
    state["checked_tree"] = worktree_tree()
    save_state(state)
    used = state.get("attempts", 0)
    print("REPAIR_BASE={}".format(state["base"]))
    if used >= MAX_ATTEMPTS:
        print("✗ check.sh still fails after {} repair attempts. Nothing was pushed.".format(used))
        print("  Review the changes by hand; `python3 -m engine.cli repair-reset` drops the loop once you have.")
        return 3
    print("Repair attempt {}/{} failed — {} left.".format(used, MAX_ATTEMPTS, MAX_ATTEMPTS - used))
    return 0


def pre():
    """Before running check.sh. Prints NONE | RUN_CHECK | SKIP_CHECK; rc 1 on a violation or exhausted loop."""
    state = load_state()
    if state is None:
        print("NONE")
        return 0
    found = guard(state["base"], state.get("untracked_at_open", []))
    if found:
        _print_violations(found)
        return 1
    tree = worktree_tree()
    step = next_step(state, tree)
    if step == "EXHAUSTED":
        print("✗ All {} repair attempts are used. Nothing was pushed.".format(MAX_ATTEMPTS))
        print("  Review the changes by hand; `python3 -m engine.cli repair-reset` drops the loop once you have.")
        return 1
    if step == "RUN_CHECK" and counts_attempt(state, tree):
        state["attempts"] = state.get("attempts", 0) + 1
        save_state(state)
    print(step)
    return 0


def green():
    """check.sh passed. rc 0 = loop closed (or none open) · 4 = commit the repair first · 1 = violation."""
    state = load_state()
    if state is None:
        return 0
    preexisting = state.get("untracked_at_open", [])
    found = guard(state["base"], preexisting)
    if found:
        _print_violations(found)
        return 1
    pending = uncommitted(tracked_changes(), untracked_files(), preexisting)
    if pending:
        state["green_tree"] = worktree_tree()
        save_state(state)
        print("✓ check.sh is green after repair attempt {}, but the repair is not committed:".format(
            state.get("attempts", 0)))
        for path in pending:
            print("  - " + path)
        print("  Stage them (new files included — /f-commit only stages tracked files) and")
        print("  commit with /f-commit, then re-run /f-mr:")
        print("    git add -- " + " ".join(shlex.quote(p) for p in pending))
        print("  This exact content will not be re-checked.")
        return 4
    clear_state()
    print("✓ Repair loop closed — check.sh green, guard clean.")
    return 0


def is_open():
    try:
        return load_state() is not None
    except Exception:
        return False


def run(cmd, args):
    """Entry point for ``engine.cli repair-<cmd>``."""
    try:
        if cmd == "guard" and len(args) == 1:
            try:
                found = guard(args[0])
            except ValueError as exc:
                print("✗ repair guard: {}".format(exc), file=sys.stderr)
                return 2
            if found:
                _print_violations(found)
                return 1
            print("✓ Repair guard: check.sh, test configs and existing tests untouched")
            return 0
        if cmd == "red" and not args:
            return red()
        if cmd == "pre" and not args:
            return pre()
        if cmd == "green" and not args:
            return green()
        if cmd == "reset" and not args:
            clear_state()
            print("Repair loop dropped.")
            return 0
        if cmd == "status" and not args:
            state = load_state()
            print(json.dumps(state) if state else "none")
            return 0
    except subprocess.CalledProcessError as exc:
        print("✗ repair: git failed: {}".format(exc), file=sys.stderr)
        return 2
    print("Usage: repair-red|repair-pre|repair-green|repair-reset|repair-status | repair-guard <base-ref>",
          file=sys.stderr)
    return 2
