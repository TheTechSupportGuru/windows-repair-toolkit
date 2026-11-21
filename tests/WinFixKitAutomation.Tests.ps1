# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# WinFixKitAutomation.Tests.ps1 - unit tests for the BETA beta\WinFixKit-beta-automation.ps1 (WinFixKit + an Automation
# tab ported from WinSuperTool). Above all: the ported code must still match WinSuperTool's, because Automation is
# changed in WinSuperTool FIRST and then ported (see CONTRIBUTING.md). Parser only - no GUI, no admin, no changes.
#   Invoke-Pester .\tests\WinFixKitAutomation.Tests.ps1
$Root = Split-Path $PSScriptRoot -Parent
$BetaFile = Join-Path $Root 'beta\WinFixKit-beta-automation.ps1'
$WstFile = Join-Path $Root 'tools\WinSuperTool.ps1'
$HasBeta = Test-Path $BetaFile
if ($HasBeta) {
    $BetaText = [IO.File]::ReadAllText($BetaFile)
    $pe = $null; $BetaAst = [Management.Automation.Language.Parser]::ParseFile($BetaFile, [ref]$null, [ref]$pe); $BetaErrors = @($pe)
    $WstAst = [Management.Automation.Language.Parser]::ParseFile($WstFile, [ref]$null, [ref]$null)
}
function Get-Fn($ast, [string]$n) { $f = $ast.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true); if ($f) { $f.Extent.Text -replace "`r", '' } else { $null } }
function Get-Assign($ast, [string]$v) { $a = $ast.Find({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq $v }, $true); if ($a) { $a.Extent.Text -replace "`r", '' } else { $null } }
# WinSuperTool's text with the documented port renames applied
function ConvertTo-Ported([string]$t) {
    $t = $t -replace '\bNew-Ctl ', 'New-AutoCtl '
    $t = $t -replace '\bSafe \{', 'Invoke-AutoSafe {'
    $t = $t.Replace('$DataDir', '$script:RootDir')
    $t.Replace('WinSuperTool-Data\Task-Results', 'WinFixKit\Task-Results')
}

Describe 'W1 WinFixKit beta-automation: the file' {
    It 'exists, parses and is pure ASCII' -Skip:(-not $HasBeta) {
        $BetaErrors.Count | Should Be 0
        @([IO.File]::ReadAllBytes($BetaFile) | Where-Object { $_ -gt 127 }).Count | Should Be 0
    }
    It 'says it is a beta, with the port rule, in its header and window title' -Skip:(-not $HasBeta) {
        $BetaText | Should Match '# Version 1\.9 beta-automation \d+'
        $BetaText | Should Match 'RULE: Automation changes are made in WinSuperTool FIRST'
        $BetaText | Should Match "Text = 'WinFixKit \(BETA: Automation\)"
        $BetaText | Should Match 'SPDX-License-Identifier: GPL-3.0-or-later'
    }
    It 'keeps the shared window helpers block identical to the stable WinFixKit' -Skip:(-not $HasBeta) {
        $rx = '(?s)#  Window helpers - the same block in every Windows Repair Toolkit tool.*?\nfunction Complete-WrtWindow \{.*?\n\}'
        $a = [regex]::Match(([IO.File]::ReadAllText((Join-Path $Root 'tools\WinFixKit.ps1'))), $rx).Value -replace "`r", ''
        $b = [regex]::Match($BetaText, $rx).Value -replace "`r", ''
        $a.Length | Should BeGreaterThan 1000
        $b | Should BeExactly $a
    }
    It 'changes nothing else of WinFixKit: outside the Automation region only the header, title and window set-up differ' -Skip:(-not $HasBeta) {
        $stable = @([IO.File]::ReadAllLines((Join-Path $Root 'tools\WinFixKit.ps1')))
        $s = [regex]::Match($BetaText, '(?m)^#region AUTOMATION\r?$').Index; $e = [regex]::Match($BetaText, '(?m)^#endregion AUTOMATION').Index
        $outside = @(($BetaText.Substring(0, $s) + $BetaText.Substring($e + '#endregion AUTOMATION'.Length)) -split '\r?\n')
        $diff = @(Compare-Object $stable $outside | ForEach-Object { $_.InputObject.Trim() } | Where-Object { $_ })
        $allowed = '^# (Version 1\.9|BETA:|RULE:|\s+The ported code)|WinFixKit \(BETA: Automation\)|WinFixKit - Windows Troubleshooting Power Tool|^Initialize-WrtWindow \$script:Form @\((\$tpAuto)?\) 900 600$'
        @($diff | Where-Object { $_ -notmatch $allowed }) | Should BeNullOrEmpty
    }
    It 'has a launcher that starts the beta script' -Skip:(-not $HasBeta) {
        $bat = [IO.File]::ReadAllText((Join-Path $Root 'beta\Launch-WinFixKit-beta-automation.bat'))
        $bat | Should Match '%~dp0WinFixKit-beta-automation\.ps1'
        $bat | Should Match 'SPDX-License-Identifier: GPL-3.0-or-later'
    }
}

