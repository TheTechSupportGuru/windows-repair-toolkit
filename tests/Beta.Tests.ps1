# Beta.Tests.ps1 - unit tests for the WinSuperTool 1.9 BETA (beta\WinSuperTool.ps1): Recovery tab task summaries.
# Reads the beta script with the PowerShell parser only (no GUI, no admin, no system changes).
#   Invoke-Pester .\tests\Beta.Tests.ps1
$BetaPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'beta\WinSuperTool.ps1'
$tk = $null; $pe = $null
$BetaAst = [Management.Automation.Language.Parser]::ParseFile($BetaPath, [ref]$tk, [ref]$pe)
function Get-BetaFn([string]$n) {
    $f = $BetaAst.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
    if (-not $f) { throw "Function $n not found" }; $f.Extent.Text
}
function Get-BetaAssign([string]$v) {
    $a = $BetaAst.Find({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and
        $x.Left -is [Management.Automation.Language.VariableExpressionAst] -and $x.Left.VariablePath.UserPath -eq $v }, $true)
    if (-not $a) { throw "Assignment to `$$v not found" }; $a.Extent.Text
}
$NL = "`r`n"
. ([scriptblock]::Create((Get-BetaFn 'New-TaskRule')))
. ([scriptblock]::Create((Get-BetaAssign 'SfcCommon')))
. ([scriptblock]::Create((Get-BetaAssign 'DismError')))
. ([scriptblock]::Create((Get-BetaAssign 'TaskRules')))
. ([scriptblock]::Create((Get-BetaFn 'Get-TaskVerdict')))
. ([scriptblock]::Create((Get-BetaFn 'Read-TaskResult')))
function J([string[]]$l) { $l -join "`r`n" }

Describe 'B1 beta script basics' {
    It 'parses without errors and is pure ASCII' {
        $pe.Count | Should Be 0
        @([IO.File]::ReadAllBytes($BetaPath) | Where-Object { $_ -gt 127 }).Count | Should Be 0
    }
    It 'says BETA in its version line and window title' {
        $t = [IO.File]::ReadAllText($BetaPath)
        $t | Should Match '# Version 1\.9 BETA 1'
        (Get-BetaAssign 'AppName') | Should Match 'BETA'
    }
    It 'every Recovery tool Kind has rules, and every Logs name is a Live Monitor item' {
        . ([scriptblock]::Create((Get-BetaFn 'New-MonItem'))); $WinDir = 'C:\Windows'
        . ([scriptblock]::Create((Get-BetaAssign 'MonItems')))
        $BcdSetBuild = {}
        . ([scriptblock]::Create((Get-BetaAssign 'Tools')))
        foreach ($t in $Tools) {
            if ($t.Kind) { $TaskRules.ContainsKey($t.Kind) | Should Be $true }
            foreach ($l in @($t.Logs)) { if ($l) { @($MonItems | Where-Object Name -eq $l).Count | Should Be 1 } }
        }
        @($Tools | Where-Object { $_.Kind }).Count | Should BeGreaterThan 10
    }
    It 'new scan-only tools use the online forms on the running Windows and /image offline' {
        $BcdSetBuild = {}
        . ([scriptblock]::Create((Get-BetaAssign 'Tools')))
        $v = $Tools | Where-Object Name -like 'System file check, scan only*'
        (& $v.Argv @{ Win = 'C:'; Live = $true }) -join ' ' | Should Be '/verifyonly'
        (& $v.Argv @{ Win = 'D:'; Live = $false }) -join ' ' | Should Be '/verifyonly /offbootdir=D:\ /offwindir=D:\Windows'
        $c = $Tools | Where-Object Name -like 'DISM: check health*'
        (& $c.Argv @{ Win = 'C:'; Live = $true }) -join ' ' | Should Be '/online /cleanup-image /checkhealth'
        (& $c.Argv @{ Win = 'D:'; Live = $false }) -join ' ' | Should Be '/image:D:\ /cleanup-image /checkhealth'
        $s = $Tools | Where-Object Name -like 'DISM: scan health*'
        (& $s.Argv @{ Win = 'C:'; Live = $true }) -join ' ' | Should Be '/online /cleanup-image /scanhealth'
    }
}

