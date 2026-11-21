#requires -Version 5.1
# Version 1.8.4 (2026-11-20). What changed: docs/changes/V1.8.4.md
# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file or https://www.gnu.org/licenses/.
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
      3  AI Analyze     logs + screenshots to Claude or Gemini. Phone QR login (key encrypted with a # [AI]
                        one-time pad, memory only), 1-hour session. # [AI]
      4  Mount          mount / unmount partitions with diskpart or Storage cmdlets
                        (whitelisted, non-destructive commands only), remembered between runs.
      5  Safe Mode      safeboot minimal: edit the boot entry or add a separate boot-menu clone.
      6  Sysprep        A generalize (+ optional /mode:vm), B1 audit, B2 OOBE, opt-in pre-flight
                        checks, optional answer file.
      7  Unattend       build / preview / save / deploy unattend.xml with checkboxes.
      8  Recovery       EXPERIMENTAL boot-repair tools.

    Start it with WinSuperTool.bat (same folder). Every BCD change is backed up first.
    Mount memory, BCD backups and the activity log live in WinSuperTool-Data next to this script.
#>

$ErrorActionPreference = 'Continue'
$AppName = 'Windows Super Tool'
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
$PsExePath = Join-Path $PSHOME 'powershell.exe'
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

#region AI-ANALYZE
# =====================================================================
#  3. AI ANALYZE  (Claude or Gemini, phone QR login, 1-hour session)
# =====================================================================
$AiModelClaude   = 'claude-sonnet-5-5'
$AiModelGemini   = 'gemini-flash-latest'   # if Google retires it, try 'gemini-2.5-flash' or another current Flash model
$AiSessionMin    = 60        # session length in minutes
$AiPairingMin    = 5         # how long each QR code stays valid
$AiMaxFileChars  = 150000    # newest part of each log that is sent
$AiMaxTotalChars = 450000    # all logs together (keeps requests fast and inside model limits)
$AiMaxImageBytes = 3.5MB      # per image (raw); base64 is 4/3 bigger, so this stays under a 5 MB per-image limit either way
$AiMaxTotalImageB64 = 15MB    # all images together, as base64 (keeps the whole request well under the API request-size limits)
$AiImageMaxEdge  = 2000      # bigger screenshots are scaled down before upload (saves bandwidth)
$AiImageTypes    = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp' }
$AiConvertTypes  = @('.bmp', '.tif', '.tiff')
$AiFolderTypes   = @('.log', '.txt', '.csv', '.xml', '.json', '.ini', '.evtx', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp')
$AiSystemPrompt  = 'You are a Windows troubleshooting expert. Give a concise analysis: 1) Summary, 2) Key errors/findings, 3) Likely cause, 4) Step-by-step fixes. Use plain text, no markdown.'
$AiKeyLogNames   = @('_collection_summary.txt', 'target.txt', 'Crash_Shutdown_Events.txt', 'CBS.log', 'dism.log', 'setuperr.log', 'setupact.log',
                     'ReportingEvents.log', 'WindowsUpdate_merged.log', 'System.evtx', 'Application.evtx', 'Setup.evtx',
                     'Microsoft-Windows-WindowsUpdateClient%4Operational.evtx', 'BlueBox.log', 'systeminfo.txt', 'hotfixes.txt', 'setupapi.dev.log')

$aiFiles = New-Object Collections.ArrayList
$script:ApiKey = $null; $script:SessionEnd = [datetime]::MinValue
$script:Listener = $null; $script:Token = ''; $script:Pad = $null
$script:PairExpires = [datetime]::MinValue; $script:Attempts = 0
$script:QM = $null; $script:QF = $null
$script:AiJob = $null; $script:TickErr = $false

# ---------- QR code encoder (byte mode, error correction L, versions 1-9) ----------
$script:GfExp = New-Object 'int[]' 512
$script:GfLog = New-Object 'int[]' 256
$gx = 1
for ($i = 0; $i -lt 255; $i++) {
    $script:GfExp[$i] = $gx; $script:GfLog[$gx] = $i
    $gx = $gx -shl 1
    if ($gx -band 0x100) { $gx = $gx -bxor 0x11D }
}
for ($i = 255; $i -lt 512; $i++) { $script:GfExp[$i] = $script:GfExp[$i - 255] }

function GfMul($a, $b) {
    if ($a -eq 0 -or $b -eq 0) { return 0 }
    return $script:GfExp[$script:GfLog[$a] + $script:GfLog[$b]]
}
function Get-RsEc([int[]]$data, [int]$n) {
    $gen = @(1)
    for ($i = 0; $i -lt $n; $i++) {
        $new = New-Object 'int[]' ($gen.Length + 1)
        for ($j = 0; $j -lt $gen.Length; $j++) {
            $new[$j]     = $new[$j] -bxor $gen[$j]
            $new[$j + 1] = $new[$j + 1] -bxor (GfMul $gen[$j] $script:GfExp[$i])
        }
        $gen = $new
    }
    $rem = New-Object 'int[]' $n
    foreach ($b in $data) {
        $f = $b -bxor $rem[0]
        for ($k = 0; $k -lt $n - 1; $k++) { $rem[$k] = $rem[$k + 1] }
        $rem[$n - 1] = 0
        if ($f -ne 0) {
            for ($k = 0; $k -lt $n; $k++) { $rem[$k] = $rem[$k] -bxor (GfMul $gen[$k + 1] $f) }
        }
    }
    return ,$rem
}
function Set-QrModule($x, $y, $v) {
    if ($v) { $script:QM[$y, $x] = 1 } else { $script:QM[$y, $x] = 0 }
    $script:QF[$y, $x] = $true
}
function Add-Bits($list, [int]$val, [int]$cnt) {
    for ($i = $cnt - 1; $i -ge 0; $i--) { $list.Add(($val -shr $i) -band 1) }
}
function Set-QrFormat([int]$m, [int]$size) {
    $data = (1 -shl 3) -bor $m
    $rem = $data
    for ($k = 0; $k -lt 10; $k++) { $rem = ($rem -shl 1) -bxor (($rem -shr 9) * 0x537) }
    $fb = (($data -shl 10) -bor $rem) -bxor 0x5412
    for ($i = 0; $i -lt 6; $i++)  { Set-QrModule 8 $i ((($fb -shr $i) -band 1) -eq 1) }
    Set-QrModule 8 7 ((($fb -shr 6) -band 1) -eq 1)
    Set-QrModule 8 8 ((($fb -shr 7) -band 1) -eq 1)
    Set-QrModule 7 8 ((($fb -shr 8) -band 1) -eq 1)
    for ($i = 9; $i -lt 15; $i++) { Set-QrModule (14 - $i) 8 ((($fb -shr $i) -band 1) -eq 1) }
    for ($i = 0; $i -lt 8; $i++)  { Set-QrModule ($size - 1 - $i) 8 ((($fb -shr $i) -band 1) -eq 1) }
    for ($i = 8; $i -lt 15; $i++) { Set-QrModule 8 ($size - 15 + $i) ((($fb -shr $i) -band 1) -eq 1) }
    Set-QrModule 8 ($size - 8) $true
}
function New-QrMatrix([string]$text) {
    $dataCw = 0, 19, 34, 55, 80, 108, 136, 156, 194, 232
    $ecPer  = 0, 7, 10, 15, 20, 26, 18, 20, 24, 30
    $blocks = 0, 1, 1, 1, 1, 1, 2, 2, 2, 2
    $align  = @($null, $null, @(6, 18), @(6, 22), @(6, 26), @(6, 30), @(6, 34), @(6, 22, 38), @(6, 24, 42), @(6, 26, 46))

    $payload = [Text.Encoding]::UTF8.GetBytes($text)
    $n = $payload.Length
    $ver = 0
    for ($v = 1; $v -le 9; $v++) { if ((12 + 8 * $n) -le ($dataCw[$v] * 8)) { $ver = $v; break } }
    if ($ver -eq 0) { throw 'QR payload too long' }

    # data bits
    $bits = New-Object 'System.Collections.Generic.List[int]'
    Add-Bits $bits 4 4
    Add-Bits $bits $n 8
    foreach ($b in $payload) { Add-Bits $bits $b 8 }
    $cap = $dataCw[$ver] * 8
    Add-Bits $bits 0 ([Math]::Min(4, $cap - $bits.Count))
    while (($bits.Count % 8) -ne 0) { $bits.Add(0) }
    $cw = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $val = 0
        for ($j = 0; $j -lt 8; $j++) { $val = ($val -shl 1) -bor $bits[$i + $j] }
        $cw.Add($val)
    }
    $k = 0
    while ($cw.Count -lt $dataCw[$ver]) { if (($k % 2) -eq 0) { $cw.Add(0xEC) } else { $cw.Add(0x11) }; $k++ }

    # blocks + error correction + interleave
    $nb = $blocks[$ver]; $per = [int]($dataCw[$ver] / $nb); $ec = $ecPer[$ver]
    $db = @(); $eb = @()
    for ($b = 0; $b -lt $nb; $b++) {
        $blk = [int[]]($cw.GetRange($b * $per, $per).ToArray())
        $db += ,$blk
        $eb += ,(Get-RsEc $blk $ec)
    }
    $final = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $per; $i++) { for ($b = 0; $b -lt $nb; $b++) { $final.Add($db[$b][$i]) } }
    for ($i = 0; $i -lt $ec;  $i++) { for ($b = 0; $b -lt $nb; $b++) { $final.Add($eb[$b][$i]) } }

    # matrix and fixed patterns
    $size = 17 + 4 * $ver
    $script:QM = New-Object 'int[,]'  $size, $size
    $script:QF = New-Object 'bool[,]' $size, $size
    for ($i = 0; $i -lt $size; $i++) {
        Set-QrModule 6 $i (($i % 2) -eq 0)
        Set-QrModule $i 6 (($i % 2) -eq 0)
    }
    foreach ($c in @(@(3, 3), @(($size - 4), 3), @(3, ($size - 4)))) {
        for ($dy = -4; $dy -le 4; $dy++) {
            for ($dx = -4; $dx -le 4; $dx++) {
                $xx = $c[0] + $dx; $yy = $c[1] + $dy
                if ($xx -ge 0 -and $xx -lt $size -and $yy -ge 0 -and $yy -lt $size) {
                    $d = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
                    Set-QrModule $xx $yy (($d -ne 2) -and ($d -ne 4))
                }
            }
        }
    }
    $pos = $align[$ver]
    if ($pos) {
        $last = $pos[$pos.Length - 1]
        foreach ($a in $pos) {
            foreach ($b in $pos) {
                if (($a -eq 6 -and $b -eq 6) -or ($a -eq 6 -and $b -eq $last) -or ($a -eq $last -and $b -eq 6)) { continue }
                for ($dy = -2; $dy -le 2; $dy++) {
                    for ($dx = -2; $dx -le 2; $dx++) {
                        $d = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
                        Set-QrModule ($a + $dx) ($b + $dy) ($d -ne 1)
                    }
                }
            }
        }
    }
    Set-QrFormat 0 $size
    if ($ver -ge 7) {
        $rem = $ver
        for ($k = 0; $k -lt 12; $k++) { $rem = ($rem -shl 1) -bxor (($rem -shr 11) * 0x1F25) }
        $vb = ($ver -shl 12) -bor $rem
        for ($i = 0; $i -lt 18; $i++) {
            $bit = ((($vb -shr $i) -band 1) -eq 1)
            $a = $size - 11 + ($i % 3); $b = [int][Math]::Floor($i / 3)
            Set-QrModule $a $b $bit
            Set-QrModule $b $a $bit
        }
    }

    # place data bits in the zigzag pattern
    $idx = 0; $total = $final.Count * 8; $right = $size - 1
    while ($right -ge 1) {
        if ($right -eq 6) { $right = 5 }
        $upward = ((($right + 1) -band 2) -eq 0)
        for ($vert = 0; $vert -lt $size; $vert++) {
            if ($upward) { $y = $size - 1 - $vert } else { $y = $vert }
            for ($j = 0; $j -lt 2; $j++) {
                $x = $right - $j
                if ((-not $script:QF[$y, $x]) -and ($idx -lt $total)) {
                    $script:QM[$y, $x] = (($final[($idx -shr 3)] -shr (7 - ($idx -band 7))) -band 1)
                    $idx++
                }
            }
        }
        $right -= 2
    }
    # mask 0, then the final format bits
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            if ((-not $script:QF[$y, $x]) -and ((($x + $y) % 2) -eq 0)) { $script:QM[$y, $x] = $script:QM[$y, $x] -bxor 1 }
        }
    }
    Set-QrFormat 0 $size
    return @{ Size = $size; Mod = $script:QM }
}
function New-QrBitmap([string]$text, [int]$scale = 6) {
    $q = New-QrMatrix $text
    $n = $q.Size; $quiet = 4; $dim = ($n + 2 * $quiet) * $scale
    $bmp = New-Object Drawing.Bitmap $dim, $dim
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.Clear([Drawing.Color]::White)
    for ($y = 0; $y -lt $n; $y++) {
        for ($x = 0; $x -lt $n; $x++) {
            if ($q.Mod[$y, $x] -eq 1) {
                $g.FillRectangle([Drawing.Brushes]::Black, ($x + $quiet) * $scale, ($y + $quiet) * $scale, $scale, $scale)
            }
        }
    }
    $g.Dispose()
    return $bmp
}

