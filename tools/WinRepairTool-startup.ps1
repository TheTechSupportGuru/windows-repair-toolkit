# Version 1.8.2 (2026-11-20). What changed: docs/changes/V1.8.2.md
# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file or https://www.gnu.org/licenses/.
<#
  Windows Repair Toolkit v2 - single-file WinForms GUI (Windows 11 and WinPE / Hiren's PE 11)
  Tab 1  Mount / unmount partitions (diskpart OR Storage cmdlets, whitelisted non-destructive commands only)
  Tab 2  Safe Mode (minimal): edit the entry directly OR create a separate boot-menu clone
  Tab 3  Sysprep deployment (fixed commands, one at a time, optional /mode:vm)
  Tab 4  EXPERIMENTAL boot recovery tools
#>
$ErrorActionPreference = 'Continue'
$IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
$NL = "`r`n"

# ---- 64-bit: a 32-bit host sees SysWOW64 (no sysprep.exe, no bcdedit/bootrec there) and a redirected registry ----
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $native = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $native) { Start-Process -FilePath $native -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""; exit }
}
$PsExePath = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---- self-elevate (normal Windows only; WinPE already runs as SYSTEM) ----
if (-not $IsWinPE) {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        try { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ErrorAction Stop }
        catch {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show("Windows Repair Toolkit needs administrator rights, and the UAC prompt was cancelled or failed:`r`n`r`n$($_.Exception.Message)", 'Windows Repair Toolkit', 'OK', 'Warning')
        }
        exit
    }
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
Show-WrtSplash 'WinRepairTool'

# ---- where memory + backups live (script folder if writable, else TEMP) ----
$StateDir = $env:TEMP
if ($PSScriptRoot) {
    try {
        $probe = Join-Path $PSScriptRoot '.w'
        [IO.File]::WriteAllText($probe, ''); Remove-Item $probe -Force
        $StateDir = $PSScriptRoot
    } catch {}
}
$StateFile = Join-Path $StateDir 'WinRepairTool.mounts.json'
$script:Mounts = New-Object Collections.ArrayList
# [0] names new clones; [1] = clones made by WinSuperTool (both tools now see and delete each other's clones)
$CloneMarkers = @('Safe Mode (minimal) [WinRepairTool]', 'Safe Mode (minimal) [WinSuperTool]')
$CloneMarker = $CloneMarkers[0]
$BcdBackupDir = Join-Path $StateDir 'BCD-Backups'
$script:Consoles = New-Object Collections.ArrayList     # repair console windows started from the Recovery tab
# PowerShell also treats the typographic quotes U+2018-U+201B as single quotes, so double those too
function Esc-Sq([string]$s) { return ($s -replace "(['$([char]0x2018)-$([char]0x201B)])", '$1$1') }

