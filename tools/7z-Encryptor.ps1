# Version 1.5 (2026-11-26)
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
# Runs 7-Zip without a window while the window stays responsive; returns the exit code
function Invoke-7Zip([string]$exe, [string[]]$argList) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, ((@($argList) | ForEach-Object { ConvertTo-ProcessArg $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    try { while (-not $p.WaitForExit(100)) { [System.Windows.Forms.Application]::DoEvents() }; return $p.ExitCode } finally { $p.Dispose() }
}
# Encrypts, then tests the new archive with the password (7z t) so a broken file is never reported as done.
# Returns @{ Ok; Message; Output }. A failed archive is deleted.
function Invoke-Encrypt($o) {
    if (-not ($o.SevenZip -and [IO.File]::Exists($o.SevenZip))) { return @{ Ok = $false; Message = '7-Zip is not installed (7z.exe not found).' } }
    [void][IO.Directory]::CreateDirectory((Split-Path $o.Out))
    $rc = Invoke-7Zip $o.SevenZip (New-EncryptArgs $o.Out $o.Sources $o.Format $o.Password ($o.HideNames -ne $false) $(if ($o.ZipMethod) { $o.ZipMethod } else { 'ZipCrypto' }))
    if ($rc -ge 2 -or -not (Test-Path -LiteralPath $o.Out)) { Remove-Item -LiteralPath $o.Out -Force -ErrorAction SilentlyContinue; return @{ Ok = $false; Message = "7-Zip could not create the file (exit code $rc)."; Output = $o.Out } }
    $t = Invoke-7Zip $o.SevenZip @('t', "-p$($o.Password)", '--', $o.Out)
    if ($t -ne 0) { Remove-Item -LiteralPath $o.Out -Force -ErrorAction SilentlyContinue; return @{ Ok = $false; Message = "The new file did not pass 7-Zip's test (exit code $t) and was deleted."; Output = $o.Out } }
    $msg = if ($rc -eq 1) { 'Encrypted, but some files were skipped (in use or no access).' } else { 'Encrypted and tested.' }
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
$EncSettingTypes = @{ SaveFolder = [string]; EmailMode = [string]; EmailProgram = [string]; MailTo = [string]; Format = [string] }
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
    Add-Help $parent ($pt.X + 145) ($pt.Y) 'Remember settings' ("Off (the default): nothing is written anywhere. Your choices stay in use until you close the tool, then they are forgotten.`r`n`r`n" +
        "Ticked: the folder of your last encrypted file, 7z or zip, the email choice, the chosen mail program and the mailto: address are saved in 7z-Encryptor.settings.json next to the script, right away and whenever they change, so they travel with the folder (USB stick, share). Never a password, never the list of files. Items dropped on 7z-Encryptor.bat are still saved next to the first one.`r`n`r`n" +
        "Unticking it deletes that file. A damaged settings file is ignored and the tool starts with no memory.")
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
$EmailModes = 'Classic', 'Share', 'Program', 'Mailto'
# 1.4: a mailto: link (Windows opens the default mail program with the address filled in). A mailto: link cannot
# attach a file, so the file is also selected in Explorer to drag into the email. $null when the address is not usable.
function Get-MailtoUri([string]$to, [string]$file) {
    $to = ($to -replace ';', ',' -replace '\s', '' -replace ',{2,}', ',').Trim(',')
    if ($to -and $to -notmatch '^[^@,?&#"<>%]+@[^@,?&#"<>%]+(,[^@,?&#"<>%]+@[^@,?&#"<>%]+)*$') { return $null }
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
    if (-not ($file -and (Test-Path -LiteralPath $file))) { return "The encrypted file is not there any more:`r`n$file" }
    $name = Split-Path $file -Leaf
    if ($mode -eq 'Mailto') {
        $u = Get-MailtoUri $mailTo $file
        if (-not $u) { return "Type an email address for mailto: (several: separate them with ; ), or leave it empty." }
        try { Start-Process $u } catch { return "Windows has no mail program set for mailto: links.`r`n$($_.Exception.Message)" }
        Show-InFolder $file
        return "Your mail program opens a new email$(if ($mailTo.Trim()) { " to $($mailTo.Trim())" }).`r`n`r`nA mailto: link cannot attach files: drag $name from the Explorer window that opened into the email."
    }
    if ($mode -eq 'Program') {
        if (-not ($program -and (Test-Path -LiteralPath $program))) { return 'Pick the mail program first (Choose program...).' }
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
function Add-Help($parent, [int]$x, [int]$y, [string]$title, [string]$text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = '?'; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size(24, 24)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $b.Tag = @($title, $text)
    $tip.SetToolTip($b, $text)
    $b.Add_Click({ [void][System.Windows.Forms.MessageBox]::Show([string]$this.Tag[1], [string]$this.Tag[0], 'OK', 'Information') })
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
    $u.Lbl = New-Ctl Label 'Format' "15,$y"; $u.Lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $u.Rb7z = New-Ctl RadioButton '7z (AES-256)' "15,$($y + 23)" '150,24'; $u.Rb7z.Checked = $true
    $u.RbZip = New-Ctl RadioButton 'zip' "175,$($y + 23)" '80,24'
    $u.Hide = New-Ctl CheckBox 'Full encryption: also hide the file names' "35,$($y + 52)"; $u.Hide.Checked = $true
    $u.ZipPanel = New-Object System.Windows.Forms.Panel; $u.ZipPanel.Location = "35,$($y + 50)"; $u.ZipPanel.Size = '420,28'; $u.ZipPanel.Visible = $false
    $u.RbCrypto = New-Ctl RadioButton 'Standard (opens in Windows)' '0,2' '200,24'; $u.RbCrypto.Checked = $true
    $u.RbAes = New-Ctl RadioButton 'AES-256 (needs 7-Zip)' '210,2' '200,24'
    $u.ZipPanel.Controls.AddRange(@($u.RbCrypto, $u.RbAes))
    $u.LblPw = New-Ctl Label 'Password:' "15,$($y + 90)"; $u.Pw = New-Ctl TextBox '' "125,$($y + 87)" '220,25'; $u.Pw.UseSystemPasswordChar = $true
    $u.LblPw2 = New-Ctl Label 'Type it again:' "15,$($y + 122)"; $u.Pw2 = New-Ctl TextBox '' "125,$($y + 119)" '220,25'; $u.Pw2.UseSystemPasswordChar = $true
    $u.Show = New-Ctl CheckBox 'Show' "355,$($y + 89)"
    $u.Show.Tag = $u; $u.Show.add_CheckedChanged({ $x = $this.Tag; $x.Pw.UseSystemPasswordChar = -not $this.Checked; $x.Pw2.UseSystemPasswordChar = -not $this.Checked })
    $u.Rb7z.Tag = $u; $u.Rb7z.add_CheckedChanged({ $x = $this.Tag; $x.Hide.Visible = $this.Checked; $x.ZipPanel.Visible = -not $this.Checked })
    $parent.Controls.AddRange(@($u.Lbl, $u.Rb7z, $u.RbZip, $u.Hide, $u.ZipPanel, $u.LblPw, $u.Pw, $u.LblPw2, $u.Pw2, $u.Show))
    Add-Help $parent 75 ($y - 3) 'Format' ("7z: 7-Zip's own format with AES-256, the strongest. 'Full encryption' also hides the file names, so nothing at all can be seen without the password (on by default).`r`n`r`n" +
        "zip: 'Standard' is the classic zip password (ZipCrypto): anyone can open it in Windows Explorer with the password, but it is weak and the file names stay visible. 'AES-256' is strong but needs 7-Zip, WinRAR or similar to open; file names stay visible.`r`n`r`n" +
        "There is no way to get the files back without the password: keep it somewhere safe. The originals are not changed or deleted.")
    Add-Help $parent 92 ($y + 87) 'Password' ("Type the password twice; both must match exactly. Upper and lower case count, and so does every space, also one at the start or the end.`r`n`r`n" +
        "7z: any characters (accents, other alphabets). zip: only English letters, digits, spaces and ordinary symbols, because 7-Zip refuses others in zip files. A double quote ("") cannot be used in either.`r`n`r`n" +
        "'Show' shows what you typed. The password is never saved, also not with 'Remember settings' ticked. There is no way to get the files back without it, and send it some other way than the encrypted file (phone, text message).")
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
    Add-Help $parent 170 ($y + 1) '7-Zip' ("7-Zip (free, open source) does the encrypting. The tool looks for it when it starts and offers to install it when it is missing.`r`n`r`n" +
        "Where it looks: the Program Files folders, the place 7-Zip's setup records and the PATH. In Windows PE (Hiren's BootCD PE 10 / 11 and others) also the X: and Y: drives, up to 3 folders deep.`r`n`r`n" +
        "'Install 7-Zip' runs  $WingetCmd`r`n'Update 7-Zip' runs  $WingetUpdateCmd`r`nin a console window (you may be asked to allow it). When winget finishes, the tool finds 7-Zip again by itself.")
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
    $w.LblOpt = New-Ctl Label '2. How to encrypt' '15,170'; $w.LblOpt.Font = $bold
    $p.Controls.AddRange(@($w.LblSrc, $w.List, $w.Add, $w.Remove, $w.LblOpt))
    $w.Opt = New-EncryptOptions $p 205
    $w.LblOut = New-Ctl Label '3. Save as' '15,360'; $w.LblOut.Font = $bold
    $w.Out = New-Ctl TextBox '' '15,383' '390,25'
    $w.Browse = New-Ctl Button 'Browse...' '415,381' '135,28'
    $w.Go = New-Ctl Button 'Encrypt' '15,422' '390,40'; $w.Go.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $w.Status = New-Ctl Label '' '15,468' '535,20'; $w.Status.ForeColor = [System.Drawing.Color]::DimGray; $w.Status.AutoEllipsis = $true
    $p.Controls.AddRange(@($w.LblOut, $w.Out, $w.Browse, $w.Go, $w.Status))
    # 1.2: after encrypting - show it, or send it by email in one of three ways (remembered)
    $w.ShowDir = New-Ctl Button 'Show in folder' '15,492' '135,28'; $w.ShowDir.Enabled = $false
    $w.Mail = New-Ctl Button 'Send by email' '160,492' '135,28'; $w.Mail.Enabled = $false
    $w.LblMail = New-Ctl Label 'Email with:' '15,531' '75,20'
    # their own panel: radio buttons in one container are one group, and the 7z / zip choice is on the page itself
    $w.MailPanel = New-Object System.Windows.Forms.Panel; $w.MailPanel.Location = '92,526'; $w.MailPanel.Size = '460,58'
    $w.RbClassic = New-Ctl RadioButton 'Send to > Mail recipient' '0,2' '175,24'
    $w.RbShare = New-Ctl RadioButton 'Windows Share' '178,2' '115,24'
    $w.RbProgram = New-Ctl RadioButton 'Choose program...' '296,2' '160,24'
    # 1.4: mailto: with the address typed here (typing in the box picks this option)
    $w.RbMailto = New-Ctl RadioButton 'mailto:' '0,32' '70,24'
    $w.MailTo = New-Ctl TextBox ([string]$script:Settings.MailTo) '72,31' '384,25'
    $w.MailPanel.Controls.AddRange(@($w.RbClassic, $w.RbShare, $w.RbProgram, $w.RbMailto, $w.MailTo))
    $mode = [string]$script:Settings.EmailMode; if ($EmailModes -notcontains $mode) { $mode = 'Classic' }
    switch ($mode) { 'Share' { $w.RbShare.Checked = $true } 'Program' { $w.RbProgram.Checked = $true } 'Mailto' { $w.RbMailto.Checked = $true } default { $w.RbClassic.Checked = $true } }
    if ($mode -eq 'Program' -and $script:Settings.EmailProgram) { $w.RbProgram.Text = 'Program: ' + [IO.Path]::GetFileNameWithoutExtension([string]$script:Settings.EmailProgram) }
    $p.Controls.AddRange(@($w.ShowDir, $w.Mail, $w.LblMail, $w.MailPanel))
    $script:MainUi = $w
    $w.Get7 = New-Get7Row $p 599 { $script:MainUi.Go.Enabled = [bool]$script:SevenZip }
    $w.Remember = New-RememberBox $p '15,632'
    $w.Go.Enabled = [bool]$script:SevenZip
    Add-Help $p 245 7 'Files and folders' "Tick files and folders in the tree ('Add Files/Folders'), drag them from Explorer onto this list, or drop them on 7z-Encryptor.bat to start with them in the list. 'Remove' takes the selected lines out (Ctrl / Shift + click to select several). An item already in the list is not added twice.`r`n`r`nEverything in the list goes into ONE encrypted file; folders keep their name and everything inside them. The originals are not changed or deleted."
    Add-Help $p 105 357 'Save as' "Where the encrypted file goes, named after the first item (or Encrypted-<date> for several items). Items dropped on 7z-Encryptor.bat are saved next to the first one. Otherwise, with 'Remember settings' ticked, the folder of your last encrypted file is remembered (in 7z-Encryptor.settings.json next to the script, so it travels with the folder) and used next time; until then it goes next to the first item. 'Browse...' picks another place or name.`r`n`r`nAn existing file is never overwritten: the name filled in skips taken names ('name (2)'), and a name you type that is taken is refused. It cannot be saved inside a folder that is being encrypted. A share needs the share folder: \\server\share\file.7z."
    Add-Help $p 305 494 'Show in folder / Send by email' ("After a file is encrypted: 'Show in folder' opens its folder with the file selected; 'Send by email' starts a new email with it, the way chosen below.`r`n`r`nEmail with (remembered when 'Remember settings' is ticked):`r`n- Send to > Mail recipient: the classic Windows way, the same as right-click > Send to > Mail recipient. Needs a classic mail program (Outlook classic, Thunderbird, ...). If there is none (for example only the new Outlook or webmail), the Windows Share window opens instead.`r`n- Windows Share: the Windows 10 / 11 Share window (mail apps, nearby sharing, ...).`r`n- Choose program...: a mail program you pick (Outlook and Thunderbird get the file attached; other programs are started with the file name).`r`n- mailto: Windows' own mailto: link. Your default mail program opens a new email to the address typed in the box, with the file name as the subject. Separate several addresses with a semicolon, or leave the box empty. A mailto: link cannot attach files, so the file is also selected in Explorer: drag it into the email.`r`n`r`nSend the password some other way (phone, text message), never in the same email.")

    $w.Add.add_Click({ $x = $script:MainUi; foreach ($q in (Show-FolderPicker $true)) { if (-not @($x.List.Items | Where-Object { $_ -ieq $q }).Count) { [void]$x.List.Items.Add($q) } }; Update-MainOut })
    $w.Remove.add_Click({ $x = $script:MainUi; foreach ($s in @($x.List.SelectedItems)) { $x.List.Items.Remove($s) }; Update-MainOut })
    # 1.5: files and folders dragged from Explorer onto the list are added (never twice, not the tool itself)
    $w.List.AllowDrop = $true
    $w.List.add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } else { $e.Effect = 'None' } })
    $w.List.add_DragDrop({ param($s, $e) [void](Add-MainDropped @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))) })
    $w.Out.add_KeyPress({ $script:MainUi.OutEdited = $true })
    # 1.5: 7z or zip is remembered too (with Remember settings ticked)
    if ([string]$script:Settings.Format -eq 'zip') { $w.Opt.RbZip.Checked = $true }
    $w.Opt.Rb7z.add_CheckedChanged({ Update-MainOut; if ($script:MainUi) { $script:Settings.Format = (Get-EncryptChoice $script:MainUi.Opt).Format; Save-EncSettings } })
    $w.Browse.add_Click({
        $x = $script:MainUi; $ext = (Get-EncryptChoice $x.Opt).Format
        $sd = New-Object System.Windows.Forms.SaveFileDialog; $sd.Filter = $(if ($ext -eq 'zip') { 'Zip file (*.zip)|*.zip' } else { '7z file (*.7z)|*.7z' }); $sd.OverwritePrompt = $false
        if ($x.Out.Text) { try { $sd.InitialDirectory = Split-Path $x.Out.Text; $sd.FileName = Split-Path $x.Out.Text -Leaf } catch {} }
        if ($sd.ShowDialog() -eq 'OK') { $x.Out.Text = $sd.FileName; $x.OutEdited = $true }
        $sd.Dispose()
    })
    $w.Go.add_Click({
        $x = $script:MainUi; $c = Get-EncryptChoice $x.Opt
        $src = @($x.List.Items | ForEach-Object { [string]$_ }); $out = $x.Out.Text.Trim().Trim('"')
        $bad = Test-EncryptInput $src $c.Password $x.Opt.Pw2.Text $out $c.Format
        if ($bad) { [void][System.Windows.Forms.MessageBox]::Show($bad, '7z-Encryptor', 'OK', 'Warning'); return }
        $x.Go.Enabled = $false; $x.Form.Cursor = 'WaitCursor'; $x.Status.Text = 'Encrypting...'
        try { $r = Invoke-Encrypt (@{ SevenZip = $script:SevenZip; Sources = $src; Out = $out } + $c) } finally { $x.Go.Enabled = $true; $x.Form.Cursor = 'Default' }
        $x.Status.Text = $r.Message
        if ($r.Ok) {
            $x.LastOut = $r.Output; $x.ShowDir.Enabled = $true; $x.Mail.Enabled = $true
            $script:Settings.SaveFolder = Split-Path $r.Output; Save-EncSettings
            $x.OutEdited = $false; Update-MainOut
            $x.Status.Text = "$($r.Message) $(Split-Path $r.Output -Leaf) - use Show in folder or Send by email below."
        } else { Show-EncryptResult $r }
    })
    $w.ShowDir.add_Click({ $x = $script:MainUi; if ($x.LastOut) { Show-InFolder $x.LastOut } })
    $w.Mail.add_Click({
        $x = $script:MainUi
        $m = Send-EncryptedFile $x.LastOut (Get-MainEmailMode) ([string]$script:Settings.EmailProgram) $x.Form.Handle $x.MailTo.Text
        if ($m) { [void][System.Windows.Forms.MessageBox]::Show($m, '7z-Encryptor', 'OK', 'Information') }
    })
    foreach ($rb in $w.RbClassic, $w.RbShare, $w.RbProgram, $w.RbMailto) { $rb.add_Click({ Set-MainEmailMode $this }) }
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
function Get-MainEmailMode { $x = $script:MainUi; if ($x.RbShare.Checked) { 'Share' } elseif ($x.RbProgram.Checked) { 'Program' } elseif ($x.RbMailto.Checked) { 'Mailto' } else { 'Classic' } }
# a click on an email option: remember it; "Choose program..." asks for the program (Cancel keeps the old choice)
function Set-MainEmailMode($rb) {
    $x = $script:MainUi
    if ($rb -eq $x.RbProgram) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog; $ofd.Title = 'Pick your mail program'; $ofd.Filter = 'Programs (*.exe)|*.exe'
        if ($script:Settings.EmailProgram) { try { $ofd.InitialDirectory = Split-Path ([string]$script:Settings.EmailProgram) } catch {} } else { $ofd.InitialDirectory = ${env:ProgramFiles} }
        $ok = $ofd.ShowDialog() -eq 'OK'; if ($ok) { $script:Settings.EmailProgram = $ofd.FileName }; $ofd.Dispose()
        if (-not $ok -and -not $script:Settings.EmailProgram) {
            switch ([string]$script:Settings.EmailMode) { 'Share' { $x.RbShare.Checked = $true } 'Mailto' { $x.RbMailto.Checked = $true } default { $x.RbClassic.Checked = $true } }; return
        }
    }
    $script:Settings.EmailMode = Get-MainEmailMode; $script:Settings.MailTo = $x.MailTo.Text.Trim(); Save-EncSettings
    if ($rb -eq $x.RbMailto -and -not $x.MailTo.Focused) { [void]$x.MailTo.Focus() }
    $x.RbProgram.Text = if ($x.RbProgram.Checked -and $script:Settings.EmailProgram) { 'Program: ' + [IO.Path]::GetFileNameWithoutExtension([string]$script:Settings.EmailProgram) } else { 'Choose program...' }
}
# Fills in "Save as" from the list and the format, until the user types or browses a name of their own
function Update-MainOut {
    $x = $script:MainUi; $ext = (Get-EncryptChoice $x.Opt).Format
    if ($x.OutEdited) { if ($x.Out.Text -match '\.(7z|zip)$') { $x.Out.Text = $x.Out.Text -replace '\.(7z|zip)$', ".$ext" }; return }
    $src = @($x.List.Items | ForEach-Object { [string]$_ })
    $x.Out.Text = if ($src.Count) { $first = $src[0].TrimEnd('\'); $dir = if ($first -match '^[A-Za-z]:$') { $first + '\' } else { Split-Path $first }; if (-not $x.Dropped -and $script:Settings.SaveFolder -and [IO.Directory]::Exists([string]$script:Settings.SaveFolder)) { $dir = [string]$script:Settings.SaveFolder }; Get-ArchivePath $src $dir $ext } else { '' }
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