# ---------- pairing server (tiny HTTP listener on the local network) ----------
$PairPageHtml = @'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>Connect PC</title>
<style>body{font-family:system-ui,sans-serif;margin:0;padding:24px;background:#f5f5f7;color:#111}
input,button{width:100%;box-sizing:border-box;font-size:17px;padding:14px;margin-top:12px;border-radius:10px;border:1px solid #bbb}
button{background:#d97757;color:#fff;border:0;font-weight:600}#m{color:#b00020;min-height:1.5em}</style></head><body>
<h2>Connect this PC</h2>
<p>Enter your Claude or Gemini API key. It is encrypted on this phone before it is sent. The PC keeps it in memory only and forgets it after 1 hour.</p>
<input id="k" type="password" placeholder="Paste your API key" autocomplete="current-password" autocapitalize="off" autocorrect="off" spellcheck="false">
<button id="b">Send to PC</button><p id="m"></p>
<script>
(function(){
var m=document.getElementById('m');
function b64(s){s=s.replace(/-/g,'+').replace(/_/g,'/');while(s.length%4)s+='=';var r=atob(s),o=new Uint8Array(r.length);for(var i=0;i<r.length;i++)o[i]=r.charCodeAt(i);return o;}
document.getElementById('b').onclick=function(){
 var pad;try{pad=b64(location.hash.slice(1));}catch(e){pad=[];}
 if(!pad.length){m.textContent='Please scan the QR code again.';return;}
 var key=new TextEncoder().encode(document.getElementById('k').value.trim());
 if(!key.length||key.length>pad.length){m.textContent='That does not look like a valid key.';return;}
 var hex='';for(var i=0;i<key.length;i++){var v=key[i]^pad[i];hex+=(v<16?'0':'')+v.toString(16);}
 fetch(location.pathname.replace(/\/$/,'')+'/key',{method:'POST',body:hex}).then(function(r){
  if(r.ok){document.getElementById('k').value='';history.replaceState(null,'',location.pathname);
   document.body.innerHTML='<h2>Connected</h2><p>You can close this page. Click Log out on the PC when you are done.</p>';}
  else{m.textContent='The PC rejected the key. Check it and try again.';}
 }).catch(function(){m.textContent='Could not reach the PC. Are both on the same Wi-Fi?';});
};})();
</script></body></html>
'@

function Get-LanIp {
    try {
        $s = New-Object Net.Sockets.Socket ([Net.Sockets.AddressFamily]::InterNetwork), ([Net.Sockets.SocketType]::Dgram), ([Net.Sockets.ProtocolType]::Udp)
        $s.Connect('8.8.8.8', 53)
        $ip = $s.LocalEndPoint.Address.ToString(); $s.Close()
        if ($ip -ne '0.0.0.0') { return $ip }
    } catch {}
    foreach ($a in [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName())) {
        if ($a.AddressFamily -eq 'InterNetwork' -and -not $a.ToString().StartsWith('169.254')) { return $a.ToString() }
    }
    return '127.0.0.1'
}
function Stop-Pairing {
    if ($script:Listener) { try { $script:Listener.Stop() } catch {}; $script:Listener = $null }
    $script:Pad = $null; $script:Token = ''
}
function Start-Pairing {
    Stop-Pairing
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $pad = New-Object byte[] 128; $rng.GetBytes($pad)
    $tk  = New-Object byte[] 8;   $rng.GetBytes($tk)
    $rng.Dispose()
    $script:Pad = $pad
    $script:Token = ([BitConverter]::ToString($tk) -replace '-', '').ToLower()
    $script:Listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Any), 0
    $script:Listener.Start()
    $port = $script:Listener.LocalEndpoint.Port
    $b64 = [Convert]::ToBase64String($pad).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $script:PairExpires = (Get-Date).AddMinutes($AiPairingMin)
    $script:Attempts = 0; $script:PairConns = 0
    return ('http://{0}:{1}/{2}#{3}' -f (Get-LanIp), $port, $script:Token, $b64)
}
function Send-Resp($stream, [int]$code, [string]$ctype, [string]$body) {
    $reasonText = switch ($code) { 200 { 'OK' } 400 { 'Bad Request' } default { 'Not Found' } }
    $b = [Text.Encoding]::UTF8.GetBytes($body)
    $h = "HTTP/1.1 $code $reasonText`r`nContent-Type: $ctype; charset=utf-8`r`nContent-Length: $($b.Length)`r`nCache-Control: no-store`r`nReferrer-Policy: no-referrer`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($h)
    $stream.Write($hb, 0, $hb.Length); $stream.Write($b, 0, $b.Length); $stream.Flush()
}
function Invoke-PairClient($client) {
    $client.ReceiveTimeout = 700; $client.SendTimeout = 700   # runs on the GUI thread: keep each client short
    $stream = $client.GetStream()
    $script:PairConns++                     # every connection counts toward the junk limit (see the timer)
    $buf = New-Object byte[] 8192; $total = 0; $hEnd = -1; $txt = ''
    # overall deadline: the 700 ms timeout is per Read, so a client sending one byte at a time could hold the GUI thread
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1500)
    while ($total -lt $buf.Length) {
        if ([DateTime]::UtcNow -gt $deadline) { return }
        $r = $stream.Read($buf, $total, $buf.Length - $total)
        if ($r -le 0) { break }
        $total += $r
        $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $total)
        $hEnd = $txt.IndexOf("`r`n`r`n")
        if ($hEnd -ge 0) {
            $len = 0
            if ($txt.Substring(0, $hEnd) -match '(?im)^content-length:\s*(\d+)') { $len = [int]$Matches[1] }
            if ($total -ge ($hEnd + 4 + $len)) { break }
        }
    }
    if ($hEnd -lt 0) { return }
    $head   = $txt.Substring(0, $hEnd) -split "`r`n"
    $parts  = $head[0] -split ' '
    if ($parts.Count -lt 2) { return }
    $method = $parts[0]
    $path   = ($parts[1] -split '\?')[0]
    $body   = $txt.Substring($hEnd + 4)
    $tok    = '/' + $script:Token

    if ($method -eq 'GET' -and $path -eq $tok) {
        Send-Resp $stream 200 'text/html' $PairPageHtml
    }
    elseif ($method -eq 'POST' -and $path -eq "$tok/key") {
        $ok = $false
        try {
            $hex = $body.Trim()
            if ($hex -match '^[0-9a-fA-F]+$' -and ($hex.Length % 2) -eq 0 -and ($hex.Length / 2) -le $script:Pad.Length) {
                $n = [int]($hex.Length / 2)
                $chars = New-Object char[] $n
                for ($i = 0; $i -lt $n; $i++) {
                    $chars[$i] = [char]([Convert]::ToInt32($hex.Substring(2 * $i, 2), 16) -bxor $script:Pad[$i])
                }
                $k = -join $chars
                if ($k -match '^(sk-ant-[A-Za-z0-9_\-]{10,}|AIza[A-Za-z0-9_\-]{30,})$') { $script:ApiKey = $k; $ok = $true }
            }
        } catch {}
        if ($ok) { Send-Resp $stream 200 'text/plain' 'OK' }
        # one rejected key ends this QR code: a second attempt with the same one-time pad would leak key XOR key
        else { $script:Attempts = 5; Send-Resp $stream 400 'text/plain' 'Invalid' }
    }
    else { Send-Resp $stream 404 'text/plain' 'Not found' }
}