# ================= helpers =================
function Msg($t, $c = 'Windows Repair Toolkit', $i = 'Information') { [void][Windows.Forms.MessageBox]::Show($t, $c, 'OK', $i) }
function Log($m) { $txtLog.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format HH:mm:ss), $m)) }
function Safe([scriptblock]$Do) { try { & $Do } catch { Log "ERROR: $($_.Exception.Message)"; Msg $_.Exception.Message 'Error' 'Error' } }
function Test-LetterUsed($L) { return ([IO.DriveInfo]::GetDrives().Name -contains ("{0}:\" -f $L.ToUpper())) }
function Fmt-Size($b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
function Ask($t, $c = 'Confirm', $i = 'Question', $def = 'Button1') { return ([Windows.Forms.MessageBox]::Show([string]$t, [string]$c, 'YesNo', $i, $def) -eq 'Yes') }
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
function Test-StorageAvail { return ([bool](Get-Command Get-Disk -ErrorAction SilentlyContinue) -and [bool](Get-Command Add-PartitionAccessPath -ErrorAction SilentlyContinue)) }

# ---- diskpart: ONLY these commands can ever be sent ----
$DpAllow = '^(list (disk|partition|volume)|select (disk|partition) \d+|select volume [D-Z]|detail partition|assign letter=[D-Z]|remove letter=[D-Z])$'
function Invoke-Diskpart([string[]]$Cmds) {
    foreach ($c in $Cmds) { if ($c -notmatch $DpAllow) { throw "Blocked diskpart command: $c" } }
    $tmp = Join-Path $env:TEMP ("dp_{0}.txt" -f [guid]::NewGuid().ToString('N'))
    Set-Content -Path $tmp -Value $Cmds -Encoding ASCII
    try { $out = & diskpart.exe /s $tmp 2>&1 | Out-String } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Log ('diskpart: ' + ($Cmds -join ' > '))
    return $out
}

# ---- mount engine: diskpart OR Storage cmdlets (same 4 operations either way) ----
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
            [pscustomobject]@{ Num = [int]$d.Number; Text = ("Disk {0}  -  {1}  -  {2}  -  {3}" -f $d.Number, $d.FriendlyName, (Fmt-Size $d.Size), $d.PartitionStyle) }
        }
    } else {
        foreach ($ln in (Get-DiskpartRows (Invoke-Diskpart 'list disk'))) {
            if ($ln -match '^\s*\*?\s*\S+\s+(\d+)\s+(.*\S)\s*$') {
                [pscustomobject]@{ Num = [int]$Matches[1]; Text = ("Disk {0}  -  {1}" -f $Matches[1], ($Matches[2] -replace '\s{2,}', '  ')) }
            }
        }
    }
}
function Get-PartList($disk) {
    if ($rbStor.Checked) {
        foreach ($p in (Get-Partition -DiskNumber $disk | Sort-Object PartitionNumber)) {
            $l = ''; if ([int][char]$p.DriveLetter -gt 0) { $l = "  [$($p.DriveLetter):]" }
            [pscustomobject]@{ Num = [int]$p.PartitionNumber; Text = ("Partition {0}  -  {1}  -  {2}{3}" -f $p.PartitionNumber, $p.Type, (Fmt-Size $p.Size), $l) }
        }
    } else {
        foreach ($ln in (Get-DiskpartRows (Invoke-Diskpart @("select disk $disk", 'list partition')))) {
            if ($ln -match '^\s*\*?\s*\S+\s+(\d+)\s+(.*\S)\s*$') {
                [pscustomobject]@{ Num = [int]$Matches[1]; Text = ("Partition {0}  -  {1}" -f $Matches[1], ($Matches[2] -replace '\s{2,}', '  ')) }
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
        Add-PartitionAccessPath -DiskNumber $disk -PartitionNumber $part -AccessPath ("{0}:" -f $L) -ErrorAction Stop
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
    foreach ($m in $script:Mounts) { [void]$lstMounts.Items.Add(("{0}:   (Disk {1}, Partition {2})" -f $m.Letter, $m.Disk, $m.Partition)) }
}
function Update-Letters {
    $cmbLetter.Items.Clear()
    $used = @([IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) })
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

# ---- Windows installations / BCD ----
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
        $dir = Join-Path $StateDir 'BCD-Backups'
        [void][IO.Directory]::CreateDirectory($dir)
        $f = Join-Path $dir ("BCD_{0}.bak" -f (Get-Date -Format yyyyMMdd_HHmmss))
        if ($t.Store) {
            # offline store (WinPE / another drive): "bcdedit /store X /export Y" is not supported, so copy the file
            [IO.File]::Copy($t.Store, $f, $true); [IO.File]::SetAttributes($f, 'Normal'); $o = ''; $ok = [IO.File]::Exists($f)
        } else {
            $o = (& bcdedit.exe /export $f 2>&1) | Out-String; $ok = ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($f))
        }
        if ($ok) {
            Log "BCD backup saved: $f"
            if ($IsWinPE -and $dir.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) { Log 'NOTE: that is the WinPE RAM disk - copy the backup somewhere permanent before rebooting.' }
            return $true
        }
        Log "BCD backup FAILED: $($o.Trim())"
    } catch { Log "BCD backup error: $($_.Exception.Message)" }
    return $false
}
# every BCD-changing command is preceded by an automatic backup - and is NOT run if that backup fails
# A failed bcdedit /import can close the running system's BCD store until a restart: Invoke-Bcd detects and blocks.
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
            return [pscustomobject]@{ Rc = 1; Out = 'The BCD backup failed, so the change was NOT made. See the log.' }
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
        if ($r.Rc -ne 0) { Msg 'Could not set the boot menu timeout. See the log.' 'Error' 'Error' }
    }
}
function Update-Windows([bool]$Popup = $false) {
    $prev = ''
    if ($cmbWin.SelectedItem) { $prev = $cmbWin.SelectedItem.Drive }
    $cmbWin.Items.Clear()
    $found = @(Get-WinInstalls)
    foreach ($w in $found) { [void]$cmbWin.Items.Add($w) }
    if ($found.Count -eq 0) {
        $lblWarn.ForeColor = 'DarkOrange'
        $lblWarn.Text = 'No Windows installation found. Mount its partition on tab 1, then press Rescan.'
    } elseif ($found.Count -gt 1) {
        $lblWarn.ForeColor = 'Red'
        $lblWarn.Text = "WARNING: $($found.Count) Windows installations found. Select the one to work on - nothing is pre-selected."
        for ($i = 0; $i -lt $found.Count; $i++) { if ($prev -and $found[$i].Drive -eq $prev) { $cmbWin.SelectedIndex = $i } }
        if ($Popup) { Msg "$($found.Count) Windows installations were detected.${NL}${NL}Choose the one you want to modify on the Safe Mode tab before changing anything." 'Multiple Windows installations' 'Warning' }
    } else {
        $lblWarn.ForeColor = 'DarkGreen'
        $lblWarn.Text = 'One Windows installation found (selected).'
        $cmbWin.SelectedIndex = 0
    }
    Update-SafeStatus
}
function Update-SafeLabels {
    if ($rbClone.Checked) { $btnSafeOn.Text = 'Create Safe Mode clone'; $btnSafeOff.Text = 'Delete Safe Mode clone(s)' }
    else { $btnSafeOn.Text = 'Enable Safe Mode (minimal)'; $btnSafeOff.Text = 'Remove Safe Mode flag' }
}
function Update-SafeStatus {
    $btnSafeOn.Enabled = $false; $btnSafeOff.Enabled = $false
    $w = $cmbWin.SelectedItem
    if (-not $w) { $lblBcd.Text = 'Select a Windows installation.'; return }
    $t = Resolve-BcdTarget $w.Drive
    if (-not $t) { $lblBcd.Text = "No boot entry for $($w.Drive) found in any BCD store. Mount the EFI/System partition (tab 1), then Rescan."; return }
    $where = if ($t.Store) { $t.Store } else { 'running system' }
    $sb = if ($t.Safeboot) { "SAFE MODE ($($t.Safeboot))" } else { 'normal boot' }
    $n = @(Get-Clones $t $w.Drive).Count
    $cl = if ($n) { "present ($n)" } else { 'none' }
    $lblBcd.Text = "Boot entry $($t.Id) in $where$NL Entry state: $sb     |     Safe Mode clone: $cl"
    $btnSafeOn.Enabled = $true; $btnSafeOff.Enabled = $true
}
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
function Read-Text($prompt, $title = 'Input') {
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = $title; $f.Size = New-Object Drawing.Size(400, 150); $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    [void](New-Ctl 'Label' $f 10 10 365 20 $prompt)
    $t = New-Ctl 'TextBox' $f 10 35 365 24
    $ok = New-Ctl 'Button' $f 205 70 80 28 'OK'; $ca = New-Ctl 'Button' $f 295 70 80 28 'Cancel'
    $ok.DialogResult = 'OK'; $ca.DialogResult = 'Cancel'; $f.AcceptButton = $ok; $f.CancelButton = $ca
    if ($f.ShowDialog() -eq 'OK') { return $t.Text.Trim() }
    return $null
}

# ================= report window =================
function Show-Report($title, $text, [bool]$Ask = $false) {
    $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = $title; $f.Size = New-Object Drawing.Size(660, 500); $f.StartPosition = 'CenterParent'
    $t = New-Ctl 'TextBox' $f 10 10 625 400
    $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Vertical'; $t.Font = New-Object Drawing.Font('Consolas', 9)
    $t.Text = $text; $t.Anchor = 'Top,Bottom,Left,Right'
    if ($Ask) {
        $ok = New-Ctl 'Button' $f 400 420 125 30 'Continue anyway'; $ca = New-Ctl 'Button' $f 535 420 100 30 'Cancel'
        $ok.DialogResult = 'Yes'; $ca.DialogResult = 'Cancel'; $f.CancelButton = $ca
        $ok.Anchor = 'Bottom,Right'; $ca.Anchor = 'Bottom,Right'
    } else {
        $cl = New-Ctl 'Button' $f 535 420 100 30 'Close'; $cl.DialogResult = 'OK'; $f.CancelButton = $cl; $cl.Anchor = 'Bottom,Right'
    }
    $t.Select(0, 0)
    return ($f.ShowDialog() -eq 'Yes')
}

