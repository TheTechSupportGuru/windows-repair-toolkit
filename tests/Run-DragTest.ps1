# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-DragTest.ps1 - drags a tool's window with the REAL mouse between two monitors, the way a person does
# (Windows' own move loop, button held down), and checks the tool never pulls the window away:
#   A  monitor 1 -> monitor 2, holding the button for 3 s with the window across the edge (the screen watcher ticks)
#   B  dropped across the edge: it must stay exactly where it was dropped
#   C  back onto monitor 1
# Needs two monitors. Runs WITHOUT admin (the tool's admin prompt is skipped). DO NOT TOUCH THE MOUSE while it runs
# (about 30 s per tool). Output: %TEMP%\wrt-drag-test\summary.txt
#   .\tests\Run-DragTest.ps1                         (Collect-Logs, WinSuperTool and the beta)
#   .\tests\Run-DragTest.ps1 -Scripts tools\WinFixKit.ps1
param([string[]]$Scripts = @('tools\Collect-Logs.ps1', 'tools\WinSuperTool.ps1', 'beta\WinSuperTool.ps1'),
      [string]$OutDir = (Join-Path $env:TEMP 'wrt-drag-test'), [string]$Child = '')
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if ($Child) {
    # child: the tool exactly as shipped, except that its admin prompt is skipped
    $src = [IO.File]::ReadAllText($Child)
    $src = $src.Replace('if ($PSCommandPath) {', 'if ($false) {').Replace('if (-not $isAdmin) {', 'if ($false) {')
    $src = [regex]::Replace($src, 'if \(-not \(New-Object Security\.Principal\.WindowsPrincipal \$id\)\.IsInRole\(\[Security\.Principal\.WindowsBuiltInRole\]::Administrator\)\) \{', 'if ($false) {')
    # no message boxes in the way: they are answered "No" (nothing is changed)
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition 'public static class WrtDragBox { public static System.Windows.Forms.DialogResult Show(params object[] a) { return System.Windows.Forms.DialogResult.No; } }'
    $src = [regex]::Replace($src, '\[(System\.)?Windows\.Forms\.MessageBox\]::Show\(', '[WrtDragBox]::Show(')
    . ([scriptblock]::Create($src))
    return
}

Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class WrtDrag {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool rp);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  // the biggest visible titled window of a process that is not the splash screen
  public static IntPtr MainWindow(int pid) {
    IntPtr best = IntPtr.Zero; long area = 0;
    EnumWindows((h, l) => { int p; GetWindowThreadProcessId(h, out p); if (p != pid || !IsWindowVisible(h)) return true;
      var s = new StringBuilder(256); GetWindowText(h, s, 256); string t = s.ToString(); if (t.Length == 0 || t == "Windows Repair Toolkit") return true;
      RECT r; GetWindowRect(h, out r); long a = (long)(r.R - r.L) * (r.B - r.T); if (a > area) { area = a; best = h; } return true; }, IntPtr.Zero);
    return best;
  }
  public static string Title(IntPtr h) { var s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
}
'@
[void][WrtDrag]::SetProcessDPIAware()
New-Item -ItemType Directory -Force $OutDir | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W([string]$m) { Add-Content -LiteralPath $sum ('{0:HH:mm:ss}  {1}' -f (Get-Date), $m); Write-Host $m }
function Get-R($h) { $r = New-Object WrtDrag+RECT; [void][WrtDrag]::GetWindowRect($h, [ref]$r); New-Object Drawing.Rectangle($r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T)) }
$scr = @([Windows.Forms.Screen]::AllScreens | Sort-Object { -not $_.Primary })
W ("Drag test {0}  screens: {1}" -f (Get-Date -Format 'yyyy-MM-dd'), (($scr | ForEach-Object { "$($_.DeviceName -replace '^\\\\\.\\', '') $($_.Bounds)" }) -join '; '))
if ($scr.Count -lt 2) { W 'SKIPPED: this test needs two monitors.'; return }
$m1 = $scr[0].WorkingArea; $m2 = $scr[1].WorkingArea
# a point on the shared edge, and which way monitor 2 lies (unit step)
if ($m2.Left -ge $m1.Right) { $edge = New-Object Drawing.Point($m1.Right, [int](([Math]::Max($m1.Top, $m2.Top) + [Math]::Min($m1.Bottom, $m2.Bottom)) / 2)); $dir = New-Object Drawing.Point(1, 0) }
elseif ($m2.Right -le $m1.Left) { $edge = New-Object Drawing.Point($m1.Left, [int](([Math]::Max($m1.Top, $m2.Top) + [Math]::Min($m1.Bottom, $m2.Bottom)) / 2)); $dir = New-Object Drawing.Point(-1, 0) }
elseif ($m2.Bottom -le $m1.Top) { $edge = New-Object Drawing.Point([int](([Math]::Max($m1.Left, $m2.Left) + [Math]::Min($m1.Right, $m2.Right)) / 2), $m1.Top); $dir = New-Object Drawing.Point(0, -1) }
else { $edge = New-Object Drawing.Point([int](([Math]::Max($m1.Left, $m2.Left) + [Math]::Min($m1.Right, $m2.Right)) / 2), $m1.Bottom); $dir = New-Object Drawing.Point(0, 1) }
W "shared edge at $($edge.X),$($edge.Y), monitor 2 lies $(@{ '1,0' = 'right'; '-1,0' = 'left'; '0,-1' = 'above'; '0,1' = 'below' }["$($dir.X),$($dir.Y)"])"

