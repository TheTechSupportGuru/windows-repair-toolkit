# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build-NoAIEdition.ps1 - builds WinSuperTool-NoAI.ps1 (+ its .bat launcher) from WinSuperTool.ps1.
#
# The no-AI edition is for people who do not want logs sent to an AI service. It is generated, never edited by hand:
#   - every block between "#region AI-ANALYZE" and "#endregion AI-ANALYZE" is removed,
#   - every line ending in "# [AI]" is removed,
#   - the tabs are renumbered and the window title says "(no-AI edition)".
# Then it CHECKS the result and refuses to write it when:
#   - it does not parse,
#   - it still calls a function or reads a variable that only existed in the removed AI code,
#   - it still contains AI or network code (API hosts, API keys, TCP / HTTP listeners or clients, web requests).
#
#   .\build\Build-NoAIEdition.ps1                                  (stable: tools\WinSuperTool.ps1)
#   .\build\Build-NoAIEdition.ps1 -Source beta\WinSuperTool.ps1    (beta)
param([string]$Source = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\WinSuperTool.ps1'), [string]$Out = '')
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path -LiteralPath $Source).Path
if (-not $Out) { $Out = Join-Path (Split-Path $Source) 'WinSuperTool-NoAI.ps1' }
$raw = [IO.File]::ReadAllText($Source)
$nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $raw -split "`r?`n"

# ---- 1. remove the AI parts ----
$keep = New-Object Collections.Generic.List[string]
$depth = 0; $removed = 0
foreach ($l in $lines) {
    if ($l -match '^\s*#region AI-ANALYZE\b') { $depth++; $removed++; continue }
    if ($l -match '^\s*#endregion AI-ANALYZE\b') { if ($depth -le 0) { throw 'Unbalanced #endregion AI-ANALYZE' }; $depth--; $removed++; continue }
    if ($depth -gt 0) { $removed++; continue }
    if ($l -match '# \[AI\]\s*$') { $removed++; continue }
    $keep.Add($l)
}
if ($depth -ne 0) { throw 'Unbalanced #region AI-ANALYZE' }
if ($removed -lt 100) { throw "Only $removed lines were marked as AI code - the markers look incomplete." }
$text = ($keep -join $nl)

# ---- 2. renumber the tabs, rename the window, add a header note ----
$script:tabNo = 0
$text = [regex]::Replace($text, "New-Page '\d+\. ", { param($m) $script:tabNo++; "New-Page '$($script:tabNo). " })
$text = [regex]::Replace($text, "(?m)^(\`$AppName = ')([^']+)(')", { param($m) $m.Groups[1].Value + $m.Groups[2].Value + ' (no-AI edition)' + $m.Groups[3].Value })
$note = @(
    '# NO-AI EDITION - generated from WinSuperTool.ps1 by build/Build-NoAIEdition.ps1; do not edit by hand.',
    '# The AI Analyze tab, the phone QR login, the "Send key logs to AI" button and all code that talks to an AI service',
    '# or listens on the network are left out. Everything else is identical to WinSuperTool.ps1 of the same version.'
) -join $nl
$text = [regex]::Replace($text, '(?m)^(# Version [^\r\n]*)', { param($m) $m.Groups[1].Value + $nl + $note }, 'None', [TimeSpan]::FromSeconds(5))
if ($text -notmatch 'NO-AI EDITION') { throw 'Version line not found' }

# ---- 3. checks ----
$tk = $null; $pe = $null
$origAst = [Management.Automation.Language.Parser]::ParseInput($raw, [ref]$tk, [ref]$pe)
$newAst  = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tk, [ref]$pe)
if ($pe.Count) { throw ("The no-AI edition does not parse: " + (($pe | Select-Object -First 3 | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ')) }
function Get-Fns($a) { @($a.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name }) | Sort-Object -Unique }
# variables a piece of code sets: assignments, parameters and foreach loop variables
function Get-Assigned($a) {
    $set = @($a.FindAll({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left -is [Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.Left.VariablePath.UserPath })
    $set += @($a.FindAll({ param($x) $x -is [Management.Automation.Language.ParameterAst] }, $true) | ForEach-Object { $_.Name.VariablePath.UserPath })
    $set += @($a.FindAll({ param($x) $x -is [Management.Automation.Language.ForEachStatementAst] }, $true) | ForEach-Object { $_.Variable.VariablePath.UserPath })
    @($set | ForEach-Object { $_ -replace '^(script|global|local):', '' }) | Sort-Object -Unique
}
$goneFns = @(Get-Fns $origAst | Where-Object { (Get-Fns $newAst) -notcontains $_ })
$calls = @($newAst.FindAll({ param($x) $x -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
$badCalls = @($calls | Where-Object { $goneFns -contains $_ })
if ($badCalls.Count) { throw "Still calls removed AI functions: $($badCalls -join ', ')" }
$newAssigned = Get-Assigned $newAst
$goneVars = @(Get-Assigned $origAst | Where-Object { $newAssigned -notcontains $_ })
$used = @($newAst.FindAll({ param($x) $x -is [Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath -replace '^(script|global|local):', '' } | Sort-Object -Unique)
$badVars = @($used | Where-Object { $goneVars -contains $_ })
if ($badVars.Count) { throw "Still uses variables that only the removed AI code set: $($badVars -join ', ')" }
$forbidden = 'api\.anthropic\.com|generativelanguage\.googleapis|x-api-key|TcpListener|HttpListener|AcceptTcpClient|TcpClient|Invoke-RestMethod|Invoke-WebRequest|Net\.WebClient|HttpClient|UploadString|DownloadString'
$hits = @([regex]::Matches($text, $forbidden) | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($hits.Count) { throw "AI / network code is still present: $($hits -join ', ')" }
if ($text -match '#region AI-ANALYZE|# \[AI\]') { throw 'AI markers left in the output' }

# ---- 4. write the script and its launcher ----
[IO.File]::WriteAllText($Out, $text, (New-Object Text.UTF8Encoding $false))
$bat = Join-Path (Split-Path $Source) 'WinSuperTool.bat'
$batOut = [IO.Path]::ChangeExtension($Out, '.bat')
if (Test-Path -LiteralPath $bat) {
    $b = [IO.File]::ReadAllText($bat).Replace('WinSuperTool.ps1', (Split-Path $Out -Leaf)).Replace('WinSuperTool.bat', (Split-Path $batOut -Leaf)).Replace('title Windows Super Tool launcher', 'title Windows Super Tool (no-AI edition) launcher')
    [IO.File]::WriteAllText($batOut, $b, (New-Object Text.ASCIIEncoding))
}
'{0}: {1} lines removed, {2} tabs, {3} functions and {4} variables of the AI code gone; checks passed.' -f (Split-Path $Out -Leaf), $removed, $script:tabNo, $goneFns.Count, $goneVars.Count
