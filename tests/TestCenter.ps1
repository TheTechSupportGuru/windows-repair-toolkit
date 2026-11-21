# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# TestCenter.ps1 - one window for every test we run regularly: a tab per tool, a tick box per test, "Run selected".
# The tests themselves are the scripts in this folder; they test the tools in ..\tools.
# Each test runs in its own (minimized) PowerShell window, one after the other. Tests marked [admin] ask for
# administrator rights (start Test Center as administrator to get only one prompt).
# Results: C:\Users\Public\wrt-testcenter-<date-time>\<test>\ plus report.txt for the whole run.
#
# Update this tool only when the test procedures change or a test script is fixed - not with every toolkit release.
#   Start-TestCenter.bat   or   powershell -STA -ExecutionPolicy Bypass -File .\tests\TestCenter.ps1
$TestCenterVersion = '1.0'
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
    @{ Tab = 'WinSuperTool'; Id = 'windowed'; Name = 'Recovery console windows (long)'; Kind = 'ps'; Script = 'Run-Windowed.ps1'; Min = 40; Admin = $true
       Results = '%LOCALAPPDATA%\suite-windowed'
       Desc = 'Checks the Recovery "cmd /c tool & pause" windows really start and chkdsk /f stops at its Y/N question.' }
    # ---- WinFixKit
    @{ Tab = 'WinFixKit'; Id = 'wfk-status-user'; Name = 'Check status: every section (no admin)'; Kind = 'ps'; Script = 'Run-StatusChecks.ps1'; Min = 3
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'Runs every "Check status" block without the GUI and proves nothing changed on the PC.' }
    @{ Tab = 'WinFixKit'; Id = 'wfk-status-admin'; Name = 'Check status: every section (admin)'; Kind = 'ps'; Script = 'Run-StatusChecks.ps1'; Min = 3; Admin = $true
       Args = [ordered]@{ OutDir = '{out}' }
       Desc = 'The same as administrator (more sections can read their data).' }
    @{ Tab = 'WinFixKit'; Id = 'wfk-fixundo'; Name = 'Apply every fix, then undo it (TEST VM ONLY)'; Kind = 'ps'; Script = 'Run-Phase3.ps1'; Min = 60; Admin = $true
       Results = '%TEMP%\suite-phase3'
       Warn = 'This test REALLY CHANGES this PC (registry, services, firewall, sharing) and undoes every change with WinFixKit''s own backups. Only run it on a TEST virtual machine AFTER taking a snapshot. Is the snapshot taken?'
       Desc = 'Applies each fix for real and undoes it with WinFixKit''s backups. Take a VM snapshot first.' }
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
function ConvertTo-PsLiteral($v) {
    if ($v -is [bool]) { if ($v) { return '$true' } else { return '$false' } }
    if ($v -is [array]) { return '@(' + (($v | ForEach-Object { ConvertTo-PsLiteral $_ }) -join ', ') + ')' }
    "'" + ([string]$v -replace "'", "''") + "'"
}
function Expand-Value($v, [string]$out) {
    if ($v -is [string]) { return $v.Replace('{out}', $out).Replace('{tools}', $ToolsDir) }
    if ($v -is [array]) { return @($v | ForEach-Object { Expand-Value $_ $out }) }
    $v
}
function Get-TestCommand($t, [string]$out) {
    $path = Join-Path $TestsDir $t.Script
    $log  = Join-Path $out 'console.txt'
    if ($t.Kind -eq 'pester') {
        $run = "Import-Module Pester; `$r = Invoke-Pester -Script $(ConvertTo-PsLiteral $path) -PassThru; " +
               "('Passed {0}  Failed {1}  Skipped {2}' -f `$r.PassedCount, `$r.FailedCount, `$r.SkippedCount) | Set-Content -LiteralPath $(ConvertTo-PsLiteral (Join-Path $out 'summary.txt')); `$code = `$r.FailedCount"
    } else {
        $pairs = @(); if ($t.Args) { foreach ($k in $t.Args.Keys) { $pairs += "$k = $(ConvertTo-PsLiteral (Expand-Value $t.Args[$k] $out))" } }
        $run = "`$p = @{ $($pairs -join '; ') }; & $(ConvertTo-PsLiteral $path) @p; `$code = [int]`$LASTEXITCODE"
    }
    "Set-Location $(ConvertTo-PsLiteral $RepoDir); try { Start-Transcript -Path $(ConvertTo-PsLiteral $log) -Force | Out-Null } catch {}; `$code = 0; $run; try { Stop-Transcript | Out-Null } catch {}; exit `$code"
}