# ================= sysprep pre-flight checks (run on the live Windows) =================
function Get-Preflight([string]$Mode) {
    $r = New-Object Collections.ArrayList
    $add = { param($l, $t) [void]$r.Add([pscustomobject]@{ Level = $l; Text = $t }) }
    $gen = ($Mode -eq 'A')
    [Windows.Forms.Cursor]::Current = [Windows.Forms.Cursors]::WaitCursor
    try {
        $sp = Join-Path $env:windir 'System32\Sysprep\sysprep.exe'
        if (Test-Path $sp) { & $add 'OK' 'sysprep.exe found.' } else { & $add 'FAIL' 'sysprep.exe not found.' }
        if (Get-Process sysprep -ErrorAction SilentlyContinue) { & $add 'FAIL' 'Sysprep is already running.' }

        $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        if ($pend) { & $add 'WARN' 'A reboot is pending (updates / servicing). Reboot first, then run sysprep.' } else { & $add 'OK' 'No pending reboot.' }

        try {
            $free = (New-Object IO.DriveInfo $env:SystemDrive).AvailableFreeSpace
            if ($free -lt 10GB) { & $add 'WARN' ("Only {0} free on {1}. Sysprep and image capture want roughly 10 GB or more." -f (Fmt-Size $free), $env:SystemDrive) }
            else { & $add 'OK' ("{0} free on {1}." -f (Fmt-Size $free), $env:SystemDrive) }
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

            $files = @("$env:windir\Panther\unattend.xml", "$env:windir\Panther\Unattend\unattend.xml", "$env:windir\System32\Sysprep\unattend.xml", "$env:SystemDrive\unattend.xml", "$env:SystemDrive\autounattend.xml") | Where-Object { [IO.File]::Exists($_) }
            if (@($files).Count) { & $add 'WARN' ('Existing answer file(s) found; they can conflict with the one you pass: ' + (@($files) -join '; ')) }
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
                    & $add 'WARN' ("Possible Store apps installed for a user but not provisioned for all users (the classic generalize failure): $shown. Remove them with Remove-AppxPackage -AllUsers if sysprep fails.")
                } else { & $add 'OK' 'No per-user-only Store apps found.' }
            } catch { & $add 'WARN' ("Could not check for Store apps installed for one user only ($($_.Exception.Message)) - the most common reason generalize fails. If it fails, look for 'was installed for a user, but not provisioned for all users' in %windir%\System32\Sysprep\Panther\setupact.log.") }
        }

        $err = "$env:windir\System32\Sysprep\Panther\setuperr.log"
        if ([IO.File]::Exists($err)) {
            $tail = @(Get-Content $err -Tail 6 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
            if ($tail.Count) { & $add 'INFO' ("A previous sysprep error log exists ($err, " + (Get-Item $err).LastWriteTime + "). Last lines: " + ($tail[-1])) }
        }
    } finally { [Windows.Forms.Cursor]::Current = [Windows.Forms.Cursors]::Default }
    return @($r)
}
function Format-Preflight($items) {
    $w = @($items | Where-Object { $_.Level -eq 'WARN' }).Count
    $f = @($items | Where-Object { $_.Level -eq 'FAIL' }).Count
    $head = "Pre-flight result: $f blocking problem(s), $w warning(s).$NL" + ('-' * 60) + $NL
    return $head + (($items | ForEach-Object { "[{0,-4}] {1}" -f $_.Level, $_.Text }) -join ($NL + $NL))
}

# ================= unattend.xml builder =================
function Build-Unattend {
    $a = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $arch = switch ($a) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'amd64' } }
    $user = $txtUser.Text.Trim(); $pcn = $txtPC.Text.Trim(); $locale = $txtLoc.Text.Trim()
    if (-not ($chkSkip.Checked -or $chkUser.Checked -or $chkPC.Checked -or $chkRegion.Checked)) { Msg 'Tick at least one option on the Unattend tab first.' 'Unattend' 'Warning'; return $null }
    if ($chkSkip.Checked -and -not $chkUser.Checked) { Msg "Skipping the OOBE screens without creating an account leaves no usable account.$NL Tick 'Create local account' as well." 'Unattend' 'Warning'; return $null }
    if ($chkUser.Checked -and ($user.Length -lt 1 -or $user.Length -gt 20 -or $user -match "[\\/\[\]:;|=,+*?<>`"@%'$([char]0x2018)-$([char]0x201B)]")) { Msg 'User name must be 1-20 characters and may not contain \ / [ ] : ; | = , + * ? < > " @ % or apostrophes.' 'Unattend' 'Warning'; return $null }   # % would be expanded by cmd in FirstLogonCommands
    if ($chkUser.Checked -and $chkNoExp.Checked -and [string]$cmbGroup.SelectedItem -ne 'Administrators') { Msg "'Password never expires' runs as the new account at its first logon, and only an administrator may change that setting.$NL Choose the Administrators group or untick 'Password never expires'." 'Unattend' 'Warning'; return $null }
    if ($chkPC.Checked -and $pcn -notmatch '^(\*|[A-Za-z0-9-]{1,15})$') { Msg 'Computer name: 1-15 letters, digits or hyphens, or * for a random name.' 'Unattend' 'Warning'; return $null }
    if ($chkRegion.Checked -and (-not $cmbTz.SelectedItem -or $locale -notmatch '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})+$')) { Msg 'Pick a time zone and enter a locale such as en-US.' 'Unattend' 'Warning'; return $null }

    $esc = { param($s) [Security.SecurityElement]::Escape($s) }
    $ns = 'xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    $comp = { param($n) ('<component name="{0}" processorArchitecture="{1}" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" {2}>' -f $n, $arch, $ns) }
    $sb = New-Object Text.StringBuilder
    $ap = { param($s) [void]$sb.AppendLine($s) }
    $pw = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($txtPass.Text + 'Password'))

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

# ================= experimental boot recovery tools =================
# Exe tools: Exe + Argv (param $c -> argument array, or @{Exe;Args} to use another program; empty = cancel) + Window ($true = own console)
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
        Help = "Exports the BCD store that boots the selected Windows to a timestamped file in the BCD-Backups folder next to this script.${NL}${NL}Use cases:${NL}- Take a safety copy before any boot repair.${NL}- Keep a known-good copy to restore later.${NL}${NL}Every BCD change made by this tool already makes an automatic backup first."
        Build = { param($c, $tool)
            $t = Resolve-BcdTarget $c.Win
            if (-not $t) { Msg 'No boot entry found for that install. Mount the EFI partition first.' 'Recovery' 'Warning'; return $null }
            return @{ Summary = $(if ($t.Store) { 'copy the offline BCD file to a timestamped backup' } else { 'bcdedit /export <timestamped file>' }); Run = { param($a) if (-not (Backup-Bcd $a)) { Msg 'The BCD backup failed. See the log.' 'Error' 'Error' } }; RunArg = $t } } },
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
        Help = "bcdboot <Windows>\Windows /s <boot partition> /f UEFI|BIOS${NL}${NL}Copies fresh boot files from the selected Windows onto the chosen boot partition and creates a new BCD entry. Firmware type (/f) comes from how THIS PC boots (UEFI or BIOS); you are warned if the chosen partition does not match.${NL}${NL}Use cases:${NL}- 'BOOTMGR is missing' or 'winload.efi not found'.${NL}- Empty or recreated EFI partition.${NL}- Boot files damaged or wiped."
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
        Help = "Offline install: sfc /scannow /offbootdir=D:\ /offwindir=D:\Windows${NL}Running Windows: sfc /scannow${NL}${NL}Verifies and repairs protected system files of the selected Windows.${NL}${NL}Use cases: Windows will not boot because of corrupt system files; after malware or a failed update."
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
        Help = "chkdsk D: /scan${NL}${NL}Scans the file system of the selected Windows volume without fixing anything.${NL}${NL}Use case: see whether file-system errors explain a boot failure."
        Argv = { param($c) @($c.Win, '/scan') } },
    [pscustomobject]@{ Name = 'Check disk and REPAIR (chkdsk /f)'; Needs = 'install'; Exe = 'chkdsk.exe'; Window = $true
        Help = "chkdsk D: /f${NL}${NL}Fixes file-system errors on the selected Windows volume. This WRITES to the disk. On the running system drive it asks to schedule the check for the next restart.${NL}${NL}Use case: the read-only scan reported errors. Back up important data first if possible."
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

# ================= GUI =================
$form = New-Object Windows.Forms.Form; Set-WrtScaling $form
$form.Text = 'Windows Repair Toolkit'; $form.ClientSize = New-Object Drawing.Size(690, 630)
$form.StartPosition = 'CenterScreen'   # (the tab pages scroll instead of the whole window since 1.8.1)
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$tip = New-Object Windows.Forms.ToolTip; $tip.AutoPopDelay = 30000; $tip.InitialDelay = 200

function New-Ctl($type, $parent, $x, $y, $w, $h, $text = '') {
    $c = New-Object "Windows.Forms.$type"
    $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, $h)
    if ($text) { $c.Text = $text }
    if ($type -in 'Label', 'CheckBox', 'RadioButton') { $c.AutoSize = $false }
    if ($type -eq 'ComboBox') { $c.DropDownStyle = 'DropDownList' }
    $parent.Controls.Add($c)
    return $c
}
function Add-Help($parent, $x, $y, $title, $text) {
    $b = New-Ctl 'Button' $parent $x $y 24 24 '?'
    $tip.SetToolTip($b, $text)
    $b.Add_Click({ [void][Windows.Forms.MessageBox]::Show($text, $title, 'OK', 'Information') }.GetNewClosure())
}
$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(10, 8); $tabs.Size = New-Object Drawing.Size(670, 470)
$form.Controls.Add($tabs)
function New-Page($text) { $p = New-Object Windows.Forms.TabPage; $p.Text = $text; $p.UseVisualStyleBackColor = $true; [void]$tabs.TabPages.Add($p); return $p }
$g1 = New-Page '1. Mount'; $g2 = New-Page '2. Safe Mode'; $g3 = New-Page '3. Sysprep'; $gU = New-Page '4. Unattend'; $g4 = New-Page '5. Recovery (experimental)'
# create the tab control now (1.8.2): until it exists every tab page is a 200 x 100 placeholder, and controls anchored to the bottom or right of a page would be measured against that and end up in the wrong place
[void]$tabs.Handle      # (reading .Handle creates it; CreateControl() does nothing while the window is not shown yet)

