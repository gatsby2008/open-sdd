#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSDD_PATH="$SCRIPT_DIR"
CMD_DIR="${HOME}/.config/opencode/commands"

mkdir -p "$CMD_DIR"

install_cmd() {
  local name="$1" description="$2"
  cat > "${CMD_DIR}/f-${name}.md" <<EOF
---description: ${description}---
Read ${OPENSDD_PATH}/agent/SDD_AGENT_INSTRUCTIONS.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${name}.sh \$ARGUMENTS
EOF
}

install_cmd_directive() {
  local name="$1" description="$2" directive="$3"
  cat > "${CMD_DIR}/f-${name}.md" <<EOF
---description: ${description}---
${directive}
EOF
}

install_cmd_directive "start" "Initialize SDD pipeline: branch + spec scaffold" "\
Read ${OPENSDD_PATH}/agent/SDD_AGENT_INSTRUCTIONS.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

Ask the user about branch choice using the suggested name (prefixed with 'feature/'), a custom name, or staying on the current branch. Once decided, run:

${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --branch <name>   # for a custom branch
${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS --keep            # to stay on current
${OPENSDD_PATH}/commands/start.sh \$ARGUMENTS                   # uses suggested branch

After the script finishes, STOP. Do NOT continue to /f-implement or /f-commit. Tell the user the spec is ready, they need to edit it and resolve Open Questions before proceeding."
install_cmd "plan"          "Discover target files and write implementation plan"
install_cmd "implement"     "Implement next focused change from the spec"
install_cmd "commit"        "Stage changes and generate semantic commit"
install_cmd "mr"            "Push branch and create merge request"
install_cmd "close"         "Clean .specwork and optionally delete feature branch"
install_cmd "status"        "Show pipeline state and next recommended step"
install_cmd "help"          "Show pipeline diagram and contextual next action"
install_cmd "pause"         "Pause pipeline and stash all work"
install_cmd "resume"        "List paused pipelines and restore selected one"
install_cmd "refine"        "Refine spec with additional context"
install_cmd "resync"        "Resync artifacts after branch rename"
install_cmd "review"        "Stack-aware code quality and security review"
install_cmd "review-address" "Work through MR review comments"
install_cmd "handoff"       "Package artifacts for another agent"
install_cmd "test-design"   "Design test cases for current changes"
install_cmd "test-impl"     "Implement test files for changed source"

echo "open-sdd: 17 commands installed to $CMD_DIR"
echo ""
echo "Re-run this script after moving open-sdd or adding new commands."
