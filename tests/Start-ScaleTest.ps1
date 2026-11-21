# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Start-ScaleTest.ps1 - tests every tool at REAL display scaling of the MAIN monitor (150 %, then 200 %).
# The tools take the main monitor's scaling only when Windows starts the session, so each step needs a sign-out.
# This script does the rest by itself:
#   1. sets the main monitor to the first scaling and asks you to sign out
#   2. after you sign in again it runs the resize audit (all sizes, both monitors) - do not use the mouse meanwhile
#   3. sets the next scaling and asks you to sign out again ... after the last one it puts your scaling back
# No admin rights needed. Results: C:\Users\Public\wrt-scale-test\summary.txt
#
#   powershell -ExecutionPolicy Bypass -File .\tests\Start-ScaleTest.ps1              (start: 150 % then 200 %)
#   powershell -ExecutionPolicy Bypass -File .\tests\Start-ScaleTest.ps1 -Scales 125  (other scalings)
#   powershell -ExecutionPolicy Bypass -File .\tests\Start-ScaleTest.ps1 -Step cancel (stop and put everything back)
param([ValidateSet('start', 'continue', 'cancel')][string]$Step = 'start', [int[]]$Scales = @(150, 200))
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$Root = 'C:\Users\Public\wrt-scale-test'; $StateFile = Join-Path $Root 'state.json'; $Sum = Join-Path $Root 'summary.txt'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; $RunName = 'WrtScaleTest'
$Audit = Join-Path $PSScriptRoot 'Run-ResizeAudit.ps1'
$Main = ([Windows.Forms.Screen]::PrimaryScreen).DeviceName
# the per-monitor scaling helper (WrtMonDpi) is taken from the resize audit, so there is one copy of it
$a = [IO.File]::ReadAllText($Audit); $i = $a.IndexOf('public static class WrtMonDpi'); $i = $a.LastIndexOf('Add-Type -TypeDefinition @"', $i); $j = $a.IndexOf('"@', $i) + 2
. ([scriptblock]::Create($a.Substring($i, $j - $i)))

function Write-Sum([string]$m) { New-Item -ItemType Directory -Force $Root | Out-Null; Add-Content -LiteralPath $Sum ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m) }
function Ask([string]$t) { [Windows.Forms.MessageBox]::Show($t, 'Windows Repair Toolkit - scaling test', 'YesNo', 'Question') -eq 'Yes' }
function Say([string]$t) { [void][Windows.Forms.MessageBox]::Show($t, 'Windows Repair Toolkit - scaling test', 'OK', 'Information') }
function Save-State($s) { $s | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8 }
function Set-NextRun { New-Item -Path $RunKey -Force | Out-Null; Set-ItemProperty -Path $RunKey -Name $RunName -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File "{0}" -Step continue' -f $PSCommandPath) }
function Set-MainScale([int]$pct) { $rc = [WrtMonDpi]::Set($Main, $pct); Start-Sleep 2; Write-Sum ("main monitor scaling -> $pct % (result $rc, now $([WrtMonDpi]::Current($Main)) %)"); $rc }
function Invoke-SignOut { & shutdown.exe /l }

switch ($Step) {
    'cancel' {
        if (Test-Path $StateFile) { $s = Get-Content $StateFile -Raw | ConvertFrom-Json; [void](Set-MainScale ([int]$s.Original)) }
        Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue; Remove-Item $StateFile -ErrorAction SilentlyContinue
        Write-Sum 'cancelled, scaling put back'; Say 'The scaling test is stopped and the scaling is put back. Sign out and in once so Windows uses it everywhere.'
    }
    'start' {
        New-Item -ItemType Directory -Force $Root | Out-Null
        $orig = [WrtMonDpi]::Current($Main)
        if (-not $orig) { Say 'Windows did not report the main monitor''s scaling, so the test cannot run on this PC.'; return }
        $s = [ordered]@{ Original = $orig; Queue = @($Scales); Started = (Get-Date).ToString('s') }
        Write-Sum ("START main monitor $Main at $orig %, screens: " + (([Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.DeviceName) $($_.Bounds)" }) -join '; ') + "; scalings to test: $($Scales -join ', ') %")
        if ((Set-MainScale $Scales[0]) -ne 0) { Say "Windows did not accept $($Scales[0]) % on this monitor. Try other values with -Scales."; return }
        Save-State $s; Set-NextRun
        if (Ask ("The main monitor is now at $($Scales[0]) %.`n`nWindows uses it for these tools only after you sign out. After you sign in again the test starts by itself and takes about 15-25 minutes: please do not use the mouse or keyboard until it says it is done.`n`nSave your work. Sign out now?")) { Invoke-SignOut }
        else { Say 'OK - sign out yourself when you are ready. The test starts after the next sign-in. To stop it: run this script with -Step cancel.' }
    }
    'continue' {
        if (-not (Test-Path $StateFile)) { return }
        $s = Get-Content $StateFile -Raw | ConvertFrom-Json; $q = @($s.Queue); $pct = [int]$q[0]
        Start-Sleep -Seconds 40      # let the desktop finish starting
        $g = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $sysDpi = $g.DpiX; $g.Dispose()
        Write-Sum ("RUN at $pct %: Windows reports system DPI $sysDpi (= {0:N0} %), main monitor $([WrtMonDpi]::Current($Main)) %" -f ($sysDpi / 0.96))
        $o1 = Join-Path $Root "sizes-$pct"; $o2 = Join-Path $Root "monitors-$pct"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Audit -OutDir $o1 -Parallel -Sizes 'min,1280x680,1920x1040,2560x1400,75%,max' *> $null
        $mat = if ([Windows.Forms.Screen]::AllScreens.Count -gt 1) { 'mon:2,min,75%,max,maxon:2,mon:1,span,mon:2,span,solo,extend,mon:2' } else { 'res:1920x1080,min,res:1280x720,min,res:back,max' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Audit -OutDir $o2 -Sizes $mat *> $null
        foreach ($o in $o1, $o2) { $r = Get-Content (Join-Path $o 'summary.txt') -ErrorAction SilentlyContinue | Select-Object -Skip 3 | Where-Object { $_ -and $_ -notmatch 'Sizes actually' } | Select-Object -First 12; Write-Sum ("  {0}: {1}" -f (Split-Path $o -Leaf), $(if ($r) { $r -join ' | ' } else { 'NO RESULT' })) }
        $q = @($q | Select-Object -Skip 1)
        if ($q.Count) {
            $s.Queue = $q; Save-State $s; [void](Set-MainScale ([int]$q[0])); Set-NextRun
            if (Ask ("The test at $pct % is done.`n`nNext: $($q[0]) %. Sign out now? After you sign in it runs by itself again (do not use the mouse until it says it is done).")) { Invoke-SignOut }
            else { Say 'OK - it continues after your next sign-in. To stop it: run this script with -Step cancel.' }
        } else {
            [void](Set-MainScale ([int]$s.Original)); Remove-Item $StateFile -ErrorAction SilentlyContinue
            Write-Sum "DONE - scaling put back to $($s.Original) %"
            Start-Process notepad.exe $Sum
            if (Ask ("The scaling test is finished. The results are in $Sum (open in Notepad).`n`nThe scaling is put back to $($s.Original) %. Sign out once more so every program uses it again?")) { Invoke-SignOut }
        }
    }
}
