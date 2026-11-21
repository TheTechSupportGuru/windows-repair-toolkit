# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Promote-Beta.ps1 - makes the beta WinSuperTool the stable one and ends the beta:
#   1 tools\WinSuperTool.ps1 / .bat  <- beta\, with every BETA label removed and the stable version header
#   2 every other tool's version header -> the new version
#   3 tests point at tools\ instead of beta\ (the beta's own tests keep running, against tools\)
#   4 beta\ scripts removed; beta\README.md says there is no beta at the moment
#   5 the no-AI edition rebuilt from tools\
#   6 report: any "BETA" left in tools\, and what still has to be done by hand (README, forms, change notes, release)
# Without -Apply it only shows what it would change. Run the unit tests afterwards.
#   .\build\Promote-Beta.ps1 -Version 1.9            (dry run)
#   .\build\Promote-Beta.ps1 -Version 1.9 -Apply
param([Parameter(Mandatory)][string]$Version, [string]$Date = (Get-Date -Format 'yyyy-MM-dd'), [switch]$Apply)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$enc = New-Object Text.UTF8Encoding $false
$changes = New-Object Collections.ArrayList
function Note([string]$m) { [void]$changes.Add($m); Write-Host $m }
function Read-Text($rel) { [IO.File]::ReadAllText((Join-Path $Root $rel)) }
function Write-Text($rel, $text) { if ($Apply) { [IO.File]::WriteAllText((Join-Path $Root $rel), $text, $enc) } }
# exact replacements; a missing one stops the script (the beta changed - check the list)
function Edit-Text([string]$text, [object[]]$pairs, [string]$what) {
    foreach ($p in $pairs) { if (-not $text.Contains($p[0])) { throw "$what : text not found: $($p[0].Substring(0, [Math]::Min(70, $p[0].Length)))" }; $text = $text.Replace($p[0], $p[1]) }
    $text
}

# ---------- 1 WinSuperTool ----------
$src = (Read-Text 'beta\WinSuperTool.ps1') -replace "`r`n", "`n"      # edited with LF, written back with CRLF
$src = Edit-Text $src @(
    @("# Version 1.9 BETA 5 (2026-11-20) - BETA build, not the stable release. What changed: docs/changes/V1.9-beta.5.md", "# Version $Version ($Date). What changed: docs/changes/V$Version.md"),
    @("# BETA: Recovery task summaries, per-task log monitors, the System Info tab and the Automation tab are new and only lightly`n# tested. Stable version: tools\ (1.8).`n", ''),
    @('EXPERIMENTAL boot-repair tools. BETA: pass / fail summary + live logs per task.', 'EXPERIMENTAL boot-repair tools, with a pass / fail summary + live logs per task.'),
    @('9  System Info    BETA: Wi-Fi passwords', '9  System Info    Wi-Fi passwords'),
    @('10  Automation     BETA: a queue of up to 10 tasks', '10  Automation     a queue of up to 10 tasks'),
    @("`$AppName = 'Windows Super Tool 1.9 BETA 5'", "`$AppName = 'Windows Super Tool'"),
    @("'BETA: this summary is new. If it gets a result wrong, please open a bug report with the full output.'", "'If this summary gets a result wrong, please open a bug report with the full output.'"),
    @(' &nbsp;|&nbsp; <span class=""beta"">BETA</span></p>', '</p>'),
    @('Created by the Windows Repair Toolkit (BETA) - licensed', 'Created by the Windows Repair Toolkit - licensed'),
    @("'BETA: every task ran in its own window; its full output", "'Every task ran in its own window; its full output"),
    @("Add-Help `$tpRec 840 239 'BETA: monitor and summary'", "Add-Help `$tpRec 840 239 'Monitor and summary'"),
    @('${NL}${NL}BETA: new in 1.9 beta 1 and only lightly tested. Greyed out', '${NL}${NL}Greyed out'),
    @("'BETA 1.9: new scan-only tools (sfc /verifyonly", "'New in $Version`: scan-only tools (sfc /verifyonly"),
    @("'BETA - run up to 10 tasks one after another on THIS PC.", "'Run up to 10 tasks one after another on THIS PC."),
    @('(repairs, updates, app upgrades). BETA feature."', '(repairs, updates, app upgrades)."'),
    @(' .beta { color:var(--warn); font-weight:600 }', '')
) 'beta\WinSuperTool.ps1'
# comments: drop the "BETA:" markers (code comments only)
$src = [regex]::Replace($src, '(?m)^(\s*#\s*)BETA( \d)?:\s*', '$1')
$src = [regex]::Replace($src, '(?m)^(\s*#.*?) \(BETA\)', '$1')
$src = [regex]::Replace($src, '(?m)^(\s*# -+ )BETA \d+: ', '$1')
Note "1 tools\WinSuperTool.ps1 <- beta (header $Version, AppName 'Windows Super Tool', 14 labels, BETA comment markers)"
Write-Text 'tools\WinSuperTool.ps1' ($src -replace "`n", "`r`n")
$bat = Read-Text 'beta\WinSuperTool.bat'
$bat = [regex]::Replace($bat, '(?m)^rem Version 1\.9 BETA \d+ \([^)]*\) - launcher for the beta WinSuperTool\.ps1 in this folder\. What changed: docs/changes/V1\.9-beta\.\d+\.md', "rem Version $Version ($Date). What changed: docs/changes/V$Version.md")
if ($bat -match 'BETA') { throw 'beta\WinSuperTool.bat still says BETA after the header change' }
Note "1 tools\WinSuperTool.bat <- beta (header $Version)"
Write-Text 'tools\WinSuperTool.bat' $bat