# ---------------------------------------------------------------- window
$form = New-Object Windows.Forms.Form
$form.Text = "Windows Repair Toolkit - Test Center $TestCenterVersion"
$form.Size = New-Object Drawing.Size(980, 760); $form.MinimumSize = New-Object Drawing.Size(720, 560)
$form.StartPosition = 'CenterScreen'; $form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.AutoScaleMode = 'Dpi'

$head = New-Object Windows.Forms.Label; $head.Dock = 'Top'; $head.Height = 54; $head.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 0)
$head.Text = "Tests the tools in: $ToolsDir`r`n" + $(if ($IsAdmin) { 'Running as administrator.' } else { 'Not administrator: every [admin] test asks for permission separately. Use "Restart as administrator" for one prompt.' }) +
             "  Monitors: $Monitors.  While tests run, leave the mouse and keyboard alone."

$tabs = New-Object Windows.Forms.TabControl; $tabs.Dock = 'Fill'
$Boxes = @{}
foreach ($tabName in ($Tests | ForEach-Object { $_.Tab } | Select-Object -Unique)) {
    $page = New-Object Windows.Forms.TabPage $tabName
    $flow = New-Object Windows.Forms.FlowLayoutPanel; $flow.Dock = 'Fill'; $flow.FlowDirection = 'TopDown'; $flow.WrapContents = $false; $flow.AutoScroll = $true; $flow.Padding = New-Object Windows.Forms.Padding(6)
    foreach ($t in ($Tests | Where-Object { $_.Tab -eq $tabName })) {
        $cb = New-Object Windows.Forms.CheckBox; $cb.AutoSize = $true; $cb.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
        $tags = @(); if ($t.Admin) { $tags += 'admin' }; if ($t.Monitors) { $tags += "$($t.Monitors) monitors" }; if ($t.WinPE) { $tags += 'WinPE only' }; $tags += "~$($t.Min) min"
        $cb.Text = "$($t.Name)   [$($tags -join ', ')]"; $cb.Tag = $t.Id; $cb.Checked = [bool]$t.Default
        $why = $null
        if ($t.Monitors -and $Monitors -lt $t.Monitors) { $why = "needs $($t.Monitors) monitors" }
        if ($t.WinPE -and -not $InWinPE) { $why = 'only inside WinPE' }
        if (-not $t.WinPE -and $InWinPE -and $t.Id -ne 'unit-suite' -and $t.Id -ne 'unit-toolkit') { $why = 'needs a running Windows' }
        if (-not (Test-Path (Join-Path $TestsDir $t.Script))) { $why = "missing $($t.Script)" }
        if ($why) { $cb.Checked = $false; $cb.Enabled = $false; $cb.Text += "  - not available here: $why" }
        $lb = New-Object Windows.Forms.Label; $lb.AutoSize = $true; $lb.MaximumSize = New-Object Drawing.Size(880, 0); $lb.Text = $t.Desc
        $lb.Margin = New-Object Windows.Forms.Padding(22, 0, 3, 10); $lb.ForeColor = [Drawing.SystemColors]::GrayText
        $flow.Controls.AddRange(@($cb, $lb)); $Boxes[$t.Id] = $cb
    }
    $flow.Add_Resize({ param($s) foreach ($c in $s.Controls) { if ($c -is [Windows.Forms.Label]) { $c.MaximumSize = New-Object Drawing.Size([Math]::Max(200, $s.ClientSize.Width - 50), 0) } } })
    $page.Controls.Add($flow); $tabs.TabPages.Add($page)
}

