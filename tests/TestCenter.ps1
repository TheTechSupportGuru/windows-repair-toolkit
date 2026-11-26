# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# TestCenter.ps1 - one window for every test we run regularly: a tab per tool, a tick box per test, "Run selected".
# Tools to test: Offline = any folder with the toolkit scripts (your own edited build too), Online = download a
# version (release, beta or main) from GitHub into a folder of your choice. Test Center shows which downloaded
# scripts you have edited since.
# Each test runs in its own (minimized) PowerShell window, one after the other, on a copy of the tests + chosen tools.
# Tests marked [admin] ask for administrator rights (start Test Center as administrator to get only one prompt).
# Results: C:\Users\Public\wrt-testcenter-<date-time>\ : a folder per test, report.txt, report.html and
# summary-for-github.md (Markdown without PC or user names, to paste into a GitHub issue or discussion).
#
# Update this tool only when the test procedures change or a test script is fixed - not with every toolkit release.
#   Start-TestCenter.bat   or   powershell -STA -ExecutionPolicy Bypass -File .\tests\TestCenter.ps1
#   Scripted (e.g. your own build):  ... TestCenter.ps1 -ToolsFolder D:\my-build\tools -Run unit-suite,unit-toolkit,sizes -ExitWhenDone
#   (test ids: the Id values in $Tests below; -Run all = every test that can run here)
param([string]$ToolsFolder, [string[]]$Run, [switch]$ExitWhenDone)
$TestCenterVersion = '1.0 beta 4'
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$TestsDir = $PSScriptRoot
$RepoDir  = Split-Path $TestsDir -Parent
$ToolsDir = Join-Path $RepoDir 'tools'
$IsAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$InWinPE  = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
$Monitors = [Windows.Forms.Screen]::AllScreens.Count
$PsExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $PsExe)) { $PsExe = (Get-Process -Id $PID).Path }

