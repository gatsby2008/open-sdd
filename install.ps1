#!/usr/bin/env pwsh
#Requires -Version 7.0
Set-StrictMode -Version 3

$ErrorActionPreference = "Stop"

$OPENSDD_PATH = Split-Path -Parent $PSCommandPath
$CMD_DIR = Join-Path $HOME ".config" "opencode" "commands"

New-Item -ItemType Directory -Force -Path $CMD_DIR | Out-Null

function Install-Cmd {
  param($Name, $Description)
  $content = @"
---description: ${Description}---
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${Name}.sh `$ARGUMENTS. After the command finishes, STOP. Present the result to the user and let them decide what to do next. Never chain multiple commands automatically.
"@
  Set-Content -Path (Join-Path $CMD_DIR "f-${Name}.md") -Value $content -Encoding UTF8
}

function Install-CmdDirective {
  param($Name, $Description, $Directive)
  $content = @"
---description: ${Description}---
${Directive}
"@
  Set-Content -Path (Join-Path $CMD_DIR "f-${Name}.md") -Value $content -Encoding UTF8
}

function Install-DocCmdDirective {
  param($Name, $Description, $Directive)
  $content = @"
---description: ${Description}---
${Directive}
"@
  Set-Content -Path (Join-Path $CMD_DIR "${Name}.md") -Value $content -Encoding UTF8
}

$startDirective = @"
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

Ask the user about branch choice using the suggested name (prefixed with 'feature/'), a custom name, or staying on the current branch. Once decided, run:

${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --choose A        # create the suggested branch
${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --branch <name>   # for a custom branch
${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --keep            # to stay on current

After the script finishes, ${OPENSDD_PATH}/commands/start.sh has written source.md and state files but has NOT created spec.md. Tell the user the pipeline is initialized and recommend ${OPENSDD_PATH}/commands/spec.sh as the next step — /f-spec reads source.md plus templates/spec.md and generates spec.md from scratch (Summary, Scope, Behavior, Implementation Context, Expected Change Scope, Safe Constraints, Open Questions). Do NOT run triage yet — triage classifies the spec body, and spec.md does not exist until /f-spec creates it. Format links cleanly so file paths + line numbers are clickable: put the description separately, e.g. `path/file.md:42` — Open Questions section. Do NOT append text directly after the line number. Then STOP.
"@

$autoDirective = @"
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

This command drives the entire pipeline non-interactively — no bash prompts.

1. Run: ${OPENSDD_PATH}/commands/auto.sh `$ARGUMENTS
   (`$ARGUMENTS is just the ticket key or free-text description — no flags.
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
back to the user for review/merge/close.
"@

Install-CmdDirective -Name "start" -Description "Initialize SDD pipeline: branch + source.md (spec.md is created by /f-spec)" -Directive $startDirective

Install-Cmd -Name "spec"          -Description "Draft (first call) or refine (subsequent calls) the spec"
Install-Cmd -Name "plan"          -Description "Discover target files and write implementation plan"
Install-Cmd -Name "implement"     -Description "Implement next focused change from the spec"
Install-Cmd -Name "commit"        -Description "Stage changes and generate semantic commit"
Install-Cmd -Name "mr"            -Description "Push branch and create merge request"
Install-Cmd -Name "close"         -Description "Clean .specwork and optionally delete feature branch"
Install-CmdDirective -Name "auto" -Description "Run full SDD pipeline non-interactively" -Directive $autoDirective
Install-Cmd -Name "status"        -Description "Show pipeline state and next recommended step"
Install-Cmd -Name "help"          -Description "Show pipeline diagram and contextual next action"
Install-Cmd -Name "pause"         -Description "Pause pipeline and stash all work"
Install-Cmd -Name "resume"        -Description "List paused pipelines and restore selected one"
Install-Cmd -Name "undo"          -Description "Discard uncommitted changes reversibly (pipeline or vibe coding); --restore to recover, --hard to discard"
Install-Cmd -Name "resync"        -Description "Resync artifacts after branch rename"
Install-Cmd -Name "code-review"   -Description "Stack-aware code quality and security review of your own branch"
Install-Cmd -Name "mr-review"     -Description "Stack-aware code quality and security review of a peer's branch or MR"
Install-Cmd -Name "mr-address" -Description "Work through MR review comments"
Install-Cmd -Name "handoff"       -Description "Package artifacts for another agent"
Install-Cmd -Name "test-design"   -Description "Design test cases for current changes"
Install-Cmd -Name "test-impl"     -Description "Implement test files for changed source"

Install-DocCmdDirective -Name "doc-catalog" -Description "Scan codebase and store the service catalog in the registry (list: /doc-catalog list)" -Directive "When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-catalog.sh list — it prints the catalog for the current repo's service. Stop after the list; do not scan the project.

Otherwise run ${OPENSDD_PATH}/commands/doc-catalog.sh `$ARGUMENTS. It scans the project, detects the stack and service, and prints instructions to generate the catalog and write it STRAIGHT to the registry — no copy in the repo (no docs/service-info.md), no confirmation prompt. Follow the printed instructions and print the stored registry path. Use --with-docs to also publish docs/architecture/, docs/features/, docs/product/ to the registry alongside the catalog."
Install-DocCmdDirective -Name "doc-catalog-query" -Description "Ask cross-service architecture questions" -Directive "Run ${OPENSDD_PATH}/commands/doc-catalog-query.sh \"`$ARGUMENTS\". It prints all registered documents (catalogs + any extra docs published with --with-docs). Use that output to answer the user's architecture question, citing the source file for every claim."
Install-DocCmdDirective -Name "doc-adr" -Description "Create an ADR and store it in the registry (list: /doc-adr list)" -Directive "When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-adr.sh list — it prints ADRs for the current repo's service. Stop after the list; do not create a new ADR.

Otherwise run ${OPENSDD_PATH}/commands/doc-adr.sh `$ARGUMENTS to find the next ADR number and gather context. Use the output to draft an ADR, then write it STRAIGHT to the registry — no copy in the repo (no docs/adr/), no confirmation prompt. Follow the printed instructions and print the stored registry path."
Install-DocCmdDirective -Name "doc-adr-query" -Description "Ask architecture-decision questions across ADRs" -Directive "Run ${OPENSDD_PATH}/commands/doc-adr-query.sh `$ARGUMENTS. It prints ADRs from the registry. Use that output to answer the user's question, citing every claim as <service>/<ADR-file>."
Install-DocCmdDirective -Name "doc-spec" -Description "Store a feature spec in the central spec registry (list: /doc-spec list)" -Directive "When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-spec.sh list — it prints specs for the current repo's service. Stop after the list.

Otherwise run ${OPENSDD_PATH}/commands/doc-spec.sh `$ARGUMENTS. It resolves the spec file (path argument or auto-detect from pipeline), detects the service, and prints instructions to store it in the registry. Counterpart to /f-mr (which stores automatically) — for hand-written or standalone specs."
Install-DocCmdDirective -Name "doc-spec-query" -Description "Ask feature/spec questions across the spec registry" -Directive "Run ${OPENSDD_PATH}/commands/doc-spec-query.sh \"`$ARGUMENTS\". It prints every spec stored by /doc-spec or /f-mr. Use that output to answer the user's feature/spec question (behavior, scope, constraints, open questions), citing every claim as <service>/<spec-file>."
Install-DocCmdDirective -Name "doc-investigation" -Description "Capture current investigation as a structured document (list: /doc-investigation list)" -Directive "When ARGUMENTS is exactly 'list', run ${OPENSDD_PATH}/commands/doc-investigation.sh list — it prints investigations for the current repo's service. Stop after the list.

Otherwise run ${OPENSDD_PATH}/commands/doc-investigation.sh `$ARGUMENTS. It detects the service name, prints the matching investigation template (bug or exploration), and outputs instructions for the LLM to synthesize the session into a structured document. Print the full draft, then write it straight to the registry — no yes/no gate; the user can still interrupt to edit."
Install-DocCmdDirective -Name "doc-investigation-query" -Description "Answer questions across all captured investigations" -Directive "Run ${OPENSDD_PATH}/commands/doc-investigation-query.sh \"`$ARGUMENTS\". It lists investigation services, narrows scope by service name if possible, and prints every investigation file. Use that output to answer the user's question, citing every claim as <service>/<file>."
Install-DocCmdDirective -Name "arch-query" -Description "Query architecture design documents (set OPEN_SDD_ARCH_HOME to the architecture repo path)" -Directive "Run ${OPENSDD_PATH}/commands/arch-query.sh \"`$ARGUMENTS\". It reads architecture design documents from `$OPEN_SDD_ARCH_HOME (set this env var to the architecture repo path), lists available project areas, and narrows scope if a project area name matches the argument. Use the output to answer the user's architecture question. Cite every claim as the source file relative to the architecture repo. If OPEN_SDD_ARCH_HOME is not set, tell the user to set it."

# Remove stale commands from previous versions
Remove-Item -Path (Join-Path $CMD_DIR "f-triage.md") -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path (Join-Path $CMD_DIR "f-refine.md") -ErrorAction SilentlyContinue | Out-Null
@("doc-adr", "doc-catalog", "doc-publish", "doc-query", "adr-publish", "adr-query") | ForEach-Object {
  Remove-Item -Path (Join-Path $CMD_DIR "f-$_.md") -ErrorAction SilentlyContinue | Out-Null
}
# doc-publish, adr-publish, spec-publish merged into doc-catalog, doc-adr, doc-spec.
Remove-Item -Path (Join-Path $CMD_DIR "doc-publish.md") -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path (Join-Path $CMD_DIR "adr-publish.md") -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path (Join-Path $CMD_DIR "spec-publish.md") -ErrorAction SilentlyContinue | Out-Null
# doc-query, adr-query, spec-query renamed to doc-catalog-query, doc-adr-query, doc-spec-query.
Remove-Item -Path (Join-Path $CMD_DIR "doc-query.md") -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path (Join-Path $CMD_DIR "adr-query.md") -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path (Join-Path $CMD_DIR "spec-query.md") -ErrorAction SilentlyContinue | Out-Null
# doc-freshness removed (regenerating with doc-catalog already reflects current code).
Remove-Item -Path (Join-Path $CMD_DIR "doc-freshness.md") -ErrorAction SilentlyContinue | Out-Null

Write-Host "open-sdd: 29 commands installed to $CMD_DIR"
Write-Host ""

# ---- set environment variables (with dedup) ------------------------------------
$profilePath = $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $profilePath)) {
  New-Item -ItemType File -Path $profilePath -Force | Out-Null
}
$lines = @(
  "`$env:OPEN_SDD_ROOT = '$OPENSDD_PATH'",
  "`$env:OPEN_SDD_DOC_HOME = (Join-Path `$env:OPEN_SDD_ROOT '.opensdd/registry')"
)
$existing = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
foreach ($line in $lines) {
  if ($existing -notcontains $line) {
    $line | Out-File -FilePath $profilePath -Append -Encoding UTF8
  }
}
Write-Host "OPEN_SDD_ROOT and OPEN_SDD_DOC_HOME added to PowerShell profile ($profilePath, deduplicated)"

Write-Host ""
Write-Host "Re-run this script after moving open-sdd or adding new commands."
Write-Host ""
Write-Host "NOTE: The pipeline uses bash scripts (.sh). On Windows, run them through WSL2 or Git Bash."