$bottom = New-Object Windows.Forms.Panel; $bottom.Dock = 'Bottom'; $bottom.Height = 250
$btns = New-Object Windows.Forms.FlowLayoutPanel; $btns.Dock = 'Top'; $btns.Height = 38; $btns.Padding = New-Object Windows.Forms.Padding(4)
function New-Button([string]$text) { $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.AutoSize = $true; $b.Height = 28; $btns.Controls.Add($b); $b }
$bRun = New-Button 'Run selected'; $bStop = New-Button 'Stop'; $bAll = New-Button 'Tick all on this tab'; $bNone = New-Button 'Untick all'
$bOpen = New-Button 'Open results folder'; $bAdmin = New-Button 'Restart as administrator'
$bStop.Enabled = $false; $bOpen.Enabled = $false; $bAdmin.Visible = -not $IsAdmin
$logBox = New-Object Windows.Forms.TextBox; $logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Vertical'; $logBox.Dock = 'Fill'
$logBox.Font = New-Object Drawing.Font('Consolas', 9)
$bottom.Controls.Add($logBox); $bottom.Controls.Add($btns)
$form.Controls.Add($tabs); $form.Controls.Add($bottom); $form.Controls.Add($head)

$script:RunRoot = $null; $script:Queue = $null; $script:Current = $null; $script:Report = $null
function Write-Log([string]$m) {
    $line = '{0:HH:mm:ss}  {1}' -f (Get-Date), $m
    $logBox.AppendText($line + "`r`n")
    if ($script:Report) { Add-Content -LiteralPath $script:Report -Value $line -Encoding UTF8 }
}

$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
function Start-NextTest {
    if (-not $script:Queue -or $script:Queue.Count -eq 0) {
        $timer.Stop(); $script:Current = $null; $bRun.Enabled = $true; $bStop.Enabled = $false
        Write-Log "ALL DONE. Results: $script:RunRoot"; $form.Activate(); return
    }
    $t = $script:Queue[0]; $script:Queue = @($script:Queue | Select-Object -Skip 1)
    $out = Join-Path $script:RunRoot $t.Id; New-Item -ItemType Directory -Force $out | Out-Null
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-TestCommand $t $out)))
    $sp = @{ FilePath = $PsExe; ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-EncodedCommand', $enc); PassThru = $true; WindowStyle = 'Minimized' }
    if ($t.Admin -and -not $IsAdmin) { $sp.Verb = 'RunAs' }
    try { $p = Start-Process @sp -ErrorAction Stop }
    catch { Write-Log "SKIPPED $($t.Name): could not start ($($_.Exception.Message))"; Start-NextTest; return }
    $script:Current = @{ Test = $t; Proc = $p; Start = Get-Date; Out = $out }
    Write-Log "START   $($t.Name)  (about $($t.Min) min)"
    $timer.Start()
}
$timer.Add_Tick({
    $c = $script:Current; if (-not $c) { return }
    if (-not $c.Proc.HasExited) { return }
    $timer.Stop()
    $mins = [Math]::Round(((Get-Date) - $c.Start).TotalMinutes, 1)
    $code = try { $c.Proc.ExitCode } catch { '?' }
    $t = $c.Test
    $where = if ($t.Results) { [Environment]::ExpandEnvironmentVariables($t.Results) + '  (and ' + $c.Out + ')' } else { $c.Out }
    $state = if ($t.Kind -eq 'pester') { if ($code -eq 0) { 'PASSED' } else { "FAILED ($code failing)" } } else { 'FINISHED' }
    Write-Log "$state  $($t.Name)  after $mins min, exit code $code"
    $sum = Join-Path $c.Out 'summary.txt'
    if (Test-Path $sum) { Get-Content $sum -TotalCount 15 | Where-Object { $_.Trim() } | ForEach-Object { Write-Log "          $_" } }
    Write-Log "          results: $where"
    Start-NextTest
})

