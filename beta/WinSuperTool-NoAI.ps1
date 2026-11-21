#requires -Version 5.1
# Version 1.9 BETA 5 (2026-11-20) - BETA build, not the stable release. What changed: docs/changes/V1.9-beta.5.md
# NO-AI EDITION - generated from WinSuperTool.ps1 by build/Build-NoAIEdition.ps1; do not edit by hand.
# The AI Analyze tab, the phone QR login, the "Send key logs to AI" button and all code that talks to an AI service
# or listens on the network are left out. Everything else is identical to WinSuperTool.ps1 of the same version.
# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file or https://www.gnu.org/licenses/.
# BETA: Recovery task summaries, per-task log monitors, the System Info tab and the Automation tab are new and only lightly
# tested. Stable version: tools\ (1.8).
<#
    WinSuperTool.ps1  -  all-in-one Windows tech toolkit (one file, no extra libraries)
    Runs on Windows 10 / 11 and in WinPE (built for Hiren's BootCD PE 11).

    Target Windows bar (top): every tab that works on an installation uses the one picked there.
    Multiple installations are detected, warned about, and never pre-selected.

    Tabs
      1  Collect Logs   Windows Update, DISM/CBS, Event Viewer, crashes, setup/upgrade, system info.
                        Works on the running Windows OR an offline install (WinPE / second drive).
      2  Live Monitor   one window per log (Get-Content <log> -Tail <N> -Wait), live Event Viewer
                        channels, folder watchers, paste-any-path section.
      4  Mount          mount / unmount partitions with diskpart or Storage cmdlets
                        (whitelisted, non-destructive commands only), remembered between runs.
      5  Safe Mode      safeboot minimal: edit the boot entry or add a separate boot-menu clone.
      6  Sysprep        A generalize (+ optional /mode:vm), B1 audit, B2 OOBE, opt-in pre-flight
                        checks, optional answer file.
      7  Unattend       build / preview / save / deploy unattend.xml with checkboxes.
      8  Recovery       EXPERIMENTAL boot-repair tools. BETA: pass / fail summary + live logs per task.
      9  System Info    BETA: Wi-Fi passwords, Windows version + keys, network, Bluetooth, video, audio;
                        buttons for the built-in Windows tools.
     10  Automation     BETA: a queue of up to 10 tasks (restore point, SFC, DISM, chkdsk, Windows Update,
                        winget, Defender) run one after another, with a summary per task and at the end.

    Start it with WinSuperTool.bat (same folder). Every BCD change is backed up first.
    Mount memory, BCD backups and the activity log live in WinSuperTool-Data next to this script.
#>

$ErrorActionPreference = 'Continue'
$AppName = 'Windows Super Tool 1.9 BETA 5 (no-AI edition)'
$NL      = "`r`n"
$IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'

# ---- relaunch elevated, 64-bit and STA when needed (WinPE already runs as SYSTEM) ----
if ($PSCommandPath) {
    $psExe  = Join-Path $PSHOME 'powershell.exe'
    $reason = @()
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $native = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path $native) { $psExe = $native; $reason += '64-bit' }
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { $reason += 'STA' }
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $argLine   = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    if (-not $isAdmin -and -not $IsWinPE) {
        try { Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argLine -ErrorAction Stop }
        catch { Write-Host "Administrator rights are required: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep -Seconds 5 }
        exit
    }
    if ($reason.Count) { Start-Process -FilePath $psExe -ArgumentList $argLine; exit }
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------------------------
#  Window helpers - the same block in every Windows Repair Toolkit tool (since 1.8.1):
#  display scaling, splash screen, fit to screen, scrolling instead of squeezing.
# ---------------------------------------------------------------------------------------------
# Sharp, unclipped text on 125 % / 150 % / 200 % displays: this process scales its own windows
# (AutoScaleMode Dpi on every form) instead of Windows stretching a blurry bitmap of them.
try { Add-Type -Namespace WrtUi -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop; [void][WrtUi.Dpi]::SetProcessDPIAware() } catch {}
try { Add-Type -Namespace WrtUi -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);' -ErrorAction Stop } catch {}
# The scaling is switched on when the form LOADS: WinForms only scales what exists at that moment, so this way the
# finished window and every control in it scale together (setting it at creation scaled nothing inside the window).
function Set-WrtScaling($f) {
    $f.Add_Load({
        $this.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96); $this.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
        $k = Get-WrtScale $this
        if ($k -gt 1.01) { Resize-WrtColumns $this $k }
        Move-WrtIntoView $this
    })
}
# WinForms centres a window using its size BEFORE scaling, so a scaled window grew past the right and bottom edge
# of the screen: centre it again with its final size and keep it inside the screen's working area.
function Move-WrtIntoView($f) {
    try {
        $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea
        if ($f.MinimumSize.Width -gt $wa.Width -or $f.MinimumSize.Height -gt $wa.Height) { $f.MinimumSize = New-Object Drawing.Size([Math]::Min($f.MinimumSize.Width, $wa.Width), [Math]::Min($f.MinimumSize.Height, $wa.Height)) }
        if ($f.Width -gt $wa.Width) { $f.Width = $wa.Width }
        if ($f.Height -gt $wa.Height) { $f.Height = $wa.Height }
        $sp = [string]$f.StartPosition; $r = $null
        if ($sp -eq 'CenterParent' -and $f.Owner) { $r = $f.Owner.Bounds } elseif ($sp -eq 'CenterScreen' -or $sp -eq 'CenterParent') { $r = $wa }
        $x = $f.Left; $y = $f.Top
        if ($r) { $x = $r.Left + [int](($r.Width - $f.Width) / 2); $y = $r.Top + [int](($r.Height - $f.Height) / 2) }
        $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $f.Width)); $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $f.Height))
        $f.Location = New-Object Drawing.Point($x, $y)
    } catch {}
}
# list view column widths are not scaled by WinForms
function Resize-WrtColumns($parent, [double]$k) {
    foreach ($c in $parent.Controls) {
        if ($c -is [Windows.Forms.ListView]) { foreach ($col in $c.Columns) { $col.Width = [int]($col.Width * $k) } }
        if ($c.Controls.Count) { Resize-WrtColumns $c $k }
    }
}
function Get-WrtScale($f) { try { $s = [double]$f.CurrentAutoScaleDimensions.Width / 96; if ($s -gt 0) { return $s } } catch {}; return 1.0 }
function Show-WrtSplash([string]$what) {
    try {
        $s = New-Object Windows.Forms.Form; Set-WrtScaling $s
        $s.FormBorderStyle = 'None'; $s.StartPosition = 'CenterScreen'; $s.ShowInTaskbar = $false; $s.TopMost = $true
        $s.ClientSize = New-Object Drawing.Size(480, 220); $s.BackColor = [Drawing.Color]::FromArgb(22, 50, 88); $s.Text = 'Windows Repair Toolkit'
        $rows = @(
            @('Windows Repair Toolkit', 22, 'Bold', 34, 48, 'White'),
            @('Brought to you by TheTechSupportGuru', 11, 'Regular', 96, 26, 'White'),
            @('Licensed under GNU GPL v3.0', 10, 'Regular', 124, 24, 'LightSteelBlue'),
            @("Loading $what ...", 9, 'Italic', 182, 22, 'Silver'))
        foreach ($r in $rows) {
            $l = New-Object Windows.Forms.Label
            $l.AutoSize = $false; $l.TextAlign = 'MiddleCenter'; $l.Text = $r[0]
            $l.Font = New-Object Drawing.Font('Segoe UI', [single]$r[1], [Drawing.FontStyle]$r[2])
            $l.ForeColor = [Drawing.Color]::FromName($r[5]); $l.BackColor = [Drawing.Color]::Transparent
            $l.Location = New-Object Drawing.Point(0, $r[3]); $l.Size = New-Object Drawing.Size(480, $r[4])
            $s.Controls.Add($l)
        }
        $s.Show(); $s.Refresh(); [Windows.Forms.Application]::DoEvents()
        $script:WrtSplash = $s; $script:WrtSplashAt = Get-Date
    } catch { $script:WrtSplash = $null }
}
function Close-WrtSplash {
    if (-not $script:WrtSplash) { return }
    try { $left = 1.2 - ((Get-Date) - $script:WrtSplashAt).TotalSeconds; if ($left -gt 0) { Start-Sleep -Milliseconds ([int]($left * 1000)) } } catch {}   # readable for at least ~1 s
    # HIDE it, do not close it: closing a window that was shown before the main window's ShowDialog also ends that
    # ShowDialog, so in 1.8.1 / 1.8.2 Collect-Logs, Monitor-Logs, WinFixKit and ClaudeLogAnalyzer closed by themselves
    # 1-2 s after starting. The splash is closed and disposed when the main window closes (Initialize-WrtWindow).
    try { $script:WrtSplash.Hide() } catch {}
}
# Call right before ShowDialog. Records how much room each scrollable area ($scroll: tab pages, panels) needs at its
# design size, so a small window scrolls instead of squeezing the controls together; sets the minimum size; opens
# maximized when the scaled window does not fit on the screen; then hides the splash screen.
function Initialize-WrtWindow($f, $scroll = @(), [int]$minW = 640, [int]$minH = 460) {
    $script:WrtForm = $f; $script:WrtMinWH = @($minW, $minH); $script:WrtExt = New-Object Collections.ArrayList
    foreach ($c in @($scroll)) {
        if (-not $c) { continue }
        $w = 0; $h = 0
        foreach ($k in $c.Controls) { if ($k.Dock -eq 'None') { $w = [Math]::Max($w, $k.Right); $h = [Math]::Max($h, $k.Bottom) } }
        [void]$script:WrtExt.Add(@($c, $w, $h))
    }
    $f.Add_Shown({ Complete-WrtWindow })
    $f.Add_FormClosed({
        try { if ($script:WrtWatch) { $script:WrtWatch.Stop(); $script:WrtWatch.Dispose(); $script:WrtWatch = $null } } catch {}
        try { if ($script:WrtSplash) { $script:WrtSplash.Close(); $script:WrtSplash.Dispose() } } catch {}; $script:WrtSplash = $null
    })
}
# Keeps the main window usable when the screen changes while the tool is open: a different resolution, a docked /
# undocked laptop, a monitor removed, or the window dragged to another monitor. The minimum size never exceeds the
# screen's work area. A normal (not maximized) window is only shrunk and moved when part of it is on NO screen: a
# window the user put across two monitors stays there. Checked once a second from a window timer.
function Update-WrtScreenFit([bool]$force = $false) {
    $f = $script:WrtForm; if (-not $f -or $f.IsDisposed -or -not $f.IsHandleCreated) { return }
    # never while a mouse button is down: the user may be dragging the window to another monitor (checked next time)
    if (-not $force -and [Windows.Forms.Control]::MouseButtons -ne [Windows.Forms.MouseButtons]::None) { return }
    $scr = [Windows.Forms.Screen]::FromControl($f); $wa = $scr.WorkingArea
    $key = '{0}|{1}' -f $scr.DeviceName, $wa
    if (-not $force -and $key -eq $script:WrtScreenKey) { return }
    $script:WrtScreenKey = $key
    $k = Get-WrtScale $f
    $needW = [int]($script:WrtMinWH[0] * $k); $needH = [int]($script:WrtMinWH[1] * $k)
    $f.MinimumSize = New-Object Drawing.Size([Math]::Min($needW, $wa.Width), [Math]::Min($needH, $wa.Height))
    # Only when the screen is too small for the minimum layout (e.g. 720p at 150 %) does the window itself scroll, so its
    # controls keep the minimum layout instead of being squeezed (anchored controls squeezed below zero room never
    # return to their places). Otherwise it must NOT scroll: a scrolling window counts its bottom-anchored controls
    # as content, and they would stop following the bottom edge when the window shrinks.
    if ($needW -gt $wa.Width -or $needH -gt $wa.Height) {
        $f.AutoScrollMinSize = New-Object Drawing.Size(($needW - ($f.Width - $f.ClientSize.Width)), ($needH - ($f.Height - $f.ClientSize.Height)))
        $f.AutoScroll = $true
    } elseif ($f.AutoScroll) {
        # (order matters: setting AutoScrollMinSize switches AutoScroll back ON, so clear it first)
        $f.AutoScrollPosition = New-Object Drawing.Point(0, 0); $f.AutoScrollMinSize = [Drawing.Size]::Empty; $f.AutoScroll = $false
    }
    if ($f.WindowState -eq 'Normal') {
        # how much of the window (without Windows' invisible 7-8 px resize border) some screen shows
        $in = New-Object Drawing.Rectangle(($f.Left + 8), $f.Top, [Math]::Max(1, $f.Width - 16), [Math]::Max(1, $f.Height - 8))
        $seen = 0.0; foreach ($s in [Windows.Forms.Screen]::AllScreens) { $r = [Drawing.Rectangle]::Intersect($s.WorkingArea, $in); if (-not $r.IsEmpty) { $seen += [double]$r.Width * $r.Height } }
        if ($seen -lt [double]$in.Width * $in.Height - 1) {
            if ($f.Width -gt $wa.Width) { $f.Width = $wa.Width }
            if ($f.Height -gt $wa.Height) { $f.Height = $wa.Height }
            $x = [Math]::Max($wa.Left, [Math]::Min($f.Left, $wa.Right - $f.Width)); $y = [Math]::Max($wa.Top, [Math]::Min($f.Top, $wa.Bottom - $f.Height))
            if ($x -ne $f.Left -or $y -ne $f.Top) { $f.Location = New-Object Drawing.Point($x, $y) }
        }
    }
}
function Complete-WrtWindow {
    $f = $script:WrtForm; $k = Get-WrtScale $f
    foreach ($e in $script:WrtExt) { try { if ($e[1] -gt 0) { $e[0].AutoScroll = $true; $e[0].AutoScrollMinSize = New-Object Drawing.Size([int](($e[1] + 8) * $k), [int](($e[2] + 8) * $k)) } } catch {} }
    try { Update-WrtScreenFit $true } catch {}      # minimum size within the screen (and scrolling only if the screen is too small)

    # Windows applies a minimized or hidden START style (a shortcut set to "Minimized", or a launcher that minimizes its
    # console) to the first window the tool shows - the main window, when the splash screen does not own it. Show it.
    try { $h = $f.Handle; if (-not [WrtUi.Win]::IsWindowVisible($h) -or [WrtUi.Win]::IsIconic($h)) { [void][WrtUi.Win]::ShowWindow($h, 9) } } catch {}
    try { $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea; if ($f.Width -gt $wa.Width -or $f.Height -gt $wa.Height) { $f.WindowState = 'Maximized' } } catch {}
    Close-WrtSplash
    try { $f.Activate() } catch {}
    try {
        $script:WrtWatch = New-Object Windows.Forms.Timer; $script:WrtWatch.Interval = 1000
        $script:WrtWatch.Add_Tick({ try { Update-WrtScreenFit } catch {} })
        $script:WrtWatch.Start()
    } catch {}
}
Show-WrtSplash $AppName
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
# the PowerShell for task / log windows: Windows PowerShell, or - where there is none, as in WinPE builds that only have
# PowerShell 7 (Hiren's PE 10) - the PowerShell this tool runs in (1.9; found by the Hiren's PE test)
$PsExePath = Join-Path $PSHOME 'powershell.exe'; if (-not [IO.File]::Exists($PsExePath)) { $PsExePath = (Get-Process -Id $PID).Path }
$script:Consoles = New-Object Collections.ArrayList     # repair console windows started from the Recovery tab
$script:Busy = $null                                    # set while a long job (log collection) runs

# minimize the console window behind the GUI (errors stay readable there)
try {
    Add-Type -Namespace WinSuperTool -Name Native -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    $hCon = [WinSuperTool.Native]::GetConsoleWindow()
    if ($hCon -ne [IntPtr]::Zero) { [void][WinSuperTool.Native]::ShowWindow($hCon, 6) }
} catch {}

# ---- data folder: next to the script if writable (USB stick in WinPE), else TEMP ----
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }
function Test-Writable([string]$dir) {
    try {
        [void][IO.Directory]::CreateDirectory($dir)
        $probe = Join-Path $dir ('.w' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, '')
        [IO.File]::Delete($probe)
        return $true
    } catch { return $false }
}
$DataDir = Join-Path $ScriptDir 'WinSuperTool-Data'
if (-not (Test-Writable $DataDir)) {
    $DataDir = Join-Path $env:TEMP 'WinSuperTool-Data'
    [void][IO.Directory]::CreateDirectory($DataDir)
}
$DataOnRam    = $IsWinPE -and $DataDir.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)
$StateFile    = Join-Path $DataDir 'mounts.json'
$ActivityLog  = Join-Path $DataDir 'activity.log'
$BcdBackupDir = Join-Path $DataDir 'BCD-Backups'
$CloneMarkers = @('Safe Mode (minimal) [WinSuperTool]', 'Safe Mode (minimal) [WinRepairTool]')   # [0] names new clones; [1] = clones made by the older WinRepairTool

# =====================================================================
#  SHARED HELPERS
# =====================================================================
function Msg($t, $c = $AppName, $i = 'Information') { [void][Windows.Forms.MessageBox]::Show([string]$t, [string]$c, 'OK', $i) }
function Ask($t, $c = 'Confirm', $i = 'Question', $def = 'Button1') { return ([Windows.Forms.MessageBox]::Show([string]$t, [string]$c, 'YesNo', $i, $def) -eq 'Yes') }
function Log([string]$m) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
    if ($script:txtLog) { $script:txtLog.AppendText($line + $NL) }
    try { [IO.File]::AppendAllText($ActivityLog, ('{0:yyyy-MM-dd} {1}{2}' -f (Get-Date), $line, $NL)) }
    catch {
        # say it once on screen instead of silently losing the audit trail
        if (-not $script:ActLogWarned -and $script:txtLog) {
            $script:ActLogWarned = $true
            $script:txtLog.AppendText(('[{0}] WARNING: cannot write the activity log file {1} ({2}). Actions are only shown here from now on.{3}' -f (Get-Date -Format 'HH:mm:ss'), $ActivityLog, $_.Exception.Message, $NL))
        }
    }
}
function Safe([scriptblock]$Do) {
    try { & $Do } catch { Log "ERROR: $($_.Exception.Message)"; Msg $_.Exception.Message 'Error' 'Error' }
}
function Test-LetterUsed([string]$L) { return ([IO.DriveInfo]::GetDrives().Name -contains ('{0}:\' -f $L.ToUpper())) }
function Fmt-Size($b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
# Firmware of the PC this runs on: 'UEFI', 'BIOS' or '' (unknown). WinPE: PEFirmwareType (1/2); Windows: %firmware_type%.
function Get-FirmwareType {
    $v = 0; try { $v = [int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop).PEFirmwareType } catch {}
    if ($v -eq 2) { return 'UEFI' }; if ($v -eq 1) { return 'BIOS' }
    switch ($env:firmware_type) { 'UEFI' { 'UEFI' } 'Legacy' { 'BIOS' } default { '' } }
}
# BitLocker state of a volume via WMI (language-independent). Returns 'On', 'Off' or the reason it could not be read.
function Get-BitLockerState([string]$Drive) {
    try {
        $ev = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$Drive'" -ErrorAction Stop
        if (-not $ev) { return 'unknown (volume not found in BitLocker WMI)' }
        $conv = (Invoke-CimMethod -InputObject $ev -MethodName GetConversionStatus -ErrorAction Stop).ConversionStatus
        if ($ev.ProtectionStatus -eq 1 -or ($null -ne $conv -and $conv -ne 0)) { return 'On' }
        return 'Off'
    } catch { return "unknown ($($_.Exception.Message))" }
}
function Open-Folder([string]$p) { try { Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $p) } catch { Msg "Could not open $p" } }

$tip = New-Object Windows.Forms.ToolTip
$tip.AutoPopDelay = 30000; $tip.InitialDelay = 200; $tip.ReshowDelay = 100

function New-Ctl($type, $parent, $x, $y, $w, $h, $text = '') {
    $c = New-Object "Windows.Forms.$type"
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size     = New-Object Drawing.Size($w, $h)
    if ($text) { $c.Text = $text }
    if ($type -in 'Label', 'CheckBox', 'RadioButton') { $c.AutoSize = $false }
    if ($type -eq 'ComboBox') { $c.DropDownStyle = 'DropDownList' }
    $parent.Controls.Add($c)
    return $c
}
# "?" button: tooltip on hover, full text in a popup on click
function Add-Help($parent, $x, $y, $title, $text) {
    $b = New-Ctl 'Button' $parent $x $y 24 24 '?'
    $b.Tag = @($title, $text)
    $tip.SetToolTip($b, $text)
    $b.Add_Click({ [void][Windows.Forms.MessageBox]::Show([string]$this.Tag[1], [string]$this.Tag[0], 'OK', 'Information') })
}
function Read-Text($prompt, $title = 'Input') {
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = $title; $f.ClientSize = New-Object Drawing.Size(390, 110); $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.Font = $form.Font
    [void](New-Ctl 'Label' $f 10 10 370 20 $prompt)
    $t  = New-Ctl 'TextBox' $f 10 35 370 24
    $ok = New-Ctl 'Button' $f 210 70 80 28 'OK'
    $ca = New-Ctl 'Button' $f 300 70 80 28 'Cancel'
    $ok.DialogResult = 'OK'; $ca.DialogResult = 'Cancel'; $f.AcceptButton = $ok; $f.CancelButton = $ca
    $r = $null
    if ($f.ShowDialog($form) -eq 'OK') { $r = $t.Text.Trim() }
    $f.Dispose()
    return $r
}
function Show-Report($title, $text, [bool]$AskContinue = $false) {
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = $title; $f.Size = New-Object Drawing.Size(700, 520); $f.StartPosition = 'CenterParent'; $f.Font = $form.Font; $f.MinimumSize = New-Object Drawing.Size(420, 300)
    $t = New-Ctl 'TextBox' $f 10 10 665 420
    $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Both'; $t.WordWrap = $false
    $t.Font = New-Object Drawing.Font('Consolas', 9); $t.Text = $text; $t.Anchor = 'Top,Bottom,Left,Right'
    if ($AskContinue) {
        $ok = New-Ctl 'Button' $f 440 440 125 30 'Continue anyway'
        $ca = New-Ctl 'Button' $f 575 440 100 30 'Cancel'
        $ok.DialogResult = 'Yes'; $ca.DialogResult = 'Cancel'; $f.CancelButton = $ca
        $ok.Anchor = 'Bottom,Right'; $ca.Anchor = 'Bottom,Right'
    } else {
        $cl = New-Ctl 'Button' $f 575 440 100 30 'Close'
        $cl.DialogResult = 'OK'; $f.CancelButton = $cl; $cl.Anchor = 'Bottom,Right'
    }
    $t.Select(0, 0)
    $res = ($f.ShowDialog($form) -eq 'Yes')
    $f.Dispose()
    return $res
}

# =====================================================================
#  SHARED: Windows installations (Target Windows bar)
# =====================================================================
function Get-WinInstalls {
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        $t = $d.DriveType.ToString()
        if ($t -ne 'Fixed' -and $t -ne 'Removable') { continue }
        if (-not $d.IsReady) { continue }
        $l = $d.Name.Substring(0, 2).ToUpper()
        if ($IsWinPE -and $l -eq $env:SystemDrive.ToUpper()) { continue }
        if (-not ([IO.File]::Exists("$l\Windows\System32\config\SYSTEM") -and [IO.File]::Exists("$l\Windows\System32\ntoskrnl.exe"))) { continue }
        $ver = ''; try { $ver = (Get-Item -LiteralPath "$l\Windows\System32\ntoskrnl.exe").VersionInfo.ProductVersion } catch {}
        $build = 0; if ($ver -match '^\d+\.\d+\.(\d+)') { $build = [int]$Matches[1] }
        $name = if ($build -ge 22000) { 'Windows 11' } elseif ($build -ge 10240) { 'Windows 10/Server' } else { 'Windows' }
        $running = (-not $IsWinPE) -and ($l -eq $env:SystemDrive.ToUpper())
        $tag = if ($running) { '  [RUNNING - this PC]' } else { '  [offline]' }
        [pscustomobject]@{ Drive = $l; Running = $running; Text = ('{0}\Windows  -  {1} {2}  [{3}]{4}' -f $l, $name, $ver, $d.VolumeLabel, $tag) }
    }
}
function Get-TargetWin { return $cmbWin.SelectedItem }
function Update-Windows([bool]$Popup = $false) {
    $prev = ''
    if ($cmbWin.SelectedItem) { $prev = $cmbWin.SelectedItem.Drive }
    $cmbWin.Items.Clear()
    $found = @(Get-WinInstalls)
    foreach ($w in $found) { [void]$cmbWin.Items.Add($w) }
    if ($found.Count -eq 0) {
        $lblWarn.ForeColor = 'DarkOrange'
        $lblWarn.Text = 'No Windows installation found. Mount its partition on the Mount tab, then press Rescan.'
    } elseif ($found.Count -gt 1) {
        $lblWarn.ForeColor = 'Red'
        $lblWarn.Text = "WARNING: $($found.Count) Windows installations found. Select the one to work on - nothing is pre-selected."
        for ($i = 0; $i -lt $found.Count; $i++) { if ($prev -and $found[$i].Drive -eq $prev) { $cmbWin.SelectedIndex = $i } }
        if ($Popup) { Msg "$($found.Count) Windows installations were detected.${NL}${NL}Choose the one you want to work on in 'Target Windows' at the top before changing anything." 'Multiple Windows installations' 'Warning' }
    } else {
        $lblWarn.ForeColor = 'DarkGreen'
        $lblWarn.Text = 'One Windows installation found (selected).'
        $cmbWin.SelectedIndex = 0
    }
    Update-SafeStatus
}

# =====================================================================
#  1. COLLECT LOGS
# =====================================================================
function Get-InteractiveUser {
    $profilePath = $env:USERPROFILE
    $desktop     = [Environment]::GetFolderPath('Desktop')
    if (-not $IsWinPE) {
        try {
            $u = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
            if ($u) {
                $sid  = (New-Object Security.Principal.NTAccount($u)).Translate([Security.Principal.SecurityIdentifier]).Value
                $prof = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath
                if ($prof) { $profilePath = $prof }
                # read the raw value: Get-ItemProperty would expand %USERPROFILE% to the ADMIN's profile
                $key = Get-Item -LiteralPath "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop
                $raw = $key.GetValue('Desktop', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($raw) {
                    $d = [regex]::Replace([string]$raw, '%USERPROFILE%', $profilePath.Replace('$', '$$'), 'IgnoreCase')
                    $desktop = [Environment]::ExpandEnvironmentVariables($d)
                }
            }
        } catch {}
    }
    [pscustomobject]@{ Profile = $profilePath; Desktop = $desktop }
}
$ColUser = Get-InteractiveUser
function Get-DefaultLogRoot {
    if ($IsWinPE) { return (Join-Path $DataDir 'logs') }
    return (Join-Path $ColUser.Desktop 'logs')
}

$script:ColCount = 0; $script:ColFail = 0; $script:LastCollect = $null

function Say([string]$m) {
    $txtCol.AppendText($m + $NL)
    [Windows.Forms.Application]::DoEvents()
}
function Copy-One([string]$s, [string]$d) {
    try { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($d)) } catch {}
    try {
        [IO.File]::Copy($s, $d, $true)          # much faster than Copy-Item for thousands of small files
        $script:ColCount++
    } catch {
        # fallback for files Windows holds open (shared read)
        $in = $null; $out = $null; $ok = $false
        try {
            $in  = [IO.File]::Open($s, 'Open', 'Read', 'ReadWrite,Delete')
            $out = [IO.File]::Create($d)
            $in.CopyTo($out)
            $script:ColCount++; $ok = $true
        } catch {
            $script:ColFail++
            Say "   FAILED: $s"
        } finally {
            if ($out) { $out.Dispose() }
            if ($in)  { $in.Dispose() }
            if (-not $ok -and $out) { try { [IO.File]::Delete($d) } catch {} }   # no half-written file in the output
        }
    }
}
# copies a file, a wildcard, or a whole folder (recursively) into $dest
function Copy-Safe([string]$src, [string]$dest) {
    if (Test-Path -LiteralPath $src -PathType Container) {
        $root  = (Get-Item -LiteralPath $src -Force).FullName.TrimEnd('\')
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        if (-not $files.Count) { Say "   (empty) $src"; return }
        $leaf = Split-Path $root -Leaf
        $i = 0
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($root.Length).TrimStart('\')
            Copy-One $f.FullName (Join-Path (Join-Path $dest $leaf) $rel)
            if ((++$i % 25) -eq 0) { Say "   ... $i / $($files.Count) files from $leaf" }   # progress (Say also keeps the window responsive)
        }
    } else {
        $files = @(Get-ChildItem -Path $src -File -Force -ErrorAction SilentlyContinue)
        if (-not $files.Count) { Say "   (not found) $src"; return }
        foreach ($f in $files) { Copy-One $f.FullName (Join-Path $dest $f.Name) }
    }
}
$EvtChannels = @(
    'System', 'Application', 'Setup',
    'Microsoft-Windows-WindowsUpdateClient/Operational',
    'Microsoft-Windows-Bits-Client/Operational',
    'Microsoft-Windows-DeliveryOptimization/Operational',
    'Microsoft-Windows-Kernel-PnP/Configuration',
    'Microsoft-Windows-Kernel-Boot/Operational',
    'Microsoft-Windows-Diagnostics-Performance/Operational',
    'Microsoft-Windows-AppXDeploymentServer/Operational',
    'Microsoft-Windows-WER-Diag/Operational',
    'Microsoft-Windows-CodeIntegrity/Operational',
    'Microsoft-Windows-TaskScheduler/Operational'
)
# live: export the channel with wevtutil.  offline: copy the channel's .evtx file from the install
function Export-Evt([string]$name, [string]$dest, [string]$W, [bool]$Live) {
    [void][IO.Directory]::CreateDirectory($dest)
    $fileName = ($name -replace '[\\/]', '%4') + '.evtx'
    if ($Live) {
        $o = (& wevtutil.exe epl $name (Join-Path $dest $fileName) /ow:true 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ } }) -join ' '
        # 15007 = ERROR_EVT_CHANNEL_NOT_FOUND (language-independent). Anything else is a real failure (path, access, disk full),
        # not "channel missing" - it used to be reported as skipped and never counted.
        if ($LASTEXITCODE -eq 0) { $script:ColCount++ }
        elseif ($LASTEXITCODE -eq 15007) { Say "   skipped (channel does not exist on this Windows): $name" }
        else { $script:ColFail++; Say "   FAILED (wevtutil exit code $LASTEXITCODE): $name - $($o.Trim())" }
    } else {
        $src = Join-Path $W ('Windows\System32\winevt\Logs\' + $fileName)
        if ([IO.File]::Exists($src)) { Copy-One $src (Join-Path $dest $fileName) } else { Say "   (not found) $src" }
    }
}

# every collector gets: $W = Windows drive (C:), $Live = running Windows?, $Root = output folder, $Prof = user profile
$Collectors = [ordered]@{
    'WU' = @{ Default = $true; Label = 'Windows Update (ETL traces, ReportingEvents, USO, WaaSMedic, merged WindowsUpdate.log)'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '1_WindowsUpdate'
        Copy-Safe "$W\Windows\Logs\WindowsUpdate"                       $d
        Copy-Safe "$W\Windows\SoftwareDistribution\ReportingEvents.log" $d
        Copy-Safe "$W\Windows\WindowsUpdate.log"                        $d
        Copy-Safe "$W\Windows\Logs\waasmedic"                           $d
        Copy-Safe "$W\Windows\Logs\SIH"                                 $d
        Copy-Safe "$W\ProgramData\USOShared\Logs"                       $d
        if (Get-Command Get-WindowsUpdateLog -ErrorAction SilentlyContinue) {
            Say '   Building merged WindowsUpdate.log (can take a minute)...'
            try {
                $p = @{ LogPath = (Join-Path $d 'WindowsUpdate_merged.log'); ErrorAction = 'Stop' }
                if (-not $Live) { $p.ETLPath = "$W\Windows\Logs\WindowsUpdate" }
                Get-WindowsUpdateLog @p | Out-Null
                $script:ColCount++
            } catch { Say "   Get-WindowsUpdateLog failed: $($_.Exception.Message)" }
        } else { Say '   Get-WindowsUpdateLog is not available here (normal in WinPE); the raw .etl traces were copied.' }
    } }

    'DISM' = @{ Default = $true; Label = 'DISM / CBS / servicing (dism.log, CBS.log, pending.xml, setupapi)'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '2_DISM_CBS'
        Copy-Safe "$W\Windows\Logs\DISM"                       $d
        Copy-Safe "$W\Windows\Logs\CBS"                        $d
        Copy-Safe "$W\Windows\Logs\DPX"                        $d
        Copy-Safe "$W\Windows\servicing\Sessions\Sessions.xml" $d
        Copy-Safe "$W\Windows\WinSxS\pending.xml"              $d
        Copy-Safe "$W\Windows\WinSxS\poqexec.log"              $d
        Copy-Safe "$W\Windows\inf\setupapi*.log"               $d
    } }

    'EVT' = @{ Default = $true; Label = 'Event Viewer - key logs (System, Application, Setup, WU client, BITS, Kernel-Boot, WER ...)'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '3_EventViewer'
        foreach ($c in $EvtChannels) { Export-Evt $c $d $W $Live }
    } }

    'SEC' = @{ Default = $false; Label = 'Event Viewer - Security log (large, sensitive)'; Run = {
        param($W, $Live, $Root, $Prof)
        Export-Evt 'Security' (Join-Path $Root '3_EventViewer') $W $Live
    } }

    'EVTALL' = @{ Default = $false; Label = 'Event Viewer - ALL raw .evtx files (can be hundreds of MB)'; Run = {
        param($W, $Live, $Root, $Prof)
        Copy-Safe "$W\Windows\System32\winevt\Logs" (Join-Path $Root '3b_EventViewer_AllRaw')
    } }

    'CRASH' = @{ Default = $true; Label = 'Crashes (Minidumps, WER reports, user CrashDumps, reliability history, crash/shutdown events)'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '4_Crashes'
        Copy-Safe "$W\Windows\Minidump"                                $d
        Copy-Safe "$W\ProgramData\Microsoft\Windows\WER\ReportArchive" $d
        Copy-Safe "$W\ProgramData\Microsoft\Windows\WER\ReportQueue"   $d
        if ($Live) {
            Copy-Safe (Join-Path $Prof 'AppData\Local\CrashDumps')            $d
            Copy-Safe (Join-Path $Prof 'AppData\Local\Microsoft\Windows\WER') (Join-Path $d 'UserWER')
        } else {
            foreach ($u in @(Get-ChildItem -LiteralPath "$W\Users" -Directory -Force -ErrorAction SilentlyContinue)) {
                $cd = Join-Path $u.FullName 'AppData\Local\CrashDumps'
                if (Test-Path -LiteralPath $cd) { Copy-Safe $cd (Join-Path $d ('Users\' + $u.Name)) }
            }
        }
        [void][IO.Directory]::CreateDirectory($d)
        $ids = 41, 1001, 1074, 1076, 6005, 6006, 6008
        if ($Live) {
            try {
                Get-CimInstance Win32_ReliabilityRecords -ErrorAction Stop |
                    Select-Object TimeGenerated, SourceName, EventIdentifier, ProductName, Message |
                    Export-Csv (Join-Path $d 'ReliabilityHistory.csv') -NoTypeInformation
                $script:ColCount++
            } catch { Say '   Reliability history unavailable' }
            $filter = @{ LogName = 'System'; Id = $ids }
        } else {
            Say '   Offline target: reliability history needs the running Windows (skipped).'
            $filter = @{ Path = "$W\Windows\System32\winevt\Logs\System.evtx"; Id = $ids }
        }
        try {
            Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
                Format-List TimeCreated, Id, ProviderName, Message |
                Out-File (Join-Path $d 'Crash_Shutdown_Events.txt') -Width 250
            $script:ColCount++
        } catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { Say '   No crash/shutdown events found' }
            else { $script:ColFail++; Say "   Crash/shutdown events FAILED: $($_.Exception.Message)" }
        }
    } }

    'BIG' = @{ Default = $false; Label = 'LARGE dumps (MEMORY.DMP + LiveKernelReports) - can be several GB'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '4b_LargeDumps'
        # only existing paths, -LiteralPath: "Get-ChildItem <missing file> -Recurse" would search ALL of C:\Windows for that name
        $need = 0
        foreach ($bp in "$W\Windows\MEMORY.DMP", "$W\Windows\LiveKernelReports") {
            if (Test-Path -LiteralPath $bp) { $need += [long](Get-ChildItem -LiteralPath $bp -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        }
        $free = try { (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Root))).AvailableFreeSpace } catch { [long]::MaxValue }
        if ($need -and $need -gt ($free - 512MB)) { $script:ColFail++; Say ('   SKIPPED: the dumps need {0}, only {1} free on the output drive.' -f (Fmt-Size $need), (Fmt-Size $free)); return }
        Copy-Safe "$W\Windows\MEMORY.DMP"        $d
        Copy-Safe "$W\Windows\LiveKernelReports" $d
    } }

    'SETUP' = @{ Default = $false; Label = 'Setup / feature-upgrade logs (Panther, $WINDOWS.~BT, Rollback, MoSetup, Sysprep)'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '5_SetupUpgrade'
        Copy-Safe "$W\Windows\Panther"                            (Join-Path $d 'Windows_Panther')
        Copy-Safe (Join-Path $W '$WINDOWS.~BT\Sources\Panther')  (Join-Path $d 'BT_Panther')
        Copy-Safe (Join-Path $W '$WINDOWS.~BT\Sources\Rollback') (Join-Path $d 'BT_Rollback')
        Copy-Safe (Join-Path $W '$Windows.~WS\Sources\Panther')  (Join-Path $d 'WS_Panther')
        Copy-Safe "$W\Windows\Logs\MoSetup"                       $d
        Copy-Safe "$W\Windows\System32\Sysprep\Panther"           (Join-Path $d 'Sysprep_Panther')
        Copy-Safe "$W\Windows\setupact.log"                       $d
        Copy-Safe "$W\Windows\setuperr.log"                       $d
    } }

    'INFO' = @{ Default = $false; Label = 'System info (systeminfo, hotfixes, DISM package list; offline: DISM packages + drivers)'; Run = {
        param($W, $Live, $Root, $Prof)
        $d = Join-Path $Root '6_SystemInfo'
        [void][IO.Directory]::CreateDirectory($d)
        if ($Live) {
            # count only what really worked
            & systeminfo.exe 2>&1 | Out-File (Join-Path $d 'systeminfo.txt')
            if ($LASTEXITCODE -eq 0) { $script:ColCount++ } else { $script:ColFail++; Say "   systeminfo failed (exit code $LASTEXITCODE)" }
            try { Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Format-Table -AutoSize | Out-File (Join-Path $d 'hotfixes.txt') -Width 250; $script:ColCount++ } catch { $script:ColFail++; Say "   hotfix list failed: $($_.Exception.Message)" }
            try {
                Get-WindowsPackage -Online -ErrorAction Stop | Format-Table PackageName, PackageState, InstallTime -AutoSize |
                    Out-File (Join-Path $d 'dism_packages.txt') -Width 300
                $script:ColCount++
            } catch { $script:ColFail++; Say "   package list failed: $($_.Exception.Message)" }
        } else {
            Say '   Offline target: using DISM /image (systeminfo and the hotfix list need the running Windows).'
            foreach ($q in @(@('/get-packages', 'dism_packages.txt'), @('/get-drivers', 'dism_drivers.txt'))) {
                & dism.exe "/image:$W\" $q[0] /format:table 2>&1 | Out-File (Join-Path $d $q[1]) -Width 300
                if ($LASTEXITCODE -eq 0) { $script:ColCount++ } else { $script:ColFail++; Say "   dism $($q[0]) failed (exit code $LASTEXITCODE) - see $($q[1])" }
            }
        }
        $v = ''
        try { $v = (Get-Item -LiteralPath "$W\Windows\System32\ntoskrnl.exe").VersionInfo.ProductVersion } catch {}
        ("Target: $W\Windows", "Kernel version: $v", "Running Windows: $Live", "Collected: $(Get-Date)") | Out-File (Join-Path $d 'target.txt')
    } }
}

