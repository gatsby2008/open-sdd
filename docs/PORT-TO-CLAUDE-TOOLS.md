# Port to claude-tools — session changes (2026-05-29)

Changes made in **open-sdd** this session and whether/how each ports to
**claude-tools** (`~/team/Yield/claude-tools/contrib/skills/sdd/`).

claude-tools is Python + Markdown skills; open-sdd is bash wrappers + a Python
engine. So most fixes need re-expression, not copy-paste.

| # | Change | Ports to claude-tools? | Target |
|---|--------|------------------------|--------|
| 1 | `reference_grep` over-fire fix (3 guards) | **YES — port it** | `lib/f-plan.py:reference_grep` + `lib/tests/test_f_plan.py` |
| 2 | `/f-resume` re-stages `.specwork/` | **N/A — confirmed** | `f-resume/SKILL.md` |
| 3 | Deregister `/f-triage` user command | **N/A — already internal** | — |
| 4 | Cosmetic `/f-*` hints (vs `./commands/X.sh`) | **N/A — skill prose already uses `/f-*`** | — |
| 5 | Add `CLAUDE.md` | **N/A — open-sdd specific** | — |
| 6 | Vibe-coding doc + "handoff is not independent" README fix | **Optional doc only — claude-tools already correct** | `contrib/skills/sdd/VIBE-CODING.md` (new, optional) |
| 7 | `detect_stack` distinguishes `frontend` from `node` | **YES — port it** | `engine/gates.py` + `lib/gates.py` (both) + tests |

---

## 1. reference_grep over-fire fix — PORT THIS

### Problem
A small, focused spec (MYYES-15518: "fix duplicate `@AssertTrue`, sanitize PII")
generated **56 plan targets** in open-sdd — 53 of them false-positive
`[reference-update]` entries. Root causes:

1. **Negated lines seed symbols.** The Safe Constraint line
   *"Do NOT remove or modify the `@Size` constraint on `phoneNumber`"* contains
   the trigger word "remove", so the heuristic extracted `@Size` and
   `phoneNumber` — the exact symbols it was told **not** to touch.
2. **No per-symbol hit cap.** A generic token (`phoneNumber` → 48 files,
   `@Size` → 8) is grepped repo-wide and every match becomes a target.
3. (open-sdd specific) The whole `## Safe Constraints` section was scanned.

claude-tools' `reference_grep` (`lib/f-plan.py:76`) has the **same flaws**. It
caps total refs at `[:10]`, so it produces ≤10 false positives instead of 56 —
less catastrophic, but still wrong (10 unrelated files flagged for a 3-file
change).

### Fix — three guards
1. **Skip the `## Safe Constraints` section** entirely (it documents what to
   preserve).
2. **Skip negated lines** anywhere (`not / never / keep / preserve / unchanged
   / n't / ...`).
3. **Per-symbol hit cap** — drop a symbol whose grep matches more than N files
   (default 8); it's a generic name, not a targeted rename.

### open-sdd implementation (reference)
`commands/plan.sh` — function `extract_reference_targets` (guards 1+2) and the
loop's `REF_HIT_CAP` check (guard 3). Tunable via `OPEN_SDD_REF_HIT_CAP`.

### claude-tools patch — `lib/f-plan.py:reference_grep`
Replace the symbol-extraction loop and add the hit cap (ensure `import os` at
top of file):