# ---------- 1. Mount ----------
[void](New-Ctl 'Label' $g1 12 15 60 20 'Engine')
$rbDp = New-Ctl 'RadioButton' $g1 75 12 110 22 'diskpart'; $rbDp.Checked = $true
$rbStor = New-Ctl 'RadioButton' $g1 190 12 170 22 'Storage cmdlets'
Add-Help $g1 370 11 'Mount engine' ("diskpart: the classic tool; works everywhere including WinPE. Output is parsed as text, so it can misbehave on non-English systems.$NL$NL Storage cmdlets: Get-Disk / Get-Partition / Add-PartitionAccessPath. Cleaner, language independent, and available on Windows 11 and most WinPE builds that include the Storage module.$NL$NL Both do the same thing: list disks and partitions, add or remove a drive letter. Nothing is formatted, cleaned or deleted.")
[void](New-Ctl 'Label' $g1 12 50 60 20 'Disk')
$cmbDisk = New-Ctl 'ComboBox' $g1 75 47 470 24; $cmbDisk.DisplayMember = 'Text'
$btnRefresh = New-Ctl 'Button' $g1 555 46 95 26 'Refresh'
[void](New-Ctl 'Label' $g1 12 82 60 20 'Partition')
$cmbPart = New-Ctl 'ComboBox' $g1 75 79 470 24; $cmbPart.DisplayMember = 'Text'
[void](New-Ctl 'Label' $g1 12 114 60 20 'Letter')
$cmbLetter = New-Ctl 'ComboBox' $g1 75 111 70 24
$btnMount = New-Ctl 'Button' $g1 155 109 150 28 'Mount'
Add-Help $g1 315 111 'Mount a partition' ("Gives any partition a temporary drive letter (diskpart: list disk > select disk > list partition > select partition > assign letter).$NL$NL Use cases:$NL- Mount the hidden EFI System Partition to edit or repair the bootloader (BCD).$NL- Reach an offline Windows install to copy data, inject/remove drivers or edit registry hives.$NL- Access Recovery / OEM partitions.$NL$NL Safety: only list, select, detail, assign letter and remove letter are ever sent to diskpart, and the Storage mode only adds/removes access paths. Only letters this tool assigned are removed.")
[void](New-Ctl 'Label' $g1 12 150 330 18 'Mounted by this tool (remembered between runs):')
$lstMounts = New-Ctl 'ListBox' $g1 12 170 535 100
$btnUnmount = New-Ctl 'Button' $g1 555 170 95 28 'Unmount'
$btnUnmountAll = New-Ctl 'Button' $g1 555 204 95 28 'Unmount all'
$chkAuto = New-Ctl 'CheckBox' $g1 12 278 330 20 'Unmount everything when this tool closes'
$chkAuto.Checked = $true