# ---------------------------------------------------------------- the tests
# Kind: ps = script with parameters, pester = unit-test file.  Args: {out} = this test's result folder, {tools} = tools folder.
# Results: where the test writes when it has no -OutDir parameter.  Min = minutes (rough).
$Tests = @(
    # ---- Whole toolkit
    @{ Tab = 'Whole toolkit'; Id = 'unit-suite'; Name = 'Unit tests: every tool (Suite)'; Kind = 'pester'; Script = 'Suite.Tests.ps1'; Min = 3; Default = $true
       Desc = 'Pester unit tests of all tools with stubs for diskpart, bcdedit and the like. Changes nothing.' }
    @{ Tab = 'Whole toolkit'; Id = 'unit-toolkit'; Name = 'Unit tests: shared code + launchers (Toolkit)'; Kind = 'pester'; Script = 'Toolkit.Tests.ps1'; Min = 1; Default = $true
       Desc = 'Identical window helpers in every tool, licence headers, pure-ASCII scripts, launchers, no-AI edition in step.' }
    @{ Tab = 'Whole toolkit'; Id = 'unit-features'; Name = 'Unit tests: 1.9 features'; Kind = 'pester'; Script = 'Beta.Tests.ps1'; Min = 1; Default = $true
       Desc = 'System Info, Automation, Recovery summaries and the HTML report of WinSuperTool.' }
    @{ Tab = 'Whole toolkit'; Id = 'unit-testcenter'; Name = 'Unit tests: Test Center''s result reader'; Kind = 'pester'; Script = 'TestCenterParser.Tests.ps1'; Min = 1; Default = $true
       Desc = 'Which summary file Test Center reads for a test, which lines count as failures, and the status it shows. Changes nothing.' }
    @{ Tab = 'Whole toolkit'; Id = 'sizes'; Name = 'Window sizes (resize audit)'; Kind = 'ps'; Script = 'Run-ResizeAudit.ps1'; Min = 15; Default = $true
       Args = [ordered]@{ OutDir = '{out}'; Parallel = $true }
       Desc = 'Opens every GUI tool at several sizes, visits every tab, reports overlapping or cut-off controls. Do not use the mouse.' }
    @{ Tab = 'Whole toolkit'; Id = 'monitors'; Name = 'Two monitors: move, maximize, unplug'; Kind = 'ps'; Script = 'Run-ResizeAudit.ps1'; Min = 15; Monitors = 2
       Args = [ordered]@{ OutDir = '{out}'; Sizes = @('mon:2', 'min', '75%', 'max', 'maxon:2', 'mon:1', 'span', 'mon:2', 'span', 'solo', 'extend', 'mon:2') }
       Desc = 'Needs 2 monitors. Moves the tools between monitors, spans them, turns monitor 2 off and on again.' }
    @{ Tab = 'Whole toolkit'; Id = 'drag'; Name = 'Two monitors: drag with the mouse'; Kind = 'ps'; Script = 'Run-DragTest.ps1'; Min = 5; Monitors = 2
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'Needs 2 monitors. Drags tool windows across the monitor edge with the real mouse. Hands off the mouse.' }
    @{ Tab = 'Whole toolkit'; Id = 'smoke'; Name = 'Start every tool as administrator'; Kind = 'ps'; Script = 'Run-ElevatedSmoke.ps1'; Min = 3; Admin = $true
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'Opens each GUI tool elevated for 20 s, closes it and checks for script errors.' }
    @{ Tab = 'Whole toolkit'; Id = 'scaling'; Name = 'Real 150 % / 200 % scaling (signs you out)'; Kind = 'ps'; Script = 'Start-ScaleTest.ps1'; Min = 50
       Results = 'C:\Users\Public\wrt-scale-test'
       Warn = 'This test changes the main monitor''s scaling and needs you to SIGN OUT twice. It continues by itself after each sign-in and puts the scaling back at the end. Run it on its own, as the last test.'
       Desc = 'Sets the main monitor to 150 % then 200 %, signs out, runs the size and monitor tests after each sign-in.' }
    # ---- WinSuperTool
    @{ Tab = 'WinSuperTool'; Id = 'regression'; Name = 'Full regression (parts A-F)'; Kind = 'ps'; Script = 'Run-Regression.ps1'; Min = 45; Admin = $true
       Args = [ordered]@{ OutDir = '{out}'; Script = '{tools}\WinSuperTool.ps1' }
       Desc = 'Live Monitor, Recovery scans, Automation, WinFixKit status, sizes and monitors in one run. Includes most single tests below.' }
    @{ Tab = 'WinSuperTool'; Id = 'monitor-live'; Name = 'Live Monitor: every item'; Kind = 'ps'; Script = 'Run-MonitorLive.ps1'; Min = 8; Admin = $true
       Args = [ordered]@{ OutDir = '{out}'; Script = '{tools}\WinSuperTool.ps1' }
       Desc = 'Opens every monitor window and checks live activity (file lines, filters, events, new files). Writes one test event.' }
    @{ Tab = 'WinSuperTool'; Id = 'recovery'; Name = 'Recovery: read-only scans + summaries'; Kind = 'ps'; Script = 'Run-TaskCapture.ps1'; Min = 25; Admin = $true
       Args = [ordered]@{ OutDir = '{out}'; Script = '{tools}\WinSuperTool.ps1'; Elevated = $true }
       Desc = 'Real SFC / DISM / chkdsk scans (read-only) through the tool''s task window; checks the pass/fail summary.' }
    @{ Tab = 'WinSuperTool'; Id = 'automation'; Name = 'Automation: queue, chains, HTML report'; Kind = 'ps'; Script = 'Run-AutomationSmoke.ps1'; Min = 30; Admin = $true
       Args = [ordered]@{ OutDir = '{out}'; Script = '{tools}\WinSuperTool.ps1'; NoPopups = $true }
       Desc = 'Runs a real Automation queue with "repair only if needed" chains and checks the per-task and final summaries.' }
    @{ Tab = 'WinSuperTool'; Id = 'sysinfo'; Name = 'System Info: all Windows-tool buttons'; Kind = 'ps'; Script = 'Run-SystemInfoButtons.ps1'; Min = 8; Admin = $true
       Args = [ordered]@{ Beta = '{tools}\WinSuperTool.ps1'; Out = '{out}' }
       Desc = 'Clicks every button on the System Info tab and checks the right window opens. Close Settings first.' }
    # ---- WinFixKit
    @{ Tab = 'WinFixKit'; Id = 'wfk-status-user'; Name = 'Check status: every section (no admin)'; Kind = 'ps'; Script = 'Run-StatusChecks.ps1'; Min = 3
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'Runs every "Check status" block without the GUI and proves nothing changed on the PC. Runs without admin rights only when Test Center itself is not running as administrator.' }
    @{ Tab = 'WinFixKit'; Id = 'wfk-status-admin'; Name = 'Check status: every section (admin)'; Kind = 'ps'; Script = 'Run-StatusChecks.ps1'; Min = 3; Admin = $true
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'The same as administrator (more sections can read their data).' }
    @{ Tab = 'WinFixKit'; Id = 'windowed'; Name = 'Fixes that open their own window (CHANGES this PC)'; Kind = 'ps'; Script = 'Run-Windowed.ps1'; Min = 40; Admin = $true
       Results = '%LOCALAPPDATA%\suite-windowed'
       Warn = 'This test runs WinFixKit fixes FOR REAL in their own windows: it removes update KB5025221 if it is installed, RE-REGISTERS ALL APPS and runs a DISM + SFC REPAIR. It also checks that WinSuperTool''s Recovery windows start and that chkdsk /f stops at its question. Only run it on a test machine. Continue?'
       Desc = 'WinFixKit fixes that open their own console window (remove KB5025221, energy report, read-only chkdsk, re-register all apps, DISM + SFC repair) and WinSuperTool''s Recovery windows. Changes the PC - asks first.' }
    @{ Tab = 'WinFixKit'; Id = 'wfk-fixundo'; Name = 'Apply every fix, then undo it (TEST VM ONLY)'; Kind = 'ps'; Script = 'Run-Phase3.ps1'; Min = 60; Admin = $true
       Results = '%TEMP%\suite-phase3'
       Warn = 'This test REALLY CHANGES this PC (registry, services, firewall, sharing) and undoes every change with WinFixKit''s own backups. Only run it on a TEST virtual machine AFTER taking a snapshot. Is the snapshot taken?'
       Desc = 'Applies each fix for real and undoes it with WinFixKit''s backups. Take a VM snapshot first.' }
    @{ Tab = 'WinFixKit'; Id = 'wfk-beta-auto'; Name = 'Unit tests: WinFixKit beta-automation (Automation port, Registry changes)'; Kind = 'pester'; Script = 'WinFixKitAutomation.Tests.ps1'; Min = 1; Default = $true
       Desc = 'The beta in beta\: the Automation code must still match WinSuperTool''s, and the Registry changes tab (key times, scan, defaults list, a real revert on a throw-away HKCU key). Changes nothing else.' }
    # ---- Backup Script Builder
    @{ Tab = 'Backup Script Builder'; Id = 'backup-unit'; Name = 'Unit tests: Backup Script Builder edge cases'; Kind = 'pester'; Script = 'BackupScriptBuilder.Tests.ps1'; Min = 1; Default = $true
       Desc = 'Pair names, drive keys, log file stamps, XML escaping, ticked-folder clean-up and reading tasks back. Changes nothing.' }
    @{ Tab = 'Backup Script Builder'; Id = 'backup-builder'; Name = 'Backup Script Builder: scripts, folder picker, schedules, layout'; Kind = 'ps'; Script = 'Run-BackupScriptBuilder.ps1'; Min = 3; Default = $true
       Desc = 'Builds a FreeFileSync script and compares it line by line with a reference, checks the destination rules, runs real Robocopy / Xcopy scripts, checks the folder picker (every user folder listed, no junctions, system folders only on request, no duplicates, the real dialog), creates / reads back / deletes a scheduled task of every type (in \BackupScriptBuilder\, as you), and checks the layout and every ? help text.' }
    # ---- 7z-Encryptor
    @{ Tab = '7z-Encryptor'; Id = '7z-encryptor'; Name = '7z-Encryptor: encryption, windows, drag-and-drop launcher'; Kind = 'ps'; Script = 'Run-7zEncryptor.ps1'; Min = 1; Default = $true
       Desc = 'Encrypts test files in every mode with 7-Zip and unpacks them again, checks both windows and drops a file on the launcher. Needs 7-Zip. Works only in a temporary folder.' }
    # ---- Log tools
    @{ Tab = 'Log tools'; Id = 'logs'; Name = 'Log collection + AI log readers'; Kind = 'ps'; Script = 'Run-LogGen.ps1'; Min = 15; Admin = $true
       Results = '%TEMP%\suite-logs'
       Desc = 'WinSuperTool collectors (live and offline), Collect-Logs.ps1, and the log readers of WinSuperTool and ClaudeLogAnalyzer. The results contain this PC''s logs - delete them when done.' }
    # ---- Other PCs
    @{ Tab = 'Other PCs / WinPE'; Id = 'field'; Name = 'Field test (Windows 10, laptops, other languages)'; Kind = 'ps'; Script = 'Run-FieldTest.ps1'; Min = 30; Admin = $true
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'The toolkit''s checks on another PC: Wi-Fi, Bluetooth, language, scans. Send only share\WRT-FieldTest-share.zip.' }
    @{ Tab = 'Other PCs / WinPE'; Id = 'pe'; Name = 'WinPE test (Hiren''s BootCD PE)'; Kind = 'ps'; Script = 'Run-PETest.ps1'; Min = 30; WinPE = $true
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'Only inside WinPE: mounts the offline Windows without changing it and runs Automation on it.' }
)

# ---------------------------------------------------------------- helpers
$RepoUrl  = 'https://github.com/TheTechSupportGuru/windows-repair-toolkit'
$ApiUrl   = 'https://api.github.com/repos/TheTechSupportGuru/windows-repair-toolkit'
$NeedsByTab = @{ 'WinSuperTool' = 'WinSuperTool.ps1'; 'WinFixKit' = 'WinFixKit.ps1'; 'Log tools' = 'Collect-Logs.ps1'; 'Backup Script Builder' = 'BackupScriptBuilder.ps1'; '7z-Encryptor' = '7z-Encryptor.ps1' }
$SourceFile = '.wrt-source.json'     # written next to a downloaded tools folder: version + original hashes
$script:Stage = $null                   # the staged copy of one run: Repo, Tests, Tools
$script:Results = New-Object Collections.ArrayList