Describe 'W2 the Automation port still matches WinSuperTool (change WinSuperTool first, then port)' {
    # ported word for word (after the renames); the adapted functions are listed in the region header instead
    $verbatim = 'New-TaskRule', 'Get-TaskVerdict', 'Get-TaskFileBase', 'Get-ExeCall', 'Start-TaskWindow', 'Read-TaskResult', 'Show-TaskSummary', 'Update-TaskWatch',
                'InfoH', 'InfoKV', 'InfoT', 'Get-InfoKeyWidth', 'Format-InfoText', 'Show-Info', 'New-AutoTask', 'Get-AutoCat', 'Format-Dur', 'Update-AutoList',
                'Complete-AutoTask', 'Get-RebootPending', 'Get-AutoSummaryBlocks', 'ConvertTo-HtmlText', 'Export-AutoHtml', 'Complete-AutoRun',
                'Edit-AutoQueue', 'Add-AutoTask', 'Test-AutoQueueShown'
    foreach ($n in $verbatim) {
        It "$n is WinSuperTool's, word for word" -Skip:(-not $HasBeta) {
            $w = Get-Fn $WstAst $n; $b = Get-Fn $BetaAst $n
            $w | Should Not BeNullOrEmpty
            $b | Should BeExactly (ConvertTo-Ported $w)
        }
    }
    It 'the task-window template ($tplTask) and the restore point script are WinSuperTool''s' -Skip:(-not $HasBeta) {
        (Get-Assign $BetaAst '$tplTask') | Should BeExactly (Get-Assign $WstAst '$tplTask')
        (Get-Assign $BetaAst '$AutoScriptRestore') | Should BeExactly ((Get-Assign $WstAst '$AutoScriptRestore').Replace('$desc = ''WinSuperTool '' + (Get-Date', '$desc = ''WinFixKit '' + (Get-Date'))
    }
    It 'the adapted functions differ only where the port says so (no live-log option, no offline queue, admin check)' -Skip:(-not $HasBeta) {
        foreach ($n in 'Save-AutoState', 'Load-AutoState', 'Set-AutoEditing', 'Start-AutoNext') {
            $w = (ConvertTo-Ported (Get-Fn $WstAst $n)) -replace '; Monitor = \$chkAutoMon\.Checked|; \$chkAutoMon\.Checked = \[bool\]\$s\.Monitor|, \$chkAutoMon|        if \(\$A\.Opt\.Monitor\) \{ \[void\]\(Start-TaskMonitors \$c\) \}\n', ''
            (Get-Fn $BetaAst $n) | Should BeExactly $w
        }
        $sar = Get-Fn $BetaAst 'Start-AutoRun'
        $sar | Should Match 'if \(-not \(Test-Admin\)\)'
        $sar | Should Not Match 'Get-TargetWin|chkdsk-fix'
    }
}

