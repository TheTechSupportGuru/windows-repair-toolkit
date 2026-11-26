#requires -Version 5.1
# Version 2.0 (2026-11-26). What changed: docs/changes/V2.0.md
# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file or https://www.gnu.org/licenses/.
<#
  Collect-Logs.ps1  -  Windows 11 log collector
  Copies Windows Update / DISM-CBS / Event Viewer / crash / setup logs
  into  <Desktop of logged-in user>\logs
  Right-click > "Run with PowerShell"  (it will ask for admin rights itself)
#>

# ---------- 64-bit + admin ----------
# A 32-bit host (some file managers, old launchers) would see SysWOW64 and a redirected registry: relaunch 64-bit first.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    exit
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" -ErrorAction Stop
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show("The log collector needs administrator rights, and the UAC prompt was cancelled or failed:`r`n`r`n$($_.Exception.Message)", 'Windows Log Collector', 'OK', 'Warning')
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
Show-WrtSplash 'Collect-Logs'

$W = $env:SystemDrive     # Windows drive (was hard-coded C:)

# ---------- find the logged-in user's profile + desktop ----------
function Get-InteractiveUser {
    $profilePath = $env:USERPROFILE
    $desktop     = [Environment]::GetFolderPath('Desktop')
    try {
        $u = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($u) {
            $sid  = (New-Object Security.Principal.NTAccount($u)).Translate([Security.Principal.SecurityIdentifier]).Value
            $prof = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath
            if ($prof) { $profilePath = $prof }
            # read the RAW value: Get-ItemProperty would expand %USERPROFILE% with the profile of whoever ELEVATED
            # (e.g. a different admin account), sending the logs to the wrong Desktop. (Same fix as WinSuperTool.)
            $key = Get-Item -LiteralPath "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop
            $raw = $key.GetValue('Desktop', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($raw) {
                $d = [regex]::Replace([string]$raw, '%USERPROFILE%', $profilePath.Replace('$', '$$'), 'IgnoreCase')
                $desktop = [Environment]::ExpandEnvironmentVariables($d)
            }
        }
    } catch {}
    [pscustomobject]@{ Profile = $profilePath; Desktop = $desktop }
}
$usr     = Get-InteractiveUser
$LogRoot = Join-Path $usr.Desktop 'logs'

# ---------- helpers ----------
$script:count = 0
$script:fail  = 0
$script:Busy  = $false
$script:StopRequested = $false

function Say([string]$m) {
    $txtOut.AppendText($m + "`r`n")
    [System.Windows.Forms.Application]::DoEvents()     # keeps the window responsive (and lets "Stop" be clicked)
}
function Fmt-Size($b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }

function Copy-One([string]$s, [string]$d) {
    try { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($d)) } catch {}
    try {
        [IO.File]::Copy($s, $d, $true)          # much faster than Copy-Item for thousands of small files
        $script:count++
    } catch {
        # fallback for files held open by Windows (shared read)
        $in = $null; $out = $null; $ok = $false
        try {
            $in  = [IO.File]::Open($s, 'Open', 'Read', 'ReadWrite,Delete')
            $out = [IO.File]::Create($d)
            $in.CopyTo($out)
            $script:count++; $ok = $true
        } catch {
            $script:fail++
            Say "   FAILED: $s"
        } finally {
            if ($out) { $out.Dispose() }
            if ($in)  { $in.Dispose() }
            if (-not $ok -and $out) { try { [IO.File]::Delete($d) } catch {} }   # no half-written file in the output
        }
    }
}

