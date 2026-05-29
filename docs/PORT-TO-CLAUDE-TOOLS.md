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