Describe 'B2 sfc results (exact wording, wrapped like the real tool)' {
    It 'no integrity violations -> passed, no corruption' {
        $o = J 'Beginning system scan.  This process will take some time.', '', 'Beginning verification phase of system scan.', 'Verification 100% complete.', '', 'Windows Resource Protection did not find any integrity violations.'
        $v = Get-TaskVerdict 'sfc' $o 0
        $v.Ok | Should Be $true; $v.Tone | Should Be 'Good'; $v.Find | Should Be 'NO CORRUPTION DETECTED'
        $v.Quote[0] | Should Be 'Windows Resource Protection did not find any integrity violations.'
    }
    It 'repaired -> corruption detected, fix worked; the wrapped message is quoted whole' {
        $o = J 'Verification 100% complete.', '', 'Windows Resource Protection found corrupt files and successfully repaired', 'them. For online repairs, details are included in the CBS log file located at', 'windir\Logs\CBS\CBS.log.'
        $v = Get-TaskVerdict 'sfc' $o 0
        $v.Find | Should Match 'FIX WORKED'; $v.Tone | Should Be 'Good'
        $v.Quote[0] | Should Be 'Windows Resource Protection found corrupt files and successfully repaired them.'
        $v.Quote[1] | Should Match '^For online repairs'
    }
    It 'unable to fix some -> fix did not work' {
        $o = J 'Windows Resource Protection found corrupt files but was unable to fix some', 'of them. For online repairs, details are included in the CBS log file.'
        $v = Get-TaskVerdict 'sfc' $o 0
        $v.Find | Should Match 'FIX DID NOT WORK'; $v.Tone | Should Be 'Bad'; $v.Ok | Should Be $true
    }
    It 'repair pending -> did not run, restart' {
        $v = Get-TaskVerdict 'sfc' (J 'There is a system repair pending which requires reboot to complete.  Restart', 'Windows and run sfc again.') 0
        $v.Ok | Should Be $false; $v.Tone | Should Be 'Warn'; $v.Next | Should Match 'Restart'
    }
    It 'not elevated (real output captured on the test VM) -> failed' {
        $v = Get-TaskVerdict 'sfc-verify' (J 'You must be an administrator running a console session in order to', 'use the sfc utility.') 1
        $v.Ok | Should Be $false
        $v.Quote[0] | Should Be 'You must be an administrator running a console session in order to use the sfc utility.'
    }
    It '/verifyonly: violations found -> corruption detected, nothing repaired' {
        $v = Get-TaskVerdict 'sfc-verify' (J 'Windows Resource Protection found integrity violations.', 'For online repairs, details are included in the CBS log file.') 0
        $v.Find | Should Match '^CORRUPTION DETECTED \(scan only'; $v.Ok | Should Be $true
    }
    It '/verifyonly: clean -> no corruption (not confused with "found integrity violations")' {
        (Get-TaskVerdict 'sfc-verify' 'Windows Resource Protection did not find any integrity violations.' 0).Find | Should Be 'NO CORRUPTION DETECTED'
    }
}

Describe 'B3 DISM results' {
    $hdr = 'Deployment Image Servicing and Management tool', 'Version: 10.0.26100.5074', '', 'Image Version: 10.0.26100.7171', ''
    It 'check health clean' {
        $v = Get-TaskVerdict 'dism-check' (J ($hdr + 'No component store corruption detected.', 'The operation completed successfully.')) 0
        $v.Find | Should Be 'NO CORRUPTION DETECTED'
        $v.Quote | Should Be @('No component store corruption detected.', 'The operation completed successfully.')
    }
    It 'scan health: repairable (progress bar on the same line is dropped from the quote)' {
        $v = Get-TaskVerdict 'dism-check' (J ($hdr + '[==========================100.0%==========================] The component store is repairable.', 'The operation completed successfully.')) 0
        $v.Find | Should Match 'CORRUPTION DETECTED - it can be repaired'
        $v.Quote[0] | Should Be 'The component store is repairable.'
    }
    It 'restore health repaired -> fix worked' {
        $v = Get-TaskVerdict 'dism-restore' (J ($hdr + '[==========================100.0%==========================] The restore operation completed successfully.', 'The component store corruption was repaired.', 'The operation completed successfully.')) 0
        $v.Find | Should Match 'FIX WORKED'; $v.Tone | Should Be 'Good'
    }
    It 'restore health with nothing to repair' {
        (Get-TaskVerdict 'dism-restore' (J ($hdr + 'The restore operation completed successfully.', 'The operation completed successfully.')) 0).Find | Should Match '^NO CORRUPTION LEFT'
    }
    It 'restore health 0x800f081f -> fix did not work, error code quoted' {
        $o = J ($hdr + '[===========================84.9%=============             ]', '', 'Error: 0x800f081f', '', 'The source files could not be found.', 'Use the "Source" option to specify the location of the files that are required to restore the feature.')
        $v = Get-TaskVerdict 'dism-restore' $o -2146498529
        $v.Ok | Should Be $false; $v.Find | Should Match 'repair source files'
        $v.Quote[0] | Should Be 'Error: 0x800f081f'; $v.Quote[1] | Should Be 'The source files could not be found.'
    }
    It 'not elevated (real output captured on the test VM) -> failed with Error: 740' {
        $v = Get-TaskVerdict 'dism-check' (J 'Error: 740', '', 'Elevated permissions are required to run DISM.', 'Use an elevated command prompt to complete these tasks.') 740
        $v.Ok | Should Be $false; $v.Quote[0] | Should Be 'Error: 740'
    }
}

