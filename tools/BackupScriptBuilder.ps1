# Version 1.0 (2026-11-22)
# Backup Script Builder - builds a FreeFileSync batch file (BackupScript.ffs_batch)
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

# ---------- folder picker (checkbox tree) ----------
function Add-DummyChild($node) { [void]$node.Nodes.Add((New-Object System.Windows.Forms.TreeNode '...')) }

function Expand-FolderNode($node) {
    if ($node.Nodes.Count -ne 1 -or $node.Nodes[0].Tag) { return }
    $node.Nodes.Clear()
    try {
        $dirs = [System.IO.Directory]::GetDirectories([string]$node.Tag) | Sort-Object
    } catch { return }
    foreach ($d in $dirs) {
        try {
            $di = New-Object System.IO.DirectoryInfo $d
            # skip junctions/symlinks (avoids loops like "Documents and Settings")
            if ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            $child = New-Object System.Windows.Forms.TreeNode $di.Name
            $child.Tag = $d
            if ($di.Attributes -band [System.IO.FileAttributes]::Hidden) { $child.ForeColor = [System.Drawing.Color]::Gray }
            Add-DummyChild $child
            [void]$node.Nodes.Add($child)
        } catch { }
    }
}

function Get-CheckedPaths($nodes, $list) {
    foreach ($n in $nodes) {
        if ($n.Checked -and $n.Tag) { $list.Add([string]$n.Tag) }
        elseif ($n.Nodes.Count) { Get-CheckedPaths $n.Nodes $list }
    }
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

    foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $drv.IsReady) { continue }
        $label = $drv.Name.TrimEnd('\')
        if ($drv.VolumeLabel) { $label += '  (' + $drv.VolumeLabel + ')' }
        $root = New-Object System.Windows.Forms.TreeNode $label
        $root.Tag = $drv.Name
        Add-DummyChild $root
        [void]$tree.Nodes.Add($root)
    }
    # open C:\Users by default since that is where most backups come from
    foreach ($r in $tree.Nodes) {
        if ($r.Tag -eq 'C:\') {
            $r.Expand()
            foreach ($c in $r.Nodes) { if ($c.Text -eq 'Users') { $c.Expand(); $tree.SelectedNode = $c } }
        }
    }

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'; $panel.Height = 42; $panel.FlowDirection = 'RightToLeft'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.Width = 90; $cancel.DialogResult = 'Cancel'
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Add Checked'; $ok.Width = 110; $ok.DialogResult = 'OK'
    $panel.Controls.AddRange(@($cancel, $ok))
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $cancel

    $dlg.Controls.Add($tree)
    $dlg.Controls.Add($panel)

    $result = New-Object System.Collections.Generic.List[string]
    if ($dlg.ShowDialog() -eq 'OK') { Get-CheckedPaths $tree.Nodes $result }
    $dlg.Dispose()
    return ,$result
}

# ---------- main window ----------
$form = New-Object System.Windows.Forms.Form; Set-WrtScaling $form
$form.Text = 'Backup Script Builder'
$form.Size = New-Object System.Drawing.Size(580, 600)
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
$lblSrc.Location = '15,12'; $lblSrc.AutoSize = $true
$lblSrc.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

$lstSrc = New-Object System.Windows.Forms.ListBox
$lstSrc.Location = '15,35'; $lstSrc.Size = '400,200'
$lstSrc.SelectionMode = 'MultiExtended'
$lstSrc.HorizontalScrollbar = $true

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add Folders...'; $btnAdd.Location = '425,35'; $btnAdd.Size = '110,30'
$btnAdd.add_Click({
    foreach ($p in (Show-FolderPicker)) {
        if (-not $lstSrc.Items.Contains($p)) { [void]$lstSrc.Items.Add($p) }
    }
})

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = 'Remove'; $btnRemove.Location = '425,72'; $btnRemove.Size = '110,30'
$btnRemove.add_Click({
    $sel = @($lstSrc.SelectedItems)
    foreach ($s in $sel) { $lstSrc.Items.Remove($s) }
})

