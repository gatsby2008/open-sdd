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
Read ${OPENSDD_PATH}/agent/SDD_AGENT_INSTRUCTIONS.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${name}.sh \$ARGUMENTS. After the command finishes, STOP. Present the result to the user and let them decide what to do next. Never chain multiple commands automatically.
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

After the script finishes, read the generated source.md and the spec.md scaffold. Draft the initial content into the spec based on the user's input: fill in Summary, Scope (In/Out), Behavior, Implementation Context, Expected Change Scope, Safe Constraints, and at least one Open Question. Keep the spec structure intact. Then STOP. Tell the user the spec is drafted and they can edit it or resolve Open Questions before proceeding."
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
install_cmd "code-review"   "Stack-aware code quality and security review"
install_cmd "review-address" "Work through MR review comments"
install_cmd "handoff"       "Package artifacts for another agent"
install_cmd "test-design"   "Design test cases for current changes"
install_cmd "test-impl"     "Implement test files for changed source"

echo "open-sdd: 17 commands installed to $CMD_DIR"
echo ""
echo "Re-run this script after moving open-sdd or adding new commands."