$cur0 = New-Object WrtDrag+POINT; [void][WrtDrag]::GetCursorPos([ref]$cur0)
# drags the window by its title bar so that the window's centre moves to $to; holds still for $hold seconds at $holdAt (0..1)
function Invoke-Drag($h, [Drawing.Point]$to, [double]$holdAt = -1, [double]$hold = 0) {
    $r = Get-R $h; $grab = New-Object Drawing.Point(($r.Left + [Math]::Min(220, [int]($r.Width / 3))), ($r.Top + 14))
    $dx = $to.X - ($r.Left + [int]($r.Width / 2)); $dy = $to.Y - ($r.Top + [int]($r.Height / 2))
    [void][WrtDrag]::SetForegroundWindow($h); Start-Sleep -Milliseconds 300
    [void][WrtDrag]::SetCursorPos($grab.X, $grab.Y); Start-Sleep -Milliseconds 150
    [WrtDrag]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200       # left button down on the title bar
    $n = 40; $log = @(); $held = $false
    for ($k = 1; $k -le $n; $k++) {
        [void][WrtDrag]::SetCursorPos(($grab.X + [int]($dx * $k / $n)), ($grab.Y + [int]($dy * $k / $n))); Start-Sleep -Milliseconds 50
        if (-not $held -and $holdAt -ge 0 -and $k / $n -ge $holdAt) {
            $held = $true; $a = Get-R $h
            Start-Sleep -Milliseconds ([int]($hold * 1000))      # button still down, mouse still: the tool's 1-second screen check runs meanwhile
            $b = Get-R $h; $log += "held $hold s at $($a.Location): window $(if ($a -eq $b) { 'did not move' } else { 'MOVED to ' + $b.Location })"
        }
    }
    Start-Sleep -Milliseconds 150; [WrtDrag]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero)      # release
    $dropped = Get-R $h; Start-Sleep -Seconds 3; $after = Get-R $h
    $want = New-Object Drawing.Point(($r.Left + $dx), ($r.Top + $dy))
    [pscustomobject]@{ From = $r; Want = $want; Dropped = $dropped; After = $after; Log = $log }
}
function On-Which($rect) { ($scr | Where-Object { $_.WorkingArea.IntersectsWith($rect) } | ForEach-Object { $_.DeviceName -replace '^\\\\\.\\', '' }) -join '+' }

