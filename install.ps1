#!/usr/bin/env pwsh
#Requires -Version 7.0
Set-StrictMode -Version 3

$ErrorActionPreference = "Stop"

$OPENSDD_PATH = Split-Path -Parent $PSCommandPath
$CMD_DIR = Join-Path $HOME ".config" "opencode" "commands"
$OPENCODE_DIR = Join-Path $HOME ".config" "opencode"

New-Item -ItemType Directory -Force -Path $CMD_DIR | Out-Null

function Install-Cmd {
  param($Name, $Description)
  $content = @"
---description: ${Description}---
Read ${OPENSDD_PATH}/agent/SDD_AGENT_INSTRUCTIONS.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules), then run ${OPENSDD_PATH}/commands/${Name}.sh `$ARGUMENTS. After the command finishes, STOP. Present the result to the user and let them decide what to do next. Never chain multiple commands automatically.
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

$startDirective = @"
Read ${OPENSDD_PATH}/agent/SDD_AGENT_INSTRUCTIONS.md for the full pipeline protocol (gates, spec template, stack detection, OQ rules).

Ask the user about branch choice using the suggested name (prefixed with 'feature/'), a custom name, or staying on the current branch. Once decided, run:

${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --branch <name>   # for a custom branch
${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS --keep            # to stay on current
${OPENSDD_PATH}/commands/start.sh `$ARGUMENTS                   # uses suggested branch

After the script finishes, read the generated source.md and the spec.md scaffold. Draft the initial content into the spec based on the user's input: fill in Summary, Scope (In/Out), Behavior, Implementation Context, Expected Change Scope, Safe Constraints, and at least one Open Question. Keep the spec structure intact. Then run ${OPENSDD_PATH}/commands/triage.sh <slug> to classify the ticket. Print the triage result (type, complexity, path, reason). Format links cleanly so the file path + line number are clickable: put the description separately, e.g. `path/file.md:42` — Open Questions section. Do NOT append text directly after the line number (e.g. avoid `:42 <- OQ`). Then STOP. Tell the user the spec is drafted. Note that the recommended path is advisory.
"@

Install-CmdDirective -Name "start" -Description "Initialize SDD pipeline: branch + spec scaffold" -Directive $startDirective

Install-Cmd -Name "plan"          -Description "Discover target files and write implementation plan"
Install-Cmd -Name "implement"     -Description "Implement next focused change from the spec"
Install-Cmd -Name "commit"        -Description "Stage changes and generate semantic commit"
Install-Cmd -Name "mr"            -Description "Push branch and create merge request"
Install-Cmd -Name "close"         -Description "Clean .specwork and optionally delete feature branch"
Install-Cmd -Name "status"        -Description "Show pipeline state and next recommended step"
Install-Cmd -Name "help"          -Description "Show pipeline diagram and contextual next action"
Install-Cmd -Name "pause"         -Description "Pause pipeline and stash all work"
Install-Cmd -Name "resume"        -Description "List paused pipelines and restore selected one"
Install-Cmd -Name "refine"        -Description "Refine spec with additional context"
Install-Cmd -Name "resync"        -Description "Resync artifacts after branch rename"
Install-Cmd -Name "code-review"   -Description "Stack-aware code quality and security review"
Install-Cmd -Name "review-address" -Description "Work through MR review comments"
Install-Cmd -Name "handoff"       -Description "Package artifacts for another agent"
Install-Cmd -Name "test-design"   -Description "Design test cases for current changes"
Install-Cmd -Name "test-impl"     -Description "Implement test files for changed source"
Install-Cmd -Name "triage"        -Description "Classify ticket complexity from spec and recommend pipeline path"

Write-Host "open-sdd: 18 commands installed to $CMD_DIR"
Write-Host ""

# Generate AGENTS.md with resolved OPEN_SDD_ROOT path
$template = Join-Path $OPENSDD_PATH "templates" "AGENTS.md"
$agentsOut = Join-Path $OPENCODE_DIR "AGENTS.md"
(Get-Content $template -Raw) -replace '\$OPEN_SDD_ROOT', $OPENSDD_PATH | Set-Content -Path $agentsOut -Encoding UTF8 -NoNewline
Write-Host "Global AGENTS.md placed at $agentsOut"

# ---- standalone skills (doc) -------------------------------------------------
$skillsDst = Join-Path $HOME ".claude" "skills"
$docSrc = Join-Path $OPENSDD_PATH "skills" "doc"
if (Test-Path $docSrc) {
  $docDst = Join-Path $skillsDst "doc"
  New-Item -ItemType Directory -Force -Path $docDst | Out-Null
  Get-ChildItem -Path $docSrc -Directory | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $docDst -Recurse -Force
  }

  Get-ChildItem -Path $docSrc -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillFile = Join-Path $_.FullName "SKILL.md"
    $desc = ""
    if (Test-Path $skillFile) {
      $firstLine = Get-Content -Path $skillFile -TotalCount 1
      if ($firstLine -eq "---") {
        $thirdLine = Get-Content -Path $skillFile -TotalCount 3 | Select-Object -Last 1
        $desc = $thirdLine -replace '^description: ', ''
      }
    }
    if (-not $desc) { $desc = "${skillName} skill" }
    $cmdContent = @"
---description: ${desc}---
View $(Join-Path $docDst $skillName "SKILL.md") and follow the instructions.
"@
    Set-Content -Path (Join-Path $CMD_DIR "${skillName}.md") -Value $cmdContent -Encoding UTF8
  }
  Write-Host "doc skills (6) installed to $docDst — available as /doc-adr, /doc-catalog, etc."
}

# ---- set environment variable -------------------------------------------------
$profilePath = $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $profilePath)) {
  New-Item -ItemType File -Path $profilePath -Force | Out-Null
}
"`$env:OPEN_SDD_ROOT = '$OPENSDD_PATH'" | Out-File -FilePath $profilePath -Append -Encoding UTF8
Write-Host "OPEN_SDD_ROOT added to PowerShell profile ($profilePath)"

Write-Host ""
Write-Host "Re-run this script after moving open-sdd or adding new commands."
Write-Host ""
Write-Host "NOTE: The pipeline uses bash scripts (.sh). On Windows, run them through WSL2 or Git Bash."