function ConvertTo-PsLiteral($v) {
    if ($v -is [bool]) { if ($v) { return '$true' } else { return '$false' } }
    if ($v -is [array]) { return '@(' + (($v | ForEach-Object { ConvertTo-PsLiteral $_ }) -join ', ') + ')' }
    "'" + ([string]$v -replace "'", "''") + "'"
}
function Expand-Value($v, [string]$out) {
    if ($v -is [string]) { return $v.Replace('{out}', $out).Replace('{tools}', $script:Stage.Tools) }
    if ($v -is [array]) { return @($v | ForEach-Object { Expand-Value $_ $out }) }
    $v
}
function Get-TestCommand($t, [string]$out) {
    $path = Join-Path $script:Stage.Tests $t.Script
    $log  = Join-Path $out 'console.txt'
    if ($t.Kind -eq 'pester') {
        $run = "Import-Module Pester; `$r = Invoke-Pester -Script $(ConvertTo-PsLiteral $path) -PassThru; " +
               "('Passed {0}  Failed {1}  Skipped {2}' -f `$r.PassedCount, `$r.FailedCount, `$r.SkippedCount) | Set-Content -LiteralPath $(ConvertTo-PsLiteral (Join-Path $out 'summary.txt')); " +
               "`$r.TestResult | Where-Object { -not `$_.Passed -and `$_.Result -ne 'Skipped' } | ForEach-Object { 'FAILED: ' + `$_.Describe + ' > ' + `$_.Name } | Add-Content -LiteralPath $(ConvertTo-PsLiteral (Join-Path $out 'summary.txt')); `$code = `$r.FailedCount"
    } else {
        $pairs = @(); if ($t.Args) { foreach ($k in $t.Args.Keys) { $pairs += "$k = $(ConvertTo-PsLiteral (Expand-Value $t.Args[$k] $out))" } }
        $run = "`$p = @{ $($pairs -join '; ') }; & $(ConvertTo-PsLiteral $path) @p; `$code = [int]`$LASTEXITCODE"
    }
    "Set-Location $(ConvertTo-PsLiteral $script:Stage.Repo); try { Start-Transcript -Path $(ConvertTo-PsLiteral $log) -Force | Out-Null } catch {}; `$code = 0; $run; try { Stop-Transcript | Out-Null } catch {}; exit `$code"
}

# what is in a tools folder: version, script hashes, and (for a downloaded folder) which scripts were edited since
function Get-ToolsInfo([string]$dir) {
    $i = [ordered]@{ Folder = $dir; Ok = $false; Version = 'unknown'; Source = 'local folder'; Files = [ordered]@{}; Edited = @() }
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $i }
    foreach ($f in Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.ps1', '.bat' } | Sort-Object Name) {
        $i.Files[$f.Name] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.Substring(0, 12).ToLower()
    }
    $i.Ok = $i.Files.Count -gt 0
    foreach ($n in 'WinSuperTool.ps1', 'WinFixKit.ps1', 'WinRepairTool-startup.ps1') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { $m = Get-Content -LiteralPath $p -TotalCount 8 | Select-String '#\s*Version\s+([0-9][0-9.]*(\s+beta\s+\d+)?)' | Select-Object -First 1; if ($m) { $i.Version = $m.Matches[0].Groups[1].Value; break } }
    }
    $sf = Join-Path $dir $SourceFile
    if (Test-Path -LiteralPath $sf) {
        try {
            $s = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
            $i.Source = "GitHub $($s.Ref)"
            foreach ($p in $s.Hashes.PSObject.Properties) { if ($i.Files[$p.Name] -ne $p.Value) { $i.Edited += $p.Name } }
            foreach ($n in $i.Files.Keys) { if (-not $s.Hashes.PSObject.Properties[$n]) { $i.Edited += "$n (new)" } }
            if ($i.Edited.Count) { $i.Source += ' + local edits' }
        } catch {}
    }
    $i
}
# paths and names that identify this PC or person are replaced before anything is exported
function Hide-Identity([string]$s) {
    if (-not $s) { return $s }
    foreach ($p in @(@($script:Stage.Repo, '<run folder>'), @($env:USERPROFILE, '%USERPROFILE%'), @($env:COMPUTERNAME, '<PC>'), @($env:USERNAME, '<user>'))) {
        if ($p[0] -and $p[0].Length -gt 2) { $s = [regex]::Replace($s, [regex]::Escape($p[0]), $p[1], 'IgnoreCase') }
    }
    $s
}
function Get-EnvInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    [ordered]@{
        Windows    = $(if ($InWinPE) { 'WinPE ' } else { '' }) + $(if ($os) { "$($os.Caption) $($os.Version) $($os.OSArchitecture)" } else { [Environment]::OSVersion.VersionString })
        PowerShell = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
        Language   = (Get-Culture).Name
        Admin      = $IsAdmin
        Monitors   = ([Windows.Forms.Screen]::AllScreens | ForEach-Object { '{0}x{1}' -f $_.Bounds.Width, $_.Bounds.Height }) -join ' + '
    }
}

# ---------------------------------------------------------------- online: versions + download
function Get-OnlineVersions {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri "$ApiUrl/releases?per_page=100" -Headers @{ 'User-Agent' = 'WRT-TestCenter' } -UseBasicParsing -ErrorAction Stop
    $list = @()
    $latest = ($rel | Where-Object { -not $_.prerelease -and -not $_.draft } | Select-Object -First 1).tag_name
    foreach ($r in $rel | Where-Object { -not $_.draft }) {
        $label = $r.tag_name + $(if ($r.tag_name -eq $latest) { '  (latest)' } elseif ($r.prerelease) { '  (beta)' } else { '' })
        $list += [pscustomobject]@{ Label = $label; Ref = $r.tag_name; Zip = "$RepoUrl/archive/refs/tags/$($r.tag_name).zip" }
    }
    # Since 1.9.1 betas have no release entry of their own (they ship inside the main release), so beta builds are
    # found by their git tags. A failure here only hides the betas, never the releases.
    try {
        $tags = Invoke-RestMethod -Uri "$ApiUrl/tags?per_page=100" -Headers @{ 'User-Agent' = 'WRT-TestCenter' } -UseBasicParsing -ErrorAction Stop
        $known = @($list | ForEach-Object { $_.Ref })
        foreach ($t in @($tags | Where-Object { $_.name -match 'beta' -and $known -notcontains $_.name } | Sort-Object name -Descending)) {
            $list += [pscustomobject]@{ Label = $t.name + '  (beta)'; Ref = $t.name; Zip = "$RepoUrl/archive/refs/tags/$($t.name).zip" }
        }
    } catch {}
    $list += [pscustomobject]@{ Label = 'main  (newest code, may be unreleased)'; Ref = 'main'; Zip = "$RepoUrl/archive/refs/heads/main.zip" }
    $list
}
function Get-OnlineTools($ver, [string]$into) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $dest = Join-Path $into ('windows-repair-toolkit-' + ($ver.Ref -replace '[^A-Za-z0-9.\-]', '_'))
    if (Test-Path -LiteralPath $dest) {
        if ([Windows.Forms.MessageBox]::Show("$dest already exists. Replace it with a fresh download? (Your edits in it are lost.)", $form.Text, 'YesNo', 'Question') -ne 'Yes') { return (Join-Path $dest 'tools') }
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    $tmpZip = Join-Path $env:TEMP ("wrt-dl-{0}.zip" -f [guid]::NewGuid().ToString('N'))
    $tmpDir = $tmpZip -replace '\.zip$', ''
    try {
        Invoke-WebRequest -Uri $ver.Zip -OutFile $tmpZip -Headers @{ 'User-Agent' = 'WRT-TestCenter' } -UseBasicParsing -ErrorAction Stop
        Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
        $top = Get-ChildItem -LiteralPath $tmpDir -Directory | Select-Object -First 1
        if (-not $top -or -not (Test-Path (Join-Path $top.FullName 'tools'))) { throw "this version has no tools folder" }
        New-Item -ItemType Directory -Force $into | Out-Null
        Move-Item -LiteralPath $top.FullName -Destination $dest
        Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    } finally { Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    $tools = Join-Path $dest 'tools'
    $info = Get-ToolsInfo $tools
    @{ Ref = $ver.Ref; Downloaded = (Get-Date).ToString('s'); Hashes = $info.Files } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tools $SourceFile) -Encoding UTF8
    $tools
}