$bRun.Add_Click({
    $sel = @($Tests | Where-Object { $Boxes[$_.Id].Checked })
    if (-not $sel.Count) { [void][Windows.Forms.MessageBox]::Show('Tick at least one test.', $form.Text); return }
    foreach ($t in @($sel | Where-Object { $_.Warn })) {
        if ([Windows.Forms.MessageBox]::Show($t.Warn + "`r`n`r`nRun '$($t.Name)'?", $form.Text, 'YesNo', 'Warning') -ne 'Yes') { $sel = @($sel | Where-Object { $_.Id -ne $t.Id }) }
    }
    if (-not $sel.Count) { return }
    # the sign-out test goes last
    $sel = @($sel | Where-Object { $_.Id -ne 'scaling' }) + @($sel | Where-Object { $_.Id -eq 'scaling' })
    $script:RunRoot = 'C:\Users\Public\wrt-testcenter-' + (Get-Date -Format 'yyyyMMdd-HHmm')
    if ($InWinPE) { $script:RunRoot = 'X:\wrt-testcenter-' + (Get-Date -Format 'yyyyMMdd-HHmm') }
    New-Item -ItemType Directory -Force $script:RunRoot | Out-Null
    $script:Report = Join-Path $script:RunRoot 'report.txt'
    $total = ($sel | Measure-Object -Property Min -Sum).Sum
    Write-Log "Test Center ${TestCenterVersion}: $($sel.Count) tests, about $total min. Tools: $ToolsDir  Admin: $IsAdmin"
    $script:Queue = $sel; $bRun.Enabled = $false; $bStop.Enabled = $true; $bOpen.Enabled = $true
    Start-NextTest
})
$bStop.Add_Click({
    $script:Queue = @()
    if ($script:Current -and -not $script:Current.Proc.HasExited) {
        try { Stop-Process -Id $script:Current.Proc.Id -Force -ErrorAction Stop; Write-Log "STOPPED $($script:Current.Test.Name)" }
        catch { Write-Log "Could not stop $($script:Current.Test.Name) (it runs as administrator) - close its window yourself. No further tests start." }
    }
})
$bAll.Add_Click({ foreach ($c in $tabs.SelectedTab.Controls[0].Controls) { if ($c -is [Windows.Forms.CheckBox] -and $c.Enabled) { $c.Checked = $true } } })
$bNone.Add_Click({ foreach ($cb in $Boxes.Values) { $cb.Checked = $false } })
$bOpen.Add_Click({ if ($script:RunRoot) { Start-Process explorer.exe $script:RunRoot } })
$bAdmin.Add_Click({
    try { Start-Process $PsExe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"" -ErrorAction Stop; $form.Close() } catch {}
})
$form.Add_FormClosing({ param($s, $e)
    if ($script:Current -and -not $script:Current.Proc.HasExited) {
        if ([Windows.Forms.MessageBox]::Show('A test is still running. Close Test Center anyway? (The running test continues; later tests do not start.)', $form.Text, 'YesNo', 'Question') -ne 'Yes') { $e.Cancel = $true }
    }
})
if (-not (Test-Path (Join-Path $ToolsDir 'WinSuperTool.ps1'))) {
    [void][Windows.Forms.MessageBox]::Show("The tools folder was not found next to the tests folder:`r`n$ToolsDir`r`n`r`nKeep the 'tests' and 'tools' folders together.", $form.Text, 'OK', 'Warning')
}
Write-Log "Tick the tests to run (a tab per tool), then press Run selected."
[void]$form.ShowDialog()