# ---------- reading files for the request ----------
# reads the newest $maxChars characters of a text file, even while Windows is writing to it
function Read-TextTail([string]$path, [int]$maxChars) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite,Delete')
    try {
        $enc = [Text.Encoding]::UTF8
        $bom = New-Object byte[] 4
        $got = $fs.Read($bom, 0, 4)
        if ($got -ge 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { $enc = [Text.Encoding]::Unicode }
        elseif ($got -ge 2 -and $bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { $enc = [Text.Encoding]::BigEndianUnicode }
        $bpc = 1; if ($enc -is [Text.UnicodeEncoding]) { $bpc = 2 }
        $start = [Math]::Max([long]0, $fs.Length - ([long]$maxChars * $bpc))
        if ($bpc -eq 2) { $start -= ($start % 2) }
        $fs.Position = $start
        $sr = New-Object IO.StreamReader($fs, $enc, ($start -eq 0))
        $text = $sr.ReadToEnd()
        return @{ Text = $text; Truncated = ($start -gt 0) }
    } finally { $fs.Dispose() }
}
function Read-LogForAi([string]$path, [int]$cap) {
    $trunc = $false
    if ([IO.Path]::GetExtension($path).ToLower() -eq '.evtx') {
        $ev = @(Get-WinEvent -FilterHashtable @{ Path = $path; Level = 1, 2, 3 } -MaxEvents 400 -ErrorAction SilentlyContinue)
        $hdr = 'Critical / Error / Warning events only, newest first:'
        if (-not $ev.Count) { $ev = @(Get-WinEvent -Path $path -MaxEvents 400 -ErrorAction SilentlyContinue); $hdr = 'Newest events (no errors or warnings found):' }
        if (-not $ev.Count) { return @{ Text = '(this event log contains no events)'; Truncated = $false; Binary = $false } }   # wevtutil writes empty logs for empty channels
        $lines = foreach ($e in $ev) {
            $m = $e.Message
            if (-not $m) { $m = '(no message text) ' + ((@($e.Properties) | ForEach-Object { $_.Value }) -join '; ') }
            '{0} [{1}] {2} (ID {3}): {4}' -f $e.TimeCreated, $e.LevelDisplayName, $e.ProviderName, $e.Id, ($m -replace '\s+', ' ')
        }
        $text = $hdr + "`n" + (@($lines) -join "`n")
    } else {
        # known binary formats (ETL traces, dumps, hives, archives) are never sent as text
        if ([IO.Path]::GetExtension($path).ToLower() -in '.etl', '.dmp', '.hiv', '.dat', '.zip', '.cab', '.exe', '.dll', '.sys', '.bin', '.db', '.edb', '.mdmp', '.hdmp') { return @{ Binary = $true } }
        $t = Read-TextTail $path $cap
        $text = $t.Text; $trunc = $t.Truncated
        # binary data decoded as UTF-8 mostly turns into U+FFFD replacement characters, so count those as well
        if ($text.Length -gt 200 -and ([regex]::Matches($text, '[\x00-\x08\x0E-\x1A\uFFFD]')).Count -gt ($text.Length / 20)) { return @{ Binary = $true } }
        $text = $text.Replace([string][char]0, '')
    }
    if ($text.Length -gt $cap) {
        # event logs are listed NEWEST FIRST, so keep the start; text logs grow at the end, so keep the end
        if ([IO.Path]::GetExtension($path) -ieq '.evtx') { $text = $text.Substring(0, $cap) } else { $text = $text.Substring($text.Length - $cap) }
        $trunc = $true
    }
    return @{ Text = $text; Truncated = $trunc; Binary = $false }
}
# returns @{ Mime; Data(base64); Note } - converts BMP/TIFF and shrinks oversized screenshots to JPEG
function Get-ImagePart([string]$path) {
    $ext  = [IO.Path]::GetExtension($path).ToLower()
    $len  = (Get-Item -LiteralPath $path).Length
    $mime = $AiImageTypes[$ext]
    $convert = (-not $mime) -or ($len -gt $AiMaxImageBytes)
    $img = $null; $bmp = $null; $g = $null; $ms = $null
    try {
        if (-not $convert -and $ext -ne '.webp' -and $ext -ne '.gif') {
            # a file that GDI+ cannot decode is not a usable picture: sending it would make the API reject the WHOLE request
            try { $img = [Drawing.Image]::FromFile($path) } catch { throw 'not a valid image file' }
            if ([Math]::Max($img.Width, $img.Height) -gt $AiImageMaxEdge) { $convert = $true }
        }
        if (-not $convert) { return @{ Mime = $mime; Data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)); Note = '' } }
        if (-not $img) { $img = [Drawing.Image]::FromFile($path) }
        $scale = [Math]::Min(1.0, $AiImageMaxEdge / [double][Math]::Max($img.Width, $img.Height))
        $nw = [Math]::Max(1, [int]($img.Width * $scale)); $nh = [Math]::Max(1, [int]($img.Height * $scale))
        $bmp = New-Object Drawing.Bitmap $nw, $nh
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([Drawing.Color]::White)
        $g.DrawImage($img, 0, 0, $nw, $nh)
        $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $ep = New-Object Drawing.Imaging.EncoderParameters 1
        $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality, [long]85)
        $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, $codec, $ep)
        return @{ Mime = 'image/jpeg'; Data = [Convert]::ToBase64String($ms.ToArray()); Note = " (converted to ${nw}x${nh} JPEG for upload)" }
    } catch {
        throw "Image '$([IO.Path]::GetFileName($path))' could not be prepared: $($_.Exception.Message)"
    } finally {
        # dispose on every path (GDI+ handles leak otherwise)
        foreach ($o in $g, $bmp, $ms, $img) { if ($o) { try { $o.Dispose() } catch {} } }
    }
}
function ConvertTo-JsonText([string]$s) {
    if ($null -eq $s) { return 'null' }
    $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    $s = [regex]::Replace($s, '[\x00-\x1F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    return '"' + $s + '"'
}
function New-AiRequest([bool]$gemini) {
    $parts  = New-Object 'System.Collections.Generic.List[string]'
    $notes  = New-Object 'System.Collections.Generic.List[string]'
    $budget = $AiMaxTotalChars
    $addText = {
        param($t)
        if ($gemini) { $parts.Add('{"text":' + (ConvertTo-JsonText $t) + '}') }
        else { $parts.Add('{"type":"text","text":' + (ConvertTo-JsonText $t) + '}') }
    }
    $imgBytes = 0
    foreach ($f in @($aiFiles)) {
        $name = [IO.Path]::GetFileName($f)
        $ext  = [IO.Path]::GetExtension($f).ToLower()
        $lblAiStatus.Text = "Preparing $name ..."; [Windows.Forms.Application]::DoEvents()   # keep the window responsive
        if ($AiImageTypes.ContainsKey($ext) -or $AiConvertTypes -contains $ext) {
            # one unreadable file must not cancel the whole request: skip it and say so in the prompt
            try { $img = Get-ImagePart $f } catch { $notes.Add("not sent ($($_.Exception.Message)): $name"); continue }
            if ($imgBytes + $img.Data.Length -gt $AiMaxTotalImageB64) { $notes.Add("not sent (image size budget used up): $name"); continue }
            $imgBytes += $img.Data.Length
            & $addText ("Image file: $name" + $img.Note)
            if ($gemini) { $parts.Add('{"inline_data":{"mime_type":"' + $img.Mime + '","data":"' + $img.Data + '"}}') }
            else { $parts.Add('{"type":"image","source":{"type":"base64","media_type":"' + $img.Mime + '","data":"' + $img.Data + '"}}') }
        } else {
            if ($budget -lt 2000) { $notes.Add("not sent (size budget used up): $name"); continue }
            try { $r = Read-LogForAi $f ([Math]::Min($AiMaxFileChars, $budget)) } catch { $notes.Add("not sent (could not read: $($_.Exception.Message)): $name"); continue }
            if ($r.Binary) { $notes.Add("not sent (binary file): $name"); continue }
            $budget -= $r.Text.Length
            $label = "Log file: $name"
            if ($r.Truncated) { $label += ' (truncated - newest part only)' }
            & $addText ($label + "`n-----`n" + $r.Text + "`n-----")
        }
    }
    $userPrompt = $txtPrompt.Text.Trim()
    if (-not $userPrompt) { $userPrompt = 'Analyze these files and give a short summary of problems and fixes.' }
    if ($notes.Count) { $userPrompt += "`n`n(Note: some files were not included: " + ($notes -join '; ') + ')' }
    & $addText $userPrompt

    $joined = $parts -join ','
    if ($gemini) {
        $json = '{"system_instruction":{"parts":[{"text":' + (ConvertTo-JsonText $AiSystemPrompt) + '}]},"contents":[{"role":"user","parts":[' + $joined + ']}],"generationConfig":{"maxOutputTokens":8192}}'
        $uri = "https://generativelanguage.googleapis.com/v1beta/models/$($AiModelGemini):generateContent"
        $headers = @{ 'x-goog-api-key' = $script:ApiKey }
    } else {
        # max_tokens 16000: on Sonnet 5.5 adaptive thinking is on by default and its tokens count toward max_tokens, so 4096
        # could leave little or no room for the answer (16000 is the recommended ceiling for a non-streaming request).
        # "fallbacks":"default" (beta) lets the API retry a refused request on a fallback model instead of returning nothing.
        $json = '{"model":' + (ConvertTo-JsonText $AiModelClaude) + ',"max_tokens":16000,"fallbacks":"default","system":' + (ConvertTo-JsonText $AiSystemPrompt) + ',"messages":[{"role":"user","content":[' + $joined + ']}]}'
        $uri = 'https://api.anthropic.com/v1/messages'
        $headers = @{ 'x-api-key' = $script:ApiKey; 'anthropic-version' = '2023-06-01'; 'anthropic-beta' = 'server-side-fallback-2026-07-01' }
    }
    return @{ Uri = $uri; Headers = $headers; Body = [Text.Encoding]::UTF8.GetBytes($json); Notes = $notes }
}
# the web request runs in a background runspace so the window stays responsive
function Start-AiRequest($req, [bool]$gemini) {
    $ps = [PowerShell]::Create()
    $job = {
        param($u, $h, $b)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            # Invoke-WebRequest + explicit UTF-8 decode: PS 5.1 would read a charset-less JSON reply as ISO-8859-1
            $w = Invoke-WebRequest -Uri $u -Method Post -Body $b -ContentType 'application/json; charset=utf-8' -Headers $h -TimeoutSec 600 -UseBasicParsing -ErrorAction Stop
            $r = [Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
            [pscustomobject]@{ Ok = $true; Resp = $r; Err = '' }
        } catch {
            $m = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
            [pscustomobject]@{ Ok = $false; Resp = $null; Err = $m }
        }
    }
    [void]$ps.AddScript($job.ToString()).AddArgument($req.Uri).AddArgument($req.Headers).AddArgument($req.Body)
    $script:AiJob = @{ PS = $ps; Handle = $ps.BeginInvoke(); Gemini = $gemini; Started = Get-Date }
}
function Stop-AiRequest {
    if ($script:AiJob) { try { [void]$script:AiJob.PS.BeginStop($null, $null) } catch {} }
}
function Complete-AiRequest {
    $job = $script:AiJob; $script:AiJob = $null
    $btnAiGo.Enabled = $true; $btnAiCancel.Enabled = $false
    $res = $null
    try { $res = $job.PS.EndInvoke($job.Handle) }
    catch { $lblAiStatus.Text = 'Cancelled.'; Log 'AI analysis cancelled.'; try { $job.PS.Dispose() } catch {}; return }
    try { $job.PS.Dispose() } catch {}
    $r = $null
    if ($res -and $res.Count) { $r = $res[0] }
    if (-not $r) { $txtAiOut.Text = 'Error: no result was returned.'; $lblAiStatus.Text = 'Failed.'; return }
    if (-not $r.Ok) {
        $txtAiOut.Text = 'Error:' + $NL + $r.Err
        $lblAiStatus.Text = 'Failed.'
        Log 'AI analysis failed (details in the Analysis box).'
        return
    }
    $resp = $r.Resp
    if ($job.Gemini) {
        $cand = @($resp.candidates)
        $out = ''
        if ($cand.Count -and $cand[0].content) { $out = (@($cand[0].content.parts) | ForEach-Object { $_.text }) -join "`r`n" }
        if (-not $out) {
            $why = ''
            if ($cand.Count) { $why = $cand[0].finishReason }
            if ($resp.promptFeedback) { $why += ' ' + $resp.promptFeedback.blockReason }
            $out = "No response text was returned (reason: $why). The content may have been blocked by Google."
        } elseif ($cand[0].finishReason -eq 'MAX_TOKENS') { $out += "`r`n`r`n[The answer was cut off at the length limit.]" }
    } else {
        $out = (@($resp.content) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`r`n"
        if ($resp.stop_reason -eq 'refusal') {
            $cat = ''; if ($resp.stop_details -and $resp.stop_details.category) { $cat = " (category: $($resp.stop_details.category))" }
            $out = "Claude declined to analyze this request$cat." + $(if ($out) { "`r`n`r`nPartial text:`r`n$out" } else { '' })
        } elseif ($resp.stop_reason -eq 'max_tokens') { $out += "`r`n`r`n[The answer was cut off at the length limit.]" }
        if (-not $out) { $out = "No response text was returned (stop_reason: $($resp.stop_reason))." }
    }
    $txtAiOut.Text = ($out -replace "(?<!`r)`n", "`r`n")
    $secs = [int]((Get-Date) - $job.Started).TotalSeconds
    $lblAiStatus.Text = "Done in $secs s."
    Log "AI analysis finished ($secs s)."
}
function Add-AiFiles($paths) {
    $n = 0
    foreach ($p in @($paths)) {
        if (-not $p) { continue }
        if ((Test-Path -LiteralPath $p -PathType Leaf) -and -not $aiFiles.Contains($p)) { [void]$aiFiles.Add($p); [void]$lstAi.Items.Add($p); $n++ }
    }
    $lblAiStatus.Text = "$($aiFiles.Count) file(s) selected."
    return $n
}
# picks the most useful files out of a Collect Logs folder, in priority order
function Get-KeyLogs([string]$root) {
    $all = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $AiKeyLogNames -contains $_.Name -and $_.Length -lt 500MB })
    $seenEvtx = @{}
    foreach ($name in $AiKeyLogNames) {
        foreach ($f in @($all | Where-Object { $_.Name -eq $name })) {
            if ($f.Extension -eq '.evtx') { if ($seenEvtx.ContainsKey($f.Name)) { continue }; $seenEvtx[$f.Name] = $true }
            $f.FullName
        }
    }
}
function Show-NewQr {
    $form.Cursor = 'WaitCursor'
    $lblCount.Text = 'Generating QR code...'; $form.Refresh()
    try {
        $url = Start-Pairing
        $bmp = New-QrBitmap $url 6
        $old = $picQr.Image
        $picQr.Size = $bmp.Size
        $picQr.Image = $bmp
        if ($old) { $old.Dispose() }
    } catch {
        $lblCount.Text = "Could not start login: $($_.Exception.Message)"
    } finally { $form.Cursor = 'Default' }
}
function Clear-Qr {
    Stop-Pairing
    $old = $picQr.Image; $picQr.Image = $null; if ($old) { $old.Dispose() }
}
function Enter-Session {
    $script:SessionEnd = (Get-Date).AddMinutes($AiSessionMin)
    $lblNotice.Text = ''
    if ($script:ApiKey.StartsWith('AIza')) { $cmbAi.SelectedIndex = 1 } else { $cmbAi.SelectedIndex = 0 }
    Clear-Qr
    $pnlLogin.Visible = $false; $pnlMain.Visible = $true
    $lblAiStatus.Text = 'Logged in via phone. Add your files.'
    Log "AI: logged in via phone ($($cmbAi.SelectedItem)); session ends in $AiSessionMin minutes."
}
function Exit-Session([string]$msg) {
    Stop-AiRequest
    $script:ApiKey = $null
    $aiFiles.Clear(); $lstAi.Items.Clear(); $txtAiOut.Clear()
    $pnlMain.Visible = $false; $pnlLogin.Visible = $true
    $lblNotice.Text = $msg
    Log "AI: $msg"
    if ($tabs.SelectedTab -eq $tpAI) { Show-NewQr } else { Clear-Qr; $lblCount.Text = '' }
}

