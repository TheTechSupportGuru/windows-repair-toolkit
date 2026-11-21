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
# Screen words (the tool must cope by itself): res:WxH / res:back (primary resolution), mon:N (move to monitor N),
# maxon:N (maximized on monitor N), span (across the edge of monitors 1 and 2), dpi2:150 / dpi2:back (scaling of
# monitor 2, live), solo / extend (monitor 2 switched off and on again). Size words after mon:N apply on that monitor.
param(
    [string[]]$Scripts = @(),
    [string[]]$Sizes = @('min', '1280x680', '1366x728', '1600x860', '75%', 'max'),
    [string]$OutDir = (Join-Path $env:TEMP 'wrt-resize-audit'),
    [double]$Scale = 1.0,
    [switch]$Shots,
    [switch]$Parallel,          # all tools at once (8 cores) - only for size steps; screen steps always run one tool at a time
    [string]$Child = ''           # internal: run ONE tool and audit it
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if (-not $Child) {
    if (-not $Scripts.Count) { $Scripts = @(Get-ChildItem (Join-Path $Root 'tools'), (Join-Path $Root 'beta') -Filter *.ps1 | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'Windows\.Forms\.Form' } | ForEach-Object { $_.FullName }) }
    Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $OutDir | Out-Null
    $screenSteps = @($Sizes -split ',' | Where-Object { $_ -match '^(res|mon|span|maxon|dpi\d|solo|extend)' })
    if ($Parallel -and $screenSteps.Count) { Write-Warning "screen steps ($($screenSteps -join ', ')) change the screen for every tool: running one tool at a time"; $Parallel = $false }
    $running = @()
    foreach ($s in $Scripts) {
        $full = (Resolve-Path $s).Path
        $tag = (Split-Path (Split-Path $full) -Leaf) + '-' + [IO.Path]::GetFileNameWithoutExtension($full)
        $args2 = @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Child', "`"$full`"", '-OutDir', "`"$OutDir`"", '-Scale', $Scale, '-Sizes', ($Sizes -join ','))
        if ($Shots) { $args2 += '-Shots' }
        # (the console is hidden by PowerShell itself, like the launchers do: a hidden START style would also apply to the
        # tool's window and can start it hidden or minimized)
        $p = Start-Process powershell.exe -PassThru -ArgumentList $args2 -RedirectStandardError (Join-Path $OutDir "$tag.stderr.txt")
        $running += ,@($p, $tag)
        if (-not $Parallel) { $running = @(); if (-not $p.WaitForExit(600000)) { $p | Stop-Process -Force; Add-Content (Join-Path $OutDir 'issues.csv') "`"$tag`",`"-`",`"-`",`"TIMEOUT`",`"the audit did not finish`"" } }
    }
    foreach ($r in $running) { if (-not $r[0].WaitForExit(900000)) { $r[0] | Stop-Process -Force; Add-Content (Join-Path $OutDir 'issues.csv') "`"$($r[1])`",`"-`",`"-`",`"TIMEOUT`",`"the audit did not finish`"" } }
    foreach ($k in 'issues', 'sizes') { $ext = if ($k -eq 'issues') { 'csv' } else { 'txt' }; Get-ChildItem $OutDir -Filter "$k-*.$ext" | Sort-Object Name | ForEach-Object { Add-Content (Join-Path $OutDir "$k.$ext") (Get-Content $_.FullName); Remove-Item $_.FullName } }
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
$WrtAuditSizesFile = Join-Path $WrtAuditOutDir "sizes-$WrtAudittag.txt"
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
# per-monitor display scaling for the "dpi2:NNN" steps (Settings > Display > Scale; on a secondary monitor it applies
# at once, without signing out). Undocumented but stable DisplayConfig calls, the same ones the Settings app uses.
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class WrtMonDpi {
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, IntPtr pathArr, ref uint modes, IntPtr modeArr, IntPtr topo);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(IntPtr p);
    [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(IntPtr p);
    static readonly int[] Steps = { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };
    // finds the display source (adapter LUID + source id) of a GDI device name such as \\.\DISPLAY2
    static bool Find(string dev, out long luid, out uint id) {
        luid = 0; id = 0; uint np, nm; if (GetDisplayConfigBufferSizes(2, out np, out nm) != 0) return false;
        IntPtr pa = Marshal.AllocHGlobal((int)np * 72), ma = Marshal.AllocHGlobal((int)nm * 64);
        try {
            if (QueryDisplayConfig(2, ref np, pa, ref nm, ma, IntPtr.Zero) != 0) return false;
            for (int i = 0; i < np; i++) {
                long l = Marshal.ReadInt64(pa, i * 72); uint s = (uint)Marshal.ReadInt32(pa, i * 72 + 8);
                IntPtr q = Marshal.AllocHGlobal(84);
                try {
                    Marshal.WriteInt32(q, 0, 1); Marshal.WriteInt32(q, 4, 84); Marshal.WriteInt64(q, 8, l); Marshal.WriteInt32(q, 16, (int)s);
                    if (DisplayConfigGetDeviceInfo(q) == 0 && Marshal.PtrToStringUni(new IntPtr(q.ToInt64() + 20)) == dev) { luid = l; id = s; return true; }
                } finally { Marshal.FreeHGlobal(q); }
            }
            return false;
        } finally { Marshal.FreeHGlobal(pa); Marshal.FreeHGlobal(ma); }
    }
    static bool Get(string dev, out long luid, out uint id, out int min, out int cur, out int max) {
        min = cur = max = 0; if (!Find(dev, out luid, out id)) return false;
        IntPtr q = Marshal.AllocHGlobal(32);
        try {
            Marshal.WriteInt32(q, 0, -3); Marshal.WriteInt32(q, 4, 32); Marshal.WriteInt64(q, 8, luid); Marshal.WriteInt32(q, 16, (int)id);
            if (DisplayConfigGetDeviceInfo(q) != 0) return false;
            min = Marshal.ReadInt32(q, 20); cur = Marshal.ReadInt32(q, 24); max = Marshal.ReadInt32(q, 28); return true;
        } finally { Marshal.FreeHGlobal(q); }
    }
    // current scaling in percent, 0 when unknown
    public static int Current(string dev) { long l; uint i; int mn, c, mx; if (!Get(dev, out l, out i, out mn, out c, out mx)) return 0; int rec = -mn; int k = rec + c; return (k >= 0 && k < Steps.Length) ? Steps[k] : 0; }
    // sets the scaling in percent; returns 0 on success
    public static int Set(string dev, int pct) {
        long l; uint i; int mn, c, mx; if (!Get(dev, out l, out i, out mn, out c, out mx)) return -1;
        int k = Array.IndexOf(Steps, pct); if (k < 0) return -2; int rel = k - (-mn); if (rel < mn || rel > mx) return -3;
        IntPtr q = Marshal.AllocHGlobal(24);
        try { Marshal.WriteInt32(q, 0, -4); Marshal.WriteInt32(q, 4, 24); Marshal.WriteInt64(q, 8, l); Marshal.WriteInt32(q, 16, (int)i); Marshal.WriteInt32(q, 20, rel); return DisplayConfigSetDeviceInfo(q); }
        finally { Marshal.FreeHGlobal(q); }
    }
}
"@
# monitor 2 off and on again for the "solo" / "extend" steps, as if it was unplugged
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class WrtMonOnOff {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DM {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettingsW(string dev, int mode, ref DM dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsExW(string dev, ref DM dm, IntPtr hwnd, int flags, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsExW(string dev, IntPtr dm, IntPtr hwnd, int flags, IntPtr p);
    const int POS = 0x20, W = 0x80000, H = 0x100000, UPDATEREGISTRY = 1, NORESET = 0x10000000;
    // "x,y,w,h" of the monitor now (ENUM_CURRENT_SETTINGS), "" when it is off
    public static string Get(string dev) { DM d = new DM(); d.dmSize = (short)Marshal.SizeOf(typeof(DM)); if (!EnumDisplaySettingsW(dev, -1, ref d) || d.dmPelsWidth == 0) return ""; return d.dmPositionX + "," + d.dmPositionY + "," + d.dmPelsWidth + "," + d.dmPelsHeight; }
    // switches a (non-primary) monitor off, as if unplugged
    public static int Off(string dev) {
        DM d = new DM(); d.dmSize = (short)Marshal.SizeOf(typeof(DM)); d.dmFields = POS | W | H;
        int r = ChangeDisplaySettingsExW(dev, ref d, IntPtr.Zero, UPDATEREGISTRY | NORESET, IntPtr.Zero); if (r != 0) return r;
        return ChangeDisplaySettingsExW(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
    }
    // switches it on again at its old place and size ("x,y,w,h" from Get)
    public static int On(string dev, string was) {
        string[] p = was.Split(','); DM d = new DM(); d.dmSize = (short)Marshal.SizeOf(typeof(DM)); EnumDisplaySettingsW(dev, -2, ref d);
        d.dmFields = POS | W | H; d.dmPositionX = int.Parse(p[0]); d.dmPositionY = int.Parse(p[1]); d.dmPelsWidth = int.Parse(p[2]); d.dmPelsHeight = int.Parse(p[3]);
        int r = ChangeDisplaySettingsExW(dev, ref d, IntPtr.Zero, UPDATEREGISTRY | NORESET, IntPtr.Zero); if (r != 0) return r;
        return ChangeDisplaySettingsExW(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
    }
}
"@
# monitors by number, as Settings shows them (\\.\DISPLAY1 = 1 ...)
function Get-WrtAuditScreen([int]$n) { [Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -match "DISPLAY$n$" } | Select-Object -First 1 }
$WrtAuditDpiStart = @{}; foreach ($s in [Windows.Forms.Screen]::AllScreens) { $WrtAuditDpiStart[$s.DeviceName] = [WrtMonDpi]::Current($s.DeviceName) }
$WrtAuditScreensStart = [Windows.Forms.Screen]::AllScreens.Count; $WrtAuditMon2 = "\\.\DISPLAY2"; $WrtAuditMon2Was = [WrtMonOnOff]::Get($WrtAuditMon2)
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
$script:AuditOut = Join-Path $WrtAuditOutDir "issues-$WrtAudittag.csv"; $WrtAuditSizesFile = Join-Path $WrtAuditOutDir "sizes-$WrtAudittag.txt"
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
# Screenshots come from the tool's OWN window (PrintWindow), not from the screen: a screen grab shows whatever
# window happens to be on top (another app, a prompt), which once led to a wrong conclusion about a bug.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class WrtShot {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
}
'@
function Save-Shot($f, $file) {
    try {
        $b = New-Object Drawing.Bitmap($f.Width, $f.Height); $g = [Drawing.Graphics]::FromImage($b); $hdc = $g.GetHdc()
        $ok = [WrtShot]::PrintWindow($f.Handle, $hdc, 2)    # 2 = PW_RENDERFULLCONTENT: also windows that are covered or partly off the screen
        $g.ReleaseHdc($hdc); $g.Dispose()
        if ($ok) { $b.Save((Join-Path $WrtAuditOutDir $file)) } else { Add-Content -LiteralPath $WrtAuditSizesFile "$WrtAudittag screenshot failed: $file" }
        $b.Dispose()
    } catch {}
}
$WrtAudithook = @'
$__f = $form
$script:__plan = New-Object Collections.ArrayList
$script:__tabs = @()
$__walk = { param($c) foreach ($k in $c.Controls) { if ($k -is [Windows.Forms.TabControl]) { $script:__tabs += $k }; & $__walk $k } }
& $__walk $__f
$__k = 0
foreach ($s in $WrtAuditSizes) {
    $__k++
    $pages = @(foreach ($t in $script:__tabs) { foreach ($p in $t.TabPages) { ,@($t, $p) } })
    if (-not $pages.Count) { [void]$script:__plan.Add(@($s, $null, $null, $__k)) } else { foreach ($tp in $pages) { [void]$script:__plan.Add(@($s, $tp[0], $tp[1], $__k)) } }
}
$script:__i = -1; $script:__lastSize = ''
$script:__screenStep = '^(res|mon|span|maxon|dpi\d|solo|extend)'
$__t = New-Object Windows.Forms.Timer; $__t.Interval = 400
$__t.Add_Tick({
    $f = $__f
    if ($script:__wait -gt 0) { $script:__wait--; return }      # let a resolution change settle
    if (-not $script:__openChecked) {
        # where the window OPENED (before any step): fully on its screen, apart from Windows' invisible 8 px resize border.
        # (A window centred with its size from before scaling grew past the screen edge - 1.8.2; a Windows 10 unit test
        # suggested .NET 4.8 may scale later than 4.8.1, so this is checked on every PC the audit runs on.)
        $script:__openChecked = $true
        $wa0 = [Windows.Forms.Screen]::FromControl($f).WorkingArea; $in0 = [Drawing.Rectangle]::Inflate($f.Bounds, -8, -8)
        Add-Content $WrtAuditSizesFile ('{0,-36} opened    {1} on a work area of {2} ({3}, .NET release {4})' -f $WrtAudittag, $f.Bounds, $wa0, $f.WindowState, (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release)
        if ($f.WindowState -eq 'Normal' -and -not $wa0.Contains($in0)) { Add-Issue 'opened' '-' 'SCREEN' "the window opened partly off the screen: $($f.Bounds), work area $wa0" }
    }    if ($script:__i -ge 0) {
        $st = $script:__plan[$script:__i]
        $tabName = if ($st[2]) { $st[2].Text } else { '(no tabs)' }
        if ($st[0] -match $script:__screenStep -and $script:__settledFor -ne $st[3]) {
            # after a screen change (resolution, other monitor, scaling, monitor removed) has settled: the window must fit
            # its screen (or scroll, if even its minimum does not fit)
            $script:__settledFor = $st[3]
            $scr2 = [Windows.Forms.Screen]::FromControl($f); $wa2 = $scr2.WorkingArea
            Add-Content $WrtAuditSizesFile ('{0,-36} {1,-9} settled: {2}x{3} min {4}x{5} scroll {6} screen work area {7}x{8} on {9} at {10},{11} state {12} screens {13}' -f $WrtAudittag, $st[0], $f.Width, $f.Height, $f.MinimumSize.Width, $f.MinimumSize.Height, $f.AutoScroll, $wa2.Width, $wa2.Height, ($scr2.DeviceName -replace '^\\\\\.\\', ''), $f.Left, $f.Top, $f.WindowState, [Windows.Forms.Screen]::AllScreens.Count)
            if ($f.WindowState -eq 'Normal' -and ($f.Width -gt $wa2.Width + 16 -or $f.Height -gt $wa2.Height + 16)) { Add-Issue $st[0] '-' 'SCREEN' "after the screen change the window $($f.Size) is bigger than the screen's work area $($wa2.Size)" }
            if ($f.MinimumSize.Width -gt $wa2.Width -or $f.MinimumSize.Height -gt $wa2.Height) { Add-Issue $st[0] '-' 'SCREEN' "after the screen change the minimum size $($f.MinimumSize) is bigger than the screen's work area $($wa2.Size)" }
            # the title bar must be on SOME screen, so the window can still be grabbed and moved
            $bar = New-Object Drawing.Rectangle(($f.Left + 40), ($f.Top + 4), [Math]::Max(1, $f.Width - 80), 20)
            if ($f.WindowState -eq 'Normal' -and -not @([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith($bar) }).Count) { Add-Issue $st[0] '-' 'SCREEN' "the title bar at $($bar.Location) is on no screen" }
            if ($st[0] -match '^mon:(\d)$' -and $scr2.DeviceName -notmatch "DISPLAY$($Matches[1])$" -and (Get-WrtAuditScreen ([int]$Matches[1]))) { Add-Issue $st[0] '-' 'SCREEN' "moved to monitor $($Matches[1]) but the window is on $($scr2.DeviceName)" }
            if ($st[0] -match '^mon:' -and -not $wa2.Contains($f.Bounds)) { Add-Issue $st[0] '-' 'SCREEN' "the window $($f.Bounds) is not fully inside its screen's work area $wa2" }
            # across the edge: when the screens show all of it, the window must stay where it was put (not be pulled onto one monitor)
            if ($st[0] -eq 'span' -and $f.WindowState -eq 'Normal') {
                $inR = New-Object Drawing.Rectangle(($f.Left + 8), $f.Top, [Math]::Max(1, $f.Width - 16), [Math]::Max(1, $f.Height - 8)); $seenA = 0.0; $onN = 0
                foreach ($sc in [Windows.Forms.Screen]::AllScreens) { $ir = [Drawing.Rectangle]::Intersect($sc.WorkingArea, $inR); if (-not $ir.IsEmpty) { $seenA += [double]$ir.Width * $ir.Height; $onN++ } }
                if ($script:__spanAll -and $onN -lt 2) { Add-Issue 'span' '-' 'SCREEN' "the window was put across the edge of two monitors (fully visible) but was moved onto one monitor: now at $($f.Bounds)" }
            }
            if ($st[0] -match '^maxon:(\d)$' -and ($f.WindowState -ne 'Maximized' -or $scr2.DeviceName -notmatch "DISPLAY$($Matches[1])$")) { Add-Issue $st[0] '-' 'SCREEN' "should be maximized on monitor $($Matches[1]), is $($f.WindowState) on $($scr2.DeviceName)" }
        }
        Test-Layout $f $st[0] $tabName
        if ($WrtAuditShots) { Save-Shot $f ('{0}-{1}-{2}.png' -f $WrtAudittag, ($st[0] -replace '[^0-9a-z]', ''), (($tabName -replace '[^A-Za-z0-9]+', '-').Trim('-'))) }
    }
    $script:__i++
    if ($script:__i -ge $script:__plan.Count) { $this.Stop(); $f.Close(); return }
    $st = $script:__plan[$script:__i]
    if ($st[3] -ne $script:__lastSize) {
        $script:__lastSize = $st[3]
        $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea
        if ($st[0] -notmatch '^(res|dpi\d|solo|extend)') { $f.WindowState = 'Normal' }     # a screen change leaves the window alone: the tool must cope
        $sz = $WrtAuditSizesFile
        switch -Regex ($st[0]) {
            '^res:back$' { $r = [WrtRes]::Current(); $m = $WrtAuditResStart -split 'x'; [void][WrtRes]::Set([int]$m[0], [int]$m[1]); Add-Content $WrtAuditSizesFile ("$WrtAudittag resolution $r -> back to $WrtAuditResStart"); $script:__wait = 6 }
            '^res:(\d+)x(\d+)$' { $rc = [WrtRes]::Set([int]$Matches[1], [int]$Matches[2]); Add-Content $WrtAuditSizesFile ("$WrtAudittag resolution $WrtAuditResStart -> $($Matches[1])x$($Matches[2]) (result $rc, now $([WrtRes]::Current()))"); $script:__wait = 6 }
            '^max$' { $f.WindowState = 'Maximized' }
            # monitors: mon:N = move to monitor N (centred), maxon:N = maximized there, span = across the edge between monitor 1 and 2
            '^(mon|maxon):(\d)$' {
                $s2 = Get-WrtAuditScreen ([int]$Matches[2])
                if (-not $s2) { Add-Content $sz "$WrtAudittag $($st[0]): there is no monitor $($Matches[2]) - skipped" }
                else { $w2 = $s2.WorkingArea; $f.Location = New-Object Drawing.Point(($w2.Left + [int](($w2.Width - $f.Width) / 2)), ($w2.Top + [int](($w2.Height - $f.Height) / 2))); if ($Matches[1] -eq 'maxon') { $f.WindowState = 'Maximized' } }
                $script:__wait = 4
            }
            '^span$' {
                $a1 = (Get-WrtAuditScreen 1).Bounds; $s2 = Get-WrtAuditScreen 2
                if (-not $s2) { Add-Content $sz "$WrtAudittag span: there is no monitor 2 - skipped" }
                else {
                    $a2 = $s2.Bounds
                    if ($a2.Bottom -le $a1.Top -or $a2.Top -ge $a1.Bottom) {      # above or below
                        $cx = [int](([Math]::Max($a1.Left, $a2.Left) + [Math]::Min($a1.Right, $a2.Right)) / 2)
                        $cy = $(if ($a2.Bottom -le $a1.Top) { [int](($a2.Bottom + $a1.Top) / 2) } else { [int](($a1.Bottom + $a2.Top) / 2) })
                    } else {                                                       # left or right
                        $cy = [int](([Math]::Max($a1.Top, $a2.Top) + [Math]::Min($a1.Bottom, $a2.Bottom)) / 2)
                        $cx = $(if ($a2.Right -le $a1.Left) { [int](($a2.Right + $a1.Left) / 2) } else { [int](($a1.Right + $a2.Left) / 2) })
                    }
                    $f.Location = New-Object Drawing.Point(($cx - [int]($f.Width / 2)), ($cy - [int]($f.Height / 2)))
                    # remember whether the screens show all of it where it was put (with different scaling there can be a gap)
                    $inR = New-Object Drawing.Rectangle(($f.Left + 8), $f.Top, [Math]::Max(1, $f.Width - 16), [Math]::Max(1, $f.Height - 8)); $seenA = 0.0
                    foreach ($sc in [Windows.Forms.Screen]::AllScreens) { $ir = [Drawing.Rectangle]::Intersect($sc.WorkingArea, $inR); if (-not $ir.IsEmpty) { $seenA += [double]$ir.Width * $ir.Height } }
                    $script:__spanAll = ($seenA -ge [double]$inR.Width * $inR.Height - 1)
                }
                $script:__wait = 4
            }
            # scaling of one monitor, live: dpi2:150 / dpi2:back
            '^dpi(\d):(\d+|back)$' {
                $dev = (Get-WrtAuditScreen ([int]$Matches[1])).DeviceName
                if (-not $dev) { Add-Content $sz "$WrtAudittag $($st[0]): there is no monitor $($Matches[1]) - skipped" }
                else { $want = $(if ($Matches[2] -eq 'back') { $WrtAuditDpiStart[$dev] } else { [int]$Matches[2] }); $was = [WrtMonDpi]::Current($dev); $rc = [WrtMonDpi]::Set($dev, $want); Add-Content $sz "$WrtAudittag scaling of $dev $was % -> $want % (result $rc, now $([WrtMonDpi]::Current($dev)) %)" }
                $script:__wait = 8
            }
            # monitor 2 removed (as if unplugged) and back: Windows' own "PC screen only" / "Extend" switch
            '^solo$' { if (-not $WrtAuditMon2Was) { Add-Content $sz "$WrtAudittag solo: there is no monitor 2 - skipped" } else { $rc = [WrtMonOnOff]::Off($WrtAuditMon2); Add-Content $sz "$WrtAudittag monitor 2 switched off (result $rc, screens now $([Windows.Forms.Screen]::AllScreens.Count))" }; $script:__wait = 10 }
            '^extend$' { if ($WrtAuditMon2Was) { $rc = [WrtMonOnOff]::On($WrtAuditMon2, $WrtAuditMon2Was); Add-Content $sz "$WrtAudittag monitor 2 switched on again at $WrtAuditMon2Was (result $rc, screens now $([Windows.Forms.Screen]::AllScreens.Count))" }; $script:__wait = 10 }
            '^min$' { $f.Size = New-Object Drawing.Size(200, 150) }
            '^(\d+)%$' { $p = [int]$Matches[1] / 100; $f.Size = New-Object Drawing.Size([int]($wa.Width * $p), [int]($wa.Height * $p)) }
            '^(\d+)x(\d+)$' { $f.Size = New-Object Drawing.Size([int]$Matches[1], [int]$Matches[2]) }
        }
        if ($f.WindowState -ne 'Maximized' -and $st[0] -notmatch $script:__screenStep) { $f.Location = New-Object Drawing.Point($wa.Left, $wa.Top) }
        [Windows.Forms.Application]::DoEvents()
        $minOk = ($f.Width -ge $f.MinimumSize.Width -and $f.Height -ge $f.MinimumSize.Height)
        Add-Content $WrtAuditSizesFile ('{0,-36} {1,-9} -> {2}x{3} (min {4}x{5}, state {6})' -f $WrtAudittag, $st[0], $f.Width, $f.Height, $f.MinimumSize.Width, $f.MinimumSize.Height, $f.WindowState)
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
    # ... and the monitors and their scaling
    if ($WrtAuditMon2Was -and [WrtMonOnOff]::Get($WrtAuditMon2) -ne $WrtAuditMon2Was) { [void][WrtMonOnOff]::On($WrtAuditMon2, $WrtAuditMon2Was); Start-Sleep -Seconds 3 }
    foreach ($d in @($WrtAuditDpiStart.Keys)) { if ($WrtAuditDpiStart[$d] -and [WrtMonDpi]::Current($d) -ne $WrtAuditDpiStart[$d]) { [void][WrtMonDpi]::Set($d, $WrtAuditDpiStart[$d]) } }
}