# ---------- 2. Safe mode ----------
[void](New-Ctl 'Label' $g2 12 15 70 20 'Apply to')
$rbEdit = New-Ctl 'RadioButton' $g2 90 12 380 22 'Edit the selected boot entry directly'; $rbEdit.Checked = $true
$rbClone = New-Ctl 'RadioButton' $g2 90 36 380 22 'Clone the entry -> separate "Safe Mode" item in the boot menu'
Add-Help $g2 480 24 'Edit vs. clone' ("Edit directly: sets safeboot on the existing entry (bcdedit /set {current} safeboot minimal). The PC boots into Safe Mode on EVERY start until you remove the flag.$NL$NL Clone: copies the entry (bcdedit /copy), names the copy 'Safe Mode (minimal) [WinRepairTool]' and sets safeboot only on the copy. Your normal entry stays untouched; pick Safe Mode from the boot menu when you want it. Removing deletes only clones this tool created.$NL$NL Every BCD change is preceded by an automatic backup.")
[void](New-Ctl 'Label' $g2 12 74 120 20 'Windows install')
$cmbWin = New-Ctl 'ComboBox' $g2 135 71 410 24; $cmbWin.DisplayMember = 'Text'
$btnRescan = New-Ctl 'Button' $g2 555 70 95 26 'Rescan'
$lblWarn = New-Ctl 'Label' $g2 12 104 640 20; $lblWarn.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$lblBcd = New-Ctl 'Label' $g2 12 128 640 44
$btnSafeOn = New-Ctl 'Button' $g2 12 184 230 30 'Enable Safe Mode (minimal)'
Add-Help $g2 248 187 'Enable Safe Mode' ("bcdedit /set {current} safeboot minimal$NL$NL Use cases:$NL- Remove or replace NVMe / RAID / Intel RST-VMD storage drivers.$NL- Switch the SATA controller mode (RAID <-> AHCI) without an INACCESSIBLE_BOOT_DEVICE blue screen.$NL- Uninstall a driver or program that crashes a normal boot.$NL$NL For an offline install the tool targets that install's own entry in its BCD store (bcdedit /store ... /set {guid} ...). In clone mode the boot menu shows the new entry; Windows usually waits about 30 seconds there.")
$btnSafeOff = New-Ctl 'Button' $g2 300 184 230 30 'Remove Safe Mode flag'
Add-Help $g2 536 187 'Remove Safe Mode' ("Edit mode: bcdedit /deletevalue {current} safeboot - returns the selected Windows to a normal boot.$NL$NL Clone mode: deletes only the clone entries created by this tool (matched by their exact name).")

# ---------- 3. Sysprep ----------
$rbA = New-Ctl 'RadioButton' $g3 12 15 590 22 'A.  Generalize:  sysprep /generalize /oobe /shutdown'
Add-Help $g3 612 14 'A - Generalize' ("%windir%\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown$NL$NL Strips machine-specific data (SID, hardware IDs) and shuts down. Next boot starts OOBE.$NL$NL Use cases:$NL- Capture a master image to deploy to many PCs.$NL- Create a template for virtual machines.$NL- Move / translate an installation to different hardware.")
$chkVM = New-Ctl 'CheckBox' $g3 34 40 570 22 'Add /mode:vm  (VM deployment on the SAME hypervisor / virtual hardware)'
$chkVM.Enabled = $false
Add-Help $g3 612 39 'VM mode' ("Appends /mode:vm to option A.$NL$NL Skips hardware re-detection on first boot, so a generalized VHD/VM image starts much faster.$NL$NL Only valid with /generalize /oobe /shutdown, and only when the image is deployed to identical virtual hardware (same hypervisor, same VM configuration). For physical PCs or a different hypervisor leave it OFF.")
$rbB1 = New-Ctl 'RadioButton' $g3 12 74 590 22 'B1. Two-step, step 1 - Audit mode:  sysprep /audit /reboot'
Add-Help $g3 612 73 'B1 - Audit mode' ("%windir%\System32\Sysprep\sysprep.exe /audit /reboot$NL$NL Reboots into Audit mode (built-in Administrator, no OOBE) so you can customize before deployment.$NL$NL Use cases:$NL- Install drivers, updates and software.$NL- Prepare an image for another PC.$NL- Remove or inject storage (NVMe / RAID) drivers before the move.")
$rbB2 = New-Ctl 'RadioButton' $g3 12 104 590 22 'B2. Two-step, step 2 - Deploy (OOBE):  sysprep /oobe /reboot'
Add-Help $g3 612 103 'B2 - Deploy (OOBE)' ("%windir%\System32\Sysprep\sysprep.exe /oobe /reboot$NL$NL Run this from Audit mode when customizing is finished. Reboots into the first-run experience (OOBE) where the end user creates their account.$NL$NL Use cases: finish a prepared install for a VM, a new PC, or the PC it was moved to.")
$chkUnatt = New-Ctl 'CheckBox' $g3 12 138 590 22 'Pass the answer file built on tab 4 to sysprep (/unattend:)'
Add-Help $g3 612 137 'Answer file' ("Builds the unattend.xml from the Unattend tab when you press Run and adds /unattend:<file> to the command (works with A, B1 and B2).$NL$NL Sysprep caches the answer file, so settings like 'skip OOBE screens', the local account, computer name and time zone are applied during the next specialize / OOBE pass.$NL$NL The file lives in your TEMP folder and holds the account password in a recoverable form - delete it afterwards.")
$lblDep = New-Ctl 'Label' $g3 12 170 640 50 'Only ONE option can be selected. Sysprep acts on the Windows you are running right now. Two-step mode: run B1 first, customize in Audit mode, then run B2. The commands are fixed and cannot be edited.'
$btnRun = New-Ctl 'Button' $g3 12 230 240 30 'Run selected command...'
$btnPre = New-Ctl 'Button' $g3 262 230 200 30 'Run pre-flight checks'
$chkAutoPre = New-Ctl 'CheckBox' $g3 12 268 500 22 'Also run the pre-flight checks automatically before each run'
Add-Help $g3 468 233 'Pre-flight checks' ("Checks the running Windows for the usual reasons sysprep fails or does damage:$NL- pending reboot, free disk space$NL- in-place upgrade (unsupported for generalize)$NL- domain join$NL- BitLocker / device encryption (generalize fails while encrypted)$NL- leftover unattend.xml files that conflict$NL- Store apps installed for one user but not provisioned (the classic generalize failure)$NL- last sysprep error log (Sysprep\Panther\setuperr.log)$NL$NL Run it on demand with the button, or tick the checkbox below it to also run it before every sysprep run (off by default). Findings can be overridden with 'Continue anyway'.")
if ($IsWinPE) {
    foreach ($c in $rbA, $rbB1, $rbB2, $btnRun, $btnPre, $chkUnatt, $chkAutoPre) { $c.Enabled = $false }
    $lblDep.Text = 'Disabled in WinPE: Sysprep only works from inside the installed Windows.'
}