# =====================================================================
#  2. LIVE MONITOR  (each log in its own PowerShell window)
# =====================================================================
# Type: File = Get-Content -Wait | Filter = same, only lines matching Extra (regex)
#       Evt  = live Event Viewer channel (Extra = optional event IDs) | Dir = watch a folder for new files
function New-MonItem($section, $name, $type, $target, $extra = $null) {
    [pscustomobject]@{ Section = $section; Name = $name; Type = $type; Target = $target; Extra = $extra }
}
$WinDir = $env:windir
$MonItems = @(
    New-MonItem 'Windows Update' 'ReportingEvents.log'                        'File' "$WinDir\SoftwareDistribution\ReportingEvents.log"
    New-MonItem 'Windows Update' 'Event: WindowsUpdateClient/Operational'     'Evt'  'Microsoft-Windows-WindowsUpdateClient/Operational'
    New-MonItem 'Windows Update' 'Event: Delivery Optimization/Operational'   'Evt'  'Microsoft-Windows-DeliveryOptimization/Operational'
    New-MonItem 'Windows Update' 'Event: BITS-Client/Operational'             'Evt'  'Microsoft-Windows-Bits-Client/Operational'

    New-MonItem 'SFC / DISM / CBS' 'dism.log'                                 'File'   "$WinDir\Logs\DISM\dism.log"
    New-MonItem 'SFC / DISM / CBS' 'CBS.log (full)'                           'File'   "$WinDir\Logs\CBS\CBS.log"
    New-MonItem 'SFC / DISM / CBS' 'CBS.log - SFC lines only ([SR])'          'Filter' "$WinDir\Logs\CBS\CBS.log" '\[SR\]'
    New-MonItem 'SFC / DISM / CBS' 'DPX setupact.log'                         'File'   "$WinDir\Logs\DPX\setupact.log"
    New-MonItem 'SFC / DISM / CBS' 'poqexec.log (pending operations)'         'File'   "$WinDir\WinSxS\poqexec.log"
    New-MonItem 'SFC / DISM / CBS' 'setupapi.dev.log (drivers/devices)'       'File'   "$WinDir\inf\setupapi.dev.log"

    New-MonItem 'Setup / Upgrade' 'Windows\Panther\setupact.log'              'File' "$WinDir\Panther\setupact.log"
    New-MonItem 'Setup / Upgrade' 'Windows\Panther\setuperr.log'              'File' "$WinDir\Panther\setuperr.log"
    New-MonItem 'Setup / Upgrade' '$WINDOWS.~BT Panther\setupact.log'         'File' (Join-Path $env:SystemDrive '$WINDOWS.~BT\Sources\Panther\setupact.log')
    New-MonItem 'Setup / Upgrade' '$WINDOWS.~BT Panther\setuperr.log'         'File' (Join-Path $env:SystemDrive '$WINDOWS.~BT\Sources\Panther\setuperr.log')
    New-MonItem 'Setup / Upgrade' 'MoSetup BlueBox.log'                       'File' "$WinDir\Logs\MoSetup\BlueBox.log"
    New-MonItem 'Setup / Upgrade' 'Sysprep setupact.log'                      'File' "$WinDir\System32\Sysprep\Panther\setupact.log"

    New-MonItem 'Event Viewer (live)' 'System'                                'Evt'  'System'
    New-MonItem 'Event Viewer (live)' 'Application'                           'Evt'  'Application'
    New-MonItem 'Event Viewer (live)' 'Setup'                                 'Evt'  'Setup'
    New-MonItem 'Event Viewer (live)' 'Security'                              'Evt'  'Security'
    New-MonItem 'Event Viewer (live)' 'CodeIntegrity/Operational'             'Evt'  'Microsoft-Windows-CodeIntegrity/Operational'
    New-MonItem 'Event Viewer (live)' 'Windows Defender/Operational'          'Evt'  'Microsoft-Windows-Windows Defender/Operational'

    New-MonItem 'Crashes' 'System: crash/shutdown events (41,1001,1074,1076,6008)' 'Evt' 'System'      '41,1001,1074,1076,6008'
    New-MonItem 'Crashes' 'Application: crashes/hangs (1000,1001,1002)'            'Evt' 'Application' '1000,1001,1002'
    New-MonItem 'Crashes' 'Watch folder: Windows\Minidump'                         'Dir' "$WinDir\Minidump"
    New-MonItem 'Crashes' 'Watch folder: WER ReportQueue'                          'Dir' "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
    New-MonItem 'Crashes' 'Watch folder: LiveKernelReports'                        'Dir' "$WinDir\LiveKernelReports"
)

# event logs that exist on this Windows (some channels differ between versions, e.g. Delivery Optimization)
$EvtLogNames = @(); try { $EvtLogNames = @([System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetLogNames()) } catch {}

# ---- child-window script templates ----
$tplFile = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$p = '__TARGET__'
Write-Host "Monitoring: $p   (Ctrl+C to stop)" -ForegroundColor Cyan
while (-not (Test-Path -LiteralPath $p)) { Write-Host "Waiting for file to exist..." -ForegroundColor Yellow; Start-Sleep 3 }
Get-Content -LiteralPath $p -Tail __TAIL__ -Wait
'@

$tplFilter = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$p = '__TARGET__'
Write-Host "Monitoring: $p  filter: __PATTERN__   (Ctrl+C to stop)" -ForegroundColor Cyan
while (-not (Test-Path -LiteralPath $p)) { Write-Host "Waiting for file to exist..." -ForegroundColor Yellow; Start-Sleep 3 }
Get-Content -LiteralPath $p -Tail __FILTERTAIL__ -Wait | Select-String -Pattern '__PATTERN__'
'@

$tplEvt = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$log = '__TARGET__'; $ids = @(__IDS__); $tail = __TAIL__
try { Get-WinEvent -ListLog $log -ErrorAction Stop | Out-Null }
catch {
    # a log that is simply not on this Windows (they differ between versions) gets a plain message, not an error
    $names = @(); try { $names = @([System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetLogNames()) } catch {}
    if ($names.Count -and $names -notcontains $log) { Write-Host "The event log '$log' does not exist on this PC. Event logs differ between Windows versions and editions, so there is nothing to monitor here." -ForegroundColor Yellow }
    else { Write-Host "Cannot open event log '$log': $($_.Exception.Message)" -ForegroundColor Red }
    return
}
function Show($e) {
    $msg = ($e.Message -split "`r?`n")[0]
    $col = switch ($e.Level) { 1 {'Red'} 2 {'Red'} 3 {'Yellow'} default {'Gray'} }
    Write-Host ('{0:yyyy-MM-dd HH:mm:ss} [{1}] ID {2} {3}: {4}' -f $e.TimeCreated, $e.LevelDisplayName, $e.Id, $e.ProviderName, $msg) -ForegroundColor $col
}
$idq = if ($ids.Count) { ' and (' + (($ids | ForEach-Object { "EventID=$_" }) -join ' or ') + ')' } else { '' }
function Get-Ev($max) {
    $f = @{ LogName = $log }
    if ($ids.Count) { $f.Id = $ids }
    Get-WinEvent -FilterHashtable $f -MaxEvents $max -ErrorAction SilentlyContinue
}
function Get-Top { try { (Get-WinEvent -LogName $log -MaxEvents 1 -ErrorAction Stop).RecordId } catch { 0 } }
Write-Host "Live event monitor: $log   (Ctrl+C to stop)" -ForegroundColor Cyan
$last = [long](Get-Top)
Get-Ev $tail | Sort-Object RecordId | ForEach-Object { Show $_ }
while ($true) {
    Start-Sleep 2
    # one cheap read of the newest record; only when something new arrived, ask Windows for exactly the new records
    # (it used to read and render the newest 100 events every 2 seconds, in every monitor window)
    $top = [long](Get-Top)
    if ($top -lt $last) { Write-Host '--- the log was cleared ---' -ForegroundColor Yellow; $last = 0 }
    if ($top -gt $last) {
        Get-WinEvent -LogName $log -FilterXPath "*[System[EventRecordID>$last$idq]]" -ErrorAction SilentlyContinue |
            Sort-Object RecordId | ForEach-Object { Show $_ }
        $last = $top
    }
}
'@

$tplDir = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$d = '__TARGET__'
Write-Host "Watching folder: $d   (Ctrl+C to stop)" -ForegroundColor Cyan
while (-not (Test-Path -LiteralPath $d)) { Write-Host "Waiting for folder to exist..." -ForegroundColor Yellow; Start-Sleep 3 }
$seen = @{}
Write-Host "Existing files:" -ForegroundColor Gray
Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
    $seen[$_.FullName] = $_.Length
    Write-Host ('{0:yyyy-MM-dd HH:mm:ss}  {1,12:N0} bytes  {2}' -f $_.LastWriteTime, $_.Length, $_.FullName) -ForegroundColor Gray
}
Write-Host "--- waiting for new files ---" -ForegroundColor Cyan
while ($true) {
    Start-Sleep 3
    Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $seen.ContainsKey($_.FullName)) {
            $seen[$_.FullName] = $_.Length
            Write-Host ('{0:yyyy-MM-dd HH:mm:ss}  NEW  {1:N0} bytes  {2}' -f (Get-Date), $_.Length, $_.FullName) -ForegroundColor Green
        }
    }
}
'@

$script:MonProcs = New-Object Collections.ArrayList
# PowerShell also treats the typographic quotes U+2018-U+201B as single quotes (e.g. O<U+2019>Brien), so double those too
function Esc-Sq([string]$s) { return ($s -replace "(['$([char]0x2018)-$([char]0x201B)])", '$1$1') }
function Start-Monitor($item, [int]$tail) {
    $tpl = switch ($item.Type) {
        'File'   { $tplFile }
        'Filter' { $tplFilter }
        'Evt'    { $tplEvt }
        'Dir'    { $tplDir }
    }
    $ids = ''
    if ($item.Type -eq 'Evt' -and $item.Extra) { $ids = (@("$($item.Extra)" -split ',' | ForEach-Object { [int]$_.Trim() }) -join ',') }
    $code = $tpl.Replace('__TITLE__', (Esc-Sq ('MONITOR: ' + $item.Name)))
    $code = $code.Replace('__TARGET__', (Esc-Sq $item.Target))
    $code = $code.Replace('__FILTERTAIL__', [string][Math]::Max($tail, 300))
    $code = $code.Replace('__TAIL__', [string]$tail)
    $code = $code.Replace('__PATTERN__', (Esc-Sq ([string]$item.Extra)))
    $code = $code.Replace('__IDS__', $ids)
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $p = Start-Process -FilePath $PsExePath -PassThru -ArgumentList '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc
    [void]$script:MonProcs.Add($p)
}
function Update-MonStatus([string]$msg) {
    $open = @($script:MonProcs | Where-Object { -not $_.HasExited }).Count
    $lblMonStatus.Text = "$msg   Open monitor windows: $open"
}


# =====================================================================
#  4. MOUNT  (diskpart OR Storage cmdlets - whitelisted, non-destructive)
# =====================================================================
function Test-StorageAvail { return ([bool](Get-Command Get-Disk -ErrorAction SilentlyContinue) -and [bool](Get-Command Add-PartitionAccessPath -ErrorAction SilentlyContinue)) }

# ONLY these diskpart commands can ever be sent
$DpAllow = '^(list (disk|partition|volume)|select (disk|partition) \d+|select volume [D-Z]|detail partition|assign letter=[D-Z]|remove letter=[D-Z])$'
function Invoke-Diskpart([string[]]$Cmds) {
    foreach ($c in $Cmds) { if ($c -notmatch $DpAllow) { throw "Blocked diskpart command: $c" } }
    $tmp = Join-Path $env:TEMP ('dp_{0}.txt' -f [guid]::NewGuid().ToString('N'))
    Set-Content -Path $tmp -Value $Cmds -Encoding ASCII
    try { $out = & diskpart.exe /s $tmp 2>&1 | Out-String } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Log ('diskpart: ' + ($Cmds -join ' > '))
    return $out
}
# Data rows of a diskpart table = the lines between the "---  ---" underline and the next blank line.
# Works in any display language ("Disk 0", "Datentraeger 0", "Disque 0" ...), because it never looks for the English word.
function Get-DiskpartRows([string]$Text) {
    $in = $false
    foreach ($ln in ($Text -split "`r?`n")) {
        if ($ln -match '^\s*-{2,}(\s+-{2,})+\s*$') { $in = $true; continue }
        if ($in -and -not $ln.Trim()) { $in = $false; continue }
        if ($in) { $ln }
    }
}
function Get-DiskList {
    if ($rbStor.Checked) {
        foreach ($d in (Get-Disk | Sort-Object Number)) {
            [pscustomobject]@{ Num = [int]$d.Number; Text = ('Disk {0}  -  {1}  -  {2}  -  {3}' -f $d.Number, $d.FriendlyName, (Fmt-Size $d.Size), $d.PartitionStyle) }
        }
    } else {
        foreach ($ln in (Get-DiskpartRows (Invoke-Diskpart 'list disk'))) {
            if ($ln -match '^\s*\*?\s*\S+\s+(\d+)\s+(.*\S)\s*$') {
                [pscustomobject]@{ Num = [int]$Matches[1]; Text = ('Disk {0}  -  {1}' -f $Matches[1], ($Matches[2] -replace '\s{2,}', '  ')) }
            }
        }
    }
}
function Get-PartList($disk) {
    if ($rbStor.Checked) {
        foreach ($p in (Get-Partition -DiskNumber $disk | Sort-Object PartitionNumber)) {
            $l = ''; if ([int][char]$p.DriveLetter -gt 0) { $l = "  [$($p.DriveLetter):]" }
            [pscustomobject]@{ Num = [int]$p.PartitionNumber; Text = ('Partition {0}  -  {1}  -  {2}{3}' -f $p.PartitionNumber, $p.Type, (Fmt-Size $p.Size), $l) }
        }
    } else {
        foreach ($ln in (Get-DiskpartRows (Invoke-Diskpart @("select disk $disk", 'list partition')))) {
            if ($ln -match '^\s*\*?\s*\S+\s+(\d+)\s+(.*\S)\s*$') {
                [pscustomobject]@{ Num = [int]$Matches[1]; Text = ('Partition {0}  -  {1}' -f $Matches[1], ($Matches[2] -replace '\s{2,}', '  ')) }
            }
        }
    }
}
# returns a letter, '' (no letter) or 'NOVOLUME'
function Get-PartLetter($disk, $part) {
    if ($rbStor.Checked) {
        $p = Get-Partition -DiskNumber $disk -PartitionNumber $part
        if ([int][char]$p.DriveLetter -gt 0) { return [string]$p.DriveLetter } else { return '' }
    }
    return (Get-DpPartLetter $disk $part)
}
# diskpart "detail partition": letter of the partition's volume, read by COLUMN POSITION under the "---- ---" underline
# (the words "Volume" / "no volume" are translated). Returns 'X', '' (volume without letter) or 'NOVOLUME'.
function Get-DpPartLetter($disk, $part, [string]$Detail = '') {
    if (-not $Detail) { $Detail = Invoke-Diskpart @("select disk $disk", "select partition $part", 'detail partition') }
    $lines = @($Detail -split "`r?`n")
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -match '^\s*-{2,}(\s+-{2,})+\s*$') {
            $cols = [regex]::Matches($lines[$i], '-+')
            $row = $lines[$i + 1]
            if ($cols.Count -lt 2 -or -not $row.Trim()) { return 'NOVOLUME' }
            $c = $cols[1]                                                   # 2nd column = drive letter
            $l = $row.PadRight($c.Index + $c.Length).Substring($c.Index, $c.Length).Trim()
            if ($l -cmatch '^[A-Z]$') { return $l } else { return '' }
        }
    }
    return 'NOVOLUME'                                                       # no volume table at all
}
# The Storage cmdlets cache disk/partition data per process and do not see letters that diskpart (or another
# program) changed meanwhile. Refresh before trusting Get-Partition.
function Sync-StorageCache { if (Get-Command Update-HostStorageCache -ErrorAction SilentlyContinue) { try { Update-HostStorageCache -ErrorAction Stop } catch {} } }
# $true for the Microsoft Reserved partition (GPT type e3c9e316-...): it has no file system, and a drive letter on it
# makes Explorer offer to FORMAT it.
function Test-IsMsr($disk, $part) {
    $msr = 'e3c9e316-0b5c-4db8-817d-f92df00215ae'
    if (Get-Command Get-Partition -ErrorAction SilentlyContinue) {
        try { Sync-StorageCache; return ([string](Get-Partition -DiskNumber $disk -PartitionNumber $part -ErrorAction Stop).GptType -match $msr) } catch {}
    }
    return ((Invoke-Diskpart @("select disk $disk", "select partition $part", 'detail partition')) -match $msr)
}
# Partition behind a drive letter. Get-Partition does NOT report letters that diskpart assigned (seen on the EFI
# partition, even in a new process), so go letter -> volume GUID (mountvol, language-independent) -> partition AccessPaths.
function Get-LetterPartition($L) {
    $vol = (& mountvol.exe ('{0}:' -f $L) /L 2>$null | Out-String).Trim()
    if ($vol -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]+\}\\$') { return $null }
    if (-not (Get-Command Get-Partition -ErrorAction SilentlyContinue)) { return $null }
    Sync-StorageCache
    return (Get-Partition -ErrorAction SilentlyContinue | Where-Object { @($_.AccessPaths) -contains $vol } | Select-Object -First 1)
}
function Mount-Part($disk, $part, $L) {
    if (Test-IsMsr $disk $part) { throw "Partition $part on disk $disk is the Microsoft Reserved (MSR) partition. It has no file system and must not get a drive letter." }
    if ($rbStor.Checked) {
        Log "Add-PartitionAccessPath -DiskNumber $disk -PartitionNumber $part -AccessPath ${L}:"
        Add-PartitionAccessPath -DiskNumber $disk -PartitionNumber $part -AccessPath ('{0}:' -f $L) -ErrorAction Stop
    } else {
        [void](Invoke-Diskpart @("select disk $disk", "select partition $part", "assign letter=$L"))
    }
    Start-Sleep -Milliseconds 800
    return (Test-LetterUsed $L)
}
function Unmount-Letter($L) {
    if ($rbStor.Checked) {
        $p = Get-LetterPartition $L
        $done = $false
        if ($p) {
            Log "Remove-PartitionAccessPath ${L}:"
            try { Remove-PartitionAccessPath -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -AccessPath ('{0}:' -f $L) -ErrorAction Stop; $done = $true } catch { Log "Remove-PartitionAccessPath failed ($($_.Exception.Message)) - using mountvol." }
        }
        # letters assigned by diskpart are invisible to the Storage cmdlets: remove the mount point directly
        if (-not $done) { Log "mountvol ${L}: /D"; $o = (& mountvol.exe ('{0}:' -f $L) /D 2>&1 | Out-String).Trim(); if ($LASTEXITCODE -ne 0) { throw "mountvol ${L}: /D failed: $o" } }
    } else {
        [void](Invoke-Diskpart @("select volume $L", "remove letter=$L"))
    }
}
$script:Mounts = New-Object Collections.ArrayList
function Save-Mounts { try { Set-Content -Path $StateFile -Value (ConvertTo-Json -InputObject @($script:Mounts)) -Encoding UTF8 -ErrorAction Stop } catch { Log "WARNING: could not save the mount memory (${StateFile}): $($_.Exception.Message). These mounts will not be remembered." } }
function Load-Mounts {
    $script:Mounts = New-Object Collections.ArrayList
    if (Test-Path $StateFile) {
        try {
            $j = Get-Content $StateFile -Raw
            if ($j -and $j.Trim()) {
                # PS 5.1 returns a JSON array as ONE object: foreach (not @(...)) enumerates it correctly.
                $parsed = ConvertFrom-Json $j
                Sync-StorageCache
                foreach ($m in $parsed) {
                    if (-not $m -or -not $m.Letter) { continue }
                    if (Test-MountStillOurs $m) { [void]$script:Mounts.Add($m) }
                    else { Log "Forgot remembered mount $($m.Letter): - it no longer points at Disk $($m.Disk), Partition $($m.Partition)." }
                }
            }
        } catch { Log "Could not read the mount memory file ${StateFile}: $($_.Exception.Message)" }
    }
}
# A remembered mount is trusted only if its letter STILL belongs to the same disk + partition.
# Otherwise "Unmount" could remove the letter of a different drive that took that letter since.
function Test-MountStillOurs($m) {
    $L = ([string]$m.Letter).ToUpper()
    if (-not $L -or -not (Test-LetterUsed $L)) { return $false }
    # WinPE without Storage cmdlets: ask diskpart which letter that disk/partition has now
    if (-not (Get-Command Get-Partition -ErrorAction SilentlyContinue)) { return ((Get-DpPartLetter $m.Disk $m.Partition) -eq $L) }
    $p = Get-LetterPartition $L                                                           # $null = cannot verify -> do not trust
    if (-not $p) { return $false }
    return ([int]$p.DiskNumber -eq [int]$m.Disk -and [int]$p.PartitionNumber -eq [int]$m.Partition)
}
function Update-MountList {
    $lstMounts.Items.Clear()
    foreach ($m in $script:Mounts) { [void]$lstMounts.Items.Add(('{0}:   (Disk {1}, Partition {2})' -f $m.Letter, $m.Disk, $m.Partition)) }
}
function Update-Letters {
    $cmbLetter.Items.Clear()
    $used = @([IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpper() })
    foreach ($c in 68..90) { $l = [string][char]$c; if ($used -notcontains $l) { [void]$cmbLetter.Items.Add($l) } }
    if ($cmbLetter.Items.Count) { $cmbLetter.SelectedIndex = 0 }
}
function Update-Disks {
    $cmbDisk.Items.Clear(); $cmbPart.Items.Clear()
    foreach ($d in @(Get-DiskList)) { [void]$cmbDisk.Items.Add($d) }
    if ($cmbDisk.Items.Count) { $cmbDisk.SelectedIndex = 0 }
}
function Update-Parts {
    $cmbPart.Items.Clear()
    $d = $cmbDisk.SelectedItem; if (-not $d) { return }
    foreach ($p in @(Get-PartList $d.Num)) { [void]$cmbPart.Items.Add($p) }
    if ($cmbPart.Items.Count) { $cmbPart.SelectedIndex = 0 }
}
function Dismount-One($m) {
    $L = ([string]$m.Letter).ToUpper()
    if ($L -notmatch '^[A-Z]$') { Log "Refusing to unmount: '$L' is not a drive letter."; return $false }
    if ($L -eq $env:SystemDrive.Substring(0, 1).ToUpper()) { Log "Refusing to unmount the system drive ${L}:"; return $false }
    # the letter may have been taken by ANOTHER volume since it was mounted here (Explorer, Disk Management, USB re-plug)
    if (Test-LetterUsed $L) {
        $owner = $null                                                  # $null = cannot tell -> keep the old behaviour
        if (Get-Command Get-Partition -ErrorAction SilentlyContinue) {
            $p = Get-LetterPartition $L
            if ($p) { $owner = ([int]$p.DiskNumber -eq [int]$m.Disk -and [int]$p.PartitionNumber -eq [int]$m.Partition) }
        } else { $owner = ((Get-DpPartLetter $m.Disk $m.Partition) -eq $L) }
        if ($owner -eq $false) { Log "${L}: now belongs to another partition - forgetting it, NOT unmounting."; $script:Mounts.Remove($m); return $false }
    }
    try { if (Test-LetterUsed $L) { Unmount-Letter $L; Start-Sleep -Milliseconds 600 } } catch { Log "Unmount error: $($_.Exception.Message)" }
    if (Test-LetterUsed $L) { Log "Could not unmount ${L}: (in use?)"; return $false }
    $script:Mounts.Remove($m); Log "Unmounted ${L}:"; return $true
}
function Update-AfterMountChange { Save-Mounts; Update-MountList; Update-Letters; Update-Esp; Update-Windows }

# =====================================================================
#  5. SAFE MODE / BCD
# =====================================================================
function ConvertFrom-BcdText([string]$text) {
    foreach ($blk in [regex]::Split($text, '(?:\r?\n){2,}')) {
        # The identifier is the first line under the ----- underline. Its label is translated on non-English Windows
        # (identifier / Bezeichner / identificateur ...), so match the position + {...} value, not the word.
        if ($blk -match '(?m)^-{3,}[ \t]*\r?\n[^{\r\n]*?\s(\{[^}\r\n]+\})[ \t]*\r?$' -or $blk -match '(?m)^identifier\s+(\{[^}]+\})') {
            $id = $Matches[1]; $dev = ''; $sb = ''; $desc = ''
            if ($blk -match '(?m)^osdevice\s+partition=([A-Za-z]:)') { $dev = $Matches[1].ToUpper() }
            if ($blk -match '(?m)^safeboot\s+(\S+)') { $sb = $Matches[1] }
            if ($blk -match '(?m)^description\s+(.+?)\s*$') { $desc = $Matches[1] }
            [pscustomobject]@{ Id = $id; Dev = $dev; Safeboot = $sb; Desc = $desc }
        }
    }
}
function Get-BcdAll($t) {
    $a = @(); if ($t.Store) { $a += '/store'; $a += $t.Store }; $a += '/enum'; $a += 'osloader'
    return @(ConvertFrom-BcdText ((& bcdedit.exe @a 2>&1) | Out-String))
}
function Resolve-BcdTarget($drive) {
    if (-not $IsWinPE -and $drive -eq $env:SystemDrive.ToUpper()) {
        $e = @(ConvertFrom-BcdText ((& bcdedit.exe /enum '{current}' 2>&1) | Out-String)) | Select-Object -First 1
        $sb = ''; if ($e) { $sb = $e.Safeboot }
        return @{ Store = $null; Id = '{current}'; Safeboot = $sb }
    }
    # Running Windows + another install on this PC (dual boot): its entry normally lives in the LOADED system store.
    # Use that (no /store): the same file on a mounted ESP is locked as a registry hive, so backups would fail.
    if (-not $IsWinPE) {
        foreach ($e in @(ConvertFrom-BcdText ((& bcdedit.exe /enum osloader 2>&1) | Out-String))) {
            if ($e.Dev -eq $drive.ToUpper()) { return @{ Store = $null; Id = $e.Id; Safeboot = $e.Safeboot } }
        }
    }
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -notin 'Fixed', 'Removable' -or -not $d.IsReady) { continue }   # no network / optical drives
        $l = $d.Name.Substring(0, 2)
        foreach ($rel in '\EFI\Microsoft\Boot\BCD', '\Boot\BCD') {
            $store = "$l$rel"
            if (-not [IO.File]::Exists($store)) { continue }
            $txt = (& bcdedit.exe /store $store /enum osloader 2>&1) | Out-String
            foreach ($e in @(ConvertFrom-BcdText $txt)) {
                if ($e.Dev -eq $drive.ToUpper()) { return @{ Store = $store; Id = $e.Id; Safeboot = $e.Safeboot } }
            }
        }
    }
    return $null
}
function Get-Clones($t, $drive) {
    return @(Get-BcdAll $t | Where-Object { $_.Dev -eq $drive.ToUpper() -and $CloneMarkers -contains $_.Desc -and $_.Id -match '^\{[0-9a-fA-F-]{36}\}$' })
}
function Backup-Bcd($t) {
    try {
        [void][IO.Directory]::CreateDirectory($BcdBackupDir)
        $f = Join-Path $BcdBackupDir ('BCD_{0}.bak' -f (Get-Date -Format yyyyMMdd_HHmmss))
        if ($t.Store) {
            # offline store (WinPE / another drive): "bcdedit /store X /export Y" is not supported, so copy the file
            [IO.File]::Copy($t.Store, $f, $true); [IO.File]::SetAttributes($f, 'Normal'); $o = ''; $ok = [IO.File]::Exists($f)
        } else {
            $o = (& bcdedit.exe /export $f 2>&1) | Out-String; $ok = ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($f))
        }
        if ($ok) {
            Log "BCD backup saved: $f"
            if ($DataOnRam) { Log 'NOTE: that is the WinPE RAM disk - copy the backup somewhere permanent.' }
            return $true
        }
        Log "BCD backup FAILED: $($o.Trim())"
    } catch { Log "BCD backup error: $($_.Exception.Message)" }
    return $false
}
# every BCD-changing command is preceded by an automatic backup - and is NOT run if that backup fails
function Invoke-Bcd($t, [string[]]$BcdArgs) {
    # A failed "bcdedit /import" can leave the running system's BCD store CLOSED (HKLM\BCD00000000 unloaded) until a
    # restart - seen on VirtualBox UEFI. Every later bcdedit call then fails, so stop and say so instead.
    if ($null -eq $script:BcdLoadedAtStart) { $script:BcdLoadedAtStart = Test-Path 'HKLM:\BCD00000000' }
    if ($script:BcdStoreLost -and -not $t.Store) {
        Log ('NOT RUN (BCD store closed - restart needed): bcdedit ' + ($BcdArgs -join ' '))
        return [pscustomobject]@{ Rc = 1; Out = 'The boot store of this Windows is CLOSED after a failed bcdedit /import. Restart Windows before using any BCD tool.' }
    }
    # back up before EVERYTHING except the known read-only verbs (so a future button using /default, /displayorder ... is covered too)
    if ($BcdArgs[0] -notin '/enum', '/v', '/export', '/?') {
        if (-not (Backup-Bcd $t)) {
            Log ('NOT RUN (no backup): bcdedit ' + ($BcdArgs -join ' '))
            return [pscustomobject]@{ Rc = 1; Out = 'The BCD backup failed, so the change was NOT made. See the activity log.' }
        }
    }
    $a = @(); if ($t.Store) { $a += '/store'; $a += $t.Store }; $a += $BcdArgs
    Log ('bcdedit ' + ($a -join ' '))
    $o = (& bcdedit.exe @a 2>&1) | Out-String
    $rc = $LASTEXITCODE
    Log $o.Trim()
    if ($rc -ne 0 -and -not $t.Store -and $script:BcdLoadedAtStart -and -not (Test-Path 'HKLM:\BCD00000000')) {
        $script:BcdStoreLost = $true
        $warn = "The boot configuration store of this Windows is now CLOSED (bcdedit can no longer open it).${NL}${NL}- Restart Windows before using any Safe Mode, boot menu or BCD tool - they are blocked until then.${NL}- In testing, the BCD on disk was NOT changed by the failed command and Windows started normally.${NL}- To restore a BCD backup reliably, run this tool from WinPE (it then restores by verified file copy)."
        Log "WARNING: BCD store closed after a failed bcdedit $($BcdArgs[0]) - restart needed."
        Msg $warn 'Restart required' 'Warning'
        $o += $NL + $warn
    }
    return [pscustomobject]@{ Rc = $rc; Out = $o }
}
# Restore a BCD backup.
#  - Offline store (WinPE, or the BCD of another drive): verified FILE COPY - no firmware sync involved.
#  - Store of the RUNNING Windows: bcdedit /import (cannot copy over a loaded store). This fails on some UEFI firmware;
#    Invoke-Bcd then detects the closed store and blocks further BCD actions until a restart.
function Restore-BcdBackup($t, [string]$File) {
    if (-not [IO.File]::Exists($File)) { return [pscustomobject]@{ Rc = 1; Out = "Backup file not found: $File" } }
    if ($t.Store) {
        if (-not (Backup-Bcd $t)) { return [pscustomobject]@{ Rc = 1; Out = 'The BCD backup failed, so the restore was NOT done.' } }
        $attr = $null
        try {
            $attr = [IO.File]::GetAttributes($t.Store)
            [IO.File]::SetAttributes($t.Store, 'Normal')
            Copy-Item -LiteralPath $File -Destination $t.Store -Force -ErrorAction Stop
            $same = (Get-FileHash -LiteralPath $File).Hash -eq (Get-FileHash -LiteralPath $t.Store).Hash
            Log "BCD restored by file copy: $File -> $($t.Store) (verified identical: $same)"
            if ($same) { return [pscustomobject]@{ Rc = 0; Out = 'Restored by file copy (verified identical to the backup).' } }
            return [pscustomobject]@{ Rc = 1; Out = 'The file was copied, but the result does not match the backup.' }
        } catch { return [pscustomobject]@{ Rc = 1; Out = "File copy failed: $($_.Exception.Message)" } }
        finally { if ($null -ne $attr) { try { [IO.File]::SetAttributes($t.Store, $attr) } catch {} } }   # hidden+system back on every path
    }
    return (Invoke-Bcd $t @('/import', $File))
}
# A Safe Mode clone can only be picked in the boot menu; with "timeout 0" Windows never shows that menu.
# Only an explicit 0 is acted on (element names in bcdedit /enum output are not translated).
function Confirm-BootMenuShown($t) {
    $a = @(); if ($t.Store) { $a += '/store'; $a += $t.Store }; $a += '/enum'; $a += '{bootmgr}'
    $o = (& bcdedit.exe @a 2>&1) | Out-String
    if ($o -notmatch '(?m)^timeout\s+(\d+)\s*$' -or [int]$Matches[1] -gt 0) { return }
    if (Ask "The boot menu timeout is 0 seconds, so Windows starts without showing the boot menu and the Safe Mode entry cannot be picked.${NL}${NL}Set the boot menu timeout to 5 seconds?" 'Boot menu' 'Question') {
        $r = Invoke-Bcd $t @('/timeout', '5')
        if ($r.Rc -ne 0) { Msg 'Could not set the boot menu timeout. See the activity log.' 'Error' 'Error' }
    }
}
function Update-SafeLabels {
    if ($rbClone.Checked) { $btnSafeOn.Text = 'Create Safe Mode clone'; $btnSafeOff.Text = 'Delete Safe Mode clone(s)' }
    else { $btnSafeOn.Text = 'Enable Safe Mode (minimal)'; $btnSafeOff.Text = 'Remove Safe Mode flag' }
}
function Update-SafeStatus {
    $btnSafeOn.Enabled = $false; $btnSafeOff.Enabled = $false
    $w = Get-TargetWin
    if (-not $w) { $lblBcd.Text = 'Select the Target Windows at the top.'; return }
    $t = Resolve-BcdTarget $w.Drive
    if (-not $t) { $lblBcd.Text = "No boot entry for $($w.Drive) found in any BCD store. Mount the EFI / System partition on the Mount tab, then press Rescan."; return }
    $where = 'running system'; if ($t.Store) { $where = $t.Store }
    $sb = 'normal boot'; if ($t.Safeboot) { $sb = "SAFE MODE ($($t.Safeboot))" }
    $n = @(Get-Clones $t $w.Drive).Count
    $cl = 'none'; if ($n) { $cl = "present ($n)" }
    $lblBcd.Text = "Target: $($w.Text)${NL}Boot entry $($t.Id) in $where${NL}Entry state: $sb     |     Safe Mode clone: $cl"
    $btnSafeOn.Enabled = $true; $btnSafeOff.Enabled = $true
}

