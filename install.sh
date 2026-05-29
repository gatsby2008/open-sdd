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

install_cmd_directive "start" "Initialize SDD pipeline: branch + source.md (spec.md is created by /f-spec)" "\
Read ${OPENSDD_PATH}/agent/SDD_AGENT_INSTRUCTIONS.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

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
install_cmd "status"        "Show pipeline state and next recommended step"
install_cmd "help"          "Show pipeline diagram and contextual next action"
install_cmd "pause"         "Pause pipeline and stash all work"
install_cmd "resume"        "List paused pipelines and restore selected one"
install_cmd "refine"        "Deprecated — alias for spec, forwards to ./commands/spec.sh"
install_cmd "resync"        "Resync artifacts after branch rename"
install_cmd "code-review"   "Stack-aware code quality and security review"
install_cmd "mr-address" "Work through MR review comments"
install_cmd "handoff"       "Package artifacts for another agent"
install_cmd "test-design"   "Design test cases for current changes"
install_cmd "test-impl"     "Implement test files for changed source"
# NOTE: triage is intentionally NOT registered as a /f-* command. It is an
# internal sub-step run by /f-spec (draft mode) via commands/triage.sh — see
# agent/SDD_AGENT_INSTRUCTIONS.md ("Do NOT run triage here").

# Remove commands deregistered in newer versions (clean up stale installs).
rm -f "${CMD_DIR}/f-triage.md"

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

# ---- set environment variables (with dedup) ----
ZSENV="${HOME}/.zshenv"
touch "$ZSENV"
for _line in \
  "export OPEN_SDD_ROOT=\"$OPENSDD_PATH\"" \
  "export OPEN_SDD_DOC_HOME=\"\${OPEN_SDD_ROOT:-\$HOME}/.opensdd/registry\""; do
  grep -qxF "$_line" "$ZSENV" || echo "$_line" >> "$ZSENV"
done
echo "OPEN_SDD_ROOT and OPEN_SDD_DOC_HOME added to ~/.zshenv (deduplicated)"

echo ""
echo "Re-run this script after moving open-sdd or adding new commands."
