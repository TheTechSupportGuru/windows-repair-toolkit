# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# WinFixKitAutomation.Tests.ps1 - unit tests for the Automation and Registry changes tabs of tools\WinFixKit.ps1 (WinFixKit + an Automation
# tab ported from WinSuperTool). Above all: the ported code must still match WinSuperTool's, because Automation is
# changed in WinSuperTool FIRST and then ported (see CONTRIBUTING.md). Parser only - no GUI, no admin, no changes.
#   Invoke-Pester .\tests\WinFixKitAutomation.Tests.ps1
$Root = Split-Path $PSScriptRoot -Parent
$BetaFile = Join-Path $Root 'tools\WinFixKit.ps1'
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

Describe 'W1 WinFixKit (Automation and Registry changes promoted in 2.1): the file' {
    It 'exists, parses and is pure ASCII' -Skip:(-not $HasBeta) {
        $BetaErrors.Count | Should Be 0
        @([IO.File]::ReadAllBytes($BetaFile) | Where-Object { $_ -gt 127 }).Count | Should Be 0
    }
    It 'is a stable version with the port rule; only the two new tabs say beta' -Skip:(-not $HasBeta) {
        $BetaText | Should Match '# Version 2\.\d+ \('
        $BetaText | Should Not Match '# Version [\d.]+ beta'
        $BetaText | Should Match 'RULE: Automation changes are made in WinSuperTool FIRST'
        $BetaText | Should Match "Text = 'WinFixKit - Windows Troubleshooting Power Tool'"
        $BetaText | Should Match "TabPage @\{ Text = 'Automation \(beta\)'"
        $BetaText | Should Match "TabPage @\{ Text = 'Registry changes \(beta\)'"
        $BetaText | Should Match 'SPDX-License-Identifier: GPL-3.0-or-later'
    }
    It 'keeps the shared window helpers block identical to WinSuperTool' -Skip:(-not $HasBeta) {
        $rx = '(?s)#  Window helpers - the same block in every Windows Repair Toolkit tool.*?\nfunction Complete-WrtWindow \{.*?\n\}'
        $a = [regex]::Match(([IO.File]::ReadAllText($WstFile)), $rx).Value -replace "`r", ''
        $b = [regex]::Match($BetaText, $rx).Value -replace "`r", ''
        $a.Length | Should BeGreaterThan 1000
        $b | Should BeExactly $a
    }
    It 'has a launcher that starts it, and the old beta files are gone' {
        $bat = [IO.File]::ReadAllText((Join-Path $Root 'tools\Launch-WinFixKit.bat'))
        $bat | Should Match '%~dp0WinFixKit\.ps1'
        Test-Path (Join-Path $Root 'beta\WinFixKit-beta-automation.ps1') | Should Be $false
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
    It 'counts only the errors a fix SHOWS (a silenced one is not an error; found in the first full test)' -Skip:(-not $HasBeta) {
        $run = { param($block) $fake = [pscustomobject]@{ Kind = 'wfk-fix'; Name = 'stand-in'; Sec = @{ Name = 'Test' }; Act = @{ Label = 'stand-in'; Run = $block } }
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ((Get-WfkCall $fake) + "; exit `$LASTEXITCODE") 2>&1 | Out-String
            Get-TaskVerdict 'wfk-fix' $out $LASTEXITCODE }
        (& $run { param($x) Get-Process NoSuchProcessXyz -ErrorAction SilentlyContinue; 'silenced only' }).Find | Should Be 'FIX RAN - no error messages'
        (& $run { param($x) Write-Error 'a step failed'; 'Reboot is required to finish.' }).Find | Should Be 'FIX RAN - WITH ERROR MESSAGES - RESTART NEEDED'
        $v = & $run { param($x) throw 'boom' }; $v.Ok | Should Be $false; $v.Quote | Should Be 'WinFixKit fix FAILED: boom'
        # a fix that catches its own error and reports it as text (the Store re-registers do; second full test)
        (& $run { param($x) 'Re-registering...'; 'Failed Microsoft.WindowsStore: Deployment failed with HRESULT: 0x80073D02'; 'Done.' }).Find | Should Be 'FIX RAN - WITH ERROR MESSAGES'
    }
    It 'in WinPE every task says it needs the running Windows' -Skip:(-not $HasBeta) {
        $IsWinPE = $true; (Get-AutoWhyNot 'restore-point') | Should Match 'running Windows'; $IsWinPE = $false
        (Get-AutoWhyNot 'restore-point') | Should Be ''
    }
    if ($HasBeta) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'W4 Registry changes tab (beta-automation 3) - safe tests on a throwaway HKCU key' {
    if ($HasBeta) {
        $tmp4 = Join-Path $env:TEMP ('wfk-reg-test-' + [guid]::NewGuid().ToString('N'))
        $script:RootDir = $tmp4; $script:RegDir = "$tmp4\Reg"; $script:RegKeyDir = "$tmp4\Reg\Keys"; $script:RegFullDir = "$tmp4\Reg\Full"; [void][IO.Directory]::CreateDirectory($script:RegKeyDir)
        foreach ($s in $BetaAst.EndBlock.Statements) { if ($s.Extent.Text -match 'Add-Type -Namespace WfkReg' -or $s.Extent.Text -match '^\$(RegAreas|RegSkip|RegDefaults|RegSourceInfo) *=') { . ([scriptblock]::Create($s.Extent.Text)) } }
        foreach ($fn in $BetaAst.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -in 'Get-RegKeyTime', 'ConvertTo-RegNet', 'Get-RegValues', 'Get-ChangedRegKeys', 'Get-RefPath', 'Get-DefaultsMap', 'Format-RegData', 'Test-RegSame', 'Get-RegChangeRows', 'Invoke-RegRevert', 'Backup-RegValue', 'Get-BackupId', 'Test-BackupPending', 'ConvertTo-RegExePath', 'Get-WfkBackupMap' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
        $tk = 'HKCU:\Software\WfkRegChangesTest'
        Remove-Item $tk -Recurse -Force -ErrorAction SilentlyContinue
    }
    It 'reads the last-change time of a key' -Skip:(-not $HasBeta) {
        New-Item $tk -Force | Out-Null; New-ItemProperty $tk -Name Probe -Value 1 -PropertyType DWord -Force | Out-Null
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\WfkRegChangesTest'); $tm = Get-RegKeyTime $k; $k.Close()
        ((Get-Date) - $tm).TotalMinutes | Should BeLessThan 2
    }
    It 'the scan finds a key changed after the date and not one before it' -Skip:(-not $HasBeta) {
        New-Item "$tk\Sub" -Force | Out-Null; New-ItemProperty "$tk\Sub" -Name X -Value 5 -PropertyType DWord -Force | Out-Null
        @(Get-ChangedRegKeys @($tk) (Get-Date).AddMinutes(-2)) -contains "$tk\Sub" | Should Be $true
        @(Get-ChangedRegKeys @($tk) (Get-Date).AddMinutes(5)).Count | Should Be 0
    }
    It 'every built-in default is well-formed and every area path is a registry path' -Skip:(-not $HasBeta) {
        foreach ($d in $RegDefaults) {
            $d[0] | Should Match '^HK(LM|CU):\\'
            $d[2] | Should Match '^(DWord|QWord|String|ExpandString|MultiString|Binary)$'
            if ($d[2] -eq 'DWord' -and $null -ne $d[3]) { $d[3] -is [int] | Should Be $true }
            $d[4] | Should Match '^(all|10|11)$'
        }
        @($RegDefaults).Count | Should BeGreaterThan 60
        foreach ($a in $RegAreas.Values) { foreach ($p in $a) { $p | Should Match '^HK(LM|CU):\\' } }
    }
    It 'maps live keys into a loaded reference hive (SOFTWARE, CurrentControlSet, user)' -Skip:(-not $HasBeta) {
        $ref = @{ Software = 'WFK_REF_S_SOFTWARE'; System = 'WFK_REF_S_SYSTEM'; User = 'WFK_REF_S_USER'; ControlSet = 'ControlSet002' }
        Get-RefPath 'HKLM:\SOFTWARE\Policies\X' $ref | Should Be 'HKLM:\WFK_REF_S_SOFTWARE\Policies\X'
        Get-RefPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' $ref | Should Be 'HKLM:\WFK_REF_S_SYSTEM\ControlSet002\Services\Spooler'
        Get-RefPath 'HKCU:\Software\X' $ref | Should Be 'HKLM:\WFK_REF_S_USER\Software\X'
    }
    It 'lists a value that differs from the reference, can revert it, and the revert restores it with a backup first' -Skip:(-not $HasBeta) {
        $map = @{ ("$tk\Sub|X").ToLower() = @{ Exists = $true; Kind = 'DWord'; Data = 1 }; ("$tk\Sub|Gone").ToLower() = @{ Exists = $false; Kind = 'DWord'; Data = $null } }
        New-ItemProperty "$tk\Sub" -Name Gone -Value 7 -PropertyType DWord -Force | Out-Null
        $rows = @(Get-RegChangeRows @("$tk\Sub") @(@{ Id = 'defaults'; Name = 'test list'; Map = $map }) @{})
        $x = $rows | Where-Object Name -eq 'X'; $g = $rows | Where-Object Name -eq 'Gone'
        $x.CanRevert | Should Be $true; $x.Old | Should Match '^1 '; $x.Current | Should Match '^5 '
        $g.CanRevert | Should Be $true; $g.Old | Should Be '(not set)'
        $bk = "$tmp4\chosen-backup-folder"
        (Invoke-RegRevert $x $bk) | Should Match '^Reverted'
        (Invoke-RegRevert $g $bk) | Should Match '^Reverted'
        (Get-ItemProperty "$tk\Sub").X | Should Be 1
        ((Get-Item "$tk\Sub").GetValueNames() -contains 'Gone') | Should Be $false
        @(Get-ChildItem $bk -Filter *.reg).Count | Should BeGreaterThan 0
        @(Get-ChildItem $script:RegKeyDir -Filter *.json).Count | Should Be 2
    }
    It 'a value that did not exist in a whole-registry reference is information only (not revertable)' -Skip:(-not $HasBeta) {
        New-ItemProperty "$tk\Sub" -Name NewByApp -Value 'x' -PropertyType String -Force | Out-Null
        $fakeRef = @{ User = 'WfkNoSuchHive'; Software = $null; System = $null }   # a reference that does not have the key
        $rows = @(Get-RegChangeRows @("$tk\Sub") @(@{ Id = 'shadow'; Name = 'test shadow'; Ref = $fakeRef }) @{})
        $r = $rows | Where-Object Name -eq 'NewByApp'
        $r | Should Not BeNullOrEmpty
        $r.CanRevert | Should Be $false
    }
    if ($HasBeta) { Remove-Item $tk -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $tmp4 -Recurse -Force -ErrorAction SilentlyContinue }
}