# Copies a file, wildcard, or whole folder (recursively) into $dest
function Copy-Safe([string]$src, [string]$dest) {
    if ($script:StopRequested) { return }
    if (Test-Path -LiteralPath $src -PathType Container) {
        $root  = (Get-Item -LiteralPath $src -Force).FullName.TrimEnd('\')
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        if (-not $files.Count) { Say "   (empty) $src"; return }
        $leaf = Split-Path $root -Leaf
        $i = 0
        foreach ($f in $files) {
            if ($script:StopRequested) { Say '   stopped.'; return }
            $rel = $f.FullName.Substring($root.Length).TrimStart('\')
            Copy-One $f.FullName (Join-Path (Join-Path $dest $leaf) $rel)
            if ((++$i % 25) -eq 0) { Say "   ... $i / $($files.Count) files from $leaf" }
        }
    } else {
        $files = @(Get-ChildItem -Path $src -File -Force -ErrorAction SilentlyContinue)
        if (-not $files.Count) { Say "   (not found) $src"; return }
        foreach ($f in $files) { Copy-One $f.FullName (Join-Path $dest $f.Name) }
    }
}

function Export-Evt([string]$name, [string]$dest) {
    if ($script:StopRequested) { return }
    [void][IO.Directory]::CreateDirectory($dest)
    $file = Join-Path $dest (($name -replace '[\\/]', '%4') + '.evtx')
    $o = (& wevtutil.exe epl $name $file /ow:true 2>&1 | ForEach-Object { [string]$_ }) -join ' '
    # 15007 = channel does not exist (language-independent). Anything else is a real failure (path, access, disk full).
    if ($LASTEXITCODE -eq 0) { $script:count++ }
    elseif ($LASTEXITCODE -eq 15007) { Say "   skipped (channel does not exist on this Windows): $name" }
    else { $script:fail++; Say "   FAILED (wevtutil exit code $LASTEXITCODE): $name - $($o.Trim())" }
}

# ---------- collectors ----------
$Collectors = [ordered]@{

'WU' = @{ Label = 'Windows Update (ETL, ReportingEvents, USO, WaaSMedic, merged WindowsUpdate.log)'; Run = {
    $d = Join-Path $LogRoot '1_WindowsUpdate'
    Copy-Safe "$W\Windows\Logs\WindowsUpdate"                          $d
    Copy-Safe "$W\Windows\SoftwareDistribution\ReportingEvents.log"    $d
    Copy-Safe "$W\Windows\WindowsUpdate.log"                           $d
    Copy-Safe "$W\Windows\Logs\waasmedic"                              $d
    Copy-Safe "$W\Windows\Logs\SIH"                                    $d
    Copy-Safe "$W\ProgramData\USOShared\Logs"                          $d
    if ($script:StopRequested) { return }
    if (Get-Command Get-WindowsUpdateLog -ErrorAction SilentlyContinue) {
        Say '   Building merged WindowsUpdate.log (can take a minute)...'
        try {
            Get-WindowsUpdateLog -LogPath (Join-Path $d 'WindowsUpdate_merged.log') -ErrorAction Stop | Out-Null
            $script:count++
        } catch { $script:fail++; Say "   Get-WindowsUpdateLog failed: $($_.Exception.Message)" }
    } else { Say '   Get-WindowsUpdateLog is not available here; the raw .etl traces were copied.' }
}}

'DISM' = @{ Label = 'DISM / CBS / servicing (dism.log, CBS.log, pending.xml, setupapi)'; Run = {
    $d = Join-Path $LogRoot '2_DISM_CBS'
    Copy-Safe "$W\Windows\Logs\DISM"                       $d
    Copy-Safe "$W\Windows\Logs\CBS"                        $d
    Copy-Safe "$W\Windows\Logs\DPX"                        $d
    Copy-Safe "$W\Windows\servicing\Sessions\Sessions.xml" $d
    Copy-Safe "$W\Windows\WinSxS\pending.xml"              $d
    Copy-Safe "$W\Windows\WinSxS\poqexec.log"              $d
    Copy-Safe "$W\Windows\inf\setupapi*.log"               $d
}}

'EVT' = @{ Label = 'Event Viewer - key logs exported (System, Application, Setup, WU client, etc.)'; Run = {
    $d = Join-Path $LogRoot '3_EventViewer'
    $channels = @(
        'System','Application','Setup',
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
    foreach ($c in $channels) { Export-Evt $c $d }
}}

'SEC' = @{ Label = 'Event Viewer - Security log (large, sensitive)'; Run = {
    Export-Evt 'Security' (Join-Path $LogRoot '3_EventViewer')
}}

'EVTALL' = @{ Label = 'Event Viewer - ALL raw .evtx files (can be hundreds of MB)'; Run = {
    $d = Join-Path $LogRoot '3b_EventViewer_AllRaw'
    Copy-Safe "$W\Windows\System32\winevt\Logs" $d
}}

'CRASH' = @{ Label = 'Crashes (Minidumps, WER reports, user CrashDumps, reliability history, bugcheck events)'; Run = {
    $d = Join-Path $LogRoot '4_Crashes'
    Copy-Safe "$W\Windows\Minidump"                                     $d
    Copy-Safe "$W\ProgramData\Microsoft\Windows\WER\ReportArchive"      $d
    Copy-Safe "$W\ProgramData\Microsoft\Windows\WER\ReportQueue"        $d
    Copy-Safe (Join-Path $usr.Profile 'AppData\Local\CrashDumps')       $d
    Copy-Safe (Join-Path $usr.Profile 'AppData\Local\Microsoft\Windows\WER') (Join-Path $d 'UserWER')
    if ($script:StopRequested) { return }
    [void][IO.Directory]::CreateDirectory($d)
    try {
        Get-CimInstance Win32_ReliabilityRecords -ErrorAction Stop |
            Select-Object TimeGenerated, SourceName, EventIdentifier, ProductName, Message |
            Export-Csv -LiteralPath (Join-Path $d 'ReliabilityHistory.csv') -NoTypeInformation
        $script:count++
    } catch { Say '   Reliability history unavailable' }
    try {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Id=41,1001,1074,1076,6005,6006,6008 } -ErrorAction Stop |
            Format-List TimeCreated, Id, ProviderName, Message |
            Out-File -LiteralPath (Join-Path $d 'Crash_Shutdown_Events.txt') -Width 250
        $script:count++
    } catch {
        # "no events" is normal; anything else (access denied, broken log) is a real failure
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { Say '   No crash/shutdown events found' }
        else { $script:fail++; Say "   Crash/shutdown events FAILED: $($_.Exception.Message)" }
    }
}}

'BIG' = @{ Label = 'LARGE dumps (MEMORY.DMP + LiveKernelReports) - can be several GB'; Run = {
    $d = Join-Path $LogRoot '4b_LargeDumps'
    # check free space first (only existing paths, -LiteralPath: a missing path with -Recurse would search all of Windows)
    $need = 0
    foreach ($bp in "$W\Windows\MEMORY.DMP", "$W\Windows\LiveKernelReports") {
        if (Test-Path -LiteralPath $bp) { $need += [long](Get-ChildItem -LiteralPath $bp -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
    }
    $free = try { (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($LogRoot))).AvailableFreeSpace } catch { [long]::MaxValue }
    if ($need -and $need -gt ($free - 512MB)) { $script:fail++; Say ('   SKIPPED: the dumps need {0}, only {1} free on the output drive.' -f (Fmt-Size $need), (Fmt-Size $free)); return }
    Copy-Safe "$W\Windows\MEMORY.DMP"          $d
    Copy-Safe "$W\Windows\LiveKernelReports"   $d
}}

'SETUP' = @{ Label = 'Setup / feature-upgrade logs (Panther, $WINDOWS.~BT, Rollback, MoSetup)'; Run = {
    $d = Join-Path $LogRoot '5_SetupUpgrade'
    Copy-Safe "$W\Windows\Panther"                           (Join-Path $d 'Windows_Panther')
    Copy-Safe (Join-Path $W '$WINDOWS.~BT\Sources\Panther')  (Join-Path $d 'BT_Panther')
    Copy-Safe (Join-Path $W '$WINDOWS.~BT\Sources\Rollback') (Join-Path $d 'BT_Rollback')
    Copy-Safe (Join-Path $W '$Windows.~WS\Sources\Panther')  (Join-Path $d 'WS_Panther')
    Copy-Safe "$W\Windows\Logs\MoSetup"                      $d
    Copy-Safe "$W\Windows\System32\Sysprep\Panther"          (Join-Path $d 'Sysprep_Panther')
    Copy-Safe "$W\Windows\setupact.log"                      $d
    Copy-Safe "$W\Windows\setuperr.log"                      $d
}}

'INFO' = @{ Label = 'System info (systeminfo, installed hotfixes, DISM packages list)'; Run = {
    $d = Join-Path $LogRoot '6_SystemInfo'
    [void][IO.Directory]::CreateDirectory($d)
    # count only what really worked (it used to add 2 whatever happened)
    & systeminfo.exe 2>&1 | Out-File -LiteralPath (Join-Path $d 'systeminfo.txt')
    if ($LASTEXITCODE -eq 0) { $script:count++ } else { $script:fail++; Say "   systeminfo failed (exit code $LASTEXITCODE)" }
    try { Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Format-Table -AutoSize | Out-File -LiteralPath (Join-Path $d 'hotfixes.txt') -Width 250; $script:count++ }
    catch { $script:fail++; Say "   hotfix list failed: $($_.Exception.Message)" }
    try {
        Get-WindowsPackage -Online -ErrorAction Stop | Format-Table PackageName, PackageState, InstallTime -AutoSize |
            Out-File -LiteralPath (Join-Path $d 'dism_packages.txt') -Width 300
        $script:count++
    } catch { $script:fail++; Say "   package list failed: $($_.Exception.Message)" }
}}
}

# ---------- GUI ----------
$form = New-Object Windows.Forms.Form; Set-WrtScaling $form
$form.Text = 'Windows Log Collector'
$form.Size = New-Object Drawing.Size(640, 640)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

$lbl = New-Object Windows.Forms.Label
$lbl.Text = "Select logs to collect.`nOutput: $LogRoot"
$lbl.Location = '12,10'; $lbl.Size = '600,38'
$form.Controls.Add($lbl)

$boxes = @{}
$y = 55
foreach ($k in $Collectors.Keys) {
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = $Collectors[$k].Label
    $cb.Location = "16,$y"; $cb.Size = '590,24'
    $cb.Checked = ($k -in 'WU','DISM','EVT','CRASH')
    $form.Controls.Add($cb)
    $boxes[$k] = $cb
    $y += 28
}

$btnAll = New-Object Windows.Forms.Button
$btnAll.Text = 'Select / clear all'; $btnAll.Location = "16,$($y+8)"; $btnAll.Size = '130,30'
$btnAll.Add_Click({
    $any = $boxes.Values | Where-Object { -not $_.Checked }
    foreach ($b in $boxes.Values) { $b.Checked = [bool]$any }
})
$form.Controls.Add($btnAll)

$btnGo = New-Object Windows.Forms.Button
$btnGo.Text = 'Submit'; $btnGo.Location = "160,$($y+8)"; $btnGo.Size = '130,30'
$form.Controls.Add($btnGo)

$btnStop = New-Object Windows.Forms.Button
$btnStop.Text = 'Stop'; $btnStop.Location = "304,$($y+8)"; $btnStop.Size = '90,30'; $btnStop.Enabled = $false
$btnStop.Add_Click({ $script:StopRequested = $true; $btnStop.Enabled = $false; Say '   Stopping after the current file...' })
$form.Controls.Add($btnStop)

$txtOut = New-Object Windows.Forms.TextBox
$txtOut.Multiline = $true; $txtOut.ScrollBars = 'Vertical'; $txtOut.ReadOnly = $true
$txtOut.Location = "16,$($y+50)"; $txtOut.Size = "590,$(600 - ($y+50) - 40)"
$txtOut.Font = New-Object Drawing.Font('Consolas', 9)
$form.Controls.Add($txtOut)

# The copy runs on the window's thread (Say keeps it responsive). Closing the window mid-run used to leave the
# copy running hidden in the background; now closing is refused until it ends - use Stop first.
$form.Add_FormClosing({
    param($s, $e)
    if ($script:Busy) {
        $e.Cancel = $true
        [void][Windows.Forms.MessageBox]::Show('Logs are still being collected. Press Stop first, then close the window.', 'Windows Log Collector')
    }
})

$btnGo.Add_Click({
    $sel = @($Collectors.Keys | Where-Object { $boxes[$_].Checked })
    if (-not $sel) { [Windows.Forms.MessageBox]::Show('Pick at least one item.') | Out-Null; return }
    $btnGo.Enabled = $false; $btnAll.Enabled = $false; $btnStop.Enabled = $true
    $script:Busy = $true; $script:StopRequested = $false
    $script:count = 0; $script:fail = 0
    $txtOut.Clear()      # the summary file used to contain every earlier run of this session too
    try {
        [void][IO.Directory]::CreateDirectory($LogRoot)
        Say "Started $(Get-Date)  ->  $LogRoot"
        foreach ($k in $sel) {
            if ($script:StopRequested) { break }
            Say "`r`n[$k] $($Collectors[$k].Label)"
            try { & $Collectors[$k].Run } catch { $script:fail++; Say "   ERROR: $($_.Exception.Message)" }
        }
        $how = if ($script:StopRequested) { 'STOPPED by you' } else { 'Done' }
        Say "`r`n$how. Files copied/exported: $($script:count)   Failed: $($script:fail)"
        try { $txtOut.Text | Out-File -LiteralPath (Join-Path $LogRoot '_collection_summary.txt') -ErrorAction Stop } catch { Say "   Could not write the summary file: $($_.Exception.Message)" }
        Start-Process explorer.exe $LogRoot
    } catch {
        Say "ERROR: $($_.Exception.Message)"
    } finally {
        # always give the buttons back, even after an unexpected error
        $script:Busy = $false
        $btnGo.Enabled = $true; $btnAll.Enabled = $true; $btnStop.Enabled = $false
    }
})

# resizing (1.8.1): the output box grows with the window
function Set-Anchor([string]$a, [object[]]$ctls) { foreach ($c in $ctls) { if ($c) { $c.Anchor = $a } } }
Set-Anchor 'Top,Left,Right'        @($lbl)
Set-Anchor 'Top,Bottom,Left,Right' @($txtOut)
Initialize-WrtWindow $form @() 640 560
[void]$form.ShowDialog()