Describe 'B4 chkdsk, bcdboot, bootrec, drivers' {
    It 'chkdsk /scan clean' {
        $o = J 'The type of the file system is NTFS.', '', 'Stage 1: Examining basic file system structure ...', '  262144 file records processed.', 'File verification completed.', '', 'Windows has scanned the file system and found no problems.', 'No further action is required.', '', '  62324735 KB total disk space.'
        $v = Get-TaskVerdict 'chkdsk-scan' $o 0
        $v.Find | Should Be 'NO PROBLEMS FOUND'
        $v.Quote | Should Be @('Windows has scanned the file system and found no problems.', 'No further action is required.')
    }
    It 'chkdsk /scan problems' {
        (Get-TaskVerdict 'chkdsk-scan' (J 'Windows has found problems that must be fixed offline.', 'Please run "chkdsk /spotfix" to fix the issues.') 3).Find | Should Match 'PROBLEMS DETECTED'
    }
    It 'chkdsk /scan not elevated (real output) -> not checked' {
        (Get-TaskVerdict 'chkdsk-scan' (J 'Access Denied as you do not have sufficient privileges or', 'the disk may be locked by another process.') 3).Ok | Should Be $false
    }
    It 'chkdsk /f on the system drive, answered Y -> scheduled (not "cannot lock")' {
        $o = J 'The type of the file system is NTFS.', 'Cannot lock current drive.', '', 'Chkdsk cannot run because the volume is in use by another', 'process.  Would you like to schedule this volume to be', 'checked the next time the system restarts? (Y/N) Y', '', 'This volume will be checked the next time the system restarts.'
        $v = Get-TaskVerdict 'chkdsk-fix' $o 0
        $v.Find | Should Match '^SCHEDULED'; $v.Tone | Should Be 'Warn'
    }
    It 'chkdsk /f answered N -> not run' {
        $o = J 'Cannot lock current drive.', '', 'Chkdsk cannot run because the volume is in use by another', 'process.  Would you like to schedule this volume to be', 'checked the next time the system restarts? (Y/N) N'
        (Get-TaskVerdict 'chkdsk-fix' $o 3).Find | Should Match 'not scheduled'
    }
    It 'chkdsk /f made corrections -> fix worked' {
        (Get-TaskVerdict 'chkdsk-fix' 'Windows has made corrections to the file system.' 1).Find | Should Match 'FIX WORKED'
    }
    It 'bcdboot success and failure' {
        (Get-TaskVerdict 'bcdboot' 'Boot files successfully created.' 0).Find | Should Match 'FIX WORKED'
        (Get-TaskVerdict 'bcdboot' 'Failure when attempting to copy boot files.' 1).Ok | Should Be $false
    }
    It 'bootrec /scanos counts' {
        (Get-TaskVerdict 'bootrec-scan' (J 'Scanning all disks for Windows installations.', '', 'Successfully scanned Windows installations.', 'Total identified Windows installations: 0', 'The operation completed successfully.') 0).Find | Should Match '^NO WINDOWS'
        (Get-TaskVerdict 'bootrec-scan' (J 'Successfully scanned Windows installations.', 'Total identified Windows installations: 1', '[1]  D:\Windows') 0).Tone | Should Be 'Good'
    }
    It 'bootrec /fixboot access denied -> failed' {
        (Get-TaskVerdict 'bootrec' 'Access is denied.' 1).Ok | Should Be $false
    }
    It 'pnputil add: success, and a failed package wins over the total' {
        (Get-TaskVerdict 'driver' (J 'Microsoft PnP Utility', '', 'Adding driver package:  net.inf', 'Driver package added successfully.', '', 'Total driver packages:  1', 'Added driver packages:  1') 0).Tone | Should Be 'Good'
        (Get-TaskVerdict 'driver' (J 'Adding driver package:  a.inf', 'Failed to add driver package: The hash for the file is not present.', 'Added driver packages:  1') 0).Find | Should Be 'AT LEAST ONE DRIVER FAILED'
    }
}