# ---------------------------------------------------------------- reports
# lines a test reports on purpose (the test's own expected failures, or what a VM cannot do) - shown, never counted as a problem
$ExpectedById = @{
    'automation' = @('TEST: winget missing', 'winget is not available', '3 task\(s\) ran: 2 passed, 1 failed')
    'regression' = @('C2-(stop-on-fail|no-popups-no-html) : 3 task\(s\) ran: 2 passed, 1 failed', 'Unable to get User Principal Name', 'is not a domain user')
    'logs'       = @('dism /get-(packages|drivers) failed \(exit code 87\)', 'INFO\s+copied\s+0\s+failed\s+2', 'ERROR BINARY - skipped', 'Read-Log\s*:\s*ERROR')
    'windowed'   = @('wusa rejected the request', 'KB5025221 is most likely not installed')
}
function Get-FileLines([string]$p) { @(Get-Content -LiteralPath $p -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }) }
# the summary a test left: summary.txt, else progress.txt, else <name>-summary.txt, else the CSV results, else what it printed
function Get-TestSummary($t, [string]$out) {
    $dirs = @($out)
    if ($t.Results) { $dirs += [Environment]::ExpandEnvironmentVariables($t.Results) }
    foreach ($d in $dirs) {
        foreach ($n in 'summary.txt', 'progress.txt') {
            $p = Join-Path $d $n
            if (Test-Path -LiteralPath $p) { return @{ File = $p; Lines = (Get-FileLines $p) } }
        }
        $p = Get-ChildItem -LiteralPath $d -Filter '*summary*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($p) { return @{ File = $p.FullName; Lines = (Get-FileLines $p.FullName) } }
    }
    # System Info buttons: results.csv (Kind, Button, Result, Detail)
    $csv = Join-Path $out 'results.csv'
    if (Test-Path -LiteralPath $csv) {
        $rows = @(Import-Csv -LiteralPath $csv)
        $res = New-Object 'System.Collections.Generic.List[string]'
        $notOk = New-Object 'System.Collections.Generic.List[string]'
        foreach ($row in $rows) {
            $v = $row.PSObject.Properties.Value
            $res.Add($v[2])
            if ($v[2] -ne 'PASS') { $notOk.Add('NOT OK: ' + $v[1] + ' - ' + $v[3]) }
        }
        $l = New-Object 'System.Collections.Generic.List[string]'
        $l.Add('Buttons: ' + (($res | Group-Object | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '))
        foreach ($s in $notOk) { $l.Add($s) }
        return @{ File = $csv; Lines = $l.ToArray() }
    }
    # WinFixKit status checks: status-summary-<user|admin>.csv + the snapshot line it printed
    $csv = Get-ChildItem -LiteralPath $out -Filter 'status-summary-*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($csv) {
        $rows = @(Import-Csv -LiteralPath $csv.FullName)
        $l = New-Object 'System.Collections.Generic.List[string]'
        $l.Add("Sections checked: $($rows.Count)")
        $snap = @(Get-FileLines (Join-Path $out 'console.txt') | Where-Object { $_ -match '^SNAPSHOT CHANGED' }) | Select-Object -Last 1
        if ($snap) { $l.Add($snap) } else { $l.Add('NO RESULT: the read-only snapshot line is missing') }
        foreach ($row in $rows) {
            if ($row.FirstError -match 'UNCAUGHT') { $l.Add("UNCAUGHT in section $($row.Section): $($row.FirstError)") }
        }
        foreach ($row in $rows) {
            if ([int]$row.ErrorLines -gt 0) { $l.Add("Section $($row.Section): $($row.ErrorLines) line(s) from Windows' own logs about this PC (see status-*.txt) - information, not a tool fault") }
        }
        return @{ File = $csv.FullName; Lines = $l.ToArray() }
    }
    # nothing: the last lines it printed, without the transcript's header and its record of handled errors
    $tx = Get-FileLines (Join-Path $out 'console.txt')
    if (-not $tx) { return @{ File = $null; Lines = @() } }
    $body = New-Object 'System.Collections.Generic.List[string]'
    $inHead = $false
    foreach ($l in $tx) {
        if ($l -match '^\*{10,}') { $inHead = -not $inHead; continue }
        if ($inHead -or $l -match '^(Transcript started|Windows PowerShell transcript|PS>TerminatingError|>> TerminatingError)' -or $l -match '^\s*(At line:|At .+:\d+ char:|\+ |CategoryInfo|FullyQualifiedErrorId|~+$)') { continue }
        $body.Add($l)
    }
    @{ File = $null; Lines = @($body.ToArray() | Select-Object -Last 15) }
}
function Get-ResultStatus($t, $code, [string[]]$lines) {
    if ($t.Kind -eq 'pester') { if ($code -eq 0) { return 'PASSED' } else { return 'FAILED' } }
    if (-not $lines) { return 'NO SUMMARY' }
    if (@(Get-FlaggedLines $t $lines).Count) { 'CHECK' } else { 'OK' }
}
# the summary lines that need a look (failure words, not "0 failed", not a heading, not an expected line of this test)
$script:FlaggedLineMatchRegex = [regex]::new('\b(fail(ed|s|ures?)?|errors?|NO RESULT|UNCAUGHT|not ok|wrong|missing|problem)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:FlaggedLineNotMatchRegex = [regex]::new('^\s*=====|^\s*PASS\b|:\s*$|launcher said|Transcript: |information, not a tool fault', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:FlaggedLineZeroNotMatchRegex = [regex]::new('\b0\s+(fail|error)|(fail\w*|errors?)[^\d\r\n]{0,30}\b0\b(?![.,]\d)|no (failures|errors|issues|problems)|nothing \(read-only confirmed\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function Get-FlaggedLines($t, [string[]]$lines) {
    $exp = @($ExpectedById[$t.Id])
    @($lines | Where-Object {
        $l = $_
        $script:FlaggedLineMatchRegex.IsMatch($l) -and
        -not $script:FlaggedLineNotMatchRegex.IsMatch($l) -and
        -not $script:FlaggedLineZeroNotMatchRegex.IsMatch($l) -and
        -not ($exp | Where-Object { $_ -and $l -match $_ })
    })
}
function Get-MarkdownSummary {
    $ti = $script:RunTools; $e = Get-EnvInfo
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("### Test Center $TestCenterVersion results")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- **Tools:** version $($ti.Version), source: $($ti.Source)" + $(if ($ti.Edited.Count) { " (edited: $($ti.Edited -join ', '))" } else { '' }))
    [void]$sb.AppendLine("- **Windows:** $($e.Windows), language $($e.Language)")
    [void]$sb.AppendLine("- **PowerShell:** $($e.PowerShell); admin: $($e.Admin); monitors: $($e.Monitors)")
    [void]$sb.AppendLine("- **Run:** $($script:RunStarted)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Test | Result | Minutes | Summary |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($r in $script:Results) {
        $first = (@($r.Lines) | Select-Object -First 3) -join '; '
        $cell = (Hide-Identity $first) -replace '\|', '/' ; if ($cell.Length -gt 160) { $cell = $cell.Substring(0, 157) + '...' }
        [void]$sb.AppendLine("| $($r.Name) | **$($r.Status)** | $($r.Minutes) | $cell |")
    }
    $fails = @($script:Results | Where-Object { $_.Status -in 'FAILED', 'CHECK', 'NO SUMMARY', 'NOT STARTED', 'STOPPED' })
    if ($fails.Count) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('<details><summary>Details of tests that need a look</summary>'); [void]$sb.AppendLine(''); [void]$sb.AppendLine('```')
        foreach ($r in $fails) { [void]$sb.AppendLine("== $($r.Name): $($r.Status)"); foreach ($l in @($r.Lines) | Select-Object -First 25) { [void]$sb.AppendLine((Hide-Identity $l)) } }
        [void]$sb.AppendLine('```'); [void]$sb.AppendLine('</details>')
    }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('<details><summary>Script hashes (SHA-256, first 12)</summary>'); [void]$sb.AppendLine('')
    foreach ($k in $ti.Files.Keys) { [void]$sb.AppendLine("- ``$k`` $($ti.Files[$k])") }
    [void]$sb.AppendLine('</details>')
    $sb.ToString()
}
function Get-HtmlReport {
    function Get-SafeHtml($s) { [Net.WebUtility]::HtmlEncode((Hide-Identity ([string]$s))) }
    $ti = $script:RunTools; $e = Get-EnvInfo
    $colors = @{ PASSED = '#1a7f37'; OK = '#1a7f37'; FAILED = '#cf222e'; CHECK = '#bf8700'; 'NO SUMMARY' = '#6e7781'; 'NOT STARTED' = '#6e7781'; STOPPED = '#6e7781' }
    $rows = foreach ($r in $script:Results) {
        "<tr><td>$(Get-SafeHtml $r.Tab)</td><td>$(Get-SafeHtml $r.Name)</td><td style='color:$($colors[$r.Status]);font-weight:bold'>$(Get-SafeHtml $r.Status)</td><td>$($r.Minutes)</td><td>$(Get-SafeHtml $r.Code)</td>" +
        "<td><details><summary>$(Get-SafeHtml ((@($r.Lines) | Select-Object -First 1) -join ''))</summary><pre>$(Get-SafeHtml ((@($r.Lines)) -join "`n"))</pre></details></td></tr>"
    }
    $envRows = ($e.Keys | ForEach-Object { "<tr><th>$_</th><td>$(Get-SafeHtml $e[$_])</td></tr>" }) -join ''
    $hashRows = ($ti.Files.Keys | ForEach-Object { "<tr><td>$(Get-SafeHtml $_)</td><td><code>$($ti.Files[$_])</code></td><td>$(if ($ti.Edited -contains $_) { 'edited' })</td></tr>" }) -join ''
    $counts = ($script:Results | Group-Object Status | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ' &nbsp; '
    @"
<!doctype html><html><head><meta charset="utf-8"><title>Test Center results</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1f2328;background:#fff}table{border-collapse:collapse;margin:8px 0 20px}td,th{border:1px solid #d0d7de;padding:4px 8px;text-align:left;vertical-align:top}th{background:#f6f8fa}pre{white-space:pre-wrap;font-size:12px;margin:4px 0}h1{font-size:22px}h2{font-size:17px;margin-top:24px}</style></head><body>
<h1>Windows Repair Toolkit - Test Center $TestCenterVersion</h1>
<p>Run started $(Get-SafeHtml $script:RunStarted). Tools version <b>$(Get-SafeHtml $ti.Version)</b>, source: $(Get-SafeHtml $ti.Source). &nbsp; $counts</p>
<h2>Results</h2><table><tr><th>Tab</th><th>Test</th><th>Result</th><th>Minutes</th><th>Exit</th><th>Summary</th></tr>$($rows -join "`n")</table>
<h2>Environment</h2><table>$envRows</table>
<h2>Scripts tested</h2><table><tr><th>File</th><th>SHA-256 (first 12)</th><th></th></tr>$hashRows</table>
<h2>Run log</h2><pre>$(Get-SafeHtml $logBox.Text)</pre>
<p>OK / CHECK for script tests are read from each test's summary.txt (CHECK = words like "failed" or "error" were found - read the summary). PASSED / FAILED come from Pester.</p>
</body></html>
"@
}
function Save-Reports {
    if (-not $script:RunRoot -or -not $script:Results.Count) { return }
    [IO.File]::WriteAllText((Join-Path $script:RunRoot 'report.html'), (Get-HtmlReport), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $script:RunRoot 'summary-for-github.md'), (Get-MarkdownSummary), (New-Object Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- window
$form = New-Object Windows.Forms.Form
$form.Text = "Windows Repair Toolkit - Test Center $TestCenterVersion"
$form.Size = New-Object Drawing.Size(1000, 820); $form.MinimumSize = New-Object Drawing.Size(760, 620)
$form.StartPosition = 'CenterScreen'; $form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.AutoScaleMode = 'Dpi'

# --- source of the tools: offline folder or online download
$src = New-Object Windows.Forms.GroupBox; $src.Text = 'Tools to test'; $src.Dock = 'Top'; $src.Height = 168; $src.Padding = New-Object Windows.Forms.Padding(8, 4, 8, 4)
$grid = New-Object Windows.Forms.TableLayoutPanel; $grid.Dock = 'Fill'; $grid.ColumnCount = 4; $grid.RowCount = 4
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize'))); [void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize'))); [void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
function New-Lbl([string]$t) { $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.AutoSize = $true; $l.Anchor = 'Left'; $l }
function New-Btn([string]$t) { $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.AutoSize = $true; $b }
$modeFlow = New-Object Windows.Forms.FlowLayoutPanel; $modeFlow.AutoSize = $true; $modeFlow.Dock = 'Fill'
$rbOff = New-Object Windows.Forms.RadioButton; $rbOff.Text = 'Offline: use a folder on this PC'; $rbOff.AutoSize = $true; $rbOff.Checked = $true
$rbOn  = New-Object Windows.Forms.RadioButton; $rbOn.Text = 'Online: download a version from GitHub'; $rbOn.AutoSize = $true
$modeFlow.Controls.AddRange(@($rbOff, $rbOn))
$grid.Controls.Add((New-Lbl 'Mode:'), 0, 0); $grid.Controls.Add($modeFlow, 1, 0); $grid.SetColumnSpan($modeFlow, 3)
$tbTools = New-Object Windows.Forms.TextBox; $tbTools.Dock = 'Fill'; $tbTools.Text = $ToolsDir
$bBrowse = New-Btn 'Browse...'; $bReload = New-Btn 'Re-check'
$grid.Controls.Add((New-Lbl 'Tools folder:'), 0, 1); $grid.Controls.Add($tbTools, 1, 1); $grid.Controls.Add($bBrowse, 2, 1); $grid.Controls.Add($bReload, 3, 1)
$cbVer = New-Object Windows.Forms.ComboBox; $cbVer.DropDownStyle = 'DropDownList'; $cbVer.Dock = 'Fill'; $cbVer.DisplayMember = 'Label'
$bList = New-Btn 'Get version list'; $bDl = New-Btn 'Download'
$grid.Controls.Add((New-Lbl 'Version:'), 0, 2); $grid.Controls.Add($cbVer, 1, 2); $grid.Controls.Add($bList, 2, 2); $grid.Controls.Add($bDl, 3, 2)
$tbDl = New-Object Windows.Forms.TextBox; $tbDl.Dock = 'Fill'; $tbDl.Text = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WRT-TestCenter'
if (-not [Environment]::GetFolderPath('MyDocuments')) { $tbDl.Text = 'C:\Users\Public\WRT-TestCenter' }
$bDlBrowse = New-Btn 'Browse...'
$grid.Controls.Add((New-Lbl 'Download into:'), 0, 3); $grid.Controls.Add($tbDl, 1, 3); $grid.Controls.Add($bDlBrowse, 2, 3)
$lbInfo = New-Object Windows.Forms.Label; $lbInfo.AutoSize = $true; $lbInfo.Anchor = 'Left'; $grid.Controls.Add($lbInfo, 3, 3)
$src.Controls.Add($grid)

$head = New-Object Windows.Forms.Label; $head.Dock = 'Top'; $head.Height = 60; $head.Padding = New-Object Windows.Forms.Padding(8, 4, 8, 0)
$head.Text = $(if ($IsAdmin) { 'Running as administrator.' } else { 'Not administrator: every [admin] test asks for permission separately. Use "Restart as administrator" for one prompt.' }) +
             "  Monitors: $Monitors.  While tests run, leave the mouse and keyboard alone.`r`nThe tests check the newest toolkit features, so an older version fails the tests of features it does not have yet."

$tabs = New-Object Windows.Forms.TabControl; $tabs.Dock = 'Fill'
$Boxes = @{}; $BaseText = @{}
foreach ($tabName in ($Tests | ForEach-Object { $_.Tab } | Select-Object -Unique)) {
    $page = New-Object Windows.Forms.TabPage $tabName
    $flow = New-Object Windows.Forms.FlowLayoutPanel; $flow.Dock = 'Fill'; $flow.FlowDirection = 'TopDown'; $flow.WrapContents = $false; $flow.AutoScroll = $true; $flow.Padding = New-Object Windows.Forms.Padding(6)
    foreach ($t in ($Tests | Where-Object { $_.Tab -eq $tabName })) {
        $cb = New-Object Windows.Forms.CheckBox; $cb.AutoSize = $true; $cb.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
        $tags = @(); if ($t.Admin) { $tags += 'admin' }; if ($t.Monitors) { $tags += "$($t.Monitors) monitors" }; if ($t.WinPE) { $tags += 'WinPE only' }; $tags += "~$($t.Min) min"
        $BaseText[$t.Id] = "$($t.Name)   [$($tags -join ', ')]"; $cb.Text = $BaseText[$t.Id]; $cb.Tag = $t.Id; $cb.Checked = [bool]$t.Default
        $lb = New-Object Windows.Forms.Label; $lb.AutoSize = $true; $lb.MaximumSize = New-Object Drawing.Size(880, 0); $lb.Text = $t.Desc
        $lb.Margin = New-Object Windows.Forms.Padding(22, 0, 3, 10); $lb.ForeColor = [Drawing.SystemColors]::GrayText
        $flow.Controls.AddRange(@($cb, $lb)); $Boxes[$t.Id] = $cb
    }
    $flow.Add_Resize({ param($s) foreach ($c in $s.Controls) { if ($c -is [Windows.Forms.Label]) { $c.MaximumSize = New-Object Drawing.Size([Math]::Max(200, $s.ClientSize.Width - 50), 0) } } })
    $page.Controls.Add($flow); $tabs.TabPages.Add($page)
}

$bottom = New-Object Windows.Forms.Panel; $bottom.Dock = 'Bottom'; $bottom.Height = 240
$btns = New-Object Windows.Forms.FlowLayoutPanel; $btns.Dock = 'Top'; $btns.AutoSize = $true; $btns.AutoSizeMode = 'GrowAndShrink'; $btns.Padding = New-Object Windows.Forms.Padding(4)
function New-Button([string]$text) { $b = New-Btn $text; $b.Height = 28; $btns.Controls.Add($b); $b }
$bRun = New-Button 'Run selected'; $bStop = New-Button 'Stop'; $bAll = New-Button 'Tick all on this tab'; $bNone = New-Button 'Untick all'
$bOpen = New-Button 'Open results'; $bHtml = New-Button 'Export HTML...'; $bMd = New-Button 'Copy summary for GitHub'; $bGh = New-Button 'Report on GitHub'; $bPack = New-Button 'Pack full results'
$bAdmin = New-Button 'Restart as administrator'
$bStop.Enabled = $false; foreach ($b in $bOpen, $bHtml, $bMd, $bPack) { $b.Enabled = $false }; $bAdmin.Visible = -not $IsAdmin
$logBox = New-Object Windows.Forms.TextBox; $logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Vertical'; $logBox.Dock = 'Fill'
$logBox.Font = New-Object Drawing.Font('Consolas', 9)
$bottom.Controls.Add($logBox); $bottom.Controls.Add($btns)
$form.Controls.Add($tabs); $form.Controls.Add($bottom); $form.Controls.Add($head); $form.Controls.Add($src)

$script:RunRoot = $null; $script:Queue = $null; $script:Current = $null; $script:Report = $null; $script:Versions = @()
function Write-Log([string]$m) {
    $line = '{0:HH:mm:ss}  {1}' -f (Get-Date), $m
    $logBox.AppendText($line + "`r`n")
    if ($script:Report) { Add-Content -LiteralPath $script:Report -Value $line -Encoding UTF8 }
}

# grey out what cannot run here or with these tools
function Update-Availability {
    $dir = $tbTools.Text.Trim()
    $script:Tools = Get-ToolsInfo $dir
    foreach ($t in $Tests) {
        $cb = $Boxes[$t.Id]; $why = $null
        if ($t.Monitors -and $Monitors -lt $t.Monitors) { $why = "needs $($t.Monitors) monitors" }
        if ($t.WinPE -and -not $InWinPE) { $why = 'only inside WinPE' }
        if (-not $t.WinPE -and $InWinPE -and $t.Id -ne 'unit-suite' -and $t.Id -ne 'unit-toolkit') { $why = 'needs a running Windows' }
        if (-not (Test-Path (Join-Path $TestsDir $t.Script))) { $why = "missing tests\$($t.Script)" }
        $need = $NeedsByTab[$t.Tab]
        if (-not $why -and $need -and -not $script:Tools.Files.Contains($need)) { $why = "this tools folder has no $need" }
        if (-not $script:Tools.Ok) { $why = 'choose a tools folder' }
        $cb.Enabled = -not $why; if ($why) { $cb.Checked = $false; $cb.Text = "$($BaseText[$t.Id])  - not available: $why" } else { $cb.Text = $BaseText[$t.Id] }
    }
    $lbInfo.Text = if ($script:Tools.Ok) { "Version $($script:Tools.Version), $($script:Tools.Files.Count) scripts" + $(if ($script:Tools.Edited.Count) { ", $($script:Tools.Edited.Count) edited" } else { '' }) } else { 'No scripts in that folder' }
}
function Update-Mode {
    $on = $rbOn.Checked
    foreach ($c in $cbVer, $bList, $bDl, $tbDl, $bDlBrowse) { $c.Enabled = $on }
}

# copy tests + chosen tools into one folder for the run, so every test finds ..\tools whatever folder was chosen
function New-RunCopy([string]$root) {
    $w = Join-Path $root '_run'
    $r = @{ Repo = $w; Tests = Join-Path $w 'tests'; Tools = Join-Path $w 'tools' }
    New-Item -ItemType Directory -Force $r.Tests, $r.Tools | Out-Null
    Copy-Item (Join-Path $TestsDir '*') $r.Tests -Recurse -Force
    Copy-Item (Join-Path $tbTools.Text.Trim() '*') $r.Tools -Recurse -Force
    # build\ and LICENSE (the Toolkit unit tests use them): from the tested version when it has them, else from Test Center's
    $toolsParent = Split-Path $tbTools.Text.Trim() -Parent
    foreach ($n in 'build', 'LICENSE') {
        $s = Join-Path $toolsParent $n; if (-not (Test-Path $s)) { $s = Join-Path $RepoDir $n }
        if (Test-Path $s) { Copy-Item $s (Join-Path $w $n) -Recurse -Force }
    }
    $r
}

$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
function Complete-Run {
    $timer.Stop(); $script:Current = $null; $bRun.Enabled = $true; $bStop.Enabled = $false
    foreach ($b in $bHtml, $bMd) { $b.Enabled = $script:Results.Count -gt 0 }
    Save-Reports
    $c = ($script:Results | Group-Object Status | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-Log "ALL DONE ($c). Results: $script:RunRoot  (report.html, summary-for-github.md)"; $form.Activate()
    if ($ExitWhenDone) { $form.Close() }
}
function Start-NextTest {
    if (-not $script:Queue -or $script:Queue.Count -eq 0) { Complete-Run; return }
    $t = $script:Queue[0]; $script:Queue = @($script:Queue | Select-Object -Skip 1)
    $out = Join-Path $script:RunRoot $t.Id; New-Item -ItemType Directory -Force $out | Out-Null
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-TestCommand $t $out)))
    $sp = @{ FilePath = $PsExe; ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-EncodedCommand', $enc); PassThru = $true; WindowStyle = 'Minimized' }
    if ($t.Admin -and -not $IsAdmin) { $sp.Verb = 'RunAs' }
    try { $p = Start-Process @sp -ErrorAction Stop }
    catch {
        Write-Log "NOT STARTED  $($t.Name): $($_.Exception.Message)"
        [void]$script:Results.Add([pscustomobject]@{ Tab = $t.Tab; Name = $t.Name; Status = 'NOT STARTED'; Minutes = 0; Code = ''; Lines = @($_.Exception.Message); Folder = $out })
        Start-NextTest; return
    }
    $script:Current = @{ Test = $t; Proc = $p; Start = Get-Date; Out = $out }
    Write-Log "START   $($t.Name)  (about $($t.Min) min)"
    $timer.Start()
}
$timer.Add_Tick({
    $c = $script:Current; if (-not $c) { return }
    if (-not $c.Proc.HasExited) { return }
    $timer.Stop()
    $mins = [Math]::Round(((Get-Date) - $c.Start).TotalMinutes, 1)
    $code = try { $c.Proc.ExitCode } catch { '' }
    $t = $c.Test
    $s = Get-TestSummary $t $c.Out; $lines = @($s.Lines); $sum = $s.File
    # a summary from elsewhere (e.g. %TEMP%) is copied next to the test's other results
    if ($sum -and $sum -notlike "$($c.Out)*") { Copy-Item -LiteralPath $sum (Join-Path $c.Out (Split-Path $sum -Leaf)) -ErrorAction SilentlyContinue }
    $status = if ($c.Stopped) { 'STOPPED' } else { Get-ResultStatus $t $code $lines }
    # CHECK: the lines that caused it come first (log, GitHub summary, HTML)
    if ($status -eq 'CHECK') { $lines = @(Get-FlaggedLines $t $lines | ForEach-Object { "NEEDS A LOOK: $($_.Trim())" }) + $lines }
    [void]$script:Results.Add([pscustomobject]@{ Tab = $t.Tab; Name = $t.Name; Status = $status; Minutes = $mins; Code = $code; Lines = $lines; Folder = $c.Out })
    Write-Log "$status  $($t.Name)  after $mins min, exit code $code"
    $lines | Select-Object -First 12 | ForEach-Object { Write-Log "          $_" }
    Save-Reports
    Start-NextTest
})

$rbOff.Add_CheckedChanged({ Update-Mode }); Update-Mode
$bBrowse.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'The folder with the toolkit scripts (WinSuperTool.ps1, WinFixKit.ps1, ...)'
    if (Test-Path $tbTools.Text) { $d.SelectedPath = $tbTools.Text }
    if ($d.ShowDialog($form) -eq 'OK') { $tbTools.Text = $d.SelectedPath; Update-Availability }
})
$bReload.Add_Click({ Update-Availability })
$tbTools.Add_Leave({ Update-Availability })
$bDlBrowse.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'Where to put downloaded versions'; if ($d.ShowDialog($form) -eq 'OK') { $tbDl.Text = $d.SelectedPath } })
$bList.Add_Click({
    $form.Cursor = 'WaitCursor'
    try { $script:Versions = @(Get-OnlineVersions); $cbVer.Items.Clear(); foreach ($v in $script:Versions) { [void]$cbVer.Items.Add($v) }; if ($cbVer.Items.Count) { $cbVer.SelectedIndex = 0 }; Write-Log "GitHub: $($script:Versions.Count) versions found." }
    catch { Write-Log "Could not read the version list from GitHub: $($_.Exception.Message)" }
    finally { $form.Cursor = 'Default' }
})
$bDl.Add_Click({
    $v = $cbVer.SelectedItem; if (-not $v) { [void][Windows.Forms.MessageBox]::Show('Press "Get version list" and pick a version first.', $form.Text); return }
    $form.Cursor = 'WaitCursor'; Write-Log "Downloading $($v.Ref) from GitHub ..."
    try { $tools = Get-OnlineTools $v $tbDl.Text.Trim(); $tbTools.Text = $tools; Update-Availability; Write-Log "Downloaded $($v.Ref) to $(Split-Path $tools -Parent). You can edit the scripts there; Test Center shows which ones were edited." }
    catch { Write-Log "Download failed: $($_.Exception.Message)" }
    finally { $form.Cursor = 'Default' }
})

