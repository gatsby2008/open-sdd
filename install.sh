#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSDD_PATH="$SCRIPT_DIR"
CMD_DIR="${HOME}/.config/opencode/commands"
OPENCODE_DIR="${HOME}/.config/opencode"

mkdir -p "$CMD_DIR"

install_cmd() {
  local name="$1" description="$2"
  cat > "${CMD_DIR}/f-${name}.md" <<EOF
---description: ${description}---
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${name}.sh \$ARGUMENTS. After the command finishes, STOP. Present the result to the user and let them decide what to do next. Never chain multiple commands automatically.
EOF
}

install_cmd_directive() {
  local name="$1" description="$2" directive="$3"
  cat > "${CMD_DIR}/f-${name}.md" <<EOF
---description: ${description}---
${directive}
EOF
}

install_doc_cmd_directive() {
  local name="$1" description="$2" directive="$3"
  cat > "${CMD_DIR}/${name}.md" <<EOF
---description: ${description}---
${directive}
EOF
}

install_cmd_directive "start" "Initialize SDD pipeline: branch + source.md (spec.md is created by /f-spec)" "\
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

Ask the user about branch choice using the suggested name (prefixed with 'feature/'), a custom name, or staying on the current branch. Once decided, run:

${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --choose A        # create the suggested branch
${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --branch <name>   # for a custom branch
${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --keep            # to stay on current

After the script finishes, ${OPENSDD_PATH}/commands/start.sh has written source.md and state files but has NOT created spec.md. Tell the user the pipeline is initialized and recommend ${OPENSDD_PATH}/commands/spec.sh as the next step — /f-spec reads source.md plus templates/spec.md and generates spec.md from scratch (Summary, Scope, Behavior, Implementation Context, Expected Change Scope, Safe Constraints, Open Questions). Do NOT run triage yet — triage classifies the spec body, and spec.md does not exist until /f-spec creates it. Format links cleanly so file paths + line numbers are clickable: put the description separately, e.g. \`path/file.md:42\` — Open Questions section. Do NOT append text directly after the line number. Then STOP."
install_cmd "spec"          "Draft (first call) or refine (subsequent calls) the spec"
install_cmd "plan"          "Discover target files and write implementation plan"
install_cmd "implement"     "Implement next focused change from the spec"
install_cmd "commit"        "Stage changes and generate semantic commit"
install_cmd "mr"            "Push branch and create merge request"
install_cmd "close"         "Clean .specwork and optionally delete feature branch"
install_cmd_directive "auto" "Run full SDD pipeline non-interactively" "\
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

This command drives the entire pipeline non-interactively — no bash prompts.

1. Run: ${OPENSDD_PATH}/commands/auto.sh \$ARGUMENTS
   (\$ARGUMENTS is just the ticket key or free-text description — no flags.
   auto.sh runs f-start, f-spec, checks OQs, f-plan, f-implement in sequence.)
2. When auto.sh finishes, read the spec and plan it printed. Implement every target.
   After each target file is done, run: ${OPENSDD_PATH}/commands/implement.sh --done N
3. TEST GATE — only if auto.sh printed a 'RISK SIGNAL' block: after all targets
   are implemented and BEFORE commit, STOP and ask the user whether to run the
   test steps (they are token-costly). Run them ONLY with the user's go-ahead:
   ${OPENSDD_PATH}/commands/test-design.sh then ${OPENSDD_PATH}/commands/test-impl.sh
   If auto.sh reported no risk signal, skip this step silently.
4. Run: ${OPENSDD_PATH}/commands/commit.sh
5. Run: ${OPENSDD_PATH}/commands/mr.sh — then STOP.

Auto mode ends at the merge request. Do NOT run close.sh (it deletes the branch
and is a post-merge action) and do NOT run mr-address.sh (it needs human review
comments that do not exist yet). Both are human-gated steps after the MR is open.

All commands above have SDD_NON_INTERACTIVE=1 set, so they auto-confirm (branch
creation, commit message) without prompting. Only Open Questions block progression.

Do NOT ask the user for confirmation between steps — execute the flow through to
the open MR, then present the summary (MR link, branch, status) and hand control
back to the user for review/merge/close."
install_cmd "status"        "Show pipeline state and next recommended step"
install_cmd "help"          "Show pipeline diagram and contextual next action"
install_cmd "pause"         "Pause pipeline and stash all work"
install_cmd "resume"        "List paused pipelines and restore selected one"
install_cmd "undo"          "Discard uncommitted changes reversibly (pipeline or vibe coding); --restore to recover, --hard to discard"
install_cmd "resync"        "Resync artifacts after branch rename"
install_cmd "code-review"   "Stack-aware code quality and security review of your own branch"
install_cmd "mr-review"    "Stack-aware code quality and security review of a peer's branch or MR"
install_cmd "mr-address" "Work through MR review comments"
install_cmd "handoff"       "Package artifacts for another agent"
install_cmd "test-design"   "Design test cases for current changes"
install_cmd "test-impl"     "Implement test files for changed source"
install_doc_cmd_directive "doc-catalog" "Scan codebase and store the service catalog in the registry (list: /doc-catalog list)" "\
When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-catalog.sh list — it prints the catalog for the current repo's service. Stop after the list; do not scan the project.

Otherwise run ${OPENSDD_PATH}/commands/doc-catalog.sh . It scans the project, detects the stack and service, and prints instructions to generate the catalog and write it STRAIGHT to the registry — no copy in the repo (no docs/service-info.md), no confirmation prompt. Follow the printed instructions and print the stored registry path. Use --with-docs to also publish docs/architecture/, docs/features/, docs/product/ to the registry alongside the catalog."
install_doc_cmd_directive "doc-catalog-query" "Ask cross-service architecture questions" "\
Run ${OPENSDD_PATH}/commands/doc-catalog-query.sh \"\$ARGUMENTS\". It prints all registered documents (catalogs + any extra docs published with --with-docs). Use that output to answer the user's architecture question, citing the source file for every claim."
install_doc_cmd_directive "doc-adr" "Create an ADR and store it in the registry (list: /doc-adr list)" "\
When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-adr.sh list — it prints ADRs for the current repo's service. Stop after the list; do not create a new ADR.

Otherwise run ${OPENSDD_PATH}/commands/doc-adr.sh \$ARGUMENTS to find the next ADR number and gather context. Use the output to draft an ADR, then write it STRAIGHT to the registry — no copy in the repo (no docs/adr/), no confirmation prompt. Follow the printed instructions and print the stored registry path."
install_doc_cmd_directive "doc-adr-query" "Ask architecture-decision questions across ADRs" "\
Run ${OPENSDD_PATH}/commands/doc-adr-query.sh \$ARGUMENTS. It prints ADRs from the registry. Use that output to answer the user's question, citing every claim as <service>/<ADR-file>."
install_doc_cmd_directive "doc-spec" "Store a feature spec in the central spec registry (list: /doc-spec list)" "\
When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-spec.sh list — it prints specs for the current repo's service. Stop after the list.

Otherwise run ${OPENSDD_PATH}/commands/doc-spec.sh \$ARGUMENTS. It resolves the spec file (path argument or auto-detect from pipeline), detects the service, and prints instructions to store it in the registry. Counterpart to /f-mr (which stores automatically) — for hand-written or standalone specs."
install_doc_cmd_directive "doc-spec-query" "Ask feature/spec questions across the spec registry" "\
Run ${OPENSDD_PATH}/commands/doc-spec-query.sh \"\$ARGUMENTS\". It prints every spec stored by /doc-spec or /f-mr. Use that output to answer the user's feature/spec question (behavior, scope, constraints, open questions), citing every claim as <service>/<spec-file>."
install_doc_cmd_directive "doc-investigation" "Capture current investigation as a structured document (list: /doc-investigation list)" "\
When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-investigation.sh list — it prints investigations for the current repo's service. Stop after the list.

Otherwise run ${OPENSDD_PATH}/commands/doc-investigation.sh \$ARGUMENTS. It detects the service name, prints the matching investigation template (bug or exploration), and outputs instructions for the LLM to synthesize the session into a structured document. Print the full draft, then write it straight to the registry — no yes/no gate; the user can still interrupt to edit."
install_doc_cmd_directive "doc-investigation-query" "Answer questions across all captured investigations" "\
Run ${OPENSDD_PATH}/commands/doc-investigation-query.sh \"\$ARGUMENTS\". It lists investigation services, narrows scope by service name if possible, and prints every investigation file. Use that output to answer the user's question, citing every claim as <service>/<file>."
install_doc_cmd_directive "arch-query" "Query architecture design documents (set OPEN_SDD_ARCH_HOME to the architecture repo path)" "\
Run ${OPENSDD_PATH}/commands/arch-query.sh \"\$ARGUMENTS\". It reads architecture design documents from \$OPEN_SDD_ARCH_HOME (set this env var to the architecture repo path), lists available project areas, and narrows scope if a project area name matches the argument. Use the output to answer the user's architecture question. Cite every claim as the source file relative to the architecture repo. If OPEN_SDD_ARCH_HOME is not set, tell the user to set it."
# NOTE: triage is intentionally NOT registered as a /f-* command. It is an
# internal sub-step run by /f-spec (draft mode) via commands/triage.sh — see
# agent/PIPELINE.md ("Do NOT run triage here").

# Remove commands deregistered or renamed in newer versions (clean up stale installs).
rm -f "${CMD_DIR}/f-triage.md"
rm -f "${CMD_DIR}/f-refine.md"
# Clean up f-prefixed variants from earlier buggy installs.
rm -f "${CMD_DIR}/f-doc-adr.md" "${CMD_DIR}/f-doc-catalog.md" "${CMD_DIR}/f-doc-publish.md" "${CMD_DIR}/f-doc-query.md"
rm -f "${CMD_DIR}/f-adr-publish.md" "${CMD_DIR}/f-adr-query.md"
# doc-publish, adr-publish, spec-publish merged into doc-catalog, doc-adr, doc-spec.
rm -f "${CMD_DIR}/doc-publish.md" "${CMD_DIR}/adr-publish.md" "${CMD_DIR}/spec-publish.md"
# doc-query, adr-query, spec-query renamed to doc-catalog-query, doc-adr-query, doc-spec-query.
rm -f "${CMD_DIR}/doc-query.md" "${CMD_DIR}/adr-query.md" "${CMD_DIR}/spec-query.md"
# doc-freshness removed (regenerating with doc-catalog already reflects current code).
rm -f "${CMD_DIR}/doc-freshness.md"

echo "open-sdd: 29 commands installed to $CMD_DIR"

# ---------------------------------------------------------------------------
# Global SDD instructions file (avoids confusion with project-level AGENTS.md)
# Installed as ~/.config/opencode/instructions/sdd-pipeline.md and wired into
# opencode.json so opencode loads it across all sessions.
# ---------------------------------------------------------------------------
INST_DIR="${OPENCODE_DIR}/instructions"
mkdir -p "$INST_DIR"

# Pre-process: replace $OPEN_SDD_ROOT with the absolute path
sed "s|\$OPEN_SDD_ROOT|${OPENSDD_PATH}|g" \
  "${OPENSDD_PATH}/templates/pipeline-reference.md" \
  > "${INST_DIR}/sdd-pipeline.md"

echo "  SDD instructions: ${INST_DIR}/sdd-pipeline.md"

# Wire into opencode.json (create or update)
OPENCODE_CONFIG="${OPENCODE_DIR}/opencode.json"
if [ -f "$OPENCODE_CONFIG" ]; then
  # Add instructions field if not present
  python3 -c "
import json, sys
path = '${OPENCODE_CONFIG}'
with open(path) as f:
    cfg = json.load(f)
if 'instructions' not in cfg:
    cfg['instructions'] = ['instructions/sdd-pipeline.md']
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)
    print('  Config: added instructions to opencode.json')
else:
    ref = 'instructions/sdd-pipeline.md'
    if ref not in cfg['instructions']:
        cfg['instructions'].append(ref)
        with open(path, 'w') as f:
            json.dump(cfg, f, indent=2)
        print('  Config: appended instructions to opencode.json')
    else:
        print('  Config: instructions already present in opencode.json')
"
else
  cat > "$OPENCODE_CONFIG" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "instructions": ["instructions/sdd-pipeline.md"]
}
EOF
  echo "  Config: created opencode.json with instructions"
fi

# Clean up stale global AGENTS.md from older versions (now replaced by instructions/)
if [ -f "${OPENCODE_DIR}/AGENTS.md" ]; then
  # Only remove if it looks like an SDD file (contains "SDD Pipeline")
  if grep -q "SDD Pipeline" "${OPENCODE_DIR}/AGENTS.md" 2>/dev/null; then
    rm "${OPENCODE_DIR}/AGENTS.md"
    echo "  Cleanup: removed stale global AGENTS.md (replaced by instructions/sdd-pipeline.md)"
  fi
fi

echo ""
echo "============================================"
echo "  open-sdd requirements check"
echo "============================================"
echo "  git:    $(git --version 2>/dev/null || echo 'NOT FOUND — install git')"
echo "  bash:   $(bash --version 2>/dev/null | head -1 || echo 'NOT FOUND — install bash >= 4.x')"
echo "  python: $(python3 --version 2>/dev/null || echo 'NOT FOUND — install python >= 3.9')"
echo "  gh:     $(gh --version 2>/dev/null | head -1 || echo 'optional — install for auto MRs')"
echo ""
echo "  Project toolchain: detected by commands/check.sh per project"
echo "  Jira:              set JIRA_BASE_URL, JIRA_USER, JIRA_TOKEN (optional)"
echo ""
echo "  Windows users: run from WSL2 (recommended) or Git Bash"
echo "============================================"

echo ""
echo "Re-run this script after moving open-sdd or adding new commands."