Describe 'B6 real elevated output, read back by the task window on the Windows 11 test VM (2026-11-20)' {
    $hdr = 'Deployment Image Servicing and Management tool', 'Version: 10.0.26100.9549', '', 'Image Version: 10.0.26300.9974', ''
    It 'dism /online /cleanup-image /checkhealth' {
        $v = Get-TaskVerdict 'dism-check' (J ($hdr + 'No component store corruption detected.', 'The operation completed successfully.')) 0
        $v.Find | Should Be 'NO CORRUPTION DETECTED'; $v.Ok | Should Be $true
    }
    It 'dism /online /cleanup-image /scanhealth (progress bar on the result line)' {
        $v = Get-TaskVerdict 'dism-check' (J ($hdr + '[==========================100.0%==========================] No component store corruption detected.', 'The operation completed successfully.')) 0
        $v.Find | Should Be 'NO CORRUPTION DETECTED'; $v.Quote[0] | Should Be 'No component store corruption detected.'
    }
    It 'sfc /verifyonly' {
        $v = Get-TaskVerdict 'sfc-verify' (J 'Beginning system scan.  This process will take some time.', '', 'Beginning verification phase of system scan.', 'Verification 100% complete.', '', 'Windows Resource Protection did not find any integrity violations.') 0
        $v.Find | Should Be 'NO CORRUPTION DETECTED'; $v.Quote[0] | Should Be 'Windows Resource Protection did not find any integrity violations.'
    }
    It 'chkdsk C: /scan (stage and phase lines before, size lines after)' {
        $o = J 'The type of the file system is NTFS.', 'Volume label is Windows.', '', 'Stage 1: Examining basic file system structure ...', '  243200 file records processed.', 'File verification completed.',
               ' Phase duration (File record verification): 3.98 seconds.', '', 'Stage 3: Examining security descriptors ...', 'CHKDSK is verifying Usn Journal...', 'Usn Journal verification completed.', '',
               'Windows has scanned the file system and found no problems.', 'No further action is required.', '', '  40485887 KB total disk space.', '         0 KB in bad sectors.', 'Total duration: 10.48 seconds (10487 ms).'
        $v = Get-TaskVerdict 'chkdsk-scan' $o 0
        $v.Find | Should Be 'NO PROBLEMS FOUND'
        $v.Quote | Should Be @('Windows has scanned the file system and found no problems.', 'No further action is required.')
    }
}

Describe 'B5 fallbacks and result file' {
    It 'unknown wording (other display language) -> exit code decides' {
        $v = Get-TaskVerdict 'sfc' 'Der Windows-Ressourcenschutz hat keine Integritaetsverletzungen gefunden.' 0
        $v.Matched | Should Be $false; $v.Ok | Should Be $true; $v.Tone | Should Be 'Warn'
        (Get-TaskVerdict 'dism-check' 'Fehler: 87' 87).Find | Should Be 'FAILED (exit code 87)'
    }
    It 'Read-TaskResult reads the header and keeps the output' {
        $f = Join-Path $env:TEMP ('wst-beta-test-{0}.txt' -f [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($f, "Rc=0`r`nStarted=2026-11-20T10:00:00`r`nEnded=2026-11-20T10:05:30`r`n-----`r`nline 1`r`nline 2")
        $r = Read-TaskResult $f; Remove-Item $f
        $r.Rc | Should Be 0; $r.Output | Should Be "line 1`r`nline 2"; ($r.Ended - $r.Started).TotalSeconds | Should Be 330
    }
    It 'the task window writes its result before "Press Enter", via a temp file + rename' {
        $tpl = Get-BetaAssign 'tplTask'
        $tpl.IndexOf('Move-Item') | Should BeLessThan $tpl.IndexOf('Read-Host')
        $tpl | Should Match '\$LASTEXITCODE'
    }
}
