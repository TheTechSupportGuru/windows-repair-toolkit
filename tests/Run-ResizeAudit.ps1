# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-ResizeAudit.ps1 - opens each GUI tool, sets its main window to a list of sizes, visits every tab at every size,
# and records layout problems:
#   OVERLAP   two visible controls in the same container overlap
#   CUT-OFF   a control lies (partly) outside its container and the container cannot scroll to it
#   TEXT      a button / label / check box text does not fit its control
#   MINSIZE   the window went smaller than its minimum (no hard stop), or the minimum is bigger than the screen
# Optional screenshots per size and tab. Runs WITHOUT admin: self-elevation is skipped and message boxes are recorded
# instead of shown, so nothing on the PC is changed. Works at any resolution - meant for 720p to 4K screens.
#
#   .\tests\Run-ResizeAudit.ps1                                   all tools, default sizes, report in %TEMP%\wrt-resize-audit
#   .\tests\Run-ResizeAudit.ps1 -Sizes 1280x680,2560x1400,max -Shots
#   .\tests\Run-ResizeAudit.ps1 -Scripts beta\WinSuperTool.ps1 -Scale 1.5     (simulated 150 % display)
# Size words: min (try 200x150: must stop at the minimum), max (maximized), 50% / 75% (of the screen's work area), WxH.
param(
    [string[]]$Scripts = @(),
    [string[]]$Sizes = @('min', '1280x680', '1366x728', '1600x860', '75%', 'max'),
    [string]$OutDir = (Join-Path $env:TEMP 'wrt-resize-audit'),
    [double]$Scale = 1.0,
    [switch]$Shots,
    [string]$Child = ''           # internal: run ONE tool and audit it
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

if (-not $Child) {
    if (-not $Scripts.Count) { $Scripts = @(Get-ChildItem (Join-Path $Root 'tools'), (Join-Path $Root 'beta') -Filter *.ps1 | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'Windows\.Forms\.Form' } | ForEach-Object { $_.FullName }) }
    Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $OutDir | Out-Null
    foreach ($s in $Scripts) {
        $full = (Resolve-Path $s).Path
        $tag = (Split-Path (Split-Path $full) -Leaf) + '-' + [IO.Path]::GetFileNameWithoutExtension($full)
        $args2 = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Child', "`"$full`"", '-OutDir', "`"$OutDir`"", '-Scale', $Scale, '-Sizes', ($Sizes -join ','))
        if ($Shots) { $args2 += '-Shots' }
        $p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList $args2 -RedirectStandardError (Join-Path $OutDir "$tag.stderr.txt")
        if (-not $p.WaitForExit(600000)) { $p | Stop-Process -Force; Add-Content (Join-Path $OutDir 'issues.csv') "`"$tag`",`"-`",`"-`",`"TIMEOUT`",`"the audit did not finish`"" }
    }
    $rows = @(if (Test-Path (Join-Path $OutDir 'issues.csv')) { Import-Csv (Join-Path $OutDir 'issues.csv') -Header Tool, Size, Tab, Kind, Detail })
    $sum = "Resize audit $(Get-Date)  scale=$Scale  screen=$([Windows.Forms.Screen]::PrimaryScreen.Bounds.Size) work area=$([Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Size)`r`n"
    $sum += "Sizes: $($Sizes -join ', ')`r`n`r`n"
    $sum += ($rows | Group-Object Tool | ForEach-Object { '{0,-36} {1,4} issue(s): {2}' -f $_.Name, $_.Count, (($_.Group | Group-Object Kind | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ') }) -join "`r`n"
    if (-not $rows.Count) { $sum += 'No issues found.' }
    $sum += "`r`n`r`nSizes actually reached:`r`n" + ((Get-Content (Join-Path $OutDir 'sizes.txt') -ErrorAction SilentlyContinue) -join "`r`n")
    [IO.File]::WriteAllText((Join-Path $OutDir 'summary.txt'), $sum)
    $sum
    return
}

# ===================== child: load ONE tool without admin, audit it =====================
# (the audit's own variables are named $WrtAudit* so the tool's variables - many tools use $tag, $Root, $Scale - cannot overwrite them)
$WrtAuditChild = $Child; $WrtAuditOutDir = $OutDir; $WrtAuditSizes = $Sizes; $WrtAuditShots = $Shots; $WrtAuditScale = $Scale
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$WrtAudittag = (Split-Path (Split-Path $WrtAuditChild) -Leaf) + '-' + [IO.Path]::GetFileNameWithoutExtension($WrtAuditChild)
$WrtAuditSizes = @($WrtAuditSizes | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
public static class WrtAuditBox {
    public static string LogPath;
    public static System.Windows.Forms.DialogResult Show(params object[] a) { System.IO.File.AppendAllText(LogPath, string.Join(" | ", a) + "\r\n"); return System.Windows.Forms.DialogResult.No; }
}
'@
# display-resolution switching for the "res:WxH" / "res:back" steps (changes the screen while the tool is open)
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class WrtRes {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DM {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettingsW(string dev, int mode, ref DM dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsW(ref DM dm, int flags);
    public static string Current() { DM d = new DM(); d.dmSize = (short)Marshal.SizeOf(typeof(DM)); if (!EnumDisplaySettingsW(null, -1, ref d)) return ""; return d.dmPelsWidth + "x" + d.dmPelsHeight; }
    public static int Set(int w, int h) { DM d = new DM(); d.dmSize = (short)Marshal.SizeOf(typeof(DM)); EnumDisplaySettingsW(null, -1, ref d); d.dmPelsWidth = w; d.dmPelsHeight = h; d.dmFields = 0x80000 | 0x100000; return ChangeDisplaySettingsW(ref d, 0); }
}
"@
$WrtAuditResStart = [WrtRes]::Current()
[WrtAuditBox]::LogPath = Join-Path $WrtAuditOutDir "$WrtAudittag.msgboxes.txt"
$WrtAuditsrc = [IO.File]::ReadAllText($WrtAuditChild)
$WrtAuditsrc = $WrtAuditsrc.Replace('if ($PSCommandPath) {', 'if ($false) {').Replace('if (-not $isAdmin) {', 'if ($false) {')
$WrtAuditsrc = [regex]::Replace($WrtAuditsrc, 'if \(-not \(New-Object Security\.Principal\.WindowsPrincipal \$id\)\.IsInRole\(\[Security\.Principal\.WindowsBuiltInRole\]::Administrator\)\) \{', 'if ($false) {')
$WrtAuditsrc = [regex]::Replace($WrtAuditsrc, '\[(System\.)?Windows\.Forms\.MessageBox\]::Show\(', '[WrtAuditBox]::Show(')
$WrtAuditsrc = $WrtAuditsrc.Replace('Start-Process -FilePath $html;', '')
if ($WrtAuditScale -ne 1.0) {
    $WrtAuditsrc = $WrtAuditsrc.Replace('New-Object Drawing.SizeF(96, 96)', ('New-Object Drawing.SizeF({0}, {0})' -f [int](96 / $WrtAuditScale)))
    $WrtAuditsrc = $WrtAuditsrc.Replace('CurrentAutoScaleDimensions.Width / 96', ('CurrentAutoScaleDimensions.Width / {0}' -f [int](96 / $WrtAuditScale)))   # minimum and scroll sizes scale too
    $WrtAuditsrc = [regex]::Replace($WrtAuditsrc, "(Drawing\.Font\('[^']+', )(\d+(?:\.\d+)?)", { param($m) $m.Groups[1].Value + ([double]$m.Groups[2].Value * $WrtAuditScale).ToString([Globalization.CultureInfo]::InvariantCulture) })
}
Set-Location $WrtAuditOutDir
$script:AuditOut = Join-Path $WrtAuditOutDir 'issues.csv'
function Add-Issue($size, $tab, $kind, $detail) { Add-Content -LiteralPath $script:AuditOut ('"{0}","{1}","{2}","{3}","{4}"' -f $WrtAudittag, $size, ($tab -replace '"', "'"), $kind, ($detail -replace '"', "'")) }
function Get-Name($c) { $t = ($c.Text -replace '\s+', ' ').Trim(); if ($t.Length -gt 40) { $t = $t.Substring(0, 40) + '...' }; if ($t) { "$($c.GetType().Name) '$t'" } else { $c.GetType().Name + $(if ($c.Name) { " $($c.Name)" } else { '' }) } }
function Test-Layout($root, [string]$size, [string]$tab) {
    $queue = New-Object Collections.Queue; $queue.Enqueue($root)
    while ($queue.Count) {
        $p = $queue.Dequeue()
        $kids = @($p.Controls | Where-Object { $_.Visible })
        $scroll = ($p -is [Windows.Forms.ScrollableControl]) -and $p.AutoScroll
        $area = if ($scroll) { $p.DisplayRectangle } else { $p.ClientRectangle }
        for ($i = 0; $i -lt $kids.Count; $i++) {
            $a = $kids[$i]
            if ($a -is [Windows.Forms.TabPage]) { continue }
            # CUT-OFF: outside what the container shows or can scroll to
            if ($a.Dock -eq 'None' -and ($a.Right -gt $area.Right + 2 -or $a.Bottom -gt $area.Bottom + 2 -or $a.Left -lt $area.Left - 2 -or $a.Top -lt $area.Top - 2)) {
                Add-Issue $size $tab 'CUT-OFF' ("{0} at {1} is outside {2} {3}" -f (Get-Name $a), $a.Bounds, (Get-Name $p), $area)
            }
            # OVERLAP with a later sibling
            for ($j = $i + 1; $j -lt $kids.Count; $j++) {
                $b = $kids[$j]
                if ($a.Dock -ne 'None' -or $b.Dock -ne 'None' -or $b -is [Windows.Forms.TabPage]) { continue }
                $r = [Drawing.Rectangle]::Intersect($a.Bounds, $b.Bounds)
                if ($r.Width -gt 2 -and $r.Height -gt 2) { Add-Issue $size $tab 'OVERLAP' ("{0} {1} and {2} {3}" -f (Get-Name $a), $a.Bounds, (Get-Name $b), $b.Bounds) }
            }
            # TEXT that does not fit (fixed-size buttons, labels, check boxes, radio buttons)
            if (-not $a.AutoSize -and $a.Text -and ($a -is [Windows.Forms.Button] -or $a -is [Windows.Forms.Label] -or $a -is [Windows.Forms.CheckBox] -or $a -is [Windows.Forms.RadioButton])) {
                $pad = if ($a -is [Windows.Forms.Button]) { 8 } elseif ($a -is [Windows.Forms.CheckBox] -or $a -is [Windows.Forms.RadioButton]) { 22 } else { 0 }
                $w = [Math]::Max(1, $a.Width - $pad)
                $flags = [Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::TextBoxControl
                $need = [Windows.Forms.TextRenderer]::MeasureText($a.Text.Replace('&&', '&'), $a.Font, (New-Object Drawing.Size($w, 100000)), $flags)
                $one = [Windows.Forms.TextRenderer]::MeasureText($a.Text.Replace('&&', '&'), $a.Font)
                if ($need.Height -gt $a.Height + 2 -or ($a -is [Windows.Forms.Button] -and $one.Width -gt $w + 2 -and $need.Height -gt $a.Height - 4)) {
                    Add-Issue $size $tab 'TEXT' ("{0}: needs {1}x{2}, has {3}x{4}" -f (Get-Name $a), [Math]::Min($one.Width + $pad, $a.Width + 999), $need.Height, $a.Width, $a.Height)
                }
            }
            if ($a.Controls.Count -and $a -isnot [Windows.Forms.ComboBox] -and $a -isnot [Windows.Forms.NumericUpDown]) { $queue.Enqueue($a) }
        }
    }
}
function Save-Shot($f, $file) {
    try { $r = $f.Bounds; $b = New-Object Drawing.Bitmap($r.Width, $r.Height); $g = [Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($r.Location, [Drawing.Point]::Empty, $r.Size); $g.Dispose(); $b.Save((Join-Path $WrtAuditOutDir $file)); $b.Dispose() } catch {}
}
$WrtAudithook = @'
$__f = $form
$script:__plan = New-Object Collections.ArrayList
$script:__tabs = @()
$__walk = { param($c) foreach ($k in $c.Controls) { if ($k -is [Windows.Forms.TabControl]) { $script:__tabs += $k }; & $__walk $k } }
& $__walk $__f
foreach ($s in $WrtAuditSizes) {
    $pages = @(foreach ($t in $script:__tabs) { foreach ($p in $t.TabPages) { ,@($t, $p) } })
    if (-not $pages.Count) { [void]$script:__plan.Add(@($s, $null, $null)) } else { foreach ($tp in $pages) { [void]$script:__plan.Add(@($s, $tp[0], $tp[1])) } }
}
$script:__i = -1; $script:__lastSize = ''
$__t = New-Object Windows.Forms.Timer; $__t.Interval = 400
$__t.Add_Tick({
    $f = $__f
    if ($script:__wait -gt 0) { $script:__wait--; return }      # let a resolution change settle
    if ($script:__i -ge 0) {
        $st = $script:__plan[$script:__i]
        $tabName = if ($st[2]) { $st[2].Text } else { '(no tabs)' }
        if ($st[0] -match '^res:' -and $script:__settledFor -ne $script:__i) {
            # after a resolution change has settled: the window must fit the new screen (or scroll, if even its minimum does not fit)
            $script:__settledFor = $script:__i
            $wa2 = [Windows.Forms.Screen]::FromControl($f).WorkingArea
            Add-Content (Join-Path $WrtAuditOutDir 'sizes.txt') ('{0,-36} {1,-9} settled: {2}x{3} min {4}x{5} scroll {6} screen work area {7}x{8}' -f $WrtAudittag, $st[0], $f.Width, $f.Height, $f.MinimumSize.Width, $f.MinimumSize.Height, $f.AutoScroll, $wa2.Width, $wa2.Height)
            if ($f.WindowState -eq 'Normal' -and ($f.Width -gt $wa2.Width + 16 -or $f.Height -gt $wa2.Height + 16)) { Add-Issue $st[0] '-' 'SCREEN' "after the resolution change the window $($f.Size) is bigger than the screen's work area $($wa2.Size)" }
            if ($f.MinimumSize.Width -gt $wa2.Width -or $f.MinimumSize.Height -gt $wa2.Height) { Add-Issue $st[0] '-' 'SCREEN' "after the resolution change the minimum size $($f.MinimumSize) is bigger than the screen's work area $($wa2.Size)" }
        }
        Test-Layout $f $st[0] $tabName
        if ($WrtAuditShots) { Save-Shot $f ('{0}-{1}-{2}.png' -f $WrtAudittag, ($st[0] -replace '[^0-9a-z]', ''), (($tabName -replace '[^A-Za-z0-9]+', '-').Trim('-'))) }
    }
    $script:__i++
    if ($script:__i -ge $script:__plan.Count) { $this.Stop(); $f.Close(); return }
    $st = $script:__plan[$script:__i]
    if ($st[0] -ne $script:__lastSize) {
        $script:__lastSize = $st[0]
        $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea
        if ($st[0] -notmatch '^res:') { $f.WindowState = 'Normal' }     # a resolution step leaves the window alone: the tool must cope
        switch -Regex ($st[0]) {
            '^res:back$' { $r = [WrtRes]::Current(); $m = $WrtAuditResStart -split 'x'; [void][WrtRes]::Set([int]$m[0], [int]$m[1]); Add-Content (Join-Path $WrtAuditOutDir 'sizes.txt') ("$WrtAudittag resolution $r -> back to $WrtAuditResStart"); $script:__wait = 6 }
            '^res:(\d+)x(\d+)$' { $rc = [WrtRes]::Set([int]$Matches[1], [int]$Matches[2]); Add-Content (Join-Path $WrtAuditOutDir 'sizes.txt') ("$WrtAudittag resolution $WrtAuditResStart -> $($Matches[1])x$($Matches[2]) (result $rc, now $([WrtRes]::Current()))"); $script:__wait = 6 }
            '^max$' { $f.WindowState = 'Maximized' }
            '^min$' { $f.Size = New-Object Drawing.Size(200, 150) }
            '^(\d+)%$' { $p = [int]$Matches[1] / 100; $f.Size = New-Object Drawing.Size([int]($wa.Width * $p), [int]($wa.Height * $p)) }
            '^(\d+)x(\d+)$' { $f.Size = New-Object Drawing.Size([int]$Matches[1], [int]$Matches[2]) }
        }
        if ($f.WindowState -ne 'Maximized' -and $st[0] -notmatch '^res:') { $f.Location = New-Object Drawing.Point($wa.Left, $wa.Top) }
        [Windows.Forms.Application]::DoEvents()
        $minOk = ($f.Width -ge $f.MinimumSize.Width -and $f.Height -ge $f.MinimumSize.Height)
        Add-Content (Join-Path $WrtAuditOutDir 'sizes.txt') ('{0,-36} {1,-9} -> {2}x{3} (min {4}x{5}, state {6})' -f $WrtAudittag, $st[0], $f.Width, $f.Height, $f.MinimumSize.Width, $f.MinimumSize.Height, $f.WindowState)
        if ($st[0] -eq 'min') {
            if ($f.MinimumSize.Width -lt 300 -or $f.MinimumSize.Height -lt 200) { Add-Issue 'min' '-' 'MINSIZE' "no real minimum size: the window shrank to $($f.Size)" }
            if ($f.MinimumSize.Width -gt $wa.Width -or $f.MinimumSize.Height -gt $wa.Height) { Add-Issue 'min' '-' 'MINSIZE' "the minimum size $($f.MinimumSize) is bigger than the screen's work area $($wa.Size)" }
        }
        if (-not $minOk) { Add-Issue $st[0] '-' 'MINSIZE' "window $($f.Size) is smaller than its minimum $($f.MinimumSize)" }
    }
    if ($st[1]) { $st[1].SelectedTab = $st[2] }
})
$__f.Add_Shown({ $__t.Start() })
'@
$WrtAuditsrc = [regex]::Replace($WrtAuditsrc, '(?m)^(\[void\]\$(script:)?[Ff]orm\.ShowDialog\(\))', { param($m) $WrtAudithook + "`r`n" + $m.Value })
$ErrorActionPreference = 'Continue'      # the tools expect the default; 'Stop' would turn their harmless warnings into failures
try { . ([scriptblock]::Create($WrtAuditsrc)) }
catch { Add-Issue '-' '-' 'ERROR' ("the tool stopped: {0} (line {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber) }
finally {
    # always put the screen resolution back, even when the tool stopped early
    if ($WrtAuditResStart -and [WrtRes]::Current() -ne $WrtAuditResStart) { $m = $WrtAuditResStart -split 'x'; [void][WrtRes]::Set([int]$m[0], [int]$m[1]) }
}
