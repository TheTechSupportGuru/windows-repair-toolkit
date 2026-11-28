# Version 1.8 (2026-11-27)
# 7z-Encryptor - encrypts files and folders with 7-Zip: a 7z (AES-256, optionally the file names too) or a zip
# (standard ZipCrypto or AES-256), with a password you pick. Files dropped on 7z-Encryptor.bat open the same window, already in the list.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU General Public License v3 or (at your option) any later version, WITHOUT ANY WARRANTY. See LICENSE
# Needs 7-Zip (free, https://www.7-zip.org/); the window can install it with winget.
#   7z-Encryptor.ps1                 the window, empty
#   7z-Encryptor.ps1 <file> <file>   the same window with these items in the list, saved next to the first one
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)
$ScriptDir = $PSScriptRoot
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
Show-WrtSplash '7z-Encryptor'

# ---------- file / folder picker (the same as in Backup Script Builder 1.3) ----------
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
        # 1.3: Robocopy / Xcopy can also back up single files: list them after the folders
        if ($script:PickerFiles) { foreach ($fi in (Get-PickerFiles ([string]$node.Tag))) { [void]$node.Nodes.Add((New-FileNode $fi)) } }
    } finally { if ($tv) { $tv.EndUpdate() } }
}
# The files in one folder, sorted, without hidden system files (desktop.ini, thumbs.db ...); empty when it cannot be read
function Get-PickerFiles([string]$path) {
    try { $all = (New-Object System.IO.DirectoryInfo $path).GetFiles() } catch { return ,@() }
    $keep = @($all | Where-Object { -not (($_.Attributes -band [IO.FileAttributes]::Hidden) -and ($_.Attributes -band [IO.FileAttributes]::System)) })
    return ,@($keep | Sort-Object Name)
}
function New-FileNode([System.IO.FileInfo]$fi) {
    $n = New-Object System.Windows.Forms.TreeNode $fi.Name
    $n.Tag = $fi.FullName; $n.Name = 'file'; $n.ForeColor = [System.Drawing.Color]::DarkBlue
    return $n
}
$script:PickerFiles = $false
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

