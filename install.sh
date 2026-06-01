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

install_doc_cmd() {
  local name="$1" description="$2"
  cat > "${CMD_DIR}/${name}.md" <<EOF
---description: ${description}---
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${name}.sh \$ARGUMENTS. After the command finishes, STOP. Present the result to the user and let them decide what to do next. Never chain multiple commands automatically.
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

${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --branch <name>   # for a custom branch
${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --keep            # to stay on current
${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS                   # uses suggested branch

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
install_cmd "resync"        "Resync artifacts after branch rename"
install_cmd "code-review"   "Stack-aware code quality and security review of your own branch"
install_cmd "mr-review"    "Stack-aware code quality and security review of a peer's branch or MR"
install_cmd "mr-address" "Work through MR review comments"
install_cmd "handoff"       "Package artifacts for another agent"
install_cmd "test-design"   "Design test cases for current changes"
install_cmd "test-impl"     "Implement test files for changed source"
install_doc_cmd_directive "doc-catalog" "Scan codebase and generate/update docs/service-info.md" "\
Run ${OPENSDD_PATH}/commands/doc-catalog.sh \$ARGUMENTS to scan the project and produce structured findings, then use those findings to generate or update docs/service-info.md. Ask the user for confirmation before writing."
install_doc_cmd_directive "doc-publish" "Publish service catalog to central registry" "\
Run ${OPENSDD_PATH}/commands/doc-publish.sh \$ARGUMENTS. If the argument is 'list', print the registered catalogs. Use --with-docs to also publish docs/architecture/, docs/features/, docs/product/ alongside the catalog."
install_doc_cmd_directive "doc-query" "Ask cross-service architecture questions" "\
Run ${OPENSDD_PATH}/commands/doc-query.sh \"\$ARGUMENTS\". It prints all registered documents (catalogs + any extra docs published with --with-docs). Use that output to answer the user's architecture question, citing the source file for every claim."
install_doc_cmd_directive "doc-adr" "Create an Architecture Decision Record" "\
Run ${OPENSDD_PATH}/commands/doc-adr.sh \$ARGUMENTS to find the next ADR number and gather context. Use the output to draft an ADR, confirm with the user, write to docs/adr/, and offer to commit."
install_doc_cmd_directive "adr-publish" "Publish ADRs to central registry" "\
Run ${OPENSDD_PATH}/commands/adr-publish.sh \$ARGUMENTS. If the argument is 'list', print the registered ADRs. Otherwise sync docs/adr/*.md to the central registry."
install_doc_cmd_directive "adr-query" "Ask architecture-decision questions across ADRs" "\
Run ${OPENSDD_PATH}/commands/adr-query.sh \$ARGUMENTS. It prints ADRs from the registry. Use that output to answer the user's question, citing every claim as <service>/<ADR-file>."
install_doc_cmd_directive "doc-freshness" "Check docs for drift against code" "\
Run ${OPENSDD_PATH}/commands/doc-freshness.sh \$ARGUMENTS. It scans the repo's docs/ folder and compares claims against the actual code — version numbers, endpoint paths, link validity, staleness. Use the drift report to answer the user's question. Propose specific fixes for each drift item."
install_doc_cmd_directive "spec-query" "Ask questions about product specs" "\
Run ${OPENSDD_PATH}/commands/spec-query.sh \"\$ARGUMENTS\". It reads product specs from the registry (product-spec.md, gap-analysis.md, feature-inventory.md). Use the output to answer the user's product/spec question, citing the source file for every claim."
install_doc_cmd_directive "sec-query" "Ask questions about security docs" "\
Run ${OPENSDD_PATH}/commands/sec-query.sh \"\$ARGUMENTS\". It reads security docs from the registry (security-report.md, gl-*-report*.json). Use the output to answer the user's security question, citing the source file for every claim."
# NOTE: triage is intentionally NOT registered as a /f-* command. It is an
# internal sub-step run by /f-spec (draft mode) via commands/triage.sh — see
# agent/PIPELINE.md ("Do NOT run triage here").

# Remove commands deregistered or renamed in newer versions (clean up stale installs).
rm -f "${CMD_DIR}/f-triage.md"
rm -f "${CMD_DIR}/f-refine.md"
# Clean up f-prefixed variants from earlier buggy installs.
rm -f "${CMD_DIR}/f-doc-adr.md" "${CMD_DIR}/f-doc-catalog.md" "${CMD_DIR}/f-doc-publish.md" "${CMD_DIR}/f-doc-query.md"
rm -f "${CMD_DIR}/f-adr-publish.md" "${CMD_DIR}/f-adr-query.md"

echo "open-sdd: 28 commands installed to $CMD_DIR"

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