$results = @()
foreach ($s in $Scripts) {
    $full = (Resolve-Path $s).Path; $name = "$(Split-Path (Split-Path $full) -Leaf)\$(Split-Path $full -Leaf)"
    $p = Start-Process powershell.exe -PassThru -ArgumentList '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Child', "`"$full`""
    $h = [IntPtr]::Zero; for ($k = 0; $k -lt 60 -and $h -eq [IntPtr]::Zero; $k++) { Start-Sleep -Milliseconds 500; $h = [WrtDrag]::MainWindow($p.Id) }
    Start-Sleep -Seconds 3; $h = [WrtDrag]::MainWindow($p.Id)
    if ($h -eq [IntPtr]::Zero) { W "$name : FAILED - no window"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; continue }
    W "=== $name : '$([WrtDrag]::Title($h))'"
    # start centred on monitor 1, a size that fits both monitors
    $w = [Math]::Min(1000, [int]($m2.Width * 0.6)); $hh = [Math]::Min(700, [int]($m2.Height * 0.6))
    [void][WrtDrag]::MoveWindow($h, ($m1.Left + [int](($m1.Width - $w) / 2)), ($m1.Top + [int](($m1.Height - $hh) / 2)), $w, $hh, $true); Start-Sleep -Seconds 2
    $r0 = Get-R $h
    # A: to the middle of monitor 2, holding still for 3 s while the window is across the edge
    $c2 = New-Object Drawing.Point(($m2.Left + [int]($m2.Width / 2)), ($m2.Top + [int]($m2.Height / 2)))
    # hold where about 65 % of the window is already on monitor 2: Windows now counts the window as on monitor 2 while the
    # button is still down - the moment the 1.8.4 draft pulled windows away (found with the old code, see the docs)
    $holdC = New-Object Drawing.Point(($edge.X + $dir.X * [int]($r0.Width * 0.15)), ($edge.Y + $dir.Y * [int]($r0.Height * 0.15)))
    $along = { param($pt) ($pt.X - ($r0.Left + $r0.Width / 2)) * $dir.X + ($pt.Y - ($r0.Top + $r0.Height / 2)) * $dir.Y }
    $edgeHold = [Math]::Max(0.05, [Math]::Min(0.95, (& $along $holdC) / [Math]::Max(1, (& $along $c2))))
    $a = Invoke-Drag $h $c2 $edgeHold 3
    $okA = ([Math]::Abs($a.After.X - $a.Want.X) -le 12 -and [Math]::Abs($a.After.Y - $a.Want.Y) -le 12 -and (On-Which $a.After) -eq ($scr[1].DeviceName -replace '^\\\\\.\\', ''))
    W ("  A  monitor 1 -> 2   {0}  {1}; dropped at {2}, 3 s later {3} on {4} (expected {5})" -f $(if ($okA -and -not ($a.Log -match 'MOVED')) { 'PASS' } else { 'FAIL' }), ($a.Log -join '; '), $a.Dropped.Location, $a.After.Location, (On-Which $a.After), $a.Want)
    # B: drop it across the edge, coming from monitor 2, with most of it (about 60 %) back on monitor 1
    $cE = New-Object Drawing.Point(($edge.X - $dir.X * [int]($a.After.Width * 0.1)), ($edge.Y - $dir.Y * [int]($a.After.Height * 0.1)))
    $b = Invoke-Drag $h $cE
    $okB = ($b.After -eq $b.Dropped) -and ((On-Which $b.After) -match '\+')
    W ("  B  across the edge   {0}  dropped at {1} on {2}, 3 s later {3} on {4}" -f $(if ($okB) { 'PASS' } else { 'FAIL' }), $b.Dropped.Location, (On-Which $b.Dropped), $b.After.Location, (On-Which $b.After))
    # C: back to monitor 1
    $c1 = New-Object Drawing.Point(($m1.Left + [int]($m1.Width / 2)), ($m1.Top + [int]($m1.Height / 2)))
    $c = Invoke-Drag $h $c1
    $okC = ([Math]::Abs($c.After.X - $c.Want.X) -le 12 -and [Math]::Abs($c.After.Y - $c.Want.Y) -le 12)
    W ("  C  back to monitor 1 {0}  3 s later {1} on {2} (expected {3})" -f $(if ($okC) { 'PASS' } else { 'FAIL' }), $c.After.Location, (On-Which $c.After), $c.Want)
    $results += [pscustomobject]@{ Tool = $name; A = $okA -and -not ($a.Log -match 'MOVED'); B = $okB; C = $okC }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1
}
[void][WrtDrag]::SetCursorPos($cur0.X, $cur0.Y)
$bad = @($results | Where-Object { -not ($_.A -and $_.B -and $_.C) })
W ("RESULT: {0} of {1} tools passed all 3 drags" -f ($results.Count - $bad.Count), $results.Count)