```python
def reference_grep(spec_text):
    """Grep the codebase for concrete symbols the spec says to rename/remove/replace.

    Guards against over-matching (the 2026-05-29 consumer-portal blow-up):
      1. Skip the "## Safe Constraints" section — documents what to PRESERVE.
      2. Skip negated lines ("Do NOT remove the `@Size` constraint").
      3. Cap hits per symbol — a generic token matching many files is not a
         targeted rename.
    """
    trigger = re.compile(
        r"\b(renam\w*|remov\w*|delet\w*|deprecat\w*|replac\w*|migrat\w*|drop)\b",
        re.IGNORECASE,
    )
    negation = re.compile(
        r"\b(?:not|never|without|keep|keeps|keeping|kept|preserv\w*|retain\w*|"
        r"maintain\w*|unchanged|untouched|intact)\b|n't",
        re.IGNORECASE,
    )
    symbols = set()
    in_safe_constraints = False
    for line in spec_text.splitlines():
        m = re.match(r"^\s*##\s+(.*)", line)
        if m:
            in_safe_constraints = m.group(1).strip().lower().startswith("safe constraints")
            continue
        if in_safe_constraints:
            continue
        if not trigger.search(line):
            continue
        if negation.search(line):           # guard 2
            continue
        symbols.update(re.findall(r"`([^`]+)`", line))
        symbols.update(re.findall(r"(/\w[\w/_-]*)", line))

    candidates = [s for s in symbols if len(s) >= 3][:10]
    if not candidates:
        return []

    hit_cap = int(os.environ.get("CLAUDE_TOOLS_REF_HIT_CAP", "8"))  # guard 3
    refs = set()
    source_exts = (".java", ".kt", ".ts", ".tsx")
    for term in candidates:
        try:
            result = subprocess.run(
                ["grep", "-rlF", term, "src/"],
                capture_output=True, text=True, check=False, timeout=15,
            )
            hits = [l.strip() for l in result.stdout.splitlines()
                    if l.strip().endswith(source_exts)]
            if len(hits) > hit_cap:          # guard 3: too generic
                continue
            refs.update(hits)
        except Exception:
            pass

    return sorted(refs)[:10]
```

Only the loop body changed (guards 1+2) plus the `hit_cap` filter (guard 3). The
trigger regex and `[:10]` caps are left as claude-tools had them.

> **Divergence to decide:** open-sdd added `legacy|retire` to the trigger regex;
> claude-tools does not have them. Not part of this fix — port only if you want
> the broader trigger.

### claude-tools tests — add to `lib/tests/test_f_plan.py`
Mirror open-sdd's `tests/smoke.sh` "reference-update guards" block:

- `test_skips_symbols_in_safe_constraints_section` — a `## Safe Constraints`
  body with `` `@Size` `` must yield no candidate for `@Size`.
- `test_skips_negated_remove_line` — `"Do NOT remove the \`@Size\` constraint"`
  yields no `@Size`.
- `test_hit_cap_skips_generic_symbol` — create >cap source files containing a
  token, set `CLAUDE_TOOLS_REF_HIT_CAP` low, assert that token produces no refs
  while a legit single-file removal still does.

(The existing `test_finds_real_reference_on_rename` at line 36 already covers
the positive case and must still pass.)

---

## 2. /f-resume re-stages `.specwork/` — N/A (confirmed by repro)

### Problem (open-sdd)
`/f-pause` did `git add -f .specwork/` then `git stash push`. Because the
`.specwork/` files were **new entries in the index** at stash time, `git stash
pop` restored them **staged**. `.specwork/` is gitignored transient state and
must never be staged/committed.

### open-sdd fix
`commands/resume.sh` — after `git stash pop`, unstage:
```bash
if [ -d ".specwork" ]; then
  git reset -q -- .specwork/ 2>/dev/null || true
fi
```

### claude-tools status
`f-pause/SKILL.md` uses **`git stash push --all`** (no `git add -f`).
Files captured via `--all` are stashed as untracked/ignored and `git stash pop`
restores them **ignored**, not staged — so claude-tools does **not** reproduce
the bug. **Verified** with the repro below (`.specwork/` came back `!!` ignored,
nothing staged). No change needed.

Repro (run in a scratch repo):
```bash
git init -q; echo ".specwork/" > .gitignore; git add .gitignore; git commit -qm init
mkdir -p .specwork/_state; echo '{}' > .specwork/_state/x-state.json
git stash push --all -m "f-pause: feature/x"
git stash pop
git status --short --ignored   # → "!! .specwork/" (ignored), NOT "A  .specwork/..."
```

> **Reverse insight for open-sdd:** the cleaner root-cause fix would be to make
> open-sdd's `pause.sh` use `git stash push --all` like claude-tools, instead of
> `git add -f` + unstage-on-resume. Current open-sdd fix (unstage on resume)
> works; this is a possible future simplification.

---

## 3. Deregister `/f-triage` — N/A (already correct in claude-tools)

open-sdd's `install.sh` registered `/f-triage` as a user command, but triage is
an internal sub-step of `/f-spec` (draft mode). Removed the registration; kept
`commands/triage.sh`.

claude-tools has **no `f-triage` skill dir** — triage lives in `lib/triage.py` /
`engine/triage.py` and is invoked internally (see `f-start/SKILL.md`). Already
correct; nothing to port.

---

## 4. Cosmetic `/f-*` hints — N/A

open-sdd's bash scripts printed `./commands/spec.sh`, `bash commands/...` in
user-facing output; converted to `/f-spec` etc. (kept agent-execution
instructions as script paths). claude-tools skills are Markdown prose that
already reference `/f-*`. Nothing to port.

---

## 5. CLAUDE.md — N/A

Added a `CLAUDE.md` to open-sdd describing its bash↔engine architecture.
claude-tools already has its own `CLAUDE.md`. open-sdd specific.

---

## 6. Vibe-coding doc + "handoff is not independent" fix — OPTIONAL DOC ONLY

### What open-sdd did
- Added `docs/VIBE-CODING.md` — a consolidated guide to the three **standalone**
  commands usable without a pipeline: `/f-commit`, `/f-mr`, `/f-code-review`
  (loop: branch → code-review → commit → mr; what you give up; when to graduate
  to the full pipeline).
- Fixed open-sdd's `README.md`, which **wrongly** listed `/f-handoff` under
  "INDEPENDENT". `handoff` requires the pipeline (it packages
  `.specwork/_state`, `spec.md`, `plan.md`, `_progress/`). Removed it from that
  list and added a vibe-coding pointer.

### claude-tools status — already correct, nothing to fix
Verified in `contrib/skills/sdd/`:
- `f-commit/SKILL.md` — *"works in SDD pipeline, vibe coding, and git-only
  workflows"*.
- `f-mr/SKILL.md` — has explicit **pipeline mode (2A)** vs **standalone mode
  (2B)**; *"If `.specwork` artifacts are missing, generate from git history
  only."*
- `f-code-review/SKILL.md` — *"Run from the active pipeline branch, or any
  current branch when reviewing outside SDD."*
- `f-handoff/SKILL.md` — *"`/f-handoff` requires all of these:
  `.specwork/_state/...`, `spec.md`, `plan.md`, `_progress/...-context.md`"* —
  correctly pipeline-only.
- `contrib/skills/sdd/README.md` "INDEPENDENT" block lists **only** `/f-commit`,
  `/f-mr`, `/f-code-review` (+ doc/adr commands). It does **not** list
  `/f-handoff`. So the open-sdd README bug was a **regression** open-sdd
  introduced; claude-tools never had it.

### Optional port
The only thing claude-tools lacks is a **single consolidated vibe-coding guide**.
The standalone behavior is already implemented and documented per-skill, so this
is documentation polish, not a fix. If wanted, add
`contrib/skills/sdd/VIBE-CODING.md` mirroring open-sdd's (adjust paths/wording to
claude-tools' skill layout). No code changes needed.

---

## 7. detect_stack: distinguish `frontend` from `node` — PORT THIS

### Problem
claude-tools' `detect_stack()` (in **both** `engine/gates.py:124` and
`lib/gates.py:128`) returns only `java` / `node` / `unknown`. A React/Vue/Angular
app resolves to **`node`**, even though several skills already write `frontend`
in their prose (`f-code-review`, `f-test-impl`, `f-help`, `f-commit`, `f-spec`).
So the deterministic plan/test logic treats UI repos as generic Node backends —
missing component/RTL/Storybook/a11y handling. This is the "UI gap".

### What open-sdd did (the fix to port)
`engine/gates.py:detect_stack()` now returns `frontend` when, alongside
`package.json`, it finds a frontend framework **config file** or a frontend
framework **dependency**. All consumers route `frontend` specially:
`plan.sh` (React/Vue error boundaries, component/page/hook discovery),
`test-design.sh` (RTL + MSW + Storybook + Playwright), `test-impl.sh`
(`stack in ("node","frontend")`), `code-review.sh` (a11y / React-Vue patterns /
state-management focus). Unit tests added in `tests/test_gates.py`.

### claude-tools patch — apply to BOTH `engine/gates.py` and `lib/gates.py`
Replace the `package.json → node` line with:

```python
def detect_stack(project_dir: str = ".") -> str:
    root = Path(project_dir)
    if any((root / f).exists() for f in ["build.gradle", "build.gradle.kts", "pom.xml"]):
        return "java"
    if not (root / "package.json").exists():
        return "unknown"
    frontend_configs = [
        "vite.config.ts", "vite.config.js", "vite.config.mjs",
        "next.config.js", "next.config.ts", "next.config.mjs",
        "angular.json", "svelte.config.js", "nuxt.config.ts",
        "nuxt.config.js", "vue.config.js", "remix.config.js",
        "astro.config.mjs",
    ]
    if any((root / f).exists() for f in frontend_configs):
        return "frontend"
    try:
        import json
        pkg = json.loads((root / "package.json").read_text(encoding="utf-8"))
        deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
        frontend_kw = {"react", "vue", "@angular/core", "svelte", "preact", "solid-js", "lit"}
        if frontend_kw & set(deps.keys()):
            return "frontend"
    except Exception:
        pass
    return "node"
```

### Follow-up audit in claude-tools (important)
Once `detect_stack` can emit `frontend`, make sure the **deterministic
consumers** handle it (the skills' prose already does). In particular
`lib/f-plan.py` — check `resolve_test_path` / mock-consumer / reference-grep
extension filters and group `frontend` with `node` (mirror open-sdd's
`node|frontend)` cases) so `frontend` does not silently fall through to a
java/unknown default.

### Tests — add to claude-tools test suite (mirror `tests/test_gates.py`)
- `frontend` via config file (`vite.config.ts` next to `package.json`).
- `frontend` via dependency (`{"dependencies": {"react": "..."}}`).
- backend-only deps (`express`) stays `node`.
- polyglot `build.gradle` + `package.json` resolves to `java` (precedence).