# 2. Destination folder
$lblDst = New-Object System.Windows.Forms.Label
$lblDst.Text = '2. Destination folder'
$lblDst.Location = '15,250'; $lblDst.AutoSize = $true
$lblDst.Font = $lblSrc.Font

$txtDest = New-Object System.Windows.Forms.TextBox
$txtDest.Location = '15,273'; $txtDest.Size = '400,25'

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'; $btnBrowse.Location = '425,271'; $btnBrowse.Size = '110,28'
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
$lblPreview.Location = '15,303'; $lblPreview.Size = '520,20'
$lblPreview.ForeColor = [System.Drawing.Color]::DimGray
$lblPreview.AutoEllipsis = $true
$txtDest.add_TextChanged({
    $r = Get-DestRoot
    if ($r) { $lblPreview.Text = 'Creates ' + $r + '\  (Current, Archive-Deleted, Logs)' } else { $lblPreview.Text = '' }
})

# 3. Keep days
$lblDays = New-Object System.Windows.Forms.Label
$lblDays.Text = '3. Keep deleted/changed files for (days)'
$lblDays.Location = '15,338'; $lblDays.AutoSize = $true
$lblDays.Font = $lblSrc.Font

$numDays = New-Object System.Windows.Forms.NumericUpDown
$numDays.Location = '15,361'; $numDays.Size = '100,25'
$numDays.Minimum = 1; $numDays.Maximum = 36500; $numDays.Value = 365

# 4. Build
$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = '4. Build Script'
$btnBuild.Location = '15,410'; $btnBuild.Size = '485,45'
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

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabBuild = New-Object System.Windows.Forms.TabPage 'Build Script'
$tabSched = New-Object System.Windows.Forms.TabPage 'Schedule Task'
$tabBuild.Controls.AddRange(@($lblSrc, $lstSrc, $btnAdd, $btnRemove, $lblDst, $txtDest, $btnBrowse, $lblPreview, $lblDays, $numDays, $btnBuild))
$tabs.TabPages.AddRange(@($tabBuild, $tabSched))
$form.Controls.Add($tabs)

$lnkFfs = New-Object System.Windows.Forms.LinkLabel
$lnkFfs.Dock = 'Bottom'; $lnkFfs.Height = 26; $lnkFfs.TextAlign = 'MiddleCenter'
$lnkFfs.Text = 'Made for FreeFileSync, the free open source sync tool: https://freefilesync.org/'
$lnkFfs.LinkArea = New-Object System.Windows.Forms.LinkArea($lnkFfs.Text.IndexOf('https'), 'https://freefilesync.org/'.Length)
$lnkFfs.add_LinkClicked({ Start-Process 'https://freefilesync.org/' })
$form.Controls.Add($lnkFfs)
$tabs.BringToFront()

Add-Help $tabBuild 140 9 'Source folders' ("The folders you want backed up. Click 'Add Folders...' and tick as many folders as you like in the tree (it opens at C:\Users).`r`n`r`n" +
    "Each folder becomes one folder pair in the FreeFileSync script: the folder (left side) is mirrored to Current\<folder name> (right side).`r`n`r`n" +
    "Two folders with the same name (for example two users' Documents) get -2, -3 ... so they do not overwrite each other. 'Remove' takes the selected folders off the list.")
Add-Help $tabBuild 165 247 'Destination folder' ("Where the backup lives. Usually a folder on an external or second drive, for example H:\.`r`n`r`n" +
    "The tool creates AutomaticFileBackups inside it (or uses the folder itself when it is already called AutomaticFileBackups) with:`r`n" +
    "  Current - the latest copy of every source folder`r`n  Archive-Deleted - files that were deleted or changed, in time-stamped folders`r`n  Logs - FreeFileSync's log of every run`r`n" +
    "and saves BackupScript.ffs_batch there.`r`n`r`nThe destination cannot be inside one of the source folders.")
Add-Help $tabBuild 290 335 'Keep days' ("How many days FreeFileSync keeps files in Archive-Deleted. When a file is deleted or changed in a source folder, the old copy is moved there instead of being thrown away.`r`n`r`n" +
    "Older archived copies are removed after this many days (the script's MaxAge). 365 = one year.")