#endregion AI-ANALYZE

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
    [pscustomobject]@{ Name = 'Rebuild boot files (bcdboot)'; Needs = 'both'; Exe = 'bcdboot.exe'; Window = $false
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
    [pscustomobject]@{ Name = 'Scan for Windows installs (bootrec /scanos)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $false
        Help = "bootrec /scanos${NL}${NL}Read-only scan for Windows installations that are not in the boot menu.${NL}${NL}Use case: check whether Windows is detected before rebuilding the BCD.${NL}bootrec ships with WinRE; some WinPE builds do not include it."
        Argv = { param($c) @('/scanos') } },
    [pscustomobject]@{ Name = 'Rebuild BCD (bootrec /rebuildbcd)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $true
        Help = "bootrec /rebuildbcd${NL}${NL}Scans for installs and offers to add them to the BCD (asks Yes / No / All in its own window).${NL}${NL}Use cases: missing boot menu entry; 'no operating system found'.${NL}Tip: run 'BCD: back up store' first."
        Argv = { param($c) @('/rebuildbcd') } },
    [pscustomobject]@{ Name = 'Write new MBR (bootrec /fixmbr)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $false
        Help = "bootrec /fixmbr${NL}${NL}Writes a standard Windows master boot record to the system disk without touching the partition table.${NL}${NL}Use cases: corrupted MBR, boot-sector virus, a non-Windows loader left on a BIOS/MBR disk.${NL}Rarely needed on UEFI/GPT disks."
        Argv = { param($c)
            if ((Get-FirmwareType) -eq 'UEFI' -and -not (Ask "This PC boots in UEFI mode. bootrec /fixmbr only matters for BIOS/MBR disks and does not repair UEFI boot - use 'Rebuild boot files (bcdboot)' instead.${NL}${NL}Run it anyway?" 'UEFI system' 'Warning' 'Button2')) { return @() }
            @('/fixmbr') } },
    [pscustomobject]@{ Name = 'Write boot sector (bootrec /fixboot)'; Needs = 'none'; Exe = 'bootrec.exe'; Window = $false
        Help = "bootrec /fixboot${NL}${NL}Writes a new boot sector to the system partition.${NL}${NL}Use case: BIOS/MBR systems with a damaged boot sector.${NL}On UEFI it often returns 'Access is denied' - use 'Rebuild boot files (bcdboot)' instead."
        Argv = { param($c)
            if ((Get-FirmwareType) -eq 'UEFI' -and -not (Ask "This PC boots in UEFI mode. bootrec /fixboot is for BIOS/MBR boot sectors and usually fails with 'Access is denied' on UEFI - use 'Rebuild boot files (bcdboot)' instead.${NL}${NL}Run it anyway?" 'UEFI system' 'Warning' 'Button2')) { return @() }
            @('/fixboot') } },
    [pscustomobject]@{ Name = 'System file check (sfc)'; Needs = 'install'; Exe = 'sfc.exe'; Window = $true
        Help = "Offline install: sfc /scannow /offbootdir=D:\ /offwindir=D:\Windows${NL}Running Windows: sfc /scannow${NL}${NL}Verifies and repairs protected system files of the Target Windows.${NL}${NL}Use cases: Windows will not boot because of corrupt system files; after malware or a failed update."
        Argv = { param($c) if ($c.Live) { @('/scannow') } else { @('/scannow', "/offbootdir=$($c.Win)\", "/offwindir=$($c.Win)\Windows") } } },
    [pscustomobject]@{ Name = 'DISM: restore health'; Needs = 'install'; Exe = 'dism.exe'; Window = $true
        Help = "Offline install: dism /image:D:\ /cleanup-image /restorehealth /scratchdir:D:\Windows\Temp${NL}Running Windows: dism /online /cleanup-image /restorehealth${NL}${NL}Repairs the component store.${NL}${NL}Use case: sfc cannot repair files. Offline repair may fail without a /source (install.wim); check the console output."
        Argv = { param($c) if ($c.Live) { @('/online', '/cleanup-image', '/restorehealth') } else { @("/image:$($c.Win)\", '/cleanup-image', '/restorehealth', "/scratchdir:$($c.Win)\Windows\Temp") } } },
    [pscustomobject]@{ Name = 'Drivers: list third-party drivers'; Needs = 'install'; Exe = 'dism.exe'; Window = $true
        Help = "dism /image:D:\ /get-drivers   (running Windows: dism /online /get-drivers)${NL}${NL}Read-only list of non-Microsoft drivers (oemNN.inf).${NL}${NL}Use case: find the NVMe / RAID / Intel RST-VMD driver name before removing it."
        Argv = { param($c) if ($c.Live) { @('/online', '/get-drivers') } else { @("/image:$($c.Win)\", '/get-drivers') } } },
    [pscustomobject]@{ Name = 'Drivers: inject from folder'; Needs = 'install'; Exe = 'dism.exe'; Window = $true
        Help = "Offline install: dism /image:D:\ /add-driver /driver:<folder> /recurse${NL}Running Windows: pnputil /add-driver <folder>\*.inf /subdirs /install${NL}${NL}Adds every driver found in a folder.${NL}${NL}Use cases: 0x7B INACCESSIBLE_BOOT_DEVICE after moving the disk to new hardware; adding NVMe / RAID / VMD storage drivers so Windows can boot."
        Argv = { param($c)
            $fb = New-Object Windows.Forms.FolderBrowserDialog; $fb.Description = 'Folder containing the driver .inf files'
            if ($fb.ShowDialog() -ne 'OK') { return @() }
            if ($c.Live) { return @{ Exe = 'pnputil.exe'; Args = @('/add-driver', (Join-Path $fb.SelectedPath '*.inf'), '/subdirs', '/install') } }
            return @("/image:$($c.Win)\", '/add-driver', "/driver:$($fb.SelectedPath)", '/recurse') } },
    [pscustomobject]@{ Name = 'Drivers: remove one (oemNN.inf)'; Needs = 'install'; Exe = 'dism.exe'; Window = $true
        Help = "Offline install: dism /image:D:\ /remove-driver /driver:oemNN.inf${NL}Running Windows: pnputil /delete-driver oemNN.inf /uninstall${NL}${NL}Removes one third-party driver package.${NL}${NL}Use cases: a storage / RAID driver is causing a boot crash; clean up before switching controller mode.${NL}Run 'Drivers: list third-party drivers' first to get the oemNN.inf name."
        Argv = { param($c)
            $n = Read-Text 'Driver published name (for example oem12.inf):' 'Remove driver'
            if (-not $n) { return @() }
            if ($n -notmatch '^oem\d+\.inf$') { Msg 'Invalid name. Use the oemNN.inf name from the driver list.' 'Invalid' 'Warning'; return @() }
            if ($c.Live) { return @{ Exe = 'pnputil.exe'; Args = @('/delete-driver', $n, '/uninstall') } }
            return @("/image:$($c.Win)\", '/remove-driver', "/driver:$n") } },
    [pscustomobject]@{ Name = 'Check disk, read-only scan (chkdsk /scan)'; Needs = 'install'; Exe = 'chkdsk.exe'; Window = $true
        Help = "chkdsk D: /scan${NL}${NL}Scans the file system of the Target Windows volume without fixing anything.${NL}${NL}Use case: see whether file-system errors explain a boot failure."
        Argv = { param($c) @($c.Win, '/scan') } },
    [pscustomobject]@{ Name = 'Check disk and REPAIR (chkdsk /f)'; Needs = 'install'; Exe = 'chkdsk.exe'; Window = $true
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
$tpAI   = New-Page '3. AI Analyze' # [AI]
$tpMnt  = New-Page '4. Mount'
$tpSafe = New-Page '5. Safe Mode'
$tpSys  = New-Page '6. Sysprep'
$tpUna  = New-Page '7. Unattend'
$tpRec  = New-Page '8. Recovery (experimental)'
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
$btnColToAi = New-Ctl 'Button' $tpCol 410 274 200 30 'Send key logs to AI Analyze' # [AI]
Add-Help $tpCol 616 277 'Send key logs to AI Analyze' ("Adds the most useful files from the last collection to the AI Analyze tab: the summary, crash/shutdown events, CBS.log, dism.log, setup logs, ReportingEvents.log, the merged WindowsUpdate.log, and the System / Application / Setup / Windows Update event logs (errors and warnings only).${NL}${NL}Large logs are trimmed to their newest part, and the total is capped so the request stays fast.") # [AI]
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

#region AI-ANALYZE
# ---------- 3. AI Analyze ----------
$pnlLogin = New-Object Windows.Forms.Panel; $pnlLogin.Dock = 'Fill'; $tpAI.Controls.Add($pnlLogin)
$picQr = New-Ctl 'PictureBox' $pnlLogin 12 8 366 366
$picQr.SizeMode = 'Normal'
$lblQrTitle = New-Ctl 'Label' $pnlLogin 400 10 540 34 'Scan to log in'
$lblQrTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 16)
$lblQrHow = New-Ctl 'Label' $pnlLogin 400 50 540 100 ("1. Scan the code with your phone camera.${NL}2. Paste your Claude or Gemini API key on the page that opens.${NL}3. The key is encrypted on the phone with a one-time pad from this QR code, kept in memory only, and wiped after $AiSessionMin minutes or on Log out.${NL}${NL}Phone and PC must be on the same network (Wi-Fi or phone hotspot).")
$lblCount = New-Ctl 'Label' $pnlLogin 400 158 540 22 ''
$btnNewQr = New-Ctl 'Button' $pnlLogin 400 184 170 32 'New QR code'
Add-Help $pnlLogin 576 188 'AI login' ("Each QR code works for one successful login, expires after $AiPairingMin minutes and stops after 5 bad attempts.${NL}${NL}The QR code carries a random one-time pad that never crosses the network, so someone sniffing the Wi-Fi only sees scrambled data. The key is never written to disk.${NL}${NL}The first time on each PC, Windows Firewall may ask about PowerShell: allow Private networks. If the phone page will not load, that prompt is usually the cause.${NL}${NL}Use a dedicated API key with a low spend limit on shared PCs.")
$lblNotice = New-Ctl 'Label' $pnlLogin 400 226 540 44 ''
$lblNotice.ForeColor = 'DarkRed'
$lblKeys = New-Ctl 'Label' $pnlLogin 400 276 540 110 ("Where to get a key:${NL}- Claude: console.anthropic.com > API Keys (pay as you go; set a low spend limit).${NL}- Gemini: aistudio.google.com > Get API key (free tier; Google may use free-tier content to improve its products, so avoid sensitive logs).")
$lblKeys.ForeColor = 'DimGray'

$pnlMain = New-Object Windows.Forms.Panel; $pnlMain.Dock = 'Fill'; $pnlMain.Visible = $false; $tpAI.Controls.Add($pnlMain)
[void](New-Ctl 'Label' $pnlMain 12 11 88 20 'Analyze with:')
$cmbAi = New-Ctl 'ComboBox' $pnlMain 102 8 200 24
[void]$cmbAi.Items.AddRange(@('Claude (Anthropic)', 'Gemini (Google)'))
$cmbAi.SelectedIndex = 0
$lblSession = New-Ctl 'Label' $pnlMain 320 11 300 20 ''
$btnLogout  = New-Ctl 'Button' $pnlMain 836 6 104 28 'Log out'
$btnAiBrowse    = New-Ctl 'Button' $pnlMain 12 40 100 28 'Browse...'
$btnAiFolder    = New-Ctl 'Button' $pnlMain 116 40 110 28 'Add folder...'
$btnAiCollected = New-Ctl 'Button' $pnlMain 230 40 150 28 'Add collected logs'
$btnAiRemove    = New-Ctl 'Button' $pnlMain 384 40 120 28 'Remove selected'
$btnAiClear     = New-Ctl 'Button' $pnlMain 508 40 70 28 'Clear'
Add-Help $pnlMain 584 42 'Files for analysis' ("Logs and pictures go to the AI together in one request.${NL}${NL}- Logs: .log .txt .csv .xml .json .evtx (event logs: errors and warnings, newest 400). Each log is trimmed to its newest $AiMaxFileChars characters and all logs together to $AiMaxTotalChars.${NL}- Pictures: .png .jpg .gif .webp, plus .bmp / .tif which are converted. Screenshots larger than $AiImageMaxEdge px or 4.5 MB are shrunk to JPEG to save bandwidth.${NL}- Add folder adds the logs and pictures in a folder (and its subfolders).${NL}- Add collected logs adds the key files from the last Collect Logs run.${NL}${NL}Windows blocks drag-and-drop from Explorer into admin windows, so use Browse (drag-and-drop does work in WinPE).")
$lstAi = New-Ctl 'ListBox' $pnlMain 12 72 928 88
$lstAi.SelectionMode = 'MultiExtended'; $lstAi.HorizontalScrollbar = $true; $lstAi.AllowDrop = $true
[void](New-Ctl 'Label' $pnlMain 12 164 300 18 'Prompt (optional):')
$txtPrompt = New-Ctl 'TextBox' $pnlMain 12 182 928 46 'Analyze these files. Identify errors, likely root causes, and recommended fixes.'
$txtPrompt.Multiline = $true; $txtPrompt.ScrollBars = 'Vertical'
$btnAiGo = New-Ctl 'Button' $pnlMain 12 234 820 34 'Upload && Analyze'
$btnAiGo.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
$btnAiCancel = New-Ctl 'Button' $pnlMain 838 234 102 34 'Cancel'
$btnAiCancel.Enabled = $false
[void](New-Ctl 'Label' $pnlMain 12 278 70 20 'Analysis:')
$lblAiStatus = New-Ctl 'Label' $pnlMain 84 278 680 20 'Ready.'
$btnAiCopy = New-Ctl 'Button' $pnlMain 776 274 80 26 'Copy'
$btnAiSave = New-Ctl 'Button' $pnlMain 860 274 80 26 'Save...'
$txtAiOut = New-Ctl 'TextBox' $pnlMain 12 304 928 134
$txtAiOut.Multiline = $true; $txtAiOut.ReadOnly = $true; $txtAiOut.ScrollBars = 'Vertical'; $txtAiOut.BackColor = [Drawing.Color]::White

#endregion AI-ANALYZE
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
#region AI-ANALYZE
Set-Anchor 'Top,Right'             @($btnLogout, $btnAiCancel, $btnAiCopy, $btnAiSave)
Set-Anchor 'Top,Left,Right'        @($lstAi, $txtPrompt, $btnAiGo, $lblAiStatus)
Set-Anchor 'Top,Bottom,Left,Right' @($txtAiOut)
#endregion AI-ANALYZE
Set-Anchor 'Top,Left,Right'        @($cmbDisk, $cmbPart, $lstMounts, $lblBcd, $lblSafeInfo, $lblDep, $lblExp, $cmbEsp, $cmbTool, $lblToolDesc, $lblToolNote)
Set-Anchor 'Top,Right'             @($btnRefresh, $btnUnmount, $btnUnmountAll, $btnEspRefresh, $btnToolHelp)
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
#region AI-ANALYZE
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tpAI -and -not $script:ApiKey -and -not $script:Listener) { Safe { Show-NewQr } }
})
#endregion AI-ANALYZE

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
#region AI-ANALYZE
$btnColToAi.Add_Click({ Safe {
    $root = $script:LastCollect
    if (-not $root) { $root = [Environment]::ExpandEnvironmentVariables($txtColOut.Text.Trim().Trim('"')) }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { Msg 'Collect logs first (or point the output folder at an existing logs folder).' 'Send to AI' 'Warning'; return }
    $list = @(Get-KeyLogs $root)
    if (-not $list.Count) { Msg "No key log files found in $root." 'Send to AI' 'Warning'; return }
    $n = Add-AiFiles $list
    Log "Added $n key log file(s) from $root to the AI Analyze tab."
    $tabs.SelectedTab = $tpAI
} })
#endregion AI-ANALYZE

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

#region AI-ANALYZE
# ---- 3. AI Analyze ----
$btnNewQr.Add_Click({ $lblNotice.Text = ''; Safe { Show-NewQr } })
$btnLogout.Add_Click({ Exit-Session 'Logged out. Key and files cleared from this PC.' })
$cmbAi.Add_SelectedIndexChanged({
    if ($cmbAi.SelectedIndex -eq 1) { $lblAiStatus.Text = 'Gemini free tier: Google may use content to improve its products. Avoid sensitive logs.' }
    else { $lblAiStatus.Text = 'Ready.' }
})
$btnAiBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Filter = 'Logs and images|*.log;*.txt;*.csv;*.evtx;*.json;*.xml;*.ini;*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp;*.tif;*.tiff|All files|*.*'
    if ($dlg.ShowDialog() -eq 'OK') { [void](Add-AiFiles $dlg.FileNames) }
})
$btnAiFolder.Add_Click({ Safe {
    $fb = New-Object Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Add the logs and pictures in this folder (and its subfolders)'
    if ($fb.ShowDialog() -ne 'OK') { return }
    $found = @(Get-ChildItem -LiteralPath $fb.SelectedPath -Recurse -File -Force -ErrorAction SilentlyContinue |
               Where-Object { $AiFolderTypes -contains $_.Extension.ToLower() -and $_.Length -lt 500MB } |
               Select-Object -First 60 | ForEach-Object { $_.FullName })
    if (-not $found.Count) { Msg 'No logs or pictures found in that folder.' 'Add folder' 'Warning'; return }
    $n = Add-AiFiles $found
    Log "AI: added $n file(s) from $($fb.SelectedPath)."
} })
$btnAiCollected.Add_Click({ Safe {
    $root = $script:LastCollect
    if (-not $root) { $root = [Environment]::ExpandEnvironmentVariables($txtColOut.Text.Trim().Trim('"')) }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { Msg 'Run Collect Logs first.' 'Add collected logs' 'Warning'; return }
    $list = @(Get-KeyLogs $root)
    if (-not $list.Count) { Msg "No key log files found in $root." 'Add collected logs' 'Warning'; return }
    [void](Add-AiFiles $list)
} })
$btnAiRemove.Add_Click({
    foreach ($i in @($lstAi.SelectedItems)) { $aiFiles.Remove($i); $lstAi.Items.Remove($i) }
    $lblAiStatus.Text = "$($aiFiles.Count) file(s) selected."
})
$btnAiClear.Add_Click({ $aiFiles.Clear(); $lstAi.Items.Clear(); $lblAiStatus.Text = 'Cleared.' })
$lstAi.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$lstAi.Add_DragDrop({ [void](Add-AiFiles $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) })
$btnAiGo.Add_Click({ Safe {
    if (-not $script:ApiKey -or (Get-Date) -gt $script:SessionEnd) { Exit-Session 'Session ended. Scan a new QR code.'; return }
    if ($script:AiJob) { return }
    if ($aiFiles.Count -eq 0) { Msg 'Add at least one file.' 'AI Analyze' 'Warning'; return }
    $gemini      = ($cmbAi.SelectedIndex -eq 1)
    $isGeminiKey = $script:ApiKey.StartsWith('AIza')
    if ($gemini -ne $isGeminiKey) {
        $want = 'Claude'; if ($isGeminiKey) { $want = 'Gemini' }
        Msg "The selected AI does not match the key you logged in with. Switch the dropdown to $want, or log out and scan again with the other key." 'AI Analyze' 'Warning'
        return
    }
    $form.Cursor = 'WaitCursor'; $lblAiStatus.Text = 'Preparing files...'; $form.Refresh()
    try { $req = New-AiRequest $gemini } finally { $form.Cursor = 'Default' }
    if ($req.Notes.Count) { Log ('AI: ' + ($req.Notes -join '; ')) }
    $txtAiOut.Clear()
    Start-AiRequest $req $gemini
    $btnAiGo.Enabled = $false; $btnAiCancel.Enabled = $true
    $mb = '{0:N1}' -f ($req.Body.Length / 1MB)
    $lblAiStatus.Text = "Analyzing ($mb MB sent)... the window stays usable; this can take a minute."
    Log "AI: request sent to $($cmbAi.SelectedItem) ($($aiFiles.Count) file(s), $mb MB)."
} })
$btnAiCancel.Add_Click({ Stop-AiRequest; $lblAiStatus.Text = 'Cancelling...' })
$btnAiCopy.Add_Click({ if ($txtAiOut.Text) { [Windows.Forms.Clipboard]::SetText($txtAiOut.Text); $lblAiStatus.Text = 'Analysis copied to the clipboard.' } })
$btnAiSave.Add_Click({ Safe {
    if (-not $txtAiOut.Text) { Msg 'Nothing to save yet.'; return }
    $d = New-Object Windows.Forms.SaveFileDialog
    $d.Filter = 'Text file (*.txt)|*.txt'; $d.FileName = ('AI_analysis_{0:yyyyMMdd_HHmm}.txt' -f (Get-Date))
    if ($script:LastCollect -and (Test-Path -LiteralPath $script:LastCollect)) { $d.InitialDirectory = $script:LastCollect } else { $d.InitialDirectory = $DataDir }
    if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText($d.FileName, $txtAiOut.Text); Log "Analysis saved: $($d.FileName)" }
} })

# ---- shared timer: QR pairing, session countdown, finished AI requests ----
$timer.Add_Tick({
    try {
        $now = Get-Date
        if ($script:AiJob -and $script:AiJob.Handle.IsCompleted) { Complete-AiRequest }
        if (-not $script:ApiKey) {
            if ($script:Listener) {
                if ($now -gt $script:PairExpires -or $script:Attempts -ge 5 -or $script:PairConns -ge 40) {
                    if ($script:PairConns -ge 40) { Log 'AI pairing: too many connections to the pairing port (another device on the network?) - QR code cancelled.' }
                    Clear-Qr
                    $lblCount.Text = 'This QR code is no longer valid. Click "New QR code".'
                } else {
                    $lblCount.Text = 'Waiting for your phone... code valid for ' + ($script:PairExpires - $now).ToString('m\:ss')
                    # at most 3 clients per tick: this runs on the GUI thread, so a flood of connections must not freeze the window
                    $n = 0
                    while ($script:Listener -and $n -lt 3 -and $script:Listener.Pending()) {
                        $n++
                        $c = $script:Listener.AcceptTcpClient()
                        try { Invoke-PairClient $c } catch {} finally { $c.Close() }
                        if ($script:ApiKey) { break }
                    }
                    if ($script:ApiKey) { Enter-Session }
                }
            }
        } else {
            $left = $script:SessionEnd - $now
            if ($left.TotalSeconds -le 0) { Exit-Session "Your $AiSessionMin-minute session ended. Scan a new QR code to continue." }
            else { $lblSession.Text = 'Session ends in ' + $left.ToString('hh\:mm\:ss') }
        }
    } catch {
        if (-not $script:TickErr) { $script:TickErr = $true; Log "Timer error: $($_.Exception.Message)" }
    }
})

#endregion AI-ANALYZE

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
    if ($def.Run) { & $def.Run $def.RunArg }
    elseif ($def.Window) {
        # PowerShell console with every argument single-quoted: no cmd.exe parsing, so & ^ % ( ) in paths are safe
        Log $def.Line
        $cmd = "& '" + (Esc-Sq $def.Exe) + "' " + ((@($def.Argv) | ForEach-Object { "'" + (Esc-Sq ([string]$_)) + "'" }) -join ' ') +
               "`r`nWrite-Host ''; Write-Host ('Exit code: ' + `$LASTEXITCODE); Read-Host 'Press Enter to close this window'"
        $p = Start-Process -FilePath $PsExePath -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd)))
        [void]$script:Consoles.Add($p)
    }
    else {
        Log $def.Line
        $o = (& $def.Exe @($def.Argv) 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ } }) -join $NL
        $rc = $LASTEXITCODE; Log $o.Trim()
        if ($rc -ne 0) { Msg "$($def.Exe) failed (exit code $rc):${NL}${NL}$($o.Trim())" $tool.Name 'Error' } else { Msg ("Done:${NL}${NL}" + $o.Trim()) $tool.Name }
    }
} })

# ---- form ----
$form.Add_Shown({
    # start the shared timer FIRST: if a startup step below fails, the AI login must still work
    $timer.Start()
    Safe {
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
    try { $timer.Stop() } catch {}
    Stop-AiRequest; Stop-Pairing; $script:ApiKey = $null # [AI]
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