# ---------- 4. Unattend ----------
[void](New-Ctl 'Label' $gU 12 8 630 34 'Builds an answer file (unattend.xml). Tick only what you want; unticked options are left out of the file.')
$chkSkip = New-Ctl 'CheckBox' $gU 12 46 590 22 'Skip OOBE screens (EULA, online account, Wi-Fi, privacy, OEM registration)'; $chkSkip.Checked = $true
Add-Help $gU 612 45 'Skip OOBE screens' ("Hides the first-run screens (HideEULAPage, HideOnlineAccountScreens, HideLocalAccountScreen, HideWirelessSetupInOOBE, HideOEMRegistrationScreen, ProtectYourPC=3).$NL$NL This is the 'skip user creation' switch: nobody is asked to create an account. Because that leaves no way to sign in, it requires 'Create local account' below.$NL$NL Use cases: unattended VM and PC deployment, lab machines, hands-off image rollouts.")
$chkUser = New-Ctl 'CheckBox' $gU 12 76 300 22 'Create local account'; $chkUser.Checked = $true
Add-Help $gU 612 75 'Local account' ("Creates a local account during OOBE (LocalAccounts in the oobeSystem pass).$NL$NL The password is stored base64-encoded, which is obfuscation, not encryption: anyone who can read the file can recover it. Delete the file after use.$NL$NL Password never expires adds a first-logon command (Set-LocalUser -PasswordNeverExpires).")
[void](New-Ctl 'Label' $gU 36 106 50 20 'Name')
$txtUser = New-Ctl 'TextBox' $gU 90 103 160 24; $txtUser.Text = 'User'
[void](New-Ctl 'Label' $gU 262 106 65 20 'Password')
$txtPass = New-Ctl 'TextBox' $gU 330 103 150 24; $txtPass.UseSystemPasswordChar = $true
$chkShowPw = New-Ctl 'CheckBox' $gU 488 104 100 22 'Show'
[void](New-Ctl 'Label' $gU 36 136 50 20 'Group')
$cmbGroup = New-Ctl 'ComboBox' $gU 90 133 160 24
[void]$cmbGroup.Items.Add('Administrators'); [void]$cmbGroup.Items.Add('Users'); $cmbGroup.SelectedIndex = 0
$chkNoExp = New-Ctl 'CheckBox' $gU 262 134 330 22 'Password never expires'
$chkLogon = New-Ctl 'CheckBox' $gU 36 164 560 22 'Auto-logon once after setup (uses the account above)'
$chkPC = New-Ctl 'CheckBox' $gU 12 196 200 22 'Set computer name'
$txtPC = New-Ctl 'TextBox' $gU 215 193 150 24; $txtPC.Text = '*'
[void](New-Ctl 'Label' $gU 372 197 270 20 '*  =  random name')
$chkRegion = New-Ctl 'CheckBox' $gU 12 226 330 22 'Set time zone and language'
[void](New-Ctl 'Label' $gU 36 256 70 20 'Time zone')
$cmbTz = New-Ctl 'ComboBox' $gU 110 253 300 24
[void](New-Ctl 'Label' $gU 420 256 50 20 'Locale')
$txtLoc = New-Ctl 'TextBox' $gU 475 253 80 24
$btnUPrev = New-Ctl 'Button' $gU 12 296 110 30 'Preview XML'
$btnUSave = New-Ctl 'Button' $gU 130 296 130 30 'Save as...'
$btnUDeploy = New-Ctl 'Button' $gU 268 296 230 30 'Deploy to selected Windows'
Add-Help $gU 504 299 'Deploy answer file' ("Writes the file to <selected Windows>\Windows\Panther\Unattend\unattend.xml (an existing file is backed up first). Windows Setup looks there during the specialize and OOBE passes.$NL$NL It only has an effect on an install that is about to go through specialize / OOBE (after sysprep /generalize, or on a fresh image). On an install that already finished OOBE it does nothing until it is sysprepped.$NL$NL Alternative: tick 'Pass the answer file to sysprep' on the Sysprep tab instead.")
[void](New-Ctl 'Label' $gU 12 338 635 60 'Passwords in an answer file are only obfuscated (base64), not encrypted. Delete the file after use. The file is built for this PC architecture; the target install must match.')

# ---------- 5. Experimental recovery ----------
$lblExp = New-Ctl 'Label' $g4 12 10 640 36 'EXPERIMENTAL: these tools are untested on your hardware and can change boot configuration or disk contents. Back up first (BCD backup tool below).'
$lblExp.ForeColor = 'Red'; $lblExp.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
[void](New-Ctl 'Label' $g4 12 56 100 20 'Boot partition')
$cmbEsp = New-Ctl 'ComboBox' $g4 115 53 430 24; $cmbEsp.DisplayMember = 'Text'
$btnEspRefresh = New-Ctl 'Button' $g4 555 52 95 26 'Refresh'
[void](New-Ctl 'Label' $g4 12 90 100 20 'Tool')
$cmbTool = New-Ctl 'ComboBox' $g4 115 87 430 24; $cmbTool.DisplayMember = 'Name'
foreach ($t in $Tools) { [void]$cmbTool.Items.Add($t) }
$btnToolHelp = New-Ctl 'Button' $g4 551 86 24 24 '?'
$lblToolDesc = New-Ctl 'Label' $g4 12 124 640 60
$lblToolNote = New-Ctl 'Label' $g4 12 190 640 36 'Tools use the Windows install selected on the Safe Mode tab and (where needed) the boot partition above. Long jobs open their own console window.'
$btnTool = New-Ctl 'Button' $g4 12 236 240 30 'Run selected tool...'

# ---------- log ----------
$txtLog = New-Ctl 'TextBox' $form 10 488 670 132
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.Font = New-Object Drawing.Font('Consolas', 8.5)

# ================= events =================
$cmbDisk.Add_SelectedIndexChanged({ Safe { Update-Parts } })
$rbStor.Add_CheckedChanged({ Safe { Update-Disks } })
$btnRefresh.Add_Click({ Safe { Update-Disks; Update-Letters; Update-Windows; Update-Esp } })
$btnRescan.Add_Click({ Safe { Update-Windows $true } })
$cmbWin.Add_SelectedIndexChanged({ Safe { Update-SafeStatus } })
$rbClone.Add_CheckedChanged({ Safe { Update-SafeLabels; Update-SafeStatus } })
$rbA.Add_CheckedChanged({ $chkVM.Enabled = $rbA.Checked; if (-not $rbA.Checked) { $chkVM.Checked = $false } })
$btnEspRefresh.Add_Click({ Safe { Update-Esp } })
$cmbTool.Add_SelectedIndexChanged({
    $t = $cmbTool.SelectedItem
    if ($t) { $lblToolDesc.Text = ($t.Help -split "`r?`n")[0]; $tip.SetToolTip($btnToolHelp, $t.Help) }
})
$btnToolHelp.Add_Click({ $t = $cmbTool.SelectedItem; if ($t) { Msg $t.Help $t.Name 'Information' } })

