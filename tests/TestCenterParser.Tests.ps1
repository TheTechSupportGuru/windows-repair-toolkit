# TestCenterParser.Tests.ps1 - unit tests for Test Center's result parser (Get-TestSummary, Get-ResultStatus,
# Get-FlaggedLines): which summary file wins, what counts as a failure line, and the status shown per test.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   Invoke-Pester .\tests\TestCenterParser.Tests.ps1
$tcFile = Join-Path $PSScriptRoot 'TestCenter.ps1'
$tcAst = [Management.Automation.Language.Parser]::ParseFile($tcFile, [ref]$null, [ref]$null)
foreach ($fn in $tcAst.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'Get-FileLines', 'Get-TestSummary', 'Get-ResultStatus', 'Get-FlaggedLines' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
$exp = $tcAst.FindAll({ $args[0] -is [Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -match '^\$(ExpectedById|script:FlaggedLine)' -and $args[0].Parent.Parent -is [Management.Automation.Language.ScriptBlockAst] }, $true)
foreach ($a in $exp) { . ([scriptblock]::Create($a.Extent.Text)) }

Describe 'Get-FlaggedLines' {
    $t = @{ Id = 'automation'; Kind = 'ps' }
    It 'ignores clean lines (0 failed, no errors, PASS, headings, expected lines)' {
        @(Get-FlaggedLines $t @('77 passed, 0 failed', 'Errors: 0', 'no failures found', 'PASS  errors are escaped', 'Failed tasks:', '===== failed', 'TEST: winget missing')).Count | Should Be 0
    }
    It 'flags real failures' {
        @(Get-FlaggedLines $t @('3 failed', 'ERROR: disk', 'UNCAUGHT in section 4', 'NO RESULT: x', 'FAIL  something wrong')).Count | Should Be 5
    }
    It 'an expected line of one test is flagged for another' { @(Get-FlaggedLines @{ Id = 'logs' } @('TEST: winget missing')).Count | Should Be 1 }
}
Describe 'Get-ResultStatus' {
    It 'pester: exit code decides' { Get-ResultStatus @{ Kind = 'pester' } 0 @() | Should Be 'PASSED'; Get-ResultStatus @{ Kind = 'pester' } 1 @('x') | Should Be 'FAILED' }
    It 'script: no lines, clean, flagged' {
        $t = @{ Id = 'x'; Kind = 'ps' }
        Get-ResultStatus $t 0 @() | Should Be 'NO SUMMARY'
        Get-ResultStatus $t 0 @('12 passed, 0 failed') | Should Be 'OK'
        Get-ResultStatus $t 0 @('2 failed') | Should Be 'CHECK'
    }
}
Describe 'Get-TestSummary' {
    $t = @{ Id = 'x'; Kind = 'ps' }
    It 'summary.txt wins over progress.txt' {
        $d = Join-Path $TestDrive 'a'; New-Item -ItemType Directory $d | Out-Null
        'p' | Set-Content "$d\progress.txt"; "s1`r`n`r`ns2" | Set-Content "$d\summary.txt"
        $r = Get-TestSummary $t $d; $r.File | Should Match 'summary\.txt$'; ($r.Lines -join '|') | Should Be 's1|s2'
    }
    It 'finds a *summary*.txt' {
        $d = Join-Path $TestDrive 'b'; New-Item -ItemType Directory $d | Out-Null; 'x' | Set-Content "$d\run-summary-1.txt"
        (Get-TestSummary $t $d).File | Should Match 'run-summary-1\.txt$'
    }
    It 'reads the Results folder of a test too' {
        $d = Join-Path $TestDrive 'c'; $e = Join-Path $TestDrive 'res'; New-Item -ItemType Directory $d, $e | Out-Null; 'r' | Set-Content "$e\summary.txt"
        (Get-TestSummary @{ Id = 'x'; Results = $e } $d).Lines | Should Be 'r'
    }
    It 'results.csv: counts and NOT OK lines' {
        $d = Join-Path $TestDrive 'd'; New-Item -ItemType Directory $d | Out-Null
        @([pscustomobject]@{ Kind = 'b'; Button = 'One'; Result = 'PASS'; Detail = '' }, [pscustomobject]@{ Kind = 'b'; Button = 'Two'; Result = 'FAIL'; Detail = 'no window' }) | Export-Csv "$d\results.csv" -NoTypeInformation
        $l = (Get-TestSummary $t $d).Lines; $l[0] | Should Match 'PASS 1'; $l[1] | Should Be 'NOT OK: Two - no window'
    }
    It 'console.txt: last 15 lines without the transcript header and handled errors' {
        $d = Join-Path $TestDrive 'e'; New-Item -ItemType Directory $d | Out-Null
        @('**********', 'Windows PowerShell transcript start', 'Username: someone', '**********') + (1..20 | ForEach-Object { "line $_" }) + @('At line:3 char:1', '+ CategoryInfo : x') | Set-Content "$d\console.txt"
        $r = Get-TestSummary $t $d; $r.File | Should Be $null; $r.Lines.Count | Should Be 15; $r.Lines[0] | Should Be 'line 6'; ($r.Lines -join '') | Should Not Match 'Username|At line'
    }
    It 'nothing at all: no file, no lines' { $r = Get-TestSummary $t (Join-Path $TestDrive 'none'); $r.File | Should Be $null; @($r.Lines).Count | Should Be 0 }
}
Describe 'Parser edge cases' {
    It 'should match FAILED case-insensitively' {
        $lines = @('FAILED: something went wrong')
        $result = Get-FlaggedLines @{ Id = 'automation'; Kind = 'ps' } $lines
        $result.Count | Should Be 1
    }

    It 'should not flag a line expected for its own test Id' {
        $lines = @('winget is not available')
        $result = Get-FlaggedLines @{ Id = 'automation'; Kind = 'ps' } $lines
        $result.Count | Should Be 0
    }

    It 'should return FAILED for pester kind with nonzero exit code and empty lines' {
        $status = Get-ResultStatus @{ Id = 'x'; Kind = 'pester' } 1 @()
        $status | Should Be 'FAILED'
    }

    It 'should return OK when lines only contain expected patterns' {
        $lines = @('winget is not available', '3 task(s) ran: 2 passed, 1 failed')
        $status = Get-ResultStatus @{ Id = 'automation'; Kind = 'ps' } 0 $lines
        $status | Should Be 'OK'
    }

    It 'should return NO SUMMARY for non-pester kind with empty lines' {
        $status = Get-ResultStatus @{ Id = 'x'; Kind = 'ps' } 0 @()
        $status | Should Be 'NO SUMMARY'
    }
}