Describe 'W3 the WinFixKit task list' {
    if ($HasBeta) {
        $tmp = Join-Path $env:TEMP ('wfk-auto-test-' + [guid]::NewGuid().ToString('N'))
        $script:RootDir = $tmp; $script:LogDir = "$tmp\Logs"; $script:ReportDir = "$tmp\Reports"; $script:RegDir = "$tmp\Reg"; $script:RegKeyDir = "$tmp\Reg\Keys"; $script:RegFullDir = "$tmp\Reg\Full"
        $script:WfkSelf = $BetaFile; $IsWinPE = $false; $NL = "`r`n"; $TaskDir = "$tmp\Task-Results"
        foreach ($fn in $BetaAst.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -in 'Esc-Sq', 'New-TaskRule', 'Get-TaskVerdict', 'Get-TaskFileBase', 'Get-WfkPrelude', 'Get-WfkCall', 'New-AutoTask', 'New-WfkTasks', 'Get-WfkPreset', 'Get-AutoCode', 'Get-AutoWhyNot' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
        foreach ($s in $BetaAst.EndBlock.Statements) { if ($s.Extent.Text -match '^\$(Sections|WfkReboot|TaskRules|AutoScriptRestore|AutoRestore|AutoCatalog|AutoPresets) *=|^\$AutoRestore \| Add-Member') { . ([scriptblock]::Create($s.Extent.Text)) } }
    }
    It 'holds every status check and every fix that needs no answer, plus the restore point, with unique ids' -Skip:(-not $HasBeta) {
        $want = 1 + @($Sections | Where-Object { $_.Status }).Count + @($Sections | ForEach-Object { @($_.Actions) } | Where-Object { -not $_.Prompt -and $_.Label -notlike 'Open *' }).Count
        $AutoCatalog.Count | Should Be $want
        @($AutoCatalog.Id | Select-Object -Unique).Count | Should Be $AutoCatalog.Count
        @($AutoCatalog | Where-Object { $_.Act -and $_.Act.Prompt }).Count | Should Be 0
    }
    It 'every preset has tasks, at most 10, all in the catalog' -Skip:(-not $HasBeta) {
        foreach ($k in $AutoPresets.Keys) {
            $p = @($AutoPresets[$k]); $p.Count | Should BeGreaterThan 2; $p.Count | Should Not BeGreaterThan 10
            foreach ($id in $p) { @($AutoCatalog.Id) -contains $id | Should Be $true }
        }
    }
    It 'every task builds task-window code that parses, and a fix''s code is in a file (too long for a command line)' -Skip:(-not $HasBeta) {
        foreach ($c in $AutoCatalog) {
            $code = Get-AutoCode $c @{ EnableSR = $false }
            $e = $null; [void][Management.Automation.Language.Parser]::ParseInput($code.Call, [ref]$null, [ref]$e)
            @($e).Count | Should Be 0
            if ($c.Sec) {
                $code.Call | Should Match "^\. '.+\.ps1'$"
                $file = $code.Call.Substring(3, $code.Call.Length - 4)
                $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$e); @($e).Count | Should Be 0
            }
        }
    }
    It 'reads the result line of a fix and of a status check' -Skip:(-not $HasBeta) {
        (Get-TaskVerdict 'wfk-fix' "--- RUNNING ---`r`nok`r`n`r`nWinFixKit fix finished without error messages." 0).Find | Should Be 'FIX RAN - no error messages'
        (Get-TaskVerdict 'wfk-fix' "--- RUNNING ---`r`nReboot is required.`r`n`r`nWinFixKit fix finished with 2 error message(s) - read the output above." 0).Find | Should Be 'FIX RAN - WITH ERROR MESSAGES - RESTART NEEDED'
        $v = Get-TaskVerdict 'wfk-fix' "--- RUNNING ---`r`n`r`nWinFixKit fix FAILED: Access is denied" 1; $v.Ok | Should Be $false; $v.Quote | Should Be 'WinFixKit fix FAILED: Access is denied'
        (Get-TaskVerdict 'wfk-status' "x`r`n`r`nWinFixKit status check finished." 0).Find | Should Match '^STATUS SAVED'
    }
    It 'in WinPE every task says it needs the running Windows' -Skip:(-not $HasBeta) {
        $IsWinPE = $true; (Get-AutoWhyNot 'restore-point') | Should Match 'running Windows'; $IsWinPE = $false
        (Get-AutoWhyNot 'restore-point') | Should Be ''
    }
    if ($HasBeta) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