$chkUser.Add_CheckedChanged({ Update-UnattendUi })
$chkPC.Add_CheckedChanged({ Update-UnattendUi })
$chkRegion.Add_CheckedChanged({ Update-UnattendUi })
$chkShowPw.Add_CheckedChanged({ $txtPass.UseSystemPasswordChar = -not $chkShowPw.Checked })
$btnPre.Add_Click({ Safe {
    $mode = if ($rbB1.Checked) { 'B1' } elseif ($rbB2.Checked) { 'B2' } else { 'A' }
    [void](Show-Report "Sysprep pre-flight checks (mode $mode)" (Format-Preflight @(Get-Preflight $mode)))
} })
$btnUPrev.Add_Click({ Safe {
    $x = Build-Unattend
    if ($x) { [void](Show-Report 'unattend.xml preview (password is only base64-obfuscated)' $x) }
} })
$btnUSave.Add_Click({ Safe {
    $x = Build-Unattend; if (-not $x) { return }
    $d = New-Object Windows.Forms.SaveFileDialog
    $d.FileName = 'unattend.xml'; $d.Filter = 'XML file (*.xml)|*.xml'; $d.InitialDirectory = $StateDir
    if ($d.ShowDialog() -eq 'OK') { Write-Xml $d.FileName $x; Log "Answer file saved: $($d.FileName)" }
} })
$btnUDeploy.Add_Click({ Safe {
    $w = $cmbWin.SelectedItem
    if (-not $w) { Msg 'Select a Windows installation on the Safe Mode tab first.'; return }
    $x = Build-Unattend; if (-not $x) { return }
    $dest = "$($w.Drive)\Windows\Panther\Unattend\unattend.xml"
    $q = "Write the answer file to:$NL$dest$NL$NL for $($w.Text)$NL$NL An existing file is backed up first. Continue?"
    if ([Windows.Forms.MessageBox]::Show($q, 'Deploy answer file', 'YesNo', 'Question') -ne 'Yes') { return }
    # -ErrorAction Stop: if the existing answer file cannot be backed up, do NOT overwrite it (Safe shows the error)
    if ([IO.File]::Exists($dest)) { Copy-Item -LiteralPath $dest -Destination ('{0}.bak_{1}' -f $dest, (Get-Date -Format yyyyMMdd_HHmmss)) -ErrorAction Stop }
    Write-Xml $dest $x
    Log "Answer file deployed: $dest"
    Msg "Deployed to $dest"
} })
$btnMount.Add_Click({ Safe {
    $d = $cmbDisk.SelectedItem; $p = $cmbPart.SelectedItem; $L = [string]$cmbLetter.SelectedItem
    if (-not $d -or -not $p -or -not $L) { Msg 'Select a disk, a partition and a free letter first.'; return }
    $cur = Get-PartLetter $d.Num $p.Num
    if ($cur -eq 'NOVOLUME') { Msg 'This partition has no mountable volume (e.g. MSR / reserved).' 'Cannot mount' 'Warning'; return }
    if ($cur) { Msg "This partition is already mounted as ${cur}:." 'Already mounted' 'Information'; return }
    if (Test-LetterUsed $L) { Update-Letters; Msg "Letter ${L}: was just taken. Pick another." 'Letter in use' 'Warning'; return }
    if (Mount-Part $d.Num $p.Num $L) {
        [void]$script:Mounts.Add([pscustomobject]@{ Letter = $L; Disk = $d.Num; Partition = $p.Num })
        Save-Mounts; Update-MountList; Update-Letters; Update-Esp; Log "Mounted as ${L}:"; Update-Windows
    } else { Msg 'Mount failed. See the log below.' 'Mount failed' 'Error' }
} })
$btnUnmount.Add_Click({ Safe {
    $i = $lstMounts.SelectedIndex
    if ($i -lt 0) { Msg 'Select a mounted entry in the list first.'; return }
    [void](Dismount-One $script:Mounts[$i])
    Save-Mounts; Update-MountList; Update-Letters; Update-Esp; Update-Windows
} })
$btnUnmountAll.Add_Click({ Safe {
    foreach ($m in @($script:Mounts)) { [void](Dismount-One $m) }
    Save-Mounts; Update-MountList; Update-Letters; Update-Esp; Update-Windows
} })

