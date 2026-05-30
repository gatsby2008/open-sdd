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

function Install-DocCmd {
  param($Name, $Description)
  $content = @"
---description: ${Description}---
Read ${OPENSDD_PATH}/agent/PIPELINE.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${Name}.sh `$ARGUMENTS. After the command finishes, STOP. Present the result to the user and let them decide what to do next. Never chain multiple commands automatically.
"@
  Set-Content -Path (Join-Path $CMD_DIR "${Name}.md") -Value $content -Encoding UTF8
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

${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --branch <name>   # for a custom branch
${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --keep            # to stay on current
${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS                   # uses suggested branch

After the script finishes, ${OPENSDD_PATH}/commands/start.sh has written source.md and state files but has NOT created spec.md. Tell the user the pipeline is initialized and recommend ${OPENSDD_PATH}/commands/spec.sh as the next step — /f-spec reads source.md plus templates/spec.md and generates spec.md from scratch (Summary, Scope, Behavior, Implementation Context, Expected Change Scope, Safe Constraints, Open Questions). Do NOT run triage yet — triage classifies the spec body, and spec.md does not exist until /f-spec creates it. Format links cleanly so file paths + line numbers are clickable: put the description separately, e.g. `path/file.md:42` — Open Questions section. Do NOT append text directly after the line number. Then STOP.
"@

Install-CmdDirective -Name "start" -Description "Initialize SDD pipeline: branch + source.md (spec.md is created by /f-spec)" -Directive $startDirective

Install-Cmd -Name "spec"          -Description "Draft (first call) or refine (subsequent calls) the spec"
Install-Cmd -Name "plan"          -Description "Discover target files and write implementation plan"
Install-Cmd -Name "implement"     -Description "Implement next focused change from the spec"
Install-Cmd -Name "commit"        -Description "Stage changes and generate semantic commit"
Install-Cmd -Name "mr"            -Description "Push branch and create merge request"
Install-Cmd -Name "close"         -Description "Clean .specwork and optionally delete feature branch"
Install-Cmd -Name "status"        -Description "Show pipeline state and next recommended step"
Install-Cmd -Name "help"          -Description "Show pipeline diagram and contextual next action"
Install-Cmd -Name "pause"         -Description "Pause pipeline and stash all work"
Install-Cmd -Name "resume"        -Description "List paused pipelines and restore selected one"
Install-Cmd -Name "refine"        -Description "Deprecated — alias for spec, forwards to ./commands/spec.sh"
Install-Cmd -Name "resync"        -Description "Resync artifacts after branch rename"
Install-Cmd -Name "code-review"   -Description "Stack-aware code quality and security review"
Install-Cmd -Name "mr-address" -Description "Work through MR review comments"
Install-Cmd -Name "handoff"       -Description "Package artifacts for another agent"
Install-Cmd -Name "test-design"   -Description "Design test cases for current changes"
Install-Cmd -Name "test-impl"     -Description "Implement test files for changed source"
Install-DocCmdDirective -Name "doc-catalog" -Description "Scan codebase and generate/update docs/service-info.md" -Directive "Run ${OPENSDD_PATH}/commands/doc-catalog.sh `$ARGUMENTS to scan the project and produce structured findings, then use those findings to generate or update docs/service-info.md. Ask the user for confirmation before writing."
Install-DocCmdDirective -Name "doc-publish" -Description "Publish service catalog to central registry" -Directive "Run ${OPENSDD_PATH}/commands/doc-publish.sh `$ARGUMENTS. If the argument is 'list', print the registered catalogs. Otherwise publish docs/service-info.md."
Install-DocCmdDirective -Name "doc-query" -Description "Ask cross-service architecture questions" -Directive "Run ${OPENSDD_PATH}/commands/doc-query.sh `$ARGUMENTS. It prints all registered service catalogs. Use that output to answer the question, citing the source catalog for each claim."
Install-DocCmdDirective -Name "doc-adr" -Description "Create an Architecture Decision Record" -Directive "Run ${OPENSDD_PATH}/commands/doc-adr.sh `$ARGUMENTS to find the next ADR number and gather context. Use the output to draft an ADR, confirm with the user, write to docs/adr/, and offer to commit."
Install-DocCmdDirective -Name "adr-publish" -Description "Publish ADRs to central registry" -Directive "Run ${OPENSDD_PATH}/commands/adr-publish.sh `$ARGUMENTS. If the argument is 'list', print the registered ADRs. Otherwise sync docs/adr/*.md to the registry."
Install-DocCmdDirective -Name "adr-query" -Description "Ask architecture-decision questions across ADRs" -Directive "Run ${OPENSDD_PATH}/commands/adr-query.sh `$ARGUMENTS. It prints ADRs from the registry. Use that output to answer the question, citing every claim as <service>/<ADR-file>."

# Remove stale commands from previous versions
Remove-Item -Path (Join-Path $CMD_DIR "f-triage.md") -ErrorAction SilentlyContinue | Out-Null
@("doc-adr", "doc-catalog", "doc-publish", "doc-query", "adr-publish", "adr-query") | ForEach-Object {
  Remove-Item -Path (Join-Path $CMD_DIR "f-$_.md") -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "open-sdd: 25 commands installed to $CMD_DIR"
Write-Host ""

# ---- set environment variables (with dedup) ------------------------------------
$profilePath = $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $profilePath)) {
  New-Item -ItemType File -Path $profilePath -Force | Out-Null
}
$lines = @(
  "`$env:OPEN_SDD_ROOT = '$OPENSDD_PATH'",
  "`$env:OPEN_SDD_DOC_HOME = '`${OPEN_SDD_ROOT:-`$HOME}/.opensdd/registry'"
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