$bRun.Add_Click({
    Update-Availability
    $sel = @($Tests | Where-Object { $Boxes[$_.Id].Checked })
    if (-not $sel.Count) { [void][Windows.Forms.MessageBox]::Show('Tick at least one test.', $form.Text); return }
    foreach ($t in @($sel | Where-Object { $_.Warn })) {
        if ([Windows.Forms.MessageBox]::Show($t.Warn + "`r`n`r`nRun '$($t.Name)'?", $form.Text, 'YesNo', 'Warning') -ne 'Yes') { $sel = @($sel | Where-Object { $_.Id -ne $t.Id }) }
    }
    if (-not $sel.Count) { return }
    # the sign-out test goes last
    $sel = @($sel | Where-Object { $_.Id -ne 'scaling' }) + @($sel | Where-Object { $_.Id -eq 'scaling' })
    $base = if ($InWinPE) { 'X:\' } else { 'C:\Users\Public\' }
    $script:RunRoot = $base + 'wrt-testcenter-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Force $script:RunRoot | Out-Null
    $script:Report = Join-Path $script:RunRoot 'report.txt'; $script:Results.Clear(); $script:RunStarted = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    try { $script:Stage = New-RunCopy $script:RunRoot } catch { Write-Log "Could not copy the tests and tools for the run: $($_.Exception.Message)"; return }
    $script:RunTools = $script:Tools
    $total = ($sel | ForEach-Object { $_.Min } | Measure-Object -Sum).Sum
    Write-Log "Test Center ${TestCenterVersion}: $($sel.Count) tests, about $total min. Tools: version $($script:Tools.Version) from $($tbTools.Text) ($($script:Tools.Source))  Admin: $IsAdmin"
    $script:Queue = $sel; $bRun.Enabled = $false; $bStop.Enabled = $true; $bOpen.Enabled = $true; $bPack.Enabled = $true
    Start-NextTest
})
$bStop.Add_Click({
    $script:Queue = @()
    if ($script:Current -and -not $script:Current.Proc.HasExited) {
        $script:Current.Stopped = $true
        try { Stop-Process -Id $script:Current.Proc.Id -Force -ErrorAction Stop; Write-Log "STOPPED $($script:Current.Test.Name)" }
        catch { Write-Log "Could not stop $($script:Current.Test.Name) (it runs as administrator) - close its window yourself. No further tests start." }
    }
})
$bAll.Add_Click({ foreach ($c in $tabs.SelectedTab.Controls[0].Controls) { if ($c -is [Windows.Forms.CheckBox] -and $c.Enabled) { $c.Checked = $true } } })
$bNone.Add_Click({ foreach ($cb in $Boxes.Values) { $cb.Checked = $false } })
$bOpen.Add_Click({ if ($script:RunRoot) { Start-Process explorer.exe $script:RunRoot } })
$bHtml.Add_Click({
    $d = New-Object Windows.Forms.SaveFileDialog; $d.Filter = 'HTML report (*.html)|*.html'; $d.FileName = "TestCenter-report-$(Get-Date -Format 'yyyyMMdd-HHmm').html"
    if ($d.ShowDialog($form) -eq 'OK') { [IO.File]::WriteAllText($d.FileName, (Get-HtmlReport), (New-Object Text.UTF8Encoding($false))); Start-Process $d.FileName }
})
$bMd.Add_Click({
    $file = if ($script:RunRoot) { Join-Path $script:RunRoot 'summary-for-github.md' } else { '' }
    try {
        $md = Get-MarkdownSummary
        # another program can hold the clipboard for a moment: 10 tries, 200 ms apart
        [Windows.Forms.Clipboard]::SetDataObject($md, $true, 10, 200)
        Write-Log "Summary copied (Markdown, no PC or user names). Paste it into a GitHub issue or discussion. The same text is in $file"
    } catch {
        Write-Log "Could not copy to the clipboard ($($_.Exception.Message)). Open this file and copy it from there: $file"
    }
})
$bGh.Add_Click({ Start-Process "$RepoUrl/issues/new/choose" })
# a zip of the whole results folder (every test's console.txt and files) for whoever fixes the failures - NOT for GitHub
$bPack.Add_Click({
    if (-not $script:RunRoot -or -not (Test-Path -LiteralPath $script:RunRoot)) { return }
    if ($script:Current -and -not $script:Current.Proc.HasExited) { [void][Windows.Forms.MessageBox]::Show('Wait until the tests are finished (or press Stop) before packing.', $form.Text); return }
    $zip = $script:RunRoot.TrimEnd('\') + '-full.zip'
    $form.Cursor = 'WaitCursor'
    try {
        Remove-Item -LiteralPath $zip -ErrorAction SilentlyContinue
        $items = @(Get-ChildItem -LiteralPath $script:RunRoot -Force | Where-Object { $_.Name -ne '_run' } | ForEach-Object { $_.FullName })
        Compress-Archive -LiteralPath $items -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
        Write-Log "PACKED the full results to: $zip  ($([Math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)) MB)"
        Write-Log '          It contains this PC''s name, user paths and logs: send it only to whoever fixes the failures, do not post it on GitHub (use summary-for-github.md there).'
        Start-Process explorer.exe "/select,`"$zip`""
    } catch { Write-Log "Packing failed: $($_.Exception.Message)" }
    finally { $form.Cursor = 'Default' }
})
$bAdmin.Add_Click({
    try { Start-Process $PsExe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"" -ErrorAction Stop; $form.Close() } catch {}
})
$form.Add_FormClosing({ param($s, $e)
    if ($script:Current -and -not $script:Current.Proc.HasExited) {
        if ([Windows.Forms.MessageBox]::Show('A test is still running. Close Test Center anyway? (The running test continues; later tests do not start.)', $form.Text, 'YesNo', 'Question') -ne 'Yes') { $e.Cancel = $true }
    }
})
if ($ToolsFolder) { $tbTools.Text = (Resolve-Path -LiteralPath $ToolsFolder -ErrorAction SilentlyContinue).Path; if (-not $tbTools.Text) { $tbTools.Text = $ToolsFolder } }
Update-Availability
if (-not $script:Tools.Ok) { Write-Log "No tools found in $ToolsDir - choose a folder (Offline) or download a version (Online)." }
Write-Log "Choose the tools (top), tick the tests (a tab per tool), then press Run selected."
if ($Run) {
    $form.Add_Shown({
        foreach ($cb in $Boxes.Values) { $cb.Checked = $false }
        foreach ($id in ($Run -split ",") | ForEach-Object { $_.Trim() }) { foreach ($t in $Tests) { if (($id -eq "all" -and -not $t.Warn) -or $t.Id -eq $id) { if ($Boxes[$t.Id].Enabled) { $Boxes[$t.Id].Checked = $true } else { Write-Log "Skipped $($t.Id): not available here" } } } }
        $bRun.PerformClick()
    })
}
[void]$form.ShowDialog()
