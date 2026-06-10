# open-sdd Setup — Per-Project, One-Time Config & Requirements

Everything you configure once. For the flow and commands see
[pipeline.md](pipeline.md); for the concepts see [concepts.md](concepts.md).

---

## Per-project setup

In each consumer project where you want to use the pipeline:

1. Install open-sdd globally (see [Install](../README.md#install) in the README).
2. *(Recommended)* Run `/init` inside the project so opencode creates a project-level `AGENTS.md` with build commands, architecture, and conventions.

The first `/f-start` auto-bootstraps `.opensdd/service-rules.md` and
`.opensdd/mr-config.json` in the project.

> **How instructions are loaded.** opencode loads **two separate sources** without conflict:
> - **Global instructions** (`~/.config/opencode/instructions/sdd-pipeline.md`) — installed by `install.sh` with the SDD pipeline rules and command mappings. Referenced from `opencode.json` via the `instructions` field.
> - **Project memory** (`<project>/AGENTS.md`) — created by `/init` with project-specific guidance (build commands, architecture, conventions).
>
> The global file tells the model how to run the pipeline. The project file tells it how your codebase is structured. They complement each other. `/init` never touches the global instructions, and if a project `AGENTS.md` already exists, `/init` improves it in place.
>
> **Note on auto-generation:** Some proactive models (Sonnet, Opus, GPT-4) may auto-create an `AGENTS.md` at startup if none exists. This is the model's behavior, not opencode's. If you prefer to control when and how it's generated, run `/init` manually.

---

## One-Time Setup

### Jira REST credentials (optional but recommended)

```zsh
export JIRA_BASE_URL="https://your-company.atlassian.net"
export JIRA_USER="your.email@company.com"
export JIRA_TOKEN="your-atlassian-api-token"
```

Without Jira credentials, `/f-start` falls back to free-text input.

### `.specwork/` is gitignored

`.specwork/` is **transient runtime state** — spec drafts, plan, cache, escalation
log — and must never be committed. The permanent artifacts are the commits, the
published spec (`docs/specs/<slug>-spec.md`, if `/f-mr` publishes it), and any
ADRs.

`/f-start` enforces this automatically: on first run in a project it appends
`.specwork/` to `.gitignore` (or creates `.gitignore` if missing). If files were
already tracked from a prior setup, it warns with the exact `git rm --cached`
command to untrack them.

`.opensdd/` (the per-project config directory — `mr-config.json`,
`service-rules.md`) **is** committed.

### MR config

Project config (`.opensdd/mr-config.json`, commit this):

```json
{
  "target_branch": "development",
  "merge_strategy": "squash"
}
```

### Validation script (`commands/check.sh`)

`/f-commit` and `/f-mr` run `bash commands/check.sh` as the quality gate
before committing and pushing. The pipeline treats `exit 0` as clean and
any non-zero exit as a stop signal.

open-sdd ships a **stack-detecting default** at
`$OPEN_SDD_ROOT/commands/check.sh`. It inspects the project root and runs
the standard command for the detected stack:

| Detected file | Command run |
|---|---|
| `build.gradle` / `build.gradle.kts` | `./gradlew check` |
| `pom.xml` | `mvn verify` |
| `package.json` + `pnpm-lock.yaml` | `pnpm test` |
| `package.json` + `yarn.lock` | `yarn test` |
| `package.json` (npm) | `npm test` |
| `Cargo.toml` | `cargo test` |
| `pyproject.toml` / `setup.py` / `setup.cfg` | `pytest` |
| `go.mod` | `go test ./...` |

For most projects this is enough — no setup required.

**Project-local override.** When the framework default is not enough (e.g.
Spring Boot with a separate `integrationTest` source set, Maven with
profiles, monorepos that chain multiple commands, lint/format steps not
wired into the default lifecycle), drop a script at `commands/check.sh` in
the project root and `/f-commit` and `/f-mr` will prefer it over the
framework default. A template ships with open-sdd:

```bash
# from the project root
mkdir -p commands
cp "$OPEN_SDD_ROOT/templates/check.sh.example" commands/check.sh
git add commands/check.sh
git commit -m "chore: add commands/check.sh for project-specific validation"
```

What the override *should* do:

- Run the same commands CI runs (unit + integration + lint + format).
- Exit non-zero on any failure (`set -euo pipefail` at the top handles this).
- Stay reproducible — no network, no cache reliance, no randomness.

What it *should not* do:

- Talk to remote services (Jira, Slack, deploy endpoints).
- Mutate working state (no commits, no `git push`, no schema migrations).
- Run optional/slow workflows that aren't in CI.

**Windows:** the file is bash. Run it through Git Bash or WSL2; the Gradle
/ Maven / npm CLIs invoked inside work identically from those shells.

### Service rules (optional but recommended)

Copy `templates/service-rules.md` to `.opensdd/service-rules.md` and
document service-level invariants: business rules, fallback behavior,
architecture constraints, historical guarantees.

`/f-start` reads both `rules.md` (open-sdd global rules) and
`.opensdd/service-rules.md` (per-project invariants) and compiles them
into `.specwork/_state/<slug>-rules.json`.

### Doc registry (optional)

open-sdd bundles doc commands (`/doc-adr`, `/doc-catalog`, `/doc-publish`,
`/doc-query`, `/adr-publish`, `/adr-query`) that publish and query a
central registry of service catalogs and ADRs. The registry location is
controlled by:

```bash
export OPEN_SDD_DOC_HOME=/path/to/shared/registry
```

Default: `${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/`.

---

## Requirements

### Required

| Tool | Version | Why | Windows | macOS | Linux |
|------|---------|-----|---------|-------|-------|
| **LLM client** | Latest | Interprets `/f-*` commands, runs LLM inference | Varies by client | Varies by client | Varies by client |
| **git** | >= 2.x | All version control | Git Bash or WSL2 | Built-in | Built-in |
| **Bash** | >= 4.x | All pipeline scripts (`commands/*.sh`) | Git Bash or WSL2 | Built-in | Built-in |
| **Python** | >= 3.9 | Engine layer (`engine/`) | python.org or WSL2 | Built-in | Built-in |

**Install an LLM client:** the pipeline commands require an LLM client that
supports custom slash commands. Choose your preferred client and follow its
installation instructions.

### Optional

| Tool | When you need it | Install (macOS) | Install (Windows) |
|------|-----------------|-----------------|-------------------|
| **GitHub CLI (`gh`)** | Auto MR creation + merge checks | `brew install gh` | `winget install GitHub.cli` |
| **GitLab CLI (`glab`)** | Auto MR on self-hosted GitLab | `brew install glab` | `winget install glab` |
| **jq** | Jira JSON parsing | `brew install jq` | `winget install jqlang.jq` |

### Project toolchain (required by `check.sh`)

The quality gate auto-detects your project stack and runs its test command:

| Detected file | Command run | You need |
|---------------|-------------|----------|
| `build.gradle` / `build.gradle.kts` | `./gradlew check` | Java (Gradle wrapper is bundled) |
| `pom.xml` | `mvn verify` | Java + Maven |
| `package.json` + `pnpm-lock.yaml` | `pnpm test` | Node.js + pnpm |
| `package.json` + `yarn.lock` | `yarn test` | Node.js + Yarn |
| `package.json` (npm) | `npm test` | Node.js + npm |
| `pyproject.toml` / `setup.py` | `pytest` | Python + deps |
| `Cargo.toml` | `cargo test` | Rust + Cargo |
| `go.mod` | `go test ./...` | Go |

---

## Windows

The pipeline runs on bash scripts. Two options:

### Option A — WSL2 (recommended)

Full Linux environment inside Windows. Everything works natively.

```powershell
# 1. Install WSL2 with Ubuntu (run in PowerShell as Admin)
wsl --install

# 2. Restart your machine, then open the "Ubuntu" terminal

# 3. Inside Ubuntu, update packages
sudo apt update && sudo apt upgrade -y

# 4. Clone open-sdd
git clone <repo-url> ~/team/Yield/open-sdd

# 5. Run installer
cd ~/team/Yield/open-sdd && bash install.sh
```

After install, always work from inside the Ubuntu terminal (open via Start menu
or `wsl -d Ubuntu -e bash` from PowerShell). The pipeline, git, and your LLM client all
run inside WSL2.

**Optional tools inside WSL2:**

```bash
# GitHub CLI — auto MR creation
sudo apt install gh

# GitLab CLI — auto MR on self-hosted GitLab
sudo apt install glab    # or: brew install glab (if Homebrew on Linux is set up)
```

> **WSL2 + Windows drives:** Access your Windows files at `/mnt/c/`. Clone repos
> into the Linux filesystem (`~/team/...`) for best performance — `/mnt/c/`
> is noticeably slower for git operations.

### Option B — Git Bash

Runs bash scripts without WSL2. Some commands (e.g. `glab mr diff`) may need
adjustments.

```powershell
# 1. Install Git for Windows (comes with Git Bash)
#    Download from https://git-scm.com/download/win

# 2. Install Python 3.9+
#    Download from https://python.org/downloads/
#    Check "Add Python to PATH" during install

# 3. Install an LLM client (choose one that supports custom slash commands)

# 4. Clone open-sdd
#    Open Git Bash (Start menu → Git Bash)
git clone <repo-url> ~/team/Yield/open-sdd

# 5. Run installer from Git Bash (not CMD, not PowerShell)
cd ~/team/Yield/open-sdd
bash install.sh
```

**Important:** Some LLM clients default to PowerShell on Windows. When a
command prints a clickable path like `/home/user/repo/file:42`, PowerShell won't
recognise it. Either:
- Use WSL2 (option A) for full compatibility, or
- Configure your LLM client to launch Git Bash as its shell backend

**Optional tools (Git Bash):**

```powershell
# GitHub CLI — auto MR creation
winget install GitHub.cli

# GitLab CLI — auto MR on self-hosted GitLab (needed by /f-mr-review MR mode)
winget install glab
```

### Verify installation (both options)

```bash
# Inside bash (WSL2 or Git Bash), run these checks:
git --version          # should show >= 2.x
bash --version         # should show >= 4.x
python3 --version      # should show >= 3.9
gh --version           # optional, for /f-mr on GitHub
glab version           # optional, for /f-mr on GitLab + /f-mr-review MR mode
```

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| `bash: command not found` | You're in CMD or PowerShell. Open Git Bash or the Ubuntu terminal. |
| `python3: command not found` | Install Python and add it to PATH (Git Bash) or `sudo apt install python3` (WSL2). |
| `install.sh: line X: syntax error` | You're running with CMD/PowerShell. Use `bash install.sh` from **Git Bash** or the Ubuntu terminal. |
| `glab: command not found` | `winget install glab` (Git Bash) or `sudo apt install glab` (WSL2). Fallback: pass branch names to `/f-mr-review` instead of MR links. |
| Git operations are slow | You cloned on `/mnt/c/` (Windows drive). Re-clone inside the Linux filesystem (`~/team/`). |
| LLM client can't find bash | Point your client's shell setting to the full path of `bash.exe` (Git Bash: `C:\Program Files\Git\bin\bash.exe`) or use the WSL2 terminal. |

---

## Structure

```
open-sdd/
├── agent/
│   └── PIPELINE.md   # System prompt for any LLM
├── lib/
│   ├── gates.sh                     # Validation gates
│   ├── jira.sh                      # Jira REST client via curl
│   ├── non_interactive.sh          # SDD_NON_INTERACTIVE helpers
│   ├── service-name.sh             # Service-name resolution
│   └── spec-publish.sh             # Spec-registry publish helper
├── commands/                        # 31 scripts (29 user-facing commands + internal helpers)
│   ├── auto.sh
│   ├── check.sh                     # Validation-gate runner (internal helper)
│   ├── close.sh
│   ├── code-review.sh
│   ├── commit.sh
│   ├── handoff.sh
│   ├── help.sh
│   ├── implement.sh
│   ├── mr-address.sh
│   ├── mr-review.sh
│   ├── mr.sh
│   ├── pause.sh
│   ├── plan.sh
│   ├── resume.sh
│   ├── resync.sh
│   ├── spec.sh                      # Draft / refine spec
│   ├── spec-publish.sh
│   ├── spec-query.sh
│   ├── start.sh
│   ├── status.sh
│   ├── test-design.sh
│   ├── test-impl.sh
│   ├── triage.sh                    # Internal — classifies the spec (run by /f-spec)
│   ├── undo.sh
│   ├── doc-catalog.sh               # doc/adr commands (9)
│   ├── doc-publish.sh
│   ├── doc-query.sh
│   ├── doc-freshness.sh
│   ├── doc-adr.sh
│   ├── adr-publish.sh
│   └── adr-query.sh
├── templates/
│   ├── rules.md                     # Global pipeline rules (compiled at /f-start)
│   ├── service-rules.md             # Per-project invariants (copy to .opensdd/)
│   ├── rules.json                   # Rules schema template
│   ├── spec.md                      # Spec scaffold template
│   ├── mr-config.json               # MR config template
│   ├── pipeline-reference.md        # Global SDD instructions (installed to opencode)
│   └── check.sh.example             # Project-local validation-script template
└── install.sh                       # Register /f-* commands as custom commands
```