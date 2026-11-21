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
        $t | Should Match '# Version 1\.9 BETA \d'
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
    It 'the task window writes its result before it closes (Press Enter / countdown), via a temp file + rename' {
        $tpl = Get-BetaAssign 'tplTask'
        $tpl.IndexOf('Move-Item') | Should BeLessThan $tpl.IndexOf('__CLOSE__')
        $tpl | Should Match '\$LASTEXITCODE'
        (Get-BetaFn 'Start-TaskWindow') | Should Match "Read-Host 'Press Enter"
    }
}

Describe 'B7 Automation catalog, presets and task scripts' {
    . ([scriptblock]::Create((Get-BetaFn 'Esc-Sq'))); . ([scriptblock]::Create((Get-BetaFn 'Get-ExeCall'))); . ([scriptblock]::Create((Get-BetaFn 'New-AutoTask')))
    . ([scriptblock]::Create((Get-BetaFn 'New-MonItem'))); $WinDir = 'C:\Windows'; . ([scriptblock]::Create((Get-BetaAssign 'MonItems')))
    foreach ($v in 'AutoScriptRestore', 'AutoScriptWU', 'AutoScriptWinget', 'AutoScriptDefender', 'CbsSr', 'AutoCatalog', 'AutoPresets') { . ([scriptblock]::Create((Get-BetaAssign $v))) }
    It 'every catalog task has rules, valid log names, and code that builds a call that parses' {
        foreach ($c in $AutoCatalog) {
            $TaskRules.ContainsKey($c.Kind) | Should Be $true
            foreach ($l in @($c.Logs)) { if ($l) { @($MonItems | Where-Object Name -eq $l).Count | Should Be 1 } }
            $code = & $c.Code @{ EnableSR = $false }
            $code.Line | Should Not BeNullOrEmpty
            $tk2 = $null; $pe2 = $null; [void][Management.Automation.Language.Parser]::ParseInput($code.Call, [ref]$tk2, [ref]$pe2)
            $pe2.Count | Should Be 0
            $code.Call | Should Not Match '__[A-Z]+__'
        }
    }
    It 'presets only use catalog tasks and hold at most 10' {
        foreach ($k in $AutoPresets.Keys) { @($AutoPresets[$k]).Count | Should BeLessThan 11; foreach ($id in $AutoPresets[$k]) { @($AutoCatalog | Where-Object Id -eq $id).Count | Should Be 1 } }
    }
    It '"repair only if needed" chains point at real tasks and match the scan result wording' {
        foreach ($c in @($AutoCatalog | Where-Object { $_.Then })) { @($AutoCatalog | Where-Object Id -eq $c.Then.Add).Count | Should Be 1 }
        $s = $AutoCatalog | Where-Object Id -eq 'sfc-verify-fix'; $d = $AutoCatalog | Where-Object Id -eq 'dism-scan-fix'
        (Get-TaskVerdict 'sfc-verify' 'Windows Resource Protection found integrity violations.' 0).Find | Should Match $s.Then.If
        (Get-TaskVerdict 'sfc-verify' 'Windows Resource Protection did not find any integrity violations.' 0).Find | Should Not Match $s.Then.If
        (Get-TaskVerdict 'dism-check' 'The component store is repairable.' 0).Find | Should Match $d.Then.If
        (Get-TaskVerdict 'dism-check' 'No component store corruption detected.' 0).Find | Should Not Match $d.Then.If
    }
    It 'the restore-point script puts the 24-hour limit back and the System Protection option switches' {
        $AutoScriptRestore | Should Match 'finally'
        $AutoScriptRestore | Should Match 'SystemRestorePointCreationFrequency -Value \$old'
        (& ($AutoCatalog | Where-Object Id -eq 'restore-point').Code @{ EnableSR = $true }).Call | Should Match 'if \(\$true\)'
    }
    It 'task scripts cannot overwrite the task window''s own variables (found in the elevated run: $res was overwritten)' {
        . ([scriptblock]::Create((Get-BetaAssign 'tplTask')))      # defines $tplTask (the template text)
        $tk3 = $null; $pe3 = $null; $tAst = [Management.Automation.Language.Parser]::ParseInput($tplTask.Replace('__CMD__', '').Replace('__CLOSE__', ''), [ref]$tk3, [ref]$pe3)
        $top = @($tAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] } | ForEach-Object { $_.Left.VariablePath.UserPath })
        $top.Count | Should BeGreaterThan 3
        foreach ($n in $top) { $n | Should Match '^Wst' }
        foreach ($s in @($AutoScriptRestore, $AutoScriptWU, $AutoScriptWinget, $AutoScriptDefender)) {
            $a4 = [Management.Automation.Language.Parser]::ParseInput($s, [ref]$tk3, [ref]$pe3)
            $names = @($a4.FindAll({ param($x) $x -is [Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath })
            @($names | Where-Object { $_ -match '^Wst' }).Count | Should Be 0
        }
    }
    It 'winget list-only task does not upgrade' {
        (& ($AutoCatalog | Where-Object Id -eq 'winget-check').Code @{}).Call | Should Not Match '--all'
    }
}

