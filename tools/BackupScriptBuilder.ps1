# Version 1.2 (2026-11-26)
# Backup Script Builder - builds a FreeFileSync batch file (BackupScript.ffs_batch), or a Robocopy / Xcopy script (.ps1 or .bat)
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU General Public License v3 or (at your option) any later version, WITHOUT ANY WARRANTY. See LICENSE
# Uses only what ships with Windows (PowerShell 5.1 + WinForms).

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
Show-WrtSplash 'Backup Script Builder'

$BaseName = 'AutomaticFileBackups'

# ---------- helpers ----------
function ConvertTo-XmlText([string]$s) {
    return [System.Security.SecurityElement]::Escape($s)
}

function Get-PairName([string]$path, [hashtable]$used) {
    $name = Split-Path -Path $path -Leaf
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match ':') {
        $name = ($path.Substring(0, 1)) + '-Drive'
    }
    $name = $name -replace '[\\/:*?"<>|]', '_'
    $final = $name; $n = 2
    while ($used.ContainsKey($final.ToLower())) { $final = "$name-$n"; $n++ }
    $used[$final.ToLower()] = $true
    return $final
}

function New-BatchXml([string[]]$sources, [string]$root, [int]$days) {
    $current = ($root + '\' + 'Current')
    $archive = ($root + '\' + 'Archive-Deleted')
    $logs    = ($root + '\' + 'Logs')
    $used = @{}
    $sb = New-Object System.Text.StringBuilder
    $nl = "`r`n"
    [void]$sb.Append('<?xml version="1.0" encoding="utf-8"?>' + $nl)
    [void]$sb.Append('<FreeFileSync XmlType="BATCH" XmlFormat="23">' + $nl)
    [void]$sb.Append('    <Notes/>' + $nl)
    [void]$sb.Append('    <Compare>' + $nl)
    [void]$sb.Append('        <Variant>TimeAndSize</Variant>' + $nl)
    [void]$sb.Append('        <Symlinks>Exclude</Symlinks>' + $nl)
    [void]$sb.Append('        <IgnoreTimeShift/>' + $nl)
    [void]$sb.Append('    </Compare>' + $nl)
    [void]$sb.Append('    <Synchronize>' + $nl)
    [void]$sb.Append('        <Changes>' + $nl)
    [void]$sb.Append('            <Left Create="right" Update="right" Delete="right"/>' + $nl)
    [void]$sb.Append('            <Right Create="none" Update="none" Delete="none"/>' + $nl)
    [void]$sb.Append('        </Changes>' + $nl)
    [void]$sb.Append('        <DeletionPolicy>Versioning</DeletionPolicy>' + $nl)
    [void]$sb.Append('        <VersioningFolder Style="TimeStamp-Folder" MaxAge="' + $days + '">' + (ConvertTo-XmlText $archive) + '</VersioningFolder>' + $nl)
    [void]$sb.Append('    </Synchronize>' + $nl)
    [void]$sb.Append('    <Filter>' + $nl)
    [void]$sb.Append('        <Include>' + $nl)
    [void]$sb.Append('            <Item>*</Item>' + $nl)
    [void]$sb.Append('        </Include>' + $nl)
    [void]$sb.Append('        <Exclude>' + $nl)
    [void]$sb.Append('            <Item>\System Volume Information\</Item>' + $nl)
    [void]$sb.Append('            <Item>\$Recycle.Bin\</Item>' + $nl)
    [void]$sb.Append('            <Item>\RECYCLE?\</Item>' + $nl)
    [void]$sb.Append('            <Item>\Recovery\</Item>' + $nl)
    [void]$sb.Append('            <Item>*\thumbs.db</Item>' + $nl)
    [void]$sb.Append('            <Item>*\desktop.ini</Item>' + $nl)
    [void]$sb.Append('        </Exclude>' + $nl)
    [void]$sb.Append('        <SizeMin Unit="None">0</SizeMin>' + $nl)
    [void]$sb.Append('        <SizeMax Unit="None">0</SizeMax>' + $nl)
    [void]$sb.Append('        <TimeSpan Type="None">0</TimeSpan>' + $nl)
    [void]$sb.Append('    </Filter>' + $nl)
    [void]$sb.Append('    <FolderPairs>' + $nl)
    $pairDirs = @()
    foreach ($src in $sources) {
        $name = Get-PairName $src $used
        $dst = ($current + '\' + $name)
        $arc = ($archive + '\' + $name)
        $pairDirs += $dst, $arc
        [void]$sb.Append('        <Pair>' + $nl)
        [void]$sb.Append('            <Left>' + (ConvertTo-XmlText $src) + '</Left>' + $nl)
        [void]$sb.Append('            <Right>' + (ConvertTo-XmlText $dst) + '</Right>' + $nl)
        [void]$sb.Append('            <Synchronize>' + $nl)
        [void]$sb.Append('                <Changes>' + $nl)
        [void]$sb.Append('                    <Left Create="right" Update="right" Delete="right"/>' + $nl)
        [void]$sb.Append('                    <Right Create="none" Update="none" Delete="none"/>' + $nl)
        [void]$sb.Append('                </Changes>' + $nl)
        [void]$sb.Append('                <DeletionPolicy>Versioning</DeletionPolicy>' + $nl)
        [void]$sb.Append('                <VersioningFolder Style="TimeStamp-Folder" MaxAge="' + $days + '">' + (ConvertTo-XmlText $arc) + '</VersioningFolder>' + $nl)
        [void]$sb.Append('            </Synchronize>' + $nl)
        [void]$sb.Append('        </Pair>' + $nl)
    }
    [void]$sb.Append('    </FolderPairs>' + $nl)
    [void]$sb.Append('    <Errors Ignore="true" Retry="0" Delay="5"/>' + $nl)
    [void]$sb.Append('    <PostSyncCommand Condition="Completion"/>' + $nl)
    [void]$sb.Append('    <LogFolder>' + (ConvertTo-XmlText $logs) + '</LogFolder>' + $nl)
    [void]$sb.Append('    <EmailNotification Condition="Always"/>' + $nl)
    [void]$sb.Append('    <GridViewType>Action</GridViewType>' + $nl)
    [void]$sb.Append('    <Batch>' + $nl)
    [void]$sb.Append('        <ProgressDialog Minimized="false" AutoClose="true"/>' + $nl)
    [void]$sb.Append('        <ErrorDialog>Show</ErrorDialog>' + $nl)
    [void]$sb.Append('        <PostSyncAction>None</PostSyncAction>' + $nl)
    [void]$sb.Append('    </Batch>' + $nl)
    [void]$sb.Append('</FreeFileSync>' + $nl)
    return @{ Xml = $sb.ToString(); Dirs = @($current, $archive, $logs) + $pairDirs }
}

# ---------- Robocopy / Xcopy scripts (1.1) ----------
# Switch lists: Key = what goes on the command line, Text = what the tech sees, On = ticked by default.
$RoboSwitches = @(
    @{ Key = '/E';        On = $true;  Text = '/E - copy all subfolders, including empty ones' }
    @{ Key = '/MIR';      On = $false; Text = '/MIR - mirror: also DELETES backup files that were deleted from the source' }
    @{ Key = '/Z';        On = $true;  Text = '/Z - restartable mode (resumes a large file after a network drop)' }
    @{ Key = '/B';        On = $false; Text = '/B - backup mode: copies files you have no rights to (needs admin)' }
    @{ Key = '/J';        On = $false; Text = '/J - unbuffered I/O, faster for very large files' }
    @{ Key = '/COPY:DAT'; On = $true;  Text = '/COPY:DAT - copy data, attributes and timestamps' }
    @{ Key = '/DCOPY:T';  On = $true;  Text = '/DCOPY:T - keep the folders'' timestamps' }
    @{ Key = '/SEC';      On = $false; Text = '/SEC - also copy NTFS permissions' }
    @{ Key = '/XO';       On = $false; Text = '/XO - skip files that are older than the copy in the backup' }
    @{ Key = '/FFT';      On = $false; Text = '/FFT - 2-second time tolerance (backups to a NAS or FAT drive)' }
    @{ Key = '/XJ';       On = $true;  Text = '/XJ - skip junction points (avoids endless loops)' }
    @{ Key = '/R:2';      On = $true;  Text = '/R:2 - retry a failed file 2 times (default is 1 million)' }
    @{ Key = '/W:5';      On = $true;  Text = '/W:5 - wait 5 seconds between retries (default is 30)' }
    @{ Key = '/NP';       On = $true;  Text = '/NP - no progress percentages (keeps the log readable)' }
    @{ Key = '/NDL';      On = $false; Text = '/NDL - do not list folder names in the log' }
    @{ Key = '/NFL';      On = $false; Text = '/NFL - do not list file names in the log' }
    @{ Key = '/TEE';      On = $true;  Text = '/TEE - show the output on screen as well as in the log' }
    @{ Key = '/XD $RECYCLE.BIN "System Volume Information"'; On = $true; Text = '/XD - skip the Recycle Bin and System Volume Information folders' }
)
$XcopySwitches = @(
    @{ Key = '/E'; On = $true;  Text = '/E - copy all subfolders, including empty ones' }
    @{ Key = '/I'; On = $true;  Text = '/I - the destination is a folder (needed when copying several files)' }
    @{ Key = '/H'; On = $true;  Text = '/H - also copy hidden and system files' }
    @{ Key = '/C'; On = $true;  Text = '/C - keep going when a file fails' }
    @{ Key = '/K'; On = $true;  Text = '/K - keep the read-only attribute' }
    @{ Key = '/R'; On = $true;  Text = '/R - overwrite read-only files in the backup' }
    @{ Key = '/Y'; On = $true;  Text = '/Y - overwrite without asking (needed for unattended runs)' }
    @{ Key = '/D'; On = $true;  Text = '/D - only copy files that are newer than the backup copy' }
    @{ Key = '/Q'; On = $false; Text = '/Q - do not list the file names' }
    @{ Key = '/Z'; On = $false; Text = '/Z - restartable network copy' }
    @{ Key = '/J'; On = $false; Text = '/J - unbuffered I/O, faster for very large files' }
    @{ Key = '/O'; On = $false; Text = '/O - also copy file ownership and permissions' }
    @{ Key = '/X'; On = $false; Text = '/X - also copy audit settings (includes /O)' }
)
# The drive (C:) or network share (\\server\share) a source folder is on: robocopy can copy one drive per thread
function Get-DriveKey([string]$path) {
    if ($path -match '^(\\\\[^\\]+\\[^\\]+)') { return $Matches[1].ToUpper() }
    return $path.Substring(0, 2).ToUpper()
}
# Log file name: Backup-<Tool>[-<stamp>].log; the stamp is worked out when the script RUNS
function Get-LogStampFormat($log) {
    if ($log.Mode -ne 'New') { return '' }
    if ($log.Date -and $log.Time) { return 'yyyy-MM-dd_HHmmss' }
    if ($log.Date) { return 'yyyy-MM-dd' }
    if ($log.Time) { return 'HHmmss' }
    return ''
}
# Builds a Robocopy or Xcopy backup script.
#   $tool 'Robocopy' / 'Xcopy', $format 'ps1' / 'bat', $switches = keys from the lists above,
#   $log = @{ Enabled; Folder; Mode = 'Append' / 'New'; Date; Time }, $parallel = one thread per source drive (Robocopy), $mt = /MT threads (0 = off)
function New-CopyScript([string]$tool, [string]$format, [string[]]$sources, [string]$root, [string[]]$switches, $log, [bool]$parallel = $false, [int]$mt = 0) {
    $current = $root + '\Current'
    $used = @{}; $pairs = @()
    foreach ($s in $sources) { $pairs += , @($s.TrimEnd('\'), ($current + '\' + (Get-PairName $s $used))) }
    if ($pairs.Count) { foreach ($p in $pairs) { if ($p[0] -match '^[A-Za-z]:$') { $p[0] = $p[0] + '\.' } } }
    $isRobo = $tool -eq 'Robocopy'
    $sw = @($switches)
    if ($isRobo -and $mt -gt 0) { $sw += "/MT:$mt" }
    $failAt = if ($isRobo) { 8 } else { 2 }     # robocopy: 0-7 = success; xcopy: 0-1 = success
    $logOn = [bool]$log.Enabled
    $logDir = if ($log.Folder) { $log.Folder.TrimEnd('\') } else { $root + '\Logs' }
    $stampFmt = Get-LogStampFormat $log
    $base = "Backup-$tool"
    $groups = [ordered]@{}
    foreach ($p in $pairs) { $k = Get-DriveKey $p[0]; if (-not $groups.Contains($k)) { $groups[$k] = @() }; $groups[$k] += , $p }
    $useParallel = $isRobo -and $parallel -and $groups.Count -gt 1
    $nl = "`r`n"; $sb = New-Object System.Text.StringBuilder
    $head = "Backup script created by Backup Script Builder 1.2 ($tool, $(if ($useParallel) { 'one thread per source drive' } else { 'one copy at a time' })) on $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    if ($format -eq 'ps1') {
        $q = { param($t) "'" + ($t -replace "'", "''") + "'" }
        [void]$sb.Append("# $head${nl}# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit${nl}")
        [void]$sb.Append("`$ErrorActionPreference = 'Continue'${nl}`$Switches = @(")
        $swArgs = foreach ($x in $sw) { foreach ($part in [regex]::Matches($x, '"[^"]*"|\S+')) { & $q ($part.Value.Trim('"')) } }
        [void]$sb.Append(($swArgs -join ', ') + ")${nl}")
        if ($logOn) {
            [void]$sb.Append("`$LogDir = $(& $q $logDir)${nl}[void][IO.Directory]::CreateDirectory(`$LogDir)${nl}")
            $stampExpr = if ($stampFmt) { " + '-' + (Get-Date -Format '$stampFmt')" } else { '' }
            [void]$sb.Append("`$Log = Join-Path `$LogDir ('$base'$stampExpr + '.log')${nl}")
            if ($log.Mode -eq 'New' -and -not $stampFmt) { [void]$sb.Append("Remove-Item -LiteralPath `$Log -ErrorAction SilentlyContinue${nl}") }
        } else { [void]$sb.Append("`$Log = `$null${nl}") }
        # one function runs a list of pairs; the parallel version runs it once per drive in a background job
        $fn = "function Invoke-Pairs(`$Pairs, `$Switches, `$Log) {${nl}    `$worst = 0${nl}    foreach (`$p in `$Pairs) {${nl}        `$src, `$dst = `$p -split '\|', 2${nl}"
        if ($isRobo) { $fn += "        `$a = @(`$src, `$dst) + `$Switches${nl}        if (`$Log) { `$a += '/LOG+:' + `$Log }${nl}        & robocopy.exe @a${nl}" }
        else {
            $fn += "        `$a = @(`$src, (`$dst + '\')) + `$Switches${nl}"
            $fn += "        if (`$Log) { & xcopy.exe @a 2>&1 | Tee-Object -FilePath `$Log -Append } else { & xcopy.exe @a }${nl}"
        }
        $fn += "        if (`$LASTEXITCODE -gt `$worst) { `$worst = `$LASTEXITCODE }${nl}    }${nl}    `$worst${nl}}${nl}"
        [void]$sb.Append($fn)
        if ($useParallel) {
            [void]$sb.Append("`$Groups = [ordered]@{${nl}")
            foreach ($k in $groups.Keys) { [void]$sb.Append("    $(& $q $k) = @(" + (($groups[$k] | ForEach-Object { & $q ($_[0] + '|' + $_[1]) }) -join ', ') + ")${nl}") }
            [void]$sb.Append("}${nl}`$fnText = `${function:Invoke-Pairs}.ToString()${nl}`$jobs = foreach (`$k in `$Groups.Keys) {${nl}")
            [void]$sb.Append("    `$gl = if (`$Log) { `$Log -replace '\.log`$', ('-' + (`$k -replace '[\\:]', '') + '.log') } else { `$null }${nl}")
            [void]$sb.Append("    Start-Job -Name ('Backup ' + `$k) -ArgumentList `$fnText, @(`$Groups[`$k]), `$Switches, `$gl -ScriptBlock { param(`$f, `$Pairs, `$Switches, `$Log) . ([scriptblock]::Create('function Invoke-Pairs {' + `$f + '}')); Invoke-Pairs `$Pairs `$Switches `$Log | Select-Object -Last 1 }${nl}}${nl}")
            [void]$sb.Append("Write-Host ('Copying ' + @(`$jobs).Count + ' drives at the same time...')${nl}`$codes = @(`$jobs | Wait-Job | Receive-Job)${nl}`$jobs | Remove-Job${nl}")
            [void]$sb.Append("`$Worst = (`$codes | Measure-Object -Maximum).Maximum${nl}")
        } else {
            [void]$sb.Append("`$Pairs = @(${nl}" + (($pairs | ForEach-Object { '    ' + (& $q ($_[0] + '|' + $_[1])) }) -join ",${nl}") + "${nl})${nl}")
            [void]$sb.Append("`$Worst = Invoke-Pairs `$Pairs `$Switches `$Log | Select-Object -Last 1${nl}")
        }
        [void]$sb.Append("if ([int]`$Worst -ge $failAt) { Write-Host ""Backup finished WITH ERRORS (exit code `$Worst) - see the log."" -ForegroundColor Red; exit 1 }${nl}")
        [void]$sb.Append("Write-Host 'Backup finished.' -ForegroundColor Green${nl}exit 0${nl}")
    } else {
        $b = { param($t) $t -replace '%', '%%' }      # a % in a .bat line must be doubled
        $swLine = $sw -join ' '
        [void]$sb.Append("@echo off${nl}rem $head${nl}rem Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit${nl}setlocal${nl}")
        if ($useParallel) { [void]$sb.Append("if ""%~1""==""group"" goto :group%~2${nl}") }
        if ($logOn) {
            [void]$sb.Append("set ""LOGDIR=$(& $b $logDir)""${nl}if not exist ""%LOGDIR%"" mkdir ""%LOGDIR%""${nl}")
            if ($stampFmt) { [void]$sb.Append("for /f %%a in ('powershell -NoProfile -Command ""Get-Date -Format $stampFmt""') do set ""STAMP=-%%a""${nl}") } else { [void]$sb.Append("set ""STAMP=""${nl}") }
            [void]$sb.Append("set ""LOG=%LOGDIR%\$base%STAMP%.log""${nl}")
            if ($log.Mode -eq 'New' -and -not $stampFmt) { [void]$sb.Append("if exist ""%LOG%"" del ""%LOG%""${nl}") }
        }
        $line = {
            param($p, $logVar)
            if ($isRobo) { $l = "robocopy ""$(& $b $p[0])"" ""$(& $b $p[1])"" $swLine"; if ($logOn) { $l += " /LOG+:""%$logVar%""" } }
            else { $l = "xcopy ""$(& $b $p[0])"" ""$(& $b $p[1])\"" $swLine"; if ($logOn) { $l += " >> ""%$logVar%"" 2>&1" } }
            $l + "${nl}" + "if %ERRORLEVEL% GTR %WORST% set WORST=%ERRORLEVEL%${nl}"
        }
        if ($useParallel) {
            [void]$sb.Append("set ""RUN=%RANDOM%%RANDOM%""${nl}echo Copying $($groups.Count) drives at the same time...${nl}")
            $i = 0
            foreach ($k in $groups.Keys) { $i++; [void]$sb.Append("start ""Backup $(& $b $k)"" /min cmd /c """"%~f0"" group $i ""%RUN%"" ""%LOG%""""${nl}") }
            [void]$sb.Append(":wait${nl}ping -n 6 127.0.0.1 >nul${nl}")
            for ($j = 1; $j -le $i; $j++) { [void]$sb.Append("if not exist ""%TEMP%\bsb-%RUN%-$j.done"" goto :wait${nl}") }
            [void]$sb.Append("set WORST=0${nl}")
            for ($j = 1; $j -le $i; $j++) { [void]$sb.Append("set /p CODE=<""%TEMP%\bsb-%RUN%-$j.done""${nl}if %CODE% GTR %WORST% set WORST=%CODE%${nl}del ""%TEMP%\bsb-%RUN%-$j.done""${nl}") }
            [void]$sb.Append("goto :end${nl}")
            $i = 0
            foreach ($k in $groups.Keys) {
                $i++
                [void]$sb.Append(":group$i${nl}set WORST=0${nl}")
                if ($logOn) { [void]$sb.Append("set ""GLOG=%~4""${nl}set ""GLOG=%GLOG:~0,-4%-$(($k -replace '[\\:]', '') -replace '%', '%%').log""${nl}") }
                foreach ($p in $groups[$k]) { [void]$sb.Append((& $line $p 'GLOG')) }
                [void]$sb.Append(">""%TEMP%\bsb-%~3-$i.done"" echo %WORST%${nl}exit /b 0${nl}")
            }
        } else {
            [void]$sb.Append("set WORST=0${nl}")
            foreach ($p in $pairs) { [void]$sb.Append((& $line $p 'LOG')) }
        }
        [void]$sb.Append(":end${nl}if %WORST% GEQ $failAt (echo Backup finished WITH ERRORS ^(exit code %WORST%^) - see the log. & exit /b 1)${nl}echo Backup finished.${nl}exit /b 0${nl}")
    }
    $dirs = @($current) + @($pairs | ForEach-Object { $_[1] }); if ($logOn) { $dirs += $logDir }
    return @{ Text = $sb.ToString(); Dirs = $dirs; File = ($root + "\BackupScript-$tool.$format") }
}

# ---------- folder picker (checkbox tree) ----------
# The reparse tag of a folder, read from its directory entry (FindFirstFile) without opening the folder. 1.1 asked
# Get-Item for LinkType, which is EMPTY on PowerShell 5.1 for the profile's own junctions ("My Documents",
# "Application Data", "Cookies" ...: they deny listing), so they showed up as empty duplicate folders.
try {
    Add-Type -Namespace WrtBsb -Name Reparse -ErrorAction Stop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct FindData { public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME C, A, W; public uint SizeHigh, SizeLow, Tag, Reserved1;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string Alt; }
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr FindFirstFileW(string path, out FindData data);
[DllImport("kernel32.dll")] static extern bool FindClose(IntPtr h);
public static uint GetTag(string path) {
    FindData d; IntPtr h = FindFirstFileW(path.TrimEnd('\\'), out d);
    if (h == new IntPtr(-1)) return 0;
    FindClose(h); return ((d.Attr & 0x400) != 0) ? d.Tag : 0;
}
// a junction / mount point or a symbolic link (compared here: in PowerShell 0xA0000003 is a negative Int32)
public static bool IsLink(string path) { uint t = GetTag(path); return t == 0xA0000003u || t == 0xA000000Cu; }
'@
} catch {}
function Add-DummyChild($node) { [void]$node.Nodes.Add((New-Object System.Windows.Forms.TreeNode '...')) }
# Skip only real junctions (0xA0000003) and symbolic links (0xA000000C): they can loop or point at another folder in
# the list. OneDrive marks its folders as reparse points too (files on demand, other tags), and those must stay.
function Test-SkipFolder([System.IO.DirectoryInfo]$di) {
    if (-not ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $false }
    try { return [WrtBsb.Reparse]::IsLink($di.FullName) } catch {
        try { $lt = (Get-Item -LiteralPath $di.FullName -Force -ErrorAction Stop).LinkType; return ($lt -in 'Junction', 'SymbolicLink') } catch { return $false }
    }
}
# Windows and program folders: hidden from the tree until "Show Windows and program folders" is ticked. Backing them
# up is rarely what anyone wants (programs need reinstalling anyway) and most of it is locked while Windows runs.
$script:SystemRootNames = @('Windows', 'Program Files', 'Program Files (x86)', 'Program Files (Arm)', 'ProgramData', 'Recovery', 'PerfLogs',
    'System Volume Information', 'Boot', 'Config.Msi', 'MSOCache', 'OneDriveTemp', 'Documents and Settings', 'Intel', 'AMD', 'NVIDIA', 'inetpub')
function Test-SystemFolder([System.IO.DirectoryInfo]$di) {
    $a = $di.Attributes
    if (($a -band [IO.FileAttributes]::Hidden) -and ($a -band [IO.FileAttributes]::System)) { return $true }
    if ($di.Parent -and -not $di.Parent.Parent) {
        # directly on a drive
        if ($di.Name.StartsWith('$') -or $script:SystemRootNames -contains $di.Name) { return $true }
    }
    return $false
}
# The user's own folders wherever they really are (moved into OneDrive or elsewhere), every OneDrive folder, and the
# other user profiles on this PC (also ones kept on another drive)
function Get-QuickFolders {
    $list = New-Object System.Collections.ArrayList; $seen = @{}
    $add = { param($n, $p) if ($p) { $p = ([string]$p).TrimEnd('\'); if ($p -and -not $seen.ContainsKey($p.ToLower()) -and [IO.Directory]::Exists($p)) { $seen[$p.ToLower()] = 1; [void]$list.Add([pscustomobject]@{ Name = $n; Path = $p }) } } }
    foreach ($f in @(@('Desktop', 'Desktop'), @('Documents', 'MyDocuments'), @('Pictures', 'MyPictures'), @('Music', 'MyMusic'), @('Videos', 'MyVideos'), @('Favorites', 'Favorites'))) { & $add $f[0] ([Environment]::GetFolderPath($f[1])) }
    try {
        $usf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop
        foreach ($k in @(@('Downloads', '{374DE290-123F-4565-9164-39C4925E467B}'), @('Saved Games', '{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}'), @('Contacts', '{56784854-C6CB-462B-8169-88E350ACB882}'))) {
            if ($usf.($k[1])) { & $add $k[0] ([Environment]::ExpandEnvironmentVariables([string]$usf.($k[1]))) }
        }
    } catch {}
    & $add 'Saved Games' (Join-Path $env:USERPROFILE 'Saved Games'); & $add 'Contacts' (Join-Path $env:USERPROFILE 'Contacts')
    & $add 'OneDrive' $env:OneDrive; & $add 'OneDrive' $env:OneDriveConsumer; & $add 'OneDrive (work or school)' $env:OneDriveCommercial
    foreach ($a in @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) { & $add ('OneDrive - ' + $a.PSChildName) ([string](Get-ItemProperty $a.PSPath -ErrorAction SilentlyContinue).UserFolder) }
    & $add 'Your user folder' $env:USERPROFILE
    # other people's profiles (S-1-5-21-... are real user accounts; the service profiles are left out)
    foreach ($p in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'S-1-5-21-*' })) {
        $dir = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty $p.PSPath -ErrorAction SilentlyContinue).ProfileImagePath)
        if ($dir) { & $add ('User: ' + (Split-Path $dir -Leaf)) $dir }
    }
    return $list
}

$script:ShowSystem = $false
function New-FolderNode([System.IO.DirectoryInfo]$di) {
    $child = New-Object System.Windows.Forms.TreeNode $di.Name
    $child.Tag = $di.FullName
    if (Test-SystemFolder $di) { $child.Name = 'sys' }
    if ($di.Attributes -band [System.IO.FileAttributes]::Hidden) { $child.ForeColor = [System.Drawing.Color]::Gray }
    Add-DummyChild $child
    return $child
}
# The folders inside one folder, sorted, without junctions / symbolic links; $null when it cannot be opened
function Get-SubFolders([string]$path) {
    try { $all = (New-Object System.IO.DirectoryInfo $path).GetDirectories() } catch { return $null }
    $keep = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    foreach ($di in $all) { try { if (-not (Test-SkipFolder $di)) { $keep.Add($di) } } catch {} }
    $arr = $keep.ToArray()
    [Array]::Sort([string[]]@($arr | ForEach-Object { $_.Name }), $arr, [StringComparer]::CurrentCultureIgnoreCase)
    return ,$arr
}
function Expand-FolderNode($node) {
    if ($node.Nodes.Count -ne 1 -or $node.Nodes[0].Tag -or $node.Nodes[0].Name -eq 'info') { return }
    $tv = $node.TreeView; if ($tv) { $tv.BeginUpdate() }
    try {
        $node.Nodes.Clear()
        $dirs = Get-SubFolders ([string]$node.Tag)
        if ($null -eq $dirs) {
            # say so instead of an expand arrow that opens nothing
            $i = New-Object System.Windows.Forms.TreeNode '(cannot open this folder - no access)'; $i.Name = 'info'; $i.ForeColor = [System.Drawing.Color]::Gray
            [void]$node.Nodes.Add($i); return
        }
        foreach ($di in $dirs) {
            $c = New-FolderNode $di
            if ($c.Name -eq 'sys' -and -not $script:ShowSystem) { continue }
            [void]$node.Nodes.Add($c)
        }
    } finally { if ($tv) { $tv.EndUpdate() } }
}
# Show or hide the Windows / program folders in every folder that is already open (ticks elsewhere are kept)
function Update-SystemNodes($nodes) {
    foreach ($n in @($nodes)) {
        if (-not $n.Tag) { Update-SystemNodes $n.Nodes; continue }                  # the Quick picks group
        if ($n.Nodes.Count -eq 1 -and -not $n.Nodes[0].Tag) { continue }           # not opened yet, or no access
        if ($script:ShowSystem) {
            $dirs = Get-SubFolders ([string]$n.Tag)
            if ($dirs) {
                $have = @{}; foreach ($c in $n.Nodes) { if ($c.Tag) { $have[([string]$c.Tag).ToLower()] = 1 } }
                $i = 0
                foreach ($di in $dirs) {
                    if ($have.ContainsKey($di.FullName.ToLower())) { $i++; continue }
                    $c = New-FolderNode $di
                    if ($c.Name -eq 'sys') { $n.Nodes.Insert($i, $c); $i++ }
                }
            }
        } else {
            foreach ($c in @($n.Nodes)) { if ($c.Name -eq 'sys') { $n.Nodes.Remove($c) } }
        }
        Update-SystemNodes $n.Nodes
    }
}

function Get-CheckedPaths($nodes, $list) {
    foreach ($n in $nodes) {
        if ($n.Checked -and $n.Tag) { $list.Add([string]$n.Tag) }
        elseif ($n.Nodes.Count) { Get-CheckedPaths $n.Nodes $list }
    }
}
# One entry per folder: no duplicates (a quick pick and the same folder in the tree), and nothing that is already
# inside another ticked folder (Desktop when the whole user folder is ticked), so nothing is copied twice
function Get-UniqueFolders([string[]]$paths) {
    $clean = @($paths | Where-Object { $_ } | ForEach-Object { if ($_.Length -gt 3) { $_.TrimEnd('\') } else { $_ } } | Sort-Object -Property Length)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($p in $clean) {
        $covered = $false
        foreach ($o in $out) {
            $pre = if ($o.EndsWith('\')) { $o } else { $o + '\' }
            if ($p -ieq $o -or $p.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break }
        }
        if (-not $covered) { $out.Add($p) }
    }
    return ,$out
}

function Show-FolderPicker {
    $dlg = New-Object System.Windows.Forms.Form; Set-WrtScaling $dlg
    $dlg.Text = 'Check the folders to back up'
    $dlg.Size = New-Object System.Drawing.Size(520, 600)
    $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false

    $tree = New-Object System.Windows.Forms.TreeView
    $tree.CheckBoxes = $true
    $tree.Dock = 'Fill'
    $tree.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $tree.add_BeforeExpand({ Expand-FolderNode $_.Node })
    # the "(cannot open ...)" line is not a folder: it cannot be ticked
    $tree.add_BeforeCheck({ if ($_.Node.Name -eq 'info') { $_.Cancel = $true } })
    $script:ShowSystem = $false

    $tree.BeginUpdate()
    # quick picks first: the user's folders and OneDrive, wherever they really are
    $quick = New-Object System.Windows.Forms.TreeNode 'Quick picks (your folders and other users)'
    $quick.NodeFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    foreach ($q in Get-QuickFolders) {
        $n = New-Object System.Windows.Forms.TreeNode ($q.Name + '  -  ' + $q.Path); $n.Tag = $q.Path
        Add-DummyChild $n; [void]$quick.Nodes.Add($n)
    }
    [void]$tree.Nodes.Add($quick); $quick.Expand()
    foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $drv.IsReady) { continue }
        $label = $drv.Name.TrimEnd('\')
        if ($drv.VolumeLabel) { $label += '  (' + $drv.VolumeLabel + ')' }
        $root = New-Object System.Windows.Forms.TreeNode $label
        $root.Tag = $drv.Name
        Add-DummyChild $root
        [void]$tree.Nodes.Add($root)
    }
    # open the Users folder of the Windows drive by default since that is where most backups come from
    $sysDrive = ([string]$env:SystemDrive).TrimEnd('\') + '\'
    foreach ($r in $tree.Nodes) {
        if ($r.Tag -and ([string]$r.Tag) -ieq $sysDrive) {
            # filled here: before the window exists Expand() does not raise BeforeExpand (1.1 never opened Users)
            Expand-FolderNode $r; $r.Expand()
            foreach ($c in $r.Nodes) { if ($c.Text -eq 'Users') { Expand-FolderNode $c; $c.Expand(); $tree.SelectedNode = $c } }
        }
    }
    $tree.EndUpdate()

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, 42); $panel.Dock = 'Bottom'
    $chkSys = New-Object System.Windows.Forms.CheckBox
    $chkSys.Text = 'Show Windows and program folders'; $chkSys.AutoSize = $true; $chkSys.Location = New-Object System.Drawing.Point(8, 11)
    $chkSys.add_CheckedChanged({
        $script:ShowSystem = $chkSys.Checked
        $tree.BeginUpdate(); try { Update-SystemNodes $tree.Nodes } finally { $tree.EndUpdate() }
    })
    $tip.SetToolTip($chkSys, "Off: Windows, Program Files, ProgramData, Recovery and other system folders are not listed`r`n(and hidden system folders anywhere). Your own files are never in them.`r`nTick it to list and back them up anyway.")
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.Size = New-Object System.Drawing.Size(90, 28); $cancel.DialogResult = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(($panel.Width - 98), 7); $cancel.Anchor = 'Top, Right'
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Add Checked'; $ok.Size = New-Object System.Drawing.Size(110, 28); $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(($panel.Width - 214), 7); $ok.Anchor = 'Top, Right'
    $panel.Controls.AddRange(@($chkSys, $ok, $cancel))
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $cancel

    $dlg.Controls.Add($tree)
    $dlg.Controls.Add($panel)
    $script:PickerForm = $dlg; $script:PickerTree = $tree; $script:PickerShowSystem = $chkSys

    $checked = New-Object System.Collections.Generic.List[string]
    if ($dlg.ShowDialog() -eq 'OK') { Get-CheckedPaths $tree.Nodes $checked }
    $dlg.Dispose()
    $result = Get-UniqueFolders $checked.ToArray()
    return ,$result
}

# ---------- main window ----------
$form = New-Object System.Windows.Forms.Form; Set-WrtScaling $form
$form.Text = 'Backup Script Builder'
$form.Size = New-Object System.Drawing.Size(620, 950)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# "?" buttons: hover for a tooltip, click for the full explanation (same as the other toolkit tools)
$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 30000
function Add-Help($parent, [int]$x, [int]$y, [string]$title, [string]$text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = '?'; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size(24, 24)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $b.Tag = @($title, $text)
    $tip.SetToolTip($b, $text)
    $b.Add_Click({ [void][System.Windows.Forms.MessageBox]::Show([string]$this.Tag[1], [string]$this.Tag[0], 'OK', 'Information') })
    $parent.Controls.Add($b)
}

# 1. Source folders
$lblSrc = New-Object System.Windows.Forms.Label
$lblSrc.Text = '1. Source folders'
$lblSrc.Location = '15,60'; $lblSrc.AutoSize = $true
$lblSrc.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

$lstSrc = New-Object System.Windows.Forms.ListBox
$lstSrc.Location = '15,83'; $lstSrc.Size = '400,150'
$lstSrc.SelectionMode = 'MultiExtended'
$lstSrc.HorizontalScrollbar = $true

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add Folders...'; $btnAdd.Location = '425,83'; $btnAdd.Size = '110,30'
$btnAdd.add_Click({
    foreach ($p in (Show-FolderPicker)) {
        if (-not @($lstSrc.Items | Where-Object { $_ -ieq $p }).Count) { [void]$lstSrc.Items.Add($p) }
    }
})

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = 'Remove'; $btnRemove.Location = '425,120'; $btnRemove.Size = '110,30'
$btnRemove.add_Click({
    $sel = @($lstSrc.SelectedItems)
    foreach ($s in $sel) { $lstSrc.Items.Remove($s) }
})

# 2. Destination folder
$lblDst = New-Object System.Windows.Forms.Label
$lblDst.Text = '2. Destination folder'
$lblDst.Location = '15,245'; $lblDst.AutoSize = $true
$lblDst.Font = $lblSrc.Font

$txtDest = New-Object System.Windows.Forms.TextBox
$txtDest.Location = '15,268'; $txtDest.Size = '400,25'

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'; $btnBrowse.Location = '425,266'; $btnBrowse.Size = '110,28'
$btnBrowse.add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Pick where the backup script and its folders will go'
    $fb.ShowNewFolderButton = $true
    if ($txtDest.Text -and (Test-Path $txtDest.Text)) { $fb.SelectedPath = $txtDest.Text }
    if ($fb.ShowDialog() -eq 'OK') { $txtDest.Text = $fb.SelectedPath }
    $fb.Dispose()
})

# The script and its folders go in <chosen folder>\AutomaticFileBackups
# (or straight into the chosen folder if it is already named that).
function Get-DestRoot {
    $p = $txtDest.Text.Trim().TrimEnd('\')
    if (-not $p) { return $null }
    if ((Split-Path $p -Leaf) -ieq $BaseName) { return $p }
    return $p + '\' + $BaseName
}

$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Location = '15,296'; $lblPreview.Size = '520,20'
$lblPreview.ForeColor = [System.Drawing.Color]::DimGray
$lblPreview.AutoEllipsis = $true
$txtDest.add_TextChanged({
    $r = Get-DestRoot
    if ($r) { $lblPreview.Text = 'Creates ' + $r + '\  (Current, Archive-Deleted, Logs)' } else { $lblPreview.Text = '' }
})

# 3. Keep days
$lblDays = New-Object System.Windows.Forms.Label
$lblDays.Text = '3. Keep deleted/changed files for (days)'
$lblDays.Location = '5,8'; $lblDays.AutoSize = $true
$lblDays.Font = $lblSrc.Font

$numDays = New-Object System.Windows.Forms.NumericUpDown
$numDays.Location = '5,31'; $numDays.Size = '100,25'
$numDays.Minimum = 1; $numDays.Maximum = 36500; $numDays.Value = 365

# 4. Build
$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = '4. Build FreeFileSync batch'
$btnBuild.Location = '15,778'; $btnBuild.Size = '485,45'
$btnBuild.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$btnBuild.add_Click({
    if ($lstSrc.Items.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show('Add at least one source folder.', 'Backup Script Builder', 'OK', 'Warning'); return
    }
    $root = Get-DestRoot
    if (-not $root -or $root -notmatch '^([a-zA-Z]:|\\\\[^\\]+\\[^\\]+)\\') {
        [void][System.Windows.Forms.MessageBox]::Show('Pick a destination folder (a full path like H:\Backups).', 'Backup Script Builder', 'OK', 'Warning'); return
    }
    $sources = @($lstSrc.Items | ForEach-Object { [string]$_ })
    foreach ($s in $sources) {
        $sp = $s.TrimEnd('\') + '\'
        if (($root + '\').StartsWith($sp, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void][System.Windows.Forms.MessageBox]::Show("The destination is inside the source folder $s.`r`nThat would back the backup up into itself. Pick another folder.", 'Backup Script Builder', 'OK', 'Error'); return
        }
    }
    if (-not $rbFfs.Checked) { Invoke-BuildCopyScript $sources $root; return }
    $out = ($root + '\' + 'BackupScript.ffs_batch')
    if (Test-Path $out) {
        $a = [System.Windows.Forms.MessageBox]::Show("$out already exists.`r`nOverwrite it?", 'Backup Script Builder', 'YesNo', 'Question')
        if ($a -ne 'Yes') { return }
    }
    try {
        $r = New-BatchXml $sources $root ([int]$numDays.Value)
        foreach ($d in $r.Dirs) { [void][System.IO.Directory]::CreateDirectory($d) }
        [System.IO.File]::WriteAllText($out, $r.Xml, (New-Object System.Text.UTF8Encoding $false))
        Add-ScriptChoice $out
        $cboScript.Text = $out
        $a = [System.Windows.Forms.MessageBox]::Show("Backup script created:`r`n$out`r`n`r`nOpen the folder?", 'Backup Script Builder', 'YesNo', 'Information')
        if ($a -eq 'Yes') { Start-Process explorer.exe $root }
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("Could not build the script:`r`n" + $_.Exception.Message, 'Backup Script Builder', 'OK', 'Error')
    }
})

# ---------- 1.1: what to create (FreeFileSync batch, Robocopy or Xcopy script) ----------
$lblType = New-Object System.Windows.Forms.Label
$lblType.Text = 'What to create'; $lblType.Location = '15,8'; $lblType.AutoSize = $true; $lblType.Font = $lblSrc.Font
$rbFfs = New-Object System.Windows.Forms.RadioButton;   $rbFfs.Text = 'Create FreeFileSync batch'; $rbFfs.Location = '15,30';  $rbFfs.Size = '180,24'; $rbFfs.Checked = $true
$rbRobo = New-Object System.Windows.Forms.RadioButton;  $rbRobo.Text = 'Create Robocopy batch';    $rbRobo.Location = '200,30'; $rbRobo.Size = '170,24'
$rbXcopy = New-Object System.Windows.Forms.RadioButton; $rbXcopy.Text = 'Create Xcopy batch';      $rbXcopy.Location = '375,30'; $rbXcopy.Size = '160,24'
$pnlFfs = New-Object System.Windows.Forms.Panel; $pnlFfs.Location = '10,325'; $pnlFfs.Size = '570,445'

# one page for Robocopy, one for Xcopy: script type, log options, (robocopy) threads, then all switches at the bottom
$CopyUi = @{}
function New-CopyPanel([string]$tool, $switchList) {
    $p = New-Object System.Windows.Forms.Panel; $p.Location = '10,325'; $p.Size = '570,445'; $p.AutoScroll = $true; $p.Visible = $false
    $u = @{ Panel = $p }
    $mk = { param($type, $text, $loc, $size) $c = New-Object "System.Windows.Forms.$type"; if ($text) { $c.Text = $text }; $c.Location = $loc; if ($size) { $c.Size = $size } else { $c.AutoSize = $true }; $p.Controls.Add($c); $c }
    $l = & $mk 'Label' 'Script type' '5,8' $null; $l.Font = $lblSrc.Font
    $g1 = New-Object System.Windows.Forms.Panel; $g1.Location = '130,4'; $g1.Size = '300,26'; $p.Controls.Add($g1)
    $u.RbPs1 = New-Object System.Windows.Forms.RadioButton; $u.RbPs1.Text = 'PowerShell (.ps1)'; $u.RbPs1.Location = '0,2'; $u.RbPs1.AutoSize = $true; $u.RbPs1.Checked = $true
    $u.RbBat = New-Object System.Windows.Forms.RadioButton; $u.RbBat.Text = 'Batch file (.bat)'; $u.RbBat.Location = '150,2'; $u.RbBat.AutoSize = $true
    $g1.Controls.AddRange(@($u.RbPs1, $u.RbBat))
    $l = & $mk 'Label' 'Log' '5,40' $null; $l.Font = $lblSrc.Font
    $u.ChkLog = & $mk 'CheckBox' 'Create a log of every run' '130,38' $null; $u.ChkLog.Checked = $true
    [void](& $mk 'Label' 'Log folder' '5,70' $null)
    $u.TxtLog = & $mk 'TextBox' '' '130,67' '300,25'
    $u.BtnLog = & $mk 'Button' 'Browse...' '440,65' '100,28'
    $u.LblLogHint = & $mk 'Label' 'Empty = the Logs folder next to the backup' '130,93' '400,18'; $u.LblLogHint.ForeColor = [System.Drawing.Color]::DimGray
    $g2 = New-Object System.Windows.Forms.Panel; $g2.Location = '130,113'; $g2.Size = '420,26'; $p.Controls.Add($g2)
    $u.RbAppend = New-Object System.Windows.Forms.RadioButton; $u.RbAppend.Text = 'Append to one log file'; $u.RbAppend.Location = '0,2'; $u.RbAppend.AutoSize = $true
    $u.RbNew = New-Object System.Windows.Forms.RadioButton; $u.RbNew.Text = 'New log file every run'; $u.RbNew.Location = '190,2'; $u.RbNew.AutoSize = $true; $u.RbNew.Checked = $true
    $g2.Controls.AddRange(@($u.RbAppend, $u.RbNew))
    $u.ChkDate = & $mk 'CheckBox' 'Add the date to the log name' '150,141' $null; $u.ChkDate.Checked = $true
    $u.ChkTime = & $mk 'CheckBox' 'Add the time' '370,141' $null; $u.ChkTime.Checked = $true
    $y = 175
    if ($tool -eq 'Robocopy') {
        $l = & $mk 'Label' 'Threads' '5,177' $null; $l.Font = $lblSrc.Font
        $g3 = New-Object System.Windows.Forms.Panel; $g3.Location = '130,173'; $g3.Size = '380,50'; $p.Controls.Add($g3)
        $u.RbSingle = New-Object System.Windows.Forms.RadioButton; $u.RbSingle.Text = 'One drive at a time (single thread)'; $u.RbSingle.Location = '0,2'; $u.RbSingle.AutoSize = $true; $u.RbSingle.Checked = $true
        $u.RbParallel = New-Object System.Windows.Forms.RadioButton; $u.RbParallel.Text = 'One thread per source drive (drives copy at the same time)'; $u.RbParallel.Location = '0,26'; $u.RbParallel.AutoSize = $true
        $g3.Controls.AddRange(@($u.RbSingle, $u.RbParallel))
        [void](& $mk 'Label' 'Threads per copy (/MT, 0 = off)' '150,230' $null)
        $u.NumMt = & $mk 'NumericUpDown' '' '370,227' '70,25'; $u.NumMt.Minimum = 0; $u.NumMt.Maximum = 128; $u.NumMt.Value = 8
        $y = 262
    }
    $l = & $mk 'Label' "$tool switches (ticked = used)" "5,$y" $null; $l.Font = $lblSrc.Font
    $u.Switches = & $mk 'CheckedListBox' '' "5,$($y + 22)" '540,150'; $u.Switches.CheckOnClick = $true; $u.Switches.HorizontalScrollbar = $true
    foreach ($s in $switchList) { [void]$u.Switches.Items.Add($s.Text, [bool]$s.On) }
    $u.SwitchKeys = @($switchList | ForEach-Object { $_.Key })
    $u.ChkLog.Tag = $u; $u.RbNew.Tag = $u; $u.BtnLog.Tag = $u
    $sync = { $x = $this.Tag; foreach ($c in $x.TxtLog, $x.BtnLog, $x.RbAppend, $x.RbNew) { $c.Enabled = $x.ChkLog.Checked }; $x.ChkDate.Enabled = $x.ChkLog.Checked -and $x.RbNew.Checked; $x.ChkTime.Enabled = $x.ChkDate.Enabled }
    $u.ChkLog.Add_CheckedChanged($sync); $u.RbNew.Add_CheckedChanged($sync)
    $u.BtnLog.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.Description = 'Where the log files go'; $fb.ShowNewFolderButton = $true; if ($fb.ShowDialog() -eq 'OK') { $this.Tag.TxtLog.Text = $fb.SelectedPath }; $fb.Dispose() })
    $hy = if ($tool -eq 'Robocopy') { 171 } else { -1 }
    Add-Help $p 435 4 'Script type' ("PowerShell (.ps1) or a classic batch file (.bat) - both do the same copy. The task on the Schedule Task tab runs a .ps1 with PowerShell and a .bat with cmd.`r`n`r`nThe script is saved next to the backup as BackupScript-$tool.ps1 or .bat.")
    Add-Help $p 440 36 'Log' ("Writes what $tool did on every run to a .log file. 'Log folder' empty = the Logs folder inside the backup folder.`r`n`r`n" +
        "Append to one log file: every run adds to Backup-$tool.log.`r`nNew log file every run: a new file each time; tick date and / or time to put them in its name (Backup-$tool-2026-11-25_230000.log). With neither ticked, the one log file is replaced every run.")
    if ($hy -gt 0) { Add-Help $p 520 $hy 'Threads' ("One drive at a time: every folder is copied one after the other.`r`n`r`nOne thread per source drive: folders on different drives (or network shares) copy at the same time, one copy per drive, each with its own log (Backup-Robocopy-...-C.log). Faster when the sources are on separate disks; no gain for folders on the same disk.`r`n`r`n" +
        "Threads per copy (/MT): robocopy copies this many files at once inside each copy (1-128, 8 is robocopy's default). 0 = off. Not useful on a single slow USB disk.") }
    Add-Help $p 520 ($y - 2) "$tool switches" ("Every switch that matters for a backup, with what it does. Ticked switches go into the script; the defaults are a safe backup that only adds and updates files.`r`n`r`n" +
        $(if ($tool -eq 'Robocopy') { "/MIR also deletes files from the backup that were deleted from the source - only tick it if you want an exact mirror. /B needs the task to run as administrator." } else { "Keep /I and /Y ticked for unattended runs, or xcopy stops and asks a question." }))
    $script:CopyUi[$tool] = $u
    return $p
}
$pnlRobo = New-CopyPanel 'Robocopy' $RoboSwitches
$pnlXcopy = New-CopyPanel 'Xcopy' $XcopySwitches
function Get-BuildType { if ($rbRobo.Checked) { 'Robocopy' } elseif ($rbXcopy.Checked) { 'Xcopy' } else { 'FreeFileSync' } }
$typeChanged = {
    $t = Get-BuildType
    $pnlFfs.Visible = $t -eq 'FreeFileSync'; $pnlRobo.Visible = $t -eq 'Robocopy'; $pnlXcopy.Visible = $t -eq 'Xcopy'
    $btnBuild.Text = '4. Build ' + $(if ($t -eq 'FreeFileSync') { 'FreeFileSync batch' } else { "$t script" })
    $r = Get-DestRoot
    if ($r) { $lblPreview.Text = 'Creates ' + $r + '\  ' + $(if ($t -eq 'FreeFileSync') { '(Current, Archive-Deleted, Logs)' } else { "(Current, Logs, BackupScript-$t)" }) }
}
foreach ($rb in $rbFfs, $rbRobo, $rbXcopy) { $rb.Add_CheckedChanged($typeChanged) }
$txtDest.add_TextChanged($typeChanged)

function Invoke-BuildCopyScript([string[]]$sources, [string]$root) {
    $tool = Get-BuildType; $u = $CopyUi[$tool]
    $sw = @(for ($i = 0; $i -lt $u.Switches.Items.Count; $i++) { if ($u.Switches.GetItemChecked($i)) { $u.SwitchKeys[$i] } })
    $log = @{ Enabled = $u.ChkLog.Checked; Folder = $u.TxtLog.Text.Trim(); Mode = $(if ($u.RbNew.Checked) { 'New' } else { 'Append' }); Date = $u.ChkDate.Checked; Time = $u.ChkTime.Checked }
    $par = ($tool -eq 'Robocopy') -and $u.RbParallel.Checked
    $mt = if ($tool -eq 'Robocopy') { [int]$u.NumMt.Value } else { 0 }
    $r = New-CopyScript $tool $(if ($u.RbBat.Checked) { 'bat' } else { 'ps1' }) $sources $root $sw $log $par $mt
    if (Test-Path -LiteralPath $r.File) {
        if ([System.Windows.Forms.MessageBox]::Show("$($r.File) already exists.`r`nOverwrite it?", 'Backup Script Builder', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    try {
        foreach ($d in $r.Dirs) { [void][System.IO.Directory]::CreateDirectory($d) }
        # a .bat must be in the console's code page: keep it ASCII-safe; a .ps1 gets a BOM so PowerShell 5.1 reads it right
        if ($r.File -like '*.bat') { [System.IO.File]::WriteAllText($r.File, $r.Text, [System.Text.Encoding]::Default) }
        else { [System.IO.File]::WriteAllText($r.File, $r.Text, (New-Object System.Text.UTF8Encoding $true)) }
        Add-ScriptChoice $r.File; $cboType.SelectedItem = $tool; $cboScript.Text = $r.File
        if ([System.Windows.Forms.MessageBox]::Show("$tool script created:`r`n$($r.File)`r`n`r`nOpen the folder?", 'Backup Script Builder', 'YesNo', 'Information') -eq 'Yes') { Start-Process explorer.exe $root }
    } catch { [void][System.Windows.Forms.MessageBox]::Show("Could not build the script:`r`n" + $_.Exception.Message, 'Backup Script Builder', 'OK', 'Error') }
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabBuild = New-Object System.Windows.Forms.TabPage 'Build Script'
$tabSched = New-Object System.Windows.Forms.TabPage 'Schedule Task'
$tabBuild.Controls.AddRange(@($lblType, $rbFfs, $rbRobo, $rbXcopy, $lblSrc, $lstSrc, $btnAdd, $btnRemove, $lblDst, $txtDest, $btnBrowse, $lblPreview, $pnlFfs, $pnlRobo, $pnlXcopy, $btnBuild))
$pnlFfs.Controls.AddRange(@($lblDays, $numDays))
$tabs.TabPages.AddRange(@($tabBuild, $tabSched))
$form.Controls.Add($tabs)

$lnkFfs = New-Object System.Windows.Forms.LinkLabel
$lnkFfs.Dock = 'Bottom'; $lnkFfs.Height = 26; $lnkFfs.TextAlign = 'MiddleCenter'
$lnkFfs.Text = 'Made for FreeFileSync, the free open source sync tool: https://freefilesync.org/'
$lnkFfs.LinkArea = New-Object System.Windows.Forms.LinkArea($lnkFfs.Text.IndexOf('https'), 'https://freefilesync.org/'.Length)
$lnkFfs.add_LinkClicked({ Start-Process 'https://freefilesync.org/' })
$form.Controls.Add($lnkFfs)
$tabs.BringToFront()

Add-Help $tabBuild 140 57 'Source folders' ("The folders you want backed up. Click 'Add Folders...' and tick as many folders as you like in the tree (it opens at C:\Users). Quick picks lists your own folders, OneDrive and the other users' profiles. Windows and program folders (Windows, Program Files, ProgramData ...) are left out of the tree until you tick 'Show Windows and program folders'. A folder inside another ticked folder is only added once.`r`n`r`n" +
    "Each folder becomes one folder pair in the FreeFileSync script: the folder (left side) is mirrored to Current\<folder name> (right side).`r`n`r`n" +
    "Two folders with the same name (for example two users' Documents) get -2, -3 ... so they do not overwrite each other. 'Remove' takes the selected folders off the list.")
Add-Help $tabBuild 165 242 'Destination folder' ("Where the backup lives. Usually a folder on an external or second drive, for example H:\.`r`n`r`n" +
    "The tool creates AutomaticFileBackups inside it (or uses the folder itself when it is already called AutomaticFileBackups) with:`r`n" +
    "  Current - the latest copy of every source folder`r`n  Archive-Deleted - files that were deleted or changed, in time-stamped folders`r`n  Logs - FreeFileSync's log of every run`r`n" +
    "and saves BackupScript.ffs_batch there.`r`n`r`nThe destination cannot be inside one of the source folders.")
Add-Help $pnlFfs 290 5 'Keep days' ("How many days FreeFileSync keeps files in Archive-Deleted. When a file is deleted or changed in a source folder, the old copy is moved there instead of being thrown away.`r`n`r`n" +
    "Older archived copies are removed after this many days (the script's MaxAge). 365 = one year.")
Add-Help $tabBuild 510 788 'Build Script' ("Creates the folders and writes BackupScript.ffs_batch, a FreeFileSync batch job with your folders, destination and keep days.`r`n`r`n" +
    "Run it by double-clicking it (with FreeFileSync installed) or schedule it on the Schedule Task tab. An existing script is only overwritten after you confirm.")
# =====================================================================
# Tab 2: Scheduled task
# Every task this tool makes lives in the Task Scheduler folder
# \BackupScriptBuilder\ so it can find, modify and delete only its own.
# =====================================================================
$TaskFolder = '\BackupScriptBuilder\'
$NewTaskText = '<New task>'
$FreqOnce = 'Once'; $FreqDaily = 'Daily'; $FreqWeekly = 'Weekly'; $FreqHours = 'Every X hours'; $FreqLogon = 'At log on'
$TimeLimits = [ordered]@{
    'No limit'   = [TimeSpan]::Zero
    '30 minutes' = New-TimeSpan -Minutes 30
    '1 hour'     = New-TimeSpan -Hours 1
    '2 hours'    = New-TimeSpan -Hours 2
    '4 hours'    = New-TimeSpan -Hours 4
    '8 hours'    = New-TimeSpan -Hours 8
    '12 hours'   = New-TimeSpan -Hours 12
    '1 day'      = New-TimeSpan -Days 1
    '3 days'     = New-TimeSpan -Days 3
}
$boldFont = $lblSrc.Font

function New-Lbl([string]$text, [string]$loc, [switch]$Bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = $loc; $l.AutoSize = $true
    if ($Bold) { $l.Font = $boldFont }
    $tabSched.Controls.Add($l)
    return $l
}

# --- existing tasks ---
[void](New-Lbl 'Task' '15,15' -Bold)
$cboTask = New-Object System.Windows.Forms.ComboBox
$cboTask.Location = '130,12'; $cboTask.Size = '255,25'; $cboTask.DropDownStyle = 'DropDownList'
$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = 'Delete Task'; $btnDelete.Location = '425,10'; $btnDelete.Size = '110,28'

[void](New-Lbl 'Task name' '15,52')
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = '130,49'; $txtName.Size = '285,25'

# --- action ---
[void](New-Lbl 'Backup type' '15,89' -Bold)
$cboType = New-Object System.Windows.Forms.ComboBox
$cboType.Location = '130,86'; $cboType.Size = '255,25'; $cboType.DropDownStyle = 'DropDownList'
$cboType.Items.AddRange(@('FreeFileSync', 'Robocopy', 'Xcopy')); $cboType.SelectedIndex = 0
$tabSched.Controls.Add($cboType)
[void](New-Lbl 'Backup script' '15,126' -Bold)
$cboScript = New-Object System.Windows.Forms.ComboBox
$cboScript.Location = '130,123'; $cboScript.Size = '255,25'
$btnScript = New-Object System.Windows.Forms.Button
$btnScript.Text = 'Browse...'; $btnScript.Location = '425,121'; $btnScript.Size = '110,28'

$lblExe = New-Lbl 'FreeFileSync.exe' '15,163'
$txtExe = New-Object System.Windows.Forms.TextBox
$txtExe.Location = '130,160'; $txtExe.Size = '255,25'
$txtExe.Text = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$btnExe = New-Object System.Windows.Forms.Button
$btnExe.Text = 'Browse...'; $btnExe.Location = '425,158'; $btnExe.Size = '110,28'

# --- trigger ---
[void](New-Lbl 'Schedule' '15,207' -Bold)
$cboFreq = New-Object System.Windows.Forms.ComboBox
$cboFreq.Location = '130,204'; $cboFreq.Size = '130,25'; $cboFreq.DropDownStyle = 'DropDownList'
$cboFreq.Items.AddRange(@($FreqOnce, $FreqDaily, $FreqWeekly, $FreqHours, $FreqLogon))

$lblStart = New-Lbl 'Start' '15,244'
$dtDate = New-Object System.Windows.Forms.DateTimePicker
$dtDate.Location = '130,241'; $dtDate.Size = '150,25'; $dtDate.Format = 'Short'
$dtTime = New-Object System.Windows.Forms.DateTimePicker
$dtTime.Location = '290,241'; $dtTime.Size = '125,25'; $dtTime.Format = 'Time'; $dtTime.ShowUpDown = $true
$dtTime.Value = [datetime]::Today.AddHours(2)

$lblEvery = New-Lbl 'Repeat every' '15,281'
$numEvery = New-Object System.Windows.Forms.NumericUpDown
$numEvery.Location = '130,278'; $numEvery.Size = '70,25'; $numEvery.Minimum = 1; $numEvery.Maximum = 365
$lblUnit = New-Lbl 'days' '205,281'

$pnlDays = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlDays.Location = '128,309'; $pnlDays.Size = '410,28'
$dayBoxes = @()
foreach ($d in 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $d.Substring(0, 3); $cb.Tag = $d; $cb.AutoSize = $true
    $pnlDays.Controls.Add($cb); $dayBoxes += $cb
}

# --- settings ---
[void](New-Lbl 'Settings' '15,352' -Bold)
$chkMissed = New-Object System.Windows.Forms.CheckBox
$chkMissed.Text = 'Run as soon as possible after a missed start'
$chkMissed.Location = '130,350'; $chkMissed.AutoSize = $true; $chkMissed.Checked = $true

[void](New-Lbl 'Stop task after' '15,385')
$cboLimit = New-Object System.Windows.Forms.ComboBox
$cboLimit.Location = '130,382'; $cboLimit.Size = '130,25'; $cboLimit.DropDownStyle = 'DropDownList'
foreach ($k in $TimeLimits.Keys) { [void]$cboLimit.Items.Add($k) }
$cboLimit.SelectedItem = '4 hours'

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'Create Task'; $btnSave.Location = '15,437'; $btnSave.Size = '370,45'
$btnSave.Font = $btnBuild.Font
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run Now'; $btnRun.Location = '425,437'; $btnRun.Size = '110,45'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = '15,492'; $lblStatus.Size = '520,20'; $lblStatus.ForeColor = [System.Drawing.Color]::DimGray

$tabSched.Controls.AddRange(@($cboTask, $btnDelete, $txtName, $cboScript, $btnScript, $txtExe, $btnExe, $cboFreq,
    $dtDate, $dtTime, $numEvery, $pnlDays, $chkMissed, $cboLimit, $btnSave, $btnRun, $lblStatus))

Add-Help $tabSched 390 12 'Task' ("Pick <New task> to make a new scheduled backup, or one of the tasks this tool already made to change, run or delete it.`r`n`r`n" +
    "The tool keeps its tasks in their own Task Scheduler folder, \BackupScriptBuilder\, so it only ever lists and changes its own tasks. 'Delete Task' removes only the task, never the script or the backups.")
Add-Help $tabSched 390 86 'Backup type' ("Which kind of backup script the task runs:`r`n  FreeFileSync - starts FreeFileSync.exe with the .ffs_batch file`r`n  Robocopy / Xcopy - runs the script built on the first tab: a .ps1 with PowerShell, a .bat with cmd`r`n`r`nThe list of scripts shows the ones of this type.")
Add-Help $tabSched 425 49 'Task name' ("A name you will recognise, for example 'Nightly backup to H'. It is the task's name in Task Scheduler (folder \BackupScriptBuilder\).`r`n`r`nRenaming a task and saving replaces the old one.")
Add-Help $tabSched 390 123 'Backup script' ("The FreeFileSync batch file (.ffs_batch) the task runs. The script you built on the first tab is already in the list, as are the scripts your existing tasks use. 'Browse...' picks any other .ffs_batch file.")
Add-Help $tabSched 390 160 'FreeFileSync.exe' ("The task starts this program with the backup script as its argument. FreeFileSync is normally installed at C:\Program Files\FreeFileSync\FreeFileSync.exe.`r`n`r`nGet it free from https://freefilesync.org/ if it is not installed.")
Add-Help $tabSched 270 204 'Schedule' ("When the backup runs:`r`n  Once - one time, at the start date and time`r`n  Daily - every N days at that time`r`n  Weekly - on the ticked days, every N weeks`r`n" +
    "  Every X hours - from the start time, repeating every N hours`r`n  At log on - each time you sign in to Windows")
Add-Help $tabSched 425 241 'Start' ("The first date and the time of day the task runs. Daily and weekly tasks run at this time on every matching day.")
Add-Help $tabSched 270 278 'Repeat every' ("Daily: run every N days (1 = every day). Weekly: every N weeks on the ticked days. Every X hours: every N hours (1-23).")
Add-Help $tabSched 425 348 'Run after a missed start' ("When ticked, a backup that was missed because the PC was off or asleep runs as soon as possible afterwards.`r`n`r`nWhen not ticked, a missed run is skipped until the next scheduled time.")
Add-Help $tabSched 270 382 'Stop task after' ("Task Scheduler stops the backup if it is still running after this long, for example when a drive is stuck. Pick 'No limit' to never stop it.`r`n`r`nA first full backup of many files can take hours, so leave enough time.")
Add-Help $tabSched 390 447 'Create / Save, Run Now' ("Create Task (or Save Changes for an existing one) registers the task for your user account. It runs while you are logged on, with no password stored.`r`n`r`nRun Now starts the selected task straight away, to test it.")

# --- logic ---
function Add-ScriptChoice([string]$path) {
    if ($path -and -not $cboScript.Items.Contains($path)) { [void]$cboScript.Items.Add($path) }
}

# the script a task runs: the last quoted path in its arguments (FreeFileSync "x.ffs_batch", powershell -File "x.ps1", cmd /c "x.bat")
function Get-ScriptFromAction($a) {
    $m = [regex]::Matches([string]$a.Arguments, '"([^"]+)"')
    if ($m.Count) { return $m[$m.Count - 1].Groups[1].Value }
    return ([string]$a.Arguments).Trim()
}
function Get-ScriptType([string]$exe, [string]$script) {
    if ($exe -like '*FreeFileSync*' -or $script -like '*.ffs_batch') { return 'FreeFileSync' }
    if ($script -match 'xcopy') { return 'Xcopy' }
    if ($script -match 'robocopy') { return 'Robocopy' }
    try { if ((Get-Content -LiteralPath $script -TotalCount 5 -ErrorAction Stop) -match 'Xcopy') { return 'Xcopy' } } catch {}
    return 'Robocopy'
}
function Update-TypeUi {
    $ffs = [string]$cboType.SelectedItem -eq 'FreeFileSync'
    $lblExe.Visible = $ffs; $txtExe.Visible = $ffs; $btnExe.Visible = $ffs
    foreach ($c in $tabSched.Controls) { if ($c -is [System.Windows.Forms.Button] -and $c.Text -eq '?' -and $c.Tag -and $c.Tag[0] -eq 'FreeFileSync.exe') { $c.Visible = $ffs } }
}
function Get-OurTasks {
    return @(Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue | Sort-Object TaskName)
}

function Update-TaskList([string]$select) {
    $cboTask.Items.Clear()
    [void]$cboTask.Items.Add($NewTaskText)
    foreach ($t in Get-OurTasks) {
        [void]$cboTask.Items.Add($t.TaskName)
        foreach ($a in $t.Actions) { Add-ScriptChoice (Get-ScriptFromAction $a) }
    }
    if ($select -and $cboTask.Items.Contains($select)) { $cboTask.SelectedItem = $select } else { $cboTask.SelectedIndex = 0 }
}

function Update-FreqUi {
    $f = [string]$cboFreq.SelectedItem
    $hasStart = $f -ne $FreqLogon
    $lblStart.Visible = $hasStart; $dtDate.Visible = $hasStart; $dtTime.Visible = $hasStart
    $repeat = $f -in $FreqDaily, $FreqWeekly, $FreqHours
    $lblEvery.Visible = $repeat; $numEvery.Visible = $repeat; $lblUnit.Visible = $repeat
    $lblUnit.Text = switch ($f) { $FreqDaily { 'day(s)' } $FreqWeekly { 'week(s)' } $FreqHours { 'hour(s)' } default { '' } }
    $numEvery.Maximum = if ($f -eq $FreqHours) { 23 } else { 365 }
    $pnlDays.Visible = $f -eq $FreqWeekly
}
$cboFreq.add_SelectedIndexChanged({ Update-FreqUi })
$cboType.add_SelectedIndexChanged({ Update-TypeUi })

function Reset-TaskForm {
    $txtName.Text = ''
    $cboType.SelectedItem = 'FreeFileSync'
    $cboFreq.SelectedItem = $FreqDaily
    $numEvery.Value = 1
    $dtDate.Value = [datetime]::Today
    $dtTime.Value = [datetime]::Today.AddHours(2)
    foreach ($cb in $dayBoxes) { $cb.Checked = $false }
    $chkMissed.Checked = $true
    $cboLimit.SelectedItem = '4 hours'
    $txtExe.Text = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
    $btnSave.Text = 'Create Task'; $btnDelete.Enabled = $false; $btnRun.Enabled = $false
    $lblStatus.Text = ''
}

function Read-TaskIntoForm([string]$name) {
    $t = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $name -ErrorAction Stop
    Reset-TaskForm
    $txtName.Text = $t.TaskName
    $a = $t.Actions | Select-Object -First 1
    if ($a) { $sp = Get-ScriptFromAction $a; $cboType.SelectedItem = (Get-ScriptType $a.Execute $sp); if ($cboType.SelectedItem -eq 'FreeFileSync') { $txtExe.Text = $a.Execute }; $cboScript.Text = $sp }
    $tr = $t.Triggers | Select-Object -First 1
    if ($tr) {
        if ($tr.StartBoundary) {
            $start = [datetime]::Parse($tr.StartBoundary)
            $dtDate.Value = $start.Date; $dtTime.Value = [datetime]::Today + $start.TimeOfDay
        }
        switch ($tr.CimClass.CimClassName) {
            'MSFT_TaskDailyTrigger' { $cboFreq.SelectedItem = $FreqDaily; $numEvery.Value = [Math]::Max(1, $tr.DaysInterval) }
            'MSFT_TaskWeeklyTrigger' {
                $cboFreq.SelectedItem = $FreqWeekly; $numEvery.Value = [Math]::Max(1, $tr.WeeksInterval)
                $bits = @{ Sunday = 1; Monday = 2; Tuesday = 4; Wednesday = 8; Thursday = 16; Friday = 32; Saturday = 64 }
                foreach ($cb in $dayBoxes) { $cb.Checked = ($tr.DaysOfWeek -band $bits[$cb.Tag]) -ne 0 }
            }
            'MSFT_TaskLogonTrigger' { $cboFreq.SelectedItem = $FreqLogon }
            default {
                if ($tr.Repetition -and $tr.Repetition.Interval) {
                    $cboFreq.SelectedItem = $FreqHours
                    $h = [System.Xml.XmlConvert]::ToTimeSpan($tr.Repetition.Interval).TotalHours
                    $numEvery.Value = [Math]::Min(23, [Math]::Max(1, [int]$h))
                } else { $cboFreq.SelectedItem = $FreqOnce }
            }
        }
    }
    $chkMissed.Checked = [bool]$t.Settings.StartWhenAvailable
    $lim = [TimeSpan]::Zero
    if ($t.Settings.ExecutionTimeLimit) { $lim = [System.Xml.XmlConvert]::ToTimeSpan($t.Settings.ExecutionTimeLimit) }
    $cboLimit.SelectedItem = 'No limit'
    foreach ($k in $TimeLimits.Keys) { if ($TimeLimits[$k] -eq $lim) { $cboLimit.SelectedItem = $k } }
    $btnSave.Text = 'Save Changes'; $btnDelete.Enabled = $true; $btnRun.Enabled = $true
    $info = Get-ScheduledTaskInfo -TaskPath $TaskFolder -TaskName $name -ErrorAction SilentlyContinue
    if ($info -and $info.NextRunTime) { $lblStatus.Text = 'Next run: ' + $info.NextRunTime }
}

$cboTask.add_SelectedIndexChanged({
    try {
        if ($cboTask.SelectedItem -eq $NewTaskText) { Reset-TaskForm } else { Read-TaskIntoForm ([string]$cboTask.SelectedItem) }
    } catch { $lblStatus.Text = 'Could not read task: ' + $_.Exception.Message }
})

$btnScript.add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = if ([string]$cboType.SelectedItem -eq 'FreeFileSync') { 'FreeFileSync batch (*.ffs_batch)|*.ffs_batch|All files (*.*)|*.*' } else { 'Backup script (*.ps1;*.bat;*.cmd)|*.ps1;*.bat;*.cmd|All files (*.*)|*.*' }
    if ($ofd.ShowDialog() -eq 'OK') { Add-ScriptChoice $ofd.FileName; $cboScript.Text = $ofd.FileName }
    $ofd.Dispose()
})

$btnExe.add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'FreeFileSync.exe|FreeFileSync.exe|Programs (*.exe)|*.exe'
    if ($ofd.ShowDialog() -eq 'OK') { $txtExe.Text = $ofd.FileName }
    $ofd.Dispose()
})

$btnSave.add_Click({
    $msgTitle = 'Backup Script Builder'
    $name = ($txtName.Text.Trim() -replace '[\\/:*?"<>|]', '_')
    $script = $cboScript.Text.Trim().Trim('"')
    $exe = $txtExe.Text.Trim().Trim('"')
    if (-not $name) { [void][System.Windows.Forms.MessageBox]::Show('Give the task a name.', $msgTitle, 'OK', 'Warning'); return }
    $kind = [string]$cboType.SelectedItem
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { [void][System.Windows.Forms.MessageBox]::Show('Pick a backup script that exists (' + $(if ($kind -eq 'FreeFileSync') { '.ffs_batch' } else { '.ps1 or .bat' }) + ').', $msgTitle, 'OK', 'Warning'); return }
    if ($kind -ne 'FreeFileSync' -and $script -notmatch '\.(ps1|bat|cmd)$') { [void][System.Windows.Forms.MessageBox]::Show('A Robocopy or Xcopy task runs a .ps1 or .bat script. Pick one, or change the backup type.', $msgTitle, 'OK', 'Warning'); return }
    if ($kind -eq 'FreeFileSync' -and -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        $a = [System.Windows.Forms.MessageBox]::Show("FreeFileSync was not found at:`r`n$exe`r`n`r`nCreate the task anyway?", $msgTitle, 'YesNo', 'Warning')
        if ($a -ne 'Yes') { return }
    }
    $editing = $cboTask.SelectedItem -ne $NewTaskText
    $oldName = [string]$cboTask.SelectedItem
    $exists = @(Get-OurTasks | Where-Object { $_.TaskName -ieq $name }).Count -gt 0
    if ($exists -and -not ($editing -and $oldName -ieq $name)) {
        $a = [System.Windows.Forms.MessageBox]::Show("A task named '$name' already exists.`r`nReplace it?", $msgTitle, 'YesNo', 'Question')
        if ($a -ne 'Yes') { return }
    }
    try {
        $at = $dtDate.Value.Date + $dtTime.Value.TimeOfDay
        $n = [int]$numEvery.Value
        switch ([string]$cboFreq.SelectedItem) {
            $FreqOnce   { $trigger = New-ScheduledTaskTrigger -Once -At $at }
            $FreqDaily  { $trigger = New-ScheduledTaskTrigger -Daily -At $at -DaysInterval $n }
            $FreqWeekly {
                $days = @($dayBoxes | Where-Object Checked | ForEach-Object { $_.Tag })
                if (-not $days) { [void][System.Windows.Forms.MessageBox]::Show('Tick at least one day of the week.', $msgTitle, 'OK', 'Warning'); return }
                $trigger = New-ScheduledTaskTrigger -Weekly -At $at -WeeksInterval $n -DaysOfWeek $days
            }
            $FreqHours  { $trigger = New-ScheduledTaskTrigger -Once -At $at -RepetitionInterval (New-TimeSpan -Hours $n) }
            $FreqLogon  { $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) }
        }
        if ($kind -eq 'FreeFileSync') { $action = New-ScheduledTaskAction -Execute $exe -Argument ('"' + $script + '"') }
        elseif ($script -like '*.ps1') { $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"') -WorkingDirectory (Split-Path $script) }
        else { $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c "' + $script + '"') -WorkingDirectory (Split-Path $script) }
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $TimeLimits[[string]$cboLimit.SelectedItem] -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $settings.StartWhenAvailable = $chkMissed.Checked
        [void](Register-ScheduledTask -TaskPath $TaskFolder -TaskName $name -Action $action -Trigger $trigger -Settings $settings `
            -Description ('Created by Backup Script Builder (' + $kind + ')') -Force -ErrorAction Stop)
        if ($editing -and $oldName -ine $name) {
            Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $oldName -Confirm:$false -ErrorAction SilentlyContinue
        }
        Update-TaskList $name
        [void][System.Windows.Forms.MessageBox]::Show("Task '$name' saved.`r`n(Task Scheduler folder: $TaskFolder)", $msgTitle, 'OK', 'Information')
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("Could not save the task:`r`n" + $_.Exception.Message, $msgTitle, 'OK', 'Error')
    }
})

$btnDelete.add_Click({
    $name = [string]$cboTask.SelectedItem
    if ($name -eq $NewTaskText) { return }
    $a = [System.Windows.Forms.MessageBox]::Show("Delete the scheduled task '$name'?`r`n(The backup script and backups are not touched.)", 'Backup Script Builder', 'YesNo', 'Warning')
    if ($a -ne 'Yes') { return }
    try {
        Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $name -Confirm:$false -ErrorAction Stop
        Update-TaskList
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("Could not delete the task:`r`n" + $_.Exception.Message, 'Backup Script Builder', 'OK', 'Error')
    }
})

$btnRun.add_Click({
    $name = [string]$cboTask.SelectedItem
    if ($name -eq $NewTaskText) { return }
    try { Start-ScheduledTask -TaskPath $TaskFolder -TaskName $name -ErrorAction Stop; $lblStatus.Text = "Started '$name'." }
    catch { $lblStatus.Text = 'Could not start: ' + $_.Exception.Message }
})

Update-TaskList
Update-FreqUi
Update-TypeUi

Initialize-WrtWindow $form @($tabBuild, $tabSched) 600 600
[void]$form.ShowDialog()