function Show-FolderPicker([bool]$Files = $false) {
    $script:PickerFiles = $Files
    $dlg = New-Object System.Windows.Forms.Form; Set-WrtScaling $dlg
    $dlg.Text = $(if ($Files) { 'Check the folders and files to back up' } else { 'Check the folders to back up' })
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


# ---------- 7-Zip (the same as in Backup Script Builder 1.8) ----------
# 7z.exe from the usual install folders, the path 7-Zip's setup writes to the registry or the PATH; in Windows PE
# (Hiren's BootCD PE 10 / 11 and others, 1.5) also X:\ and Y:\, up to 3 folders deep; $null when not found
function Test-WinPe { return (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') -or ($env:SystemDrive -eq 'X:') }
# The first 7z.exe in $root or up to $depth folders below it, shallowest first. Skips Windows, boot and system folders,
# and stops after $max folders so a big drive cannot hang the tool.
function Find-7ZipUnder([string]$root, [int]$depth = 3, [int]$max = 4000) {
    if (-not $root -or -not [IO.Directory]::Exists($root)) { return $null }
    $skip = '^(Windows|Boot|EFI|Recovery|sources|System Volume Information|\$.*)$'
    $level = @($root); $seen = 0
    for ($d = 0; $d -le $depth -and $level.Count; $d++) {
        $next = New-Object System.Collections.Generic.List[string]
        foreach ($dir in $level) {
            $f = Join-Path $dir '7z.exe'; if ([IO.File]::Exists($f)) { return $f }
            if ($d -eq $depth) { continue }
            try { $subs = [IO.Directory]::GetDirectories($dir) } catch { continue }
            foreach ($s in $subs) { if ([IO.Path]::GetFileName($s) -notmatch $skip -and ++$seen -le $max) { $next.Add($s) } }
        }
        $level = $next.ToArray()
    }
    return $null
}
function Find-7Zip([string[]]$peRoots = @('X:\', 'Y:\'), [bool]$isPe = (Test-WinPe)) {
    $c = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe", "$env:ProgramW6432\7-Zip\7z.exe")
    foreach ($k in 'HKLM:\SOFTWARE\7-Zip', 'HKCU:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\WOW6432Node\7-Zip') {
        $i = Get-ItemProperty $k -ErrorAction SilentlyContinue
        foreach ($v in @($i.Path64, $i.Path)) { if ($v) { $c += (Join-Path $v '7z.exe') } }
    }
    $c += @(Get-Command 7z.exe -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    foreach ($p in $c) { if ($p -and [IO.File]::Exists($p)) { return $p } }
    if ($isPe) { foreach ($r in $peRoots) { $f = Find-7ZipUnder $r; if ($f) { return $f } } }
    return $null
}
function ConvertTo-ProcessArg([string]$a) {
    if ($a -and $a -notmatch '[\s"]') { return $a }
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

# ---------- encryption with 7-Zip ----------
# 7-Zip arguments. 7z: AES-256 on the contents; $hideNames also encrypts the list of file names (full encryption).
# zip: 'ZipCrypto' = standard zip encryption (opens in Windows Explorer, but weak), 'AES256' = strong (needs 7-Zip,
# WinRAR or similar to open). The password goes to 7-Zip on its command line and is never written anywhere.
function New-EncryptArgs([string]$out, [string[]]$sources, [string]$format, [string]$password, [bool]$hideNames = $true, [string]$zipMethod = 'ZipCrypto') {
    $a = @('a', "-t$format", '-mx=5', '-y', '-ssw', "-p$password")
    if ($format -eq '7z') { if ($hideNames) { $a += '-mhe=on' } } else { $a += "-mem=$zipMethod" }
    $a += '--'; $a += $out; $a += $sources
    return , $a
}
# The name of a file or folder for showing and naming: C-Drive for a drive root, the share name for \\server\share
# (Split-Path 'C:' -Leaf would give the CURRENT folder on C:)
function Get-ItemName([string]$path) {
    $p = $path.Trim().TrimEnd('\')
    if ($p -match '^([A-Za-z]):$') { return $Matches[1].ToUpper() + '-Drive' }
    if ($p -match '^\\\\[^\\]+\\([^\\]+)$') { return $Matches[1] }
    return [IO.Path]::GetFileName($p)
}# Where the archive goes: <folder>\<name of the one item>.<ext>, or Encrypted-<date>.<ext> for several; never an existing file
function Get-ArchivePath([string[]]$sources, [string]$folder, [string]$ext) {
    $items = @($sources | Where-Object { $_ })
    $name = if ($items.Count -eq 1) { Get-ItemName $items[0] } else { 'Encrypted-' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') }
    if (-not $name) { $name = 'Encrypted' }
    $name = $name -replace '[\\/:*?"<>|]', '_'
    $p = Join-Path $folder "$name.$ext"; $n = 2
    while (Test-Path -LiteralPath $p) { $p = Join-Path $folder "$name ($n).$ext"; $n++ }
    return $p
}
# Checks before encrypting; returns the problem as text, or '' when it can go
function Test-EncryptInput([string[]]$sources, [string]$password, [string]$password2, [string]$out, [string]$format = '7z') {
    if (-not @($sources | Where-Object { $_ }).Count) { return 'Add at least one file or folder.' }
    foreach ($s in $sources) { if (-not (Test-Path -LiteralPath $s)) { return "Not found: $s" } }
    if (-not $password) { return 'Type a password.' }
    if ($password -cne $password2) { return 'The two passwords are not the same.' }
    if ($password -match '"') { return 'The password cannot contain a double quote (").' }
    if ($format -eq 'zip' -and $password -match '[^\x20-\x7E]') { return 'A zip password can only use English letters, digits, spaces and ordinary symbols (7-Zip refuses others in zip files). Use 7z for other characters.' }
    if (-not $out -or $out -notmatch '^([a-zA-Z]:\\|\\\\[^\\]+\\[^\\]+\\.)') { return 'Pick where to save the encrypted file (a full path).' }
    if (Test-Path -LiteralPath $out) { return "$out already exists. Pick another name." }
    foreach ($s in $sources) { if ($out -ieq $s) { return 'The encrypted file cannot replace one of the items.' } }
    # 1.4: not inside a folder that is being encrypted (7-Zip would pack the new file into itself)
    foreach ($s in $sources) { $d = $s.TrimEnd('\') + '\'; if ([IO.Directory]::Exists($s) -and $out.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) { return "The encrypted file cannot be saved inside $s, which is being encrypted. Pick another place (Browse...)." } }
    return ''
}
# Runs 7-Zip without a window while the window stays responsive; returns the exit code. 1.6: 7-Zip's own output is
# kept in $script:Last7zOutput (read in the background, so a long output cannot block 7-Zip), for its warnings.
function Invoke-7Zip([string]$exe, [string[]]$argList) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, ((@($argList) | ForEach-Object { ConvertTo-ProcessArg $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $script:Last7zOutput = ''
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
        while (-not $p.WaitForExit(100)) { [System.Windows.Forms.Application]::DoEvents() }
        $p.WaitForExit(); $script:Last7zOutput = [string]$se.Result + [string]$so.Result
        return $p.ExitCode
    } finally { $p.Dispose() }
}
# 1.6: the WARNING / ERROR lines of 7-Zip's output, each with the line after it (7-Zip writes the file name there),
# at most $max warnings
function Get-7ZipWarnings([string]$text, [int]$max = 5) {
    $all = @(($text -split "`r?`n") | ForEach-Object { $_.Trim() })
    $l = @(); for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -notmatch '^(WARNING|ERROR)\b') { continue }
        $w = $all[$i]; if ($i + 1 -lt $all.Count -and $all[$i + 1] -and $all[$i + 1] -notmatch '^(WARNING|ERROR)\b') { $w += ' ' + $all[$i + 1] }
        $l += $w
    }
    if ($l.Count -gt $max) { $l = @($l[0..($max - 1)]) + "... and $($l.Count - $max) more" }
    return ($l -join "`r`n")
}
# Encrypts, then tests the new archive with the password (7z t) so a broken file is never reported as done.
# Returns @{ Ok; Message; Output }. A failed archive is deleted.
function Invoke-Encrypt($o) {
    if (-not ($o.SevenZip -and [IO.File]::Exists($o.SevenZip))) { return @{ Ok = $false; Message = '7-Zip is not installed (7z.exe not found).' } }
    [void][IO.Directory]::CreateDirectory((Split-Path $o.Out))
    $rc = Invoke-7Zip $o.SevenZip (New-EncryptArgs $o.Out $o.Sources $o.Format $o.Password ($o.HideNames -ne $false) $(if ($o.ZipMethod) { $o.ZipMethod } else { 'ZipCrypto' }))
    $warn = Get-7ZipWarnings $script:Last7zOutput
    if ($rc -ge 2 -or -not (Test-Path -LiteralPath $o.Out)) { Remove-Item -LiteralPath $o.Out -Force -ErrorAction SilentlyContinue; return @{ Ok = $false; Message = "7-Zip could not create the file (exit code $rc)."; Output = $o.Out } }
    $t = Invoke-7Zip $o.SevenZip @('t', "-p$($o.Password)", '--', $o.Out)
    if ($t -ne 0) { Remove-Item -LiteralPath $o.Out -Force -ErrorAction SilentlyContinue; return @{ Ok = $false; Message = "The new file did not pass 7-Zip's test (exit code $t) and was deleted."; Output = $o.Out } }
    $msg = if ($rc -eq 1) { 'Encrypted, but some files were skipped (in use or no access).' + $(if ($warn) { "`r`n7-Zip says:`r`n$warn" }) } else { 'Encrypted and tested.' }
    return @{ Ok = ($rc -eq 0); Message = $msg; Output = $o.Out }
}

# ---------- remembered settings (1.2): 7z-Encryptor.settings.json next to this script ----------
# Kept in the tool's own folder, so a USB stick / WinPE kit / share keeps its settings wherever it runs. Only folders
# and choices are kept, never a password. A read-only folder just means nothing is remembered.
# WRT_SETTINGS_DIR puts the file somewhere else (the tests use it).
function Get-SettingsFile([string]$name) {
    $d = if ($env:WRT_SETTINGS_DIR) { $env:WRT_SETTINGS_DIR } else { $ScriptDir }
    if ($d) { Join-Path $d "$name.settings.json" }
}
# 1.3: nothing is remembered unless "Remember settings" is ticked (off at first). The file is only used when it says
# Remember = true; a damaged or odd file (bad JSON, wrong types) means no memory: the tool starts as if it had none.
$EncSettingTypes = @{ SaveMode = [string]; SaveName = [string]; SaveFolder = [string]; EmailMode = [string]; EmailProgram = [string]; MailTo = [string]; Format = [string] }
function Read-Settings([string]$name, [hashtable]$types) {
    $s = @{}
    try {
        $f = Get-SettingsFile $name
        if ($f -and [IO.File]::Exists($f)) {
            $o = [IO.File]::ReadAllText($f) | ConvertFrom-Json
            if ($o -is [PSCustomObject] -and $o.Remember -is [bool] -and $o.Remember) {
                $s.Remember = $true
                foreach ($k in $types.Keys) { $v = $o.$k; if ($null -ne $v -and $v -is $types[$k]) { $s[$k] = $v } }
            }
        }
    } catch { $s = @{} }
    $s
}
function Save-Settings([string]$name, $s) {
    try { $f = Get-SettingsFile $name; if ($f) { [IO.File]::WriteAllText($f, (New-Object PSObject -Property $s | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)) } } catch {}
}
function Remove-Settings([string]$name) { try { $f = Get-SettingsFile $name; if ($f -and [IO.File]::Exists($f)) { [IO.File]::Delete($f) } } catch {} }
$script:Settings = Read-Settings '7z-Encryptor' $EncSettingTypes
function Save-EncSettings { if ($script:Settings.Remember) { Save-Settings '7z-Encryptor' $script:Settings } }
# the "Remember settings" box: ticked saves what is chosen now, unticked deletes the file. The choices
# stay in use until the tool closes either way.
function Set-EncRemember([bool]$on) {
    if ($on) {
        $script:Settings.Remember = $true
        if ($script:MainUi) { $script:Settings.EmailMode = Get-MainEmailMode; $script:Settings.MailTo = $script:MainUi.MailTo.Text.Trim(); $script:Settings.Format = (Get-EncryptChoice $script:MainUi.Opt).Format }
        Save-EncSettings
    } else { $script:Settings.Remember = $false; Remove-Settings '7z-Encryptor' }
}
function New-RememberBox($parent, [string]$loc) {
    $c = New-Ctl CheckBox 'Remember settings' $loc '140,24'; $c.Checked = [bool]$script:Settings.Remember
    $c.add_CheckedChanged({ Set-EncRemember $this.Checked }); $parent.Controls.Add($c)
    $t = New-Object System.Windows.Forms.ToolTip; $t.SetToolTip($c, 'Off: nothing is saved. On: the save folder, 7z or zip, email choice and mailto: address are kept in 7z-Encryptor.settings.json next to the script (never a password). Untick to delete that file.')
    $pt = [Drawing.Point]$loc
    Add-Help $parent 170 ($pt.Y) 'Remember settings' ("## Off (the default)`r`nNothing is saved. Your choices are forgotten when you close the tool.`r`n`r`n## On`r`nYour last folder, 7z or zip, the email choice, the mail program and the mailto: address are saved in 7z-Encryptor.settings.json next to the script. Never a password.`r`n`r`n## Turning it off`r`nUnticking it deletes that file.")
    $c
}

# ---------- send the encrypted file by email (1.2) ----------
# Classic: the same Simple MAPI call as Explorer's Send to > Mail recipient (Outlook classic, Thunderbird, ...).
# Share: the Windows 10 / 11 Share window. Program: a mail program the user picked, with the file attached.
if (-not ('WrtMapi' -as [type])) {
    Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class WrtMapi {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)] public class Msg { public int reserved; public string subject; public string noteText; public string messageType; public string dateReceived; public string conversationID; public int flags; public IntPtr originator; public int recipCount; public IntPtr recips; public int fileCount; public IntPtr files; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)] public class FileDesc { public int reserved; public int flags; public int position; public string path; public string name; public IntPtr type; }
    [DllImport("MAPI32.DLL", CharSet = CharSet.Ansi)] static extern int MAPISendMail(IntPtr session, IntPtr hwnd, Msg message, int flags, int reserved);
    public static int Send(string path, string name, string subject, IntPtr hwnd) {
        FileDesc fd = new FileDesc(); fd.position = -1; fd.path = path; fd.name = name;
        IntPtr p = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(FileDesc))); Marshal.StructureToPtr(fd, p, false);
        Msg m = new Msg(); m.subject = subject; m.noteText = ""; m.fileCount = 1; m.files = p;
        try { return MAPISendMail(IntPtr.Zero, hwnd, m, 0x9, 0); } finally { Marshal.DestroyStructure(p, typeof(FileDesc)); Marshal.FreeHGlobal(p); }
    }
}
"@
}
$EmailModes = 'Classic', 'Program', 'Mailto'   # 1.7: no 'Share' option any more (a remembered one becomes Classic)
# 1.4: a mailto: link (Windows opens the default mail program with the address filled in). A mailto: link cannot
# attach a file, so the file is also selected in Explorer to drag into the email. $null when the address is not usable.
function Get-MailtoUri([string]$to, [string]$file) {
    $to = ($to -replace ';', ',' -replace '\s', '' -replace ',{2,}', ',').Trim(',')
    if ($to -and $to -notmatch '^[^@,?&#"<>%]+@[^@,?&#"<>%]+(,[^@,?&#"<>%]+@[^@,?&#"<>%]+)*$') { return $null }
    if (-not $file) { return 'mailto:' + $to }   # 1.7: no file yet - just a new email
    $name = Split-Path $file -Leaf
    return 'mailto:' + $to + '?subject=' + [Uri]::EscapeDataString($name) + '&body=' + [Uri]::EscapeDataString("Attached: $name (encrypted). The password comes separately.")
}
# the command line for a picked mail program: Outlook and Thunderbird attach with their own switches
function Get-MailProgramArgs([string]$exe, [string]$file) {
    switch -regex ((Split-Path $exe -Leaf).ToLower()) {
        '^outlook\.exe$' { return '/a "' + $file + '"' }
        '^thunderbird\.exe$' { return '-compose "attachment=''' + ([Uri]$file).AbsoluteUri + '''"' }
        default { return '"' + $file + '"' }
    }
}
# ---------- 1.7: change the default mailto: program / mail app ----------
function Confirm-ChangeDefault([string]$what) {
    return ([System.Windows.Forms.MessageBox]::Show("Are you sure you want to change your default $($what)?", '7z-Encryptor', 'YesNo', 'Warning') -eq 'Yes')
}
# Windows' own "pick an app for mailto:" prompt (with "Always"); Settings > Default apps where it is not there (PowerShell 7)
function Set-MailtoDefault {
    try {
        $null = [Windows.System.Launcher, Windows.System, ContentType = WindowsRuntime]
        $o = New-Object Windows.System.LauncherOptions; $o.DisplayApplicationPicker = $true
        $null = [Windows.System.Launcher]::LaunchUriAsync([Uri]'mailto:', $o); return
    } catch {}
    foreach ($t in 'ms-settings:defaultapps?registeredProtocol=mailto', 'ms-settings:defaultapps') { try { Start-Process $t -ErrorAction Stop; return } catch {} }
    [void][System.Windows.Forms.MessageBox]::Show('This Windows has no Default apps settings page (for example Windows PE).', '7z-Encryptor')
}
# The classic (Simple MAPI) mail programs Windows knows - the ones Attach (Send to) can use - and the one in use.
# The user's choice (HKCU) wins over the computer's (HKLM), so changing it needs no administrator.
$MailClientRoots = 'HKLM:\SOFTWARE\Clients\Mail', 'HKLM:\SOFTWARE\WOW6432Node\Clients\Mail', 'HKCU:\Software\Clients\Mail'
function Get-MailClients([string[]]$roots = $MailClientRoots) {
    $n = foreach ($r in $roots) { if (Test-Path $r) { Get-ChildItem $r -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -notmatch '^(Hotmail|None)$' } | ForEach-Object { $_.PSChildName } } }
    return @($n | Sort-Object -Unique)   # nothing installed: nothing returned
}
function Get-MailClientInUse([string[]]$roots = $MailClientRoots) {
    foreach ($r in @($roots[-1]) + @($roots[0..($roots.Count - 2)])) { try { $v = (Get-Item $r -ErrorAction Stop).GetValue(''); if ($v) { return [string]$v } } catch {} }
    return ''
}
function Set-MailClient([string]$name, [string]$key = 'HKCU:\Software\Clients\Mail') {
    if (-not (Test-Path $key)) { [void](New-Item $key -Force) }
    Set-Item -Path $key -Value $name
}
function Show-MailAppPicker {
    $names = @(Get-MailClients)
    if (-not $names.Count) { [void][System.Windows.Forms.MessageBox]::Show("No classic mail program is installed (Outlook classic, Thunderbird, ...).`r`n`r`nThe new Outlook and webmail cannot be picked here: use mailto: or Windows Share instead.", '7z-Encryptor', 'OK', 'Information'); return }
    $cur = Get-MailClientInUse
    $d = New-Object System.Windows.Forms.Form; $d.Text = 'Default mail app'; $d.ClientSize = New-Object System.Drawing.Size(320, 220)
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'; $d.MinimizeBox = $false; $d.MaximizeBox = $false; $d.ShowInTaskbar = $false
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $l = New-Ctl Label 'Mail program for Attach (Send to):' '12,10'
    $lb = New-Ctl ListBox '' '12,32' '296,140'; foreach ($n in $names) { [void]$lb.Items.Add($n) }
    $lb.SelectedIndex = [Math]::Max(0, [array]::IndexOf([string[]]$names, $cur))
    $ok = New-Ctl Button 'OK' '152,182' '75,28'; $ok.DialogResult = 'OK'; $ca = New-Ctl Button 'Cancel' '233,182' '75,28'; $ca.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($l, $lb, $ok, $ca)); $d.AcceptButton = $ok; $d.CancelButton = $ca
    if ($d.ShowDialog() -eq 'OK' -and $lb.SelectedItem) {
        try { Set-MailClient ([string]$lb.SelectedItem); [void][System.Windows.Forms.MessageBox]::Show("Attach (Send to) now uses $($lb.SelectedItem).", '7z-Encryptor', 'OK', 'Information') }
        catch { [void][System.Windows.Forms.MessageBox]::Show("Could not change it:`r`n$($_.Exception.Message)", '7z-Encryptor', 'OK', 'Warning') }
    }
    $d.Dispose()
}
# ---------- 1.7: mail programs found on this PC (for Choose program:) ----------
# Outlook classic, Thunderbird and the new Outlook by their usual places and App Paths, plus every classic mail
# program registered with Windows (Clients\Mail). Quick: registry reads and a few fixed paths, no disk search.
$AppPathRoots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths'
function Get-ExeFromCommand([string]$cmd) {
    $cmd = [Environment]::ExpandEnvironmentVariables([string]$cmd).Trim()
    if ($cmd -match '^"([^"]+\.exe)"') { return $Matches[1] }
    if ($cmd -match '^(.+?\.exe)(\s|$)') { return $Matches[1] }
    return ''
}
function Find-MailPrograms([string[]]$pfDirs = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432), [string[]]$appPathRoots = $AppPathRoots, [string[]]$clientRoots = $MailClientRoots, [string]$winApps = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps' } else { '' })) {   # Windows PE has no LOCALAPPDATA
    $found = New-Object System.Collections.ArrayList; $seen = @{}
    $add = { param($name, $path) if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { $k = ([IO.Path]::GetFullPath($path)).ToLower(); if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; [void]$found.Add([pscustomobject]@{ Name = $name; Path = [IO.Path]::GetFullPath($path) }) } } }
    $appPath = { param($exe) foreach ($r in $appPathRoots) { try { $v = (Get-Item (Join-Path $r $exe) -ErrorAction Stop).GetValue(''); if ($v) { return (Get-ExeFromCommand ('"' + $v.Trim('"') + '"')) } } catch {} }; '' }
    $pf = @($pfDirs | Where-Object { $_ } | Select-Object -Unique)
    # Outlook classic
    & $add 'Outlook (classic)' (& $appPath 'OUTLOOK.EXE')
    foreach ($d in $pf) { foreach ($o in @(Get-ChildItem -Path (Join-Path $d 'Microsoft Office') -Filter OUTLOOK.EXE -Recurse -Depth 3 -ErrorAction SilentlyContinue)) { & $add 'Outlook (classic)' $o.FullName } }
    # Thunderbird
    & $add 'Thunderbird' (& $appPath 'thunderbird.exe')
    foreach ($d in $pf) { & $add 'Thunderbird' (Join-Path $d 'Mozilla Thunderbird\thunderbird.exe') }
    # the new Outlook (a Store app; its olk.exe alias)
    if ($winApps) { & $add 'Outlook (new)' (Join-Path $winApps 'olk.exe') }
    # every other classic mail program Windows knows
    foreach ($r in $clientRoots) {
        foreach ($k in @(Get-ChildItem $r -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -match '^(Hotmail|None)$') { continue }
            try { $c = (Get-Item (Join-Path $k.PSPath 'shell\open\command') -ErrorAction Stop).GetValue('') } catch { continue }
            & $add $k.PSChildName (Get-ExeFromCommand $c)
        }
    }
    return @($found)
}
# fills the Choose program: list - what was found, the remembered program, then Other...
function Update-MailProgList($w) {
    $w.MailProg.Items.Clear(); $w.MailProgItems = New-Object System.Collections.ArrayList
    foreach ($p in $w.MailProgs) { [void]$w.MailProgItems.Add($p) }
    $cur = [string]$script:Settings.EmailProgram
    if ($cur -and -not @($w.MailProgItems | Where-Object { $_.Path -ieq $cur }).Count) { [void]$w.MailProgItems.Add([pscustomobject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($cur); Path = $cur }) }
    foreach ($p in $w.MailProgItems) { [void]$w.MailProg.Items.Add($p.Name) }
    [void]$w.MailProg.Items.Add('Other...')
    $i = -1; for ($n = 0; $n -lt $w.MailProgItems.Count; $n++) { if ($w.MailProgItems[$n].Path -ieq $cur) { $i = $n } }
    $w.MailProg.SelectedIndex = $i
}
# a pick in the list: that program (Other... asks for one); Choose program: is ticked and it is remembered
function Select-MailProgram($x) {
    $i = $x.MailProg.SelectedIndex; if ($i -lt 0) { return }
    if ($i -ge $x.MailProgItems.Count) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog; $ofd.Title = 'Pick your mail program'; $ofd.Filter = 'Programs (*.exe)|*.exe'; $ofd.InitialDirectory = ${env:ProgramFiles}
        $ok = $ofd.ShowDialog() -eq 'OK'; $pick = $ofd.FileName; $ofd.Dispose()
        if (-not $ok) { Update-MailProgList $x; return }
        $script:Settings.EmailProgram = $pick; Update-MailProgList $x
    } else { $script:Settings.EmailProgram = $x.MailProgItems[$i].Path }
    $x.RbProgram.Checked = $true; Set-MainEmailMode $x.RbProgram
}
# a box that takes a path dragged from Explorer (toolkit 2.8); $onDrop gets the first dropped path
$script:PathDrops = @{}
function Enable-PathDrop($ctl, [scriptblock]$onDrop) {
    $script:PathDrops[$ctl] = $onDrop; $ctl.AllowDrop = $true
    $ctl.add_DragEnter({ param($s, $e) if ($s.Enabled -and $e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } else { $e.Effect = 'None' } })
    $ctl.add_DragDrop({ param($s, $e) $p = @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop) | Where-Object { $_ })[0]; if ($p) { try { & $script:PathDrops[$s] ([string]$p) } catch {} } })
}
function Get-DropFolder([string]$p) { if ([IO.Directory]::Exists($p)) { return $p.TrimEnd('\') } elseif ([IO.File]::Exists($p)) { return [IO.Path]::GetDirectoryName($p) } else { return '' } }
# the Save as box takes a drop: Folder mode the folder; File mode a .7z / .zip, or a folder plus the name already in the box
function Set-OutDropped([string]$p) {
    $x = $script:MainUi; $ext = (Get-EncryptChoice $x.Opt).Format
    if ($x.RbSaveDir.Checked) { $d = Get-DropFolder $p; if ($d) { $x.Out.Text = $d; $x.OutEdited = $true }; return }
    if ($p -match '\.(7z|zip)$' -and -not [IO.Directory]::Exists($p)) { $x.Out.Text = $p; $x.OutEdited = $true; return }
    $d = Get-DropFolder $p; if (-not $d) { return }
    $leaf = try { Split-Path $x.Out.Text.Trim().Trim('"') -Leaf } catch { '' }; if ($leaf -notmatch '\.(7z|zip)$') { $leaf = "Encrypted.$ext" }
    $x.Out.Text = Join-Path $d $leaf; $x.OutEdited = $true
}
function Show-InFolder([string]$file) { Start-Process explorer.exe "/select,`"$file`"" }
# Explorer's own Share verb (Windows 10 / 11); $false when this Windows has none
function Invoke-ShareWindow([string]$file) {
    try {
        $item = (New-Object -ComObject Shell.Application).Namespace((Split-Path $file)).ParseName((Split-Path $file -Leaf))
        $v = @($item.Verbs() | Where-Object { ($_.Name -replace '&', '') -match '^(Share|Teilen|Partager|Compartir|Condividi|Delen)$' }) | Select-Object -First 1
        if ($v) { $v.DoIt(); return $true }
        return $false
    } catch { return $false }
}
# returns '' when the mail / share window opened, else a message for the user
function Send-EncryptedFile([string]$file, [string]$mode, [string]$program, [IntPtr]$hwnd = [IntPtr]::Zero, [string]$mailTo = '') {
    if ($file -and -not (Test-Path -LiteralPath $file)) { return "The encrypted file is not there any more:`r`n$file" }
    if ($mode -eq 'Mailto') {
        $u = Get-MailtoUri $mailTo $file
        if (-not $u) { return "Type an email address for mailto: (several: separate them with ; ), or leave it empty." }
        try { Start-Process $u } catch { return "Windows has no mail program set for mailto: links.`r`n$($_.Exception.Message)" }
        # with no default mail program Windows asks which app to use (OpenWith.exe); opening Explorer now would
        # close that prompt, so wait until the user has picked (or closed it), up to 10 minutes
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 600) {
            if ($sw.Elapsed.TotalMilliseconds -gt 1500 -and -not (Get-Process -Name OpenWith -ErrorAction SilentlyContinue)) { break }
            [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200
        }
        if (-not $file) { return '' }   # 1.7: mailto: without an encrypted file just opens a new email
        $name = Split-Path $file -Leaf
        Show-InFolder $file
        return "Your mail program opens a new email$(if ($mailTo.Trim()) { " to $($mailTo.Trim())" }).`r`n`r`nA mailto: link cannot attach files: drag $name from the Explorer window that opened into the email."
    }
    if (-not $file) { return 'Encrypt a file first (only mailto: works without one).' }
    $name = Split-Path $file -Leaf
    if ($mode -eq 'Program') {
        if (-not ($program -and (Test-Path -LiteralPath $program))) { return 'Pick the mail program first (Choose program:).' }
        if ((Split-Path $program -Leaf) -ieq 'olk.exe') {
            try { Start-Process -FilePath $program } catch { return "Could not start $program`r`n$($_.Exception.Message)" }
            Show-InFolder $file; return "The new Outlook opens.`r`n`r`nIt cannot be given a file to attach: drag $name from the Explorer window that opened into a new email."
        }
        try { Start-Process -FilePath $program -ArgumentList (Get-MailProgramArgs $program $file); return '' } catch { return "Could not start $program`r`n$($_.Exception.Message)" }
    }
    if ($mode -eq 'Classic') {
        $rc = -1; try { $rc = [WrtMapi]::Send($file, $name, $name, $hwnd) } catch {}
        if ($rc -eq 0 -or $rc -eq 1) { return '' }      # 1 = the user closed the mail window
        # no classic mail program (for example only the new Outlook): fall back to the Windows Share window
        if (Invoke-ShareWindow $file) { return '' }
        Show-InFolder $file; return "No classic mail program answered (Send to > Mail recipient, MAPI error $rc), and this Windows has no Share window.`r`nThe file is selected in Explorer: attach it to an email yourself."
    }
    if (Invoke-ShareWindow $file) { return '' }
    Show-InFolder $file; return "This Windows has no Share window. The file is selected in Explorer: attach it to an email yourself."
}

# ---------- shared controls ----------
$WingetCmd = 'winget install -e --id 7zip.7zip'
$script:SevenZip = Find-7Zip
$tip = New-Object System.Windows.Forms.ToolTip; $tip.AutoPopDelay = 30000
# 1.7: help in its own window, "## " lines shown as bold titles with a blank line between sections
function Show-HelpBox([string]$title, [string]$text) {
    $f = New-Object System.Windows.Forms.Form; $f.Text = $title; $f.Size = New-Object System.Drawing.Size(520, 440)
    $f.StartPosition = 'CenterParent'; $f.MinimizeBox = $false; $f.MaximizeBox = $false; $f.ShowInTaskbar = $false
    $f.BackColor = [System.Drawing.SystemColors]::Window; $f.Padding = New-Object System.Windows.Forms.Padding(14, 12, 10, 8)
    $rt = New-Object System.Windows.Forms.RichTextBox; $rt.Dock = 'Fill'; $rt.ReadOnly = $true; $rt.BorderStyle = 'None'
    $rt.BackColor = [System.Drawing.SystemColors]::Window; $rt.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $rt.Width = 480; $rt.add_ContentsResized({ param($s, $e) $s.Tag = $e.NewRectangle.Height }); $null = $rt.Handle   # measures the text
    $bold = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    foreach ($l in ($text -split "\r?\n")) {
        if ($l.StartsWith('## ')) { $rt.SelectionFont = $bold; $rt.AppendText($l.Substring(3) + "`n") }
        else { $rt.SelectionFont = $rt.Font; $rt.AppendText($l + "`n") }
    }
    $rt.Select(0, 0)
    # tall enough for all the text (no scroll bar), but never taller than the screen
    $wa = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
    $f.ClientSize = New-Object System.Drawing.Size(504, [Math]::Min([int]$rt.Tag + 20 + 32 + 16, $wa.Height - 60))
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'OK'; $ok.Dock = 'Bottom'; $ok.Height = 32; $ok.DialogResult = 'OK'
    $f.Controls.AddRange(@($rt, $ok)); $f.AcceptButton = $ok; $f.CancelButton = $ok
    $f.Add_Shown({ $this.AcceptButton.Focus() })
    [void]$f.ShowDialog(); $f.Dispose()
}
function Add-Help($parent, [int]$x, [int]$y, [string]$title, [string]$text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = '?'; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size(24, 24)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $b.Tag = @($title, $text)
    $tip.SetToolTip($b, ($text -replace '## ', ''))
    $b.Add_Click({ Show-HelpBox ([string]$this.Tag[0]) ([string]$this.Tag[1]) })
    $parent.Controls.Add($b)
}
function New-Ctl([string]$type, [string]$text, [string]$loc, [string]$size) {
    $c = New-Object "System.Windows.Forms.$type"; if ($text) { $c.Text = $text }; $c.Location = $loc
    if ($size) { $c.Size = $size } elseif ($type -in 'Label', 'CheckBox', 'RadioButton') { $c.AutoSize = $true }
    return $c
}
# The "how to encrypt" block: format, what is hidden, password twice. Returns its controls.
function New-EncryptOptions($parent, [int]$y) {
    $u = @{}
    $u.Lbl = New-Ctl Label '' "155,$y" '0,0'; $u.Lbl.Visible = $false; $u.Lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $u.Rb7z = New-Ctl RadioButton '7z (AES-256)' "15,$($y + 25)" '105,24'; $u.Rb7z.Checked = $true
    $u.RbZip = New-Ctl RadioButton 'zip' "125,$($y + 25)" '50,24'
    $u.Hide = New-Ctl CheckBox 'Full encryption: also hide the file names' "190,$($y + 27)"; $u.Hide.Checked = $true
    $u.ZipPanel = New-Object System.Windows.Forms.Panel; $u.ZipPanel.Location = "190,$($y + 23)"; $u.ZipPanel.Size = '360,28'; $u.ZipPanel.Visible = $false
    $u.RbCrypto = New-Ctl RadioButton 'Standard (opens in Windows)' '0,2' '190,24'; $u.RbCrypto.Checked = $true
    $u.RbAes = New-Ctl RadioButton 'AES-256 (needs 7-Zip)' '192,2' '165,24'
    $u.ZipPanel.Controls.AddRange(@($u.RbCrypto, $u.RbAes))
    $u.LblPw = New-Ctl Label 'Password:' "15,$($y + 63)"; $u.Pw = New-Ctl TextBox '' "105,$($y + 60)" '380,25'; $u.Pw.UseSystemPasswordChar = $true
    $u.LblPw2 = New-Ctl Label 'Type it again:' "15,$($y + 95)"; $u.Pw2 = New-Ctl TextBox '' "105,$($y + 92)" '380,25'; $u.Pw2.UseSystemPasswordChar = $true
    $u.Show = New-Ctl CheckBox 'Show' "492,$($y + 94)"
    $u.Show.Tag = $u; $u.Show.add_CheckedChanged({ $x = $this.Tag; $x.Pw.UseSystemPasswordChar = -not $this.Checked; $x.Pw2.UseSystemPasswordChar = -not $this.Checked })
    $u.Rb7z.Tag = $u; $u.Rb7z.add_CheckedChanged({ $x = $this.Tag; $x.Hide.Visible = $this.Checked; $x.ZipPanel.Visible = -not $this.Checked })
    $parent.Controls.AddRange(@($u.Lbl, $u.Rb7z, $u.RbZip, $u.Hide, $u.ZipPanel, $u.LblPw, $u.Pw, $u.LblPw2, $u.Pw2, $u.Show))
    $px = $u.LblPw2.Right + 4; foreach ($b in $u.Pw, $u.Pw2) { $b.Left = $px; $b.Width = 485 - $px }   # 1.7: right after 'Type it again:' (measured in the window's font)
    Add-Help $parent 262 ($y - 3) 'Format' ("## 7z (recommended)`r`nThe strongest (AES-256). 'Full encryption' also hides the file names.`r`n`r`n## zip - Standard`r`nOpens in Windows Explorer with the password, but it is weak and the file names stay visible.`r`n`r`n## zip - AES-256`r`nStrong, but needs 7-Zip or WinRAR to open. The file names stay visible.`r`n`r`n## Keep the password safe`r`nWithout it the files cannot be recovered.")
    Add-Help $parent 492 ($y + 60) 'Password' ("## Type it twice`r`nBoth must match exactly. Upper and lower case count, and so does every space.`r`n`r`n## Allowed characters`r`n7z: any characters.`r`nzip: only English letters, digits and ordinary symbols.`r`nA double quote ("") cannot be used.`r`n`r`n## Never saved`r`nThe password is never saved. Send it separately from the file (phone, text message).")
    return $u
}
function Get-EncryptChoice($u) {
    return @{ Format = $(if ($u.RbZip.Checked) { 'zip' } else { '7z' }); HideNames = $u.Hide.Checked; ZipMethod = $(if ($u.RbAes.Checked) { 'AES256' } else { 'ZipCrypto' }); Password = $u.Pw.Text }
}
# The 7-Zip row: shows the winget command, installs or updates 7-Zip in a console window, then looks for it again
$WingetUpdateCmd = 'winget upgrade -e --id 7zip.7zip'
function Get-7ZipVersion { if ($script:SevenZip) { try { return [Diagnostics.FileVersionInfo]::GetVersionInfo($script:SevenZip).ProductVersion.Trim() } catch {} }; return '' }
function New-Get7Row($parent, [int]$y, $onFound) {
    $r = @{}
    $r.Lbl = New-Ctl Label '' "15,$($y + 4)" '150,20'; $r.Lbl.AutoEllipsis = $true
    $r.Box = New-Ctl TextBox $WingetCmd "200,$y" '320,25'; $r.Box.ReadOnly = $true
    $r.Btn = New-Ctl Button 'Install 7-Zip' "200,$($y + 31)" '155,28'
    $r.BtnUp = New-Ctl Button 'Update 7-Zip' "365,$($y + 31)" '155,28'
    $r.OnFound = $onFound; $r.Proc = $null
    $r.Timer = New-Object System.Windows.Forms.Timer; $r.Timer.Interval = 1000; $r.Timer.Tag = $r
    $r.Timer.add_Tick({ $x = $this.Tag; if ($x.Proc -and $x.Proc.HasExited) { $this.Stop(); $x.Proc = $null; $script:SevenZip = Find-7Zip; Update-Get7Row $x; & $x.OnFound } })
    $r.Btn.Tag = $r; $r.BtnUp.Tag = $r
    $r.Btn.add_Click({ Start-7ZipWinget $this.Tag 'install' })
    $r.BtnUp.add_Click({ Start-7ZipWinget $this.Tag 'upgrade' })
    $parent.Controls.AddRange(@($r.Lbl, $r.Box, $r.Btn, $r.BtnUp))
    Add-Help $parent 170 ($y + 1) '7-Zip' ("## What it is`r`n7-Zip (free) does the encrypting. The tool finds it by itself and offers to install it when it is missing.`r`n`r`n## Install / Update`r`n'Install 7-Zip' runs: $WingetCmd`r`n'Update 7-Zip' runs: $WingetUpdateCmd`r`n`r`n## Windows PE`r`nIn Hiren's BootCD PE it also looks on the X: and Y: drives.")
    Update-Get7Row $r
    return $r
}
# Runs winget (install or upgrade) in its own console window; the row's timer picks 7-Zip up when it is done
function Start-7ZipWinget($r, [string]$what) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { [void][System.Windows.Forms.MessageBox]::Show('winget (App Installer) is not on this PC. Download 7-Zip from https://www.7-zip.org/ instead.', '7-Zip', 'OK', 'Information'); return }
    $cmd = if ($what -eq 'upgrade') { $WingetUpdateCmd } else { $WingetCmd }
    $r.Box.Text = $cmd
    $r.Proc = Start-Process cmd.exe -ArgumentList '/c', "$cmd & echo. & pause" -PassThru
    $r.Btn.Enabled = $false; $r.BtnUp.Enabled = $false; $r.Lbl.Text = $(if ($what -eq 'upgrade') { 'Updating...' } else { 'Installing...' }); $r.Timer.Start()
}
function Update-Get7Row($r) {
    $busy = [bool]$r.Proc
    if ($script:SevenZip) { $v = Get-7ZipVersion; $r.Lbl.Text = '7-Zip ' + $(if ($v) { "$v " }) + 'installed'; $r.Lbl.ForeColor = [System.Drawing.Color]::DarkGreen; $r.Btn.Enabled = $false; $r.Btn.Text = 'Installed'; $r.BtnUp.Enabled = -not $busy }
    else { $r.Lbl.Text = '7-Zip is needed:'; $r.Lbl.ForeColor = [System.Drawing.Color]::DarkRed; $r.Btn.Enabled = -not $busy; $r.Btn.Text = 'Install 7-Zip'; $r.BtnUp.Enabled = $false }
}
# On start: when 7-Zip is missing, ask once whether to install it now
function Request-7ZipInstall($r) {
    if ($script:SevenZip) { return }
    if ([System.Windows.Forms.MessageBox]::Show("7-Zip is not installed. 7z-Encryptor needs it to encrypt.`r`n`r`nInstall it now with winget?`r`n  $WingetCmd", '7z-Encryptor', 'YesNo', 'Question') -eq 'Yes') { Start-7ZipWinget $r 'install' }
}function Show-EncryptResult($r) {
    if ($r.Ok) {
        if ([System.Windows.Forms.MessageBox]::Show("$($r.Message)`r`n$($r.Output)`r`n`r`nShow it in its folder?", '7z-Encryptor', 'YesNo', 'Information') -eq 'Yes') { Start-Process explorer.exe "/select,`"$($r.Output)`"" }
    } else { [void][System.Windows.Forms.MessageBox]::Show("$($r.Message)`r`n$($r.Output)", '7z-Encryptor', 'OK', 'Warning') }
}

# ---------- the window: pick files and folders (or drop them on 7z-Encryptor.bat), encrypt them into one archive ----------
# 1.4: one window for both ways of starting. Dropped items are put in the list and saved next to the first one.
function New-MainWindow([string[]]$items = @()) {
    $f = New-Object System.Windows.Forms.Form; Set-WrtScaling $f
    $f.Text = '7z-Encryptor'; $f.Size = New-Object System.Drawing.Size(580, 732); $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $p = New-Object System.Windows.Forms.Panel; $p.Dock = 'Fill'; $f.Controls.Add($p)
    $w = @{ Form = $f; Page = $p; OutEdited = $false; LastOut = ''; Dropped = [bool]@($items).Count }
    $bold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $w.LblSrc = New-Ctl Label '1. Files and folders to encrypt' '15,10'; $w.LblSrc.Font = $bold
    $w.List = New-Ctl ListBox '' '15,33' '390,130'; $w.List.SelectionMode = 'MultiExtended'; $w.List.HorizontalScrollbar = $true
    $w.Add = New-Ctl Button 'Add Files/Folders' '415,33' '135,30'
    $w.Remove = New-Ctl Button 'Remove' '415,70' '135,30'
    $w.LblOpt = New-Ctl Label '2. How to Encrypt : Format / File Type' '15,181'; $w.LblOpt.Font = $bold
    $p.Controls.AddRange(@($w.LblSrc, $w.List, $w.Add, $w.Remove, $w.LblOpt))
    $w.Opt = New-EncryptOptions $p 181
    $w.LblOut = New-Ctl Label '3. Save as' '15,316'; $w.LblOut.Font = $bold
    $w.RbSaveFile = New-Ctl RadioButton 'File' '0,2' '50,24'
    $w.RbSaveDir = New-Ctl RadioButton 'Folder: Named + Date' '52,2' '143,24'
    $w.SavePanel = New-Object System.Windows.Forms.Panel; $w.SavePanel.Location = '100,312'; $w.SavePanel.Size = '197,26'
    $w.SavePanel.Controls.AddRange(@($w.RbSaveFile, $w.RbSaveDir))
    $w.SaveName = New-Ctl TextBox $(if ($script:Settings.SaveName) { [string]$script:Settings.SaveName } else { 'Encrypted' }) '299,313' '206,25'
    if ([string]$script:Settings.SaveMode -eq 'Folder') { $w.RbSaveDir.Checked = $true } else { $w.RbSaveFile.Checked = $true }
    $p.Controls.AddRange(@($w.SavePanel, $w.SaveName))
    $w.Out = New-Ctl TextBox '' '15,344' '390,25'
    $w.Browse = New-Ctl Button 'Browse...' '415,342' '135,28'
    $w.Go = New-Ctl Button 'Encrypt' '15,380' '390,40'; $w.Go.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $w.Status = New-Ctl Label '' '15,424' '535,18'; $w.Status.ForeColor = [System.Drawing.Color]::DimGray; $w.Status.AutoEllipsis = $true
    $p.Controls.AddRange(@($w.LblOut, $w.Out, $w.Browse, $w.Go, $w.Status))
    # 1.2: after encrypting - show it, or send it by email in one of three ways (remembered)
    $w.ShowDir = New-Ctl Button 'Show in folder' '415,380' '135,40'; $w.ShowDir.Enabled = $false
    $w.Mail = New-Ctl Button 'Send by email' '15,522' '135,28'; $w.Mail.Enabled = $false
    $w.LblSend = New-Ctl Label '4. Send' '15,438'; $w.LblSend.Font = $bold; $p.Controls.Add($w.LblSend)
    $w.LblMail = New-Ctl Label 'Email with:' '15,465' '75,20'
    # their own panel: radio buttons in one container are one group, and the 7z / zip choice is on the page itself
    $w.MailPanel = New-Object System.Windows.Forms.Panel; $w.MailPanel.Location = '92,460'; $w.MailPanel.Size = '460,58'
    $w.RbClassic = New-Ctl RadioButton 'Attach (Send to)' '0,2' '125,24'
    # 1.7: Choose program: with a list of the mail programs found on this PC, and Other... to pick one yourself
    $w.RbProgram = New-Ctl RadioButton 'Choose program:' '128,2'
    $w.MailProg = New-Object System.Windows.Forms.ComboBox; $w.MailProg.DropDownStyle = 'DropDownList'; $w.MailProg.Location = '250,2'; $w.MailProg.Size = '206,24'
    $w.MailProgs = @(Find-MailPrograms); Update-MailProgList $w
    # 1.4: mailto: with the address typed here (typing in the box picks this option)
    $w.RbMailto = New-Ctl RadioButton 'mailto:' '0,32' '70,24'
    $w.MailTo = New-Ctl TextBox ([string]$script:Settings.MailTo) '72,31' '384,25'
    $w.MailPanel.Controls.AddRange(@($w.RbClassic, $w.RbProgram, $w.MailProg, $w.RbMailto, $w.MailTo))
    # 1.7: Change Default: mailto: (the program for mailto: links) and Email (the classic mail program that
    # Attach (Send to) uses) - each asks first
    $w.LblDefault = New-Ctl Label 'Change Default:' '160,528'
    $w.MailDefault = New-Ctl Button 'mailto:' '262,522' '75,28'
    $w.MailApp = New-Ctl Button 'Email' '342,522' '75,28'
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.SetToolTip($w.MailDefault, 'Change the program that opens mailto: links (choose Always)'); $tt.SetToolTip($w.MailApp, 'Change the mail program that Attach (Send to) uses')
    $w.MailDefault.add_Click({ if (Confirm-ChangeDefault 'mailto') { Set-MailtoDefault } })
    $w.MailApp.add_Click({ if (Confirm-ChangeDefault 'mail app') { Show-MailAppPicker } })
    $mode = [string]$script:Settings.EmailMode; if ($EmailModes -notcontains $mode) { $mode = 'Classic' }
    switch ($mode) { 'Program' { $w.RbProgram.Checked = $true } 'Mailto' { $w.RbMailto.Checked = $true } default { $w.RbClassic.Checked = $true } }
    $p.Controls.AddRange(@($w.ShowDir, $w.Mail, $w.LblMail, $w.MailPanel, $w.LblDefault, $w.MailDefault, $w.MailApp))
    $script:MainUi = $w
    $w.Get7 = New-Get7Row $p 590 { $script:MainUi.Go.Enabled = [bool]$script:SevenZip }
    $w.Remember = New-RememberBox $p '15,623'
    $w.Go.Enabled = [bool]$script:SevenZip
    Add-Help $p 245 7 'Files and folders' ("## Add`r`n'Add Files/Folders' picks them in a tree. You can also drag them from Explorer onto the list, or drop them on 7z-Encryptor.bat.`r`n`r`n## Remove`r`n'Remove' takes the selected lines out. Ctrl or Shift + click selects several.`r`n`r`n## What you get`r`nEverything in the list goes into ONE encrypted file. The originals are not changed.")
    Add-Help $p 512 314 'Save as' ("## File`r`nThe box below is the exact file it is saved as.`r`n`r`n## Folder: Named + Date`r`nThe box below is the folder. The file is named after the box on the right plus the date and time, for example Encrypted-11-27-26--14-05.7z (a second one in the same minute gets (2)).`r`n`r`n## Where it goes`r`nNext to the first item, named after it. Items dropped on 7z-Encryptor.bat are saved next to the first one. With 'Remember settings' ticked, your last folder is used.`r`n`r`n## Change it`r`n'Browse...' picks another place or name. On a network share use the share folder: \\server\share\file.7z`r`n`r`n## Never overwritten`r`nAn existing file is never overwritten; a free name like 'name (2)' is used. It cannot be saved inside a folder that is being encrypted.")
    Add-Help $p 305 494 'Show in folder / Send by email' ("## Show in folder`r`nOpens the folder with the encrypted file selected.`r`n`r`n## Send by email`r`nStarts a new email the way chosen below.`r`n`r`n## Attach (Send to)`r`nAttaches the file, like right-click > Send to > Mail recipient. Needs a classic mail program (Outlook classic, Thunderbird). If there is none, the Windows Share window opens instead.`r`n`r`n## Choose program:`r`nPick a mail program from the list (Outlook classic, Thunderbird, the new Outlook and others found on this PC), or Other... to pick one yourself. Outlook classic and Thunderbird get the file attached; the new Outlook just opens, with the file selected in Explorer to drag in.`r`n`r`n## mailto:`r`nOpens your default mail program to the address in the box (separate several with ;). A mailto: link cannot attach files: drag the file from the Explorer window into the email. Works even before anything is encrypted.`r`n`r`n## Change Default`r`n'mailto:' changes the program that opens mailto: links. 'Email' changes the classic mail program that Attach (Send to) uses. Both ask first.`r`n`r`n## The password`r`nSend it some other way, never in the same email.")

    # 1.7: a line between the sections (same spacing everywhere), each ? right after its heading, no empty space at the bottom
    foreach ($y in 171, 306, 428, 558) { $s = New-Object System.Windows.Forms.Label; $s.BorderStyle = 'Fixed3D'; $s.Location = "15,$y"; $s.Size = '535,2'; $p.Controls.Add($s) }
    $w.LblSet = New-Ctl Label '5. Settings and Install' '15,568'; $w.LblSet.Font = $bold; $p.Controls.Add($w.LblSet)
    # Save as: File and Folder: Named + Date at their real width, right after the heading; the name box takes the rest
    foreach ($rb in $w.RbSaveFile, $w.RbSaveDir) { $rb.AutoSize = $true }
    $w.RbSaveFile.Left = 0; $w.RbSaveDir.Left = $w.RbSaveFile.Right + 2
    $w.SavePanel.Left = $w.LblOut.Right + 6; $w.SavePanel.Width = $w.RbSaveDir.Right + 2
    $w.SaveName.Left = $w.SavePanel.Right + 2; $w.SaveName.Width = 508 - $w.SaveName.Left
    foreach ($pair in @(@($w.LblSrc, 'Files and folders'), @($w.LblOpt, 'Format'), @($w.LblSend, 'Show in folder / Send by email'))) {
        $q = @($p.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '?' -and $_.Tag[0] -eq $pair[1] })[0]
        $q.Location = New-Object System.Drawing.Point(($pair[0].Left + $pair[0].PreferredWidth + 4), ($pair[0].Top - 3))
    }
    # the status line sits on the 4. Send heading row, after its ? (no empty row under Encrypt)
    $sq = @($p.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '?' -and $_.Tag[0] -eq 'Show in folder / Send by email' })[0]
    $w.Status.Location = New-Object System.Drawing.Point(($sq.Right + 8), ($w.LblSend.Top + 1)); $w.Status.Width = 550 - $w.Status.Left
    $w.Form.ClientSize = New-Object System.Drawing.Size($w.Form.ClientSize.Width, ((@($p.Controls) | ForEach-Object { $_.Bottom } | Measure-Object -Maximum).Maximum + 12))   # same margin as the top
    $w.Add.add_Click({ $x = $script:MainUi; foreach ($q in (Show-FolderPicker $true)) { if (-not @($x.List.Items | Where-Object { $_ -ieq $q }).Count) { [void]$x.List.Items.Add($q) } }; Update-MainOut })
    $w.Remove.add_Click({ $x = $script:MainUi; foreach ($s in @($x.List.SelectedItems)) { $x.List.Items.Remove($s) }; Update-MainOut })
    # 1.5: files and folders dragged from Explorer onto the list are added (never twice, not the tool itself)
    $w.List.AllowDrop = $true
    $w.List.add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } else { $e.Effect = 'None' } })
    $w.List.add_DragDrop({ param($s, $e) [void](Add-MainDropped @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))) })
    $w.Out.add_KeyPress({ $script:MainUi.OutEdited = $true })
    Enable-PathDrop $w.Out { param($p) Set-OutDropped $p }
    # 1.5: 7z or zip is remembered too (with Remember settings ticked)
    if ([string]$script:Settings.Format -eq 'zip') { $w.Opt.RbZip.Checked = $true }
    $w.Opt.Rb7z.add_CheckedChanged({ Update-MainOut; if ($script:MainUi) { $script:Settings.Format = (Get-EncryptChoice $script:MainUi.Opt).Format; Save-EncSettings } })
    $w.RbSaveDir.add_CheckedChanged({
        $x = $script:MainUi; if (-not $x) { return }
        $o = $x.Out.Text.Trim().Trim('"')
        if ($x.RbSaveDir.Checked) { if ($o -match '\.(7z|zip)$') { $x.Out.Text = Split-Path $o } }
        else { $x.OutEdited = $false }
        Update-MainOut
        $script:Settings.SaveMode = $(if ($x.RbSaveDir.Checked) { 'Folder' } else { 'File' }); Save-EncSettings
    })
    $w.SaveName.add_TextChanged({ $x = $script:MainUi; if ($x -and -not $x.RbSaveDir.Checked) { $x.RbSaveDir.Checked = $true } })
    $w.SaveName.add_Leave({ $script:Settings.SaveName = $script:MainUi.SaveName.Text.Trim(); Save-EncSettings })
    $w.Browse.add_Click({
        $x = $script:MainUi; $ext = (Get-EncryptChoice $x.Opt).Format
        if ($x.RbSaveDir.Checked) {
            $fd = New-Object System.Windows.Forms.FolderBrowserDialog; $fd.Description = 'Folder for the encrypted file'
            if ($x.Out.Text -and [IO.Directory]::Exists($x.Out.Text)) { $fd.SelectedPath = $x.Out.Text }
            if ($fd.ShowDialog() -eq 'OK') { $x.Out.Text = $fd.SelectedPath; $x.OutEdited = $true }
            $fd.Dispose(); return
        }
        $sd = New-Object System.Windows.Forms.SaveFileDialog; $sd.Filter = $(if ($ext -eq 'zip') { 'Zip file (*.zip)|*.zip' } else { '7z file (*.7z)|*.7z' }); $sd.OverwritePrompt = $false
        if ($x.Out.Text) { try { $sd.InitialDirectory = Split-Path $x.Out.Text; $sd.FileName = Split-Path $x.Out.Text -Leaf } catch {} }
        if ($sd.ShowDialog() -eq 'OK') { $x.Out.Text = $sd.FileName; $x.OutEdited = $true }
        $sd.Dispose()
    })
    $w.Go.add_Click({
        $x = $script:MainUi; $c = Get-EncryptChoice $x.Opt
        $src = @($x.List.Items | ForEach-Object { [string]$_ }); $out = $x.Out.Text.Trim().Trim('"')
        if ($x.RbSaveDir.Checked -and $out) { $an = Get-AutoName $x.SaveName.Text $c.Format; $out = Get-FreePath (Join-Path $out $an) }   # 1.7
        $bad = Test-EncryptInput $src $c.Password $x.Opt.Pw2.Text $out $c.Format
        if ($bad) { [void][System.Windows.Forms.MessageBox]::Show($bad, '7z-Encryptor', 'OK', 'Warning'); return }
        $x.Go.Enabled = $false; $x.Form.Cursor = 'WaitCursor'; $x.Status.Text = 'Encrypting...'
        try { $r = Invoke-Encrypt (@{ SevenZip = $script:SevenZip; Sources = $src; Out = $out } + $c) } finally { $x.Go.Enabled = $true; $x.Form.Cursor = 'Default' }
        $x.Status.Text = $r.Message
        if ($r.Ok) {
            $x.LastOut = $r.Output; $x.ShowDir.Enabled = $true; $x.Mail.Enabled = $true
            $script:Settings.SaveFolder = Split-Path $r.Output; Save-EncSettings
            if (-not $x.RbSaveDir.Checked) { $x.OutEdited = $false }; Update-MainOut
            $x.Status.Text = "$($r.Message) $(Split-Path $r.Output -Leaf) - use Show in folder or Send by email below."
        } else { Show-EncryptResult $r }
    })
    $w.ShowDir.add_Click({ $x = $script:MainUi; if ($x.LastOut) { Show-InFolder $x.LastOut } })
    $w.Mail.add_Click({
        $x = $script:MainUi
        $m = Send-EncryptedFile $x.LastOut (Get-MainEmailMode) ([string]$script:Settings.EmailProgram) $x.Form.Handle $x.MailTo.Text
        if ($m) { [void][System.Windows.Forms.MessageBox]::Show($m, '7z-Encryptor', 'OK', 'Information') }
    })
    foreach ($rb in $w.RbClassic, $w.RbProgram, $w.RbMailto) { $rb.add_CheckedChanged({ $x = $script:MainUi; if ($x) { $x.Mail.Enabled = [bool]$x.LastOut -or $x.RbMailto.Checked } }); $rb.add_Click({ Set-MainEmailMode $this }) }
    $w.Mail.Enabled = $w.RbMailto.Checked   # 1.7: mailto: needs no encrypted file
    $w.MailProg.add_SelectionChangeCommitted({ Select-MailProgram $script:MainUi })
    $w.MailTo.add_TextChanged({ $x = $script:MainUi; if (-not $x.RbMailto.Checked) { $x.RbMailto.Checked = $true; Set-MainEmailMode $x.RbMailto } })
    $w.MailTo.add_Leave({ $script:Settings.MailTo = $script:MainUi.MailTo.Text.Trim(); Save-EncSettings })
    $f.Add_Shown({ Request-7ZipInstall $script:MainUi.Get7 })
    foreach ($i in @($items)) { if (-not @($w.List.Items | Where-Object { $_ -ieq $i }).Count) { [void]$w.List.Items.Add($i) } }
    Update-MainOut
    return $f
}
# Items dragged onto the main window's list: added like 'Add Files/Folders' does; missing ones and the tool's own
# files are skipped. Returns how many were added.
function Add-MainDropped([string[]]$paths) {
    $x = $script:MainUi; $n = 0
    foreach ($q in (Get-DroppedItems $paths)) {
        if (-not (Test-Path -LiteralPath $q)) { continue }
        if (-not @($x.List.Items | Where-Object { $_ -ieq $q }).Count) { [void]$x.List.Items.Add($q); $n++ }
    }
    if ($n) { Update-MainOut }
    return $n
}
function Get-MainEmailMode { $x = $script:MainUi; if ($x.RbProgram.Checked) { 'Program' } elseif ($x.RbMailto.Checked) { 'Mailto' } else { 'Classic' } }
# a click on an email option: remember it; "Choose program:" with nothing picked yet opens the list of mail programs
function Set-MainEmailMode($rb) {
    $x = $script:MainUi
    if ($rb -eq $x.RbProgram -and -not $script:Settings.EmailProgram) { $x.MailProg.DroppedDown = $true; return }   # 1.7: pick from the list
    $script:Settings.EmailMode = Get-MainEmailMode; $script:Settings.MailTo = $x.MailTo.Text.Trim(); Save-EncSettings
    if ($rb -eq $x.RbMailto -and -not $x.MailTo.Focused) { [void]$x.MailTo.Focus() }
}
# Fills in "Save as" from the list and the format, until the user types or browses a name of their own
# 1.7: "Folder: Named + Date": <name>-MM-dd-yy--HH-mm.<ext> in the folder. Characters Windows does not allow are dropped.
function Get-AutoName([string]$name, [string]$ext, [datetime]$when = (Get-Date)) {
    $n = ($name -replace '[\\/:*?"<>|]', '').Trim().TrimEnd('.'); if (-not $n) { $n = 'Encrypted' }
    return $n + '-' + $when.ToString('MM-dd-yy--HH-mm') + '.' + $ext
}
# 1.7: name (2), name (3) ... when the file is already there (two files in the same minute)
function Get-FreePath([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $path }
    $dir = Split-Path $path; $base = [IO.Path]::GetFileNameWithoutExtension($path); $ext = [IO.Path]::GetExtension($path)
    for ($n = 2; ; $n++) { $q = Join-Path $dir "$base ($n)$ext"; if (-not (Test-Path -LiteralPath $q)) { return $q } }
}
function Update-MainOut {
    $x = $script:MainUi; $ext = (Get-EncryptChoice $x.Opt).Format
    if ($x.RbSaveDir.Checked) { if (-not $x.OutEdited) { $src = @($x.List.Items | ForEach-Object { [string]$_ }); $x.Out.Text = if ($src.Count) { Split-Path (Get-MainDefaultOut $src $ext) } else { '' } }; return }
    if ($x.OutEdited) { if ($x.Out.Text -match '\.(7z|zip)$') { $x.Out.Text = $x.Out.Text -replace '\.(7z|zip)$', ".$ext" }; return }
    $src = @($x.List.Items | ForEach-Object { [string]$_ })
    $x.Out.Text = if ($src.Count) { Get-MainDefaultOut $src $ext } else { '' }
}
function Get-MainDefaultOut($src, [string]$ext) {
    $x = $script:MainUi; $first = $src[0].TrimEnd('\'); $dir = if ($first -match '^[A-Za-z]:$') { $first + '\' } else { Split-Path $first }; if (-not $x.Dropped -and $script:Settings.SaveFolder -and [IO.Directory]::Exists([string]$script:Settings.SaveFolder)) { $dir = [string]$script:Settings.SaveFolder }
    return Get-ArchivePath $src $dir $ext
}

# ---------- start ----------
# The items dropped on the launcher. The tool's own files (7z-Encryptor.ps1 dropped on 7z-Encryptor.bat) are left
# out, so dropping the script on its launcher just starts it.
function Get-DroppedItems([string[]]$files) {
    $own = @('7z-Encryptor.ps1', '7z-Encryptor.bat') | ForEach-Object { if ($ScriptDir) { Join-Path $ScriptDir $_ } }
    $full = { param($p) try { [IO.Path]::GetFullPath($p) } catch { $p } }
    return ,@($files | Where-Object { $_ } | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ } | Where-Object { $f = & $full $_; -not @($own | Where-Object { $_ -ieq $f }).Count })
}
# The items in cmd's own command line, as 7z-Encryptor.bat 1.1 passes it on (WRT_DROP_CMDLINE): everything after the
# launcher's path, split like Explorer wrote it (quoted when there is a space, else up to the next space). Keeps
# & ^ % ! in names that cmd would have cut up. $null when the launcher is not in the line.
function Get-LauncherItems([string]$cmdline, [string]$bat) {
    if (-not $cmdline -or -not $bat) { return $null }
    $i = $cmdline.IndexOf($bat, [StringComparison]::OrdinalIgnoreCase); $len = $bat.Length
    if ($i -lt 0) { $leaf = Split-Path $bat -Leaf; $i = $cmdline.IndexOf($leaf, [StringComparison]::OrdinalIgnoreCase); $len = $leaf.Length }
    if ($i -lt 0) { return $null }
    $rest = $cmdline.Substring($i + $len); if ($rest.StartsWith('"')) { $rest = $rest.Substring(1) }
    # cmd /c "<whole line>": the closing quote of the outer pair
    if ($cmdline -match '(?i)\s/[ck]\s*"' -and $rest.TrimEnd().EndsWith('"')) { $rest = $rest.TrimEnd(); $rest = $rest.Substring(0, $rest.Length - 1) }
    return ,@([regex]::Matches($rest, '"([^"]*)"|([^\s"]+)') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } } | Where-Object { $_.Trim() })
}
if ($env:WRT_DROP_CMDLINE) {
    $fromLine = Get-LauncherItems $env:WRT_DROP_CMDLINE $env:WRT_DROP_BAT
    if ($null -ne $fromLine) { $Files = $fromLine }
}
$env:WRT_DROP_CMDLINE = $null; $env:WRT_DROP_BAT = $null
$Files = Get-DroppedItems $Files
# if the window cannot be built with the remembered settings, it is built again with no memory (1.3)
try { $form = New-MainWindow $Files }
catch { if (-not $script:Settings.Count) { throw }; $script:Settings = @{}; $form = New-MainWindow $Files }
Initialize-WrtWindow $form @() 480 380
[void]$form.ShowDialog()