Describe 'B8 results of the Automation task scripts (their own messages)' {
    It 'restore point' {
        (Get-TaskVerdict 'restorepoint' 'Restore point created: WinSuperTool 2026-11-20 12:00:00 (number 7).' 0).Find | Should Be 'RESTORE POINT CREATED'
        (Get-TaskVerdict 'restorepoint' 'Restore point FAILED: The service cannot be started, either because it is disabled.' 1).Ok | Should Be $false
    }
    It 'Windows Update: up to date, installed with restart, some failed, check-only' {
        (Get-TaskVerdict 'winupdate' 'Windows Update: no updates are available. Windows is up to date.' 0).Find | Should Match '^UP TO DATE'
        $v = Get-TaskVerdict 'winupdate' (J 'Windows Update: 2 of 2 updates installed, 0 failed.', 'A restart is required to finish installing the updates.') 0
        $v.Find | Should Be 'UPDATES INSTALLED - RESTART REQUIRED'; $v.Tone | Should Be 'Good'
        (Get-TaskVerdict 'winupdate' 'Windows Update: 1 of 2 updates installed, 1 failed.' 1).Find | Should Be 'SOME UPDATES FAILED'
        (Get-TaskVerdict 'winupdate-check' (J 'Windows Update: 3 update(s) are available:', '  - Update A', '  - Update B') 0).Find | Should Match '^UPDATES AVAILABLE'
        (Get-TaskVerdict 'winupdate' 'Windows Update FAILED: Exception from HRESULT: 0x80070422 (0x80070422)' 1).Ok | Should Be $false
    }
    It 'winget: counts upgrades, failure wins, up to date, missing' {
        (Get-TaskVerdict 'winget' (J 'Found App A [A.A] Version 2.0', 'Successfully installed', 'Found App B [B.B] Version 3.0', 'Successfully installed') 0).Find | Should Be 'APPS UPGRADED (2)'
        (Get-TaskVerdict 'winget' (J 'Successfully installed', 'Installer failed with exit code: 1603') 1).Find | Should Be 'SOME UPGRADES FAILED (1)'
        (Get-TaskVerdict 'winget' 'No available upgrade found.' 0).Find | Should Be 'ALL APPS ARE UP TO DATE'
        (Get-TaskVerdict 'winget' 'winget is not available for this account.' 1).Ok | Should Be $false
        (Get-TaskVerdict 'winget-check' (J 'Name   Id   Version   Available', 'App A  A.A  1.0  2.0', '3 upgrades available.') 0).Find | Should Match '^APP UPGRADES AVAILABLE'
        # real layout from the elevated run: a table with no full stops, then the count -> only the count line is quoted
        $tbl = J (@('Name                  Id                              Version    Available Source', ('-' * 81)) + @(1..6 | ForEach-Object { "App $_                 Vendor.App$_                    1.0.$_      1.0.9      winget" }) + @('6 upgrades available.'))
        $v = Get-TaskVerdict 'winget-check' $tbl 0
        @($v.Quote).Count | Should Be 1; $v.Quote[0] | Should Be '6 upgrades available.'
    }
    It 'Defender' {
        (Get-TaskVerdict 'defender' 'Defender quick scan finished: no threats found.' 0).Find | Should Be 'NO THREATS FOUND'
        (Get-TaskVerdict 'defender' 'Defender quick scan finished: 2 threat(s) found.' 1).Find | Should Be 'THREATS FOUND'
        (Get-TaskVerdict 'defender' 'Defender scan FAILED: the Microsoft Defender commands are not available on this PC' 1).Ok | Should Be $false
    }
}

