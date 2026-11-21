# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-Regression.ps1 - the full elevated regression in one run (start it AS ADMINISTRATOR, one UAC prompt):
#   A  Live Monitor, every item + live activity                      (Run-MonitorLive.ps1)
#   B  Recovery summaries on real read-only scans                    (Run-TaskCapture.ps1 -Elevated)
#   C  Automation, real read-only / check tasks (8)                  (Run-AutomationSmoke.ps1 -RealQueue)
#   C2 Automation options with test tasks: stop on fail, popups off, HTML off
#   C3 Automation REPAIR tasks (only with -Repairs: they repair if needed and change the PC - take a VM snapshot first)
#   C4 Automation INSTALL tasks (only with -Installs: Windows Update installs updates, winget upgrades every app)
#   D  WinFixKit status checks, read-only with before/after snapshot (Run-StatusChecks.ps1)
#   E  WinRepairTool + Monitor-Logs checks, log collection, every stable tool opened as admin (Run-V18-Verify.ps1)
#   F  System Info tab: every button, Copy all, Save as..., the 42 Windows tools (Run-SystemInfoButtons.ps1)
# Changes: one test event in the "Windows PowerShell" log; the check tasks do what they say (Windows Update CHECK,
# winget LIST, Defender update + quick scan, a restore point only when System Protection is on). The 1.5 GB log
# collection copy of part E is deleted at the end (it holds this PC's logs).
#   .\tests\Run-Regression.ps1                                   (the beta)
#   .\tests\Run-Regression.ps1 -Script .\tools\WinSuperTool.ps1  (after the beta is promoted)
#   .\tests\Run-Regression.ps1 -Parts A,C,F                      (some parts only)
param([string]$Script = (Join-Path (Split-Path $PSScriptRoot -Parent) 'beta\WinSuperTool.ps1'),
      [string]$OutDir = ('C:\Users\Public\wrt-regression-' + (Get-Date -Format 'yyyyMMdd-HHmm')),
      [string[]]$Parts = @('A', 'B', 'C', 'C2', 'D', 'E', 'F'), [switch]$Repairs, [switch]$Installs)
$ErrorActionPreference = 'Continue'
$Script = (Resolve-Path $Script).Path
$Parts = @($Parts | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
if ($Repairs) { $Parts += 'C3' }; if ($Installs) { $Parts += 'C4' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$prog = Join-Path $OutDir 'progress.txt'
function P([string]$m) { Add-Content -LiteralPath $prog ('{0:HH:mm:ss} {1}' -f (Get-Date), $m) }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
P "start  admin: $isAdmin  script: $Script  parts: $($Parts -join ',')"
if (-not $isAdmin) { P 'STOPPED: run this as administrator'; return }
$ps = Join-Path $PSHOME 'powershell.exe'
function Invoke-Auto([string]$name, [string[]]$extra) {
    $a = @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\Run-AutomationSmoke.ps1`"", '-Script', "`"$Script`"", '-OutDir', "`"$OutDir\$name`"") + $extra
    Start-Process $ps -Wait -ArgumentList $a
    $s = Join-Path $OutDir "$name\automation-summary.txt"
    P ("  $name : " + $(if (Test-Path $s) { ((Get-Content $s | Where-Object { $_ -match 'task\(s\) ran' }) -join ' ').Trim() } else { 'NO SUMMARY' }))
}
foreach ($part in $Parts) {
    switch ($part) {
        'A'  { P 'A  Live Monitor'; $o = & "$PSScriptRoot\Run-MonitorLive.ps1" -Script $Script -OutDir "$OutDir\A-monitor" 2>&1 | Out-String; [IO.File]::WriteAllText("$OutDir\A-monitor.txt", $o)
               P ("  A : {0} passed, {1} failed" -f @($o -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\s+PASS' }).Count, @($o -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\s+FAIL' }).Count) }
        'B'  { P 'B  Recovery summaries on real scans'; $o = & "$PSScriptRoot\Run-TaskCapture.ps1" -Script $Script -OutDir "$OutDir\B-capture" -Elevated 2>&1 | Out-String; [IO.File]::WriteAllText("$OutDir\B-capture.txt", $o)
               foreach ($l in ($o -split "`r?`n" | Where-Object { $_ -match '^=== |FIND:' })) { P "  $l" } }
        'C'  { P 'C  Automation, 8 real check tasks'; Invoke-Auto 'C-auto-checks' @('-RealQueue', 'restore-point,sfc-verify,dism-check,dism-scan,chkdsk-scan,winupdate-check,winget-check,defender') }
        'C2' { P 'C2 Automation options (test tasks)'
               Invoke-Auto 'C2-stop-on-fail' @('-StopOnFail')
               Invoke-Auto 'C2-no-popups-no-html' @('-NoPopups', '-NoHtml') }
        'C3' { P 'C3 Automation REPAIR tasks'; Invoke-Auto 'C3-auto-repairs' @('-RealQueue', 'sfc-verify-fix,dism-scan-fix,dism-restore,sfc-scannow,dism-cleanup') }
        'C4' { P 'C4 Automation INSTALL tasks'; Invoke-Auto 'C4-auto-installs' @('-RealQueue', 'restore-point,winupdate,winget') }
        'D'  { P 'D  WinFixKit status checks'; $o = & "$PSScriptRoot\Run-StatusChecks.ps1" -OutDir "$OutDir\D-status" 2>&1 | Out-String; [IO.File]::WriteAllText("$OutDir\D-status.txt", $o)
               P ("  D : " + (($o -split "`r?`n" | Where-Object { $_ -match 'SNAPSHOT' }) -join ' ')) }
        'E'  { P 'E  WinRepairTool / Monitor-Logs / log collection / tools opened'; & "$PSScriptRoot\Run-V18-Verify.ps1" *> "$OutDir\E-v18.txt"
               Copy-Item "$env:TEMP\suite-v18\summary.txt" "$OutDir\E-v18-summary.txt" -ErrorAction SilentlyContinue
               Copy-Item "$env:TEMP\suite-smoke\summary.txt" "$OutDir\E-smoke-summary.txt" -ErrorAction SilentlyContinue
               Get-Content "$env:TEMP\suite-logs\summary.txt" -ErrorAction SilentlyContinue | Select-Object -Last 30 | Set-Content "$OutDir\E-logs-summary.txt"
               P ("  E : " + @(Select-String -Path "$OutDir\E-v18-summary.txt" -Pattern '\[PASS\]' -ErrorAction SilentlyContinue).Count + ' PASS, ' + @(Select-String -Path "$OutDir\E-v18-summary.txt" -Pattern '\[FAIL\]' -ErrorAction SilentlyContinue).Count + ' FAIL')
               Remove-Item "$env:TEMP\suite-logs" -Recurse -Force -ErrorAction SilentlyContinue }
        'F'  { P 'F  System Info buttons'; Start-Process $ps -Wait -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\Run-SystemInfoButtons.ps1`"", '-Beta', "`"$Script`"", '-Out', "`"$OutDir\F-sysinfo`""
               $r = @(Import-Csv "$OutDir\F-sysinfo\results.csv" -Header Kind, Name, Result, Detail -ErrorAction SilentlyContinue)
               P ("  F : " + (($r | Group-Object Result | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')) }
        default { P "unknown part '$part' - skipped" }
    }
}
P 'DONE'