Add-Help $tabBuild 510 420 'Build Script' ("Creates the folders and writes BackupScript.ffs_batch, a FreeFileSync batch job with your folders, destination and keep days.`r`n`r`n" +
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
[void](New-Lbl 'Backup script' '15,89' -Bold)
$cboScript = New-Object System.Windows.Forms.ComboBox
$cboScript.Location = '130,86'; $cboScript.Size = '255,25'
$btnScript = New-Object System.Windows.Forms.Button
$btnScript.Text = 'Browse...'; $btnScript.Location = '425,84'; $btnScript.Size = '110,28'

[void](New-Lbl 'FreeFileSync.exe' '15,126')
$txtExe = New-Object System.Windows.Forms.TextBox
$txtExe.Location = '130,123'; $txtExe.Size = '255,25'
$txtExe.Text = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$btnExe = New-Object System.Windows.Forms.Button
$btnExe.Text = 'Browse...'; $btnExe.Location = '425,121'; $btnExe.Size = '110,28'

# --- trigger ---
[void](New-Lbl 'Schedule' '15,170' -Bold)
$cboFreq = New-Object System.Windows.Forms.ComboBox
$cboFreq.Location = '130,167'; $cboFreq.Size = '130,25'; $cboFreq.DropDownStyle = 'DropDownList'
$cboFreq.Items.AddRange(@($FreqOnce, $FreqDaily, $FreqWeekly, $FreqHours, $FreqLogon))

$lblStart = New-Lbl 'Start' '15,207'
$dtDate = New-Object System.Windows.Forms.DateTimePicker
$dtDate.Location = '130,204'; $dtDate.Size = '150,25'; $dtDate.Format = 'Short'
$dtTime = New-Object System.Windows.Forms.DateTimePicker
$dtTime.Location = '290,204'; $dtTime.Size = '125,25'; $dtTime.Format = 'Time'; $dtTime.ShowUpDown = $true
$dtTime.Value = [datetime]::Today.AddHours(2)

$lblEvery = New-Lbl 'Repeat every' '15,244'
$numEvery = New-Object System.Windows.Forms.NumericUpDown
$numEvery.Location = '130,241'; $numEvery.Size = '70,25'; $numEvery.Minimum = 1; $numEvery.Maximum = 365
$lblUnit = New-Lbl 'days' '205,244'

$pnlDays = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlDays.Location = '128,272'; $pnlDays.Size = '410,28'
$dayBoxes = @()
foreach ($d in 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $d.Substring(0, 3); $cb.Tag = $d; $cb.AutoSize = $true
    $pnlDays.Controls.Add($cb); $dayBoxes += $cb
}

# --- settings ---
[void](New-Lbl 'Settings' '15,315' -Bold)
$chkMissed = New-Object System.Windows.Forms.CheckBox
$chkMissed.Text = 'Run as soon as possible after a missed start'
$chkMissed.Location = '130,313'; $chkMissed.AutoSize = $true; $chkMissed.Checked = $true

[void](New-Lbl 'Stop task after' '15,348')
$cboLimit = New-Object System.Windows.Forms.ComboBox
$cboLimit.Location = '130,345'; $cboLimit.Size = '130,25'; $cboLimit.DropDownStyle = 'DropDownList'
foreach ($k in $TimeLimits.Keys) { [void]$cboLimit.Items.Add($k) }
$cboLimit.SelectedItem = '4 hours'

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'Create Task'; $btnSave.Location = '15,400'; $btnSave.Size = '370,45'
$btnSave.Font = $btnBuild.Font
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run Now'; $btnRun.Location = '425,400'; $btnRun.Size = '110,45'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = '15,455'; $lblStatus.Size = '520,20'; $lblStatus.ForeColor = [System.Drawing.Color]::DimGray

$tabSched.Controls.AddRange(@($cboTask, $btnDelete, $txtName, $cboScript, $btnScript, $txtExe, $btnExe, $cboFreq,
    $dtDate, $dtTime, $numEvery, $pnlDays, $chkMissed, $cboLimit, $btnSave, $btnRun, $lblStatus))

Add-Help $tabSched 390 12 'Task' ("Pick <New task> to make a new scheduled backup, or one of the tasks this tool already made to change, run or delete it.`r`n`r`n" +
    "The tool keeps its tasks in their own Task Scheduler folder, \BackupScriptBuilder\, so it only ever lists and changes its own tasks. 'Delete Task' removes only the task, never the script or the backups.")
Add-Help $tabSched 425 49 'Task name' ("A name you will recognise, for example 'Nightly backup to H'. It is the task's name in Task Scheduler (folder \BackupScriptBuilder\).`r`n`r`nRenaming a task and saving replaces the old one.")
Add-Help $tabSched 390 86 'Backup script' ("The FreeFileSync batch file (.ffs_batch) the task runs. The script you built on the first tab is already in the list, as are the scripts your existing tasks use. 'Browse...' picks any other .ffs_batch file.")
Add-Help $tabSched 390 123 'FreeFileSync.exe' ("The task starts this program with the backup script as its argument. FreeFileSync is normally installed at C:\Program Files\FreeFileSync\FreeFileSync.exe.`r`n`r`nGet it free from https://freefilesync.org/ if it is not installed.")
Add-Help $tabSched 270 167 'Schedule' ("When the backup runs:`r`n  Once - one time, at the start date and time`r`n  Daily - every N days at that time`r`n  Weekly - on the ticked days, every N weeks`r`n" +
    "  Every X hours - from the start time, repeating every N hours`r`n  At log on - each time you sign in to Windows")
Add-Help $tabSched 425 204 'Start' ("The first date and the time of day the task runs. Daily and weekly tasks run at this time on every matching day.")
Add-Help $tabSched 270 241 'Repeat every' ("Daily: run every N days (1 = every day). Weekly: every N weeks on the ticked days. Every X hours: every N hours (1-23).")
Add-Help $tabSched 425 311 'Run after a missed start' ("When ticked, a backup that was missed because the PC was off or asleep runs as soon as possible afterwards.`r`n`r`nWhen not ticked, a missed run is skipped until the next scheduled time.")
Add-Help $tabSched 270 345 'Stop task after' ("Task Scheduler stops the backup if it is still running after this long, for example when a drive is stuck. Pick 'No limit' to never stop it.`r`n`r`nA first full backup of many files can take hours, so leave enough time.")
Add-Help $tabSched 390 410 'Create / Save, Run Now' ("Create Task (or Save Changes for an existing one) registers the task for your user account. It runs while you are logged on, with no password stored.`r`n`r`nRun Now starts the selected task straight away, to test it.")

# --- logic ---
function Add-ScriptChoice([string]$path) {
    if ($path -and -not $cboScript.Items.Contains($path)) { [void]$cboScript.Items.Add($path) }
}

function Get-OurTasks {
    return @(Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue | Sort-Object TaskName)
}

function Update-TaskList([string]$select) {
    $cboTask.Items.Clear()
    [void]$cboTask.Items.Add($NewTaskText)
    foreach ($t in Get-OurTasks) {
        [void]$cboTask.Items.Add($t.TaskName)
        foreach ($a in $t.Actions) { Add-ScriptChoice ($a.Arguments -replace '"', '') }
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

function Reset-TaskForm {
    $txtName.Text = ''
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
    if ($a) { $txtExe.Text = $a.Execute; $cboScript.Text = ($a.Arguments -replace '"', '') }
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
    $ofd.Filter = 'FreeFileSync batch (*.ffs_batch)|*.ffs_batch|All files (*.*)|*.*'
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
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { [void][System.Windows.Forms.MessageBox]::Show('Pick a backup script (.ffs_batch) that exists.', $msgTitle, 'OK', 'Warning'); return }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
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
        $action = New-ScheduledTaskAction -Execute $exe -Argument ('"' + $script + '"')
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $TimeLimits[[string]$cboLimit.SelectedItem] -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $settings.StartWhenAvailable = $chkMissed.Checked
        [void](Register-ScheduledTask -TaskPath $TaskFolder -TaskName $name -Action $action -Trigger $trigger -Settings $settings `
            -Description 'Created by Backup Script Builder' -Force -ErrorAction Stop)
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

Initialize-WrtWindow $form @() 580 600
[void]$form.ShowDialog()