$btnSafeOn.Add_Click({ Safe {
    $w = $cmbWin.SelectedItem; if (-not $w) { return }
    $t = Resolve-BcdTarget $w.Drive; if (-not $t) { Update-SafeStatus; return }
    if ($rbClone.Checked) {
        if (@(Get-Clones $t $w.Drive).Count) { Msg 'A Safe Mode clone for this install already exists.'; return }
        $q = "Create a separate boot-menu entry 'Safe Mode (minimal)' for:$NL$NL$($w.Text)$NL$NL Your normal entry is not changed."
        if ([Windows.Forms.MessageBox]::Show($q, 'Confirm', 'YesNo', 'Question') -ne 'Yes') { return }
        $r = Invoke-Bcd $t @('/copy', $t.Id, '/d', $CloneMarker)
        $ok = $r.Out -match '(\{[0-9a-fA-F-]{36}\})'
        if ($r.Rc -ne 0 -or -not $ok) { Msg 'Could not copy the boot entry. See the log.' 'Error' 'Error'; return }
        $new = $Matches[1]
        $r2 = Invoke-Bcd $t @('/set', $new, 'safeboot', 'minimal')
        if ($r2.Rc -ne 0) { [void](Invoke-Bcd $t @('/delete', $new)); Msg 'Could not set safeboot on the copy; the copy was removed. See the log.' 'Error' 'Error' }
        else { Confirm-BootMenuShown $t; Msg "Done. Choose 'Safe Mode (minimal)' in the boot menu on next start." }
    } else {
        $q = "Enable Safe Mode (minimal) for:$NL$NL$($w.Text)$NL$NL It will boot into Safe Mode on every start until you remove the flag."
        if ([Windows.Forms.MessageBox]::Show($q, 'Confirm', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { return }
        $r = Invoke-Bcd $t @('/set', $t.Id, 'safeboot', 'minimal')
        if ($r.Rc -ne 0) { Msg 'bcdedit reported an error. See the log.' 'Error' 'Error' }
    }
    Update-SafeStatus
} })
$btnSafeOff.Add_Click({ Safe {
    $w = $cmbWin.SelectedItem; if (-not $w) { return }
    $t = Resolve-BcdTarget $w.Drive; if (-not $t) { Update-SafeStatus; return }
    if ($rbClone.Checked) {
        $cl = @(Get-Clones $t $w.Drive)
        if ($cl.Count -eq 0) { Msg 'No Safe Mode clone created by this tool was found for this install.'; return }
        if ([Windows.Forms.MessageBox]::Show("Delete $($cl.Count) Safe Mode clone entry(ies) for:$NL$NL$($w.Text)", 'Confirm', 'YesNo', 'Question') -ne 'Yes') { return }
        $bad = @($cl | Where-Object { (Invoke-Bcd $t @('/delete', $_.Id)).Rc -ne 0 })
        if ($bad.Count) { Msg "$($bad.Count) clone(s) could not be deleted. See the log." 'Error' 'Error' }
    } else {
        if ([Windows.Forms.MessageBox]::Show("Remove the Safe Mode flag for:$NL$NL$($w.Text)", 'Confirm', 'YesNo', 'Question') -ne 'Yes') { return }
        $r = Invoke-Bcd $t @('/deletevalue', $t.Id, 'safeboot')
        if ($r.Rc -ne 0) { Msg 'bcdedit reported an error (the flag may not be set). See the log.' 'Notice' 'Warning' }
    }
    Update-SafeStatus
} })

$btnRun.Add_Click({ Safe {
    if ($rbA.Checked) {
        $arg = '/generalize /oobe /shutdown'
        $warn = "GENERALIZE removes the machine identity (SID, hardware-specific data) from THIS Windows and SHUTS DOWN.$NL The next boot starts OOBE.$NL$NL - Back up / snapshot first.$NL - Do not use on a PC you are not ready to reset (not for domain-joined production PCs).$NL - User-installed Store apps can make generalize fail."
        if ($chkVM.Checked) { $arg += ' /mode:vm'; $warn += "$NL$NL VM MODE: the image must be deployed to identical virtual hardware on the same hypervisor, otherwise it may fail to boot." }
    } elseif ($rbB1.Checked) {
        $arg = '/audit /reboot'
        $warn = "This REBOOTS THIS PC into Audit mode (built-in Administrator, no OOBE).$NL Close all work first. When customizing is done, run B2."
    } elseif ($rbB2.Checked) {
        $arg = '/oobe /reboot'
        $warn = "Run this only from Audit mode when customizing is FINISHED.$NL This REBOOTS into OOBE (first-run setup)."
    } else { Msg 'Select one of the three options first.'; return }
    $sp = Join-Path $env:windir 'System32\Sysprep\sysprep.exe'
    if (-not (Test-Path $sp)) { Msg 'sysprep.exe was not found on this system.' 'Error' 'Error'; return }
    if (Get-Process sysprep -ErrorAction SilentlyContinue) { Msg 'Sysprep is already running.' 'Busy' 'Warning'; return }
    $mode = if ($rbA.Checked) { 'A' } elseif ($rbB1.Checked) { 'B1' } else { 'B2' }
    if ($chkAutoPre.Checked) {
        $pf = @(Get-Preflight $mode)
        if (@($pf | Where-Object { $_.Level -eq 'WARN' -or $_.Level -eq 'FAIL' }).Count) {
            if (-not (Show-Report 'Pre-flight checks - issues found' (Format-Preflight $pf) $true)) { return }
        }
    }
    if ($chkUnatt.Checked) {
        $xml = Build-Unattend; if (-not $xml) { return }
        $uf = Join-Path $env:TEMP 'WinRepairTool_unattend.xml'
        Write-Xml $uf $xml
        $arg += " /unattend:`"$uf`""
        $warn += "$NL$NL ANSWER FILE: $uf is passed with /unattend. It holds the account password in a recoverable form - delete it afterwards."
    }
    $q = "$warn$NL$NL Command:$NL$sp $arg$NL$NL Continue?"
    if ([Windows.Forms.MessageBox]::Show($q, 'WARNING - Sysprep', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { return }
    Log "sysprep $arg"
    Start-Process -FilePath $sp -ArgumentList $arg
} })

$btnTool.Add_Click({ Safe {
    $tool = $cmbTool.SelectedItem; if (-not $tool) { Msg 'Select a tool first.'; return }
    $w = $cmbWin.SelectedItem; $e = $cmbEsp.SelectedItem
    if (($tool.Needs -eq 'install' -or $tool.Needs -eq 'both') -and -not $w) { Msg 'Select a Windows installation on the Safe Mode tab first.' 'Recovery' 'Warning'; return }
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
        elseif (-not (Backup-Bcd $bt) -and -not (Ask "The BCD backup failed (see the log).${NL}${NL}Run $($def.Exe) anyway?" 'Recovery' 'Warning' 'Button2')) { return }
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

$form.Add_FormClosing({
    if ($chkAuto.Checked -and $script:Mounts.Count -gt 0) {
        # a repair console started from the Recovery tab may still be working on a mounted drive
        $live = @($script:Consoles | Where-Object { $_ -and -not $_.HasExited })
        $unmount = $true
        if ($live.Count) { $unmount = Ask ("$($live.Count) repair console window(s) started by this tool are still running and may be using a mounted drive.${NL}${NL}Unmount the drives anyway?") 'Close' 'Warning' 'Button2' }
        if ($unmount) { foreach ($m in @($script:Mounts)) { [void](Dismount-One $m) } }
    }
    Save-Mounts
})
$form.Add_Shown({ Safe {
    Log $(if ($IsWinPE) { 'Running in WinPE.' } else { 'Running in normal Windows.' })
    if (-not (Test-StorageAvail)) { $rbStor.Enabled = $false; Log 'Storage cmdlets not available here - using diskpart.' }
    Update-SafeLabels
    Init-Unattend
    Update-Disks; Update-Letters; Load-Mounts; Update-MountList; Update-Esp; Update-Windows $true
} })

# ---------- resizing (1.8.1): what grows with the window and what stays at the right edge ----------
function Set-Anchor([string]$a, [object[]]$ctls) { foreach ($c in $ctls) { if ($c) { $c.Anchor = $a } } }
Set-Anchor 'Top,Bottom,Left,Right' @($tabs)
Set-Anchor 'Bottom,Left,Right'     @($txtLog)
Set-Anchor 'Top,Left,Right'        @($cmbDisk, $cmbPart, $lstMounts, $cmbWin, $lblWarn, $lblBcd, $lblDep, $lblExp, $cmbEsp, $cmbTool, $lblToolDesc, $lblToolNote)
Set-Anchor 'Top,Right'             @($btnRefresh, $btnUnmount, $btnUnmountAll, $btnRescan, $btnEspRefresh, $btnToolHelp)
Initialize-WrtWindow $form @($tabs.TabPages | ForEach-Object { $_ }) 600 520
[void]$form.ShowDialog()
