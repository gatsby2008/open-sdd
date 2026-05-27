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

After the script finishes, read the generated source.md and the spec.md scaffold. Draft the initial content into the spec based on the user's input: fill in Summary, Scope (In/Out), Behavior, Implementation Context, Expected Change Scope, Safe Constraints, and at least one Open Question. Keep the spec structure intact. Then run ${OPENSDD_PATH}/commands/triage.sh <slug> to classify the ticket. Print the triage result (type, complexity, path, reason). Format links cleanly so the file path + line number are clickable: put the description separately, e.g. \`path/file.md:42\` — Open Questions section. Do NOT append text directly after the line number (e.g. avoid \`:42 <- OQ\`). Then STOP. Tell the user the spec is drafted. Note that the recommended path is advisory."
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
install_cmd "triage"        "Classify ticket complexity from spec and recommend pipeline path"

echo "open-sdd: 18 commands installed to $CMD_DIR"
echo ""

# Generate AGENTS.md with resolved OPEN_SDD_ROOT path
sed "s|\$OPEN_SDD_ROOT|$OPENSDD_PATH|g" "$OPENSDD_PATH/templates/AGENTS.md" > "$OPENCODE_DIR/AGENTS.md"
echo "Global AGENTS.md placed at $OPENCODE_DIR/AGENTS.md"

# ---- standalone skills (doc) slash commands ----------------------------------

for skill_dir in "$OPENSDD_PATH/skills/doc/"*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  first_line="$(head -1 "$skill_dir/SKILL.md" 2>/dev/null || true)"
  desc=""
  if [ "$first_line" = "---" ]; then
    desc="$(sed -n '3p' "$skill_dir/SKILL.md" 2>/dev/null | sed 's/^description: //')"
  fi
  [ -z "$desc" ] && desc="$skill_name skill"
  cat > "${CMD_DIR}/${skill_name}.md" <<EOF
---description: ${desc}---
View ${OPENSDD_PATH}/skills/doc/${skill_name}/SKILL.md and follow the instructions.
EOF
done
echo "doc skills (6) slash commands installed — available as /doc-adr, /doc-catalog, etc."

# ---- set environment variables ----
echo "export OPEN_SDD_ROOT=\"$OPENSDD_PATH\"" >> ~/.zshrc
echo "export OPEN_SDD_DOC_HOME=\"\${OPEN_SDD_ROOT:-\$HOME}/.opensdd/registry\"" >> ~/.zshrc
echo "OPEN_SDD_ROOT and OPEN_SDD_DOC_HOME exported to ~/.zshrc"

echo ""
echo "Re-run this script after moving open-sdd or adding new commands."