# =====================================================================
#  6. SYSPREP pre-flight checks (run on the live Windows, opt-in)
# =====================================================================
function Get-Preflight([string]$Mode) {
    $r = New-Object Collections.ArrayList
    $add = { param($l, $t) [void]$r.Add([pscustomobject]@{ Level = $l; Text = $t }) }
    $gen = ($Mode -eq 'A')
    $form.Cursor = 'WaitCursor'
    try {
        $sp = Join-Path $env:windir 'System32\Sysprep\sysprep.exe'
        if (Test-Path $sp) { & $add 'OK' 'sysprep.exe found.' } else { & $add 'FAIL' 'sysprep.exe not found.' }
        if (Get-Process sysprep -ErrorAction SilentlyContinue) { & $add 'FAIL' 'Sysprep is already running.' }

        $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        if ($pend) { & $add 'WARN' 'A reboot is pending (updates / servicing). Reboot first, then run sysprep.' } else { & $add 'OK' 'No pending reboot.' }

        try {
            $free = (New-Object IO.DriveInfo $env:SystemDrive).AvailableFreeSpace
            if ($free -lt 10GB) { & $add 'WARN' ('Only {0} free on {1}. Sysprep and image capture want roughly 10 GB or more.' -f (Fmt-Size $free), $env:SystemDrive) }
            else { & $add 'OK' ('{0} free on {1}.' -f (Fmt-Size $free), $env:SystemDrive) }
        } catch {}

        if ($gen) {
            $up = @(Get-ChildItem 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Source OS*' })
            if ($up.Count) { & $add 'WARN' 'This Windows looks like an in-place UPGRADE (Source OS keys present). Sysprep is not supported on upgraded installs - use a clean install.' }
            else { & $add 'OK' 'No in-place upgrade markers found.' }

            try {
                if ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain) { & $add 'WARN' 'This PC is joined to a domain. Generalize removes the domain join and is usually not wanted on a production PC.' }
                else { & $add 'OK' 'Not domain-joined.' }
            } catch {}

            $bls = Get-BitLockerState $env:SystemDrive
            if ($bls -eq 'On') { & $add 'WARN' "BitLocker / device encryption is active on $($env:SystemDrive). Decrypt the drive first (manage-bde -off $($env:SystemDrive)) - generalize fails otherwise." }
            elseif ($bls -eq 'Off') { & $add 'OK' "No BitLocker encryption on $($env:SystemDrive)." }
            else { & $add 'WARN' "Could not check BitLocker on $($env:SystemDrive): $bls. Check by hand with: manage-bde -status $($env:SystemDrive)" }

            $ans = @("$env:windir\Panther\unattend.xml", "$env:windir\Panther\Unattend\unattend.xml", "$env:windir\System32\Sysprep\unattend.xml", "$env:SystemDrive\unattend.xml", "$env:SystemDrive\autounattend.xml") | Where-Object { [IO.File]::Exists($_) }
            if (@($ans).Count) { & $add 'WARN' ('Existing answer file(s) found; they can conflict with the one you pass: ' + (@($ans) -join '; ')) }
            else { & $add 'OK' 'No leftover answer files found.' }

            # Provisioned (all-users) app list: Get-AppxProvisionedPackage, or - when that is denied (seen on Windows 11
            # build 26300 even as admin) - the AppxAllUserStore registry list, which does not depend on the display language.
            $prov = $null
            try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object { $_.DisplayName }) } catch {}
            if ($null -eq $prov) {
                $ak = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications'
                if (Test-Path $ak) { $prov = @(Get-ChildItem $ak | ForEach-Object { ($_.PSChildName -split '_')[0] } | Sort-Object -Unique) }
            }
            try {
                if ($null -eq $prov) { throw 'the provisioned-app list could not be read' }
                $bad = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and $_.SignatureKind -ne 'System' -and $prov -notcontains $_.Name } | ForEach-Object { $_.Name } | Sort-Object -Unique)
                if ($bad.Count) {
                    $shown = ($bad | Select-Object -First 15) -join ', '
                    & $add 'WARN' "Possible Store apps installed for a user but not provisioned for all users (the classic generalize failure): $shown. Remove them with Remove-AppxPackage -AllUsers if sysprep fails."
                } else { & $add 'OK' 'No per-user-only Store apps found.' }
            } catch { & $add 'WARN' ("Could not check for Store apps installed for one user only ($($_.Exception.Message)) - the most common reason generalize fails. If it fails, look for 'was installed for a user, but not provisioned for all users' in %windir%\System32\Sysprep\Panther\setupact.log.") }
        }

        $err = "$env:windir\System32\Sysprep\Panther\setuperr.log"
        if ([IO.File]::Exists($err)) {
            $tail = @(Get-Content $err -Tail 6 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
            if ($tail.Count) { & $add 'INFO' ("A previous sysprep error log exists ($err, " + (Get-Item $err).LastWriteTime + '). Last line: ' + $tail[-1]) }
        }
    } finally { $form.Cursor = 'Default' }
    return @($r)
}
function Format-Preflight($items) {
    $w = @($items | Where-Object { $_.Level -eq 'WARN' }).Count
    $f = @($items | Where-Object { $_.Level -eq 'FAIL' }).Count
    $head = "Pre-flight result: $f blocking problem(s), $w warning(s).$NL" + ('-' * 60) + $NL
    return $head + (($items | ForEach-Object { '[{0,-4}] {1}' -f $_.Level, $_.Text }) -join ($NL + $NL))
}

# =====================================================================
#  7. UNATTEND.XML builder
# =====================================================================
function Build-Unattend {
    $a = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $a = $env:PROCESSOR_ARCHITEW6432 }
    $arch = switch ($a) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'amd64' } }
    $user = $txtUser.Text.Trim(); $pcn = $txtPC.Text.Trim(); $locale = $txtLoc.Text.Trim()
    if (-not ($chkSkip.Checked -or $chkUser.Checked -or $chkPC.Checked -or $chkRegion.Checked)) { Msg 'Tick at least one option on the Unattend tab first.' 'Unattend' 'Warning'; return $null }
    if ($chkSkip.Checked -and -not $chkUser.Checked) { Msg "Skipping the OOBE screens without creating an account leaves no usable account.${NL}Tick 'Create local account' as well." 'Unattend' 'Warning'; return $null }
    if ($chkUser.Checked -and ($user.Length -lt 1 -or $user.Length -gt 20 -or $user -match "[\\/\[\]:;|=,+*?<>`"@%'$([char]0x2018)-$([char]0x201B)]")) { Msg 'User name must be 1-20 characters and may not contain \ / [ ] : ; | = , + * ? < > " @ % or apostrophes.' 'Unattend' 'Warning'; return $null }   # % would be expanded by cmd in FirstLogonCommands
    if ($chkUser.Checked -and $chkNoExp.Checked -and [string]$cmbGroup.SelectedItem -ne 'Administrators') { Msg "'Password never expires' runs as the new account at its first logon, and only an administrator may change that setting.${NL} Choose the Administrators group or untick 'Password never expires'." 'Unattend' 'Warning'; return $null }
    if ($chkPC.Checked -and $pcn -notmatch '^(\*|[A-Za-z0-9-]{1,15})$') { Msg 'Computer name: 1-15 letters, digits or hyphens, or * for a random name.' 'Unattend' 'Warning'; return $null }
    if ($chkRegion.Checked -and (-not $cmbTz.SelectedItem -or $locale -notmatch '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})+$')) { Msg 'Pick a time zone and enter a locale such as en-US.' 'Unattend' 'Warning'; return $null }

    $esc  = { param($s) [Security.SecurityElement]::Escape([string]$s) }
    $ns   = 'xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    $comp = { param($n) ('<component name="{0}" processorArchitecture="{1}" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" {2}>' -f $n, $arch, $ns) }
    $sb   = New-Object Text.StringBuilder
    $ap   = { param($s) [void]$sb.AppendLine($s) }
    # answer-file password obfuscation: base64(UTF-16LE(password + "Password"))
    $pw   = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($txtPass.Text + 'Password'))

    & $ap '<?xml version="1.0" encoding="utf-8"?>'
    & $ap '<unattend xmlns="urn:schemas-microsoft-com:unattend">'
    if ($chkPC.Checked) {
        & $ap '  <settings pass="specialize">'
        & $ap ('    ' + (& $comp 'Microsoft-Windows-Shell-Setup'))
        & $ap ('      <ComputerName>{0}</ComputerName>' -f (& $esc $pcn))
        & $ap '    </component>'
        & $ap '  </settings>'
    }
    if ($chkSkip.Checked -or $chkUser.Checked -or $chkRegion.Checked) {
        & $ap '  <settings pass="oobeSystem">'
        if ($chkRegion.Checked) {
            $le = & $esc $locale
            & $ap ('    ' + (& $comp 'Microsoft-Windows-International-Core'))
            & $ap "      <InputLocale>$le</InputLocale>"
            & $ap "      <SystemLocale>$le</SystemLocale>"
            & $ap "      <UILanguage>$le</UILanguage>"
            & $ap "      <UserLocale>$le</UserLocale>"
            & $ap '    </component>'
        }
        & $ap ('    ' + (& $comp 'Microsoft-Windows-Shell-Setup'))
        if ($chkLogon.Checked -and $chkUser.Checked) {
            & $ap '      <AutoLogon>'
            & $ap '        <Enabled>true</Enabled>'
            & $ap '        <LogonCount>1</LogonCount>'
            & $ap ('        <Username>{0}</Username>' -f (& $esc $user))
            & $ap ('        <Password><Value>{0}</Value><PlainText>false</PlainText></Password>' -f $pw)
            & $ap '      </AutoLogon>'
        }
        if ($chkNoExp.Checked -and $chkUser.Checked) {
            $cmd = & $esc ('powershell.exe -NoProfile -Command "Set-LocalUser -Name ''{0}'' -PasswordNeverExpires $true"' -f $user)
            & $ap '      <FirstLogonCommands>'
            & $ap '        <SynchronousCommand wcm:action="add">'
            & $ap '          <Order>1</Order>'
            & $ap "          <CommandLine>$cmd</CommandLine>"
            & $ap '          <Description>Password never expires</Description>'
            & $ap '        </SynchronousCommand>'
            & $ap '      </FirstLogonCommands>'
        }
        if ($chkSkip.Checked) {
            & $ap '      <OOBE>'
            & $ap '        <HideEULAPage>true</HideEULAPage>'
            & $ap '        <HideLocalAccountScreen>true</HideLocalAccountScreen>'
            & $ap '        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>'
            & $ap '        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>'
            & $ap '        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>'
            & $ap '        <NetworkLocation>Work</NetworkLocation>'
            & $ap '        <ProtectYourPC>3</ProtectYourPC>'
            & $ap '      </OOBE>'
        }
        if ($chkRegion.Checked) { & $ap ('      <TimeZone>{0}</TimeZone>' -f (& $esc ([string]$cmbTz.SelectedItem))) }
        if ($chkUser.Checked) {
            & $ap '      <UserAccounts>'
            & $ap '        <LocalAccounts>'
            & $ap '          <LocalAccount wcm:action="add">'
            & $ap ('            <Name>{0}</Name>' -f (& $esc $user))
            & $ap ('            <DisplayName>{0}</DisplayName>' -f (& $esc $user))
            & $ap ('            <Group>{0}</Group>' -f [string]$cmbGroup.SelectedItem)
            & $ap ('            <Password><Value>{0}</Value><PlainText>false</PlainText></Password>' -f $pw)
            & $ap '          </LocalAccount>'
            & $ap '        </LocalAccounts>'
            & $ap '      </UserAccounts>'
        }
        & $ap '    </component>'
        & $ap '  </settings>'
    }
    & $ap '</unattend>'
    return $sb.ToString()
}
function Write-Xml($path, $xml) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $xml, (New-Object Text.UTF8Encoding $false))
}
function Update-UnattendUi {
    $u = $chkUser.Checked
    foreach ($c in $txtUser, $txtPass, $chkShowPw, $cmbGroup, $chkNoExp, $chkLogon) { $c.Enabled = $u }
    if (-not $u) { $chkLogon.Checked = $false; $chkNoExp.Checked = $false }
    $txtPC.Enabled = $chkPC.Checked
    $cmbTz.Enabled = $chkRegion.Checked; $txtLoc.Enabled = $chkRegion.Checked
}
function Init-Unattend {
    try { foreach ($z in [TimeZoneInfo]::GetSystemTimeZones()) { [void]$cmbTz.Items.Add($z.Id) } } catch {}
    if ($cmbTz.Items.Count -eq 0) { foreach ($z in 'Pacific Standard Time', 'Mountain Standard Time', 'Central Standard Time', 'Eastern Standard Time', 'UTC') { [void]$cmbTz.Items.Add($z) } }
    try { $i = $cmbTz.Items.IndexOf([TimeZoneInfo]::Local.Id); if ($i -ge 0) { $cmbTz.SelectedIndex = $i } } catch {}
    if ($cmbTz.SelectedIndex -lt 0) { $cmbTz.SelectedIndex = 0 }
    $loc = 'en-US'; try { if ((Get-Culture).Name) { $loc = (Get-Culture).Name } } catch {}
    $txtLoc.Text = $loc
    Update-UnattendUi
}

# =====================================================================
#  8. EXPERIMENTAL boot recovery tools
# =====================================================================
function Update-Esp {
    $prev = ''
    if ($cmbEsp.SelectedItem) { $prev = $cmbEsp.SelectedItem.Drive }
    $cmbEsp.Items.Clear()
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        $t = $d.DriveType.ToString()
        if ($t -ne 'Fixed' -and $t -ne 'Removable') { continue }
        if (-not $d.IsReady) { continue }
        $l = $d.Name.Substring(0, 2)
        if ($IsWinPE -and $l -eq $env:SystemDrive) { continue }
        $mb = [math]::Round($d.TotalSize / 1MB)
        $rem = ($t -eq 'Removable'); $tag = if ($rem) { '  (removable)' } else { '' }
        [void]$cmbEsp.Items.Add([pscustomobject]@{ Drive = $l; FS = $d.DriveFormat; Text = ('{0}  [{1}]  {2}  {3} MB{4}' -f $l, $d.VolumeLabel, $d.DriveFormat, $mb, $tag); MB = $mb; Removable = $rem })
    }
    $pick = -1
    for ($i = 0; $i -lt $cmbEsp.Items.Count; $i++) { if ($prev -and $cmbEsp.Items[$i].Drive -eq $prev) { $pick = $i } }
    # auto-pick only a small FAT32 partition on a FIXED disk - never a USB stick (it can still be chosen by hand)
    if ($pick -lt 0) { for ($i = 0; $i -lt $cmbEsp.Items.Count; $i++) { $x = $cmbEsp.Items[$i]; if ($x.FS -eq 'FAT32' -and $x.MB -lt 1100 -and -not $x.Removable) { $pick = $i; break } } }
    if ($pick -ge 0) { $cmbEsp.SelectedIndex = $pick }
}

