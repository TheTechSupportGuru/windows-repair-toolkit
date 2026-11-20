# Version 1.8.2 (2026-11-20). What changed: docs/changes/V1.8.2.md
# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file or https://www.gnu.org/licenses/.
<#
.SYNOPSIS
  WinFixKit - Windows troubleshooting power tool (replacement for the retired .diagcab troubleshooters).

.DESCRIPTION
  One tab per troubleshooter. Every tab has:
    * "Check status"  - read-only snapshot of the current state (services, DNS, ARP, routes, devices...)
    * Fix buttons     - each one takes a BEFORE snapshot, runs the fix, then takes an AFTER snapshot
    * "?" buttons     - explain exactly what a button does, which commands it runs, and the risks
  Everything shown is also written to a session log on the Desktop (WinFixKit\Logs).
  Folders are renamed with a timestamp instead of deleted wherever possible, so fixes can be undone.

  Run it with Launch-WinFixKit.bat (hidden console, bypasses execution policy) or:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinFixKit.ps1
  Status checks work as a normal user. Fixes need an elevated (administrator) session -
  use the "Relaunch as Administrator" button at the bottom.
#>
#Requires -Version 5.1
param([string]$DataRoot)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------------------------
#  Window helpers - the same block in every Windows Repair Toolkit tool (since 1.8.1):
#  display scaling, splash screen, fit to screen, scrolling instead of squeezing.
# ---------------------------------------------------------------------------------------------
# Sharp, unclipped text on 125 % / 150 % / 200 % displays: this process scales its own windows
# (AutoScaleMode Dpi on every form) instead of Windows stretching a blurry bitmap of them.
try { Add-Type -Namespace WrtUi -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop; [void][WrtUi.Dpi]::SetProcessDPIAware() } catch {}
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
    try { $script:WrtSplash.Close(); $script:WrtSplash.Dispose() } catch {}
    $script:WrtSplash = $null
}
# Call right before ShowDialog. Records how much room each scrollable area ($scroll: tab pages, panels) needs at its
# design size, so a small window scrolls instead of squeezing the controls together; sets the minimum size; opens
# maximized when the scaled window does not fit on the screen; then closes the splash screen.
function Initialize-WrtWindow($f, $scroll = @(), [int]$minW = 640, [int]$minH = 460) {
    $script:WrtForm = $f; $script:WrtMinWH = @($minW, $minH); $script:WrtExt = New-Object Collections.ArrayList
    foreach ($c in @($scroll)) {
        if (-not $c) { continue }
        $w = 0; $h = 0
        foreach ($k in $c.Controls) { if ($k.Dock -eq 'None') { $w = [Math]::Max($w, $k.Right); $h = [Math]::Max($h, $k.Bottom) } }
        [void]$script:WrtExt.Add(@($c, $w, $h))
    }
    $f.Add_Shown({ Complete-WrtWindow })
}
function Complete-WrtWindow {
    $f = $script:WrtForm; $k = Get-WrtScale $f
    foreach ($e in $script:WrtExt) { try { if ($e[1] -gt 0) { $e[0].AutoScroll = $true; $e[0].AutoScrollMinSize = New-Object Drawing.Size([int](($e[1] + 8) * $k), [int](($e[2] + 8) * $k)) } } catch {} }
    try { $f.MinimumSize = New-Object Drawing.Size([int]($script:WrtMinWH[0] * $k), [int]($script:WrtMinWH[1] * $k)) } catch {}
    try { $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea; if ($f.Width -gt $wa.Width -or $f.Height -gt $wa.Height) { $f.WindowState = 'Maximized' } } catch {}
    Close-WrtSplash
    try { $f.Activate() } catch {}
}
Show-WrtSplash 'WinFixKit'
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------------------------
#  ONE folder on the Desktop holds everything:  Desktop\WinFixKit\
#     Logs\              session logs and window transcripts
#     Reports\           saved reports, driver lists, battery/energy reports, ACL backups
#     RegistryBackups\   Keys\ (per-item originals, one-click restore) and Full\ (hive copies)
#  The path is passed along when relaunching as admin so both sessions use the same folder.
# ---------------------------------------------------------------------------------------------
if (-not $DataRoot) { $DataRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'WinFixKit' }
$script:RootDir    = $DataRoot
$script:LogDir     = Join-Path $DataRoot 'Logs'
$script:ReportDir  = Join-Path $DataRoot 'Reports'
$script:RegDir     = Join-Path $DataRoot 'RegistryBackups'
$script:RegKeyDir  = Join-Path $script:RegDir 'Keys'
$script:RegFullDir = Join-Path $script:RegDir 'Full'
foreach ($d in $script:RootDir, $script:LogDir, $script:ReportDir, $script:RegDir, $script:RegKeyDir, $script:RegFullDir) {
    $null = New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue
}
$script:LogFile = Join-Path $script:LogDir ("Session-{0}-{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ---------------------------------------------------------------------------------------------
#  Helper functions used by the status checks and fixes
# ---------------------------------------------------------------------------------------------
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Hdr([string]$t) { "`r`n=== $t ===" }

function Table($o) {
    if ($null -eq $o) { return '  (none)' }
    if ($o -is [string]) { return $o }
    $a = @($o)
    if ($a.Count -eq 0) { return '  (none)' }
    if ($a[0] -is [string]) { return ($a -join "`r`n") }
    ($a | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()
}

function Safe([scriptblock]$b) {
    try { & $b } catch { "  (unavailable: $($_.Exception.Message))" }
}

function Svc([string[]]$Names) {
    foreach ($n in $Names) {
        $found = @(Get-Service -Name $n -ErrorAction SilentlyContinue)
        if ($found.Count -eq 0) {
            [pscustomobject]@{ Name = $n; Display = '(not installed)'; Status = '-'; StartType = '-' }
        } else {
            foreach ($s in $found) {
                [pscustomobject]@{ Name = $s.Name; Display = $s.DisplayName; Status = $s.Status; StartType = $s.StartType }
            }
        }
    }
}

function StopSvc([string]$n) {
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
    if (-not $s) { return "Service $n not present (skipped)" }
    try {
        Stop-Service -Name $n -Force -ErrorAction Stop
        $s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(25))
        "Stopped $n"
    } catch { "Could not stop ${n}: $($_.Exception.Message)" }
}

function StartSvc([string]$n) {
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
    if (-not $s) { return "Service $n not present (skipped)" }
    try {
        Start-Service -Name $n -ErrorAction Stop
        "Started $n"
    } catch { "Could not start ${n}: $($_.Exception.Message)" }
}

function Rename-WithStamp([string]$path) {
    if (Test-Path -LiteralPath $path) {
        $newName = (Split-Path $path -Leaf) + '.bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
        try {
            Rename-Item -LiteralPath $path -NewName $newName -ErrorAction Stop
            "Renamed: $path  ->  $newName"
        } catch { "Could not rename ${path}: $($_.Exception.Message)" }
    } else { "Not found (skipped): $path" }
}

# Real on-disk path: follows junctions/symlinks (C:\Documents and Settings -> C:\Users) and expands 8.3 names (C:\PROGRA~1).
function Resolve-RealPath([string]$Path) {
    if (-not ('WfkPath' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class WfkPath {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetFinalPathNameByHandleW(SafeFileHandle h, StringBuilder buf, uint len, uint flags);
    public static string Final(string path) {
        using (SafeFileHandle h = CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
            if (h.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            StringBuilder sb = new StringBuilder(32768);
            uint n = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
            if (n == 0 || n >= sb.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            string s = sb.ToString();
            if (s.StartsWith(@"\\?\UNC\")) return @"\\" + s.Substring(8);
            if (s.StartsWith(@"\\?\")) return s.Substring(4);
            return s;
        }
    }
}
'@
    }
    if ($Path -match '^[A-Za-z]:$') { $Path += '\' }   # bare "C:" means "current folder on C:", not the root
    [WfkPath]::Final($Path).TrimEnd('\')
}

# Returns a reason string if a folder must NOT get recursive takeown + icacls /reset, otherwise $null.
# Works on the REAL path, so junctions and 8.3 short names cannot sneak past the list.
function Test-ProtectedFolder([string]$Path) {
    if ($Path -match '^[A-Za-z]:\\?$') { return "$Path is a drive root" }
    try { $p = Resolve-RealPath $Path } catch { return "cannot resolve the real path ($($_.Exception.Message))" }
    $under = { param($child, $parent) $parent -and ($child -eq $parent -or $child.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) }
    $norm  = { param($x) if ($x) { try { Resolve-RealPath $x } catch { $x.TrimEnd('\') } } }
    if ($p -match '^[A-Za-z]:$' -or $p -match '^\\\\[^\\]+\\[^\\]+$') { return "$p is a drive or share root" }
    # Hidden system folders at the root of ANY drive
    if ($p -match '^(?:[A-Za-z]:|\\\\[^\\]+\\[^\\]+)\\(\$Recycle\.Bin|System Volume Information|Recovery|Boot|EFI|Config\.Msi|\$WinREAgent|\$WINDOWS\.~BT|\$Windows\.~WS|\$SysReset)(\\|$)') { return "$p is a Windows system folder" }
    foreach ($sys in $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData) {
        $s = & $norm $sys
        if (& $under $p $s) { return "$p is inside protected system folder $s" }
    }
    $plKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $usersDir = & $norm ((Get-ItemProperty -LiteralPath $plKey -ErrorAction SilentlyContinue).ProfilesDirectory)
    if (-not $usersDir) { $usersDir = & $norm (Join-Path $env:SystemDrive 'Users') }
    if ($p -eq $usersDir) { return "$p is the Users folder" }
    foreach ($leaf in 'Default', 'Public') { if (& $under $p (Join-Path $usersDir $leaf)) { return "$p is inside the shared $leaf profile" } }
    $profiles = @(Get-ChildItem -LiteralPath $plKey -ErrorAction SilentlyContinue | ForEach-Object { & $norm ((Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath) } | Where-Object { $_ })
    foreach ($pr in $profiles) {
        if ($p -eq $pr) { return "$p is a whole user profile - pick a folder inside it instead" }
        if (& $under $p (Join-Path $pr 'AppData')) { return "$p is inside AppData (app and system data)" }
    }
    return $null
}

function Get-FolderSizeMB([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return 'not found' }
    try {
        $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if (-not $s) { $s = 0 }
        '{0:N1} MB' -f ($s / 1MB)
    } catch { 'unknown' }
}

function Test-TcpPort([string]$h, [int]$port, [int]$ms = 1500) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect($h, $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($ms)
        if ($ok -and $c.Connected) { $c.EndConnect($iar); return $true }
        return $false
    } catch { return $false } finally { $c.Close() }
}

function Get-PendingReboot {
    $r = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $r += 'CBS RebootPending' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $r += 'WindowsUpdate RebootRequired' }
    $p = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($p) { $r += 'PendingFileRenameOperations' }
    if ($r.Count) { 'YES: ' + ($r -join ', ') } else { 'No pending-reboot flags found' }
}

function Get-RecentEvents([hashtable]$filter, [int]$n = 10) {
    try {
        Get-WinEvent -FilterHashtable $filter -MaxEvents $n -ErrorAction Stop |
            Select-Object TimeCreated, Id, LevelDisplayName, @{ n = 'Message'; e = { ($_.Message -split "`r?`n")[0] } }
    } catch { '  (no matching events, or that log is not enabled)' }
}

# powercfg /q labels are translated, so do not match words: each setting starts with a "<GUID>  (<name>)" line, and its
# LAST two hex values (0x...) are always the current AC and DC index (min/max/increment come before them).
function Get-PowerSettings([string]$sub, [string]$setting = '') {
    $name = $null; $hex = @()
    $lines = @(if ($setting) { powercfg /q SCHEME_CURRENT $sub $setting } else { powercfg /q SCHEME_CURRENT $sub }) + '00000000-0000-0000-0000-000000000000  (end)'
    foreach ($line in $lines) {
        if ($line -match '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\s+\((.+)\)\s*$') {
            if ($name -and $hex.Count -ge 2) {
                foreach ($pair in @(@('AC', $hex[-2]), @('DC', $hex[-1]))) {
                    $v = $pair[1]
                    $note = if ($v -eq 0) { '0 (never / off / disabled)' } elseif ($v -ge 60) { "raw $v  (= $([math]::Round($v / 60, 1)) min if this is a timeout in seconds)" } else { "raw $v" }
                    '{0,-44} {1}: {2}' -f $name, $pair[0], $note
                }
            }
            $name = $Matches[2].Trim(); $hex = @()
        } elseif ($line -match ':\s*0x([0-9a-fA-F]+)\s*$') { $hex += [Convert]::ToInt64($Matches[1], 16) }
    }
}

# Firewall rule groups by their language-independent resource IDs (the display names are translated)
$script:FwGroups = [ordered]@{ 'Network Discovery' = '@FirewallAPI.dll,-32752'; 'File and Printer Sharing' = '@FirewallAPI.dll,-28502' }

# Folder of the Windows Search index (honours a moved index: HKLM\SOFTWARE\Microsoft\Windows Search\DataDirectory)
function Get-SearchIndexDir {
    $dd = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Search' -ErrorAction SilentlyContinue).DataDirectory
    if ($dd) { Join-Path ([Environment]::ExpandEnvironmentVariables($dd)) 'Applications\Windows' } else { "$env:ProgramData\Microsoft\Search\Data\Applications\Windows" }
}

# A per-user fix run elevated with ANOTHER account's credentials acts on that account's profile, not the signed-in user's
function Get-WrongUserWarning {
    $console = try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { $null }
    if ($console -and $console -ne "$env:USERDOMAIN\$env:USERNAME") { "WARNING: this tool runs as $env:USERDOMAIN\$env:USERNAME but $console is signed in - per-user fixes act on $env:USERNAME's profile, not on ${console}'s." }
}

# Escape text for a '...' PowerShell string. PowerShell also treats the typographic quotes U+2018-U+201B as
# single quotes (e.g. a profile folder named O<U+2019>Brien), so those must be doubled too, not only '.
function ConvertTo-SqEscaped([string]$s) { $s -replace "(['$([char]0x2018)-$([char]0x201B)])", '$1$1' }

function Start-InWindow([scriptblock]$Block, [string]$Title) {
    $safe = ($Title -replace '[^A-Za-z0-9]+', '-').Trim('-')
    $tl = ConvertTo-SqEscaped (Join-Path $script:LogDir ("{0}-{1}.txt" -f $safe, (Get-Date -Format 'yyyyMMdd-HHmmss')))
    $ld = ConvertTo-SqEscaped $script:LogDir
    $rdp = ConvertTo-SqEscaped $script:ReportDir
    $text = "`$LogDir = '$ld'`r`n`$ReportDir = '$rdp'`r`n`$Host.UI.RawUI.WindowTitle = '$safe'`r`nStart-Transcript -Path '$tl' | Out-Null`r`n" +
            $Block.ToString() +
            "`r`nStop-Transcript | Out-Null`r`nWrite-Host ''`r`nRead-Host 'Finished. Press Enter to close this window'"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc
    "Launched in a separate window. Transcript: $tl"
}

# ---------------------------------------------------------------------------------------------
#  Registry safety net. The FIRST backup of any value/key is kept as "the original" until it is restored.
#  After a restore, the next fix takes a fresh backup (the value may have been changed legitimately since).
#    Keys\<id>.json  = manifest for one-click restore      Keys\<id>.reg = full export of the key
#    Full\<time>\    = SYSTEM + SOFTWARE hive copies (taken once per session before the first registry change)
# ---------------------------------------------------------------------------------------------
$script:FullBackupDone = $false

function ConvertTo-RegExePath([string]$ps) { ($ps -replace '^HKLM:\\?', 'HKLM\') -replace '^HKCU:\\?', 'HKCU\' }

function Get-BackupId([string]$text, [string]$label) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text.ToLower()))).Replace('-', '').Substring(0, 10)
    $slug = ($label -replace '[^A-Za-z0-9]+', '_').Trim('_')
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
    '{0}_{1}' -f $slug, $hash
}

function Get-RegVal([string]$Key, [string]$Name) {
    $p = Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $p) { '(not set)' } else { $p.$Name }
}

# $true while a backup file exists and has NOT been restored yet (= it still holds the value to go back to)
function Test-BackupPending([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return $false }
    try { return (-not (Get-Content -LiteralPath $File -Raw | ConvertFrom-Json).RestoredAt) } catch { return $true }   # unreadable: never overwrite
}

function Backup-RegValue([string]$Key, [string]$Name, [string]$Why = '') {
    $id = Get-BackupId "$Key|$Name" $Name
    $file = Join-Path $script:RegKeyDir "$id.json"
    if (Test-BackupPending $file) { return "  Registry: original of $Key [$Name] is already backed up (kept)." }
    $keyExisted = Test-Path -LiteralPath $Key
    $existed = $false; $kind = $null; $data = $null; $regFile = $null
    if ($keyExisted) {
        $item = Get-Item -LiteralPath $Key
        if ($item.GetValueNames() -contains $Name) {
            $existed = $true
            $kind = $item.GetValueKind($Name).ToString()
            $raw = $item.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            # assign inside the branches: "$data = if ... else { $raw }" would turn an EMPTY multi-string into $null
            if ($raw -is [byte[]]) { $data = [Convert]::ToBase64String($raw) } else { $data = $raw }
        }
        $regFile = "$id.reg"
        reg.exe export (ConvertTo-RegExePath $Key) (Join-Path $script:RegKeyDir $regFile) /y 2>&1 | Out-Null
    }
    $meta = [ordered]@{ Type = 'Value'; Created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Key = $Key; Name = $Name; KeyExisted = $keyExisted; Existed = $existed; Kind = $kind; Data = $data; RegFile = $regFile; Why = $Why; RestoredAt = $null }
    $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $file -Encoding UTF8
    $shown = if (-not $existed) { 'did not exist' } elseif ($kind -eq 'Binary') { '(binary data)' } else { "$data ($kind)" }
    "  Registry: backed up original of $Key [$Name] = $shown"
}

function Backup-RegKey([string]$Key, [string]$Why = '') {
    $leaf = $Key.Substring($Key.LastIndexOf('\') + 1)
    $id = Get-BackupId "$Key|*key*" ($leaf + '_key')
    $file = Join-Path $script:RegKeyDir "$id.json"
    if (Test-BackupPending $file) { return "  Registry: original of key $Key is already backed up (kept)." }
    if (-not (Test-Path -LiteralPath $Key)) { return "  Registry: key $Key does not exist (nothing to back up)." }
    $regFile = "$id.reg"
    reg.exe export (ConvertTo-RegExePath $Key) (Join-Path $script:RegKeyDir $regFile) /y 2>&1 | Out-Null
    $meta = [ordered]@{ Type = 'Key'; Created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Key = $Key; Name = '*'; KeyExisted = $true; Existed = $true; Kind = 'Key export'; Data = $null; RegFile = $regFile; Why = $Why; RestoredAt = $null }
    $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $file -Encoding UTF8
    "  Registry: exported original of key $Key"
}

# netsh winhttp reset proxy overwrites this value (a company proxy would otherwise be lost for good)
function Backup-WinHttpProxy { Backup-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' 'WinHttpSettings' 'winhttp proxy reset' }

function Backup-NetRegKeys {
    foreach ($k in 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters', 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters', 'HKLM:\SYSTEM\CurrentControlSet\Services\Winsock', 'HKLM:\SYSTEM\CurrentControlSet\Services\Winsock2') {
        Backup-RegKey $k 'network reset'
    }
}

function Set-RegValueSafe([string]$Key, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Why = '') {
    Backup-RegValue $Key $Name $Why
    try {
        if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Key -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        "  Set $Key  $Name = $Value ($Type)"
    } catch { "  FAILED to set $Key $Name : $($_.Exception.Message)" }
}

function Set-SvcStartup([string]$Name, [string]$Mode = 'Automatic') {
    if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) { return "Service $Name not present (skipped)" }
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    Backup-RegValue $k 'Start' 'service startup type'
    Backup-RegValue $k 'DelayedAutostart' 'service startup type'
    try { Set-Service -Name $Name -StartupType $Mode -ErrorAction Stop; "Set $Name startup type = $Mode" }
    catch { "Could not set startup for ${Name}: $($_.Exception.Message)" }
}

# Native tools write some normal messages to stderr; with 2>&1 those arrive as ErrorRecords and PowerShell would print
# them as red NativeCommandError blocks. Turn everything into plain text lines.
function ConvertTo-PlainText {
    process {
        $s = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
        if ($s -and $s.Trim() -and $s -ne 'System.Management.Automation.RemoteException') { $s.TrimEnd() }
    }
}

# netsh winsock reset, plus WHICH providers the rebuilt catalog no longer lists (e.g. RFCOMM = Bluetooth serial).
function Invoke-WinsockReset {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\Winsock\Parameters'
    $before = @((Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).'Provider List')
    & netsh.exe winsock reset 2>&1 | ConvertTo-PlainText
    $rc = $LASTEXITCODE
    $after = @((Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).'Provider List')
    $gone = @($before | Where-Object { $_ -and $after -notcontains $_ })
    if ($rc -ne 0) { "WARNING: netsh winsock reset returned exit code $rc." }
    if ($gone.Count) { "NOTE: the rebuilt catalog no longer lists these providers: $($gone -join ', ')." + $(if ($gone -contains 'RFCOMM') { ' RFCOMM is Bluetooth serial - Bluetooth serial / COM-port apps may need the device re-paired.' } else { '' }) + ' The Registry Backups tab can put the old catalog keys back.' }
}

# netsh int ip reset, with an honest summary: recent Windows reports a few protected items as "failed. Access is denied."
function Invoke-IpReset {
    $log = Join-Path $script:LogDir 'netsh-ip-reset.log'
    $out = @(& netsh.exe int ip reset $log 2>&1 | ConvertTo-PlainText)
    $rc = $LASTEXITCODE
    $out
    $failed = @($out | Where-Object { $_ -match '(?i)failed' }).Count
    if ($failed -or $rc -ne 0) {
        "NOTE: netsh reported $failed item(s) as failed (exit code $rc). On Windows 10/11 a few 'failed. Access is denied.' items are normal - they are protected settings and do not stop the reset. Reboot, then check whether the problem is gone."
    }
    if (Test-Path -LiteralPath $log) { "netsh log: $log" } else { 'netsh did not write its own log on this Windows build - the output above is kept in the session log.' }
}

function Restore-RegBackup([string]$File) {
    $m = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    if ($m.Type -eq 'Key') {
        $rf = Join-Path $script:RegKeyDir $m.RegFile
        if (-not (Test-Path -LiteralPath $rf)) { return "Backup file missing: $rf" }
        # reg.exe prints even its SUCCESS message on stderr: show plain text (no NativeCommandError block) and judge by the exit code
        $o = @(& reg.exe import "$rf" 2>&1 | ConvertTo-PlainText)
        if ($LASTEXITCODE -ne 0) { return "FAILED to import the original export of $($m.Key) (reg.exe exit code $LASTEXITCODE): $($o -join ' ') - nothing was marked as restored." }
        "Imported the original export of $($m.Key). (Values added after the backup are not removed.) A reboot may be needed."
    } else {
        if ($m.Existed) {
            $val = $m.Data
            switch ($m.Kind) {
                'DWord'       { $val = [int]$val }
                'QWord'       { $val = [int64]$val }
                'Binary'      { $val = [Convert]::FromBase64String([string]$m.Data) }
                'MultiString' { $val = [string[]]@($m.Data | Where-Object { $null -ne $_ }) }   # older backups stored an empty list as null
                default       { $val = [string]$val }
            }
            # -ErrorAction Stop: a failed write must NOT be reported (and marked) as restored, or the original gets overwritten later
            try {
                if (-not (Test-Path -LiteralPath $m.Key)) { New-Item -Path $m.Key -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $m.Key -Name $m.Name -Value $val -PropertyType $m.Kind -Force -ErrorAction Stop | Out-Null
            } catch { return "FAILED to restore $($m.Key) [$($m.Name)]: $($_.Exception.Message) - nothing was marked as restored." }
            "Restored $($m.Key) [$($m.Name)] to its original value."
        } else {
            if (Test-Path -LiteralPath $m.Key) {
                if ((Get-Item -LiteralPath $m.Key).GetValueNames() -contains $m.Name) {
                    try { Remove-ItemProperty -LiteralPath $m.Key -Name $m.Name -ErrorAction Stop }
                    catch { return "FAILED to remove $($m.Key) [$($m.Name)]: $($_.Exception.Message) - nothing was marked as restored." }
                }
                "Removed $($m.Key) [$($m.Name)] (it did not exist originally)."
                if (-not $m.KeyExisted) {
                    $k = Get-Item -LiteralPath $m.Key
                    if ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item -LiteralPath $m.Key -Force; "Removed the now-empty key $($m.Key) (created by WinFixKit)." }
                }
            } else { "Key $($m.Key) no longer exists - nothing to remove." }
        }
    }
    $m.RestoredAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $m | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $File -Encoding UTF8
}

function Invoke-FullRegBackup {
    $dir = Join-Path $script:RegFullDir (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    "Full registry backup -> $dir  (this can take a minute)"
    $ok = $true
    foreach ($h in 'SYSTEM', 'SOFTWARE') {
        $f = Join-Path $dir "$h.hiv"
        $out = (& reg.exe save "HKLM\$h" "$f" /y 2>&1 | ConvertTo-PlainText) -join ' '
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $f)) { '  HKLM\{0} saved ({1:N0} MB)' -f $h, ((Get-Item -LiteralPath $f).Length / 1MB) }
        else { $ok = $false; "  HKLM\$h FAILED (reg.exe exit code $LASTEXITCODE): $out" }
    }
    # Checkpoint-Computer only WARNS (no error) when a restore point was made in the last 24 h - so count them instead
    $rp0 = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count; $rpw = $null
    try { Checkpoint-Computer -Description 'WinFixKit - before registry changes' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable rpw } catch { $rpw = $_.Exception.Message }
    if (@(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count -gt $rp0) { '  System restore point created.' } else { "  Restore point NOT created: $(@($rpw) -join ' ')" }
    $readme = @(
        "WinFixKit full registry backup - $(Get-Date)"
        ''
        'SYSTEM.hiv and SOFTWARE.hiv are complete copies (reg save) of HKLM\SYSTEM and HKLM\SOFTWARE, taken before the first registry change of the session.'
        'To roll EVERYTHING back: use the System Restore point if one was created, or boot to the Windows Recovery Environment command prompt,'
        'rename C:\Windows\System32\config\SYSTEM and SOFTWARE, then copy these files over them (named SYSTEM and SOFTWARE with no extension) and reboot.'
        'Drive letters differ inside WinRE - check with: dir C:\Windows\System32\config'
        'For a single value or key, use the Registry Backups tab in WinFixKit instead (one click per item).'
    )
    $readme | Set-Content -LiteralPath (Join-Path $dir 'README-RESTORE.txt') -Encoding UTF8
    $script:FullBackupDone = $ok          # a failed hive save is retried before the next registry fix
    if (-not $ok) { '  WARNING: the full registry backup is incomplete - it will be tried again before the next registry fix.' }
}

function Ensure-FullRegBackup {
    if ($script:FullBackupDone) { return 'Full registry backup already taken this session.' }
    Invoke-FullRegBackup
}


# =============================================================================================
#  SECTION DEFINITIONS  (Status = read-only snapshot, Actions = fixes)
# =============================================================================================
$Sections = @(

# ---------------------------------------------------------------------------------------------
@{ Name = 'Overview'
   Summary = 'System snapshot. Use "Run ALL status checks" at the bottom for a full baseline of every tab.'
   Help = @'
Overview
Shows the basics a tech wants first: OS and build, uptime, user, domain/workgroup, RAM, disk space and whether a reboot is pending.

Use the "Run ALL status checks" button at the bottom to take a baseline of every tab in one go (read-only). Everything is saved to the session log in the WinFixKit folder on the Desktop, so you can attach it to a ticket.
'@
   StatusLabel = 'Check status: system overview'
   StatusHelp = @'
Read-only. Collects: computer/user names, OS + build, last boot and uptime, domain or workgroup, manufacturer/model, RAM, fixed disk free space, pending-reboot flags and whether this tool is elevated. Nothing is changed.
'@
   Status = {
       Hdr 'System'
       Safe {
           $os = Get-CimInstance Win32_OperatingSystem
           $cs = Get-CimInstance Win32_ComputerSystem
           "Computer     : $env:COMPUTERNAME"
           "User         : $env:USERDOMAIN\$env:USERNAME"
           "OS           : $($os.Caption) build $($os.BuildNumber) ($($os.OSArchitecture))"
           "Last boot    : $($os.LastBootUpTime)"
           "Uptime       : $([int]((Get-Date) - $os.LastBootUpTime).TotalDays) days"
           "Domain/Group : $($cs.Domain) (PartOfDomain=$($cs.PartOfDomain))"
           "Model        : $($cs.Manufacturer) $($cs.Model)"
           "RAM          : $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB total, $([math]::Round($os.FreePhysicalMemory / 1MB, 1)) GB free"
           "PowerShell   : $($PSVersionTable.PSVersion)"
           "Elevated     : $(Test-Admin)"
       }
       Hdr 'Fixed disks'
       Safe { Table (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, @{ n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 1) } }, @{ n = 'FreeGB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } }) }
       Hdr 'Pending reboot'
       Safe { Get-PendingReboot }
   }
   Actions = @()
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Windows Update'
   Summary = 'Replaces wu10.diagcab: shows update service/cache state, then resets SoftwareDistribution, catroot2 and BITS.'
   Help = @'
Windows Update (replaces wu10.diagcab / wu170509.diagcab)
Most update failures are a stuck service, a corrupt download cache (SoftwareDistribution), a corrupt signature store (catroot2), or stale BITS jobs.

Start with "Check status" to see service states, cache sizes, pending-reboot flags, WSUS/GPO policy (which a reset cannot fix), BITS jobs, recent hotfixes and recent Windows Update events. Then run the reset if it looks like a cache problem.
'@
   StatusLabel = 'Check status: Windows Update'
   StatusHelp = @'
Read-only. Shows: update-related services (wuauserv, bits, cryptsvc, msiserver, usosvc, TrustedInstaller, DoSvc), size of SoftwareDistribution and catroot2, last detect/download/install success times, pending-reboot flags, WSUS/policy registry keys, active BITS jobs, the 10 newest hotfixes and the 10 newest Windows Update client events.
'@
   Status = {
       Hdr 'Services'
       Safe { Table (Svc 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc', 'TrustedInstaller', 'DoSvc') }
       Hdr 'Update cache folders'
       Safe {
           $sd = "$env:SystemRoot\SoftwareDistribution"; $cr = "$env:SystemRoot\System32\catroot2"
           "SoftwareDistribution : $(Get-FolderSizeMB $sd)"
           "catroot2             : $(Get-FolderSizeMB $cr)"
           $old = @(Get-ChildItem "$env:SystemRoot" -Directory -Filter 'SoftwareDistribution.bak_*' -ErrorAction SilentlyContinue) + @(Get-ChildItem "$env:SystemRoot\System32" -Directory -Filter 'catroot2.bak_*' -ErrorAction SilentlyContinue)
           "Old backups from earlier resets: $($old.Count)"
       }
       Hdr 'Last update activity (registry)'
       Safe {
           foreach ($t in 'Detect', 'Download', 'Install') {
               $p = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\$t" -ErrorAction SilentlyContinue
               "Last $t success: $($p.LastSuccessTime)"
           }
       }
       Hdr 'Pending reboot'
       Safe { Get-PendingReboot }
       Hdr 'WSUS / policy settings (a cache reset cannot fix these)'
       Safe {
           $found = $false
           foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') {
               if (Test-Path $k) { $found = $true; $k; (Get-ItemProperty $k | Select-Object -Property * -ExcludeProperty PS* | Format-List | Out-String).TrimEnd() }
           }
           if (-not $found) { 'No Windows Update policy keys (not WSUS/GPO managed)' }
       }
       Hdr 'BITS transfers'
       Safe { Table (Get-BitsTransfer -AllUsers | Select-Object DisplayName, JobState, OwnerAccount) }
       Hdr 'Newest installed hotfixes'
       Safe { Table (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 HotFixID, Description, InstalledOn) }
       Hdr 'Recent Windows Update client events'
       Safe { Table (Get-RecentEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient' } 10) }
   }
   Actions = @(
       @{ Label = 'Reset Windows Update components'
          Help = @'
Reset Windows Update components
Clears BITS jobs; stops usosvc, DoSvc (Delivery Optimization), wuauserv, bits, cryptsvc and msiserver; RENAMES C:\Windows\SoftwareDistribution and System32\catroot2 to *.bak_<timestamp> (Windows rebuilds both); renames the BITS queue database (qmgr.db + its edb logs on Windows 10/11, qmgr*.dat on older Windows); restarts the services.

Effects: update history in the Settings page is reset and pending downloads must be re-downloaded. The renamed folders stay on disk as your undo and can be removed with "Delete old update backups".
Needs admin. A reboot afterwards is a good idea.
'@
          Confirm = 'This will stop the update services, rename SoftwareDistribution and catroot2 (kept as .bak_ copies), clear BITS jobs and restart the services. Continue?'
          Run = {
              param($Arg)
              # clear BITS jobs FIRST: Get-BitsTransfer would start BITS again if it ran after the stop
              try { Get-BitsTransfer -AllUsers -ErrorAction Stop | Remove-BitsTransfer -ErrorAction Stop; 'Cleared BITS jobs' } catch { "BITS jobs: $($_.Exception.Message)" }
              # DoSvc keeps its cache in SoftwareDistribution\DeliveryOptimization and blocks the rename while it runs
              foreach ($s in 'usosvc', 'DoSvc', 'wuauserv', 'bits', 'cryptsvc', 'msiserver') { StopSvc $s }
              Rename-WithStamp "$env:SystemRoot\SoftwareDistribution"
              Rename-WithStamp "$env:SystemRoot\System32\catroot2"
              # BITS queue: qmgr.db + edb*.log/.jrs/.chk (ESE) on Windows 10/11, qmgr*.dat on older Windows
              Get-ChildItem "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader" -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(qmgr.*\.(dat|db|jfm)|edb.*\.(log|jrs|chk))$' } | ForEach-Object { Rename-WithStamp $_.FullName }
              foreach ($s in 'cryptsvc', 'bits', 'DoSvc', 'wuauserv', 'usosvc') { StartSvc $s }
              'Done. Reboot, then check for updates.'
          } },
       @{ Label = 'Scan for updates now'
          Help = @'
Scan for updates now
Runs UsoClient StartScan, which asks the Update Orchestrator to check for updates immediately. Harmless; use it after a reset to see whether updates now appear in Settings.
'@
          Run = { param($Arg); UsoClient StartScan; 'Scan requested. Open Settings > Windows Update to watch progress.' } },
       @{ Label = 'Repair system files (DISM + SFC) - opens a window'
          Help = @'
Repair system files (DISM + SFC)
Opens a separate window and runs: DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow. These repair the component store that Windows Update depends on.
Can take 10-30+ minutes and needs internet access for DISM. Output is saved to a transcript in the logs folder.
'@
          Window = $true; AutoStatus = $false
          Confirm = 'This opens a window and runs DISM RestoreHealth followed by SFC. It can take 10-30 minutes. Continue?'
          Run = { DISM /Online /Cleanup-Image /RestoreHealth; sfc /scannow } },
       @{ Label = 'Delete old update backups (.bak_ folders)'
          Help = @'
Delete old update backups
Permanently removes the SoftwareDistribution.bak_* and catroot2.bak_* folders left behind by earlier resets, to free disk space. Only run this once updates are confirmed working again.
'@
          Confirm = 'Permanently delete all SoftwareDistribution.bak_* and catroot2.bak_* folders? This cannot be undone.'
          Run = {
              param($Arg)
              $old = @(Get-ChildItem "$env:SystemRoot" -Directory -Filter 'SoftwareDistribution.bak_*' -ErrorAction SilentlyContinue) + @(Get-ChildItem "$env:SystemRoot\System32" -Directory -Filter 'catroot2.bak_*' -ErrorAction SilentlyContinue)
              if ($old.Count -eq 0) { 'No backups found.'; return }
              foreach ($d in $old) { try { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop; "Deleted $($d.FullName)" } catch { "Could not delete $($d.FullName): $($_.Exception.Message)" } }
          } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Files and Folders'
   Summary = 'Replaces winfilefolder.diagcab: checks Explorer, Recycle Bin, permissions and blockers, then fixes shell/permission problems.'
   Help = @'
Files and Folders (replaces winfilefolder.diagcab)
For "cannot rename/move/copy/delete" and Recycle Bin problems. Typical causes: a hung Explorer, a corrupt Recycle Bin, wrong ownership/permissions, Controlled Folder Access, a dirty disk or too many shell extensions.

Check status first; the fixes are deliberately narrow.
'@
   StatusLabel = 'Check status: files, folders and shell'
   StatusHelp = @'
Read-only. Shows: Explorer processes, Recycle Bin item count and size, disk free space and dirty bit (admin), Controlled Folder Access state, long-path setting, icon-overlay handlers (Windows only honours 15), approved shell extensions, temp folder size and the permissions on your profile folder.
'@
   Status = {
       Hdr 'Explorer processes'
       Safe { Table (Get-Process explorer -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime, @{ n = 'MemMB'; e = { [math]::Round($_.WS / 1MB, 1) } }) }
       Hdr 'Recycle Bin (current user)'
       Safe {
           $rb = (New-Object -ComObject Shell.Application).NameSpace(0xA)
           $items = @($rb.Items())
           $size = ($items | Measure-Object -Property Size -Sum).Sum
           "Items: $($items.Count)   Size: $([math]::Round(([double]$size) / 1MB, 1)) MB"
       }
       Hdr 'Disk free space'
       Safe { Table (Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{ n = 'UsedGB'; e = { [math]::Round($_.Used / 1GB, 1) } }, @{ n = 'FreeGB'; e = { [math]::Round($_.Free / 1GB, 1) } }) }
       Hdr 'Dirty bit on system drive (needs admin)'
       Safe { fsutil dirty query $env:SystemDrive }
       Hdr 'Controlled Folder Access (can block deletes/renames)'
       Safe { $m = Get-MpPreference; "EnableControlledFolderAccess = $($m.EnableControlledFolderAccess)   (0=off, 1=on, 2=audit)" }
       Hdr 'Long paths enabled'
       Safe { "LongPathsEnabled = $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem').LongPathsEnabled)" }
       Hdr 'Icon overlay handlers (Windows honours only the first 15)'
       Safe { $o = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers' | Select-Object -ExpandProperty PSChildName); "Count: $($o.Count)"; $o | ForEach-Object { '  ' + $_ } }
       Hdr 'Approved shell extensions'
       Safe {
           $p = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
           $names = $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $_.Value }
           "Count: $(@($names).Count)"
           $names | Sort-Object -Unique | ForEach-Object { '  ' + $_ }
       }
       Hdr 'Temp folder size'
       Safe { "$env:TEMP : $(Get-FolderSizeMB $env:TEMP)" }
       Hdr 'Permissions on your profile folder'
       Safe { icacls $env:USERPROFILE | Select-Object -First 10 }
   }
   Actions = @(
       @{ Label = 'Restart Windows Explorer'
          Help = @'
Restart Windows Explorer
Stops explorer.exe and starts it again. Fixes a frozen taskbar/desktop and stale file-operation state. Open File Explorer windows close; no files are touched.
'@
          Admin = $false
          Run = {
              param($Arg)
              Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
              # Windows restarts the shell itself; wait for that. Never start Explorer from an ELEVATED tool (admin desktop).
              for ($i = 0; $i -lt 10 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
              if (Get-Process explorer -ErrorAction SilentlyContinue) { 'Explorer restarted.' }
              elseif (Test-Admin) { 'Explorer did not come back by itself. Press Ctrl+Shift+Esc > Run new task > type explorer (leave "administrative privileges" UNticked).' }
              else { Start-Process explorer.exe; 'Explorer started.' }
          } },
       @{ Label = 'Empty Recycle Bin (all drives)'
          Help = @'
Empty Recycle Bin
Runs Clear-RecycleBin -Force for all drives. PERMANENTLY removes everything in the Recycle Bin. Use when the Bin will not empty from the desktop icon.
'@
          Admin = $false
          Confirm = 'Permanently delete everything in the Recycle Bin on all drives?'
          Run = { param($Arg); Clear-RecycleBin -Force -ErrorAction Stop; 'Recycle Bin emptied.' } },
       @{ Label = 'Show permissions of a folder...'
          Help = @'
Show permissions of a folder
Pick a folder and see its owner and full permission list (icacls). Read-only. Use it to find out WHY a rename/delete is refused before changing anything.
'@
          Admin = $false; AutoStatus = $false; Prompt = 'Folder'; PromptText = 'Choose the folder to inspect'
          Run = { param($Arg); if (-not $Arg) { 'No folder chosen.'; return }; "Owner: $((Get-Acl -LiteralPath $Arg).Owner)"; icacls "$Arg" } },
       @{ Label = 'Take ownership + reset permissions of a folder...'
          Help = @'
Take ownership + reset permissions
Pick a folder. The tool (1) saves its current permissions to an acl-backup file in the Reports folder (restore later with: icacls <parent> /restore <file>), (2) takes ownership recursively (takeown), (3) resets permissions back to inherited defaults (icacls /reset).
Refuses drive roots, C:\Windows, Program Files, ProgramData, C:\Users itself, the Default and Public profiles, whole user profiles, AppData and hidden system folders (Recovery, System Volume Information, ...). Junctions and short 8.3 names are resolved first, so they cannot bypass this list. Note: the backup restores permissions but NOT the previous owner. Use only on user data folders. Needs admin.
'@
          Prompt = 'Folder'; PromptText = 'Choose the folder to take ownership of and reset'
          Confirm = 'This takes ownership of the chosen folder and everything inside it and resets its permissions to inherited defaults. A backup of the old permissions is saved to the Reports folder. Continue?'
          Run = {
              param($Arg)
              if (-not $Arg) { 'No folder chosen.'; return }
              $p = (Resolve-Path -LiteralPath $Arg).ProviderPath.TrimEnd('\')
              $why = Test-ProtectedFolder $p
              if ($why) { "REFUSED: $why."; return }
              $p = Resolve-RealPath $p
              $bk = Join-Path $script:ReportDir ("acl-backup-{0}-{1}.txt" -f ((Split-Path $p -Leaf) -replace '[^A-Za-z0-9]', '_'), (Get-Date -Format 'yyyyMMdd-HHmmss'))
              "Owner before: $((Get-Acl -LiteralPath $p).Owner)"
              "Saving current permissions to $bk"
              icacls "$p" /save "$bk" /t /c | Select-Object -Last 3
              if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bk)) { "ABORTED: saving the current permissions failed (icacls exit code $LASTEXITCODE) - nothing was changed."; return }
              'Taking ownership...'
              takeown /f "$p" /r /d y | Select-Object -Last 5
              if ($LASTEXITCODE -ne 0) {
                  # the /d answer letter is translated (J, O, ...) on non-English Windows - fall back to the language-neutral SID
                  "takeown returned exit code $LASTEXITCODE - using icacls /setowner Administrators (*S-1-5-32-544) instead."
                  icacls "$p" /setowner '*S-1-5-32-544' /t /c | Select-Object -Last 3
              }
              'Resetting permissions...'
              icacls "$p" /reset /t /c | Select-Object -Last 5
              if ($LASTEXITCODE -ne 0) { "WARNING: icacls /reset returned exit code $LASTEXITCODE - some items were not reset (see above)." }
              "Owner after: $((Get-Acl -LiteralPath $p).Owner)"
          } },
       @{ Label = 'Scan system drive for errors (read-only) - opens a window'
          Help = @'
Scan system drive for errors
Opens a window and runs chkdsk on the system drive WITHOUT /f, so it only reports problems and does not change anything. If it reports errors, schedule a repair yourself with chkdsk C: /f.
'@
          Window = $true; AutoStatus = $false
          Run = { chkdsk $env:SystemDrive } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Start Menu'
   Summary = 'Replaces startmenu.diagcab: checks shell packages/processes, then re-registers Start and Shell Experience Host.'
   Help = @'
Start Menu (replaces startmenu.diagcab)
Fixes a Start menu or search box that will not open, is blank or crashes. Causes: a broken ShellExperienceHost / StartMenuExperienceHost package registration, stopped state-repository services, or (Windows 10) a corrupt tile database.
'@
   StatusLabel = 'Check status: Start menu and shell'
   StatusHelp = @'
Read-only. Shows OS build, whether the Start/Shell/Search AppX packages are registered and healthy, the shell processes and their memory, supporting services (StateRepository, tiledatamodelsvc, AppReadiness, CDP), the Windows 10 tile database folder, and recent Application Error events for the shell.
'@
   Status = {
       Hdr 'Windows build'
       Safe { $o = Get-CimInstance Win32_OperatingSystem; "$($o.Caption) build $($o.BuildNumber)   (build 22000+ is Windows 11)" }
       Hdr 'Shell AppX packages'
       Safe {
           $r = foreach ($n in 'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.Search', 'MicrosoftWindows.Client.CBS') {
               $p = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)
               if ($p.Count -eq 0) { [pscustomobject]@{ Package = $n; Version = '-'; Status = 'NOT INSTALLED (may be normal on this OS)' } }
               else { foreach ($x in $p) { [pscustomobject]@{ Package = $x.Name; Version = $x.Version; Status = $x.Status } } }
           }
           Table $r
       }
       Hdr 'Shell processes'
       Safe { Table (Get-Process StartMenuExperienceHost, ShellExperienceHost, SearchHost, SearchApp, explorer -ErrorAction SilentlyContinue | Select-Object Name, Id, @{ n = 'MemMB'; e = { [math]::Round($_.WS / 1MB, 1) } }, Responding) }
       Hdr 'Supporting services'
       Safe { Table (Svc 'StateRepository', 'tiledatamodelsvc', 'AppReadiness', 'CDPSvc', 'CDPUserSvc*', 'WSearch') }
       Hdr 'Tile database (Windows 10)'
       Safe { $t = "$env:LOCALAPPDATA\TileDataLayer"; if (Test-Path $t) { "$t : $(Get-FolderSizeMB $t)" } else { 'No TileDataLayer folder (normal on Windows 11)' } }
       Hdr 'Recent shell crashes (Application Error)'
       Safe {
           $e = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error' } -MaxEvents 80 -ErrorAction Stop |
                Where-Object { $_.Message -match 'StartMenuExperienceHost|ShellExperienceHost|explorer\.exe|SearchHost|SearchApp' } | Select-Object -First 10 TimeCreated, @{ n = 'Message'; e = { ($_.Message -split "`r?`n")[0] } }
           Table $e
       }
   }
   Actions = @(
       @{ Label = 'Restart Start / Search / Shell processes'
          Help = @'
Restart Start / Search / Shell processes
Stops StartMenuExperienceHost, ShellExperienceHost, SearchHost and SearchApp; Windows restarts them on demand. Quick first fix for a frozen Start menu. Nothing is deleted.
'@
          Admin = $false
          Run = { param($Arg); foreach ($n in 'StartMenuExperienceHost', 'ShellExperienceHost', 'SearchHost', 'SearchApp') { Stop-Process -Name $n -Force -ErrorAction SilentlyContinue; "Stopped $n (if it was running)" } } },
       @{ Label = 'Re-register Start and Shell packages'
          Help = @'
Re-register Start and Shell packages
For StartMenuExperienceHost, ShellExperienceHost, Windows.Search and Client.CBS runs Add-AppxPackage -DisableDevelopmentMode -Register on each package's AppXManifest.xml. This repairs a broken registration without reinstalling. Safe; some errors on packages that are not present are normal. Needs admin.
'@
          Confirm = 'Re-register the Start menu and shell packages for all users?'
          Run = {
              param($Arg)
              foreach ($n in 'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.Search', 'MicrosoftWindows.Client.CBS') {
                  $pk = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)
                  if ($pk.Count -eq 0) { "Skipped (not installed): $n"; continue }
                  foreach ($x in $pk) {
                      try { Add-AppxPackage -DisableDevelopmentMode -Register "$($x.InstallLocation)\AppXManifest.xml" -ErrorAction Stop; "Re-registered $($x.Name)" }
                      catch { "Failed $($x.Name): $($_.Exception.Message)" }
                  }
              }
          } },
       @{ Label = 'Rebuild tile database (Windows 10 only)'
          Help = @'
Rebuild tile database
Windows 10 only. Stops tiledatamodelsvc, renames %LOCALAPPDATA%\TileDataLayer to *.bak_<timestamp> and restarts the service so Windows recreates it. Start tile layout may reset to defaults. Skipped automatically on Windows 11. Run as the affected user.
'@
          Admin = $false
          Confirm = 'Rename the tile database so Windows rebuilds it? Your Start tile layout may reset.'
          Run = {
              param($Arg)
              if ([int](Get-CimInstance Win32_OperatingSystem).BuildNumber -ge 22000) { 'Windows 11 detected - not applicable, skipped.'; return }
              Get-WrongUserWarning
              $r = StopSvc 'tiledatamodelsvc'; $r
              if ($r -notlike 'Stopped*' -and $r -notlike '*not present*') { 'Tile database NOT reset: the service could not be stopped (that needs admin). Use "Relaunch as Administrator" while signed in as this same user.'; return }
              $o = Rename-WithStamp "$env:LOCALAPPDATA\TileDataLayer"; $o
              StartSvc 'tiledatamodelsvc'
              if ($o -like 'Could not*') { 'Tile database NOT reset (see above).' } else { 'Sign out and back in to finish.' }
          } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Microsoft Account'
   Summary = 'Replaces microsoftaccounts.diagcab: checks identity services, join state, stored credentials, clock and connectivity.'
   Help = @'
Microsoft Account (replaces microsoftaccounts.diagcab)
Sync failures and repeated sign-in prompts usually come from: stopped identity services (wlidsvc, TokenBroker), a wrong system clock, a stale token cache, credential conflicts, or blocked access to login.live.com.
'@
   StatusLabel = 'Check status: Microsoft account / sign-in'
   StatusHelp = @'
Read-only. Shows identity-related services, your UPN, dsregcmd join/PRT state (Azure AD / domain / workplace), stored credential TARGET names from Credential Manager (no passwords), W32Time clock status and TCP reachability of login.live.com, account.microsoft.com and login.microsoftonline.com.
'@
   Status = {
       Hdr 'Identity services'
       Safe { Table (Svc 'wlidsvc', 'TokenBroker', 'VaultSvc', 'OneSyncSvc*', 'CDPSvc', 'W32Time') }
       Hdr 'Signed-in identity'
       Safe {
           $upn = (& whoami.exe /upn 2>$null | Out-String).Trim()
           if ($LASTEXITCODE -eq 0 -and $upn) { "UPN: $upn" }
           else { "No UPN: this is a local account (not signed in with a Microsoft / work or school account). User: $env:USERDOMAIN\$env:USERNAME" }
       }
       Hdr 'Join / token state (dsregcmd)'
       Safe { dsregcmd /status | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined|NgcSet|AzureAdPrt|WamDefaultSet|TenantName|DeviceId' | ForEach-Object { $_.Line.Trim() } }
       Hdr 'Stored credentials (targets only)'
       Safe { cmdkey /list | Where-Object { $_ -match '=' } | ForEach-Object { $_.Trim() } }   # target lines contain "...:target=..." in every language
       Hdr 'Clock'
       Safe { w32tm /query /status }
       Hdr 'Reachability (TCP 443)'
       Safe { Table $(foreach ($h in 'login.live.com', 'account.microsoft.com', 'login.microsoftonline.com') { [pscustomobject]@{ Host = $h; Reachable = (Test-TcpPort $h 443) } }) }
   }
   Actions = @(
       @{ Label = 'Restart identity services'
          Help = @'
Restart identity services
Restarts Microsoft Account Sign-in Assistant (wlidsvc) and Web Account Manager (TokenBroker). Clears a hung sign-in state without removing any account. Needs admin.
'@
          Run = { param($Arg); foreach ($s in 'wlidsvc', 'TokenBroker') { StopSvc $s }; foreach ($s in 'TokenBroker', 'wlidsvc') { StartSvc $s } } },
       @{ Label = 'Resync system clock'
          Help = @'
Resync system clock
Starts the Windows Time service if needed and runs w32tm /resync /force. A clock that is off by more than a few minutes makes sign-in and sync fail. Needs admin.
'@
          Run = { param($Arg); StartSvc 'W32Time'; w32tm /resync /force } },
       @{ Label = 'Reset sign-in token cache (current user)'
          Help = @'
Reset sign-in token cache
Renames the current user's TokenBroker folders (%LOCALAPPDATA%\Microsoft\TokenBroker and the AAD BrokerPlugin copy) to *.bak_<timestamp>. Windows recreates them. The user will have to sign in again to Office, Store, OneDrive, etc. Fixes stuck "something went wrong" account loops.
'@
          Admin = $false
          Confirm = 'Reset the sign-in token cache for the current user? They will need to sign in again to Microsoft apps.'
          Run = {
              param($Arg)
              Get-WrongUserWarning
              $r = StopSvc 'TokenBroker'; $r
              if ($r -notlike 'Stopped*') { 'Token cache NOT reset: TokenBroker could not be stopped (that needs admin). Close Office / Store / OneDrive and use "Relaunch as Administrator" while signed in as this same user.'; return }
              $o = @(Rename-WithStamp "$env:LOCALAPPDATA\Microsoft\TokenBroker"; Rename-WithStamp "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker"); $o
              StartSvc 'TokenBroker'
              if (@($o | Where-Object { $_ -like 'Could not*' }).Count) { 'Token cache only PARTLY reset (see above) - close the apps that use it and try again.' } else { 'Sign out and back in to finish.' }
          } },
       @{ Label = 'Re-register Account Broker plugin'
          Help = @'
Re-register Account Broker plugin
Runs Add-AppxPackage -Register for Microsoft.AAD.BrokerPlugin and Microsoft.Windows.CloudExperienceHost, the packages behind the sign-in pop-ups. Needs admin.
'@
          Run = {
              param($Arg)
              foreach ($n in 'Microsoft.AAD.BrokerPlugin', 'Microsoft.Windows.CloudExperienceHost') {
                  $pk = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)
                  if ($pk.Count -eq 0) { "Skipped (not installed): $n"; continue }
                  foreach ($x in $pk) { try { Add-AppxPackage -DisableDevelopmentMode -Register "$($x.InstallLocation)\AppXManifest.xml" -ErrorAction Stop; "Re-registered $($x.Name)" } catch { "Failed $($x.Name): $($_.Exception.Message)" } }
              }
          } },
       @{ Label = 'Open Credential Manager'
          Help = @'
Open Credential Manager
Opens the Windows Credential Manager so you can remove stale MicrosoftAccount:* or Office entries by hand. Opens a window only; changes nothing.
'@
          Admin = $false; AutoStatus = $false
          Run = { param($Arg); Start-Process control.exe -ArgumentList '/name Microsoft.CredentialManager'; 'Opened Credential Manager.' } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Store Apps'
   Summary = 'Replaces Appsdiagnostic10.diagcab: checks Store/AppX services and broken packages, then resets the Store cache or re-registers apps.'
   Help = @'
Store Apps (replaces Appsdiagnostic10.diagcab)
For a Store that will not open or download, or built-in apps that crash/vanish. Typical causes: a corrupt Store cache, stopped licensing/AppX services or an app whose registration is broken.
'@
   StatusLabel = 'Check status: Store and AppX'
   StatusHelp = @'
Read-only. Shows Store-related services (ClipSVC, AppXSvc, InstallService, LicenseManager, wlidsvc), the Store package version, how many AppX packages are installed, any packages whose Status is not "Ok", Store reachability and the 10 newest AppX deployment errors.
'@
   Status = {
       Hdr 'Services'
       Safe { Table (Svc 'ClipSVC', 'AppXSvc', 'InstallService', 'LicenseManager', 'wlidsvc') }
       # one (slow) query, reused below; -AllUsers needs admin, so fall back to the current user's packages
       $appxScope = 'all users'
       $appxAll = try { @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch { $appxScope = 'current user only (not elevated)'; @(Get-AppxPackage -ErrorAction SilentlyContinue) }
       Hdr 'Microsoft Store package'
       Safe { Table ($appxAll | Where-Object { $_.Name -eq 'Microsoft.WindowsStore' } | Select-Object Name, Version, Status, InstallLocation) }
       Hdr 'AppX package count'
       Safe { "Installed ($appxScope): $($appxAll.Count)" }
       Hdr 'Packages not in "Ok" status'
       Safe { Table ($appxAll | Where-Object { $_.Status -ne 'Ok' } | Select-Object Name, Version, Status) }
       Hdr 'Store reachability (TCP 443)'
       Safe { Table $(foreach ($h in 'www.microsoft.com', 'storeedgefd.dsx.mp.microsoft.com') { [pscustomobject]@{ Host = $h; Reachable = (Test-TcpPort $h 443) } }) }
       Hdr 'Recent AppX deployment errors'
       Safe { Table (Get-RecentEvents @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; Level = 2 } 10) }
   }
   Actions = @(
       @{ Label = 'Reset Microsoft Store cache (wsreset)'
          Help = @'
Reset Microsoft Store cache
Runs wsreset.exe, which clears the Store cache without touching installed apps or account settings. A blank window appears for a while, then the Store opens. Safe first step for a Store that will not load.
'@
          Admin = $false
          Run = { param($Arg); Start-Process wsreset.exe; 'wsreset launched - wait for the Store to open on its own.' } },
       @{ Label = 'Restart Store licensing and AppX services'
          Help = @'
Restart Store licensing and AppX services
Restarts ClipSVC (Client License Service), AppXSvc and InstallService. Fixes "licence not found" and stuck downloads. Needs admin.
'@
          Run = { param($Arg); foreach ($s in 'ClipSVC', 'AppXSvc', 'InstallService') { StopSvc $s }; foreach ($s in 'ClipSVC', 'AppXSvc', 'InstallService') { StartSvc $s } } },
       @{ Label = 'Re-register Microsoft Store'
          Help = @'
Re-register Microsoft Store
Runs Add-AppxPackage -Register on the Store (and Store Purchase / Desktop App Installer) manifests. Repairs a Store that is missing or will not start. Needs admin.
'@
          Run = {
              param($Arg)
              foreach ($n in 'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller') {
                  $pk = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)
                  if ($pk.Count -eq 0) { "Skipped (not installed): $n"; continue }
                  foreach ($x in $pk) { try { Add-AppxPackage -DisableDevelopmentMode -Register "$($x.InstallLocation)\AppXManifest.xml" -ErrorAction Stop; "Re-registered $($x.Name)" } catch { "Failed $($x.Name): $($_.Exception.Message)" } }
              }
          } },
       @{ Label = 'Re-register ALL apps - opens a window'
          Help = @'
Re-register ALL apps
Opens a window and re-registers every installed AppX package for all users (the classic "fix everything" command). Takes several minutes. Packages that cannot be re-registered (often system or in-use packages) are listed as "FAILED" with the reason, and a total is shown at the end; some failures are normal. Does not uninstall anything, but a Start layout refresh can follow. Needs admin.
'@
          Window = $true; AutoStatus = $false
          Confirm = 'Re-register every installed app? This is slow and noisy, but does not uninstall anything.'
          Run = {
              $ok = 0; $bad = 0
              foreach ($pkg in @(Get-AppxPackage -AllUsers)) {      # ($_ inside catch is the error, so keep the package in $pkg)
                  try { Add-AppxPackage -DisableDevelopmentMode -Register "$($pkg.InstallLocation)\AppXManifest.xml" -ErrorAction Stop; $ok++; "Processed $($pkg.Name)" }
                  catch { $bad++; "FAILED $($pkg.Name): $(($_.Exception.Message -split "`r?`n")[0])" }
              }
              "Done: $ok re-registered, $bad failed (some failures are normal for system or in-use packages)."
          } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Printer'
   Summary = 'Replaces Printerdiagnostic10.diagcab: shows printers, ports, drivers, queue and spooler state, then fixes the spooler/queue.'
   Help = @'
Printer (replaces Printerdiagnostic10.diagcab)
Covers: stopped or hung Print Spooler, stuck jobs, wrong/unreachable ports and driver problems. The status check tests whether each network printer's IP actually answers on its print port, which is the fastest way to tell "printer off network" from "PC problem".
'@
   StatusLabel = 'Check status: printers, ports, queue'
   StatusHelp = @'
Read-only. Shows spooler services, all printers (driver, port, status), the default printer, queued jobs, number of files in the spool folder, every TCP/IP printer port with a live reachability test (default 9100), installed drivers and recent PrintService errors.
'@
   Status = {
       Hdr 'Services'
       Safe { Table (Svc 'Spooler', 'PrintNotify', 'PrintWorkflowUserSvc*') }
       Hdr 'Printers'
       Safe { Table (Get-Printer | Select-Object Name, DriverName, PortName, PrinterStatus, Shared, Type) }
       Hdr 'Default printer'
       Safe { $d = Get-CimInstance Win32_Printer | Where-Object { $_.Default }; if ($d) { $d.Name } else { '(none set)' } }
       Hdr 'Queued jobs'
       Safe { $j = foreach ($p in Get-Printer) { Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue | Select-Object PrinterName, Id, DocumentName, UserName, JobStatus, Size }; Table $j }
       Hdr 'Spool folder'
       Safe { $f = @(Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" -Force -ErrorAction SilentlyContinue); "Files in spool folder: $($f.Count)"; if ($f.Count) { Table ($f | Select-Object Name, Length, LastWriteTime) } }
       Hdr 'TCP/IP printer ports (live reachability test)'
       Safe {
           $r = foreach ($p in (Get-PrinterPort | Where-Object { $_.PrinterHostAddress })) {
               $n = if ($p.PortNumber) { $p.PortNumber } else { 9100 }
               [pscustomobject]@{ Port = $p.Name; Host = $p.PrinterHostAddress; TcpPort = $n; Reachable = (Test-TcpPort $p.PrinterHostAddress $n) }
           }
           Table $r
       }
       Hdr 'Installed printer drivers'
       Safe { Table (Get-PrinterDriver | Select-Object Name, Manufacturer, PrinterEnvironment) }
       Hdr 'Recent print service errors'
       Safe { Table (Get-RecentEvents @{ LogName = 'Microsoft-Windows-PrintService/Admin' } 10) }
   }
   Actions = @(
       @{ Label = 'Restart Print Spooler'
          Help = @'
Restart Print Spooler
Stops and starts the Spooler service. Fixes "printer offline" and a hung spooler without losing the queue. Needs admin.
'@
          Run = { param($Arg); StopSvc 'Spooler'; StartSvc 'Spooler' } },
       @{ Label = 'Clear stuck print queue'
          Help = @'
Clear stuck print queue
Stops the Spooler, deletes the temporary .SPL/.SHD job files in C:\Windows\System32\spool\PRINTERS (the file names are listed in the output), then starts the Spooler. ALL queued print jobs for all printers are lost; printers and drivers are not touched. Needs admin.
'@
          Confirm = 'This deletes ALL pending print jobs on this PC. Continue?'
          Run = {
              param($Arg)
              StopSvc 'Spooler'
              $sp = "$env:SystemRoot\System32\spool\PRINTERS"
              $f = @(Get-ChildItem $sp -Force -File -ErrorAction SilentlyContinue)
              "Removing $($f.Count) spool file(s)"
              foreach ($x in $f) { try { Remove-Item -LiteralPath $x.FullName -Force -ErrorAction Stop; "  deleted $($x.Name)" } catch { "  failed $($x.Name): $($_.Exception.Message)" } }
              StartSvc 'Spooler'
          } },
       @{ Label = 'Open printers list'
          Help = @'
Open printers list
Opens Settings > Printers and scanners so you can remove/re-add a printer or print a test page. Opens a window only.
'@
          Admin = $false; AutoStatus = $false
          Run = { param($Arg); Start-Process 'ms-settings:printers'; 'Opened printer settings.' } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Printer Share Fixes'
   Summary = 'Shared printer will not connect or install drivers (often 0x0000011b): RPC privacy setting, Point and Print restriction, KB5025221.'
   Help = @'
Printer Share Fixes
Three fixes for shared/network printers that stopped working after Windows updates and security hardening:
  1. RpcAuthnLevelPrivacyEnabled = 0   (HKLM\SYSTEM\CurrentControlSet\Control\Print)
  2. Remove update KB5025221
  3. RestrictDriverInstallationToAdministrators = 0   (HKLM\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint)

Fix 3 is needed even when a GPO says "Point and Print Restrictions = Disabled": the registry value is what lets NON-administrator users install the latest print drivers from the print server.

SECURITY: fixes 1 and 3 relax Microsoft's printing hardening (PrintNightmare era). Use them on trusted networks, only where needed. Every registry value is backed up first; undo from the Registry Backups tab.
'@
   StatusLabel = 'Check status: printer-share settings'
   StatusHelp = @'
Read-only. Shows the Windows build, the current value of RpcAuthnLevelPrivacyEnabled, every Point and Print value (policy and non-policy locations), whether KB5025221 is listed as installed (Get-HotFix may not list every update type), the Spooler service, printers shared by this PC and network printers connected for this user, and recent print-service errors.
'@
   Status = {
       Hdr 'Windows build'
       Safe { $o = Get-CimInstance Win32_OperatingSystem; $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; "$($o.Caption) $($v.DisplayVersion) build $($o.BuildNumber).$($v.UBR)" }
       Hdr 'RPC privacy setting'
       Safe { "HKLM\SYSTEM\CurrentControlSet\Control\Print  RpcAuthnLevelPrivacyEnabled = $(Get-RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled')   (0 = relaxed, 1 or not set = hardened default)" }
       Hdr 'Point and Print (policy location)'
       Safe {
           $k = 'HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
           if (Test-Path $k) { (Get-ItemProperty $k | Select-Object -Property * -ExcludeProperty PS* | Format-List | Out-String).TrimEnd() } else { 'Key not present (no policy / registry override set)' }
           "RestrictDriverInstallationToAdministrators = $(Get-RegVal $k 'RestrictDriverInstallationToAdministrators')   (0 = standard users may install drivers from the server)"
       }
       Hdr 'Point and Print (non-policy location)'
       Safe { $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Printers\PointAndPrint'; if (Test-Path $k) { (Get-ItemProperty $k | Select-Object -Property * -ExcludeProperty PS* | Format-List | Out-String).TrimEnd() } else { 'Key not present' } }
       Hdr 'KB5025221'
       Safe { $h = Get-HotFix -Id 'KB5025221' -ErrorAction SilentlyContinue; if ($h) { "Listed as INSTALLED (installed on $($h.InstalledOn))" } else { 'Not listed by Get-HotFix (not installed, or not an update type Get-HotFix reports)' } }
       Hdr 'Spooler'
       Safe { Table (Svc 'Spooler') }
       Hdr 'Printers shared BY this PC'
       Safe { Table (Get-Printer | Where-Object Shared | Select-Object Name, ShareName, DriverName, PortName) }
       Hdr 'Network printers connected for this user'
       Safe { Table (Get-Printer | Where-Object { $_.Name -like '\\*' } | Select-Object Name, DriverName, PrinterStatus) }
       Hdr 'Recent print service errors'
       Safe { Table (Get-RecentEvents @{ LogName = 'Microsoft-Windows-PrintService/Admin' } 10) }
   }
   Actions = @(
       @{ Label = 'Fix 1: set RpcAuthnLevelPrivacyEnabled = 0'; Registry = $true
          Help = @'
Fix 1: RpcAuthnLevelPrivacyEnabled = 0
Creates/sets the DWORD RpcAuthnLevelPrivacyEnabled = 0 under HKLM\SYSTEM\CurrentControlSet\Control\Print, then restarts the Print Spooler. This turns off the stricter RPC privacy requirement for print connections, which is what breaks connecting to some shared printers (commonly error 0x0000011b).
Usually applied on the PC that HOSTS the shared printer (the print server); some guides apply it on the client PCs too. Reduces security slightly - only use where needed. Needs admin.
'@
          Confirm = 'Set RpcAuthnLevelPrivacyEnabled = 0 and restart the Print Spooler? (The original value is backed up first.)'
          Run = {
              param($Arg)
              Set-RegValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled' 0 'DWord' 'printer share fix'
              StopSvc 'Spooler'; StartSvc 'Spooler'
          } },
       @{ Label = 'Fix 2: remove update KB5025221 - opens a window'
          Help = @'
Fix 2: remove update KB5025221
Opens a window and runs: wusa.exe /uninstall /kb:5025221 /quiet /norestart, then shows wusa's exit code. Reboot afterwards if it says so.
Uninstalling a cumulative update also removes the security fixes in it. Some updates cannot be removed with wusa; if it fails, use Settings > Windows Update > Update history > Uninstall updates. Consider pausing updates afterwards so it does not return. Needs admin.
'@
          Window = $true
          Confirm = 'Uninstall update KB5025221? This also removes the security fixes it contains and may need a reboot.'
          Run = {
              $h = Get-HotFix -Id 'KB5025221' -ErrorAction SilentlyContinue
              if (-not $h) { 'Get-HotFix does not list KB5025221 as installed - trying the uninstall anyway (some update types are not listed).' }
              $p = Start-Process wusa.exe -ArgumentList '/uninstall', '/kb:5025221', '/quiet', '/norestart' -Wait -PassThru
              "wusa exit code: $($p.ExitCode)"
              switch ($p.ExitCode) {
                  0       { 'Uninstalled.' }
                  3010    { 'Uninstalled - a reboot is required.' }
                  87      { if (-not $h) { 'wusa rejected the request (invalid parameter). KB5025221 is most likely not installed on this PC - nothing to remove.' } else { 'wusa rejected the request (invalid parameter). On Windows 11, combined cumulative updates often cannot be removed with wusa: use Settings > Windows Update > Update history > Uninstall updates.' } }
                  2359303 { 'Windows reports the update is not installed (0x240007 WU_S_ALREADY_UNINSTALLED) - nothing to remove.' }
                  2359302 { 'wusa reports 0x240006 (WU_S_ALREADY_INSTALLED) - unexpected for an uninstall; the update was not removed.' }
                  default { 'Not removed. Try Settings > Windows Update > Update history > Uninstall updates.' }
              }
          } },
       @{ Label = 'Fix 3: let standard users install print server drivers'; Registry = $true
          Help = @'
Fix 3: RestrictDriverInstallationToAdministrators = 0
Creates the key HKLM\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint if needed and sets RestrictDriverInstallationToAdministrators = 0, then restarts the Print Spooler. Needed so NON-admin users can install the latest print drivers from the print server, EVEN IF a GPO has "Point and Print Restrictions = Disabled".
If a domain GPO manages this setting, a policy refresh may set it back. Microsoft sets it to 1 as a PrintNightmare mitigation, so only relax it on networks you trust. Needs admin.
'@
          Confirm = 'Allow standard (non-admin) users to install print drivers from the print server? (The original value is backed up first.)'
          Run = {
              param($Arg)
              Set-RegValueSafe 'HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint' 'RestrictDriverInstallationToAdministrators' 0 'DWord' 'printer share fix'
              StopSvc 'Spooler'; StartSvc 'Spooler'
          } },
       @{ Label = 'Apply fixes 1 + 3 together'; Registry = $true
          Help = @'
Apply fixes 1 + 3 together
Sets both registry values (RpcAuthnLevelPrivacyEnabled = 0 and RestrictDriverInstallationToAdministrators = 0), then restarts the Print Spooler once. Does not remove KB5025221 (that is Fix 2). Needs admin.
'@
          Confirm = 'Apply both printer registry fixes and restart the Print Spooler? (Original values are backed up first.)'
          Run = {
              param($Arg)
              Set-RegValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled' 0 'DWord' 'printer share fix'
              Set-RegValueSafe 'HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint' 'RestrictDriverInstallationToAdministrators' 0 'DWord' 'printer share fix'
              StopSvc 'Spooler'; StartSvc 'Spooler'
          } },
       @{ Label = 'Restart Print Spooler'
          Help = @'
Restart Print Spooler
Stops and starts the Spooler service so registry changes take effect. Needs admin.
'@
          Run = { param($Arg); StopSvc 'Spooler'; StartSvc 'Spooler' } }
   )
},

@{ Name = 'Network'
   Summary = 'Replaces NetworkDiagnostics.diagcab: full network snapshot (IP, DNS, ARP, routes, proxy, tests) then targeted resets.'
   Help = @'
Network and Internet (replaces NetworkDiagnostics.diagcab)
The status check records everything you would want BEFORE touching anything: ipconfig /all, adapters, DNS servers, DNS cache, ARP table, routing table, proxy, Winsock catalog, hosts file, connectivity tests, listeners and firewall state.
Every fix button re-runs this snapshot before and after, so the log shows exactly what changed.

Output is parsed from Windows commands, so it is clearest on English-language Windows.
'@
   StatusLabel = 'Check status: full network snapshot'
   StatusHelp = @'
Read-only. Runs: ipconfig /all, Get-NetAdapter, DNS servers per adapter, DNS client cache (count + first 25), arp -a, route print, user + system proxy settings, Winsock catalog count, TCP global settings, active hosts-file entries, Wi-Fi interface details, firewall profile state, listening/established connection counts and live tests (ping gateway, ping 1.1.1.1, DNS lookup, HTTPS to microsoft.com). Can take 20-30 seconds if the network is down.
'@
   Status = {
       Hdr 'ipconfig /all'
       Safe { ipconfig /all }
       Hdr 'Network adapters'
       Safe { Table (Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress) }
       Hdr 'Connection profiles (Public / Private / Domain)'
       Safe { Table (Get-NetConnectionProfile | Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity) }
       Hdr 'DNS servers per interface (IPv4)'
       Safe { Table (Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, @{ n = 'Servers'; e = { $_.ServerAddresses -join ', ' } }) }
       Hdr 'DNS client cache (first 25)'
       Safe { $c = @(Get-DnsClientCache); "Entries in cache: $($c.Count)"; Table ($c | Select-Object -First 25 Entry, Type, Data) }
       Hdr 'ARP table (arp -a)'
       Safe { arp -a }
       Hdr 'Routing table (route print)'
       Safe { route print }
       Hdr 'Proxy settings'
       Safe {
           netsh winhttp show proxy
           $i = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
           "User proxy: Enabled=$($i.ProxyEnable)  Server=$($i.ProxyServer)  AutoConfigURL=$($i.AutoConfigURL)"
       }
       Hdr 'Winsock catalog'
       Safe { $cat = 'HKLM:\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\Protocol_Catalog9'; "Catalog entries: 64-bit $(@(Get-ChildItem "$cat\Catalog_Entries64" -ErrorAction SilentlyContinue).Count), 32-bit $(@(Get-ChildItem "$cat\Catalog_Entries" -ErrorAction SilentlyContinue).Count)" }   # registry count: works in every language
       Hdr 'TCP global parameters'
       Safe { netsh int tcp show global }
       Hdr 'Hosts file (active entries)'
       Safe { $h = @(Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }); if ($h.Count) { $h } else { '(no active entries)' } }
       Hdr 'Wi-Fi interface'
       Safe { netsh wlan show interfaces }
       Hdr 'Firewall profiles'
       Safe { Table (Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction) }
       Hdr 'Connection counts'
       Safe { $t = @(Get-NetTCPConnection -ErrorAction SilentlyContinue); "Listening: $(@($t | Where-Object State -eq 'Listen').Count)   Established: $(@($t | Where-Object State -eq 'Established').Count)" }
       Hdr 'Live connectivity tests'
       Safe {
           $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
           if ($gw) { "Default gateway $gw : ping " + $(if (Test-Connection $gw -Count 2 -Quiet -ErrorAction SilentlyContinue) { 'OK' } else { 'FAILED' }) } else { 'No default gateway found' }
           "Internet (1.1.1.1) : ping " + $(if (Test-Connection 1.1.1.1 -Count 2 -Quiet -ErrorAction SilentlyContinue) { 'OK' } else { 'FAILED' })
           try { $r = Resolve-DnsName www.microsoft.com -ErrorAction Stop | Select-Object -First 1; "DNS lookup www.microsoft.com : OK ($($r.IPAddress))" } catch { "DNS lookup www.microsoft.com : FAILED - $($_.Exception.Message)" }
           "HTTPS www.microsoft.com:443 : " + $(if (Test-TcpPort 'www.microsoft.com' 443 3000) { 'OK' } else { 'FAILED' })
       }
   }
   Actions = @(
       @{ Label = 'Flush DNS cache'
          Help = @'
Flush DNS cache
Runs Clear-DnsClientCache (ipconfig /flushdns). Removes cached name lookups so stale or wrong addresses are looked up again. Harmless, no reboot. Needs admin.
'@
          Run = { param($Arg); Clear-DnsClientCache; 'DNS cache flushed.' } },
       @{ Label = 'Clear ARP cache'
          Help = @'
Clear ARP cache
Runs netsh interface ip delete arpcache. Removes learned IP-to-MAC mappings so they are re-learned. Fixes "can ping by IP but wrong device answers" after a router or device swap. Harmless, no reboot. Needs admin.
'@
          Run = { param($Arg); netsh interface ip delete arpcache; 'ARP cache cleared.' } },
       @{ Label = 'Release and renew DHCP lease'
          Help = @'
Release and renew DHCP lease
Runs ipconfig /release then /renew on all adapters. The PC briefly loses its address and may get a new one. WARNING: this drops remote-control sessions (RDP, remote support tools). Needs admin.
'@
          Confirm = 'This briefly drops the network connection and will disconnect any remote session. Continue?'
          Run = { param($Arg); ipconfig /release; ipconfig /renew } },
       @{ Label = 'Reset WinHTTP proxy'; Registry = $true
          Help = @'
Reset WinHTTP proxy
Runs netsh winhttp reset proxy to remove a stale system-wide proxy that breaks Windows Update/Store while browsers still work. Does not change the per-user proxy set in Settings. The old setting (WinHttpSettings) is backed up first, so a company proxy can be put back from the Registry Backups tab. Needs admin.
'@
          Run = { param($Arg); Backup-WinHttpProxy; netsh winhttp reset proxy } },
       @{ Label = 'Reset Winsock catalog (reboot needed)'; Registry = $true
          Help = @'
Reset Winsock catalog
Runs netsh winsock reset, which rebuilds the Winsock catalog and removes layered providers installed by old VPN/security/adware software. A reboot is required. Can break software that depends on a custom LSP (rare).
The rebuilt catalog can also drop non-default providers such as RFCOMM (Bluetooth serial): Bluetooth serial / COM-port apps may then need the device re-paired. The tool lists any provider that disappeared. The Registry Backups tab can put the old catalog keys back. Needs admin.
'@
          Confirm = 'Reset the Winsock catalog? A reboot is required afterwards. VPN or security software may need reconfiguring, and Bluetooth serial (RFCOMM) devices may need re-pairing.'
          Run = { param($Arg); Backup-NetRegKeys; Invoke-WinsockReset; 'Reboot required to finish.' } },
       @{ Label = 'Reset TCP/IP stack (reboot needed)'; Registry = $true
          Help = @'
Reset TCP/IP stack
Runs netsh int ip reset, which rewrites the TCP/IP registry keys to defaults. Static IP settings on adapters are cleared and must be re-entered. A reboot is required.
On Windows 10/11 netsh normally reports a few protected items as "failed. Access is denied." - the tool counts them and says so; they do not stop the reset. netsh's own log file is shown if it writes one (newer builds do not); the output is always kept in the session log. Needs admin.
'@
          Confirm = 'Reset the TCP/IP stack? Static IP settings will be lost and a reboot is required.'
          Run = { param($Arg); Backup-NetRegKeys; Invoke-IpReset; 'Reboot required to finish.' } },
       @{ Label = 'FULL network reset (all of the above)'; Registry = $true
          Help = @'
FULL network reset
Runs in order: flush DNS, clear ARP, reset WinHTTP proxy, reset Winsock, reset TCP/IP, release/renew DHCP. This is what the old Network troubleshooter did behind the scenes. A BEFORE and AFTER snapshot is logged. Reboot required. Drops remote sessions. Needs admin.
'@
          Confirm = 'Run the FULL network reset? This drops the connection (including remote sessions), clears static IP settings, may require re-pairing Bluetooth serial (RFCOMM) devices, and requires a reboot.'
          Run = {
              param($Arg)
              Backup-NetRegKeys
              'Flushing DNS...';         Clear-DnsClientCache
              'Clearing ARP cache...';   netsh interface ip delete arpcache
              'Resetting WinHTTP proxy...'; Backup-WinHttpProxy; netsh winhttp reset proxy
              'Resetting Winsock...';    Invoke-WinsockReset
              'Resetting TCP/IP...';     Invoke-IpReset
              'Renewing DHCP...';        ipconfig /release; ipconfig /renew
              'DONE - restart the PC to finish the Winsock and TCP/IP resets (see any NOTE lines above).'
          } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Audio'
   Summary = 'Replaces AudioPlayback / AudioRecording diagcabs: lists audio devices, their state and drivers, then restarts audio services.'
   Help = @'
Audio Playback and Recording (replaces AudioPlayback.diagcab / AudioRecording.diagcab)
Typical causes of "no sound / mic not working": stopped audio services, an endpoint that is disabled/unplugged, a driver in an error state, or mute/enhancement settings.
Mute and enhancement toggles are not read by this tool; use "Open Sound settings" for those.
'@
   StatusLabel = 'Check status: audio services, devices, drivers'
   StatusHelp = @'
Read-only. Shows Audiosrv/AudioEndpointBuilder/MMCSS state, sound devices known to Windows with error codes, every playback and recording endpoint with its state (Active / Disabled / Unplugged / Not present), and the audio driver versions and dates.
'@
   Status = {
       Hdr 'Audio services'
       Safe { Table (Svc 'Audiosrv', 'AudioEndpointBuilder', 'MMCSS') }
       Hdr 'Sound devices (Win32_SoundDevice)'
       Safe { Table (Get-CimInstance Win32_SoundDevice | Select-Object Name, Manufacturer, Status, ConfigManagerErrorCode) }
       Hdr 'Playback and recording endpoints'
       Safe {
           $r = foreach ($flow in 'Render', 'Capture') {
               Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$flow" -ErrorAction SilentlyContinue | ForEach-Object {
                   $st = ([int](Get-ItemProperty $_.PSPath).DeviceState) -band 0xF
                   $pr = Get-ItemProperty "$($_.PSPath)\Properties" -ErrorAction SilentlyContinue
                   [pscustomobject]@{
                       Type    = $(if ($flow -eq 'Render') { 'Playback' } else { 'Recording' })
                       State   = switch ($st) { 1 { 'Active' } 2 { 'DISABLED' } 4 { 'Not present' } 8 { 'Unplugged' } default { "Other ($st)" } }
                       Name    = $pr.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
                       Adapter = $pr.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
                   }
               }
           }
           Table ($r | Sort-Object Type, State)
       }
       Hdr 'Audio drivers'
       Safe { Table (Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='MEDIA'" | Select-Object DeviceName, Manufacturer, DriverVersion, @{ n = 'DriverDate'; e = { $_.DriverDate } }) }
       Hdr 'Audio devices in an error state'
       Safe { Table (Get-CimInstance Win32_PnPEntity | Where-Object { ($_.PNPClass -in 'MEDIA', 'AudioEndpoint') -and $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, PNPClass, ConfigManagerErrorCode) }
   }
   Actions = @(
       @{ Label = 'Restart Windows Audio services'
          Help = @'
Restart Windows Audio services
Stops and starts AudioEndpointBuilder and Audiosrv (dependent services follow). Fixes the red X on the speaker icon and "no audio device" after sleep. Playing audio cuts out for a moment. Needs admin.
'@
          Run = { param($Arg); StopSvc 'Audiosrv'; StopSvc 'AudioEndpointBuilder'; StartSvc 'AudioEndpointBuilder'; StartSvc 'Audiosrv' } },
       @{ Label = 'Re-enable disabled audio devices'
          Help = @'
Re-enable disabled audio devices
Finds audio devices in the "Disabled" state (device-manager error code 22) and enables them with Enable-PnpDevice. Does not touch drivers or settings. Needs admin.
'@
          Confirm = 'Enable all audio devices that are currently disabled?'
          Run = {
              param($Arg)
              $bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { ($_.PNPClass -in 'MEDIA', 'AudioEndpoint') -and $_.ConfigManagerErrorCode -eq 22 })
              if ($bad.Count -eq 0) { 'No disabled audio devices found.'; return }
              foreach ($d in $bad) { try { Enable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop; "Enabled: $($d.Name)" } catch { "Failed: $($d.Name) - $($_.Exception.Message)" } }
          } },
       @{ Label = 'Open Sound settings (mute / enhancements)'
          Help = @'
Open Sound settings
Opens the classic Sound control panel (mmsys.cpl). Use it to check mute, default device, levels and the "Disable all enhancements" option, which this tool cannot read. Opens a window only.
'@
          Admin = $false; AutoStatus = $false
          Run = { param($Arg); Start-Process mmsys.cpl; 'Opened Sound control panel.' } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Hardware and Devices'
   Summary = 'Replaces DeviceDiagnostic.diagcab: finds devices with problems, disabled devices, USB controller state and unsigned drivers.'
   Help = @'
Hardware and Devices (replaces DeviceDiagnostic.diagcab, which Microsoft hid from Settings)
Lists every device Windows reports a problem with, in plain words (error code meaning), plus USB controllers, unsigned drivers and the USB selective-suspend setting that commonly causes devices to drop off.
'@
   StatusLabel = 'Check status: problem devices, USB, drivers'
   StatusHelp = @'
Read-only. Shows devices with a non-zero Device Manager error code (with meaning), disabled devices, USB controllers and non-OK USB devices, unsigned drivers, device counts by class, and the USB selective-suspend setting of the active power plan.
'@
   Status = {
       Hdr 'Devices with problems'
       Safe {
           $ec = @{ 1 = 'Not configured'; 3 = 'Low memory'; 10 = 'Cannot start'; 12 = 'Resource conflict'; 14 = 'Restart needed'; 18 = 'Reinstall drivers'; 19 = 'Registry problem'; 21 = 'Removal pending'; 22 = 'DISABLED'; 24 = 'Not present / not working'; 28 = 'Drivers not installed'; 31 = 'Not working properly'; 32 = 'Service disabled'; 37 = 'Driver failed to initialize'; 38 = 'Driver load failed'; 39 = 'Driver corrupt or missing'; 40 = 'Registry/service key problem'; 41 = 'Loaded but device not found'; 43 = 'Stopped - reported a problem'; 45 = 'Not connected'; 48 = 'Blocked'; 52 = 'Unsigned driver' }
           Table (Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, PNPClass, @{ n = 'Code'; e = { $_.ConfigManagerErrorCode } }, @{ n = 'Meaning'; e = { $c = [int]$_.ConfigManagerErrorCode; if ($ec.ContainsKey($c)) { $ec[$c] } else { 'Other' } } })
       }
       Hdr 'USB controllers'
       Safe { Table (Get-CimInstance Win32_USBController | Select-Object Name, Status) }
       Hdr 'USB devices not reporting OK'
       Safe { Table (Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' } | Select-Object Status, FriendlyName, InstanceId) }
       Hdr 'Unsigned drivers'
       Safe { Table (Get-CimInstance Win32_PnPSignedDriver -Filter 'IsSigned=FALSE' | Select-Object DeviceName, Manufacturer, DriverVersion) }
       Hdr 'Present devices by class'
       Safe { Table (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Group-Object Class | Sort-Object Count -Descending | Select-Object Count, Name) }
       Hdr 'USB selective suspend (active power plan)'
       Safe { Get-PowerSettings 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 }   # 1 = enabled, 0 = disabled
   }
   Actions = @(
       @{ Label = 'Rescan for hardware changes'
          Help = @'
Rescan for hardware changes
Runs pnputil /scan-devices, the same as "Scan for hardware changes" in Device Manager. Picks up devices that did not enumerate. Harmless. Needs admin.
'@
          Run = { param($Arg); pnputil /scan-devices } },
       @{ Label = 'Enable all disabled devices'
          Help = @'
Enable all disabled devices
Finds devices with error code 22 (Disabled) and enables each with Enable-PnpDevice. Check the status list first: a device may be disabled on purpose (for example, a built-in webcam). Needs admin.
'@
          Confirm = 'Enable every device that is currently disabled? Some may have been disabled on purpose.'
          Run = {
              param($Arg)
              $bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -eq 22 })
              if ($bad.Count -eq 0) { 'No disabled devices found.'; return }
              foreach ($d in $bad) { try { Enable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop; "Enabled: $($d.Name)" } catch { "Failed: $($d.Name) - $($_.Exception.Message)" } }
          } },
       @{ Label = 'Export installed driver list to the Reports folder'
          Help = @'
Export installed driver list
Runs pnputil /enum-drivers and saves the output to a text file in the Reports folder, useful to attach to a ticket or compare against a working machine. Read-only.
'@
          Admin = $false; AutoStatus = $false
          Run = { param($Arg); $f = Join-Path $script:ReportDir ("drivers-{0}-{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')); pnputil /enum-drivers | Out-File $f -Encoding UTF8; "Saved: $f" } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Power'
   Summary = 'Replaces PowerDiagnostic.diagcab: shows plans, sleep/display timers, wake sources and sleep blockers, then restores defaults.'
   Help = @'
Power (replaces PowerDiagnostic.diagcab)
Answers "why won't it sleep / why does it wake / why does the screen stay on". The status check shows the active plan, the sleep and display timers in minutes, which sleep states the hardware supports, what is currently blocking sleep and what last woke the PC.
'@
   StatusLabel = 'Check status: power plan, timers, blockers'
   StatusHelp = @'
Read-only. Shows the active plan and all plans, sleep and display timeout settings (AC/DC), available sleep states (powercfg /a), current power requests (programs blocking sleep or display off; needs admin), devices allowed to wake the PC, the last wake source and whether a battery is present.
'@
   Status = {
       Hdr 'Active power plan'
       Safe { powercfg /getactivescheme }
       Hdr 'All power plans'
       Safe { powercfg /list }
       Hdr 'Sleep settings'
       Safe { Get-PowerSettings 'SUB_SLEEP' }
       Hdr 'Display settings'
       Safe { Get-PowerSettings 'SUB_VIDEO' }
       Hdr 'Available sleep states'
       Safe { powercfg /a }
       Hdr 'What is blocking sleep / display-off right now (needs admin)'
       Safe { powercfg /requests }
       Hdr 'Devices allowed to wake the PC'
       Safe { powercfg /devicequery wake_armed }
       Hdr 'Last wake source'
       Safe { powercfg /lastwake }
       Hdr 'Battery'
       Safe { $b = Get-CimInstance Win32_Battery; if ($b) { Table ($b | Select-Object Name, EstimatedChargeRemaining, BatteryStatus) } else { 'No battery detected (desktop or no driver)' } }
   }
   Actions = @(
       @{ Label = 'Restore default power plans'; Registry = $true
          Help = @'
Restore default power plans
Runs powercfg /restoredefaultschemes. Resets Balanced / Power saver / High performance to Windows defaults, undoing wrong sleep and hibernate timers. CUSTOM plans created by the user or OEM are removed. Needs admin.
'@
          Confirm = 'Restore the default power plans? Custom plans will be removed.'
          Run = { param($Arg); Backup-RegKey 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'power plans'; powercfg /restoredefaultschemes; powercfg /getactivescheme } },
       @{ Label = 'Set Balanced as the active plan'
          Help = @'
Set Balanced as the active plan
Runs powercfg /setactive SCHEME_BALANCED. Switches the active plan without editing any plan's settings.
'@
          Run = { param($Arg); Backup-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActivePowerScheme' 'power plan'; powercfg /setactive SCHEME_BALANCED; powercfg /getactivescheme } },
       @{ Label = 'Generate battery report'
          Help = @'
Generate battery report
Runs powercfg /batteryreport and saves an HTML report (design vs full-charge capacity, usage history) to the Reports folder. Read-only. Laptops only.
'@
          AutoStatus = $false
          Run = { param($Arg); $f = Join-Path $script:ReportDir ("battery-report-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss')); powercfg /batteryreport /output "$f"; if (Test-Path -LiteralPath $f) { "Saved: $f" } else { "No report was written (powercfg exit code $LASTEXITCODE) - this PC may have no battery." } } },
       @{ Label = 'Energy efficiency report (60 s) - opens a window'
          Help = @'
Energy efficiency report
Opens a window and runs powercfg /energy for 60 seconds, then saves an HTML report of power-config problems (blockers, USB suspend, timer issues) to the Reports folder. Leave the PC idle while it runs. Read-only. Needs admin.
'@
          Window = $true; AutoStatus = $false
          Run = {
              $f = "$ReportDir\energy-report.html"
              $sw = [Diagnostics.Stopwatch]::StartNew()
              powercfg /energy /duration 60 /output "$f"
              # seen on Windows 11 build 26300: powercfg returns after < 1 s with exit code 0 and writes NO report - say so
              if (Test-Path -LiteralPath $f) { "Report saved: $f" }
              else { "No report was written (powercfg exit code $LASTEXITCODE after $([int]$sw.Elapsed.TotalSeconds) s). powercfg /energy does not work on every Windows build; try again later or after a Windows update." }
          } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Search and Indexing'
   Summary = 'Replaces SearchDiagnostic.diagcab: checks WSearch and the index, then restarts the service or rebuilds the index.'
   Help = @'
Search and Indexing (replaces SearchDiagnostic.diagcab)
For search that finds nothing, is slow, or uses lots of CPU/disk. Check whether the Windows Search service and the indexer are running and how large the index database is before rebuilding it.
'@
   StatusLabel = 'Check status: Windows Search and index'
   StatusHelp = @'
Read-only. Shows the WSearch service, indexer/search processes and memory, the index database files (Windows.edb on Windows 10, Windows.db / -gather / -usn on Windows 11) with size and date, the Windows Search registry state (SetupCompletedSuccessfully) and recent search/indexer events.
'@
   Status = {
       Hdr 'Windows Search service'
       Safe { Table (Svc 'WSearch') }
       Hdr 'Search processes'
       Safe { Table (Get-Process SearchIndexer, SearchHost, SearchApp -ErrorAction SilentlyContinue | Select-Object Name, Id, @{ n = 'CPUsec'; e = { [math]::Round($_.CPU, 1) } }, @{ n = 'MemMB'; e = { [math]::Round($_.WS / 1MB, 1) } }) }
       Hdr 'Index database'
       Safe {
           $dir = Get-SearchIndexDir
           $f = @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Windows(-\w+)?\.(edb|db)$' })
           if ($f.Count) { $f | ForEach-Object { '{0} : {1:N1} MB, last written {2}' -f $_.Name, ($_.Length / 1MB), $_.LastWriteTime } } else { "No index database found in $dir (or no access - run as admin)" }
       }
       Hdr 'Registry state'
       Safe { $r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Search'; "SetupCompletedSuccessfully = $($r.SetupCompletedSuccessfully)   DataDirectory = $($r.DataDirectory)" }
       Hdr 'Recent search events'
       Safe { Table (Get-RecentEvents @{ LogName = 'Application'; ProviderName = @('Windows Search Service', 'Microsoft-Windows-Search') } 10) }
   }
   Actions = @(
       @{ Label = 'Restart Windows Search service'
          Help = @'
Restart Windows Search service
Stops and starts WSearch. Fixes a hung indexer without changing the index. Needs admin.
'@
          Run = { param($Arg); StopSvc 'WSearch'; StartSvc 'WSearch' } },
       @{ Label = 'Rebuild search index'; Registry = $true
          Help = @'
Rebuild search index
Stops WSearch, sets SetupCompletedSuccessfully to 0, DELETES the index database (Windows.edb on Windows 10; Windows.db, Windows-gather.db, Windows-usn.db and their -wal/-shm files on Windows 11 22H2+; it is only a cache and is rebuilt automatically) and starts WSearch. Search results are incomplete and the disk/CPU is busy for a while (minutes to hours) while it re-indexes. Needs admin.
'@
          Confirm = 'Delete the search index database and rebuild it? Search will be incomplete while it re-indexes.'
          Run = {
              param($Arg)
              StopSvc 'WSearch'
              Set-RegValueSafe 'HKLM:\SOFTWARE\Microsoft\Windows Search' 'SetupCompletedSuccessfully' 0 'DWord' 'rebuild search index'
              # Windows 10 and older: Windows.edb (ESE). Windows 11 22H2+: Windows.db / Windows-gather.db / Windows-usn.db (SQLite, + -wal/-shm)
              $dir = Get-SearchIndexDir
              $files =@(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Windows(-\w+)?\.(edb|db)(-wal|-shm)?$' })
              if ($files.Count -eq 0) { "No index database found in $dir (nothing to delete - the registry reset above still forces a rebuild)" }
              foreach ($f in $files) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; "Deleted $($f.Name)" } catch { "Could not delete $($f.Name): $($_.Exception.Message)" } }
              StartSvc 'WSearch'
              'Indexing will now rebuild in the background.'
          } },
       @{ Label = 'Open Indexing Options'
          Help = @'
Open Indexing Options
Opens the classic Indexing Options dialog to see indexed locations and item counts, or use Advanced > Rebuild. Opens a window only.
'@
          Admin = $false; AutoStatus = $false
          Run = { param($Arg); Start-Process control.exe -ArgumentList '/name Microsoft.IndexingOptions'; 'Opened Indexing Options.' } }
   )
},

# ---------------------------------------------------------------------------------------------
@{ Name = 'Network Sharing'
   Summary = 'Replaces HomeGroupDiagnostic.diagcab: HomeGroup no longer exists, so this checks the discovery/SMB sharing pieces that replaced it.'
   Help = @'
Network Sharing (replaces HomeGroupDiagnostic.diagcab)
HomeGroup was removed in Windows 10 1803 and does not exist in Windows 11, so it cannot be repaired there. What actually makes PCs see each other today is: the network profile (Private), Function Discovery and SSDP services, Network Discovery + File and Printer Sharing firewall rules, SMB, and IPv6/IPv4 bindings. This tab checks and fixes those.
'@
   StatusLabel = 'Check status: discovery, SMB, firewall rules'
   StatusHelp = @'
Read-only. Shows OS build and whether legacy HomeGroup services exist, network profile category, discovery services (FDResPub, fdPHost, SSDPSRV, upnphost), file-sharing services (LanmanServer/Workstation), SMB protocol settings and shares, firewall rule groups for Network Discovery and File and Printer Sharing, and IPv6 bindings.
'@
   Status = {
       Hdr 'OS and legacy HomeGroup'
       Safe {
           $o = Get-CimInstance Win32_OperatingSystem
           "$($o.Caption) build $($o.BuildNumber)"
           Table (Svc 'HomeGroupListener', 'HomeGroupProvider')
       }
       Hdr 'Network profile'
       Safe { Table (Get-NetConnectionProfile | Select-Object Name, InterfaceAlias, NetworkCategory) }
       Hdr 'Discovery services'
       Safe { Table (Svc 'FDResPub', 'fdPHost', 'SSDPSRV', 'upnphost') }
       Hdr 'File sharing services'
       Safe { Table (Svc 'LanmanServer', 'LanmanWorkstation', 'lmhosts') }
       Hdr 'SMB server configuration'
       Safe { Table (Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol, RequireSecuritySignature) }
       Hdr 'SMB shares'
       Safe { Table (Get-SmbShare | Select-Object Name, Path, Description) }
       Hdr 'Firewall rule groups (Enabled count)'
       Safe {
           foreach ($g in $script:FwGroups.Keys) {
               "$g :"
               Table (Get-NetFirewallRule -Group $script:FwGroups[$g] -ErrorAction SilentlyContinue | Group-Object Enabled, Profile | Select-Object @{ n = 'Enabled, Profile'; e = { $_.Name } }, Count)
           }
       }
       Hdr 'IPv6 bindings'
       Safe { Table (Get-NetAdapterBinding -ComponentID ms_tcpip6 | Select-Object Name, DisplayName, Enabled) }
   }
   Actions = @(
       @{ Label = 'Start and enable discovery services'; Registry = $true
          Help = @'
Start and enable discovery services
Sets FDResPub, fdPHost, SSDPSRV, upnphost and LanmanServer to start Automatically and starts them. These make the PC visible in Network and let it find others. Needs admin.
'@
          Run = {
              param($Arg)
              foreach ($s in 'fdPHost', 'FDResPub', 'SSDPSRV', 'upnphost', 'LanmanServer') {
                  Set-SvcStartup $s 'Automatic'; StartSvc $s
              }
          } },
       @{ Label = 'Enable Network Discovery + File/Printer Sharing rules'; Registry = $true
          Help = @'
Enable Network Discovery + File/Printer Sharing rules
Enables the rules of the built-in firewall groups "Network Discovery" and "File and Printer Sharing" that apply ONLY to Private and/or Domain networks (rules that also cover Public stay as they are, and no rule's profile is changed). The groups are found by their language-independent resource IDs. Needs admin. This opens SMB/discovery ports on trusted networks, so do not use on a PC that stays on public Wi-Fi.
'@
          Confirm = 'Enable the Network Discovery and File and Printer Sharing firewall rules for Private and Domain networks?'
          Run = {
              param($Arg)
              Backup-RegKey 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy' 'firewall rules'
              # NOT Set-NetFirewallRule -Profile: that REWRITES each rule's profile. Enable only rules that never apply to Public.
              # Profile flags: Any = 0, Domain = 1, Private = 2, Public = 4.
              foreach ($g in $script:FwGroups.Keys) {
                  try {
                      $r = @(Get-NetFirewallRule -Group $script:FwGroups[$g] -ErrorAction Stop | Where-Object { $pf = [int]$_.Profile; $pf -ne 0 -and -not ($pf -band 4) })
                      if ($r.Count) { $r | Enable-NetFirewallRule -ErrorAction Stop }
                      "Enabled $($r.Count) rule(s) of group $g (Private / Domain only; Public rules untouched)"
                  } catch { "Failed ${g}: $($_.Exception.Message)" }
              }
          } },
       @{ Label = 'Set Public networks to Private'; Registry = $true
          Help = @'
Set Public networks to Private
Changes every connection currently categorised Public to Private so discovery and sharing rules apply. Only do this on a trusted home/office network. Needs admin.
'@
          Confirm = 'Change all Public network connections to Private? Only do this on a trusted network.'
          Run = { param($Arg); Backup-RegKey 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList' 'network profiles'; Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' } | ForEach-Object { try { Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private -ErrorAction Stop; "Set $($_.Name) to Private" } catch { "Could not change $($_.Name): $($_.Exception.Message)" } } } }
   )
},

@{ Name = 'SMB 24H2 Fix'
   Summary = 'Windows 11 24H2 cannot open network shares (0x80070035 "network path not found"): allow insecure guest logons and relax SMB signing.'
   Help = @'
SMB 24H2 Fix (source: wintips.org "Windows 11 24H2 cannot access network shares 0x80070035")
Cause: Windows 11 24H2 no longer allows access to shares without credentials (insecure guest logons are off) and requires SMB signing by default, so NAS boxes, routers with USB drives and older PCs that use guest access stop working.

The recommended, secure fix is to create a user account and password on the PC that hosts the share for each person who needs it. If that is not possible, the buttons below apply the article's three methods. The article says to apply them on BOTH the PC with the shares and the 24H2 PC.

SECURITY: these methods allow unauthenticated guest access and unsigned SMB traffic. Only use them on a network you trust. Undo from the Registry Backups tab (originals are backed up first).
'@
   StatusLabel = 'Check status: SMB client/server and share access'
   StatusHelp = @'
Read-only. Shows build/version and whether it is 24H2 or newer, the SMB client settings (EnableInsecureGuestLogons, signing), the SMB server settings, the exact registry values the fixes change (including the policy and WOW6432Node locations), LanmanWorkstation/LanmanServer services, current SMB connections and mapped drives, and recent SMB client connectivity events.
'@
   Status = {
       Hdr 'Windows version'
       Safe { $o = Get-CimInstance Win32_OperatingSystem; $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; "$($o.Caption) $($v.DisplayVersion) build $($o.BuildNumber).$($v.UBR)"; "24H2 or newer (build 26100+): $([int]$o.BuildNumber -ge 26100)" }
       Hdr 'SMB client configuration (this PC connecting to shares)'
       Safe { Table (Get-SmbClientConfiguration | Select-Object EnableInsecureGuestLogons, RequireSecuritySignature, EnableSecuritySignature) }
       Hdr 'SMB server configuration (this PC hosting shares)'
       Safe { Table (Get-SmbServerConfiguration | Select-Object RequireSecuritySignature, EnableSecuritySignature, EnableSMB1Protocol, EnableSMB2Protocol) }
       Hdr 'Registry values these fixes touch'
       Safe {
           $items = @(
               @('HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters', 'RequireSecuritySignature'),
               @('HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters', 'EnableSecuritySignature'),
               @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation', 'AllowInsecureGuestAuth'),
               @('HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\LanmanWorkstation', 'AllowInsecureGuestAuth'),
               @('HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters', 'requiresecuritysignature'),
               @('HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters', 'enablesecuritysignature')
           )
           foreach ($i in $items) { '{0}  [{1}] = {2}' -f $i[0], $i[1], (Get-RegVal $i[0] $i[1]) }
       }
       Hdr 'Services'
       Safe { Table (Svc 'LanmanWorkstation', 'LanmanServer') }
       Hdr 'Current SMB connections (outbound)'
       Safe { Table (Get-SmbConnection | Select-Object ServerName, ShareName, UserName, Dialect, NumOpens) }
       Hdr 'Mapped drives'
       Safe { Table (Get-SmbMapping | Select-Object LocalPath, RemotePath, Status) }
       Hdr 'Recent SMB client connectivity events'
       Safe { Table (Get-RecentEvents @{ LogName = 'Microsoft-Windows-SmbClient/Connectivity' } 10) }
   }
   Actions = @(
       @{ Label = 'Test access to a PC / NAS by name or IP...'
          Help = @'
Test access to a PC / NAS
Asks for a computer name or IP address, then checks DNS (for a name), whether TCP 445 (SMB) and 139 answer, and whether the share list of \\name can be read (net view - its result is judged by the exit code, so it works in any language). Read-only. Use it before and after a fix. (Tip from the article: also try typing \\name or \\IP in File Explorer's address bar.)
'@
          Admin = $false; AutoStatus = $false; Prompt = 'Text'; PromptText = 'Computer name or IP address of the PC / NAS with the shares (for example PC1 or 192.168.1.25):'
          Run = {
              param($Arg)
              $h = (([string]$Arg).Trim().TrimStart('\') -split '[\\/]')[0]   # "\\nas\public" -> "nas"
              "Target: $h"
              $ip = $null
              if ([Net.IPAddress]::TryParse($h, [ref]$ip)) {
                  # an IP needs no name lookup; a reverse lookup only returns a PTR record (no IPAddress field)
                  $ptr = try { (Resolve-DnsName $h -ErrorAction Stop | Where-Object { $_.NameHost } | Select-Object -First 1).NameHost } catch { $null }
                  'Name lookup: not needed (target is an IP address)' + $(if ($ptr) { "; reverse name: $ptr" } else { '' })
              } else {
                  try {
                      $ips = @(Resolve-DnsName $h -ErrorAction Stop | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress } | Select-Object -Unique)
                      if ($ips.Count) { "Name lookup: OK ($($ips -join ', '))" } else { 'Name lookup: answered, but without an IP address (try the IP address instead)' }
                  } catch { 'Name lookup: failed (try the IP address instead)' }
              }
              "TCP 445 (SMB): " + $(if (Test-TcpPort $h 445 3000) { 'OPEN' } else { 'closed / unreachable' })
              "TCP 139 (NetBIOS): " + $(if (Test-TcpPort $h 139 3000) { 'OPEN' } else { 'closed / unreachable' })
              # "\\server" alone is not a folder (Test-Path is ALWAYS false for it), so judge by net view's exit code instead
              # (stderr lines arrive as ErrorRecords: print their text only, and drop empty ones)
              $nv = @(& net.exe view "\\$h" 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } } | Where-Object { $_ -and $_ -ne 'System.Management.Automation.RemoteException' }); $rc = $LASTEXITCODE
              "Share list (net view \\$h): " + $(if ($rc -eq 0) { 'OK' } else { "FAILED (exit code $rc)" })
              $nv
          } },
       @{ Label = 'Method 3 (PowerShell): allow insecure guest + no signing'; Registry = $true
          Help = @'
Method 3 - PowerShell (the one most commenters report as working)
Backs up the related registry values, then runs:
  Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force
  Set-SmbClientConfiguration -RequireSecuritySignature $false -Force
  Set-SmbServerConfiguration -RequireSecuritySignature $false -Force
Run it on the 24H2 PC AND on the PC/NAS-host that has the shares. Reboot afterwards. Lowers SMB security. Needs admin.
'@
          Confirm = 'Allow insecure guest logons and stop requiring SMB signing on this PC? Only do this on a trusted network. (Originals are backed up first.)'
          Run = {
              param($Arg)
              $ws = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
              $sv = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
              foreach ($n in 'RequireSecuritySignature', 'EnableSecuritySignature', 'AllowInsecureGuestAuth') { Backup-RegValue $ws $n 'SMB 24H2 fix' }
              foreach ($n in 'requiresecuritysignature', 'enablesecuritysignature') { Backup-RegValue $sv $n 'SMB 24H2 fix' }
              try {
                  Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force -ErrorAction Stop
                  Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
                  Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
                  'Applied. Reboot (or restart the Workstation/Server services) and test again.'
              } catch { "FAILED: $($_.Exception.Message) - not everything was applied; use the Registry Backups tab to undo what was." }
          } },
       @{ Label = 'Method 2 (registry): the three reg add values'; Registry = $true
          Help = @'
Method 2 - Registry (works on Windows Home)
Sets these three DWORD values (originals backed up first):
  HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters   RequireSecuritySignature = 0
  HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation            AllowInsecureGuestAuth = 1
  HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\LanmanWorkstation AllowInsecureGuestAuth = 1
Reboot afterwards. To undo, use the Registry Backups tab (it removes values that did not exist before). Needs admin.
'@
          Confirm = 'Apply the three Method 2 registry values (allow insecure guest logons, no required signing)? Originals are backed up first.'
          Run = {
              param($Arg)
              Set-RegValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' 'RequireSecuritySignature' 0 'DWord' 'SMB 24H2 fix'
              Set-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation' 'AllowInsecureGuestAuth' 1 'DWord' 'SMB 24H2 fix'
              Set-RegValueSafe 'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\LanmanWorkstation' 'AllowInsecureGuestAuth' 1 'DWord' 'SMB 24H2 fix'
              'Applied. Reboot (or restart the Workstation service) and test again.'
          } },
       @{ Label = 'Method 1, step 2: disable client signing (both policies)'; Registry = $true
          Help = @'
Method 1, step 2 equivalent
In Group Policy this is Security Options: "Microsoft network client: Digitally sign communications (always)" and "(if server agrees)" both set to Disabled. This button sets the matching registry values directly (works on Home too):
  HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters  RequireSecuritySignature = 0
  HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters  EnableSecuritySignature = 0
Use it if the insecure-guest fix alone did not help. Originals are backed up first. Needs admin.
'@
          Confirm = 'Disable SMB client signing (always + if server agrees)? Originals are backed up first.'
          Run = {
              param($Arg)
              $ws = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
              Set-RegValueSafe $ws 'RequireSecuritySignature' 0 'DWord' 'SMB 24H2 fix'
              Set-RegValueSafe $ws 'EnableSecuritySignature' 0 'DWord' 'SMB 24H2 fix'
              'Applied. Reboot and test again.'
          } },
       @{ Label = 'Restart SMB Workstation + Server services'
          Help = @'
Restart SMB Workstation + Server services
Restarts LanmanWorkstation (and LanmanServer) so new SMB settings apply without a reboot. Dependent services restart too and mapped drives may briefly disconnect. A reboot is still the most reliable way. Needs admin.
'@
          Confirm = 'Restart the SMB Workstation and Server services? Mapped drives may briefly disconnect.'
          Run = {
              param($Arg)
              foreach ($s in 'LanmanWorkstation', 'LanmanServer') { try { Restart-Service -Name $s -Force -ErrorAction Stop; "Restarted $s" } catch { "Could not restart ${s}: $($_.Exception.Message)" } }
          } },
       @{ Label = 'Open Local Group Policy Editor (Method 1, Pro only)'
          Help = @'
Open Local Group Policy Editor
Method 1 from the article, for Windows Pro/Enterprise. Opens gpedit.msc. Then go to:
  Computer Configuration > Administrative Templates > Network > Lanman Workstation > "Enable insecure guest logons" = Enabled
  Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options: both "Microsoft Network Client: Digitally sign communications" policies = Disabled
Restart afterwards, on both PCs. Not available on Home editions (use Method 2 or 3 there).
'@
          Admin = $false; AutoStatus = $false
          Run = { param($Arg); if (Test-Path "$env:SystemRoot\System32\gpedit.msc") { Start-Process gpedit.msc; 'Opened Group Policy Editor.' } else { 'gpedit.msc is not available on this edition (Windows Home). Use Method 2 or Method 3.' } } }
   )
}
)

# Defaults: every action needs admin and takes before/after snapshots unless it says otherwise
foreach ($s in $Sections) {
    foreach ($a in $s.Actions) {
        if (-not $a.ContainsKey('Admin'))      { $a.Admin = $true }
        if (-not $a.ContainsKey('AutoStatus')) { $a.AutoStatus = $true }
        if (-not $a.ContainsKey('Window'))     { $a.Window = $false }
        if (-not $a.ContainsKey('Confirm'))    { $a.Confirm = $null }
        if (-not $a.ContainsKey('Prompt'))     { $a.Prompt = $null }
        if (-not $a.ContainsKey('Registry'))   { $a.Registry = $false }
    }
}

# =============================================================================================
#  GUI plumbing
# =============================================================================================
function New-Ctl([string]$Type, [hashtable]$P = @{}) {
    $c = New-Object ("System.Windows.Forms.$Type")
    foreach ($k in $P.Keys) { $c.$k = $P[$k] }
    $c
}

function Write-Out([string]$Text, [string]$Color = 'LightGray') {
    $o = $script:Out
    $o.SelectionStart = $o.TextLength
    $o.SelectionLength = 0
    $o.SelectionColor = [System.Drawing.Color]::FromName($Color)
    $o.AppendText($Text + "`r`n")
    $o.SelectionStart = $o.TextLength
    $o.ScrollToCaret()
    try { Add-Content -Path $script:LogFile -Value $Text -Encoding UTF8 } catch { }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-Capture([scriptblock]$Block, $Arg) {
    try { (& $Block $Arg *>&1 | Out-String -Width 220).TrimEnd() }
    catch { "ERROR: $($_.Exception.Message)" }
}

function Set-Busy([bool]$b) {
    $script:Tabs.Enabled = -not $b
    $script:Bottom.Enabled = -not $b
    $script:Form.Cursor = if ($b) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Help([string]$Title, [string]$Text) {
    [void][System.Windows.Forms.MessageBox]::Show($Text.Trim(), $Title, 'OK', 'Information')
}

function Invoke-StatusClick($sec) {
    Set-Busy $true
    try {
        Write-Out ("`r`n########## STATUS: {0}   [{1}] ##########" -f $sec.Name, (Get-Date -Format 'HH:mm:ss')) 'Cyan'
        Write-Out (Invoke-Capture $sec.Status $null) 'White'
    } finally { Set-Busy $false }
}

function Invoke-ActionClick($sec, $act) {
    if ($act.Admin -and -not (Test-Admin)) {
        [void][System.Windows.Forms.MessageBox]::Show('This fix needs administrator rights. Use "Relaunch as Administrator" at the bottom, then try again. (Status checks work without admin.)', 'Administrator required', 'OK', 'Warning')
        return
    }
    $arg = $null
    if ($act.Prompt -eq 'Folder') {
        $fb = New-Ctl FolderBrowserDialog @{ Description = $act.PromptText }
        if ($fb.ShowDialog() -ne 'OK') { return }
        $arg = $fb.SelectedPath
    }
    elseif ($act.Prompt -eq 'Text') {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $arg = [Microsoft.VisualBasic.Interaction]::InputBox($act.PromptText, $act.Label, '')
        if (-not $arg -or -not $arg.Trim()) { return }
    }
    if ($act.Confirm) {
        $msg = $act.Confirm
        if ($arg) { $msg += "`r`n`r`nTarget: $arg" }
        if ([System.Windows.Forms.MessageBox]::Show($msg, 'Confirm: ' + $act.Label, 'YesNo', 'Warning') -ne 'Yes') {
            Write-Out "Cancelled: $($act.Label)" 'Yellow'
            return
        }
    }
    Set-Busy $true
    try {
        Write-Out ("`r`n########## FIX: {0} > {1}   [{2}] ##########" -f $sec.Name, $act.Label, (Get-Date -Format 'HH:mm:ss')) 'Cyan'
        if ($act.AutoStatus -and $sec.Status) {
            Write-Out '--- BEFORE (status snapshot) ---' 'Yellow'
            Write-Out (Invoke-Capture $sec.Status $null) 'White'
        }
        if ($act.Registry) {
            Write-Out '--- REGISTRY SAFETY: full backup + per-item originals ---' 'Yellow'
            Write-Out (Invoke-Capture { Ensure-FullRegBackup } $null) 'LightGreen'
        }
        Write-Out '--- RUNNING ---' 'Yellow'
        if ($act.Window) {
            Write-Out (Start-InWindow $act.Run $act.Label) 'LightGreen'
        } else {
            Write-Out (Invoke-Capture $act.Run $arg) 'LightGreen'
            if ($act.AutoStatus -and $sec.Status) {
                Write-Out '--- AFTER (status snapshot) ---' 'Yellow'
                Write-Out (Invoke-Capture $sec.Status $null) 'White'
            }
        }
        Write-Out '--- finished ---' 'Yellow'
    } finally { Set-Busy $false; Update-RegBackupList }
}

function Invoke-AllStatus {
    Set-Busy $true
    try {
        foreach ($s in $Sections) {
            if ($s.Status) {
                Write-Out ("`r`n########## STATUS: {0}   [{1}] ##########" -f $s.Name, (Get-Date -Format 'HH:mm:ss')) 'Cyan'
                Write-Out (Invoke-Capture $s.Status $null) 'White'
            }
        }
        Write-Out "`r`nAll status checks complete. Session log: $script:LogFile" 'LightGreen'
    } finally { Set-Busy $false }
}

# ---- Build the window -----------------------------------------------------------------------
$script:Form = New-Ctl Form @{ Text = 'WinFixKit - Windows Troubleshooting Power Tool'; StartPosition = 'CenterScreen'; Width = 1180; Height = 840; MinimumSize = (New-Object System.Drawing.Size 900, 600) }
Set-WrtScaling $script:Form
$tip = New-Ctl ToolTip @{ AutoPopDelay = 20000; InitialDelay = 300; ReshowDelay = 200 }

# Top banner
$banner = New-Ctl Panel @{ Dock = 'Top'; Height = 54; BackColor = [System.Drawing.Color]::FromArgb(0, 51, 102) }
$bTitle = New-Ctl Label @{ Text = 'WinFixKit  -  check status first, then fix.  Every fix logs a BEFORE and AFTER snapshot.  Click ? to see what any button does.'; ForeColor = [System.Drawing.Color]::White; Left = 10; Top = 6; AutoSize = $true; Font = (New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)) }
$adminText = if (Test-Admin) { 'Running as ADMINISTRATOR - fixes enabled' } else { 'Standard user - status checks only (fixes need admin)' }
$adminColor = if (Test-Admin) { 'LightGreen' } else { 'Khaki' }
$bAdmin = New-Ctl Label @{ Text = "$adminText     |     Folder: $script:RootDir"; ForeColor = [System.Drawing.Color]::FromName($adminColor); Left = 10; Top = 30; AutoSize = $true; Font = (New-Object System.Drawing.Font('Segoe UI', 9)) }
$banner.Controls.AddRange(@($bTitle, $bAdmin))

# Split: tabs on top, output below
$split = New-Ctl SplitContainer @{ Dock = 'Fill'; Orientation = 'Horizontal' }
$script:Tabs = New-Ctl TabControl @{ Dock = 'Fill'; Multiline = $true }
$split.Panel1.Controls.Add($script:Tabs)

$script:Out = New-Ctl RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BackColor = [System.Drawing.Color]::Black; ForeColor = [System.Drawing.Color]::LightGray; Font = (New-Object System.Drawing.Font('Consolas', 9)); WordWrap = $false; HideSelection = $false }
$split.Panel2.Controls.Add($script:Out)

function Add-Row($flow, [string]$Label, $BtnTag, [string]$HelpTitle, [string]$HelpText, [bool]$IsStatus) {
    $row = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false; Margin = (New-Object System.Windows.Forms.Padding 3) }
    $b = New-Ctl Button @{ Text = $Label; Width = 400; Height = 30; Tag = $BtnTag; TextAlign = 'MiddleLeft' }
    if ($IsStatus) { $b.Add_Click({ param($s, $e) Invoke-StatusClick $s.Tag.Section }) }
    else { $b.Add_Click({ param($s, $e) Invoke-ActionClick $s.Tag.Section $s.Tag.Action }) }
    $q = New-Ctl Button @{ Text = '?'; Width = 30; Height = 30; Tag = @{ Title = $HelpTitle; Text = $HelpText }; Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
    $q.Add_Click({ param($s, $e) Show-Help $s.Tag.Title $s.Tag.Text })
    $tip.SetToolTip($b, (($HelpText.Trim() -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Skip 1 -First 1))
    $tip.SetToolTip($q, 'Click for a full explanation of this button')
    $row.Controls.AddRange(@($b, $q))
    $flow.Controls.Add($row)
}

foreach ($sec in $Sections) {
    $page = New-Ctl TabPage @{ Text = $sec.Name; Padding = (New-Object System.Windows.Forms.Padding 6) }
    $flow = New-Ctl FlowLayoutPanel @{ Dock = 'Fill'; FlowDirection = 'TopDown'; WrapContents = $false; AutoScroll = $true }

    # Section summary with its own ? button
    $hdrRow = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false; Margin = (New-Object System.Windows.Forms.Padding 3) }
    $lbl = New-Ctl Label @{ Text = $sec.Summary; AutoSize = $true; MaximumSize = (New-Object System.Drawing.Size 950, 0); Margin = (New-Object System.Windows.Forms.Padding 3, 8, 3, 8); Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)) }
    $sq = New-Ctl Button @{ Text = '?'; Width = 30; Height = 26; Tag = @{ Title = $sec.Name; Text = $sec.Help }; Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
    $sq.Add_Click({ param($s, $e) Show-Help $s.Tag.Title $s.Tag.Text })
    $tip.SetToolTip($sq, 'About this tab')
    $hdrRow.Controls.AddRange(@($sq, $lbl))
    $flow.Controls.Add($hdrRow)

    if ($sec.Status) {
        Add-Row $flow $sec.StatusLabel @{ Section = $sec } ($sec.Name + ': status check') $sec.StatusHelp $true
    }
    if ($sec.Actions.Count -gt 0) {
        $sep = New-Ctl Label @{ Text = 'Fixes (each takes a BEFORE and AFTER snapshot):'; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 3, 10, 3, 2); Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
        $flow.Controls.Add($sep)
        foreach ($a in $sec.Actions) {
            $tag = @{ Section = $sec; Action = $a }
            $label = $a.Label
            if ($a.Admin) { $label += '  [admin]' }
            Add-Row $flow $label $tag $a.Label $a.Help $false
        }
    }
    $page.Controls.Add($flow)
    $script:Tabs.TabPages.Add($page)
}

# ---- Custom tab: Service Killer ---------------------------------------------------------------
$script:KillBoxes = @(); $script:KillLabels = @()
$script:KillCounts = @(0, 0, 0, 0, 0, 0, 0)
$script:KillRunning = $false
$script:KillCritical = @('RpcSs', 'RpcEptMapper', 'DcomLaunch', 'LSM', 'SamSs', 'BrokerInfrastructure', 'CoreMessagingRegistrar', 'SystemEventsBroker', 'Power', 'PlugPlay', 'ProfSvc', 'EventLog', 'mpssvc', 'BFE')

# $true if the service's recovery settings REBOOT Windows when it dies (SC_ACTION_REBOOT = 2).
# Reads the FailureActions registry value directly, so it does not depend on the Windows display language.
function Test-RebootOnFailure([string]$Name) {
    $b = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name FailureActions -ErrorAction SilentlyContinue).FailureActions
    if (-not $b -or $b.Length -lt 20) { return $false }
    $n = [BitConverter]::ToInt32($b, 12)
    for ($i = 0; $i -lt $n -and (24 + 8 * $i) -le $b.Length; $i++) { if ([BitConverter]::ToInt32($b, 20 + 8 * $i) -eq 2) { return $true } }
    return $false
}
$script:KillBlockedProcs = @('lsass', 'csrss', 'wininit', 'winlogon', 'services', 'smss', 'System', 'Registry', 'Memory Compression')
$script:KillTimer = New-Object System.Windows.Forms.Timer
$script:KillTimer.Interval = 1000
$script:KillTimer.Add_Tick({ Invoke-KillTick })

function Invoke-KillTick {
    $script:KillTimer.Stop()
    try {
        for ($i = 0; $i -lt 7; $i++) {
            $name = $script:KillBoxes[$i].Text.Trim()
            $lbl = $script:KillLabels[$i]
            if (-not $name) { $lbl.Text = '-'; continue }
            if ($script:KillCritical -contains $name) { $lbl.Text = 'REFUSED: critical system service'; continue }
            $q = (& sc.exe queryex $name 2>&1 | Out-String)
            if ($q -match 'PID\s*:\s*(\d+)') { $svcPid = [int]$Matches[1] } else { $lbl.Text = 'service not found / cannot read PID'; continue }
            if ($svcPid -eq 0) { $lbl.Text = "not running  (killed $($script:KillCounts[$i]) time(s) so far)"; continue }
            $proc = Get-Process -Id $svcPid -ErrorAction SilentlyContinue
            if ($proc -and ($script:KillBlockedProcs -contains $proc.ProcessName)) { $lbl.Text = "REFUSED: PID $svcPid is $($proc.ProcessName)"; continue }
            $shared = @(Get-CimInstance Win32_Service -Filter "ProcessId=$svcPid" -ErrorAction SilentlyContinue)
            $rebooters = @(@($name) + @($shared | ForEach-Object { $_.Name }) | Select-Object -Unique | Where-Object { $script:KillCritical -contains $_ -or (Test-RebootOnFailure $_) })
            if ($rebooters.Count) { $lbl.Text = "REFUSED: PID $svcPid hosts $($rebooters -join ', ') - Windows restarts or breaks if that dies"; continue }
            if ($shared.Count -gt 1 -and -not $script:KillAllowShared.Checked) {
                $others = (($shared | Where-Object { $_.Name -ne $name } | Select-Object -First 4).Name) -join ', '
                $lbl.Text = "SKIPPED: PID $svcPid is shared with $($shared.Count - 1) other service(s) ($others). Tick the box above to allow."
                continue
            }
            $null = & taskkill.exe /f /pid $svcPid 2>&1
            $script:KillCounts[$i]++
            $n = $script:KillCounts[$i]
            $lbl.Text = "killed PID $svcPid   (total kills: $n)"
            try { Add-Content -Path $script:LogFile -Value ("{0}  killed {1} PID {2} (kill #{3})" -f (Get-Date -Format 'HH:mm:ss'), $name, $svcPid, $n) -Encoding UTF8 } catch { }
            if ($n -eq 1 -or ($n % 10) -eq 0) { Write-Out ("Service killer: {0} PID {1} killed (kill #{2})" -f $name, $svcPid, $n) 'Salmon' }
        }
    } finally {
        if ($script:KillRunning) { $script:KillTimer.Start() }
    }
}

function Start-Killer {
    if (-not (Test-Admin)) {
        [void][System.Windows.Forms.MessageBox]::Show('The service killer needs administrator rights. Use "Relaunch as Administrator" at the bottom.', 'Administrator required', 'OK', 'Warning')
        return
    }
    $names = @($script:KillBoxes | ForEach-Object { $_.Text.Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Type at least one service name first.', 'Service Killer', 'OK', 'Information'); return }
    $msg = "This will FORCE-KILL the process of these services every $([int]$script:KillInterval.Value) ms until you click STOP:`r`n`r`n" + ($names -join "`r`n") + "`r`n`r`nForce-killing services can lose unsaved data or destabilise Windows. Continue?"
    if ([System.Windows.Forms.MessageBox]::Show($msg, 'Confirm: start service killer', 'YesNo', 'Warning') -ne 'Yes') { return }
    $script:KillCounts = @(0, 0, 0, 0, 0, 0, 0)
    $script:KillRunning = $true
    foreach ($b in $script:KillBoxes) { $b.Enabled = $false }
    $script:KillInterval.Enabled = $false
    $script:KillStart.Enabled = $false
    $script:KillStop.Enabled = $true
    $script:KillBottomLbl.Visible = $true
    $script:KillBottomStop.Visible = $true
    $script:KillTimer.Interval = [int]$script:KillInterval.Value
    Write-Out ("Service killer STARTED for: " + ($names -join ', ')) 'Salmon'
    $script:KillTimer.Start()
}

function Stop-Killer {
    $script:KillRunning = $false
    $script:KillTimer.Stop()
    foreach ($b in $script:KillBoxes) { $b.Enabled = $true }
    $script:KillInterval.Enabled = $true
    $script:KillStart.Enabled = $true
    $script:KillStop.Enabled = $false
    $script:KillBottomLbl.Visible = $false
    $script:KillBottomStop.Visible = $false
    $summary = for ($i = 0; $i -lt 7; $i++) { $n = $script:KillBoxes[$i].Text.Trim(); if ($n) { "{0}: {1} kill(s)" -f $n, $script:KillCounts[$i] } }
    Write-Out ("Service killer STOPPED. " + ($summary -join '; ')) 'Salmon'
    if ($script:KillRestore.Checked) {
        foreach ($b in $script:KillBoxes) {
            $n = $b.Text.Trim()
            if ($n) { Write-Out (StartSvc $n) 'LightGreen' }
        }
    }
}

$killHelp = @'
Service Killer
Force-kills up to 7 Windows services over and over until you click STOP - useful for a service that keeps restarting itself or will not stop normally.

For each service name the tool repeats this every tick (default 1000 ms):
  sc queryex <name>        -> reads the service's process ID (PID)
  taskkill /f /pid <PID>   -> force-kills that process
Use the SHORT service name (for example CryptSvc, Spooler, wuauserv), shown in Services > Properties > "Service name".

Safety rails:
  - Critical services (RpcSs, DcomLaunch, LSM, SamSs, EventLog, Windows Firewall, ...), any service whose recovery action is "Restart the computer", any process that hosts one of those, and core processes (lsass, csrss, wininit, winlogon, services, smss) are refused.
  - If the PID is shared by several services (a shared svchost), killing it would take the others down too, so it is SKIPPED unless you tick "Allow killing shared processes".
  - Every kill is written to the session log. Closing the window stops the killer.
  - "Start the services again when I click STOP" tries Start-Service on each name afterwards.
Needs admin.
'@

$kpage = New-Ctl TabPage @{ Text = 'Service Killer'; Padding = (New-Object System.Windows.Forms.Padding 6) }
$kflow = New-Ctl FlowLayoutPanel @{ Dock = 'Fill'; FlowDirection = 'TopDown'; WrapContents = $false; AutoScroll = $true }
$khdr = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false }
$kq = New-Ctl Button @{ Text = '?'; Width = 30; Height = 26; Tag = @{ Title = 'Service Killer'; Text = $killHelp }; Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
$kq.Add_Click({ param($s, $e) Show-Help $s.Tag.Title $s.Tag.Text })
$klbl = New-Ctl Label @{ Text = 'Force-kill up to 7 services repeatedly until you click STOP (sc queryex + taskkill /f /pid).'; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 3, 6, 3, 6); Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)) }
$khdr.Controls.AddRange(@($kq, $klbl))
$kflow.Controls.Add($khdr)

for ($i = 1; $i -le 7; $i++) {
    $row = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false }
    $l1 = New-Ctl Label @{ Text = "Service $i :"; Width = 75; Margin = (New-Object System.Windows.Forms.Padding 3, 7, 3, 3) }
    $tb = New-Ctl TextBox @{ Width = 220 }
    $st = New-Ctl Label @{ Text = '-'; AutoSize = $true; MaximumSize = (New-Object System.Drawing.Size 800, 0); Margin = (New-Object System.Windows.Forms.Padding 8, 7, 3, 3) }
    $tip.SetToolTip($tb, 'Short service name, for example CryptSvc, Spooler, wuauserv')
    $script:KillBoxes += $tb
    $script:KillLabels += $st
    $row.Controls.AddRange(@($l1, $tb, $st))
    $kflow.Controls.Add($row)
}

$optRow = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false; Margin = (New-Object System.Windows.Forms.Padding 3, 10, 3, 3) }
$ilbl = New-Ctl Label @{ Text = 'Kill every (ms):'; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 3, 6, 3, 3) }
$script:KillInterval = New-Object System.Windows.Forms.NumericUpDown
$script:KillInterval.Minimum = 250; $script:KillInterval.Maximum = 10000; $script:KillInterval.Increment = 250; $script:KillInterval.Value = 1000; $script:KillInterval.Width = 80
$script:KillAllowShared = New-Ctl CheckBox @{ Text = 'Allow killing shared processes (a shared svchost takes its other services down too)'; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 20, 4, 3, 3) }
$optRow.Controls.AddRange(@($ilbl, $script:KillInterval, $script:KillAllowShared))
$kflow.Controls.Add($optRow)

$optRow2 = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false }
$script:KillRestore = New-Ctl CheckBox @{ Text = 'Start the services again when I click STOP'; AutoSize = $true; Checked = $true }
$optRow2.Controls.Add($script:KillRestore)
$kflow.Controls.Add($optRow2)

$btnRow = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false; Margin = (New-Object System.Windows.Forms.Padding 3, 12, 3, 3) }
$script:KillStart = New-Ctl Button @{ Text = 'START killing'; Width = 170; Height = 36; BackColor = [System.Drawing.Color]::Firebrick; ForeColor = [System.Drawing.Color]::White }
$script:KillStop = New-Ctl Button @{ Text = 'STOP'; Width = 130; Height = 36; Enabled = $false }
$script:KillStart.Add_Click({ Start-Killer })
$script:KillStop.Add_Click({ Stop-Killer })
$btnRow.Controls.AddRange(@($script:KillStart, $script:KillStop))
$kflow.Controls.Add($btnRow)

$kpage.Controls.Add($kflow)
$script:Tabs.TabPages.Add($kpage)

# ---- Custom tab: Registry Backups -------------------------------------------------------------
$regHelp = @'
Registry Backups
Before ANY registry edit WinFixKit does two things:
  1. FULL backup, once per session: copies of HKLM\SYSTEM and HKLM\SOFTWARE (RegistryBackups\Full\<time>\ with a README-RESTORE.txt) plus a System Restore point if System Protection is on. Use this as the last-resort rollback.
  2. ORIGINAL backup of each value/key the fix touches (RegistryBackups\Keys\). The first backup of an item is kept as the original and never overwritten.

Each row below is one backed-up item with its own Restore button:
  - VALUE rows put the original value back, or delete the value if it did not exist before (and remove a key WinFixKit created if it is empty).
  - KEY rows re-import the original .reg export of the whole key (values added later are not removed; a reboot may be needed).

Restoring needs admin. Actions that only use Windows APIs (re-registering apps, enabling devices, DISM) do not edit registry keys directly and are not individually backed up.
'@

function Update-RegBackupList {
    $p = $script:RegPanel
    if (-not $p) { return }
    $p.SuspendLayout()
    try {
        $p.Controls.Clear()
        $rows = @(); $bad = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $script:RegKeyDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
            try {
                $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
                if (-not $m -or -not $m.Type -or -not $m.Key) { throw 'missing fields' }
                $rows += [pscustomobject]@{ File = $f.FullName; M = $m }
            } catch { $bad += $f.Name }
        }
        $rows = @($rows | Sort-Object { $_.M.Created } -Descending)
        $h1 = New-Ctl Label @{ Text = "Per-item originals ($($rows.Count))  -  click Restore to put one item back exactly as it was:"; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 3, 6, 3, 4); Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
        $p.Controls.Add($h1)
        if ($bad.Count) {
            # do not hide them: these changes have NO one-click restore. The matching .reg export (same name) can still be imported by hand.
            $p.Controls.Add((New-Ctl Label @{ Text = ("   WARNING: {0} backup file(s) are unreadable and cannot be restored from here: {1}`r`n   Open the backup folder and import the .reg file with the same name by hand (double-click it, or: reg import <file>)." -f $bad.Count, ($bad -join ', ')); AutoSize = $true; ForeColor = [System.Drawing.Color]::Firebrick; MaximumSize = (New-Object System.Drawing.Size 1000, 0) }))
            $key = ($bad | Sort-Object) -join ','
            if ($key -ne $script:LastBadBackups) { $script:LastBadBackups = $key; Write-Out ("Registry Backups: {0} unreadable backup file(s): {1}" -f $bad.Count, ($bad -join ', ')) 'Salmon' }   # once, not after every fix
        }
        if ($rows.Count -eq 0) {
            $p.Controls.Add((New-Ctl Label @{ Text = '   (none yet - items appear here the first time a fix edits the registry)'; AutoSize = $true }))
        }
        foreach ($r in $rows) {
            $m = $r.M
            if ($m.Type -eq 'Key') { $what = "KEY export   $($m.Key)" }
            else {
                $orig = if ($m.Existed) { if ($m.Kind -eq 'Binary') { '(binary data)' } else { ($m.Data -join ', ') } } else { 'did not exist' }
                $what = "VALUE   $($m.Key)   [$($m.Name)]   original: $orig"
            }
            $txt = "$($m.Created)   $what"
            if ($m.Why) { $txt += "   ($($m.Why))" }
            if ($m.RestoredAt) { $txt += "   [restored $($m.RestoredAt)]" }
            $row = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false }
            $btn = New-Ctl Button @{ Text = 'Restore'; Width = 90; Height = 28; Tag = $r.File }
            $btn.Add_Click({ param($s, $e) Invoke-RegRestoreClick $s.Tag })
            $lab = New-Ctl Label @{ Text = $txt; AutoSize = $true; MaximumSize = (New-Object System.Drawing.Size 1000, 0); Margin = (New-Object System.Windows.Forms.Padding 6, 6, 3, 3) }
            $row.Controls.AddRange(@($btn, $lab))
            $p.Controls.Add($row)
        }
        $h2 = New-Ctl Label @{ Text = 'Full backups (SYSTEM + SOFTWARE hives):'; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 3, 14, 3, 4); Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
        $p.Controls.Add($h2)
        $fulls = @(Get-ChildItem -LiteralPath $script:RegFullDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if ($fulls.Count -eq 0) { $p.Controls.Add((New-Ctl Label @{ Text = '   (none yet - one is taken automatically before the first registry change of a session)'; AutoSize = $true })) }
        foreach ($d in $fulls) {
            $mb = [math]::Round((@(Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum / 1MB, 0)
            $row = New-Ctl FlowLayoutPanel @{ AutoSize = $true; FlowDirection = 'LeftToRight'; WrapContents = $false }
            $btn = New-Ctl Button @{ Text = 'Open folder'; Width = 90; Height = 28; Tag = $d.FullName }
            $btn.Add_Click({ param($s, $e) Start-Process explorer.exe $s.Tag })
            $lab = New-Ctl Label @{ Text = "$($d.Name)   ($mb MB)"; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding 6, 6, 3, 3) }
            $row.Controls.AddRange(@($btn, $lab))
            $p.Controls.Add($row)
        }
    } finally { $p.ResumeLayout() }
}

function Invoke-RegRestoreClick([string]$File) {
    if (-not (Test-Admin)) {
        [void][System.Windows.Forms.MessageBox]::Show('Restoring registry values needs administrator rights. Use "Relaunch as Administrator" at the bottom.', 'Administrator required', 'OK', 'Warning')
        return
    }
    if ([System.Windows.Forms.MessageBox]::Show('Restore this registry item to its original state?', 'Confirm restore', 'YesNo', 'Warning') -ne 'Yes') { return }
    Set-Busy $true
    try {
        Write-Out ("`r`n########## REGISTRY RESTORE   [{0}] ##########" -f (Get-Date -Format 'HH:mm:ss')) 'Cyan'
        Write-Out (Invoke-Capture { param($f) Restore-RegBackup $f } $File) 'LightGreen'
    } finally { Set-Busy $false }
    Update-RegBackupList
}

$rpage = New-Ctl TabPage @{ Text = 'Registry Backups'; Padding = (New-Object System.Windows.Forms.Padding 6) }
$script:RegPanel = New-Ctl FlowLayoutPanel @{ Dock = 'Fill'; FlowDirection = 'TopDown'; WrapContents = $false; AutoScroll = $true }
$rtop = New-Ctl FlowLayoutPanel @{ Dock = 'Top'; Height = 44; FlowDirection = 'LeftToRight'; WrapContents = $false }
$b1 = New-Ctl Button @{ Text = 'Create FULL registry backup now'; Width = 240; Height = 32 }
$b1.Add_Click({
    if (-not (Test-Admin)) { [void][System.Windows.Forms.MessageBox]::Show('A full backup needs administrator rights.', 'Administrator required', 'OK', 'Warning'); return }
    Set-Busy $true
    try { Write-Out "`r`n########## FULL REGISTRY BACKUP ##########" 'Cyan'; Write-Out (Invoke-Capture { Invoke-FullRegBackup } $null) 'LightGreen' } finally { Set-Busy $false }
    Update-RegBackupList
})
$b2 = New-Ctl Button @{ Text = 'Refresh list'; Width = 120; Height = 32 }
$b2.Add_Click({ Update-RegBackupList })
$b3 = New-Ctl Button @{ Text = 'Open backup folder'; Width = 160; Height = 32 }
$b3.Add_Click({ Start-Process explorer.exe $script:RegDir })
$b4 = New-Ctl Button @{ Text = '?'; Width = 30; Height = 32; Tag = @{ Title = 'Registry Backups'; Text = $regHelp }; Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
$b4.Add_Click({ param($s, $e) Show-Help $s.Tag.Title $s.Tag.Text })
$tip.SetToolTip($b1, 'Copies HKLM\SYSTEM and HKLM\SOFTWARE and tries to create a restore point.')
$rtop.Controls.AddRange(@($b1, $b2, $b3, $b4))
$rpage.Controls.Add($script:RegPanel)
$rpage.Controls.Add($rtop)
$script:Tabs.TabPages.Add($rpage)


# Bottom bar
$script:Bottom = New-Ctl FlowLayoutPanel @{ Dock = 'Bottom'; Height = 44; Padding = (New-Object System.Windows.Forms.Padding 6, 6, 6, 4) }
# (parameter is $TipText, not $Tip: PowerShell names ignore case, so $Tip would hide the global $tip ToolTip object)
function Add-BottomButton([string]$Text, [int]$Width, [scriptblock]$Click, [string]$TipText) {
    $b = New-Ctl Button @{ Text = $Text; Width = $Width; Height = 30 }
    $b.Add_Click($Click)
    $tip.SetToolTip($b, $TipText)
    $script:Bottom.Controls.Add($b)
}
Add-BottomButton 'Run ALL status checks' 170 { Invoke-AllStatus } 'Read-only baseline of every tab, written to the session log.'
Add-BottomButton 'Save output as report' 160 {
    $f = Join-Path $script:ReportDir ("Report-{0}-{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $script:Out.Text | Out-File -FilePath $f -Encoding UTF8
    Write-Out "Report saved: $f" 'LightGreen'
} 'Saves what is in the output pane to a text file in the Reports folder.'
Add-BottomButton 'Copy output' 100 { if ($script:Out.TextLength -gt 0) { [System.Windows.Forms.Clipboard]::SetText($script:Out.Text) } } 'Copies the whole output pane to the clipboard (paste into a ticket).'
Add-BottomButton 'Clear output' 100 { $script:Out.Clear() } 'Clears the pane only; the session log file keeps everything.'
Add-BottomButton 'Open WinFixKit folder' 160 { Start-Process explorer.exe $script:RootDir } 'Opens Desktop\WinFixKit (Logs, Reports, RegistryBackups).'
Add-BottomButton 'Relaunch as Administrator' 190 {
    if (Test-Admin) { [void][System.Windows.Forms.MessageBox]::Show('Already running as administrator.', 'WinFixKit', 'OK', 'Information'); return }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-DataRoot', "`"$script:RootDir`""
        $script:Form.Close()
    } catch { [void][System.Windows.Forms.MessageBox]::Show("Could not elevate: $($_.Exception.Message)", 'WinFixKit', 'OK', 'Warning') }
} 'Closes this window and reopens it with administrator rights (needed for fixes).'


$script:KillBottomLbl = New-Ctl Label @{ Text = 'SERVICE KILLER RUNNING'; ForeColor = [System.Drawing.Color]::Red; AutoSize = $true; Visible = $false; Margin = (New-Object System.Windows.Forms.Padding 12, 8, 3, 3); Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) }
$script:KillBottomStop = New-Ctl Button @{ Text = 'STOP service killer'; Width = 160; Height = 30; Visible = $false; BackColor = [System.Drawing.Color]::Firebrick; ForeColor = [System.Drawing.Color]::White }
$script:KillBottomStop.Add_Click({ Stop-Killer })
$script:Bottom.Controls.AddRange(@($script:KillBottomLbl, $script:KillBottomStop))

# Dock order: Fill first, then Bottom, then Top so layout resolves correctly
$script:Form.Controls.Add($split)
$script:Form.Controls.Add($script:Bottom)
$script:Form.Controls.Add($banner)

$script:Form.Add_FormClosing({ $script:KillRunning = $false; $script:KillTimer.Stop() })
$script:Form.Add_Shown({
    Update-RegBackupList
    try { $split.SplitterDistance = [int](340 * (Get-WrtScale $script:Form)) } catch { }
    Write-Out ("WinFixKit started {0} on {1} as {2}  (elevated: {3})" -f (Get-Date), $env:COMPUTERNAME, "$env:USERDOMAIN\$env:USERNAME", (Test-Admin)) 'Cyan'
    Write-Out 'Pick a tab, click its status check first, then use a fix if needed. "?" explains every button.' 'LightGray'
    Write-Out "Session log: $script:LogFile" 'LightGray'
    Write-Out "Data folder (logs, reports, registry backups): $script:RootDir" 'LightGray'
})

Initialize-WrtWindow $script:Form @() 900 600
[void]$script:Form.ShowDialog()