# ---------- 2 other tools' headers ----------
foreach ($f in 'ClaudeLogAnalyzer.ps1', 'Collect-Logs.ps1', 'Monitor-Logs.ps1', 'WinFixKit.ps1', 'WinRepairTool-startup.ps1') {
    $t = Read-Text "tools\$f"; $n = [regex]::Replace($t, '(?m)^# Version [\d.]+ \([^)]*\)\. What changed: docs/changes/V[\d.]+\.md', "# Version $Version ($Date). What changed: docs/changes/V$Version.md")
    if ($n -eq $t) { throw "tools\$f : version header not found" }
    Note "2 tools\$f header -> $Version"; Write-Text "tools\$f" $n
}

# ---------- 3 tests ----------
foreach ($f in @(Get-ChildItem (Join-Path $Root 'tests') -Filter *.ps1)) {
    $rel = "tests\$($f.Name)"; $t = Read-Text $rel; $n = $t
    $n = $n.Replace("'beta\WinSuperTool.ps1'", "'tools\WinSuperTool.ps1'").Replace('.\beta\WinSuperTool.ps1', '.\tools\WinSuperTool.ps1')
    $n = $n.Replace("(Join-Path `$Root 'tools'), (Join-Path `$Root 'beta')", "(Join-Path `$Root 'tools')").Replace("(Join-Path `$Repo 'tools'), (Join-Path `$Repo 'beta')", "(Join-Path `$Repo 'tools')")
    $n = $n.Replace("foreach (`$dir in 'tools', 'beta') {", "foreach (`$dir in 'tools') {")
    $n = $n.Replace("@('tools\Collect-Logs.ps1', 'tools\WinSuperTool.ps1', 'beta\WinSuperTool.ps1')", "@('tools\Collect-Logs.ps1', 'tools\WinSuperTool.ps1', 'tools\WinFixKit.ps1')")
    $n = $n.Replace("(Get-BetaAssign 'AppName') | Should Match 'BETA'", "(Get-BetaAssign 'AppName') | Should Not Match 'BETA'")
    if ($n -ne $t) { Note "3 $rel -> tools\"; Write-Text $rel $n }
}

# ---------- 4 beta folder ----------
foreach ($f in @(Get-ChildItem (Join-Path $Root 'beta') -File | Where-Object Extension -in '.ps1', '.bat')) {
    Note "4 remove beta\$($f.Name)"
    if ($Apply) { & git -C $Root rm -q -- "beta/$($f.Name)" }
}
Note '4 beta\README.md -> "no beta at the moment"'
Write-Text 'beta\README.md' "# No beta at the moment`n`nWinSuperTool 1.9 beta 5 became the stable **$Version** ($Date): see [tools/](../tools) and [V$Version](../docs/changes/V$Version.md).`nThe beta's change notes stay in [docs/changes](../docs/changes) (V1.9-beta.1 ... beta.5).`n"

# ---------- 5 no-AI edition ----------
Note '5 rebuild tools\WinSuperTool-NoAI.ps1 / .bat from tools\WinSuperTool.ps1'
if ($Apply) { & (Join-Path $PSScriptRoot 'Build-NoAIEdition.ps1') | Out-Null }

# ---------- 6 report ----------
# (dry run: the promoted text, not the files on disk)
$scan = if ($Apply) { @(Get-Content (Join-Path $Root 'tools\WinSuperTool.ps1')) + @(Get-Content (Join-Path $Root 'tools\WinSuperTool.bat')) } else { @($src -split "`n") + @($bat -split "`r?`n") }
$left = @(for ($i = 0; $i -lt $scan.Count; $i++) { if ($scan[$i] -match '\bBETA\b|\bbeta\b' -and $scan[$i] -notmatch 'v1beta|anthropic-beta|beta\)\s+lets|\(1\.9 beta \d') { [pscustomobject]@{ Filename = 'WinSuperTool'; LineNumber = $i + 1; Line = $scan[$i] } } })
Write-Host ''
Write-Host $(if ($Apply) { 'APPLIED.' } else { 'DRY RUN - nothing changed. Add -Apply to make these changes.' })
Write-Host ("BETA left in tools\ ({0}):" -f $left.Count); $left | Select-Object -First 20 | ForEach-Object { Write-Host ("  {0}:{1}: {2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0, [Math]::Min(120, $_.Line.Trim().Length))) }
Write-Host @"

Still by hand:
  - docs/changes/V$Version.md (from V1.8.4.md + V1.9-beta.1..5.md)
  - README.md: current version, version table row, remove the Beta section, folder list
  - .github issue / discussion forms: "$Version (latest)", drop the beta versions
  - unit tests (stable, toolkit, beta), then the regression (tests\Run-Regression.ps1 -Script .\tools\WinSuperTool.ps1)
  - commit, tag v$Version, release with the per-tool zips
"@