# Exe tools : Exe + Argv (param $c -> argument array, or @{Exe;Args} to use another program; empty = cancel) + Window ($true = own console)
# Script tools: Build (param $c, $tool -> @{Summary; Run; RunArg}; $null = cancel)
# $c = @{ Win = 'D:'; Live = running Windows?; Esp = 'S:'; EspFS = 'FAT32' }
$BcdSetBuild = {
    param($c, $tool)
    $t = Resolve-BcdTarget $c.Win
    if (-not $t) { Msg 'No boot entry found for that install. Mount the EFI partition first.' 'Recovery' 'Warning'; return $null }
    return @{
        Summary = "bcdedit /set $($t.Id) $($tool.Elem) $($tool.Val)"
        RunArg  = @{ T = $t; E = $tool.Elem; V = $tool.Val }
        Run     = { param($a) $r = Invoke-Bcd $a.T @('/set', $a.T.Id, $a.E, $a.V); if ($r.Rc -ne 0) { Msg 'bcdedit reported an error. See the log.' 'Error' 'Error' } }
    }
}
$Tools = @(
    [pscustomobject]@{ Name = 'BCD: back up store (export)'; Needs = 'install'
        Help = "Exports the BCD store that boots the Target Windows to a timestamped file in WinSuperTool-Data\BCD-Backups.${NL}${NL}Use cases:${NL}- Take a safety copy before any boot repair.${NL}- Keep a known-good copy to restore later.${NL}${NL}Every BCD change made by this tool already makes an automatic backup first."
        Build = { param($c, $tool)
            $t = Resolve-BcdTarget $c.Win
            if (-not $t) { Msg 'No boot entry found for that install. Mount the EFI partition first.' 'Recovery' 'Warning'; return $null }
            return @{ Summary = $(if ($t.Store) { 'copy the offline BCD file to a timestamped backup' } else { 'bcdedit /export <timestamped file>' }); Run = { param($a) if (-not (Backup-Bcd $a)) { Msg 'The BCD backup failed. See the activity log.' 'Error' 'Error' } }; RunArg = $t } } },
    [pscustomobject]@{ Name = 'BCD: restore from backup (import)'; Needs = 'install'
        Help = "Replaces the boot configuration store with a backup file made earlier.${NL}${NL}Use cases:${NL}- Undo a failed repair or rebuild.${NL}- Recover after a bad BCD edit.${NL}${NL}A fresh backup of the current store is taken first. This replaces the WHOLE store.${NL}${NL}In WinPE / for another drive's BCD: restored by a verified file copy (reliable).${NL}For the RUNNING Windows: bcdedit /import - this fails on some UEFI PCs and VMs (seen on VirtualBox) and then closes the boot store until Windows restarts. Prefer running the restore from WinPE."
        Build = { param($c, $tool)
            $t = Resolve-BcdTarget $c.Win
            if (-not $t) { Msg 'No boot entry found for that install. Mount the EFI partition first.' 'Recovery' 'Warning'; return $null }
            if (-not $t.Store -and -not (Ask "This restores into the boot store of the RUNNING Windows with bcdedit /import.${NL}${NL}On some UEFI PCs and virtual machines (seen on VirtualBox) bcdedit /import FAILS and then closes the boot store until Windows restarts. In testing the BCD on disk stayed as it was and Windows started normally.${NL}${NL}The reliable way: run this tool from WinPE (Hiren's) - the restore is then a verified file copy.${NL}${NL}Try bcdedit /import now?" 'Restore BCD into the running Windows' 'Warning' 'Button2')) { return $null }
            $dlg = New-Object Windows.Forms.OpenFileDialog; $dlg.Title = 'Select a BCD backup file'
            if (Test-Path $BcdBackupDir) { $dlg.InitialDirectory = $BcdBackupDir }
            if ($dlg.ShowDialog() -ne 'OK') { return $null }
            $how = if ($t.Store) { "copy `"$($dlg.FileName)`" over $($t.Store) (verified)" } else { "bcdedit /import `"$($dlg.FileName)`"" }
            return @{ Summary = $how; RunArg = @{ T = $t; F = $dlg.FileName }
                Run = { param($a) $r = Restore-BcdBackup $a.T $a.F; if ($r.Rc -ne 0) { Msg ("Restore failed:${NL}${NL}" + $r.Out.Trim()) 'Error' 'Error' } else { Msg $r.Out.Trim() } } } } },
    [pscustomobject]@{ Name = 'Rebuild boot files (bcdboot)'; Needs = 'both'; Exe = 'bcdboot.exe'; Window = $false; Kind = 'bcdboot'
        Help = "bcdboot <Windows>\Windows /s <boot partition> /f UEFI|BIOS${NL}${NL}Copies fresh boot files from the Target Windows onto the chosen boot partition and creates a new BCD entry. Firmware type (/f) comes from how THIS PC boots (UEFI or BIOS); you are warned if the chosen partition does not match.${NL}${NL}Use cases:${NL}- 'BOOTMGR is missing' or 'winload.efi not found'.${NL}- Empty or recreated EFI partition.${NL}- Boot files damaged or wiped."
        Argv = { param($c)
            # /f follows the FIRMWARE of this PC, not the file system of the picked partition (a FAT32 USB stick is not an ESP)
            $byFs = 'BIOS'; if ($c.EspFS -eq 'FAT32') { $byFs = 'UEFI' }
            $fw = Get-FirmwareType
            if (-not $fw) { $fw = $byFs }
            elseif ($fw -ne $byFs) {
                $why = if ($fw -eq 'UEFI') { "This PC boots in UEFI mode, but $($c.Esp) is $($c.EspFS) - the EFI system partition is normally a small FAT32 partition." } else { "This PC boots in legacy BIOS mode, but $($c.Esp) is FAT32 (that looks like an EFI partition)." }
                if (-not (Ask "$why${NL}${NL}bcdboot will use /f $fw (the firmware of THIS PC). Check that you picked the right boot partition.${NL}${NL}Continue?" 'Check boot partition' 'Warning' 'Button2')) { return @() }
            }
            @("$($c.Win)\Windows", '/s', $c.Esp, '/f', $fw) } },
    [pscustomobject]@{ Name = 'Scan for Windows installs (bootrec /scanos)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $false; Kind = 'bootrec-scan'
        Help = "bootrec /scanos${NL}${NL}Read-only scan for Windows installations that are not in the boot menu.${NL}${NL}Use case: check whether Windows is detected before rebuilding the BCD.${NL}bootrec ships with WinRE; some WinPE builds do not include it."
        Argv = { param($c) @('/scanos') } },
    [pscustomobject]@{ Name = 'Rebuild BCD (bootrec /rebuildbcd)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $true; Kind = 'bootrec'
        Help = "bootrec /rebuildbcd${NL}${NL}Scans for installs and offers to add them to the BCD (asks Yes / No / All in its own window).${NL}${NL}Use cases: missing boot menu entry; 'no operating system found'.${NL}Tip: run 'BCD: back up store' first."
        Argv = { param($c) @('/rebuildbcd') } },
    [pscustomobject]@{ Name = 'Write new MBR (bootrec /fixmbr)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $false; Kind = 'bootrec'
        Help = "bootrec /fixmbr${NL}${NL}Writes a standard Windows master boot record to the system disk without touching the partition table.${NL}${NL}Use cases: corrupted MBR, boot-sector virus, a non-Windows loader left on a BIOS/MBR disk.${NL}Rarely needed on UEFI/GPT disks."
        Argv = { param($c)
            if ((Get-FirmwareType) -eq 'UEFI' -and -not (Ask "This PC boots in UEFI mode. bootrec /fixmbr only matters for BIOS/MBR disks and does not repair UEFI boot - use 'Rebuild boot files (bcdboot)' instead.${NL}${NL}Run it anyway?" 'UEFI system' 'Warning' 'Button2')) { return @() }
            @('/fixmbr') } },
    [pscustomobject]@{ Name = 'Write boot sector (bootrec /fixboot)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $false; Kind = 'bootrec'
        Help = "bootrec /fixboot${NL}${NL}Writes a new boot sector to the system partition.${NL}${NL}Use case: BIOS/MBR systems with a damaged boot sector.${NL}On UEFI it often returns 'Access is denied' - use 'Rebuild boot files (bcdboot)' instead."
        Argv = { param($c)
            if ((Get-FirmwareType) -eq 'UEFI' -and -not (Ask "This PC boots in UEFI mode. bootrec /fixboot is for BIOS/MBR boot sectors and usually fails with 'Access is denied' on UEFI - use 'Rebuild boot files (bcdboot)' instead.${NL}${NL}Run it anyway?" 'UEFI system' 'Warning' 'Button2')) { return @() }
            @('/fixboot') } },
    [pscustomobject]@{ Name = 'System file check, scan only (sfc /verifyonly)'; Needs = 'install'; Exe = 'sfc.exe'; Window = $true; Kind = 'sfc-verify'; Logs = @('CBS.log - SFC lines only ([SR])')
        Help = "Offline install: sfc /verifyonly /offbootdir=D:\ /offwindir=D:\Windows${NL}Running Windows: sfc /verifyonly${NL}${NL}Checks the protected system files of the Target Windows for corruption WITHOUT repairing anything.${NL}${NL}Use case: find out whether system files are corrupt before deciding to repair."
        Argv = { param($c) if ($c.Live) { @('/verifyonly') } else { @('/verifyonly', "/offbootdir=$($c.Win)\", "/offwindir=$($c.Win)\Windows") } } },
    [pscustomobject]@{ Name = 'System file check and repair (sfc /scannow)'; Needs = 'install'; Exe = 'sfc.exe'; Window = $true; Kind = 'sfc'; Logs = @('CBS.log - SFC lines only ([SR])')
        Help = "Offline install: sfc /scannow /offbootdir=D:\ /offwindir=D:\Windows${NL}Running Windows: sfc /scannow${NL}${NL}Verifies and repairs protected system files of the Target Windows.${NL}${NL}Use cases: Windows will not boot because of corrupt system files; after malware or a failed update."
        Argv = { param($c) if ($c.Live) { @('/scannow') } else { @('/scannow', "/offbootdir=$($c.Win)\", "/offwindir=$($c.Win)\Windows") } } },
    [pscustomobject]@{ Name = 'DISM: check health (quick, read-only)'; Needs = 'install'; Exe = 'dism.exe'; Window = $true; Kind = 'dism-check'; Logs = @('dism.log')
        Help = "Offline install: dism /image:D:\ /cleanup-image /checkhealth${NL}Running Windows: dism /online /cleanup-image /checkhealth${NL}${NL}Quick check (seconds): reports whether the component store has already been flagged as corrupt, and whether it can be repaired. Changes nothing.${NL}${NL}Use case: a fast first look before a full scan or repair."
        Argv = { param($c) if ($c.Live) { @('/online', '/cleanup-image', '/checkhealth') } else { @("/image:$($c.Win)\", '/cleanup-image', '/checkhealth') } } },
    [pscustomobject]@{ Name = 'DISM: scan health (full scan, read-only)'; Needs = 'install'; Exe = 'dism.exe'; Window = $true; Kind = 'dism-check'; Logs = @('dism.log', 'CBS.log (full)')
        Help = "Offline install: dism /image:D:\ /cleanup-image /scanhealth /scratchdir:D:\Windows\Temp${NL}Running Windows: dism /online /cleanup-image /scanhealth${NL}${NL}Full scan of the component store for corruption (several minutes). Repairs nothing.${NL}${NL}Use case: find out whether 'DISM: restore health' is needed."
        Argv = { param($c) if ($c.Live) { @('/online', '/cleanup-image', '/scanhealth') } else { @("/image:$($c.Win)\", '/cleanup-image', '/scanhealth', "/scratchdir:$($c.Win)\Windows\Temp") } } },
    [pscustomobject]@{ Name = 'DISM: restore health'; Needs = 'install'; Exe = 'dism.exe'; Window = $true; Kind = 'dism-restore'; Logs = @('dism.log', 'CBS.log (full)')
        Help = "Offline install: dism /image:D:\ /cleanup-image /restorehealth /scratchdir:D:\Windows\Temp${NL}Running Windows: dism /online /cleanup-image /restorehealth${NL}${NL}Repairs the component store.${NL}${NL}Use case: sfc cannot repair files. Offline repair may fail without a /source (install.wim); check the console output."
        Argv = { param($c) if ($c.Live) { @('/online', '/cleanup-image', '/restorehealth') } else { @("/image:$($c.Win)\", '/cleanup-image', '/restorehealth', "/scratchdir:$($c.Win)\Windows\Temp") } } },
    [pscustomobject]@{ Name = 'Drivers: list third-party drivers'; Needs = 'install'; Exe = 'dism.exe'; Window = $true; Kind = 'driver-list'; Logs = @('dism.log')
        Help = "dism /image:D:\ /get-drivers   (running Windows: dism /online /get-drivers)${NL}${NL}Read-only list of non-Microsoft drivers (oemNN.inf).${NL}${NL}Use case: find the NVMe / RAID / Intel RST-VMD driver name before removing it."
        Argv = { param($c) if ($c.Live) { @('/online', '/get-drivers') } else { @("/image:$($c.Win)\", '/get-drivers') } } },
    [pscustomobject]@{ Name = 'Drivers: inject from folder'; Needs = 'install'; Exe = 'dism.exe'; Window = $true; Kind = 'driver'; Logs = @('dism.log', 'setupapi.dev.log (drivers/devices)')
        Help = "Offline install: dism /image:D:\ /add-driver /driver:<folder> /recurse${NL}Running Windows: pnputil /add-driver <folder>\*.inf /subdirs /install${NL}${NL}Adds every driver found in a folder.${NL}${NL}Use cases: 0x7B INACCESSIBLE_BOOT_DEVICE after moving the disk to new hardware; adding NVMe / RAID / VMD storage drivers so Windows can boot."
        Argv = { param($c)
            $fb = New-Object Windows.Forms.FolderBrowserDialog; $fb.Description = 'Folder containing the driver .inf files'
            if ($fb.ShowDialog() -ne 'OK') { return @() }
            if ($c.Live) { return @{ Exe = 'pnputil.exe'; Args = @('/add-driver', (Join-Path $fb.SelectedPath '*.inf'), '/subdirs', '/install') } }
            return @("/image:$($c.Win)\", '/add-driver', "/driver:$($fb.SelectedPath)", '/recurse') } },
    [pscustomobject]@{ Name = 'Drivers: remove one (oemNN.inf)'; Needs = 'install'; Exe = 'dism.exe'; Window = $true; Kind = 'driver'; Logs = @('dism.log', 'setupapi.dev.log (drivers/devices)')
        Help = "Offline install: dism /image:D:\ /remove-driver /driver:oemNN.inf${NL}Running Windows: pnputil /delete-driver oemNN.inf /uninstall${NL}${NL}Removes one third-party driver package.${NL}${NL}Use cases: a storage / RAID driver is causing a boot crash; clean up before switching controller mode.${NL}Run 'Drivers: list third-party drivers' first to get the oemNN.inf name."
        Argv = { param($c)
            $n = Read-Text 'Driver published name (for example oem12.inf):' 'Remove driver'
            if (-not $n) { return @() }
            if ($n -notmatch '^oem\d+\.inf$') { Msg 'Invalid name. Use the oemNN.inf name from the driver list.' 'Invalid' 'Warning'; return @() }
            if ($c.Live) { return @{ Exe = 'pnputil.exe'; Args = @('/delete-driver', $n, '/uninstall') } }
            return @("/image:$($c.Win)\", '/remove-driver', "/driver:$n") } },
    [pscustomobject]@{ Name = 'Check disk, read-only scan (chkdsk /scan)'; Needs = 'install'; Exe = 'chkdsk.exe'; Window = $true; Kind = 'chkdsk-scan'
        Help = "chkdsk D: /scan${NL}${NL}Scans the file system of the Target Windows volume without fixing anything.${NL}${NL}Use case: see whether file-system errors explain a boot failure."
        Argv = { param($c) @($c.Win, '/scan') } },
    [pscustomobject]@{ Name = 'Check disk and REPAIR (chkdsk /f)'; Needs = 'install'; Exe = 'chkdsk.exe'; Window = $true; Kind = 'chkdsk-fix'
        Help = "chkdsk D: /f${NL}${NL}Fixes file-system errors on the Target Windows volume. This WRITES to the disk. On the running system drive it asks to schedule the check for the next restart.${NL}${NL}Use case: the read-only scan reported errors. Back up important data first if possible."
        Argv = { param($c) @($c.Win, '/f') } },
    [pscustomobject]@{ Name = 'Boot menu: enable legacy F8 menu'; Needs = 'install'; Elem = 'bootmenupolicy'; Val = 'legacy'; Build = $BcdSetBuild
        Help = "bcdedit /set <entry> bootmenupolicy legacy${NL}${NL}Brings back the classic F8 Advanced Boot Options menu (Safe Mode, Disable driver signature enforcement...).${NL}${NL}Use case: you need F8 options on Windows 10/11." },
    [pscustomobject]@{ Name = 'Boot menu: restore standard menu'; Needs = 'install'; Elem = 'bootmenupolicy'; Val = 'standard'; Build = $BcdSetBuild
        Help = "bcdedit /set <entry> bootmenupolicy standard${NL}${NL}Returns to the default boot menu behavior (undoes the legacy F8 menu)." },
    [pscustomobject]@{ Name = 'Automatic Repair loop: disable'; Needs = 'install'; Elem = 'recoveryenabled'; Val = 'No'; Build = $BcdSetBuild
        Help = "bcdedit /set <entry> recoveryenabled No${NL}${NL}Stops Windows from launching Automatic Repair after failed boots.${NL}${NL}Use case: the PC loops 'Preparing Automatic Repair' / 'Diagnosing your PC' and you want to see the real error or reach Safe Mode." },
    [pscustomobject]@{ Name = 'Automatic Repair loop: re-enable'; Needs = 'install'; Elem = 'recoveryenabled'; Val = 'Yes'; Build = $BcdSetBuild
        Help = "bcdedit /set <entry> recoveryenabled Yes${NL}${NL}Turns Automatic Repair back on (the Windows default)." }
)

# =====================================================================
#  BETA: task summaries (pass / fail + the tool's own result message)
# =====================================================================
# Each tool with a Kind gets its result from the text the tool printed. Rules are checked in order; the first
# one whose pattern matches any output line wins, and that exact line is quoted in the summary.
#   Ok   = did the task run to the end ($false = it failed or did not run)
#   Tone = Good (green) / Bad (red) / Warn (orange) for the result line
# The patterns are the English messages. On another display language nothing matches and the exit code decides.
# Count = regex: append how often it occurs in the output, e.g. "APPS UPGRADED (3)". Also / AlsoText: appended when Also matches.
function New-TaskRule($p, $ok, $tone, $find, $next = '', $count = '', $also = '', $alsoText = '') { @{ P = $p; Ok = $ok; Tone = $tone; Find = $find; Next = $next; Count = $count; Also = $also; AlsoText = $alsoText } }
$SfcCommon = @(
    (New-TaskRule 'system repair pending which requires reboot' $false 'Warn' 'NOT CHECKED - a repair is waiting for a restart' 'Restart Windows, then run sfc again.')
    (New-TaskRule 'could not start the repair service' $false 'Bad' 'NOT CHECKED - sfc could not start the repair service' 'The Windows Modules Installer (TrustedInstaller) service must not be disabled. Try again, or try Safe Mode.')
    (New-TaskRule 'could not perform the requested operation' $false 'Bad' 'NOT CHECKED - sfc could not perform the check' 'Offline: check that the Target Windows is the right drive. Running Windows: try Safe Mode, or run "DISM: restore health" first.')
    (New-TaskRule 'must be an administrator' $false 'Bad' 'NOT CHECKED - sfc needs administrator rights' 'Run the tool as administrator.')
)
$DismError = New-TaskRule '^Error:\s*\S+' $false 'Bad' 'FAILED - DISM stopped with an error' 'The error is quoted above. dism.log (Windows\Logs\DISM) has the details.'
$TaskRules = @{
    'sfc' = $SfcCommon + @(
        (New-TaskRule 'found corrupt files and successfully repaired them' $true 'Good' 'CORRUPTION DETECTED - FIX WORKED (all corrupt files were repaired)' 'Restart Windows so the repaired files are used.')
        (New-TaskRule 'found corrupt files but was unable to fix some of them' $true 'Bad' 'CORRUPTION DETECTED - FIX DID NOT WORK for some files' 'Run "DISM: restore health", restart, then run sfc again. CBS.log lists the files (lines tagged [SR]).')
        (New-TaskRule 'did not find any integrity violations' $true 'Good' 'NO CORRUPTION DETECTED' 'Nothing to do.')
    )
    'sfc-verify' = $SfcCommon + @(
        (New-TaskRule 'did not find any integrity violations' $true 'Good' 'NO CORRUPTION DETECTED' 'Nothing to do.')
        (New-TaskRule 'found integrity violations' $true 'Bad' 'CORRUPTION DETECTED (scan only - nothing was repaired)' 'Run "System file check and repair (sfc /scannow)". If it cannot fix everything, run "DISM: restore health" first.')
    )
    'dism-check' = @(
        $DismError
        (New-TaskRule 'No component store corruption detected' $true 'Good' 'NO CORRUPTION DETECTED' 'Nothing to do.')
        (New-TaskRule 'component store is repairable' $true 'Bad' 'CORRUPTION DETECTED - it can be repaired' 'Run "DISM: restore health", then "System file check and repair (sfc /scannow)".')
        (New-TaskRule 'component store cannot be repaired|not repairable' $true 'Bad' 'CORRUPTION DETECTED - it can NOT be repaired' 'DISM cannot fix this store. A repair install (in-place upgrade) or reset is usually needed.')
    )
    'dism-restore' = @(
        (New-TaskRule 'source files could not be found' $false 'Bad' 'FIX DID NOT WORK - DISM could not find the repair source files' 'Offline: DISM needs a matching install.wim / install.esd as /source. Running Windows: check the internet connection and Windows Update, or give a /source.')
        $DismError
        (New-TaskRule 'component store corruption was repaired' $true 'Good' 'CORRUPTION DETECTED - FIX WORKED (the component store was repaired)' 'Run "System file check and repair (sfc /scannow)" next, then restart.')
        (New-TaskRule 'restore operation completed successfully' $true 'Good' 'NO CORRUPTION LEFT - the restore operation completed' 'If system files were reported corrupt, run "System file check and repair (sfc /scannow)" now.')
    )
    'driver-list' = @(
        $DismError
        (New-TaskRule 'The operation completed successfully' $true 'Good' 'COMPLETED - the driver list is in the window' 'Use the "Published Name" (oemNN.inf) with "Drivers: remove one".')
    )
    'driver' = @(
        $DismError
        (New-TaskRule 'Failed to|could not be|Unable to' $false 'Bad' 'AT LEAST ONE DRIVER FAILED' 'Read the output for the driver that failed.')
        (New-TaskRule 'successfully installed|successfully removed|Driver package added successfully|Driver package deleted successfully|Added driver packages:\s*[1-9]|The operation completed successfully' $true 'Good' 'COMPLETED - the driver change worked' 'Restart the PC (or the target Windows) to use the change.')
        (New-TaskRule 'Added driver packages:\s*0' $false 'Bad' 'NO DRIVERS WERE ADDED' 'Check that the folder holds .inf drivers for this Windows version and processor type.')
    )
    'chkdsk-scan' = @(
        (New-TaskRule 'Cannot lock|Cannot open volume|Access denied|Access is denied' $false 'Bad' 'NOT CHECKED - chkdsk could not open the volume' 'Close programs using the drive, or run the check from WinPE.')
        (New-TaskRule 'found no problems' $true 'Good' 'NO PROBLEMS FOUND' 'Nothing to do.')
        (New-TaskRule 'must be fixed offline|found problems|found errors|errors found' $true 'Bad' 'PROBLEMS DETECTED in the file system' 'Run "Check disk and REPAIR (chkdsk /f)". On the system drive it runs at the next restart.')
    )
    'chkdsk-fix' = @(
        (New-TaskRule 'will be checked the next time the system restarts' $true 'Warn' 'SCHEDULED - the check and repair run at the next restart' 'Restart the PC. The result is then in Event Viewer > Application, source Wininit.')
        (New-TaskRule 'cannot run because the volume is in use' $false 'Warn' 'NOT RUN - the volume is in use and the check was not scheduled' 'Run it again and answer Y to schedule it for the next restart.')
        (New-TaskRule 'Cannot lock|Cannot open volume|Access denied|Access is denied' $false 'Bad' 'NOT RUN - chkdsk could not lock the volume' 'Close programs using the drive, or run the repair from WinPE.')
        (New-TaskRule 'could not be corrected|could not fix|unable to fix' $true 'Bad' 'PROBLEMS FOUND - FIX DID NOT WORK for all of them' 'Back up your data. Run chkdsk /f again; if it keeps failing the disk may be failing.')
        (New-TaskRule 'made corrections to the file system' $true 'Good' 'PROBLEMS FOUND - FIX WORKED (corrections were made)' 'Restart and run the read-only scan again to confirm.')
        (New-TaskRule 'found no problems' $true 'Good' 'NO PROBLEMS FOUND' 'Nothing to do.')
    )
    'bcdboot' = @(
        (New-TaskRule 'Boot files successfully created' $true 'Good' 'FIX WORKED - boot files were created' 'Restart and check that Windows starts.')
        (New-TaskRule 'Failure|BFSVC Error|Error' $false 'Bad' 'FIX DID NOT WORK - bcdboot failed' 'Check the boot partition and the Target Windows, then try again.')
    )
    'bootrec-scan' = @(
        (New-TaskRule 'Access is denied|Element not found|cannot find|cannot be found' $false 'Bad' 'FAILED - bootrec could not scan' 'Use "Rebuild boot files (bcdboot)" instead.')
        (New-TaskRule 'Total identified Windows installations:\s*0\b' $true 'Warn' 'NO WINDOWS INSTALLATIONS FOUND outside the boot menu' 'Installs already in the boot menu are not counted. Mount the Windows drive, or use bcdboot.')
        (New-TaskRule 'Total identified Windows installations:\s*[1-9]' $true 'Good' 'WINDOWS INSTALLATION(S) FOUND' 'Use "Rebuild BCD (bootrec /rebuildbcd)" to add them to the boot menu.')
    )
    'bootrec' = @(
        (New-TaskRule 'Access is denied|Element not found|cannot find|cannot be found|operation was canceled' $false 'Bad' 'FIX DID NOT WORK - bootrec reported an error' 'On UEFI PCs use "Rebuild boot files (bcdboot)" instead.')
        (New-TaskRule 'The operation completed successfully' $true 'Good' 'FIX WORKED - the operation completed successfully' 'Restart and check that Windows starts.')
    )
    # ---- Automation tasks (the scripts below print these messages themselves) ----
    'dism-cleanup' = @(
        $DismError
        (New-TaskRule 'The operation completed successfully' $true 'Good' 'COMPLETED - the component store was cleaned up' 'Nothing to do.')
    )
    'restorepoint' = @(
        (New-TaskRule 'Restore point FAILED|was NOT created' $false 'Bad' 'NO RESTORE POINT - creating it failed' 'Turn on System Protection for the system drive (System Properties > System Protection > Configure), or tick "Turn on System Protection" on the Automation tab.')
        (New-TaskRule 'Restore point created' $true 'Good' 'RESTORE POINT CREATED' 'Nothing to do. You can roll back with System Restore (rstrui).')
    )
    'winupdate' = @(
        (New-TaskRule 'Windows Update FAILED' $false 'Bad' 'FAILED - Windows Update could not run' 'Check that the Windows Update service is not disabled and that the PC is online, then try again.')
        (New-TaskRule 'updates installed, [1-9]\d* failed' $true 'Bad' 'SOME UPDATES FAILED' 'Restart and run Windows Update again. The failed update and its error code are in the output.' '' 'restart is required' ' - RESTART REQUIRED')
        (New-TaskRule 'updates installed, 0 failed' $true 'Good' 'UPDATES INSTALLED' 'Restart if the result says a restart is required.' '' 'restart is required' ' - RESTART REQUIRED')
        (New-TaskRule 'no updates are available' $true 'Good' 'UP TO DATE - no updates were available' 'Nothing to do.')
    )
    'winupdate-check' = @(
        (New-TaskRule 'Windows Update FAILED' $false 'Bad' 'FAILED - Windows Update could not run' 'Check that the Windows Update service is not disabled and that the PC is online, then try again.')
        (New-TaskRule 'update\(s\) are available' $true 'Warn' 'UPDATES AVAILABLE (not installed)' 'Queue "Windows Update: download and install updates" to install them.')
        (New-TaskRule 'no updates are available' $true 'Good' 'UP TO DATE - no updates are available' 'Nothing to do.')
    )
    'winget' = @(
        (New-TaskRule 'winget is not available' $false 'Bad' 'NOT RUN - winget is not available' 'Install or update "App Installer" from the Microsoft Store, then try again.')
        (New-TaskRule 'Installer failed|failed with exit code|unexpected error|Installation failed' $true 'Bad' 'SOME UPGRADES FAILED' 'Read the output for the app that failed; close it if it is running and try again.' 'Successfully installed')
        (New-TaskRule 'Successfully installed' $true 'Good' 'APPS UPGRADED' 'Nothing to do.' 'Successfully installed')
        (New-TaskRule 'No available upgrade found|No newer package versions|No installed package found matching' $true 'Good' 'ALL APPS ARE UP TO DATE' 'Nothing to do.')
    )
    'winget-check' = @(
        (New-TaskRule 'winget is not available' $false 'Bad' 'NOT RUN - winget is not available' 'Install or update "App Installer" from the Microsoft Store, then try again.')
        (New-TaskRule '\d+ upgrades? available' $true 'Warn' 'APP UPGRADES AVAILABLE (not installed)' 'Queue "winget: upgrade all apps" to install them.')
        (New-TaskRule 'No available upgrade found|No newer package versions|No installed package found matching' $true 'Good' 'ALL APPS ARE UP TO DATE' 'Nothing to do.')
    )
    'defender' = @(
        (New-TaskRule 'Defender scan FAILED' $false 'Bad' 'NOT SCANNED - the Defender scan could not run' 'Another antivirus may have turned Microsoft Defender off; use that antivirus to scan instead.')
        (New-TaskRule '[1-9]\d* threat\(s\) found' $true 'Bad' 'THREATS FOUND' 'Open Windows Security > Virus and threat protection > Protection history and act on the threats.')
        (New-TaskRule 'no threats found' $true 'Good' 'NO THREATS FOUND' 'Nothing to do.')
    )
}

# Pass / fail for one finished task. Returns Ok, Tone, Find (headline), Next (advice), Quote (exact lines the tool printed).
function Get-TaskVerdict([string]$Kind, [string]$Text, $Rc) {
    # drop DISM-style progress bars "[=====  45.0%  ====]" that share a line with the result message
    $clean = ([string]$Text) -replace '\[[=\s]*\d+(\.\d+)?%[=\s]*\]\s*', ''
    $lines = @($clean -split "`r?`n" | ForEach-Object { $_.Trim() })
    # DISM-style "Error: 0x800f081f" + the explanation on the next line are always worth quoting
    $err = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^Error:\s*\S+') {
            $err += $lines[$i]
            for ($k = $i + 1; $k -lt $lines.Count; $k++) { if ($lines[$k]) { $err += $lines[$k]; break } }
            break
        }
    }
    # sfc and chkdsk wrap their own messages at about 70 characters: join each paragraph, then split it into
    # sentences, so a message is matched (and quoted) whole wherever the tool broke the line
    $sent = New-Object Collections.ArrayList     # each item: @(paragraph number, sentence)
    $pn = 0
    foreach ($para in ($clean -split '\r?\n[ \t]*\r?\n')) {
        $pn++
        $joined = ((($para -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' ')
        foreach ($s in ($joined -split '(?<=[.!?])\s+')) { if ($s.Trim()) { [void]$sent.Add(@($pn, $s.Trim())) } }
    }
    foreach ($r in @($TaskRules[$Kind])) {
        if (-not $r) { continue }
        for ($i = $sent.Count - 1; $i -ge 0; $i--) {          # newest output first: the result comes at the end
            if ($sent[$i][1] -notmatch $r.P) { continue }
            $hitText = $sent[$i][1]
            # a "sentence" that is really a table run together (winget prints no full stops): quote just the matching line
            if ($hitText.Length -gt 200) { $ln = @($lines | Where-Object { $_ -match $r.P }) | Select-Object -Last 1; if ($ln) { $hitText = $ln } }
            $q = @($err) + @($hitText)
            # the tool's follow-up sentence ("No further action is required.", "Details are included in the CBS.Log ...")
            if ($hitText -eq $sent[$i][1] -and $i + 1 -lt $sent.Count -and $sent[$i + 1][0] -eq $sent[$i][0] -and $sent[$i + 1][1].Length -le 160) { $q += $sent[$i + 1][1] }
            $q = @($q | Select-Object -Unique | ForEach-Object { if ($_.Length -gt 400) { $_.Substring(0, 400) + ' ...' } else { $_ } })
            $find = $r.Find
            if ($r.Count) { $find += ' ({0})' -f [regex]::Matches($clean, $r.Count).Count }
            if ($r.Also -and $clean -match $r.Also) { $find += $r.AlsoText }
            return [pscustomobject]@{ Ok = $r.Ok; Tone = $r.Tone; Find = $find; Next = $r.Next; Quote = $q; Matched = $true }
        }
    }
    $code = if ($null -eq $Rc -or "$Rc" -eq '') { 'unknown' } else { "$Rc" }
    if ("$Rc" -eq '0') {
        return [pscustomobject]@{ Ok = $true; Tone = 'Warn'; Find = 'FINISHED (exit code 0) - no known result message was found'; Matched = $false; Quote = @($err)
            Next = 'Read the full output. Result messages are matched in English; on another display language the summary can only use the exit code.' }
    }
    return [pscustomobject]@{ Ok = $false; Tone = 'Bad'; Find = "FAILED (exit code $code)"; Matched = $false; Quote = @($err)
        Next = 'Read the full output for the reason. Result messages are matched in English; on another display language the summary can only use the exit code.' }
}

# Console window for a task with "summary" on: runs the command exactly as before (its own progress display and
# Y/N prompts work), then reads back what was printed from the console screen buffer and writes it to a result
# file BEFORE "Press Enter". The main window's timer picks the file up and shows the summary.
# The template's own variables are named $Wst* so a task script (__CMD__) cannot overwrite them by accident.
$tplTask = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$WstRes = '__RESULT__'; $WstMark = '===== WinSuperTool: task output starts here ====='
try { $WstBuf = $Host.UI.RawUI.BufferSize; if ($WstBuf.Height -lt 9000) { $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size($WstBuf.Width, 9000) } } catch {}
Write-Host '__LINE__' -ForegroundColor Cyan
Write-Host $WstMark -ForegroundColor DarkGray
$WstY0 = $Host.UI.RawUI.CursorPosition.Y; $WstT0 = Get-Date
__CMD__
$WstRc = $LASTEXITCODE; $WstT1 = Get-Date
function Read-WstScreen {
    $raw = $Host.UI.RawUI; $w = $raw.BufferSize.Width; $h = $raw.BufferSize.Height; $end = $raw.CursorPosition.Y
    # the marker row is still there unless the buffer filled up and scrolled; then read the newest 3000 rows
    $top = if ($end -lt ($h - 1)) { [Math]::Max(0, $WstY0 - 1) } else { [Math]::Max(0, $end - 3000) }
    $cells = $raw.GetBufferContents((New-Object Management.Automation.Host.Rectangle(0, $top, ($w - 1), $end)))
    $sb = New-Object Text.StringBuilder; $row = New-Object char[] $w
    for ($y = 0; $y -le ($end - $top); $y++) {
        for ($x = 0; $x -lt $w; $x++) { $row[$x] = $cells[$y, $x].Character }
        $t = (New-Object string (,$row)).TrimEnd()
        [void]$sb.Append($t)
        if ($t.Length -lt $w) { [void]$sb.Append("`r`n") }     # a full row is a long line that wrapped: join it to the next
    }
    $all = $sb.ToString(); $i = $all.LastIndexOf($WstMark)
    if ($i -ge 0) { $all = $all.Substring($i + $WstMark.Length) }
    $all.Trim()
}
$WstTxt = ''; try { $WstTxt = Read-WstScreen } catch { $WstTxt = "(could not read the console window: $($_.Exception.Message))" }
$WstBody = "Rc=$WstRc`r`nStarted=$($WstT0.ToString('s'))`r`nEnded=$($WstT1.ToString('s'))`r`n-----`r`n$WstTxt"
try { [IO.File]::WriteAllText("$WstRes.tmp", $WstBody, (New-Object Text.UTF8Encoding $false)); Move-Item -LiteralPath "$WstRes.tmp" -Destination $WstRes -Force }
catch { Write-Host "Could not save the result for the summary: $($_.Exception.Message)" -ForegroundColor Red }
Write-Host ''; Write-Host ('Exit code: ' + $WstRc)
__CLOSE__
'@

$TaskDir = Join-Path $DataDir 'Task-Results'
$script:TaskWatch = New-Object Collections.ArrayList    # console tasks waiting for their summary
function Get-TaskFileBase([string]$name) {
    $slug = ($name -replace '[^A-Za-z0-9]+', '-').Trim('-'); if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
    [void][IO.Directory]::CreateDirectory($TaskDir)
    Join-Path $TaskDir ('{0:yyyyMMdd_HHmmss_fff}_{1}' -f (Get-Date), $slug)
}
# PowerShell call of one program with every argument single-quoted (no cmd.exe parsing)
function Get-ExeCall([string]$exe, [string[]]$argv) { "& '" + (Esc-Sq $exe) + "' " + ((@($argv) | ForEach-Object { "'" + (Esc-Sq ([string]$_)) + "'" }) -join ' ') }
# Opens a task window (Recovery tab with "summary" on, and every Automation task) and registers it for its summary.
#   $Call = PowerShell code that runs the task (it must leave $LASTEXITCODE set); $AutoItem = the Automation row, or $null
function Start-TaskWindow([string]$Name, [string]$Kind, [string]$Line, [string]$Call, [bool]$AutoClose = $false, $AutoItem = $null) {
    $resFile = (Get-TaskFileBase $Name) + '.txt'
    $close = if ($AutoClose) { "Write-Host 'This window closes in 15 seconds.' -ForegroundColor DarkGray; Start-Sleep -Seconds 15" } else { "Read-Host 'Press Enter to close this window'" }
    $cmd = $tplTask.Replace('__CMD__', $Call).Replace('__CLOSE__', $close).Replace('__TITLE__', (Esc-Sq ('TASK: ' + $Name))).Replace('__RESULT__', (Esc-Sq $resFile)).Replace('__LINE__', (Esc-Sq $Line))
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    # a classic console window (not Windows Terminal) keeps the whole output in its buffer, so all of it can be read back
    $conhost = Join-Path $env:windir 'System32\conhost.exe'
    if ([IO.File]::Exists($conhost)) { $p = Start-Process -FilePath $conhost -PassThru -ArgumentList ('"{0}" -NoProfile -ExecutionPolicy Bypass -EncodedCommand {1}' -f $PsExePath, $enc) }
    else { $p = Start-Process -FilePath $PsExePath -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc }
    [void]$script:Consoles.Add($p)
    [void]$script:TaskWatch.Add([pscustomobject]@{ Name = $Name; Kind = $Kind; Line = $Line; ResultFile = $resFile; OutFile = $null; Proc = $p; AutoItem = $AutoItem })
    return $resFile
}
function Read-TaskResult([string]$path) {
    $raw = [IO.File]::ReadAllText($path)
    $i = $raw.IndexOf("-----`r`n")
    $head = if ($i -ge 0) { $raw.Substring(0, $i) } else { '' }
    $r = [pscustomobject]@{ Rc = $null; Started = $null; Ended = $null; Output = $(if ($i -ge 0) { $raw.Substring($i + 7) } else { $raw }) }
    foreach ($l in ($head -split "`r`n")) {
        if ($l -match '^Rc=(-?\d+)') { $r.Rc = [int]$Matches[1] }
        elseif ($l -match '^Started=(.+)') { try { $r.Started = [datetime]$Matches[1] } catch {} }
        elseif ($l -match '^Ended=(.+)') { try { $r.Ended = [datetime]$Matches[1] } catch {} }
    }
    $r
}
function Show-TaskSummary($task, $res, $v, [bool]$Modeless = $false) {
    $green = [Drawing.Color]::FromArgb(30, 130, 60); $red = [Drawing.Color]::FromArgb(190, 35, 35); $orange = [Drawing.Color]::FromArgb(200, 110, 0)
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = "Task summary - $($task.Name)"; $f.Size = New-Object Drawing.Size(760, 540); $f.StartPosition = 'CenterScreen'; $f.Font = $form.Font
    $f.TopMost = $true; $f.MinimizeBox = $false; $f.MinimumSize = New-Object Drawing.Size(560, 420)
    $ban = New-Ctl 'Label' $f 0 0 760 46
    $ban.Anchor = 'Top,Left,Right'; $ban.TextAlign = 'MiddleCenter'; $ban.ForeColor = 'White'
    $ban.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold)
    if ($v.Ok) { $ban.Text = 'TASK PASSED - it ran to the end'; $ban.BackColor = $green } else { $ban.Text = 'TASK FAILED - it did not complete'; $ban.BackColor = $red }
    if (-not $v.Ok -and $v.Tone -eq 'Warn') { $ban.Text = 'TASK DID NOT RUN - action needed'; $ban.BackColor = $orange }
    $res1 = New-Ctl 'Label' $f 12 54 730 48 ('Result: ' + $v.Find)
    $res1.Anchor = 'Top,Left,Right'; $res1.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
    $res1.ForeColor = switch ($v.Tone) { 'Good' { $green } 'Bad' { $red } default { $orange } }
    $exe = ([string]$task.Line -split ' ')[0]
    $sb = New-Object Text.StringBuilder
    if (@($v.Quote).Count) {
        [void]$sb.AppendLine("What $exe said (its own words):")
        foreach ($q in @($v.Quote)) { [void]$sb.AppendLine('    "' + $q + '"') }
    } else { [void]$sb.AppendLine("$exe printed no result message the summary recognizes - see the full output.") }
    [void]$sb.AppendLine('')
    if ($v.Next) { [void]$sb.AppendLine('Next step:'); [void]$sb.AppendLine('    ' + $v.Next); [void]$sb.AppendLine('') }
    [void]$sb.AppendLine("Tool:       $($task.Name)")
    [void]$sb.AppendLine("Command:    $($task.Line)")
    if ($res.Started -and $res.Ended) { [void]$sb.AppendLine(('Ran:        {0:HH:mm:ss} - {1:HH:mm:ss}  ({2:hh\:mm\:ss})' -f $res.Started, $res.Ended, ($res.Ended - $res.Started))) }
    $rcTxt = "$($res.Rc)"; if ($res.Rc -is [int] -and ($res.Rc -lt 0 -or $res.Rc -gt 65535)) { $rcTxt += ('  (0x{0:X8})' -f $res.Rc) }
    [void]$sb.AppendLine("Exit code:  $rcTxt")
    if ($task.OutFile) { [void]$sb.AppendLine("Saved to:   $($task.OutFile)") }
    if (-not $v.Matched) { [void]$sb.AppendLine(''); [void]$sb.AppendLine('(The summary found no known message, so the result comes from the exit code.)') }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('BETA: this summary is new. If it gets a result wrong, please open a bug report with the full output.')
    $t = New-Ctl 'TextBox' $f 12 106 720 340
    $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Both'; $t.WordWrap = $true; $t.Anchor = 'Top,Bottom,Left,Right'
    $t.Font = New-Object Drawing.Font('Consolas', 9); $t.Text = $sb.ToString()
    $full = New-Ctl 'Button' $f 12 456 170 30 'Show full output'
    $full.Anchor = 'Bottom,Left'; $full.Tag = [string]$task.OutFile
    $full.Add_Click({ $p = [string]$this.Tag; if ($p -and [IO.File]::Exists($p)) { Start-Process -FilePath notepad.exe -ArgumentList ('"{0}"' -f $p) } else { Msg 'The output file is not there any more.' } })
    $cl = New-Ctl 'Button' $f 632 456 100 30 'Close'
    $cl.Anchor = 'Bottom,Right'; $cl.DialogResult = 'OK'; $f.CancelButton = $cl; $f.AcceptButton = $cl
    $t.Select(0, 0)
    if ($Modeless) {
        # Automation: the queue goes on while this window stays open. Kept on top in the bottom-right corner (the next task's
        # console opens top-left), staggered so several stay readable.
        $f.TopMost = $true; $f.StartPosition = 'Manual'
        $script:SumOffset = ([int]$script:SumOffset + 30) % 240
        $f.Tag = $script:SumOffset
        # on the monitor the tool is on, not always the main monitor (1.9 beta 5, found with two monitors)
        $wa = $(if ($form -and $form.IsHandleCreated) { [Windows.Forms.Screen]::FromControl($form).WorkingArea } else { [Windows.Forms.Screen]::PrimaryScreen.WorkingArea })
        $f.Location = New-Object Drawing.Point(([Math]::Max($wa.Left, $wa.Right - $f.Width - 8 - $script:SumOffset)), ([Math]::Max($wa.Top, $wa.Bottom - $f.Height - 8 - $script:SumOffset)))
        # placed again once shown: on a scaled display the window only reaches its final size when it loads, so the
        # position worked out above would push a 150 % window partly off the screen
        $f.Add_Shown({
            $wa2 = [Windows.Forms.Screen]::FromControl($this).WorkingArea; $off = [int]$this.Tag
            $this.Location = New-Object Drawing.Point(([Math]::Max($wa2.Left, $wa2.Right - $this.Width - 8 - $off)), ([Math]::Max($wa2.Top, $wa2.Bottom - $this.Height - 8 - $off)))
        })
        $f.Show($form); $f.Activate()
        return
    }
    [void]$f.ShowDialog($form)
    $f.Dispose()
}
# timer: a console task with "summary" on has finished (result file written) or its window was closed early
function Update-TaskWatch {
    foreach ($t in @($script:TaskWatch)) {
        if ([IO.File]::Exists($t.ResultFile)) {
            $script:TaskWatch.Remove($t)
            $r = Read-TaskResult $t.ResultFile
            $t.OutFile = $t.ResultFile
            $v = Get-TaskVerdict $t.Kind $r.Output $r.Rc
            Log ('RESULT: {0} - {1} (exit code {2}). Output: {3}' -f $t.Name, $v.Find, $r.Rc, $t.ResultFile)
            if ($t.AutoItem) { Complete-AutoTask $t $r $v; return }
            $script:InSummary = $true
            try { Show-TaskSummary $t $r $v } finally { $script:InSummary = $false }
            return      # one summary per tick; the next one (if any) shows on a later tick
        }
        if ($t.Proc -and $t.Proc.HasExited -and -not [IO.File]::Exists($t.ResultFile)) {
            $script:TaskWatch.Remove($t)
            Log "RESULT: $($t.Name) - the window was closed before the task finished; no summary."
            if ($t.AutoItem) {
                $v = [pscustomobject]@{ Ok = $false; Tone = 'Bad'; Find = 'NOT FINISHED - its window was closed before the task ended'; Next = 'Run the task again and leave its window open.'; Quote = @(); Matched = $false }
                Complete-AutoTask $t ([pscustomobject]@{ Rc = $null; Started = $null; Ended = (Get-Date); Output = '' }) $v
                return
            }
            $script:InSummary = $true
            try { Msg "The window for '$($t.Name)' was closed before the task finished, so there is no summary." 'Task summary' 'Warning' } finally { $script:InSummary = $false }
            return
        }
    }
}
# BETA: live monitor windows for the logs a Recovery task writes (names from $MonItems)
function Start-TaskMonitors($tool) {
    $n = 0
    foreach ($name in @($tool.Logs)) {
        if (-not $name) { continue }
        $item = $MonItems | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($item -and $item.Type -eq 'Evt' -and $EvtLogNames.Count -and $EvtLogNames -notcontains $item.Target) { Log "Not monitored (this event log is not on this PC): $($item.Target)"; continue }
        if ($item) { Start-Monitor $item 20; $n++; Log "Monitoring for $($tool.Name): $($item.Target)" }
    }
    return $n
}

# =====================================================================
#  BETA: easy-to-read info window (System Info tab, Automation summary)
# =====================================================================
# Blocks: InfoH = heading, InfoKV = "key: value" row (value may have several lines), InfoT = a line of text.
# C (colour) = Good / Bad / Warn / '' for the value or text.
function InfoH([string]$t) { [pscustomobject]@{ K = 'H'; Key = ''; T = $t; C = '' } }
function InfoKV([string]$k, $v, [string]$c = '') { [pscustomobject]@{ K = 'KV'; Key = $k; T = ((@($v) | ForEach-Object { [string]$_ }) -join "`n"); C = $c } }
function InfoT([string]$t, [string]$c = '') { [pscustomobject]@{ K = 'T'; Key = ''; T = $t; C = $c } }
function Get-InfoKeyWidth($blocks) { $w = 8; foreach ($b in $blocks) { if ($b.K -eq 'KV' -and $b.Key.Length -gt $w) { $w = $b.Key.Length } }; [Math]::Min($w, 30) }
function Format-InfoText($blocks, [string]$title = '', [string]$note = '') {
    $w = Get-InfoKeyWidth $blocks; $sb = New-Object Text.StringBuilder
    if ($title) { [void]$sb.AppendLine($title); [void]$sb.AppendLine(('{0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date))) }
    if ($note) { [void]$sb.AppendLine($note) }
    foreach ($b in $blocks) {
        switch ($b.K) {
            'H'  { [void]$sb.AppendLine(''); [void]$sb.AppendLine($b.T); [void]$sb.AppendLine('-' * [Math]::Min(80, $b.T.Length)) }
            'KV' { $ls = @($b.T -split "`n"); [void]$sb.AppendLine('  ' + $b.Key.PadRight($w) + '  ' + $ls[0]); for ($i = 1; $i -lt $ls.Count; $i++) { [void]$sb.AppendLine((' ' * ($w + 4)) + $ls[$i]) } }
            default { [void]$sb.AppendLine('  ' + $b.T) }
        }
    }
    $sb.ToString()
}
function Show-Info([string]$title, $blocks, [string]$note = '', [bool]$OnTop = $false) {
    $blocks = @($blocks | Where-Object { $_ })
    $green = [Drawing.Color]::FromArgb(30, 130, 60); $red = [Drawing.Color]::FromArgb(190, 35, 35); $orange = [Drawing.Color]::FromArgb(190, 100, 0)
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = $title; $f.Size = New-Object Drawing.Size(900, 660); $f.StartPosition = 'CenterParent'; $f.Font = $form.Font; $f.MinimumSize = New-Object Drawing.Size(600, 400)
    $rt = New-Object Windows.Forms.RichTextBox
    $rt.Location = New-Object Drawing.Point(10, 10); $rt.Size = New-Object Drawing.Size(864, 562); $rt.Anchor = 'Top,Bottom,Left,Right'
    $rt.BackColor = [Drawing.Color]::White; $rt.DetectUrls = $false; $rt.WordWrap = $true; $rt.BorderStyle = 'FixedSingle'
    $f.Controls.Add($rt)
    $fH = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold); $fK = New-Object Drawing.Font('Consolas', 10)
    $fV = New-Object Drawing.Font('Consolas', 10, [Drawing.FontStyle]::Bold); $fN = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Italic)
    $cH = [Drawing.Color]::FromArgb(0, 70, 140); $cK = [Drawing.Color]::FromArgb(90, 90, 90); $cV = [Drawing.Color]::Black
    $add = { param($text, $font, $color) $rt.SelectionStart = $rt.TextLength; $rt.SelectionLength = 0; $rt.SelectionFont = $font; $rt.SelectionColor = $color; $rt.SelectedText = $text }
    $col = { param($c) switch ($c) { 'Good' { $green } 'Bad' { $red } 'Warn' { $orange } default { $cV } } }
    $w = Get-InfoKeyWidth $blocks
    if ($note) { & $add ($note + "`n") $fN ([Drawing.Color]::DimGray) }
    $first = $true
    foreach ($b in $blocks) {
        switch ($b.K) {
            'H'  { if (-not $first) { & $add "`n" $fK $cV }; & $add ($b.T + "`n") $fH $cH }
            'KV' {
                $ls = @($b.T -split "`n")
                & $add ('  ' + $b.Key.PadRight($w) + '  ') $fK $cK
                & $add ($ls[0] + "`n") $fV (& $col $b.C)
                for ($i = 1; $i -lt $ls.Count; $i++) { & $add ((' ' * ($w + 4)) + $ls[$i] + "`n") $fV (& $col $b.C) }
            }
            default { & $add ('  ' + $b.T + "`n") $fK (& $col $b.C) }
        }
        $first = $false
    }
    $rt.ReadOnly = $true; $rt.SelectionStart = 0; $rt.SelectionLength = 0
    $plain = Format-InfoText $blocks $title $note
    $bCopy = New-Ctl 'Button' $f 10 580 120 30 'Copy all'; $bCopy.Anchor = 'Bottom,Left'; $bCopy.Tag = $plain
    $bCopy.Add_Click({ try { [Windows.Forms.Clipboard]::SetText([string]$this.Tag) } catch { Msg "Could not copy: $($_.Exception.Message)" } })
    $bSave = New-Ctl 'Button' $f 138 580 120 30 'Save as...'; $bSave.Anchor = 'Bottom,Left'; $bSave.Tag = @($plain, $title)
    $bSave.Add_Click({
        $d = New-Object Windows.Forms.SaveFileDialog; $d.Filter = 'Text file (*.txt)|*.txt'; $d.InitialDirectory = $DataDir
        $d.FileName = (($this.Tag[1] -replace '[^A-Za-z0-9 _-]', '') -replace '\s+', '_') + ('_{0:yyyyMMdd_HHmm}.txt' -f (Get-Date))
        if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText($d.FileName, [string]$this.Tag[0]); Log "Saved: $($d.FileName)" }
    })
    $bClose = New-Ctl 'Button' $f 774 580 100 30 'Close'; $bClose.Anchor = 'Bottom,Right'; $bClose.DialogResult = 'OK'; $f.CancelButton = $bClose
    if ($OnTop) { $f.TopMost = $true; $f.StartPosition = 'CenterScreen' }     # above the task windows that are still counting down
    [void]$f.ShowDialog($form)
    $f.Dispose()
}
function Invoke-Busy([string]$what, [scriptblock]$do) {
    $old = $form.Cursor; $form.Cursor = [Windows.Forms.Cursors]::WaitCursor; $form.Refresh()
    Log "System info: $what"
    try { & $do } finally { $form.Cursor = $old }
}

# =====================================================================
#  BETA: 9. SYSTEM INFO
# =====================================================================
function Get-SafeCim([string]$class, [string]$filter = '', [string]$ns = 'root\cimv2') {
    try { if ($filter) { @(Get-CimInstance -Namespace $ns -ClassName $class -Filter $filter -ErrorAction Stop) } else { @(Get-CimInstance -Namespace $ns -ClassName $class -ErrorAction Stop) } } catch { @() }
}
function Format-Mac([string]$m) { if (-not $m) { return '' }; $h = ($m -replace '[^0-9A-Fa-f]', '').ToUpper(); if ($h.Length -ne 12) { return $m }; ($h -split '(..)' | Where-Object { $_ }) -join ':' }
function Format-CimDate($d) { if ($d -is [datetime]) { return $d.ToString('yyyy-MM-dd') }; if ($d -match '^(\d{4})(\d{2})(\d{2})') { return "$($Matches[1])-$($Matches[2])-$($Matches[3])" }; [string]$d }
function ConvertTo-SubnetMask([int]$len) {
    $bits = ('1' * [Math]::Max(0, [Math]::Min(32, $len))).PadRight(32, '0')
    (0..3 | ForEach-Object { [Convert]::ToInt32($bits.Substring($_ * 8, 8), 2) }) -join '.'
}
# Windows product key stored in the registry (DigitalProductId). With a digital license this is often a generic key.
function ConvertFrom-DigitalProductId([byte[]]$id) {
    if (-not $id -or $id.Length -lt 67) { return '' }
    $key = [byte[]]$id[52..66]
    $isWin8 = [int]([Math]::Floor($key[14] / 6)) -band 1       # integer division (PowerShell's / keeps the fraction)
    $key[14] = [byte](($key[14] -band 0xF7) -bor (($isWin8 -band 2) * 4))
    $chars = 'BCDFGHJKMPQRTVWXY2346789'; $out = ''; $last = 0
    for ($i = 24; $i -ge 0; $i--) {
        $cur = 0
        for ($j = 14; $j -ge 0; $j--) { $cur = $cur * 256 + $key[$j]; $key[$j] = [byte][Math]::Floor($cur / 24); $cur = $cur % 24 }
        $out = $chars[$cur] + $out; $last = $cur
    }
    if ($isWin8) { $s = $out.Substring(1); $out = $s.Substring(0, $last) + 'N' + $s.Substring($last) }
    ($out.Substring(0, 25) -split '(.{5})' | Where-Object { $_ }) -join '-'
}

# ---- A1 Wi-Fi networks and passwords ----
function Get-WifiInfo {
    $b = New-Object Collections.ArrayList
    # (1.9 beta 5) every note gets a heading: in "Everything in one report" a note without one read as part of the Bluetooth part above it
    if (-not (Get-Command netsh.exe -ErrorAction SilentlyContinue)) { [void]$b.Add((InfoH 'Wi-Fi')); [void]$b.Add((InfoT 'netsh is not available here, so Wi-Fi networks cannot be read.' 'Warn')); return $b }
    $svc = Get-Service WlanSvc -ErrorAction SilentlyContinue
    if (-not $svc) { [void]$b.Add((InfoH 'Wi-Fi')); [void]$b.Add((InfoT 'This PC has no Wi-Fi service (WLAN AutoConfig is not installed), so there are no Wi-Fi networks to show.' 'Warn')); return $b }
    if ($svc.Status -ne 'Running') { [void]$b.Add((InfoH 'Wi-Fi service')); [void]$b.Add((InfoT 'The WLAN AutoConfig service is not running. Saved networks are shown if Windows can still read them.' 'Warn')) }
    $ifText = (& netsh.exe wlan show interfaces 2>$null) -join "`n"
    $connected = @([regex]::Matches($ifText, '(?m)^\s*SSID\s*:\s*(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
    $tmp = Join-Path $env:windir ('Temp\wst-wifi-' + [guid]::NewGuid().ToString('N'))
    $nets = @()
    try {
        [void][IO.Directory]::CreateDirectory($tmp)
        # the export writes the passwords in plain text: it goes to an admin-only folder and is deleted right after reading
        $null = & netsh.exe wlan export profile key=clear "folder=$tmp" 2>&1
        foreach ($f in @(Get-ChildItem -LiteralPath $tmp -Filter *.xml -ErrorAction SilentlyContinue)) {
            try {
                [xml]$x = [IO.File]::ReadAllText($f.FullName)
                $p = $x.WLANProfile; $sec = $p.MSM.security
                $ssid = [string]$p.SSIDConfig.SSID.name; if (-not $ssid) { $ssid = [string]$p.name }
                $auth = [string]$sec.authEncryption.authentication; $enc = [string]$sec.authEncryption.encryption
                $pw = [string]$sec.sharedKey.keyMaterial
                if (-not $pw) {
                    $pw = if ($auth -eq 'open') { '(none - open network)' }
                          elseif ([string]$sec.authEncryption.useOneX -eq 'true') { '(no shared password - signs in with a user account or certificate)' }
                          else { '(not stored)' }
                }
                $nets += [pscustomobject]@{ Ssid = $ssid; Profile = [string]$p.name; Pw = $pw; Auth = $auth; Enc = $enc; Mode = [string]$p.connectionMode; Now = ($connected -contains $ssid) }
            } catch {}
        }
    } finally { try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Stop } catch {} }
    $nets = @($nets | Sort-Object @{ e = { -not $_.Now } }, Ssid)
    [void]$b.Add((InfoH ('Saved Wi-Fi networks ({0})' -f $nets.Count)))
    if (-not $nets.Count) { [void]$b.Add((InfoT 'No saved Wi-Fi networks were found on this PC.')) }
    foreach ($n in $nets) {
        [void]$b.Add((InfoKV 'Network' ($n.Ssid + $(if ($n.Now) { '   <- CONNECTED NOW' } else { '' })) $(if ($n.Now) { 'Good' } else { '' })))
        [void]$b.Add((InfoKV '  Password' $n.Pw))
        [void]$b.Add((InfoKV '  Security' ("$($n.Auth) / $($n.Enc)")))
        [void]$b.Add((InfoKV '  Connects' $(if ($n.Mode -eq 'auto') { 'automatically' } else { 'manually' })))
        if ($n.Profile -and $n.Profile -ne $n.Ssid) { [void]$b.Add((InfoKV '  Profile name' $n.Profile)) }
    }
    [void]$b.Add((InfoH 'Wi-Fi networks in range now'))
    $inRange = @(& netsh.exe wlan show networks 2>$null | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -match '^SSID \d+\s*:' -or $_ -match '^\s+\S' })
    if ($inRange.Count) { foreach ($l in $inRange) { [void]$b.Add((InfoT $l.Trim())) } } else { [void]$b.Add((InfoT 'None found (no Wi-Fi adapter, Wi-Fi is off, or no networks nearby).')) }
    return $b
}

# ---- A2 Windows version and keys ----
function Get-WindowsInfo {
    $b = New-Object Collections.ArrayList
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = 0; [void][int]::TryParse([string]$cv.CurrentBuild, [ref]$build)
    $name = [string]$cv.ProductName; if ($build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }   # Windows 11 still says "Windows 10" here
    $rel = if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }
    $maj = if ($null -ne $cv.CurrentMajorVersionNumber) { "$($cv.CurrentMajorVersionNumber).$($cv.CurrentMinorVersionNumber)" } else { $cv.CurrentVersion }
    [void]$b.Add((InfoH 'Windows'))
    [void]$b.Add((InfoKV 'Edition' $name))
    [void]$b.Add((InfoKV 'Release' $rel))
    [void]$b.Add((InfoKV 'Full version' ("$maj.$build.$($cv.UBR)")))
    [void]$b.Add((InfoKV 'Build' ("$build.$($cv.UBR)")))
    [void]$b.Add((InfoKV 'Edition ID' $cv.EditionID))
    [void]$b.Add((InfoKV 'Installation type' $cv.InstallationType))
    [void]$b.Add((InfoKV 'Architecture' $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' })))
    if ($cv.InstallDate) { [void]$b.Add((InfoKV 'Installed on' ([DateTimeOffset]::FromUnixTimeSeconds([long]$cv.InstallDate).LocalDateTime.ToString('yyyy-MM-dd HH:mm')))) }
    [void]$b.Add((InfoKV 'Build lab' $cv.BuildLabEx))
    if ($IsWinPE) { [void]$b.Add((InfoT 'NOTE: this is the WinPE system you booted, not an installed Windows.' 'Warn')) }

    [void]$b.Add((InfoH 'Product keys'))
    $k = ''; try { $k = ConvertFrom-DigitalProductId ([byte[]]$cv.DigitalProductId) } catch {}
    [void]$b.Add((InfoKV 'Installed key' $(if ($k) { $k } else { '(not readable)' })))
    $sppKey = ''; try { $sppKey = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -ErrorAction Stop).BackupProductKeyDefault } catch {}
    if ($sppKey) { [void]$b.Add((InfoKV 'Backup key (licensing)' $sppKey)) }
    $sls = Get-SafeCim 'SoftwareLicensingService' | Select-Object -First 1
    $oa3 = if ($sls) { [string]$sls.OA3xOriginalProductKey } else { '' }
    [void]$b.Add((InfoKV 'Motherboard (firmware) key' $(if ($oa3) { $oa3 } else { 'none - the BIOS / UEFI has no Windows key built in' }) $(if ($oa3) { '' } else { 'Warn' })))
    if ($sls -and $sls.OA3xOriginalProductKeyDescription) { [void]$b.Add((InfoKV 'Motherboard key is for' $sls.OA3xOriginalProductKeyDescription)) }
    [void]$b.Add((InfoT 'With a digital license the installed key is often a generic key; activation is then tied to the hardware or Microsoft account.'))

    [void]$b.Add((InfoH 'Activation'))
    $lp = Get-SafeCim 'SoftwareLicensingProduct' "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
    if ($lp) {
        $st = @('Not activated', 'ACTIVATED', 'Grace period (out of box)', 'Grace period (hardware changed)', 'Grace period (not genuine)', 'Notification mode - not activated', 'Extended grace period')[[int]$lp.LicenseStatus]
        [void]$b.Add((InfoKV 'Status' $st $(if ([int]$lp.LicenseStatus -eq 1) { 'Good' } else { 'Bad' })))
        $ch = if ($lp.ProductKeyChannel) { $lp.ProductKeyChannel } else { $lp.Description }
        [void]$b.Add((InfoKV 'License channel' $ch))
        [void]$b.Add((InfoKV 'Active key ends in' $lp.PartialProductKey))
        [void]$b.Add((InfoKV 'License name' $lp.Name))
    } else { [void]$b.Add((InfoT 'The activation status could not be read.' 'Warn')) }

    [void]$b.Add((InfoH 'PC, motherboard and firmware'))
    $cs = Get-SafeCim 'Win32_ComputerSystem' | Select-Object -First 1
    $bb = Get-SafeCim 'Win32_BaseBoard' | Select-Object -First 1
    $bios = Get-SafeCim 'Win32_BIOS' | Select-Object -First 1
    if ($cs) { [void]$b.Add((InfoKV 'PC maker / model' ("$($cs.Manufacturer) $($cs.Model)".Trim()))) }
    if ($bb) { [void]$b.Add((InfoKV 'Motherboard' ("$($bb.Manufacturer) $($bb.Product)".Trim()))) }
    if ($bios) { [void]$b.Add((InfoKV 'BIOS / UEFI version' ("$($bios.SMBIOSBIOSVersion)  ($(Format-CimDate $bios.ReleaseDate))"))) }
    $fw = Get-FirmwareType; [void]$b.Add((InfoKV 'Boot mode' $(if ($fw) { $fw } else { 'unknown' })))
    $sb = 'unknown'; try { $sb = if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'On' } else { 'Off' } } catch { if ($fw -eq 'BIOS') { $sb = 'not supported (legacy BIOS boot)' } }
    [void]$b.Add((InfoKV 'Secure Boot' $sb))
    return $b
}

# ---- A3 Network connections ----
function Get-NetInfo {
    $b = New-Object Collections.ArrayList
    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
        [void]$b.Add((InfoT 'The network PowerShell commands are not available here (WinPE?). This is the output of ipconfig /all:' 'Warn'))
        foreach ($l in @(& ipconfig.exe /all)) { if ($l.Trim()) { [void]$b.Add((InfoT $l.TrimEnd())) } }
        return $b
    }
    $ads = @(Get-NetAdapter -ErrorAction SilentlyContinue)
    $cfg = @{}; foreach ($c in (Get-SafeCim 'Win32_NetworkAdapterConfiguration')) { $cfg[[int]$c.InterfaceIndex] = $c }
    $metric = @{}
    foreach ($r in @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
        $im = 0; try { $im = (Get-NetIPInterface -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric } catch {}
        $m = [int]$r.RouteMetric + [int]$im
        if (-not $metric.ContainsKey([int]$r.ifIndex) -or $m -lt $metric[[int]$r.ifIndex]) { $metric[[int]$r.ifIndex] = $m }
    }
    # Wi-Fi details per interface, as netsh prints them
    $wl = @{}; $cur = $null
    foreach ($l in @(& netsh.exe wlan show interfaces 2>$null)) {
        if ($l -match '^\s*Name\s*:\s*(.+?)\s*$') { $cur = $Matches[1]; $wl[$cur] = New-Object Collections.ArrayList; continue }
        if ($cur -and $l -match '^\s*([^:]+?)\s*:\s*(.+?)\s*$') { [void]$wl[$cur].Add(@($Matches[1], $Matches[2])) }
    }
    $sorted = @($ads | Sort-Object @{ e = { if ($_.Status -eq 'Up') { 0 } else { 1 } } }, @{ e = { if ($metric.ContainsKey([int]$_.ifIndex)) { $metric[[int]$_.ifIndex] } else { 99999 } } }, ifIndex)
    $up = @($sorted | Where-Object { $_.Status -eq 'Up' })
    $inet = $sorted | Where-Object { $_.Status -eq 'Up' -and $metric.ContainsKey([int]$_.ifIndex) } | Select-Object -First 1
    [void]$b.Add((InfoH 'Network summary'))
    [void]$b.Add((InfoKV 'Adapters' ('{0} in total, {1} connected' -f $sorted.Count, $up.Count)))
    [void]$b.Add((InfoKV 'Internet goes through' $(if ($inet) { "$($inet.Name) ($($inet.InterfaceDescription))" } else { 'no default route - this PC is not connected to a network with internet' }) $(if ($inet) { 'Good' } else { 'Warn' })))
    $n = 0
    foreach ($a in $sorted) {
        $n++
        $idx = [int]$a.ifIndex
        $desc = [string]$a.InterfaceDescription
        $type = if ($a.Virtual -or $desc -match 'Virtual|Hyper-V|VMware|VirtualBox Host|TAP-|VPN|WireGuard|Loopback|Tunnel') { 'Virtual / VPN adapter' }
                elseif ($a.PhysicalMediaType -match '802\.11') { 'Wi-Fi' } elseif ($a.PhysicalMediaType -match '802\.3') { 'Ethernet (wired)' }
                elseif ($a.PhysicalMediaType -match 'Blue') { 'Bluetooth' } elseif ($a.PhysicalMediaType -match 'WWAN|Mobile') { 'Mobile broadband' } else { [string]$a.MediaType }
        $state = switch ([string]$a.Status) { 'Up' { 'CONNECTED' } 'Disconnected' { 'not connected (cable unplugged / not joined)' } 'Disabled' { 'DISABLED' } default { [string]$a.Status } }
        $tag = if ($inet -and $a.ifIndex -eq $inet.ifIndex) { '   (used for internet)' } else { '' }
        [void]$b.Add((InfoH ("{0}. {1} - {2}{3}" -f $n, $a.Name, $type, $tag)))
        [void]$b.Add((InfoKV 'Status' $state $(if ($a.Status -eq 'Up') { 'Good' } elseif ($a.Status -eq 'Disabled') { 'Warn' } else { '' })))
        [void]$b.Add((InfoKV 'Adapter' $desc))
        [void]$b.Add((InfoKV 'MAC address' (Format-Mac $a.MacAddress)))
        if ($a.Status -eq 'Up') { [void]$b.Add((InfoKV 'Link speed' $a.LinkSpeed)) }
        $dv = if ($a.DriverVersion) { $a.DriverVersion } else { $a.DriverVersionString }
        if ($dv) { [void]$b.Add((InfoKV 'Driver' ("$dv  ($(Format-CimDate $a.DriverDate))  $($a.DriverProvider)".Trim()))) }
        if ($a.Status -ne 'Up') { continue }
        $v4 = @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        [void]$b.Add((InfoKV 'IPv4 address' $(if ($v4.Count) { @($v4 | ForEach-Object { "$($_.IPAddress) / $($_.PrefixLength)  (subnet mask $(ConvertTo-SubnetMask $_.PrefixLength), $($_.PrefixOrigin))" }) } else { '(none)' })))
        $v6 = @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv6 -ErrorAction SilentlyContinue)
        if ($v6.Count) { [void]$b.Add((InfoKV 'IPv6 address' @($v6 | ForEach-Object { "$($_.IPAddress)  ($(if ($_.IPAddress -like 'fe80*') { 'link-local' } else { [string]$_.SuffixOrigin }))" }))) }
        $c = $cfg[$idx]
        if ($c -and $c.DefaultIPGateway) { [void]$b.Add((InfoKV 'Default gateway' @($c.DefaultIPGateway))) }
        $dns = @(Get-DnsClientServerAddress -InterfaceIndex $idx -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        if ($dns.Count) { [void]$b.Add((InfoKV 'DNS servers' $dns)) }
        if ($c) {
            [void]$b.Add((InfoKV 'DHCP' $(if ($c.DHCPEnabled) { "on  (server $($c.DHCPServer))" } else { 'off - fixed (static) address' })))
            if ($c.DHCPEnabled -and $c.DHCPLeaseExpires) { [void]$b.Add((InfoKV 'DHCP lease' ("obtained $($c.DHCPLeaseObtained), expires $($c.DHCPLeaseExpires)"))) }
            if ($c.DNSDomain) { [void]$b.Add((InfoKV 'DNS suffix' $c.DNSDomain)) }
        }
        $prof = Get-NetConnectionProfile -InterfaceIndex $idx -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($prof) { [void]$b.Add((InfoKV 'Network' ("$($prof.Name)  ($($prof.NetworkCategory) network, IPv4: $($prof.IPv4Connectivity))"))) }
        if ($metric.ContainsKey($idx)) { [void]$b.Add((InfoKV 'Route metric' ("$($metric[$idx])  (lower = preferred)"))) }
        if ($wl.ContainsKey([string]$a.Name)) {
            foreach ($p in $wl[[string]$a.Name]) { if ($p[0] -notmatch '^(Description|GUID|Physical address|Interface type)$') { [void]$b.Add((InfoKV ('Wi-Fi ' + $p[0]) $p[1])) } }
        }
    }
    return $b
}

# ---- A4 Bluetooth ----
function Get-BtInfo {
    $b = New-Object Collections.ArrayList
    $dev = @(); try { $dev = @(Get-PnpDevice -Class Bluetooth -ErrorAction Stop) } catch {}
    $radioMac = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Bluetooth' } | ForEach-Object { Format-Mac $_.MacAddress })
    $radios = @($dev | Where-Object { $_.InstanceId -notmatch '^(BTHENUM|BTHLE|BTHLEDEVICE|BTHMODEM|BTHHFENUM|SWD)\\' -and $_.InstanceId -notmatch '^ROOT\\' })
    [void]$b.Add((InfoH 'Bluetooth adapter'))
    if (-not $dev.Count) { [void]$b.Add((InfoT 'No Bluetooth adapter or devices were found on this PC.' 'Warn')); return $b }
    if (-not $radios.Count) { [void]$b.Add((InfoT 'No Bluetooth radio found (only remembered devices).' 'Warn')) }
    foreach ($r in $radios) {
        [void]$b.Add((InfoKV 'Adapter' $r.FriendlyName))
        [void]$b.Add((InfoKV 'Status' $(if ($r.Status -eq 'OK') { 'working' } else { [string]$r.Status }) $(if ($r.Status -eq 'OK') { 'Good' } else { 'Warn' })))
        $ver = ''; try { $ver = (Get-PnpDeviceProperty -InstanceId $r.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction Stop).Data } catch {}
        if ($ver) { [void]$b.Add((InfoKV 'Driver version' $ver)) }
    }
    if ($radioMac.Count) { [void]$b.Add((InfoKV 'Adapter MAC address' $radioMac)) }
    # paired devices: BTHENUM\DEV_<address> (classic) and BTHLE\DEV_<address> (low energy)
    $paired = @{}
    foreach ($d in $dev) {
        if ($d.InstanceId -notmatch '^(BTHENUM|BTHLE)\\DEV_([0-9A-F]{12})') { continue }
        $addr = $Matches[2]; $kind = if ($Matches[1] -eq 'BTHLE') { 'Bluetooth LE' } else { 'Classic' }
        $conn = $null
        try { $conn = [bool](Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName '{83DA6326-97A6-4088-9453-A1923F573B29} 15' -ErrorAction Stop).Data } catch {}
        if ($paired.ContainsKey($addr)) { if ($conn) { $paired[$addr].Conn = $true }; continue }
        $paired[$addr] = [pscustomobject]@{ Name = $d.FriendlyName; Mac = (Format-Mac $addr); Kind = $kind; Conn = $conn; Present = ($d.Status -eq 'OK') }
    }
    # devices only remembered in the registry
    try {
        foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices' -ErrorAction Stop)) {
            $addr = $k.PSChildName.ToUpper(); if ($addr -notmatch '^[0-9A-F]{12}$' -or $paired.ContainsKey($addr)) { continue }
            $nm = ''; try { $raw = (Get-ItemProperty -LiteralPath $k.PSPath -Name Name -ErrorAction Stop).Name; $nm = [Text.Encoding]::UTF8.GetString([byte[]]$raw).Trim([char]0) } catch {}
            $paired[$addr] = [pscustomobject]@{ Name = $(if ($nm) { $nm } else { '(no name)' }); Mac = (Format-Mac $addr); Kind = 'Classic'; Conn = $false; Present = $false }
        }
    } catch {}
    $list = @($paired.Values | Sort-Object @{ e = { -not $_.Conn } }, Name)
    [void]$b.Add((InfoH ('Paired devices ({0}, {1} connected now)' -f $list.Count, @($list | Where-Object { $_.Conn }).Count)))
    if (-not $list.Count) { [void]$b.Add((InfoT 'No paired Bluetooth devices.')) }
    foreach ($p in $list) {
        $st = if ($p.Conn) { 'CONNECTED' } elseif ($null -eq $p.Conn) { 'paired (connection state unknown)' } else { 'paired, not connected' }
        [void]$b.Add((InfoKV $p.Name ("$st   |   MAC $($p.Mac)   |   $($p.Kind)") $(if ($p.Conn) { 'Good' } else { '' })))
    }
    return $b
}

# ---- A5 Video cards ----
# ---- Displays (1.9 beta 5): every monitor, not only the main one ----
# Win32_VideoController reports the main display's resolution only, and WmiMonitorID is empty on many PCs (and in
# virtual machines), so a second monitor did not appear at all. Windows' own display settings list every display
# with its real resolution and position; the scaling comes from the same call the Settings app uses.
$script:DispApiLoaded = $false
function Get-DisplayRaw {
    if (-not $script:DispApiLoaded) {
        try {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace WinSuperToolDisp {
  public static class Disp {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DD {
      public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
      public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DM {
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
      public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
      public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevicesW(string dev, int i, ref DD dd, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettingsW(string dev, int mode, ref DM dm);
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, IntPtr pathArr, ref uint modes, IntPtr modeArr, IntPtr topo);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(IntPtr p);
    static readonly int[] Steps = { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };
    // scaling in percent of a display such as \\.\DISPLAY2, 0 when Windows does not say
    static int Scale(string dev) {
      uint np, nm; if (GetDisplayConfigBufferSizes(2, out np, out nm) != 0) return 0;
      IntPtr pa = Marshal.AllocHGlobal((int)np * 72), ma = Marshal.AllocHGlobal((int)nm * 64), q = Marshal.AllocHGlobal(84);
      try {
        if (QueryDisplayConfig(2, ref np, pa, ref nm, ma, IntPtr.Zero) != 0) return 0;
        for (int i = 0; i < np; i++) {
          long l = Marshal.ReadInt64(pa, i * 72); int s = Marshal.ReadInt32(pa, i * 72 + 8);
          Marshal.WriteInt32(q, 0, 1); Marshal.WriteInt32(q, 4, 84); Marshal.WriteInt64(q, 8, l); Marshal.WriteInt32(q, 16, s);
          if (DisplayConfigGetDeviceInfo(q) != 0 || Marshal.PtrToStringUni(new IntPtr(q.ToInt64() + 20)) != dev) continue;
          Marshal.WriteInt32(q, 0, -3); Marshal.WriteInt32(q, 4, 32);
          if (DisplayConfigGetDeviceInfo(q) != 0) return 0;
          int k = -Marshal.ReadInt32(q, 20) + Marshal.ReadInt32(q, 24);
          return (k >= 0 && k < Steps.Length) ? Steps[k] : 0;
        }
        return 0;
      } catch { return 0; } finally { Marshal.FreeHGlobal(pa); Marshal.FreeHGlobal(ma); Marshal.FreeHGlobal(q); }
    }
    // one line per display that is part of the desktop: device|main(1/0)|x|y|width|height|Hz|scaling %|monitor name
    public static string[] List() {
      var o = new List<string>();
      for (int i = 0; i < 32; i++) {
        DD d = new DD(); d.cb = Marshal.SizeOf(typeof(DD)); if (!EnumDisplayDevicesW(null, i, ref d, 0)) break;
        if ((d.StateFlags & 1) == 0) continue;
        DM m = new DM(); m.dmSize = (short)Marshal.SizeOf(typeof(DM)); if (!EnumDisplaySettingsW(d.DeviceName, -1, ref m)) continue;
        DD mon = new DD(); mon.cb = Marshal.SizeOf(typeof(DD)); string mn = EnumDisplayDevicesW(d.DeviceName, 0, ref mon, 0) ? mon.DeviceString : "";
        o.Add(string.Join("|", new string[] { d.DeviceName, ((d.StateFlags & 4) != 0) ? "1" : "0", m.dmPositionX.ToString(), m.dmPositionY.ToString(), m.dmPelsWidth.ToString(), m.dmPelsHeight.ToString(), m.dmDisplayFrequency.ToString(), Scale(d.DeviceName).ToString(), mn }));
      }
      return o.ToArray();
    }
  }
}
'@
            $script:DispApiLoaded = $true
        } catch { return @() }
    }
    try { @([WinSuperToolDisp.Disp]::List()) } catch { @() }
}
# where a display is, seen from the main display (x, y, width, height of both)
function Get-DisplayPlace([int[]]$main, [int[]]$d) {
    if ($d[0] -eq $main[0] -and $d[1] -eq $main[1]) { return 'main display' }
    $w = @()
    if ($d[0] -ge $main[0] + $main[2]) { $w += 'right of' } elseif ($d[0] + $d[2] -le $main[0]) { $w += 'left of' }
    if ($d[1] -ge $main[1] + $main[3]) { $w += 'below' } elseif ($d[1] + $d[3] -le $main[1]) { $w += 'above' }
    if (-not $w.Count) { return 'overlaps the main display (duplicated?)' }
    ($w -join ' and ') + ' the main display'
}
function Get-DisplayRows {
    $raw = @(Get-DisplayRaw | ForEach-Object { $p = $_ -split '\|'; [pscustomobject]@{ Dev = $p[0]; Main = $p[1] -eq '1'; R = [int[]]@($p[2], $p[3], $p[4], $p[5]); Hz = [int]$p[6]; Scale = [int]$p[7]; Name = $p[8] } })
    $m = $raw | Where-Object Main | Select-Object -First 1
    foreach ($d in $raw) {
        $n = $d.Dev -replace '^\\\\\.\\DISPLAY', ''
        $v = '{0} x {1}' -f $d.R[2], $d.R[3]
        if ($d.Hz -gt 1) { $v += " at $($d.Hz) Hz" }
        if ($d.Scale) { $v += ", scaling $($d.Scale) %" }
        $lines = @($v)
        if ($m) { $lines += (Get-DisplayPlace $m.R $d.R) }
        if ($d.Name) { $lines += $d.Name }
        InfoKV "Display $n" $lines
    }
}
function Get-GpuInfo {
    $b = New-Object Collections.ArrayList
    $reg = @()
    # SilentlyContinue: the protected "Properties" subkey must not cancel the whole read
    try { $reg = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue }) } catch {}
    # @(): one WMI object is not an array, and .Count on a single CIM object is empty in PowerShell 5.1
    $vcs = @(Get-SafeCim 'Win32_VideoController')
    if (-not $vcs.Count) { [void]$b.Add((InfoT 'No video card information is available.' 'Warn')); return $b }
    $n = 0
    foreach ($v in $vcs) {
        $n++
        [void]$b.Add((InfoH ("{0}. {1}" -f $n, $v.Name)))
        [void]$b.Add((InfoKV 'Status' $(if ($v.Status -eq 'OK') { 'working' } else { [string]$v.Status }) $(if ($v.Status -eq 'OK') { 'Good' } else { 'Warn' })))
        $r = $reg | Where-Object { $_.DriverDesc -eq $v.Name } | Select-Object -First 1
        [void]$b.Add((InfoKV 'Driver version' $v.DriverVersion))
        [void]$b.Add((InfoKV 'Driver date' (Format-CimDate $v.DriverDate)))
        if ($r -and $r.ProviderName) { [void]$b.Add((InfoKV 'Driver made by' $r.ProviderName)) }
        $mem = $null
        if ($r) { $q = $r.'HardwareInformation.qwMemorySize'; if ($q) { $mem = [double]$q } else { $m2 = $r.'HardwareInformation.MemorySize'; if ($m2 -is [byte[]] -and $m2.Length -ge 4) { $mem = [double][BitConverter]::ToUInt32($m2, 0) } elseif ($m2) { $mem = [double]$m2 } } }
        if (-not $mem -and $v.AdapterRAM) { $mem = [double][uint32]$v.AdapterRAM }
        if ($mem) { [void]$b.Add((InfoKV 'Video memory' ('{0:N1} GB' -f ($mem / 1GB)))) }
        if ($v.CurrentHorizontalResolution) { [void]$b.Add((InfoKV 'Current display' ("$($v.CurrentHorizontalResolution) x $($v.CurrentVerticalResolution)" + $(if ([int]$v.CurrentRefreshRate -gt 1) { " at $($v.CurrentRefreshRate) Hz" } else { '' })))) }   # virtual adapters report 0 or 1 Hz
        if ($v.VideoProcessor) { [void]$b.Add((InfoKV 'Graphics chip' $v.VideoProcessor)) }
        if ($v.PNPDeviceID) { [void]$b.Add((InfoKV 'Device ID' (($v.PNPDeviceID -split '\\')[0..1] -join '\'))) }
    }
    $disp = @(Get-DisplayRows)
    if ($disp.Count) { [void]$b.Add((InfoH ('Displays ({0})' -f $disp.Count))); foreach ($r in $disp) { [void]$b.Add($r) } }
    $mons = @(Get-SafeCim 'WmiMonitorID' '' 'root\wmi')
    if ($mons.Count) {
        [void]$b.Add((InfoH ('Monitors ({0})' -f $mons.Count)))
        $dec = { param($a) (-join (@($a) | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })).Trim() }
        foreach ($m in $mons) {
            $nm = & $dec $m.UserFriendlyName; if (-not $nm) { $nm = '(no name)' }
            [void]$b.Add((InfoKV $nm ("maker $(& $dec $m.ManufacturerName), made $($m.YearOfManufacture)")))
        }
    }
    return $b
}

# ---- A6 Audio ----
$script:AudioApiLoaded = $false
function Get-AudioDefaultId([int]$flow, [int]$role) {
    if (-not $script:AudioApiLoaded) {
        try {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System; using System.Runtime.InteropServices;
namespace WinSuperToolAudio {
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
  }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr p, out IntPtr iface);
    [PreserveSig] int OpenPropertyStore(int access, out IntPtr store);
    [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
  }
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
  public static class Defaults {
    public static string Get(int flow, int role) {
      try {
        IMMDeviceEnumerator e = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
        IMMDevice d; if (e.GetDefaultAudioEndpoint(flow, role, out d) != 0 || d == null) return null;
        string id; if (d.GetId(out id) != 0) return null; return id;
      } catch { return null; }
    }
  }
}
'@
            $script:AudioApiLoaded = $true
        } catch { return $null }
    }
    try { [WinSuperToolAudio.Defaults]::Get($flow, $role) } catch { $null }
}
function Get-AudioEndpoints([string]$flow) {
    $base = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$flow"
    $out = @()
    foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        $st = 0; try { $st = [int]((Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop).DeviceState) -band 0xF } catch {}
        $p = Get-ItemProperty -LiteralPath (Join-Path $k.PSPath 'Properties') -ErrorAction SilentlyContinue
        $name = [string]$p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'; $card = [string]$p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
        $out += [pscustomobject]@{ Guid = $k.PSChildName.ToLower(); Name = $name; Card = $card; State = $st }
    }
    $out
}
function Get-AudioInfo {
    $b = New-Object Collections.ArrayList
    $flows = @(@('Render', 0, 'Output devices (speakers, headphones)'), @('Capture', 1, 'Input devices (microphones)'))
    foreach ($fl in $flows) {
        $eps = @(Get-AudioEndpoints $fl[0])
        $def = Get-AudioDefaultId $fl[1] 0; $com = Get-AudioDefaultId $fl[1] 2
        $act = @($eps | Where-Object { $_.State -eq 1 })
        [void]$b.Add((InfoH ('{0} - {1} active' -f $fl[2], $act.Count)))
        if (-not $act.Count) { [void]$b.Add((InfoT 'None active.')) }
        foreach ($e in ($act | Sort-Object Name)) {
            $isDef = $def -and $def.ToLower().EndsWith($e.Guid); $isCom = $com -and $com.ToLower().EndsWith($e.Guid)
            $mark = if ($isDef -and $isCom) { 'DEFAULT (also for calls)' } elseif ($isDef) { 'DEFAULT' } elseif ($isCom) { 'default for calls only' } else { 'available' }
            [void]$b.Add((InfoKV ("$($e.Name)") ("$mark   |   $($e.Card)") $(if ($isDef) { 'Good' } else { '' })))
        }
        if ($null -eq $def -and $act.Count) { [void]$b.Add((InfoT 'The default device could not be read on this PC.' 'Warn')) }
        $off = @($eps | Where-Object { $_.State -ne 1 -and $_.Name })
        if ($off.Count) {
            $why = @{ 2 = 'disabled'; 4 = 'not present'; 8 = 'unplugged' }
            [void]$b.Add((InfoKV 'Not active' @($off | Sort-Object Name | ForEach-Object { "$($_.Name) ($($_.Card)) - $(if ($why.ContainsKey($_.State)) { $why[$_.State] } else { 'inactive' })" })))
        }
    }
    [void]$b.Add((InfoH 'Sound hardware and drivers'))
    $drv = @(Get-SafeCim 'Win32_PnPSignedDriver' "DeviceClass='MEDIA'")
    if (-not $drv.Count) { $drv = @(Get-SafeCim 'Win32_SoundDevice' | ForEach-Object { [pscustomobject]@{ DeviceName = $_.Name; DriverVersion = ''; DriverDate = $null; DriverProviderName = $_.Manufacturer } }) }
    if (-not $drv.Count) { [void]$b.Add((InfoT 'No sound hardware found.' 'Warn')) }
    foreach ($d in ($drv | Sort-Object DeviceName)) {
        $v = if ($d.DriverVersion) { "driver $($d.DriverVersion)  ($(Format-CimDate $d.DriverDate))  by $($d.DriverProviderName)" } else { "by $($d.DriverProviderName)" }
        [void]$b.Add((InfoKV $d.DeviceName $v))
    }
    return $b
}

# ---- Windows tools launcher ----
# Exe = program (checked in System32 unless it is a URI), Arg = arguments, Need = file that must exist (edition-specific tools)
function New-WinTool($name, $exe, $arg = '', $tipText = '', $need = '') { [pscustomobject]@{ Name = $name; Exe = $exe; Arg = $arg; Tip = $tipText; Need = $need } }
$S32 = Join-Path $env:windir 'System32'
$WinTools = @(
    New-WinTool 'DirectX Diagnostic' 'dxdiag.exe' '' 'dxdiag: graphics, sound and DirectX details; can save a full report.'
    New-WinTool 'System Information' 'msinfo32.exe' '' 'msinfo32: full hardware, drivers and software summary.'
    New-WinTool 'Event Viewer' 'eventvwr.msc' '' 'All Windows event logs.'
    New-WinTool 'Advanced System Settings' 'SystemPropertiesAdvanced.exe' '' 'Performance, user profiles, startup and recovery, environment variables.'
    New-WinTool 'Internet Options' 'control.exe' 'inetcpl.cpl' 'inetcpl.cpl: proxy, security zones, reset Internet settings.' "$S32\inetcpl.cpl"
    New-WinTool 'Group Policy Editor' 'gpedit.msc' '' 'gpedit.msc (Pro, Enterprise and Education only).'
    New-WinTool 'Registry Editor' 'regedit.exe' '' 'regedit. Back up a key (File > Export) before changing it.' "$env:windir\regedit.exe"
    New-WinTool 'Device Manager' 'devmgmt.msc' '' 'Hardware, drivers and device errors.'
    New-WinTool 'Disk Management' 'diskmgmt.msc' '' 'Disks, partitions and drive letters.'
    New-WinTool 'Computer Management' 'compmgmt.msc' '' 'Event Viewer, shared folders, users, Device Manager and Disk Management in one window.'
    New-WinTool 'Services' 'services.msc' '' 'Start, stop and set the startup type of Windows services.'
    New-WinTool 'Task Manager' 'taskmgr.exe' '' 'Running apps, performance, startup apps.'
    New-WinTool 'Resource Monitor' 'resmon.exe' '' 'Live CPU, disk, network and memory use per process.'
    New-WinTool 'Performance Monitor' 'perfmon.exe' '' 'Performance counters and data collector sets.'
    New-WinTool 'Reliability Monitor' 'perfmon.exe' '/rel' 'History of crashes, failed updates and installs, day by day.'
    New-WinTool 'System Configuration' 'msconfig.exe' '' 'msconfig: boot options, Safe Mode, services at startup.'
    New-WinTool 'Task Scheduler' 'taskschd.msc' '' 'Scheduled tasks.'
    New-WinTool 'Control Panel' 'control.exe' '' 'The classic Control Panel.'
    New-WinTool 'Programs and Features' 'control.exe' 'appwiz.cpl' 'Uninstall or repair programs.' "$S32\appwiz.cpl"
    New-WinTool 'Network Connections' 'control.exe' 'ncpa.cpl' 'Network adapters: enable, disable, properties.' "$S32\ncpa.cpl"
    New-WinTool 'Sound Settings (classic)' 'control.exe' 'mmsys.cpl' 'Playback and recording devices, set the default.' "$S32\mmsys.cpl"
    New-WinTool 'Power Options' 'control.exe' 'powercfg.cpl' 'Power plans.' "$S32\powercfg.cpl"
    New-WinTool 'System Properties' 'control.exe' 'sysdm.cpl' 'Computer name, hardware, System Protection, remote settings.' "$S32\sysdm.cpl"
    New-WinTool 'Environment Variables' 'rundll32.exe' 'sysdm.cpl,EditEnvironmentVariables' 'Edit user and system environment variables.' "$S32\sysdm.cpl"
    New-WinTool 'Firewall (advanced)' 'wf.msc' '' 'Windows Defender Firewall with Advanced Security.'
    New-WinTool 'Windows Security' 'windowsdefender:' '' 'Virus protection, firewall, device security.'
    New-WinTool 'Local Users and Groups' 'lusrmgr.msc' '' 'lusrmgr.msc (Pro and higher).'
    New-WinTool 'Local Security Policy' 'secpol.msc' '' 'secpol.msc (Pro and higher).'
    New-WinTool 'Credential Manager' 'control.exe' '/name Microsoft.CredentialManager' 'Saved Windows and web passwords.'
    New-WinTool 'Certificates (user)' 'certmgr.msc' '' 'Personal and trusted certificates of the current user.'
    New-WinTool 'Shared Folders' 'fsmgmt.msc' '' 'Shares, open sessions and open files.'
    New-WinTool 'Print Management' 'printmanagement.msc' '' 'printmanagement.msc (Pro and higher).'
    New-WinTool 'Windows Features' 'optionalfeatures.exe' '' 'Turn Windows features on or off (.NET 3.5, SMB1, Hyper-V...).'
    New-WinTool 'Disk Cleanup' 'cleanmgr.exe' '' 'Free up disk space.'
    New-WinTool 'Optimize Drives' 'dfrgui.exe' '' 'Defragment / TRIM drives.'
    New-WinTool 'System Restore' 'rstrui.exe' '' 'Roll back to a restore point.'
    New-WinTool 'Memory Diagnostic' 'MdSched.exe' '' 'Tests the RAM at the next restart (asks first).'
    New-WinTool 'Windows Update' 'ms-settings:windowsupdate' '' 'Settings > Windows Update.'
    New-WinTool 'About this PC' 'ms-settings:about' '' 'Settings > System > About.'
    New-WinTool 'Windows version (winver)' 'winver.exe' '' 'The About Windows box with the exact build.'
    New-WinTool 'Command Prompt (admin)' 'cmd.exe' '' 'Opens as administrator (this tool runs elevated).'
    New-WinTool 'PowerShell (admin)' $PsExePath '-NoExit -NoProfile' 'Opens as administrator (this tool runs elevated).' $PsExePath
)
function Test-WinTool($t) {
    if ($t.Exe -match '^[a-z-]+:$|^ms-settings:') { return (-not $IsWinPE) }      # Settings / Windows Security pages
    if ($t.Need) { return [IO.File]::Exists($t.Need) }
    return ([IO.File]::Exists((Join-Path $S32 $t.Exe)) -or [IO.File]::Exists((Join-Path $env:windir $t.Exe)))
}
function Start-WinTool($t) {
    if (-not (Test-WinTool $t)) { Msg "$($t.Name) is not available on this PC (it is not part of this Windows edition, or this is WinPE)." 'Windows tools' 'Warning'; return }
    $exe = $t.Exe
    if ($exe -match '\.msc$') { $exe = Join-Path $S32 $exe }
    if ($t.Arg) { Start-Process -FilePath $exe -ArgumentList $t.Arg } else { Start-Process -FilePath $exe }
    Log "Opened: $($t.Name) ($($t.Exe) $($t.Arg))"
}

# =====================================================================
#  BETA: 10. AUTOMATION (a queue of up to 10 tasks, run one after another)
# =====================================================================
# Script tasks print their own result messages (matched by the rules in $TaskRules) and set $LASTEXITCODE.
$AutoScriptRestore = @'
$rc = 1
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$old = $null; try { $old = (Get-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -ErrorAction Stop).SystemRestorePointCreationFrequency } catch {}
try {
    if (__ENABLE__) { try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop; Write-Host "System Protection is on for $env:SystemDrive." } catch { Write-Host "Could not turn on System Protection: $($_.Exception.Message)" } }
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    # Windows allows only one restore point per 24 hours by default: allow this one, then put the setting back
    Set-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction Stop
    $desc = 'WinSuperTool ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Write-Host "Creating restore point '$desc' (this can take a minute)..."
    Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    $rp = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $desc })
    if ($rp.Count) { Write-Host ("Restore point created: {0} (number {1})." -f $desc, $rp[-1].SequenceNumber); $rc = 0 }
    else { Write-Host 'Restore point was NOT created. Is System Protection turned on for the system drive?' }
} catch { Write-Host "Restore point FAILED: $($_.Exception.Message)" }
finally {
    try { if ($null -eq $old) { Remove-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -ErrorAction Stop } else { Set-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction Stop } } catch {}
}
$global:LASTEXITCODE = $rc
'@
$AutoScriptWU = @'
$rc = 1
try {
    $ses = New-Object -ComObject Microsoft.Update.Session; $ses.ClientApplicationID = 'WinSuperTool'
    Write-Host 'Searching Windows Update (this can take several minutes)...'
    $wuFound = $ses.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $ups = @(); foreach ($u in $wuFound.Updates) { if (-not $u.InstallationBehavior.CanRequestUserInput) { $ups += $u } }
    if (-not $ups.Count) { Write-Host 'Windows Update: no updates are available. Windows is up to date.'; $rc = 0 }
    else {
        Write-Host ('Windows Update: {0} update(s) are available:' -f $ups.Count)
        foreach ($u in $ups) { Write-Host ('  - ' + $u.Title) }
        if (__INSTALL__) {
            $coll = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($u in $ups) { if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$coll.Add($u) }
            Write-Host ''; Write-Host 'Downloading...'
            $dl = $ses.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
            Write-Host 'Installing...'
            $ins = $ses.CreateUpdateInstaller(); $ins.Updates = $coll; $ir = $ins.Install()
            $ok = 0; $bad = 0
            for ($i = 0; $i -lt $coll.Count; $i++) {
                $r = $ir.GetUpdateResult($i)
                if ($r.ResultCode -eq 2 -or $r.ResultCode -eq 3) { $ok++; Write-Host ('  Installed: ' + $coll.Item($i).Title) }
                else { $bad++; Write-Host ('  FAILED (result {0}, 0x{1:X8}): {2}' -f $r.ResultCode, $r.HResult, $coll.Item($i).Title) }
            }
            Write-Host ''
            Write-Host ('Windows Update: {0} of {1} updates installed, {2} failed.' -f $ok, $coll.Count, $bad)
            if ($ir.RebootRequired) { Write-Host 'A restart is required to finish installing the updates.' }
            if ($bad -eq 0) { $rc = 0 }
        } else { $rc = 0 }
    }
} catch { Write-Host ('Windows Update FAILED: {0} (0x{1:X8})' -f $_.Exception.Message, $_.Exception.HResult) }
$global:LASTEXITCODE = $rc
'@
$AutoScriptWinget = @'
$wg = $null; try { $wg = (Get-Command winget.exe -ErrorAction Stop).Source } catch {}
if (-not $wg) { $c = @(Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime); if ($c.Count) { $wg = $c[-1].FullName } }
if (-not $wg) { Write-Host 'winget is not available for this account (the "App Installer" app is missing or too old).'; $global:LASTEXITCODE = 1 }
else {
    & $wg upgrade --all --accept-source-agreements --accept-package-agreements --silent
}
'@
$AutoScriptDefender = @'
$rc = 1
try {
    if (-not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) { throw 'the Microsoft Defender commands are not available on this PC' }
    Write-Host 'Updating Microsoft Defender definitions...'
    try { Update-MpSignature -ErrorAction Stop; Write-Host 'Definitions updated.' } catch { Write-Host "Definition update failed (the scan still runs): $($_.Exception.Message)" }
    $scanStart = Get-Date
    Write-Host 'Running a Microsoft Defender quick scan (several minutes)...'
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    $th = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $scanStart })
    if ($th.Count) {
        Write-Host ('Defender quick scan finished: {0} threat(s) found.' -f $th.Count)
        foreach ($d in $th) { $n = ''; try { $n = (Get-MpThreat -ThreatID $d.ThreatID -ErrorAction Stop).ThreatName } catch {}; Write-Host ('  - {0}  {1}' -f $n, (@($d.Resources) | Select-Object -First 1)) }
    } else { Write-Host 'Defender quick scan finished: no threats found.'; $rc = 0 }
} catch { Write-Host "Defender scan FAILED: $($_.Exception.Message)" }
$global:LASTEXITCODE = $rc
'@
# Catalog. Code: param($opt) -> @{ Call = PowerShell code; Line = what the summary shows as the command }
# Then: if the result (Find) matches If, the task Add is queued right after it (for "repair only if needed").
function New-AutoTask($id, $name, $kind, $help, $logs, [scriptblock]$code, $then = $null) { [pscustomobject]@{ Id = $id; Name = $name; Kind = $kind; Help = $help; Logs = @($logs); Code = $code; Then = $then } }
$CbsSr = 'CBS.log - SFC lines only ([SR])'
$AutoCatalog = @(
    New-AutoTask 'restore-point' 'Create a system restore point' 'restorepoint' 'Creates a restore point of the system drive, so the changes made by the next tasks can be rolled back with System Restore. Needs System Protection on for the system drive (tick the option below to turn it on).' @() { param($o) @{ Call = $AutoScriptRestore.Replace('__ENABLE__', $(if ($o.EnableSR) { '$true' } else { '$false' })); Line = 'Checkpoint-Computer (restore point)' } }
    New-AutoTask 'sfc-verify' 'SFC: scan only (sfc /verifyonly)' 'sfc-verify' 'Checks the protected system files for corruption without repairing anything.' @($CbsSr) { param($o) @{ Call = (Get-ExeCall 'sfc.exe' @('/verifyonly')); Line = 'sfc.exe /verifyonly' } }
    New-AutoTask 'sfc-verify-fix' 'SFC: scan, repair only if corruption is found' 'sfc-verify' 'Runs sfc /verifyonly. If it finds corruption, sfc /scannow is added right after it to repair the files.' @($CbsSr) { param($o) @{ Call = (Get-ExeCall 'sfc.exe' @('/verifyonly')); Line = 'sfc.exe /verifyonly' } } @{ If = '^CORRUPTION DETECTED'; Add = 'sfc-scannow'; Why = 'added because sfc found corruption' }
    New-AutoTask 'sfc-scannow' 'SFC: scan and repair (sfc /scannow)' 'sfc' 'Checks the protected system files and repairs the corrupt ones.' @($CbsSr) { param($o) @{ Call = (Get-ExeCall 'sfc.exe' @('/scannow')); Line = 'sfc.exe /scannow' } }
    New-AutoTask 'dism-check' 'DISM: check health (quick)' 'dism-check' 'Quick check (seconds): has the component store already been flagged as corrupt? Changes nothing.' @('dism.log') { param($o) @{ Call = (Get-ExeCall 'dism.exe' @('/online', '/cleanup-image', '/checkhealth')); Line = 'dism.exe /online /cleanup-image /checkhealth' } }
    New-AutoTask 'dism-scan' 'DISM: scan health (full scan)' 'dism-check' 'Full scan of the component store for corruption (several minutes). Repairs nothing.' @('dism.log', 'CBS.log (full)') { param($o) @{ Call = (Get-ExeCall 'dism.exe' @('/online', '/cleanup-image', '/scanhealth')); Line = 'dism.exe /online /cleanup-image /scanhealth' } }
    New-AutoTask 'dism-scan-fix' 'DISM: scan, repair only if corruption is found' 'dism-check' 'Runs DISM scan health. If it finds repairable corruption, DISM restore health is added right after it.' @('dism.log', 'CBS.log (full)') { param($o) @{ Call = (Get-ExeCall 'dism.exe' @('/online', '/cleanup-image', '/scanhealth')); Line = 'dism.exe /online /cleanup-image /scanhealth' } } @{ If = 'can be repaired'; Add = 'dism-restore'; Why = 'added because DISM found repairable corruption' }
    New-AutoTask 'dism-restore' 'DISM: restore health (repair)' 'dism-restore' 'Repairs the component store, downloading good files from Windows Update.' @('dism.log', 'CBS.log (full)') { param($o) @{ Call = (Get-ExeCall 'dism.exe' @('/online', '/cleanup-image', '/restorehealth')); Line = 'dism.exe /online /cleanup-image /restorehealth' } }
    New-AutoTask 'dism-cleanup' 'DISM: clean up the component store' 'dism-cleanup' 'Removes superseded versions of updated components (frees disk space). Old updates can no longer be uninstalled afterwards.' @('dism.log') { param($o) @{ Call = (Get-ExeCall 'dism.exe' @('/online', '/cleanup-image', '/startcomponentcleanup')); Line = 'dism.exe /online /cleanup-image /startcomponentcleanup' } }
    New-AutoTask 'chkdsk-scan' 'Check disk: read-only scan of the system drive' 'chkdsk-scan' 'chkdsk <system drive> /scan - checks the file system online without fixing anything. In WinPE: the drive of the Target Windows.' @() { param($o) @{ Call = (Get-ExeCall 'chkdsk.exe' @($env:SystemDrive, '/scan')); Line = "chkdsk.exe $env:SystemDrive /scan" } }
    New-AutoTask 'chkdsk-fix' 'Check disk and REPAIR (WinPE only: chkdsk /f)' 'chkdsk-fix' 'WinPE only: chkdsk <drive> /f on the Target Windows while it is not running - checks the file system and fixes the errors it finds, straight away. On the running Windows use the Recovery tab instead (it schedules the repair for the next restart).' @() { param($o) throw 'only for an offline Windows (WinPE)' }
    New-AutoTask 'winupdate-check' 'Windows Update: check for updates (list only)' 'winupdate-check' 'Lists the updates Windows Update offers, without installing them.' @('Event: WindowsUpdateClient/Operational') { param($o) @{ Call = $AutoScriptWU.Replace('__INSTALL__', '$false'); Line = 'Windows Update API: search' } }
    New-AutoTask 'winupdate' 'Windows Update: download and install updates' 'winupdate' 'Downloads and installs the updates Windows Update offers (not optional driver updates). Updates that need you to click something are skipped. Some need a restart.' @('Event: WindowsUpdateClient/Operational') { param($o) @{ Call = $AutoScriptWU.Replace('__INSTALL__', '$true'); Line = 'Windows Update API: search, download, install' } }
    New-AutoTask 'winget-check' 'winget: list available app upgrades' 'winget-check' 'winget upgrade - lists the installed apps that have a newer version. Changes nothing.' @() { param($o) @{ Call = $AutoScriptWinget.Replace('upgrade --all --accept-source-agreements --accept-package-agreements --silent', 'upgrade --accept-source-agreements'); Line = 'winget upgrade --accept-source-agreements' } }
    New-AutoTask 'winget' 'winget: upgrade all apps' 'winget' 'winget upgrade --all --silent - updates the installed apps winget knows about. Close the apps first; a running app can fail to update.' @() { param($o) @{ Call = $AutoScriptWinget; Line = 'winget upgrade --all --accept-source-agreements --accept-package-agreements --silent' } }
    New-AutoTask 'defender' 'Microsoft Defender: update + quick scan' 'defender' 'Updates the Microsoft Defender definitions, then runs a quick scan. Does not work when another antivirus has replaced Defender.' @('Windows Defender/Operational') { param($o) @{ Call = $AutoScriptDefender; Line = 'Update-MpSignature; Start-MpScan -ScanType QuickScan' } }
)
$AutoPresets = [ordered]@{
    'Health check (scans only, changes nothing)' = @('dism-check', 'sfc-verify', 'chkdsk-scan', 'winupdate-check', 'winget-check')
    'Repair Windows (restore point, DISM, SFC)'  = @('restore-point', 'dism-scan-fix', 'sfc-scannow', 'chkdsk-scan')
    'Update everything'                           = @('restore-point', 'winupdate', 'winget', 'defender')
    'Full maintenance'                            = @('restore-point', 'dism-scan-fix', 'sfc-verify-fix', 'winupdate', 'winget', 'defender', 'dism-cleanup')
    'Offline repair (WinPE)'                      = @('dism-check', 'dism-scan-fix', 'sfc-verify-fix', 'chkdsk-scan', 'chkdsk-fix')
}
# ---- offline Automation (1.9): in WinPE the queue works on the Target Windows, which is not running ----
# Only tasks that work on an offline Windows, with the same commands the Recovery tab uses for an offline install
# (sfc /offbootdir /offwindir, dism /image: ... /scratchdir, chkdsk on that drive). Restore point, Windows Update, winget
# and Defender need the running Windows.
$AutoOffline = @{
    'sfc-verify'     = { param($w) @{ Exe = 'sfc.exe'; Args = @('/verifyonly', "/offbootdir=$w\", "/offwindir=$w\Windows") } }
    'sfc-verify-fix' = { param($w) @{ Exe = 'sfc.exe'; Args = @('/verifyonly', "/offbootdir=$w\", "/offwindir=$w\Windows") } }
    'sfc-scannow'    = { param($w) @{ Exe = 'sfc.exe'; Args = @('/scannow', "/offbootdir=$w\", "/offwindir=$w\Windows") } }
    'dism-check'     = { param($w) @{ Exe = 'dism.exe'; Args = @("/image:$w\", '/cleanup-image', '/checkhealth') } }
    'dism-scan'      = { param($w) @{ Exe = 'dism.exe'; Args = @("/image:$w\", '/cleanup-image', '/scanhealth', "/scratchdir:$w\Windows\Temp") } }
    'dism-scan-fix'  = { param($w) @{ Exe = 'dism.exe'; Args = @("/image:$w\", '/cleanup-image', '/scanhealth', "/scratchdir:$w\Windows\Temp") } }
    'dism-restore'   = { param($w) @{ Exe = 'dism.exe'; Args = @("/image:$w\", '/cleanup-image', '/restorehealth', "/scratchdir:$w\Windows\Temp") } }
    'dism-cleanup'   = { param($w) @{ Exe = 'dism.exe'; Args = @("/image:$w\", '/cleanup-image', '/startcomponentcleanup', "/scratchdir:$w\Windows\Temp") } }
    'chkdsk-scan'    = { param($w) @{ Exe = 'chkdsk.exe'; Args = @($w, '/scan') } }
    'chkdsk-fix'     = { param($w) @{ Exe = 'chkdsk.exe'; Args = @($w, '/f') } }
}
$AutoOfflineOnly = @('chkdsk-fix')
# why a task cannot run here ('' = it can): in WinPE only the offline tasks, on a running Windows not the WinPE-only ones
function Get-AutoWhyNot([string]$id) {
    if ($IsWinPE) { if (-not $AutoOffline.ContainsKey($id)) { return 'needs the running Windows - it cannot run on an offline Windows from WinPE' } }
    elseif ($AutoOfflineOnly -contains $id) { return 'only for an offline Windows: start WinSuperTool in WinPE (on the running Windows use the Recovery tab)' }
    return ''
}
# the command of a task: the offline form when the run works on an offline Windows ($win = its drive)
function Get-AutoCode($c, $opt, [string]$win = '') {
    if ($win) { $w = $win.TrimEnd('\'); $x = & $AutoOffline[$c.Id] $w; return @{ Call = (Get-ExeCall $x.Exe $x.Args); Line = ('{0} {1}' -f $x.Exe, ($x.Args -join ' ')) } }
    return (& $c.Code $opt)
}
$AutoMax = 10
$AutoStateFile = Join-Path $DataDir 'automation.json'
$script:AutoQueue = New-Object Collections.ArrayList      # catalog ids, in order
$script:AutoRun = $null                                     # rows of the current / last run
$script:Auto = @{ Running = $false; StopReq = $false; Index = -1; Started = $null; Opt = $null; StopWhy = '' }
function Get-AutoCat([string]$id) { $AutoCatalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1 }
function Save-AutoState {
    try {
        $s = [ordered]@{ Queue = @($script:AutoQueue); Popups = $chkAutoPop.Checked; StopOnFail = $chkAutoStop.Checked; Monitor = $chkAutoMon.Checked; EnableSR = $chkAutoSR.Checked; Html = $chkAutoHtml.Checked }
        [IO.File]::WriteAllText($AutoStateFile, ($s | ConvertTo-Json -Depth 3))
    } catch {}
}
function Load-AutoState {
    try {
        if (-not [IO.File]::Exists($AutoStateFile)) { return }
        $s = [IO.File]::ReadAllText($AutoStateFile) | ConvertFrom-Json
        $script:AutoQueue.Clear()
        foreach ($id in @($s.Queue)) { if ((Get-AutoCat $id) -and $script:AutoQueue.Count -lt $AutoMax) { [void]$script:AutoQueue.Add([string]$id) } }
        $chkAutoPop.Checked = [bool]$s.Popups; $chkAutoStop.Checked = [bool]$s.StopOnFail; $chkAutoMon.Checked = [bool]$s.Monitor; $chkAutoSR.Checked = [bool]$s.EnableSR
        if ($null -ne $s.Html) { $chkAutoHtml.Checked = [bool]$s.Html }
    } catch {}
}
function Format-Dur($a, $b) { if (-not $a -or -not $b) { return '' }; $d = $b - $a; if ($d.TotalHours -ge 1) { $d.ToString('h\:mm\:ss') } else { $d.ToString('m\:ss') } }
function Update-AutoList {
    $lvAuto.BeginUpdate(); $lvAuto.Items.Clear()
    $green = [Drawing.Color]::FromArgb(30, 130, 60); $red = [Drawing.Color]::FromArgb(190, 35, 35); $orange = [Drawing.Color]::FromArgb(190, 100, 0)
    if ($script:AutoRun) {
        $i = 0
        foreach ($r in $script:AutoRun) {
            $i++
            $name = if ($r.Auto) { "   + $($r.Name)  ($($r.Why))" } else { $r.Name }
            $it = New-Object Windows.Forms.ListViewItem([string]$i)
            [void]$it.SubItems.Add($name); [void]$it.SubItems.Add($r.Status); [void]$it.SubItems.Add([string]$r.Find); [void]$it.SubItems.Add((Format-Dur $r.Started $(if ($r.Ended) { $r.Ended } elseif ($r.Started) { Get-Date } else { $null })))
            switch ($r.Status) { 'PASSED' { $it.ForeColor = $(if ($r.Tone -eq 'Bad') { $red } elseif ($r.Tone -eq 'Warn') { $orange } else { $green }) } 'FAILED' { $it.ForeColor = $red } 'NOT RUN' { $it.ForeColor = $orange } 'Running' { $it.ForeColor = [Drawing.Color]::FromArgb(0, 70, 140); $it.Font = New-Object Drawing.Font($lvAuto.Font, [Drawing.FontStyle]::Bold) } 'Skipped' { $it.ForeColor = [Drawing.Color]::Gray } }
            [void]$lvAuto.Items.Add($it)
        }
    } else {
        $i = 0
        foreach ($id in $script:AutoQueue) {
            $i++; $c = Get-AutoCat $id
            $it = New-Object Windows.Forms.ListViewItem([string]$i)
            [void]$it.SubItems.Add($c.Name); [void]$it.SubItems.Add('Waiting'); [void]$it.SubItems.Add(''); [void]$it.SubItems.Add('')
            [void]$lvAuto.Items.Add($it)
        }
    }
    $lvAuto.EndUpdate()
    $lblAutoCount.Text = '{0} of {1} tasks queued' -f $script:AutoQueue.Count, $AutoMax
}
function Set-AutoEditing([bool]$on) {
    foreach ($c in @($btnAutoAdd, $btnAutoUp, $btnAutoDown, $btnAutoRemove, $btnAutoClear, $btnAutoPreset, $cmbAutoPreset, $lstAutoCat, $chkAutoPop, $chkAutoStop, $chkAutoMon, $chkAutoSR, $chkAutoHtml)) { $c.Enabled = $on }
    $btnAutoStart.Enabled = $on; $btnAutoStopReq.Enabled = -not $on
}
function Start-AutoRun {
    if (-not $script:AutoQueue.Count) { Msg 'Add at least one task to the queue first.' 'Automation' 'Warning'; return }
    # WinPE: the queue works on the Target Windows (offline); only the tasks that can run on an offline Windows
    $win = ''
    if ($IsWinPE) {
        $tw = Get-TargetWin
        if (-not $tw) { Msg 'Select the Target Windows at the top first. In WinPE the queue works on that Windows, which is not running.' 'Automation' 'Warning'; return }
        $win = [string]$tw.Drive
    }
    $bad = @($script:AutoQueue | Where-Object { Get-AutoWhyNot $_ })
    if ($bad.Count) { Msg ("These tasks cannot run here:${NL}${NL}" + (($bad | ForEach-Object { '  ' + (Get-AutoCat $_).Name + ' - ' + (Get-AutoWhyNot $_) }) -join $NL) + "${NL}${NL}Remove them from the queue, then start again.") 'Automation' 'Warning'; return }
    $where = if ($win) { "the OFFLINE Windows on $win (from WinPE)" } else { "THIS PC ($env:COMPUTERNAME)" }
    # chkdsk /f needs the drive to itself: when this tool's own data folder (its task logs) is on that drive, chkdsk has to ask
    # whether to force a dismount (found in the Hiren's PE test). Say so before starting.
    if ($win -and (@($script:AutoQueue) -contains 'chkdsk-fix') -and ([IO.Path]::GetPathRoot($DataDir).TrimEnd('\') -ieq $win.TrimEnd('\'))) {
        if (-not (Ask ("WinSuperTool keeps its data and task logs in $DataDir - on $win, the drive that 'Check disk and REPAIR' needs to itself.${NL}${NL}chkdsk will ask whether to force a dismount of ${win}: answer N (the task is then reported as not run). Better: start WinSuperTool from a USB stick or from X:.${NL}${NL}Start the queue anyway?") 'Check disk and REPAIR' 'Warning' 'Button2')) { return }
    }
    $names = (@($script:AutoQueue) | ForEach-Object { '  ' + (Get-AutoCat $_).Name }) -join $NL
    if (-not (Ask "Run these $($script:AutoQueue.Count) task(s) on $where, one after another?${NL}${NL}$names${NL}${NL}Each task opens its own window. Some tasks change the system (repairs, updates, app upgrades). BETA feature." 'Start automation' 'Question' 'Button2')) { return }
    $script:AutoRun = New-Object Collections.ArrayList
    foreach ($id in $script:AutoQueue) { $c = Get-AutoCat $id; [void]$script:AutoRun.Add([pscustomobject]@{ Id = $id; Name = $c.Name; Auto = $false; Why = ''; Status = 'Waiting'; Find = ''; Ok = $null; Tone = ''; Rc = $null; Started = $null; Ended = $null; OutFile = ''; Quote = @(); Line = ''; Next = '' }) }
    $script:Auto = @{ Running = $true; StopReq = $false; Index = -1; Started = (Get-Date); StopWhy = ''; Win = $win
        Opt = @{ Popups = $chkAutoPop.Checked; StopOnFail = $chkAutoStop.Checked; Monitor = $chkAutoMon.Checked; EnableSR = $chkAutoSR.Checked } }
    Save-AutoState
    Set-AutoEditing $false
    Log ("AUTOMATION: started, $($script:AutoRun.Count) task(s)." + $(if ($win) { " Offline Windows: $win (WinPE)." } else { '' }))
    Start-AutoNext
}
function Start-AutoNext {
    $A = $script:Auto
    if (-not $A.Running) { return }
    if ($A.StopReq) {
        for ($i = $A.Index + 1; $i -lt $script:AutoRun.Count; $i++) { $script:AutoRun[$i].Status = 'Skipped' }
        Complete-AutoRun; return
    }
    $A.Index++
    if ($A.Index -ge $script:AutoRun.Count) { Complete-AutoRun; return }
    $r = $script:AutoRun[$A.Index]; $c = Get-AutoCat $r.Id
    $r.Status = 'Running'; $r.Started = Get-Date
    $lblAutoStatus.Text = "Running $($A.Index + 1) of $($script:AutoRun.Count): $($c.Name)"
    Update-AutoList
    try {
        if ($A.Opt.Monitor) { [void](Start-TaskMonitors $c) }
        $code = Get-AutoCode $c $A.Opt ([string]$A.Win)
        $r.Line = $code.Line
        Log "AUTOMATION $($A.Index + 1)/$($script:AutoRun.Count): $($c.Name)  ($($code.Line))"
        [void](Start-TaskWindow $c.Name $c.Kind $code.Line $code.Call $true $r)
    } catch {
        $r.Status = 'FAILED'; $r.Find = "COULD NOT START - $($_.Exception.Message)"; $r.Ended = Get-Date; $r.Ok = $false; $r.Tone = 'Bad'
        Log "AUTOMATION: $($c.Name) could not start: $($_.Exception.Message)"
        if ($A.Opt.StopOnFail) { $A.StopReq = $true; $A.StopWhy = 'stopped because a task failed' }
        Start-AutoNext
    }
}
function Complete-AutoTask($t, $res, $v) {
    $A = $script:Auto; $r = $t.AutoItem
    $r.Ended = Get-Date; $r.Rc = $res.Rc; $r.Ok = $v.Ok; $r.Tone = $v.Tone; $r.Find = $v.Find; $r.Quote = @($v.Quote); $r.OutFile = $t.ResultFile; $r.Next = [string]$v.Next
    $r.Status = if ($v.Ok) { 'PASSED' } elseif ($v.Tone -eq 'Warn') { 'NOT RUN' } else { 'FAILED' }
    if ($A.Opt -and $A.Opt.Popups) { try { Show-TaskSummary $t $res $v $true } catch { Log "Summary window error: $($_.Exception.Message)" } }
    # "repair only if needed": queue the repair right after this task
    $c = Get-AutoCat $r.Id
    if ($c.Then -and $v.Find -match $c.Then.If) {
        $add = Get-AutoCat $c.Then.Add
        $script:AutoRun.Insert($A.Index + 1, [pscustomobject]@{ Id = $add.Id; Name = $add.Name; Auto = $true; Why = $c.Then.Why; Status = 'Waiting'; Find = ''; Ok = $null; Tone = ''; Rc = $null; Started = $null; Ended = $null; OutFile = ''; Quote = @(); Line = ''; Next = '' })
        Log "AUTOMATION: $($add.Name) $($c.Then.Why)."
    }
    if ($r.Status -ne 'PASSED' -and $A.Opt.StopOnFail) { $A.StopReq = $true; $A.StopWhy = 'stopped because a task did not pass' }
    Update-AutoList
    Start-AutoNext
}
function Get-RebootPending {
    $why = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $why += 'Windows servicing (component updates or repairs)' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $why += 'Windows Update' }
    try { if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations) { $why += 'files waiting to be replaced at restart' } } catch {}
    $why
}
function Get-AutoSummaryBlocks {
    $A = $script:Auto; $rows = @($script:AutoRun)
    $ran = @($rows | Where-Object { $_.Status -in 'PASSED', 'FAILED', 'NOT RUN' })
    $pass = @($rows | Where-Object { $_.Status -eq 'PASSED' }).Count; $fail = @($rows | Where-Object { $_.Status -eq 'FAILED' }).Count
    $nr = @($rows | Where-Object { $_.Status -eq 'NOT RUN' }).Count; $skip = @($rows | Where-Object { $_.Status -eq 'Skipped' }).Count
    $b = New-Object Collections.ArrayList
    [void]$b.Add((InfoH 'Result'))
    $line = "$($ran.Count) task(s) ran: $pass passed, $fail failed" + $(if ($nr) { ", $nr did not run" } else { '' }) + $(if ($skip) { ", $skip skipped" } else { '' }) + '.'
    [void]$b.Add((InfoT $line $(if ($fail -or $nr) { 'Bad' } else { 'Good' })))
    if ($A.StopWhy) { [void]$b.Add((InfoT ('The queue ' + $A.StopWhy + '.') 'Warn')) }
    [void]$b.Add((InfoKV 'Started' ('{0:yyyy-MM-dd HH:mm:ss}' -f $A.Started)))
    [void]$b.Add((InfoKV 'Finished' ('{0:yyyy-MM-dd HH:mm:ss}  (took {1})' -f (Get-Date), (Format-Dur $A.Started (Get-Date)))))
    if ($A.Win) { [void]$b.Add((InfoKV 'Windows' "$($A.Win) - offline, from WinPE")) }
    $rb = if ($A.Win) { @() } else { @(Get-RebootPending) }
    if ($A.Win) { [void]$b.Add((InfoKV 'Restart needed' 'not checked (offline Windows) - start it to finish any repair it still has pending')) }
    else { [void]$b.Add((InfoKV 'Restart needed' $(if ($rb.Count) { 'YES - ' + ($rb -join ', ') } else { 'no' }) $(if ($rb.Count) { 'Warn' } else { 'Good' }))) }
    [void]$b.Add((InfoH 'Tasks'))
    $i = 0
    foreach ($r in $rows) {
        $i++
        $name = "$i. $($r.Name)"
        $val = @("$($r.Status)" + $(if ($r.Find) { " - $($r.Find)" } else { '' }) + $(if ($r.Started -and $r.Ended) { "   ($(Format-Dur $r.Started $r.Ended))" } else { '' }))
        if ($r.Auto) { $val += "($($r.Why))" }
        foreach ($q in @($r.Quote)) { if ($q) { $val += ('"' + $q + '"') } }
        $col = switch ($r.Status) { 'PASSED' { if ($r.Tone -eq 'Bad') { 'Bad' } elseif ($r.Tone -eq 'Warn') { 'Warn' } else { 'Good' } } 'FAILED' { 'Bad' } 'NOT RUN' { 'Warn' } default { '' } }
        [void]$b.Add((InfoKV $name $val $col))
    }
    return $b
}
# ---- BETA 3: the Automation report as one self-contained HTML page (no scripts, works offline, prints well) ----
function ConvertTo-HtmlText($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Export-AutoHtml([string]$path) {
    $A = $script:Auto; $rows = @($script:AutoRun); $now = Get-Date
    $pass = @($rows | Where-Object { $_.Status -eq 'PASSED' }).Count; $fail = @($rows | Where-Object { $_.Status -eq 'FAILED' }).Count
    $nr = @($rows | Where-Object { $_.Status -eq 'NOT RUN' }).Count; $skip = @($rows | Where-Object { $_.Status -eq 'Skipped' }).Count
    $attn = @($rows | Where-Object { $_.Status -eq 'PASSED' -and $_.Tone -ne 'Good' }).Count
    $rb = if ($A.Win) { @() } else { @(Get-RebootPending) }
    # (parentheses: in @(a, b + c) the comma binds tighter than +, which split the text into separate items)
    $overall = if ($fail -or $nr) { @('bad', ("$fail FAILED" + $(if ($nr) { ", $nr DID NOT RUN" } else { '' }) + ", $pass passed - see the red rows")) }
               elseif ($attn) { @('warn', "ALL $pass TASKS RAN - $attn result(s) need attention (orange / red results)") }
               else { @('good', "ALL $pass TASKS PASSED") }
    $cls = { param($r) switch ($r.Status) { 'PASSED' { if ($r.Tone -eq 'Bad') { 'bad' } elseif ($r.Tone -eq 'Warn') { 'warn' } else { 'good' } } 'FAILED' { 'bad' } 'NOT RUN' { 'warn' } default { 'skip' } } }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append(@'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Automation report - Windows Repair Toolkit</title>
<style>
:root { --good:#1e7e3c; --good-bg:#e6f4ea; --bad:#b42318; --bad-bg:#fdecea; --warn:#a15c00; --warn-bg:#fff4e0; --skip:#667085; --skip-bg:#f2f4f7; --ink:#1d2939; --mute:#475467; --line:#d0d5dd; }
* { box-sizing:border-box } body { font:15px/1.5 "Segoe UI",Arial,sans-serif; color:var(--ink); margin:0; background:#f8fafc }
main { max-width:1100px; margin:0 auto; padding:24px 16px 48px }
h1 { font-size:24px; margin:0 0 4px } h2 { font-size:19px; margin:32px 0 10px; border-bottom:2px solid var(--line); padding-bottom:4px }
.sub { color:var(--mute); margin:0 0 18px } .beta { color:var(--warn); font-weight:600 }
.banner { border-radius:10px; padding:16px 20px; font-size:20px; font-weight:700; margin:0 0 14px }
.banner.good { background:var(--good-bg); color:var(--good); border:1px solid var(--good) } .banner.bad { background:var(--bad-bg); color:var(--bad); border:1px solid var(--bad) } .banner.warn { background:var(--warn-bg); color:var(--warn); border:1px solid var(--warn) }
.facts { display:flex; flex-wrap:wrap; gap:8px 28px; margin:0 0 18px; color:var(--mute) } .facts b { color:var(--ink) }
table { width:100%; border-collapse:collapse; background:#fff; border:1px solid var(--line); border-radius:8px; overflow:hidden }
th, td { text-align:left; padding:9px 10px; border-bottom:1px solid var(--line); vertical-align:top } th { background:#eef2f6; font-size:13px; text-transform:uppercase; letter-spacing:.03em; color:var(--mute) }
tr.good td:first-child { border-left:5px solid var(--good) } tr.bad td:first-child { border-left:5px solid var(--bad) } tr.warn td:first-child { border-left:5px solid var(--warn) } tr.skip td:first-child { border-left:5px solid var(--skip) }
.badge { display:inline-block; padding:2px 10px; border-radius:999px; font-size:12px; font-weight:700; white-space:nowrap }
.badge.good { background:var(--good-bg); color:var(--good) } .badge.bad { background:var(--bad-bg); color:var(--bad) } .badge.warn { background:var(--warn-bg); color:var(--warn) } .badge.skip { background:var(--skip-bg); color:var(--skip) }
.res.good { color:var(--good) } .res.bad { color:var(--bad) } .res.warn { color:var(--warn) } .res { font-weight:600 }
.task { background:#fff; border:1px solid var(--line); border-radius:8px; padding:14px 16px; margin:0 0 14px }
.task.good { border-left:6px solid var(--good) } .task.bad { border-left:6px solid var(--bad) } .task.warn { border-left:6px solid var(--warn) } .task.skip { border-left:6px solid var(--skip) }
.task h3 { margin:0 0 6px; font-size:17px } .auto { color:var(--mute); font-style:italic; font-weight:400 }
blockquote { margin:8px 0; padding:6px 12px; border-left:3px solid var(--line); background:#f8fafc; font-family:Consolas,monospace; font-size:13.5px }
dl { display:grid; grid-template-columns:max-content 1fr; gap:3px 14px; margin:8px 0 } dt { color:var(--mute) } dd { margin:0; word-break:break-word }
code { font-family:Consolas,monospace; font-size:13px; background:#eef2f6; padding:1px 5px; border-radius:4px }
details { margin-top:8px } summary { cursor:pointer; color:#175cd3 } pre { background:#0f172a; color:#e2e8f0; padding:12px; border-radius:6px; overflow:auto; font:12.5px/1.45 Consolas,monospace; max-height:520px; white-space:pre-wrap }
footer { color:var(--mute); font-size:13px; margin-top:28px }
.wide { overflow-x:auto; border-radius:8px } h1, .banner, .sub, dd, blockquote, code { overflow-wrap:anywhere }
@media (max-width:640px) { body { font-size:14px } main { padding:16px 10px 32px } h1 { font-size:20px } .banner { font-size:17px; padding:12px 14px } .facts { gap:4px 16px } th, td { padding:7px 6px } th { font-size:11px } dl { grid-template-columns:1fr } dt { margin-top:4px } .task { padding:12px } }
@media print { body { background:#fff } details { display:none } .task, table { break-inside:avoid } .wide { overflow:visible } }
</style></head><body><main>
'@)
    [void]$sb.Append("<h1>Automation report</h1><p class=""sub"">Windows Repair Toolkit - $(ConvertTo-HtmlText $AppName) &nbsp;|&nbsp; <span class=""beta"">BETA</span></p>")
    [void]$sb.Append("<div class=""banner $($overall[0])"">$(ConvertTo-HtmlText $overall[1])</div>")
    $took = Format-Dur $A.Started $now
    [void]$sb.Append('<div class="facts">')
    [void]$sb.Append("<span>$(if ($A.Win) { 'Windows: <b>' + (ConvertTo-HtmlText $A.Win) + ' (offline, from WinPE)</b>' } else { 'PC: <b>' + (ConvertTo-HtmlText $env:COMPUTERNAME) + '</b>' })</span><span>Started: <b>$('{0:yyyy-MM-dd HH:mm:ss}' -f $A.Started)</b></span><span>Finished: <b>$('{0:yyyy-MM-dd HH:mm:ss}' -f $now)</b> ($took)</span>")
    [void]$sb.Append("<span>Tasks: <b>$($rows.Count)</b> - $pass passed, $fail failed$(if ($nr) { ", $nr did not run" })$(if ($skip) { ", $skip skipped" })</span>")
    [void]$sb.Append("<span>Restart needed: <b class=""res $(if ($rb.Count) { 'warn' } else { 'good' })"">$(if ($A.Win) { 'not checked (offline Windows)' } elseif ($rb.Count) { 'YES - ' + (ConvertTo-HtmlText ($rb -join ', ')) } else { 'no' })</b></span>")
    if ($A.StopWhy) { [void]$sb.Append("<span class=""res warn"">The queue $(ConvertTo-HtmlText $A.StopWhy).</span>") }
    [void]$sb.Append('</div>')
    # ---- the summary table: one line per task ----
    [void]$sb.Append('<h2>Summary</h2><div class="wide"><table><thead><tr><th>#</th><th>Task</th><th>Status</th><th>Result</th><th>Time</th></tr></thead><tbody>')
    $i = 0
    foreach ($r in $rows) {
        $i++; $c = & $cls $r
        $name = (ConvertTo-HtmlText $r.Name) + $(if ($r.Auto) { " <span class=""auto"">($(ConvertTo-HtmlText $r.Why))</span>" } else { '' })
        [void]$sb.Append("<tr class=""$c""><td>$i</td><td>$name</td><td><span class=""badge $c"">$(ConvertTo-HtmlText $r.Status)</span></td><td class=""res $c"">$(ConvertTo-HtmlText $r.Find)</td><td>$(Format-Dur $r.Started $r.Ended)</td></tr>")
    }
    [void]$sb.Append('</tbody></table></div>')   # (1.9 beta 5) the table scrolls on its own on a phone, not the whole page
    # ---- details: everything about each task, full output last ----
    [void]$sb.Append('<h2>Details</h2>')
    $i = 0
    foreach ($r in $rows) {
        $i++; $c = & $cls $r
        $autoTag = if ($r.Auto) { ' <span class="auto">' + (ConvertTo-HtmlText $r.Why) + '</span>' } else { '' }
        [void]$sb.Append("<section class=""task $c""><h3>$i. $(ConvertTo-HtmlText $r.Name) <span class=""badge $c"">$(ConvertTo-HtmlText $r.Status)</span>$autoTag</h3>")
        if ($r.Find) { [void]$sb.Append("<div class=""res $c"">$(ConvertTo-HtmlText $r.Find)</div>") }
        foreach ($q in @($r.Quote)) { if ($q) { [void]$sb.Append("<blockquote>""$(ConvertTo-HtmlText $q)""</blockquote>") } }
        [void]$sb.Append('<dl>')
        if ($r.Next) { [void]$sb.Append("<dt>Next step</dt><dd>$(ConvertTo-HtmlText $r.Next)</dd>") }
        if ($r.Line) { [void]$sb.Append("<dt>Command</dt><dd><code>$(ConvertTo-HtmlText $r.Line)</code></dd>") }
        if ($r.Started) { [void]$sb.Append("<dt>Ran</dt><dd>$('{0:HH:mm:ss}' -f $r.Started)$(if ($r.Ended) { ' - ' + ('{0:HH:mm:ss}' -f $r.Ended) + ' (' + (Format-Dur $r.Started $r.Ended) + ')' })</dd>") }
        if ($null -ne $r.Rc) { $rcs = "$($r.Rc)"; if ($r.Rc -is [int] -and ($r.Rc -lt 0 -or $r.Rc -gt 65535)) { $rcs += ('  (0x{0:X8})' -f $r.Rc) }; [void]$sb.Append("<dt>Exit code</dt><dd>$rcs</dd>") }
        if ($r.OutFile) { [void]$sb.Append("<dt>Output file</dt><dd><code>$(ConvertTo-HtmlText $r.OutFile)</code></dd>") }
        [void]$sb.Append('</dl>')
        $out = ''; if ($r.OutFile -and [IO.File]::Exists($r.OutFile)) { try { $out = (Read-TaskResult $r.OutFile).Output } catch {} }
        if ($out) { [void]$sb.Append("<details><summary>Full output</summary><pre>$(ConvertTo-HtmlText $out.Trim())</pre></details>") }
        elseif ($r.Status -eq 'Skipped') { [void]$sb.Append('<div class="auto">Not run (the queue stopped before this task).</div>') }
        [void]$sb.Append('</section>')
    }
    [void]$sb.Append("<footer>Created by the Windows Repair Toolkit (BETA) - licensed under GNU GPL v3.0. Result messages are matched in English; on another display language the result comes from the exit code.</footer></main></body></html>")
    [IO.File]::WriteAllText($path, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
    $script:LastAutoHtml = $path
    return $path
}
function Complete-AutoRun {
    $A = $script:Auto; $A.Running = $false
    Set-AutoEditing $true
    $blocks = New-Object Collections.ArrayList; $blocks.AddRange(@(Get-AutoSummaryBlocks))
    $rep = (Get-TaskFileBase 'Automation-summary') + '.txt'
    try { [IO.File]::WriteAllText($rep, (Format-InfoText $blocks 'Automation summary')) } catch { $rep = '' }
    $html = ''
    if ($chkAutoHtml.Checked) {
        try { $html = Export-AutoHtml ((Get-TaskFileBase 'Automation-report') + '.html'); Start-Process -FilePath $html; Log "AUTOMATION: HTML report: $html" }
        catch { Log "AUTOMATION: the HTML report could not be written: $($_.Exception.Message)"; $html = '' }
    }
    if ($rep) { [void]$blocks.Add((InfoH 'Saved')); [void]$blocks.Add((InfoKV 'This summary' $rep)); if ($html) { [void]$blocks.Add((InfoKV 'HTML report' $html)) }; [void]$blocks.Add((InfoKV 'Each task''s output' $TaskDir)) }
    $lblAutoStatus.Text = 'Finished at {0:HH:mm}. {1}' -f (Get-Date), $(if ($A.StopWhy) { "The queue $($A.StopWhy)." } else { '' })
    Update-AutoList
    Log "AUTOMATION: finished. Summary: $rep"
    $script:InSummary = $true
    try { Show-Info 'Automation summary' $blocks 'BETA: every task ran in its own window; its full output is saved in WinSuperTool-Data\Task-Results.' $true } finally { $script:InSummary = $false }
}

# =====================================================================
#  Run any .ps1 elevated (replaces the old Run-PS-As-Admin.bat paste mode)
# =====================================================================
function Show-ScriptRunner {
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = 'Run a PowerShell script as administrator'; $f.ClientSize = New-Object Drawing.Size(620, 150)
    $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.Font = $form.Font
    [void](New-Ctl 'Label' $f 10 10 600 36 'Paste the full path of a .ps1 file (quotes and %variables% are OK) or browse. It starts in its own window with admin rights, -ExecutionPolicy Bypass and -STA.')
    $script:SrPath = New-Ctl 'TextBox' $f 10 50 510 24
    $btnB  = New-Ctl 'Button' $f 528 49 82 26 'Browse...'
    $script:SrKeep = New-Ctl 'CheckBox' $f 10 82 420 22 'Keep the PowerShell window open after the script ends'
    $btnGo = New-Ctl 'Button' $f 420 112 95 28 'Run'
    $btnX  = New-Ctl 'Button' $f 520 112 90 28 'Close'
    $btnX.DialogResult = 'Cancel'; $f.CancelButton = $btnX; $f.AcceptButton = $btnGo
    $btnB.Add_Click({
        $d = New-Object Windows.Forms.OpenFileDialog
        $d.Filter = 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        if ($d.ShowDialog() -eq 'OK') { $script:SrPath.Text = $d.FileName }
    })
    $btnGo.Add_Click({ Safe {
        $p = [Environment]::ExpandEnvironmentVariables($script:SrPath.Text.Trim().Trim('"').Trim("'").Trim())
        if (-not $p) { Msg 'Paste or browse to a .ps1 file first.' 'Run script' 'Warning'; return }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Msg "File not found:${NL}$p" 'Run script' 'Warning'; return }
        if ([IO.Path]::GetExtension($p) -ne '.ps1') { Msg "That is not a .ps1 file:${NL}$p" 'Run script' 'Warning'; return }
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $p))
        if ($script:SrKeep.Checked) { $a = @('-NoExit') + $a }
        Start-Process -FilePath $PsExePath -ArgumentList $a
        Log "Started script (elevated): $p"
    } })
    [void]$f.ShowDialog($form)
    $f.Dispose()
}

# =====================================================================
#  GUI
# =====================================================================
$form = New-Object Windows.Forms.Form; Set-WrtScaling $form
$form.Text = $AppName
if ($IsWinPE) { $form.Text = "$AppName  -  WinPE mode" }
$form.ClientSize    = New-Object Drawing.Size(980, 680)
$form.MinimumSize   = New-Object Drawing.Size(940, 560)
$form.StartPosition = 'CenterScreen'
$form.Font          = New-Object Drawing.Font('Segoe UI', 9)
# (opens maximized when the scaled window does not fit the screen: see Initialize-WrtWindow before ShowDialog)

# ---------- Target Windows bar ----------
[void](New-Ctl 'Label' $form 10 13 106 20 'Target Windows:')
$cmbWin = New-Ctl 'ComboBox' $form 118 10 560 24; $cmbWin.DisplayMember = 'Text'
$btnRescan = New-Ctl 'Button' $form 684 9 76 26 'Rescan'
Add-Help $form 764 10 'Target Windows' ("The Windows installation the Collect Logs, Safe Mode, Unattend and Recovery tabs work on.${NL}${NL}- [RUNNING - this PC] is the Windows you booted.${NL}- [offline] is an install on another drive, or every install when you run from WinPE.${NL}${NL}If more than one install is found you get a warning and nothing is pre-selected, so you always choose which one is modified.${NL}${NL}An install that does not show up usually has no drive letter: mount its partition on the Mount tab, then press Rescan.")
$btnRunPs = New-Ctl 'Button' $form 794 9 92 26 'Run a .ps1...'
$tip.SetToolTip($btnRunPs, 'Run any PowerShell script elevated (paste a path or browse).')
$btnData  = New-Ctl 'Button' $form 890 9 82 26 'Data folder'
$tip.SetToolTip($btnData, "Open $DataDir (mount memory, BCD backups, activity log).")
$lblWarn = New-Ctl 'Label' $form 10 38 960 20
$lblWarn.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)

# ---------- tabs ----------
$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(8, 60)
$tabs.Size     = New-Object Drawing.Size(964, 492)
$tabs.Anchor   = 'Top,Bottom,Left,Right'
$form.Controls.Add($tabs)
function New-Page($text) {
    $p = New-Object Windows.Forms.TabPage
    $p.Text = $text; $p.UseVisualStyleBackColor = $true; $p.AutoScroll = $true
    $tabs.TabPages.Add($p)
    return $p
}
$tpCol  = New-Page '1. Collect Logs'
$tpMon  = New-Page '2. Live Monitor'
$tpMnt  = New-Page '3. Mount'
$tpSafe = New-Page '4. Safe Mode'
$tpSys  = New-Page '5. Sysprep'
$tpUna  = New-Page '6. Unattend'
$tpRec  = New-Page '7. Recovery'
$tpInfo = New-Page '8. System Info'
$tpAuto = New-Page '9. Automation'
# create the tab control now (1.8.2): until it exists every tab page is a 200 x 100 placeholder, and controls anchored to the bottom or right of a page would be measured against that and end up in the wrong place
[void]$tabs.Handle      # (reading .Handle creates it; CreateControl() does nothing while the window is not shown yet)

# ---------- activity log ----------
$lblLog = New-Ctl 'Label' $form 10 556 600 18 'Activity log (also saved as activity.log in the data folder):'
$lblLog.Anchor = 'Bottom,Left'
$txtLog = New-Ctl 'TextBox' $form 8 574 964 98
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object Drawing.Font('Consolas', 8.5); $txtLog.Anchor = 'Bottom,Left,Right'

# ---------- 1. Collect Logs ----------
[void](New-Ctl 'Label' $tpCol 10 11 90 20 'Output folder:')
$txtColOut     = New-Ctl 'TextBox' $tpCol 100 8 560 24
$btnColBrowse  = New-Ctl 'Button' $tpCol 666 7 80 26 'Browse...'
$btnColDefault = New-Ctl 'Button' $tpCol 750 7 70 26 'Default'
Add-Help $tpCol 824 8 'Collect logs' ("Tick what you want and press Collect selected. Everything lands in the output folder, one subfolder per category, plus _collection_summary.txt.${NL}${NL}Default output: the signed-in user's Desktop\logs (OneDrive-redirected desktops included). In WinPE the default is WinSuperTool-Data\logs next to this script, so the logs survive a reboot.${NL}${NL}Offline installs: pick the install in Target Windows. Files are copied from its disk, event logs are copied as .evtx files, and DISM /image builds the package and driver lists. Items that need the running Windows (reliability history, systeminfo, hotfixes) are skipped with a note.${NL}${NL}Files Windows holds open are copied with a shared-read fallback; anything that still fails is listed as FAILED.")
$lblColInfo = New-Ctl 'Label' $tpCol 10 38 920 20 'Copies logs from the Target Windows chosen at the top. An offline install (WinPE or a second drive) is read straight from its disk.'
$lblColInfo.ForeColor = 'DimGray'
$colBoxes = @{}
$y = 62
foreach ($k in $Collectors.Keys) {
    $cb = New-Ctl 'CheckBox' $tpCol 14 $y 900 22 $Collectors[$k].Label
    $cb.Checked = [bool]$Collectors[$k].Default
    $colBoxes[$k] = $cb
    $y += 23
}
$btnColAll  = New-Ctl 'Button' $tpCol 12 274 120 30 'Select / clear all'
$btnColGo   = New-Ctl 'Button' $tpCol 138 274 150 30 'Collect selected'
$btnColGo.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$btnColOpen = New-Ctl 'Button' $tpCol 294 274 110 30 'Open folder'
$txtCol = New-Ctl 'TextBox' $tpCol 12 312 930 128
$txtCol.Multiline = $true; $txtCol.ReadOnly = $true; $txtCol.ScrollBars = 'Vertical'; $txtCol.Font = New-Object Drawing.Font('Consolas', 9)
$txtColOut.Text = Get-DefaultLogRoot

# ---------- 2. Live Monitor ----------
[void](New-Ctl 'Label' $tpMon 10 8 880 20 'Tick the logs to watch, then press "Launch selected". Each log opens in its own window. Monitors watch the Windows this tool is running on.')
Add-Help $tpMon 914 5 'Live monitor' ("Each monitor opens its own PowerShell window running Get-Content <log> -Tail <N> -Wait (N = the number set on this tab), so you can watch every log independently. If a log does not exist yet, its window waits and starts once the file appears.${NL}${NL}- Event Viewer logs (.evtx) cannot be tailed as text, so they use a live Get-WinEvent watcher (errors red, warnings yellow).${NL}- The SFC-only CBS filter starts from at least 300 lines, because most CBS lines do not match.${NL}- Folder watchers list existing files, then report new ones (minidumps, WER reports).${NL}${NL}In WinPE, X:\Windows\Logs\DISM\dism.log and CBS.log show what offline DISM / sfc runs from the Recovery tab are doing.")
$monPanel = New-Object Windows.Forms.Panel
$monPanel.Location = New-Object Drawing.Point(10, 30); $monPanel.Size = New-Object Drawing.Size(932, 214)
$monPanel.AutoScroll = $true; $monPanel.BorderStyle = 'FixedSingle'
$tpMon.Controls.Add($monPanel)
$monChecks = New-Object Collections.ArrayList
$y = 6
foreach ($sec in @($MonItems | Select-Object -ExpandProperty Section -Unique)) {
    $hdr = New-Ctl 'Label' $monPanel 6 $y 400 22 $sec
    $hdr.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
    $secBoxes = New-Object Collections.ArrayList
    $bAll  = New-Ctl 'Button' $monPanel 640 ($y - 1) 50 24 'All'
    $bNone = New-Ctl 'Button' $monPanel 694 ($y - 1) 50 24 'None'
    $bGo   = New-Ctl 'Button' $monPanel 748 ($y - 1) 110 24 'Launch section'
    $y += 28
    foreach ($it in @($MonItems | Where-Object { $_.Section -eq $sec })) {
        $cb = New-Ctl 'CheckBox' $monPanel 22 $y 600 22 $it.Name
        $cb.Tag = $it
        # an event log that is not on this Windows (they differ between versions) is shown greyed out
        if ($it.Type -eq 'Evt' -and $EvtLogNames.Count -and $EvtLogNames -notcontains $it.Target) { $cb.Enabled = $false; $cb.Text += '   (not on this PC)' }
        $tip.SetToolTip($cb, [string]$it.Target)
        [void]$secBoxes.Add($cb); [void]$monChecks.Add($cb)
        $y += 24
    }
    $y += 10
    $bAll.Tag = $secBoxes; $bNone.Tag = $secBoxes; $bGo.Tag = $secBoxes
    $bAll.Add_Click({ foreach ($c in $this.Tag) { $c.Checked = $true } })
    $bNone.Add_Click({ foreach ($c in $this.Tag) { $c.Checked = $false } })
    $bGo.Add_Click({
        $boxes = $this.Tag
        Safe {
            $n = 0
            foreach ($c in $boxes) { Start-Monitor $c.Tag ([int]$numTail.Value); $n++; Start-Sleep -Milliseconds 200 }
            Update-MonStatus "Launched $n monitor(s) from this section."
        }
    })
}
$lblPaste = New-Ctl 'Label' $tpMon 10 250 760 20 'Paste log path(s) from anywhere - one per line; quotes and %variables% are OK:'
$lblPaste.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$txtPaste = New-Ctl 'TextBox' $tpMon 10 272 760 54
$txtPaste.Multiline = $true; $txtPaste.ScrollBars = 'Vertical'; $txtPaste.WordWrap = $false
$btnPaste      = New-Ctl 'Button' $tpMon 778 272 164 26 'Monitor pasted log(s)'
$btnPasteClear = New-Ctl 'Button' $tpMon 778 300 164 26 'Clear box'
[void](New-Ctl 'Label' $tpMon 12 341 66 20 'Tail lines:')
$numTail = New-Object Windows.Forms.NumericUpDown
$numTail.Location = New-Object Drawing.Point(80, 338); $numTail.Size = New-Object Drawing.Size(65, 24)
$numTail.Minimum = 1; $numTail.Maximum = 5000; $numTail.Value = 20
$tpMon.Controls.Add($numTail)
$btnMonLaunch = New-Ctl 'Button' $tpMon 156 334 130 30 'Launch selected'
$btnMonBrowse = New-Ctl 'Button' $tpMon 292 334 130 30 'Browse for file...'
$btnMonClear  = New-Ctl 'Button' $tpMon 428 334 100 30 'Uncheck all'
$btnMonClose  = New-Ctl 'Button' $tpMon 534 334 150 30 'Close all monitors'
$lblMonStatus = New-Ctl 'Label' $tpMon 12 372 930 40 'Ready.'

# ---------- 4. Mount ----------
[void](New-Ctl 'Label' $tpMnt 12 15 60 20 'Engine')
$rbDp   = New-Ctl 'RadioButton' $tpMnt 75 12 110 22 'diskpart'; $rbDp.Checked = $true
$rbStor = New-Ctl 'RadioButton' $tpMnt 190 12 170 22 'Storage cmdlets'
Add-Help $tpMnt 370 11 'Mount engine' ("diskpart: the classic tool; works everywhere including WinPE. Its output is parsed as text, so it can misbehave on non-English systems.${NL}${NL}Storage cmdlets: Get-Disk / Get-Partition / Add-PartitionAccessPath. Cleaner and language independent; available on Windows 10/11 and WinPE builds with the Storage module (greyed out when missing). Windows may refuse a letter on the EFI partition this way - use diskpart for that.${NL}${NL}Both do the same four things: list disks, list partitions, add a drive letter, remove a drive letter. Nothing is formatted, cleaned or deleted.")
[void](New-Ctl 'Label' $tpMnt 12 50 60 20 'Disk')
$cmbDisk = New-Ctl 'ComboBox' $tpMnt 75 47 640 24; $cmbDisk.DisplayMember = 'Text'
$btnRefresh = New-Ctl 'Button' $tpMnt 722 46 95 26 'Refresh'
[void](New-Ctl 'Label' $tpMnt 12 82 60 20 'Partition')
$cmbPart = New-Ctl 'ComboBox' $tpMnt 75 79 640 24; $cmbPart.DisplayMember = 'Text'
[void](New-Ctl 'Label' $tpMnt 12 114 60 20 'Letter')
$cmbLetter = New-Ctl 'ComboBox' $tpMnt 75 111 70 24
$btnMount  = New-Ctl 'Button' $tpMnt 155 109 150 28 'Mount'
Add-Help $tpMnt 315 111 'Mount a partition' ("Gives any partition a temporary drive letter (diskpart: list disk > select disk > list partition > select partition > assign letter).${NL}${NL}Use cases:${NL}- Mount the hidden EFI System Partition to edit or repair the bootloader (BCD).${NL}- Reach an offline Windows install to copy data or logs, inject/remove drivers or edit registry hives.${NL}- Access Recovery / OEM partitions.${NL}${NL}Safety: only list, select, detail, assign letter and remove letter are ever sent to diskpart, and the Storage mode only adds/removes access paths. Only letters this tool assigned are removed, never the system drive.")
[void](New-Ctl 'Label' $tpMnt 12 150 330 18 'Mounted by this tool (remembered between runs):')
$lstMounts     = New-Ctl 'ListBox' $tpMnt 12 170 703 100
$btnUnmount    = New-Ctl 'Button' $tpMnt 722 170 95 28 'Unmount'
$btnUnmountAll = New-Ctl 'Button' $tpMnt 722 204 95 28 'Unmount all'
$chkAuto = New-Ctl 'CheckBox' $tpMnt 12 278 400 20 'Unmount everything when this tool closes'
$chkAuto.Checked = $true

# ---------- 5. Safe Mode ----------
[void](New-Ctl 'Label' $tpSafe 12 15 70 20 'Apply to')
$rbEdit  = New-Ctl 'RadioButton' $tpSafe 90 12 420 22 'Edit the boot entry of the Target Windows directly'; $rbEdit.Checked = $true
$rbClone = New-Ctl 'RadioButton' $tpSafe 90 36 420 22 'Clone the entry -> separate "Safe Mode" item in the boot menu'
Add-Help $tpSafe 520 24 'Edit vs. clone' ("Edit directly: sets safeboot on the existing entry (bcdedit /set {current} safeboot minimal). The PC boots into Safe Mode on EVERY start until you remove the flag.${NL}${NL}Clone: copies the entry (bcdedit /copy), names the copy 'Safe Mode (minimal) [WinSuperTool]' and sets safeboot only on the copy. Your normal entry stays untouched; pick Safe Mode from the boot menu when you want it. Removing deletes only clones this tool (or the older WinRepairTool) created.${NL}${NL}Every BCD change is preceded by an automatic backup.")
$lblBcd = New-Ctl 'Label' $tpSafe 12 70 920 52
$btnSafeOn  = New-Ctl 'Button' $tpSafe 12 128 230 30 'Enable Safe Mode (minimal)'
Add-Help $tpSafe 248 131 'Enable Safe Mode' ("bcdedit /set {current} safeboot minimal${NL}${NL}Use cases:${NL}- Remove or replace NVMe / RAID / Intel RST-VMD storage drivers.${NL}- Switch the SATA controller mode (RAID <-> AHCI) without an INACCESSIBLE_BOOT_DEVICE blue screen.${NL}- Uninstall a driver or program that crashes a normal boot.${NL}${NL}For an offline install the tool targets that install's own entry in its BCD store (bcdedit /store ... /set {guid} ...). In clone mode the boot menu shows the new entry; Windows usually waits about 30 seconds there.")
$btnSafeOff = New-Ctl 'Button' $tpSafe 300 128 230 30 'Remove Safe Mode flag'
Add-Help $tpSafe 536 131 'Remove Safe Mode' ("Edit mode: bcdedit /deletevalue {current} safeboot - returns the Target Windows to a normal boot.${NL}${NL}Clone mode: deletes only the clone entries created by this tool (matched by their exact name).")
$lblSafeInfo = New-Ctl 'Label' $tpSafe 12 172 920 48 'Uses the Target Windows chosen at the top. For an offline install, mount its EFI / System partition on the Mount tab so its boot store can be found. Every change is preceded by an automatic BCD backup in the data folder.'
$lblSafeInfo.ForeColor = 'DimGray'

# ---------- 6. Sysprep ----------
$rbA = New-Ctl 'RadioButton' $tpSys 12 15 640 22 'A.  Generalize:  sysprep /generalize /oobe /shutdown'
Add-Help $tpSys 660 14 'A - Generalize' ("%windir%\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown${NL}${NL}Strips machine-specific data (SID, hardware IDs) and shuts down. Next boot starts OOBE.${NL}${NL}Use cases:${NL}- Capture a master image to deploy to many PCs.${NL}- Create a template for virtual machines.${NL}- Move / translate an installation to different hardware.")
$chkVM = New-Ctl 'CheckBox' $tpSys 34 40 620 22 'Add /mode:vm  (VM deployment on the SAME hypervisor / virtual hardware)'
$chkVM.Enabled = $false
Add-Help $tpSys 660 39 'VM mode' ("Appends /mode:vm to option A.${NL}${NL}Skips hardware re-detection on first boot, so a generalized VHD/VM image starts much faster.${NL}${NL}Only valid with /generalize /oobe /shutdown, and only when the image is deployed to identical virtual hardware (same hypervisor, same VM configuration). For physical PCs or a different hypervisor leave it OFF.")
$rbB1 = New-Ctl 'RadioButton' $tpSys 12 74 640 22 'B1. Two-step, step 1 - Audit mode:  sysprep /audit /reboot'
Add-Help $tpSys 660 73 'B1 - Audit mode' ("%windir%\System32\Sysprep\sysprep.exe /audit /reboot${NL}${NL}Reboots into Audit mode (built-in Administrator, no OOBE) so you can customize before deployment.${NL}${NL}Use cases:${NL}- Install drivers, updates and software.${NL}- Prepare an image for another PC.${NL}- Remove or inject storage (NVMe / RAID) drivers before the move.")
$rbB2 = New-Ctl 'RadioButton' $tpSys 12 104 640 22 'B2. Two-step, step 2 - Deploy (OOBE):  sysprep /oobe /reboot'
Add-Help $tpSys 660 103 'B2 - Deploy (OOBE)' ("%windir%\System32\Sysprep\sysprep.exe /oobe /reboot${NL}${NL}Run this from Audit mode when customizing is finished. Reboots into the first-run experience (OOBE) where the end user creates their account.${NL}${NL}Use cases: finish a prepared install for a VM, a new PC, or the PC it was moved to.")
$chkUnatt = New-Ctl 'CheckBox' $tpSys 12 140 640 22 'Pass the answer file built on the Unattend tab to sysprep (/unattend:)'
Add-Help $tpSys 660 139 'Answer file' ("Builds the unattend.xml from the Unattend tab when you press Run and adds /unattend:<file> to the command (works with A, B1 and B2).${NL}${NL}Sysprep caches the answer file, so settings like 'skip OOBE screens', the local account, computer name and time zone are applied during the next specialize / OOBE pass.${NL}${NL}The file lives in your TEMP folder and holds the account password in a recoverable form - delete it afterwards.")
$chkAutoPre = New-Ctl 'CheckBox' $tpSys 12 166 640 22 'Also run the pre-flight checks automatically before each run (off by default)'
$lblDep = New-Ctl 'Label' $tpSys 12 196 900 48 'Only ONE option can be selected. Sysprep acts on the Windows you are running right now (not the Target Windows). Two-step mode: run B1 first, customize in Audit mode, then run B2. The commands are fixed and cannot be edited.'
$btnRun = New-Ctl 'Button' $tpSys 12 250 240 30 'Run selected command...'
$btnPre = New-Ctl 'Button' $tpSys 262 250 200 30 'Run pre-flight checks'
Add-Help $tpSys 468 253 'Pre-flight checks' ("Checks the running Windows for the usual reasons sysprep fails or does damage:${NL}- pending reboot, free disk space${NL}- in-place upgrade (unsupported for generalize)${NL}- domain join${NL}- BitLocker / device encryption (generalize fails while encrypted)${NL}- leftover unattend.xml files that conflict${NL}- Store apps installed for one user but not provisioned (the classic generalize failure)${NL}- last sysprep error log (Sysprep\Panther\setuperr.log)${NL}${NL}They never run on their own: use this button, or tick 'Also run the pre-flight checks automatically' to check before every run. Findings can be overridden with 'Continue anyway'.")
if ($IsWinPE) {
    foreach ($c in $rbA, $rbB1, $rbB2, $btnRun, $btnPre, $chkUnatt, $chkAutoPre) { $c.Enabled = $false }
    $lblDep.Text = 'Disabled in WinPE: Sysprep only works from inside the installed Windows. (The Unattend tab can still deploy an answer file to an offline install.)'
}

# ---------- 7. Unattend ----------
[void](New-Ctl 'Label' $tpUna 12 8 900 34 'Builds an answer file (unattend.xml). Tick only what you want; unticked options are left out of the file.')
$chkSkip = New-Ctl 'CheckBox' $tpUna 12 46 590 22 'Skip OOBE screens (EULA, online account, Wi-Fi, privacy, OEM registration)'; $chkSkip.Checked = $true
Add-Help $tpUna 612 45 'Skip OOBE screens' ("Hides the first-run screens (HideEULAPage, HideOnlineAccountScreens, HideLocalAccountScreen, HideWirelessSetupInOOBE, HideOEMRegistrationScreen, ProtectYourPC=3).${NL}${NL}This is the 'skip user creation' switch: nobody is asked to create an account. Because that leaves no way to sign in, it requires 'Create local account' below.${NL}${NL}Use cases: unattended VM and PC deployment, lab machines, hands-off image rollouts.")
$chkUser = New-Ctl 'CheckBox' $tpUna 12 76 300 22 'Create local account'; $chkUser.Checked = $true
Add-Help $tpUna 612 75 'Local account' ("Creates a local account during OOBE (LocalAccounts in the oobeSystem pass).${NL}${NL}The password is stored base64-encoded, which is obfuscation, not encryption: anyone who can read the file can recover it. Delete the file after use.${NL}${NL}'Password never expires' adds a first-logon command (Set-LocalUser -PasswordNeverExpires).")
[void](New-Ctl 'Label' $tpUna 36 106 50 20 'Name')
$txtUser = New-Ctl 'TextBox' $tpUna 90 103 160 24; $txtUser.Text = 'User'
[void](New-Ctl 'Label' $tpUna 262 106 65 20 'Password')
$txtPass = New-Ctl 'TextBox' $tpUna 330 103 150 24; $txtPass.UseSystemPasswordChar = $true
$chkShowPw = New-Ctl 'CheckBox' $tpUna 488 104 100 22 'Show'
[void](New-Ctl 'Label' $tpUna 36 136 50 20 'Group')
$cmbGroup = New-Ctl 'ComboBox' $tpUna 90 133 160 24
[void]$cmbGroup.Items.Add('Administrators'); [void]$cmbGroup.Items.Add('Users'); $cmbGroup.SelectedIndex = 0
$chkNoExp = New-Ctl 'CheckBox' $tpUna 262 134 330 22 'Password never expires'
$chkLogon = New-Ctl 'CheckBox' $tpUna 36 164 560 22 'Auto-logon once after setup (uses the account above)'
$chkPC  = New-Ctl 'CheckBox' $tpUna 12 196 200 22 'Set computer name'
$txtPC  = New-Ctl 'TextBox' $tpUna 215 193 150 24; $txtPC.Text = '*'
[void](New-Ctl 'Label' $tpUna 372 197 270 20 '*  =  random name')
$chkRegion = New-Ctl 'CheckBox' $tpUna 12 226 330 22 'Set time zone and language'
[void](New-Ctl 'Label' $tpUna 36 256 70 20 'Time zone')
$cmbTz  = New-Ctl 'ComboBox' $tpUna 110 253 300 24
[void](New-Ctl 'Label' $tpUna 420 256 50 20 'Locale')
$txtLoc = New-Ctl 'TextBox' $tpUna 475 253 80 24
$btnUPrev   = New-Ctl 'Button' $tpUna 12 296 110 30 'Preview XML'
$btnUSave   = New-Ctl 'Button' $tpUna 130 296 130 30 'Save as...'
$btnUDeploy = New-Ctl 'Button' $tpUna 268 296 230 30 'Deploy to Target Windows'
Add-Help $tpUna 504 299 'Deploy answer file' ("Writes the file to <Target Windows>\Windows\Panther\Unattend\unattend.xml (an existing file is backed up first). Windows Setup looks there during the specialize and OOBE passes.${NL}${NL}It only has an effect on an install that is about to go through specialize / OOBE (after sysprep /generalize, or on a fresh image). On an install that already finished OOBE it does nothing until it is sysprepped.${NL}${NL}Alternative: tick 'Pass the answer file to sysprep' on the Sysprep tab instead.")
[void](New-Ctl 'Label' $tpUna 12 338 900 60 'Passwords in an answer file are only obfuscated (base64), not encrypted. Delete the file after use. The file is built for this PC''s processor architecture; the target install must match.')

# ---------- 8. Recovery (experimental) ----------
$lblExp = New-Ctl 'Label' $tpRec 12 10 920 36 'EXPERIMENTAL: these tools are untested on your hardware and can change boot configuration or disk contents. Back up first (BCD backup tool below).'
$lblExp.ForeColor = 'Red'; $lblExp.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
[void](New-Ctl 'Label' $tpRec 12 56 100 20 'Boot partition')
$cmbEsp = New-Ctl 'ComboBox' $tpRec 115 53 600 24; $cmbEsp.DisplayMember = 'Text'
$btnEspRefresh = New-Ctl 'Button' $tpRec 722 52 95 26 'Refresh'
[void](New-Ctl 'Label' $tpRec 12 90 100 20 'Tool')
$cmbTool = New-Ctl 'ComboBox' $tpRec 115 87 600 24; $cmbTool.DisplayMember = 'Name'
foreach ($t in $Tools) { [void]$cmbTool.Items.Add($t) }
$btnToolHelp = New-Ctl 'Button' $tpRec 721 86 24 24 '?'
$lblToolDesc = New-Ctl 'Label' $tpRec 12 124 920 60
$lblToolNote = New-Ctl 'Label' $tpRec 12 190 920 36 'Tools use the Target Windows chosen at the top and (where needed) the boot partition above. On the running Windows, sfc / DISM / driver tools switch to their online forms. Long jobs open their own console window.'
$lblToolNote.ForeColor = 'DimGray'
$btnTool = New-Ctl 'Button' $tpRec 12 236 240 30 'Run selected tool...'
# BETA: per-task log monitors and a pass / fail summary
$chkTaskMon = New-Ctl 'CheckBox' $tpRec 270 240 230 22 'Monitor this task''s logs'
$chkTaskSum = New-Ctl 'CheckBox' $tpRec 505 240 330 22 'Show a pass / fail summary when it ends'
$chkTaskSum.Checked = $true
Add-Help $tpRec 840 239 'BETA: monitor and summary' ("Monitor this task's logs: opens a live window for each log the selected tool writes while it runs, for example CBS.log ([SR] lines) for sfc and dism.log for DISM. Close those windows when you are done.${NL}${NL}Show a pass / fail summary: when the tool finishes, a window shows whether the task ran to the end (PASSED / FAILED) and what it found - for example 'NO CORRUPTION DETECTED', 'CORRUPTION DETECTED - FIX WORKED' or 'FIX DID NOT WORK' - quoting the tool's own result message. The full output is saved in WinSuperTool-Data\Task-Results.${NL}${NL}How it works: the task's console window runs the command as before; when it ends, the window reads back what the command printed and hands it to this window. With the summary on, the task opens in a classic console window so the whole output can be read back.${NL}${NL}Result messages are matched in English. On another display language the summary uses the exit code instead.${NL}${NL}BETA: new in 1.9 beta 1 and only lightly tested. Greyed out when the selected tool has no logs to watch or no result to summarize (the BCD and boot-menu tools show their own result).")
$lblBeta = New-Ctl 'Label' $tpRec 12 276 920 36 'BETA 1.9: new scan-only tools (sfc /verifyonly, DISM check health and scan health), live log windows per task, and a pass / fail summary that quotes the tool''s own result message.'
$lblBeta.ForeColor = [Drawing.Color]::FromArgb(200, 110, 0)

# ---------- 9. System Info (BETA) ----------
$lblInfo = New-Ctl 'Label' $tpInfo 12 8 930 20 'System information - each button opens an easy-to-read window (Copy all / Save as... at the bottom). Nothing is changed.'
$lblInfo.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
function New-InfoButton($text, [scriptblock]$do, $tipText) { [pscustomobject]@{ Text = $text; Do = $do; Tip = $tipText } }
$InfoButtons = @(
    New-InfoButton 'Wi-Fi networks and passwords'     { Show-Info 'Wi-Fi networks and passwords' (Invoke-Busy 'Wi-Fi networks' { Get-WifiInfo }) 'Passwords are shown in plain text. Close this window before anyone else can see the screen.' } 'Saved Wi-Fi networks with their passwords, the one connected now, and the networks in range.'
    New-InfoButton 'Windows version and product keys' { Show-Info 'Windows version and product keys' (Invoke-Busy 'Windows version' { Get-WindowsInfo }) } 'Edition, release (for example 24H2), full build number, installed key, motherboard (firmware) key and activation.'
    New-InfoButton 'Network connections (IP, MAC)'    { Show-Info 'Network connections' (Invoke-Busy 'network' { Get-NetInfo }) 'Connected adapters first; the one used for internet is marked.' } 'Every adapter in order: connected first, with IP addresses, gateway, DNS, DHCP, MAC address, type and Wi-Fi details.'
    New-InfoButton 'Bluetooth devices'                { Show-Info 'Bluetooth devices' (Invoke-Busy 'Bluetooth' { Get-BtInfo }) } 'The Bluetooth adapter and every paired device with its MAC address, connected ones first.'
    New-InfoButton 'Video cards and drivers'          { Show-Info 'Video cards and drivers' (Invoke-Busy 'video' { Get-GpuInfo }) } 'Graphics cards with driver version and date, video memory, current resolution, and the monitors.'
    New-InfoButton 'Audio devices and drivers'        { Show-Info 'Audio devices and drivers' (Invoke-Busy 'audio' { Get-AudioInfo }) } 'Speakers and microphones with the DEFAULT ones marked, plus the sound hardware and driver versions.'
    New-InfoButton 'Everything in one report'         { Show-Info 'Full system report' (Invoke-Busy 'full report' { @(Get-WindowsInfo) + @(Get-NetInfo) + @(Get-GpuInfo) + @(Get-AudioInfo) + @(Get-BtInfo) + @(Get-WifiInfo) }) 'Contains Wi-Fi passwords and product keys. Keep a saved copy private.' } 'All of the above in one window (use Save as... to keep it).'
)
$i = 0
foreach ($ib in $InfoButtons) {
    $x = 12 + ($i % 4) * 232; $y = 34 + [Math]::Floor($i / 4) * 40
    $bt = New-Ctl 'Button' $tpInfo $x $y 226 34 $ib.Text
    $bt.Tag = $ib.Do; $tip.SetToolTip($bt, $ib.Tip)
    $bt.Add_Click({ $sb = $this.Tag; Safe { & $sb } })
    $i++
}
$lblTools = New-Ctl 'Label' $tpInfo 12 122 930 20 'Windows tools - opens the built-in tool (greyed out when it is not part of this Windows edition):'
$lblTools.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$i = 0
foreach ($wt in $WinTools) {
    $x = 12 + ($i % 5) * 186; $y = 146 + [Math]::Floor($i / 5) * 30
    $bt = New-Ctl 'Button' $tpInfo $x $y 182 27 $wt.Name
    $bt.Tag = $wt; $tip.SetToolTip($bt, $wt.Tip)
    if (-not (Test-WinTool $wt)) { $bt.Enabled = $false; $tip.SetToolTip($bt, $wt.Tip + ' - not available on this PC.') }
    $bt.Add_Click({ $t = $this.Tag; Safe { Start-WinTool $t } })
    $i++
}

# ---------- 10. Automation (BETA) ----------
$lblAutoHead = New-Ctl 'Label' $tpAuto 12 6 930 32 'BETA - run up to 10 tasks one after another on THIS PC. Each task opens its own window (it closes 15 seconds after the task ends) and gets a pass / fail result; a final summary lists them all.'
$lblAutoHead.ForeColor = [Drawing.Color]::FromArgb(200, 110, 0)
[void](New-Ctl 'Label' $tpAuto 12 42 300 18 'Available tasks (double-click to add):')
$lstAutoCat = New-Ctl 'ListBox' $tpAuto 12 62 300 240; $lstAutoCat.DisplayMember = 'Name'; $lstAutoCat.HorizontalScrollbar = $true
foreach ($c in $AutoCatalog) { [void]$lstAutoCat.Items.Add($c) }
$lblAutoHelp = New-Ctl 'Label' $tpAuto 12 306 300 64 ''; $lblAutoHelp.ForeColor = 'DimGray'
$btnAutoAdd = New-Ctl 'Button' $tpAuto 318 150 72 30 'Add >'
[void](New-Ctl 'Label' $tpAuto 12 378 60 20 'Preset:')
$cmbAutoPreset = New-Ctl 'ComboBox' $tpAuto 62 375 250 24
foreach ($k in $AutoPresets.Keys) { [void]$cmbAutoPreset.Items.Add($k) }; $cmbAutoPreset.SelectedIndex = 0; $cmbAutoPreset.DropDownWidth = 320
$btnAutoPreset = New-Ctl 'Button' $tpAuto 318 374 72 26 'Load'
$tip.SetToolTip($btnAutoPreset, 'Replaces the queue with the chosen preset (you can still change it).')
[void](New-Ctl 'Label' $tpAuto 398 42 260 18 'Queue - runs from top to bottom:')
$lblAutoCount = New-Ctl 'Label' $tpAuto 760 42 182 18 ''; $lblAutoCount.TextAlign = 'TopRight'
$lvAuto = New-Object Windows.Forms.ListView
$lvAuto.Location = New-Object Drawing.Point(398, 62); $lvAuto.Size = New-Object Drawing.Size(544, 240)
$lvAuto.View = 'Details'; $lvAuto.FullRowSelect = $true; $lvAuto.HideSelection = $false; $lvAuto.MultiSelect = $false; $lvAuto.GridLines = $true
foreach ($col in @(@('#', 30), @('Task', 230), @('Status', 66), @('Result', 160), @('Time', 50))) { [void]$lvAuto.Columns.Add($col[0], $col[1]) }
$tpAuto.Controls.Add($lvAuto)
$btnAutoUp     = New-Ctl 'Button' $tpAuto 398 306 90 26 'Move up'
$btnAutoDown   = New-Ctl 'Button' $tpAuto 492 306 90 26 'Move down'
$btnAutoRemove = New-Ctl 'Button' $tpAuto 586 306 90 26 'Remove'
$btnAutoClear  = New-Ctl 'Button' $tpAuto 680 306 90 26 'Clear'
$chkAutoPop  = New-Ctl 'CheckBox' $tpAuto 398 338 270 22 'Pop up a summary after each task'; $chkAutoPop.Checked = $true
$chkAutoStop = New-Ctl 'CheckBox' $tpAuto 672 338 270 22 'Stop the queue if a task does not pass'
$chkAutoMon  = New-Ctl 'CheckBox' $tpAuto 398 362 270 22 'Open live log windows for each task'
$chkAutoSR   = New-Ctl 'CheckBox' $tpAuto 672 362 270 22 'Turn on System Protection if it is off'
$tip.SetToolTip($chkAutoSR, 'For "Create a system restore point": turns System Protection on for the system drive first (Enable-ComputerRestore).')
$chkAutoHtml = New-Ctl 'CheckBox' $tpAuto 12 408 300 22 'Save an HTML report and open it at the end'; $chkAutoHtml.Checked = $true
$tip.SetToolTip($chkAutoHtml, 'An easy-to-read report: overall result and a colour-coded summary table at the top, every task''s details and full output below. Saved in WinSuperTool-Data\Task-Results.')
$btnAutoHtml = New-Ctl 'Button' $tpAuto 12 432 180 26 'Open last HTML report'
$chkAutoHtml.Anchor = 'Bottom,Left'; $btnAutoHtml.Anchor = 'Bottom,Left'
$btnAutoStart   = New-Ctl 'Button' $tpAuto 398 394 170 34 'Start queue'
$btnAutoStart.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$btnAutoStopReq = New-Ctl 'Button' $tpAuto 574 394 170 34 'Stop after this task'; $btnAutoStopReq.Enabled = $false
$lblAutoStatus  = New-Ctl 'Label' $tpAuto 750 392 192 44 ''
if ($IsWinPE) { $lblAutoStatus.Text = 'Automation needs a running Windows - not available in WinPE.'; $lblAutoStatus.ForeColor = 'Red' }

# ---------- resizing (1.8.1): what grows with the window and what stays at the right edge ----------
function Set-Anchor([string]$a, [object[]]$ctls) { foreach ($c in $ctls) { if ($c) { $c.Anchor = $a } } }
function Get-HelpBtn($parent, [int]$maxTop) { @($parent.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '?' -and $_.Top -le $maxTop }) }
Set-Anchor 'Top,Left,Right'        @($cmbWin, $lblWarn)
Set-Anchor 'Top,Right'             (@($btnRescan, $btnRunPs, $btnData) + (Get-HelpBtn $form 20))
Set-Anchor 'Top,Left,Right'        @($txtColOut, $lblColInfo)
Set-Anchor 'Top,Right'             (@($btnColBrowse, $btnColDefault) + (Get-HelpBtn $tpCol 20))
Set-Anchor 'Top,Bottom,Left,Right' @($txtCol, $monPanel)
Set-Anchor 'Top,Right'             (Get-HelpBtn $tpMon 20)
Set-Anchor 'Bottom,Left'           (@($lblPaste, $numTail, $btnMonLaunch, $btnMonBrowse, $btnMonClear, $btnMonClose) + @($tpMon.Controls | Where-Object { $_.Text -eq 'Tail lines:' }))
Set-Anchor 'Bottom,Left,Right'     @($txtPaste, $lblMonStatus)
Set-Anchor 'Bottom,Right'          @($btnPaste, $btnPasteClear)
Set-Anchor 'Top,Left,Right'        @($cmbDisk, $cmbPart, $lstMounts, $lblBcd, $lblSafeInfo, $lblDep, $lblExp, $cmbEsp, $cmbTool, $lblToolDesc, $lblToolNote)
Set-Anchor 'Top,Right'             @($btnRefresh, $btnUnmount, $btnUnmountAll, $btnEspRefresh, $btnToolHelp)
Set-Anchor 'Top,Left,Right'        @($lblBeta, $lblAutoHead)
Set-Anchor 'Top,Bottom,Left'       @($lstAutoCat)
Set-Anchor 'Top,Bottom,Left,Right' @($lvAuto)
Set-Anchor 'Top,Right'             @($lblAutoCount)
Set-Anchor 'Bottom,Left'           (@($lblAutoHelp, $cmbAutoPreset, $btnAutoPreset, $btnAutoUp, $btnAutoDown, $btnAutoRemove, $btnAutoClear, $chkAutoPop, $chkAutoStop, $chkAutoMon, $chkAutoSR, $btnAutoStart, $btnAutoStopReq) + @($tpAuto.Controls | Where-Object { $_.Text -eq 'Preset:' }))
Set-Anchor 'Bottom,Left,Right'     @($lblAutoStatus)
# Widen the top-right buttons when their text does not fit (large fonts or display scaling), keeping them right-aligned.
function Update-TopBar {
    $k = Get-WrtScale $form; $right = $form.ClientSize.Width - [int](8 * $k); $gap = [int](4 * $k)
    foreach ($b in @($btnData, $btnRunPs, (Get-HelpBtn $form 20)[0], $btnRescan)) {
        if (-not $b) { continue }
        $need = [Windows.Forms.TextRenderer]::MeasureText($b.Text, $b.Font).Width + [int](18 * $k)
        if ($b.Width -lt $need) { $b.Width = $need }
        $b.Left = $right - $b.Width; $right = $b.Left - $gap
    }
    $cmbWin.Width = [Math]::Max([int](150 * $k), $right - $cmbWin.Left - $gap)
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250

# =====================================================================
#  EVENTS
# =====================================================================
# ---- top bar ----
$btnRescan.Add_Click({ Safe { Update-Windows $true; Update-Esp } })
$cmbWin.Add_SelectedIndexChanged({ Safe { Update-SafeStatus } })
$btnRunPs.Add_Click({ Safe { Show-ScriptRunner } })
$btnData.Add_Click({ Open-Folder $DataDir })

# ---- 1. Collect Logs ----
$btnColBrowse.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = 'Folder for the collected logs'
    if ($d.ShowDialog() -eq 'OK') { $txtColOut.Text = Join-Path $d.SelectedPath 'logs' }
})
$btnColDefault.Add_Click({ $txtColOut.Text = Get-DefaultLogRoot })
$btnColAll.Add_Click({
    $any = @($colBoxes.Values | Where-Object { -not $_.Checked }).Count -gt 0
    foreach ($b in $colBoxes.Values) { $b.Checked = $any }
})
$btnColOpen.Add_Click({
    $p = [Environment]::ExpandEnvironmentVariables($txtColOut.Text.Trim().Trim('"'))
    if ($p -and (Test-Path -LiteralPath $p)) { Open-Folder $p } else { Msg 'That folder does not exist yet. Collect logs first.' }
})
$btnColGo.Add_Click({ Safe {
    $t = Get-TargetWin
    if (-not $t) { Msg 'Select the Target Windows at the top first.' 'Collect logs' 'Warning'; return }
    $sel = @($Collectors.Keys | Where-Object { $colBoxes[$_].Checked })
    if (-not $sel.Count) { Msg 'Tick at least one item.' 'Collect logs' 'Warning'; return }
    $root = [Environment]::ExpandEnvironmentVariables($txtColOut.Text.Trim().Trim('"'))
    if (-not $root) { $root = Get-DefaultLogRoot; $txtColOut.Text = $root }
    if (-not [IO.Path]::IsPathRooted($root)) { Msg 'Enter a full output folder path (for example D:\logs).' 'Collect logs' 'Warning'; return }
    $root = [IO.Path]::GetFullPath($root)
    if ($root.StartsWith(($t.Drive + '\Windows'), [StringComparison]::OrdinalIgnoreCase)) { Msg 'Pick an output folder outside the Windows folder you are collecting from.' 'Collect logs' 'Warning'; return }
    if ($IsWinPE -and $root.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Ask "The output folder is on the WinPE RAM disk ($env:SystemDrive) and is lost at reboot.${NL}${NL}Continue anyway?" 'Collect logs' 'Warning' 'Button2')) { return }
    }
    [void][IO.Directory]::CreateDirectory($root)
    # while copying, closing the tool (auto-unmount!) and switching tabs (Mount / Rescan) are refused - see FormClosing / Selecting
    $script:Busy = 'Log collection'
    $btnColGo.Enabled = $false; $btnColAll.Enabled = $false; $form.Cursor = 'WaitCursor'
    $script:ColCount = 0; $script:ColFail = 0
    $txtCol.Clear()
    $mode = 'OFFLINE install'; if ($t.Running) { $mode = 'running Windows' }
    Say "Started $(Get-Date)  ->  $root"
    Say "Target: $($t.Text)  ($mode)"
    try {
        foreach ($k in $sel) {
            Say ($NL + "[$k] " + $Collectors[$k].Label)
            try { & $Collectors[$k].Run $t.Drive ([bool]$t.Running) $root $ColUser.Profile } catch { Say "   ERROR: $($_.Exception.Message)" }
        }
    } finally { $script:Busy = $null; $btnColGo.Enabled = $true; $btnColAll.Enabled = $true; $form.Cursor = 'Default' }
    Say ($NL + "Done. Files copied/exported: $($script:ColCount)   Failed: $($script:ColFail)")
    try { [IO.File]::WriteAllText((Join-Path $root '_collection_summary.txt'), $txtCol.Text) } catch {}
    $script:LastCollect = $root
    Log "Logs collected from $($t.Drive) to $root ($($script:ColCount) files, $($script:ColFail) failed)."
    Open-Folder $root
} })

# ---- 2. Live Monitor ----
$btnMonLaunch.Add_Click({ Safe {
    $sel = @($monChecks | Where-Object { $_.Checked })
    if (-not $sel.Count) { Msg 'Tick at least one log first.' 'Live monitor' 'Warning'; return }
    foreach ($c in $sel) { Start-Monitor $c.Tag ([int]$numTail.Value); Start-Sleep -Milliseconds 200 }
    Update-MonStatus "Launched $($sel.Count) monitor(s)."
} })
$btnMonBrowse.Add_Click({ Safe {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose a text log file to monitor'
    $dlg.Filter = 'Log/text files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        Start-Monitor (New-MonItem 'Custom' (Split-Path $dlg.FileName -Leaf) 'File' $dlg.FileName) ([int]$numTail.Value)
        Update-MonStatus "Launched: $($dlg.FileName)."
    }
} })
$btnPaste.Add_Click({ Safe {
    $launched = 0; $notes = @()
    foreach ($line in ($txtPaste.Text -split "`r?`n")) {
        $p = $line.Trim().Trim('"').Trim("'").Trim()
        if (-not $p) { continue }
        $p = [Environment]::ExpandEnvironmentVariables($p)
        if ($p -match '\.evtx$') { $notes += "Skipped (.evtx can't be tailed as text - use the Event Viewer section): $p"; continue }
        $name = Split-Path $p -Leaf
        if (-not $name) { $name = $p }
        $type = 'File'; if (Test-Path -LiteralPath $p -PathType Container) { $type = 'Dir' }
        Start-Monitor (New-MonItem 'Pasted' $name $type $p) ([int]$numTail.Value)
        $launched++
        if (-not (Test-Path -LiteralPath $p)) { $notes += "Not found yet (its window waits for it): $p" }
        Start-Sleep -Milliseconds 200
    }
    if (-not $launched -and -not $notes.Count) { Msg 'Paste at least one path first.' 'Live monitor' 'Warning'; return }
    $extra = ''; if ($notes.Count) { $extra = '  ' + ($notes -join ' | ') }
    Update-MonStatus ("Launched $launched pasted monitor(s)." + $extra)
} })
$btnPasteClear.Add_Click({ $txtPaste.Clear() })
$btnMonClear.Add_Click({ foreach ($c in $monChecks) { $c.Checked = $false } })
$btnMonClose.Add_Click({
    foreach ($p in $script:MonProcs) { try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch {} }
    $script:MonProcs.Clear()
    Update-MonStatus 'All monitor windows closed.'
})


# ---- shared timer: finished task windows (Recovery summaries, Automation) ----
$timer.Add_Tick({
    try { if ($script:TaskWatch.Count -and -not $script:InSummary) { Update-TaskWatch } }
    catch { if (-not $script:TickErr2) { $script:TickErr2 = $true; Log "Timer error (task windows): $($_.Exception.Message)" } }
})

# ---- 4. Mount ----
$cmbDisk.Add_SelectedIndexChanged({ Safe { Update-Parts } })
$rbStor.Add_CheckedChanged({ Safe { Update-Disks } })
$btnRefresh.Add_Click({ Safe { Update-Disks; Update-Letters; Update-Windows; Update-Esp } })
$btnMount.Add_Click({ Safe {
    $d = $cmbDisk.SelectedItem; $p = $cmbPart.SelectedItem; $L = [string]$cmbLetter.SelectedItem
    if (-not $d -or -not $p -or -not $L) { Msg 'Select a disk, a partition and a free letter first.'; return }
    $cur = Get-PartLetter $d.Num $p.Num
    if ($cur -eq 'NOVOLUME') { Msg 'This partition has no mountable volume (e.g. MSR / reserved).' 'Cannot mount' 'Warning'; return }
    if ($cur) { Msg "This partition is already mounted as ${cur}:." 'Already mounted' 'Information'; return }
    if (Test-LetterUsed $L) { Update-Letters; Msg "Letter ${L}: was just taken. Pick another." 'Letter in use' 'Warning'; return }
    if (Mount-Part $d.Num $p.Num $L) {
        [void]$script:Mounts.Add([pscustomobject]@{ Letter = $L; Disk = $d.Num; Partition = $p.Num })
        Log "Mounted disk $($d.Num) partition $($p.Num) as ${L}:"
        Update-AfterMountChange
    } else { Msg 'Mount failed. See the activity log.' 'Mount failed' 'Error' }
} })
$btnUnmount.Add_Click({ Safe {
    $i = $lstMounts.SelectedIndex
    if ($i -lt 0) { Msg 'Select a mounted entry in the list first.'; return }
    [void](Dismount-One $script:Mounts[$i])
    Update-AfterMountChange
} })
$btnUnmountAll.Add_Click({ Safe {
    foreach ($m in @($script:Mounts)) { [void](Dismount-One $m) }
    Update-AfterMountChange
} })

# ---- 5. Safe Mode ----
$rbClone.Add_CheckedChanged({ Safe { Update-SafeLabels; Update-SafeStatus } })
$btnSafeOn.Add_Click({ Safe {
    $w = Get-TargetWin; if (-not $w) { return }
    $t = Resolve-BcdTarget $w.Drive; if (-not $t) { Update-SafeStatus; return }
    if ($rbClone.Checked) {
        if (@(Get-Clones $t $w.Drive).Count) { Msg 'A Safe Mode clone for this install already exists.'; return }
        if (-not (Ask "Create a separate boot-menu entry 'Safe Mode (minimal)' for:${NL}${NL}$($w.Text)${NL}${NL}Your normal entry is not changed.")) { return }
        $r = Invoke-Bcd $t @('/copy', $t.Id, '/d', $CloneMarkers[0])
        if ($r.Rc -ne 0 -or $r.Out -notmatch '(\{[0-9a-fA-F-]{36}\})') { Msg 'Could not copy the boot entry. See the activity log.' 'Error' 'Error'; return }
        $new = $Matches[1]
        $r2 = Invoke-Bcd $t @('/set', $new, 'safeboot', 'minimal')
        if ($r2.Rc -ne 0) { [void](Invoke-Bcd $t @('/delete', $new)); Msg 'Could not set safeboot on the copy; the copy was removed. See the activity log.' 'Error' 'Error' }
        else { Confirm-BootMenuShown $t; Msg "Done. Choose 'Safe Mode (minimal)' in the boot menu on next start." }
    } else {
        if (-not (Ask "Enable Safe Mode (minimal) for:${NL}${NL}$($w.Text)${NL}${NL}It will boot into Safe Mode on every start until you remove the flag." 'Confirm' 'Warning' 'Button2')) { return }
        $r = Invoke-Bcd $t @('/set', $t.Id, 'safeboot', 'minimal')
        if ($r.Rc -ne 0) { Msg 'bcdedit reported an error. See the activity log.' 'Error' 'Error' }
    }
    Update-SafeStatus
} })
$btnSafeOff.Add_Click({ Safe {
    $w = Get-TargetWin; if (-not $w) { return }
    $t = Resolve-BcdTarget $w.Drive; if (-not $t) { Update-SafeStatus; return }
    if ($rbClone.Checked) {
        $cl = @(Get-Clones $t $w.Drive)
        if ($cl.Count -eq 0) { Msg 'No Safe Mode clone created by this tool was found for this install.'; return }
        if (-not (Ask "Delete $($cl.Count) Safe Mode clone entry(ies) for:${NL}${NL}$($w.Text)")) { return }
        $bad = @($cl | Where-Object { (Invoke-Bcd $t @('/delete', $_.Id)).Rc -ne 0 })
        if ($bad.Count) { Msg "$($bad.Count) clone(s) could not be deleted. See the activity log." 'Error' 'Error' }
    } else {
        if (-not (Ask "Remove the Safe Mode flag for:${NL}${NL}$($w.Text)")) { return }
        $r = Invoke-Bcd $t @('/deletevalue', $t.Id, 'safeboot')
        if ($r.Rc -ne 0) { Msg 'bcdedit reported an error (the flag may not be set). See the activity log.' 'Notice' 'Warning' }
    }
    Update-SafeStatus
} })

# ---- 6. Sysprep ----
$rbA.Add_CheckedChanged({ $chkVM.Enabled = $rbA.Checked; if (-not $rbA.Checked) { $chkVM.Checked = $false } })
$btnPre.Add_Click({ Safe {
    $mode = 'A'; if ($rbB1.Checked) { $mode = 'B1' } elseif ($rbB2.Checked) { $mode = 'B2' }
    [void](Show-Report "Sysprep pre-flight checks (mode $mode)" (Format-Preflight @(Get-Preflight $mode)))
} })
$btnRun.Add_Click({ Safe {
    if ($rbA.Checked) {
        $mode = 'A'; $sArgs = '/generalize /oobe /shutdown'
        $warn = "GENERALIZE removes the machine identity (SID, hardware-specific data) from THIS Windows and SHUTS DOWN.${NL}The next boot starts OOBE.${NL}${NL}- Back up / snapshot first.${NL}- Do not use on a PC you are not ready to reset (not for domain-joined production PCs).${NL}- User-installed Store apps can make generalize fail."
        if ($chkVM.Checked) { $sArgs += ' /mode:vm'; $warn += "${NL}${NL}VM MODE: the image must be deployed to identical virtual hardware on the same hypervisor, otherwise it may fail to boot." }
    } elseif ($rbB1.Checked) {
        $mode = 'B1'; $sArgs = '/audit /reboot'
        $warn = "This REBOOTS THIS PC into Audit mode (built-in Administrator, no OOBE).${NL}Close all work first. When customizing is done, run B2."
    } elseif ($rbB2.Checked) {
        $mode = 'B2'; $sArgs = '/oobe /reboot'
        $warn = "Run this only from Audit mode when customizing is FINISHED.${NL}This REBOOTS into OOBE (first-run setup)."
    } else { Msg 'Select one of the three options first.'; return }
    $sp = Join-Path $env:windir 'System32\Sysprep\sysprep.exe'
    if (-not (Test-Path $sp)) { Msg 'sysprep.exe was not found on this system.' 'Error' 'Error'; return }
    if (Get-Process sysprep -ErrorAction SilentlyContinue) { Msg 'Sysprep is already running.' 'Busy' 'Warning'; return }
    if ($chkAutoPre.Checked) {
        $pf = @(Get-Preflight $mode)
        if (@($pf | Where-Object { $_.Level -eq 'WARN' -or $_.Level -eq 'FAIL' }).Count) {
            if (-not (Show-Report 'Pre-flight checks - issues found' (Format-Preflight $pf) $true)) { return }
        }
    }
    if ($chkUnatt.Checked) {
        $xml = Build-Unattend; if (-not $xml) { return }
        $uf = Join-Path $env:TEMP 'WinSuperTool_unattend.xml'
        Write-Xml $uf $xml
        $sArgs += " /unattend:`"$uf`""
        $warn += "${NL}${NL}ANSWER FILE: $uf is passed with /unattend. It holds the account password in a recoverable form - delete it afterwards."
    }
    if (-not (Ask "$warn${NL}${NL}Command:${NL}$sp $sArgs${NL}${NL}Continue?" 'WARNING - Sysprep' 'Warning' 'Button2')) { return }
    Log "sysprep $sArgs"
    Start-Process -FilePath $sp -ArgumentList $sArgs
} })

# ---- 7. Unattend ----
$chkUser.Add_CheckedChanged({ Update-UnattendUi })
$chkPC.Add_CheckedChanged({ Update-UnattendUi })
$chkRegion.Add_CheckedChanged({ Update-UnattendUi })
$chkShowPw.Add_CheckedChanged({ $txtPass.UseSystemPasswordChar = -not $chkShowPw.Checked })
$btnUPrev.Add_Click({ Safe {
    $x = Build-Unattend
    if ($x) { [void](Show-Report 'unattend.xml preview (password is only base64-obfuscated)' $x) }
} })
$btnUSave.Add_Click({ Safe {
    $x = Build-Unattend; if (-not $x) { return }
    $d = New-Object Windows.Forms.SaveFileDialog
    $d.FileName = 'unattend.xml'; $d.Filter = 'XML file (*.xml)|*.xml'; $d.InitialDirectory = $DataDir
    if ($d.ShowDialog() -eq 'OK') { Write-Xml $d.FileName $x; Log "Answer file saved: $($d.FileName)" }
} })
$btnUDeploy.Add_Click({ Safe {
    $w = Get-TargetWin
    if (-not $w) { Msg 'Select the Target Windows at the top first.' 'Unattend' 'Warning'; return }
    $x = Build-Unattend; if (-not $x) { return }
    $dest = "$($w.Drive)\Windows\Panther\Unattend\unattend.xml"
    if (-not (Ask "Write the answer file to:${NL}$dest${NL}${NL}for $($w.Text)${NL}${NL}An existing file is backed up first. Continue?" 'Deploy answer file')) { return }
    # -ErrorAction Stop: if the existing answer file cannot be backed up, do NOT overwrite it (Safe shows the error)
    if ([IO.File]::Exists($dest)) { Copy-Item -LiteralPath $dest -Destination ('{0}.bak_{1}' -f $dest, (Get-Date -Format yyyyMMdd_HHmmss)) -ErrorAction Stop }
    Write-Xml $dest $x
    Log "Answer file deployed: $dest"
    Msg "Deployed to $dest"
} })

# ---- 8. Recovery ----
$btnEspRefresh.Add_Click({ Safe { Update-Esp } })
$cmbTool.Add_SelectedIndexChanged({
    $t = $cmbTool.SelectedItem
    if ($t) { $lblToolDesc.Text = ($t.Help -split "`r?`n")[0]; $tip.SetToolTip($btnToolHelp, $t.Help) }
    # BETA: only offer what the tool supports
    $chkTaskMon.Enabled = [bool]($t -and @($t.Logs).Count -and $t.Logs)
    $chkTaskSum.Enabled = [bool]($t -and $t.Kind)
    $logs = if ($chkTaskMon.Enabled) { 'Opens live windows for: ' + (@($t.Logs) -join ', ') } else { 'This tool writes no log that can be watched live.' }
    $tip.SetToolTip($chkTaskMon, $logs)
    $tip.SetToolTip($chkTaskSum, $(if ($chkTaskSum.Enabled) { 'Shows PASSED / FAILED and what the tool found, in its own words, when it ends.' } else { 'This tool shows its own result message.' }))
})
$btnToolHelp.Add_Click({ $t = $cmbTool.SelectedItem; if ($t) { Msg $t.Help $t.Name 'Information' } })
$btnTool.Add_Click({ Safe {
    $tool = $cmbTool.SelectedItem; if (-not $tool) { Msg 'Select a tool first.'; return }
    $w = Get-TargetWin; $e = $cmbEsp.SelectedItem
    if (($tool.Needs -eq 'install' -or $tool.Needs -eq 'both') -and -not $w) { Msg 'Select the Target Windows at the top first.' 'Recovery' 'Warning'; return }
    if ($tool.Needs -eq 'both' -and -not $e) { Msg 'Select the boot partition on this tab first.' 'Recovery' 'Warning'; return }
    $ctx = @{ Win = ''; Live = $false; Esp = ''; EspFS = '' }
    if ($w) { $ctx.Win = $w.Drive; $ctx.Live = [bool]$w.Running }
    if ($e) { $ctx.Esp = $e.Drive; $ctx.EspFS = $e.FS }
    if ($tool.Build) {
        $def = & $tool.Build $ctx $tool
        if (-not $def) { return }
    } else {
        $res = @(& $tool.Argv $ctx)
        $exe = $tool.Exe
        if ($res.Count -eq 1 -and $res[0] -is [hashtable]) { $exe = $res[0].Exe; $a = @($res[0].Args) } else { $a = $res }
        if ($a.Count -eq 0) { return }
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
            $hint = ''; if ($exe -eq 'bootrec.exe') { $hint = "${NL}${NL}bootrec ships with WinRE (the recovery environment) and is missing from many WinPE builds. Use 'Rebuild boot files (bcdboot)' instead." }
            Msg "$exe is not available in this environment.$hint" 'Not available' 'Warning'; return
        }
        $line = $exe + ' ' + (($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
        $def = @{ Summary = $line; Exe = $exe; Argv = $a; Window = $tool.Window; Line = $line }
    }
    $q = "EXPERIMENTAL - $($tool.Name)${NL}${NL}$($def.Summary)${NL}${NL}This tool is experimental and untested on your hardware. It may change boot configuration or disk contents. Continue?"
    if (-not (Ask $q 'EXPERIMENTAL - confirm' 'Warning' 'Button2')) { return }
    Log "TOOL: $($tool.Name)"
    # bcdboot and bootrec /rebuildbcd change the BCD too: back it up first, like every bcdedit change
    if ($w -and ($def.Exe -eq 'bcdboot.exe' -or ($def.Exe -eq 'bootrec.exe' -and @($def.Argv) -contains '/rebuildbcd'))) {
        $bt = Resolve-BcdTarget $w.Drive
        if (-not $bt) { Log 'No existing BCD entry found for this install - nothing to back up first.' }
        elseif (-not (Backup-Bcd $bt) -and -not (Ask "The BCD backup failed (see the activity log).${NL}${NL}Run $($def.Exe) anyway?" 'Recovery' 'Warning' 'Button2')) { return }
    }
    # BETA: per-task options (only for tools that support them; script tools such as the BCD ones show their own result)
    $wantMon = $chkTaskMon.Enabled -and $chkTaskMon.Checked -and -not $def.Run
    $wantSum = $chkTaskSum.Enabled -and $chkTaskSum.Checked -and [bool]$tool.Kind -and -not $def.Run
    if ($wantMon) { if ((Start-TaskMonitors $tool) -eq 0) { Log "No log to monitor for $($tool.Name)." } }
    if ($def.Run) { & $def.Run $def.RunArg }
    elseif ($def.Window) {
        # PowerShell console with every argument single-quoted: no cmd.exe parsing, so & ^ % ( ) in paths are safe
        Log $def.Line
        $call = Get-ExeCall $def.Exe @($def.Argv)
        if ($wantSum) {
            $resFile = Start-TaskWindow $tool.Name $tool.Kind $def.Line $call
            Log "Summary on: the summary opens when the task ends. Output: $resFile"
        } else {
            $cmd = $call + "`r`nWrite-Host ''; Write-Host ('Exit code: ' + `$LASTEXITCODE); Read-Host 'Press Enter to close this window'"
            $p = Start-Process -FilePath $PsExePath -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd)))
            [void]$script:Consoles.Add($p)
        }
    }
    else {
        Log $def.Line
        $t0 = Get-Date
        $o = (& $def.Exe @($def.Argv) 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ } }) -join $NL
        $rc = $LASTEXITCODE; Log $o.Trim()
        if ($wantSum) {
            $resFile = (Get-TaskFileBase $tool.Name) + '.txt'
            $body = "Rc=$rc${NL}Started=$($t0.ToString('s'))${NL}Ended=$((Get-Date).ToString('s'))${NL}-----${NL}$($o.Trim())"
            try { [IO.File]::WriteAllText($resFile, $body, (New-Object Text.UTF8Encoding $false)) } catch { $resFile = $null }
            $r = [pscustomobject]@{ Rc = $rc; Started = $t0; Ended = (Get-Date); Output = $o }
            $v = Get-TaskVerdict $tool.Kind $o $rc
            Log ('RESULT: {0} - {1} (exit code {2})' -f $tool.Name, $v.Find, $rc)
            Show-TaskSummary ([pscustomobject]@{ Name = $tool.Name; Line = $def.Line; OutFile = $resFile }) $r $v
        }
        elseif ($rc -ne 0) { Msg "$($def.Exe) failed (exit code $rc):${NL}${NL}$($o.Trim())" $tool.Name 'Error' } else { Msg ("Done:${NL}${NL}" + $o.Trim()) $tool.Name }
    }
} })

# ---- 10. Automation (BETA) ----
function Edit-AutoQueue([scriptblock]$change) {
    if ($script:Auto.Running) { return }
    $script:AutoRun = $null          # editing the queue clears the results of the last run from the list
    & $change
    Update-AutoList; Save-AutoState
}
function Add-AutoTask {
    $c = $lstAutoCat.SelectedItem; if (-not $c) { Msg 'Select a task on the left first.' 'Automation'; return }
    $why = Get-AutoWhyNot $c.Id; if ($why) { Msg "$($c.Name): $why." 'Automation' 'Warning'; return }
    if ($script:AutoQueue.Count -ge $AutoMax) { Msg "The queue holds at most $AutoMax tasks." 'Automation' 'Warning'; return }
    Edit-AutoQueue { [void]$script:AutoQueue.Add($c.Id) }
    $lvAuto.Items[$lvAuto.Items.Count - 1].Selected = $true
}
$lstAutoCat.Add_SelectedIndexChanged({ $c = $lstAutoCat.SelectedItem; if ($c) { $lblAutoHelp.Text = $c.Help } })
$lstAutoCat.Add_DoubleClick({ Safe { Add-AutoTask } })
$btnAutoAdd.Add_Click({ Safe { Add-AutoTask } })
$btnAutoPreset.Add_Click({ Safe {
    $p = $AutoPresets[[string]$cmbAutoPreset.SelectedItem]; if (-not $p) { return }
    if ($script:AutoQueue.Count -and -not (Ask "Replace the $($script:AutoQueue.Count) queued task(s) with the preset '$($cmbAutoPreset.SelectedItem)'?" 'Automation')) { return }
    $left = @($p | Where-Object { Get-AutoWhyNot $_ }); $p = @($p | Where-Object { -not (Get-AutoWhyNot $_) })
    Edit-AutoQueue { $script:AutoQueue.Clear(); foreach ($id in $p) { [void]$script:AutoQueue.Add($id) } }
    if ($left.Count) { Msg ("Left out because they cannot run here:${NL}${NL}" + (($left | ForEach-Object { '  ' + (Get-AutoCat $_).Name + ' - ' + (Get-AutoWhyNot $_) }) -join $NL)) 'Automation' }
} })
# after a run the list shows its results (rows can include added repair tasks): the first edit click switches back to the queue
function Test-AutoQueueShown { if ($script:AutoRun) { $script:AutoRun = $null; Update-AutoList; return $false }; return $true }
$btnAutoUp.Add_Click({ Safe {
    if (-not (Test-AutoQueueShown)) { return }
    if (-not $lvAuto.SelectedIndices.Count) { return }; $i = $lvAuto.SelectedIndices[0]
    if ($i -le 0 -or $i -ge $script:AutoQueue.Count) { return }
    Edit-AutoQueue { $x = $script:AutoQueue[$i]; $script:AutoQueue.RemoveAt($i); $script:AutoQueue.Insert($i - 1, $x) }
    $lvAuto.Items[$i - 1].Selected = $true
} })
$btnAutoDown.Add_Click({ Safe {
    if (-not (Test-AutoQueueShown)) { return }
    if (-not $lvAuto.SelectedIndices.Count) { return }; $i = $lvAuto.SelectedIndices[0]
    if ($i -ge $script:AutoQueue.Count - 1) { return }
    Edit-AutoQueue { $x = $script:AutoQueue[$i]; $script:AutoQueue.RemoveAt($i); $script:AutoQueue.Insert($i + 1, $x) }
    $lvAuto.Items[$i + 1].Selected = $true
} })
$btnAutoRemove.Add_Click({ Safe {
    if (-not (Test-AutoQueueShown)) { return }
    if (-not $lvAuto.SelectedIndices.Count) { return }; $i = $lvAuto.SelectedIndices[0]
    if ($i -ge $script:AutoQueue.Count) { return }
    Edit-AutoQueue { $script:AutoQueue.RemoveAt($i) }
    if ($lvAuto.Items.Count) { $lvAuto.Items[[Math]::Min($i, $lvAuto.Items.Count - 1)].Selected = $true }
} })
$btnAutoClear.Add_Click({ Safe { if ($script:AutoQueue.Count -and (Ask 'Remove every task from the queue?' 'Automation')) { Edit-AutoQueue { $script:AutoQueue.Clear() } } } })
foreach ($cb in @($chkAutoPop, $chkAutoStop, $chkAutoMon, $chkAutoSR)) { $cb.Add_CheckedChanged({ if (-not $script:Auto.Running) { Save-AutoState } }) }
$btnAutoStart.Add_Click({ Safe { Start-AutoRun } })
$btnAutoHtml.Add_Click({ Safe {
    $p = $script:LastAutoHtml
    if (-not $p -or -not [IO.File]::Exists($p)) { $p = @(Get-ChildItem -LiteralPath $TaskDir -Filter '*Automation-report.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { $_.FullName })[0] }
    if ($p -and [IO.File]::Exists($p)) { Start-Process -FilePath $p } else { Msg 'There is no HTML report yet. Run the queue with "Save an HTML report" ticked.' 'Automation' }
} })
$btnAutoStopReq.Add_Click({
    if ($script:Auto.Running) { $script:Auto.StopReq = $true; $script:Auto.StopWhy = 'was stopped by you'; $lblAutoStatus.Text = 'Stopping after the current task...'; Log 'AUTOMATION: stop requested - stops after the current task.' }
})

# ---- form ----
$form.Add_Shown({
    # start the shared timer FIRST: if a startup step below fails, task summaries, Automation and AI login must still work
    $timer.Start()
    Safe {
    Load-AutoState; Update-AutoList; Set-AutoEditing $true
    if ($lstAutoCat.Items.Count) { $lstAutoCat.SelectedIndex = 0 }
    $where = 'Windows'; if ($IsWinPE) { $where = 'WinPE' }
    Log "$AppName started in $where. Data folder: $DataDir"
    if ($DataOnRam) { Log 'NOTE: the data folder is on the WinPE RAM disk - copy backups and logs somewhere permanent before rebooting.' }
    if (-not (Test-StorageAvail)) { $rbStor.Enabled = $false; Log 'Storage cmdlets not available here - using diskpart.' }
    Update-SafeLabels
    Init-Unattend
    if ($cmbTool.Items.Count) { $cmbTool.SelectedIndex = 0 }
    Update-Disks; Update-Letters; Load-Mounts; Update-MountList; Update-Esp
    Update-Windows $true
    Update-TopBar
    }
})
$tabs.Add_Selecting({ if ($script:Busy) { $_.Cancel = $true } })    # no Mount / Rescan etc. while a collection runs
$form.Add_FormClosing({
    if ($script:Busy) { $_.Cancel = $true; Msg "$($script:Busy) is still running. Wait until it has finished, then close." 'Busy' 'Warning'; return }
    if ($script:Auto.Running -and -not (Ask "The automation queue is still running (task $($script:Auto.Index + 1) of $(@($script:AutoRun).Count)).${NL}${NL}Close anyway? The current task's window keeps running, but the rest of the queue does not run and there is no final summary." 'Automation running' 'Warning' 'Button2')) { $_.Cancel = $true; return }
    try { $timer.Stop() } catch {}
    if ($chkAuto.Checked -and $script:Mounts.Count -gt 0) {
        # a repair console started from the Recovery tab may still be working on a mounted drive
        $live = @($script:Consoles | Where-Object { $_ -and -not $_.HasExited })
        $unmount = $true
        if ($live.Count) { $unmount = Ask ("$($live.Count) repair console window(s) started by this tool are still running and may be using a mounted drive.${NL}${NL}Unmount the drives anyway?") 'Close' 'Warning' 'Button2' }
        if ($unmount) { foreach ($m in @($script:Mounts)) { [void](Dismount-One $m) } } else { Log 'Left the mounted drives in place (repair consoles still running).' }
    }
    Save-Mounts
    Log 'Closed.'
})

Initialize-WrtWindow $form (@($tabs.TabPages | ForEach-Object { $_ }) + @($tabs.TabPages | ForEach-Object { $_.Controls } | Where-Object { $_ -is [Windows.Forms.Panel] -and $_.Dock -eq 'Fill' })) 700 520
[void]$form.ShowDialog()
$form.Dispose()