Describe 'B9 System Info helpers' {
    . ([scriptblock]::Create((Get-BetaFn 'ConvertFrom-DigitalProductId'))); . ([scriptblock]::Create((Get-BetaFn 'ConvertTo-SubnetMask'))); . ([scriptblock]::Create((Get-BetaFn 'Format-Mac')))
    . ([scriptblock]::Create((Get-BetaFn 'InfoH'))); . ([scriptblock]::Create((Get-BetaFn 'InfoKV'))); . ([scriptblock]::Create((Get-BetaFn 'InfoT'))); . ([scriptblock]::Create((Get-BetaFn 'Get-InfoKeyWidth'))); . ([scriptblock]::Create((Get-BetaFn 'Format-InfoText')))
    It 'decodes a product key (Microsoft''s public generic Windows Pro key, encoded the Windows 8+ way)' {
        $chars = 'BCDFGHJKMPQRTVWXY2346789'; $k = 'VK7JGNPHTMC97JM9MPGT3V66T'; $n = $k.IndexOf('N'); $full = $chars[$n] + $k.Remove($n, 1)
        $v = [Numerics.BigInteger]::Zero; foreach ($c in $full.ToCharArray()) { $v = $v * 24 + $chars.IndexOf($c) }
        $raw = $v.ToByteArray(); $id = New-Object byte[] 164
        for ($i = 0; $i -lt 15 -and $i -lt $raw.Length; $i++) { $id[52 + $i] = $raw[$i] }
        $id[66] = $id[66] -bor 0x08
        ConvertFrom-DigitalProductId $id | Should Be 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
    }
    It 'matches the licensing service''s backup key on this PC (when both are readable)' {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $bk = $null; try { $bk = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -ErrorAction Stop).BackupProductKeyDefault } catch {}
        if ($cv.DigitalProductId -and $bk) { ConvertFrom-DigitalProductId ([byte[]]$cv.DigitalProductId) | Should Be $bk }
    }
    It 'subnet masks and MAC addresses' {
        ConvertTo-SubnetMask 24 | Should Be '255.255.255.0'; ConvertTo-SubnetMask 20 | Should Be '255.255.240.0'; ConvertTo-SubnetMask 0 | Should Be '0.0.0.0'
        Format-Mac '00-11-22-AB-CD-EF' | Should Be '00:11:22:AB:CD:EF'; Format-Mac 'aabbccddeeff' | Should Be 'AA:BB:CC:DD:EE:FF'
    }
    It 'says where each display is, seen from the main display (1.9 beta 5, two-monitor test PC)' {
        . ([scriptblock]::Create((Get-BetaFn 'Get-DisplayPlace')))
        $m = [int[]]@(0, 0, 3840, 2160)
        Get-DisplayPlace $m $m | Should Be 'main display'
        Get-DisplayPlace $m ([int[]]@(3840, 0, 2560, 1440)) | Should Be 'right of the main display'
        Get-DisplayPlace $m ([int[]]@(640, -1440, 2560, 1440)) | Should Be 'above the main display'
        Get-DisplayPlace $m ([int[]]@(-1920, 0, 1920, 1080)) | Should Be 'left of the main display'
        Get-DisplayPlace $m ([int[]]@(0, 2160, 1920, 1080)) | Should Be 'below the main display'
        Get-DisplayPlace $m ([int[]]@(3840, 2160, 1920, 1080)) | Should Be 'right of and below the main display'
    }
    It 'lists every display that is part of the desktop on this PC' {
        . ([scriptblock]::Create((Get-BetaFn 'Get-DisplayRaw')))
        $script:DispApiLoaded = $false; Add-Type -AssemblyName System.Windows.Forms
        @(Get-DisplayRaw).Count | Should Be ([Windows.Forms.Screen]::AllScreens.Count)
    }
    It 'info text lines up keys and indents multi-line values' {
        $t = Format-InfoText @((InfoH 'Net'), (InfoKV 'IPv4 address' @('10.1.1.5 / 24', '10.1.1.6 / 24')), (InfoT 'note'))
        $t | Should Match '(?m)^Net\r?$'
        $t | Should Match '(?m)^  IPv4 address  10\.1\.1\.5 / 24\r?$'
        $t | Should Match '(?m)^ {16}10\.1\.1\.6 / 24\r?$'
    }
}
