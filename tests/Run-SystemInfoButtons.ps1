# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-SystemInfoButtons.ps1 - run AS ADMINISTRATOR:
#   powershell -STA -ExecutionPolicy Bypass -File .\tests\Run-SystemInfoButtons.ps1 -Beta .\tools\WinSuperTool.ps1 -Out C:\Users\Public\wst-sysinfo-test
# Close any open Settings window first (a Settings page reuses it, and the test only counts NEW windows).
# System Info test: runs the beta WinSuperTool (as administrator) and drives its System Info tab through the real buttons.
#  - every info button: its window opens, text, timing, "Copy all" (clipboard = window text), "Save as..." (file written)
#  - every Windows-tool button: a new window with the expected title appears; it is closed again without touching it
# Results: $Out\results.csv, $Out\info-*.txt (contain product keys / addresses: local only, never commit), $Out\log.txt
param([string]$Beta, [string]$Out)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class WstSnap {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  // visible top-level windows with a title: hwnd|pid|class|title
  public static List<string> List() { var o = new List<string>(); EnumWindows((h, l) => { if (IsWindowVisible(h)) { var s = new StringBuilder(512); GetWindowText(h, s, 512); if (s.Length > 0) { var c = new StringBuilder(256); GetClassName(h, c, 256); int p; GetWindowThreadProcessId(h, out p); o.Add(h.ToInt64() + "|" + p + "|" + c + "|" + s); } } return true; }, IntPtr.Zero); return o; }
  public static void Close(long h) { PostMessage(new IntPtr(h), 0x10, IntPtr.Zero, IntPtr.Zero); }
  public static bool Exists(long h) { return IsWindow(new IntPtr(h)) && IsWindowVisible(new IntPtr(h)); }
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  // child windows of a dialog: class|text (buttons and labels)
  public static List<string> Children(long h) { var o = new List<string>(); EnumChildWindows(new IntPtr(h), (c, l) => { var s = new StringBuilder(1024); GetWindowText(c, s, 1024); var k = new StringBuilder(64); GetClassName(c, k, 64); if (s.Length > 0) o.Add(k + "|" + s); return true; }, IntPtr.Zero); return o; }
  // answers a Yes/No question box with No (IDNO = 7)
  public static void PressNo(long h) { SendMessage(new IntPtr(h), 0x111, new IntPtr(7), IntPtr.Zero); }
}
'@
$WstOut = $Out; $WstLog = Join-Path $Out 'log.txt'; $WstCsv = Join-Path $Out 'results.csv'
function Write-WstLog([string]$m) { Add-Content -LiteralPath $WstLog ('{0:HH:mm:ss.fff} {1}' -f (Get-Date), $m) }
function Add-WstResult($kind, $name, $result, $detail) { Add-Content -LiteralPath $WstCsv ('"{0}","{1}","{2}","{3}"' -f $kind, $name, $result, (([string]$detail) -replace '"', "'")) }
# what each Windows tool's window is called (English Windows 11)
$WstExpect = @{
    'DirectX Diagnostic' = 'DirectX Diagnostic Tool'; 'System Information' = '^System Information$'; 'Event Viewer' = '^Event Viewer'
    'Advanced System Settings' = '^System Properties$'; 'Internet Options' = '^Internet Properties$'; 'Group Policy Editor' = 'Local Group Policy Editor'
    'Registry Editor' = '^Registry Editor$'; 'Device Manager' = '^Device Manager$'; 'Disk Management' = '^Disk Management$'
    'Computer Management' = '^Computer Management$'; 'Services' = '^Services$'; 'Task Manager' = '^Task Manager$'; 'Resource Monitor' = '^Resource Monitor$'
    'Performance Monitor' = '^Performance Monitor$'; 'Reliability Monitor' = '^Reliability Monitor$'; 'System Configuration' = '^System Configuration$'
    'Task Scheduler' = '^Task Scheduler$'; 'Control Panel' = 'Control Panel'; 'Programs and Features' = '^Programs and Features$'
    'Network Connections' = '^Network Connections$'; 'Sound Settings (classic)' = '^Sound$'; 'Power Options' = '^Power Options$'
    'System Properties' = '^System Properties$'; 'Environment Variables' = '^Environment Variables$'; 'Firewall (advanced)' = 'Firewall with Advanced Security'
    'Windows Security' = '^Windows Security$'; 'Local Users and Groups' = 'Local Users and Groups'; 'Local Security Policy' = '^Local Security Policy$'
    'Credential Manager' = '^Credential Manager$'; 'Certificates (user)' = 'Certificates - Current User'; 'Shared Folders' = '^Shared Folders$'
    'Print Management' = '^Print Management$'; 'Windows Features' = '^Windows Features$'; 'Disk Cleanup' = '^Disk Cleanup'; 'Optimize Drives' = '^Optimize Drives$'
    'System Restore' = '^System Restore$'; 'Memory Diagnostic' = 'Windows Memory Diagnostic'; 'Windows Update' = '^Settings$'; 'About this PC' = '^Settings$'
    'Windows version (winver)' = '^About Windows$'; 'Command Prompt (admin)' = 'cmd\.exe|Command Prompt'; 'PowerShell (admin)' = 'powershell\.exe|PowerShell'
}

$src = [IO.File]::ReadAllText($Beta)
# started as administrator already: skip the tool's own restart (as in the other test loaders)
$src = $src.Replace('if ($PSCommandPath) {', 'if ($false) {').Replace('if (-not $isAdmin) {', 'if ($false) {')
# "Save as...": Windows' own dialog needs a person; the test answers it with a fixed path in the results folder
$saveOld = 'if ($d.ShowDialog() -eq ''OK'') {'
if (-not $src.Contains($saveOld)) { Add-WstResult 'setup' 'save stub' 'FAILED' 'Save as... code not found' }
$src = $src.Replace($saveOld, 'if ((& { $d.FileName = Join-Path $WstOut ("saved-" + $d.FileName); $true })) {')
$hook = @'
$script:WstPlan = New-Object Collections.ArrayList
$tabsW = $tpInfo.Parent; $tabsW.SelectedTab = $tpInfo
foreach ($c in $tpInfo.Controls) { if ($c -is [Windows.Forms.Button]) { [void]$script:WstPlan.Add($c) } }
Write-WstLog ("plan: {0} buttons on the System Info tab" -f $script:WstPlan.Count)
$script:WstI = -1; $script:WstState = 'next'; $script:WstWait = 0; $script:WstBefore = @{}; $script:WstT0 = Get-Date
$script:WstTimer = New-Object Windows.Forms.Timer; $script:WstTimer.Interval = 250
$script:WstTimer.Add_Tick({
    if ($script:WstBusy) { return }; $script:WstBusy = $true
    try {
        $me = $PID
        switch ($script:WstState) {
            'next' {
                $script:WstI++
                if ($script:WstI -ge $script:WstPlan.Count) {
                    # final sweep: anything still open that a tool button started
                    foreach ($w in [WstSnap]::List()) { $p = $w -split '\|', 4; if (-not $script:WstBefore0.ContainsKey($p[0]) -and [int]$p[1] -ne $me) { Write-WstLog "final sweep closes: $($p[3])"; [WstSnap]::Close([long]$p[0]) } }
                    Write-WstLog 'done'; $this.Stop(); $form.Close(); return
                }
                $b = $script:WstPlan[$script:WstI]; $script:WstBtn = $b
                if (-not $b.Enabled) { Add-WstResult 'tool' $b.Text 'GREYED OUT' 'button disabled (not available on this PC)'; return }
                if ($b.Tag -isnot [scriptblock] -and [string]$b.Tag.Exe -match '^ms-settings:') {
                    # Settings reuses an open Settings window, so close it first or the page would not count as a NEW window
                    foreach ($w in [WstSnap]::List()) { $q = $w -split '\|', 4; if ($q[3] -eq 'Settings') { [WstSnap]::Close([long]$q[0]) } }
                    Start-Sleep -Milliseconds 1500
                }
                $script:WstBefore = @{}; foreach ($w in [WstSnap]::List()) { $script:WstBefore[($w -split '\|')[0]] = 1 }
                $script:WstAsked = @()
                if (-not $script:WstBefore0) { $script:WstBefore0 = $script:WstBefore.Clone() }
                $script:WstClickAt = Get-Date; $script:WstWait = 0; $script:WstFound = @()
                $script:WstIsInfo = ($b.Tag -is [scriptblock])
                Write-WstLog "click: $($b.Text)"
                $script:WstState = $(if ($script:WstIsInfo) { 'info' } else { 'tool' })
                [void]$b.BeginInvoke([Action]{ $script:WstBtn.PerformClick() })
            }
            'info' {
                # the info window is modal: this timer keeps ticking inside its message loop
                $f2 = $null; foreach ($o in [Windows.Forms.Application]::OpenForms) { if ($o -ne $form -and $o.Visible -and $o.Controls.Count -and ($o.Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] })) { $f2 = $o } }
                $script:WstWait++
                if (-not $f2) { if ($script:WstWait -gt 240) { Add-WstResult 'info' $script:WstBtn.Text 'FAILED' 'no info window within 60 s'; $script:WstState = 'next' }; return }
                $secs = ((Get-Date) - $script:WstClickAt).TotalSeconds
                $rt = $f2.Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] } | Select-Object -First 1
                $btns = @($f2.Controls | Where-Object { $_ -is [Windows.Forms.Button] })
                $copy = $btns | Where-Object { $_.Text -eq 'Copy all' }; $save = $btns | Where-Object { $_.Text -eq 'Save as...' }; $close = $btns | Where-Object { $_.Text -eq 'Close' }
                $safe = ($f2.Text -replace '[^A-Za-z0-9]+', '-').Trim('-')
                try { [Windows.Forms.Clipboard]::Clear() } catch {}
                $copy.PerformClick(); $clip = ''
                # read back with retries: another program (VirtualBox's clipboard sync, a clipboard manager) can hold the clipboard
                # for a moment, and a single read then returns nothing (seen on the Windows 10 test PC)
                for ($r = 0; $r -lt 20 -and -not $clip; $r++) { try { $clip = [Windows.Forms.Clipboard]::GetText() } catch {}; if (-not $clip) { Start-Sleep -Milliseconds 100 } }
                [IO.File]::WriteAllText((Join-Path $WstOut "info-$safe.txt"), $clip)
                $before = @(Get-ChildItem $WstOut -Filter 'saved-*' -ErrorAction SilentlyContinue).Count
                $save.PerformClick(); $saved = @(Get-ChildItem $WstOut -Filter 'saved-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1)
                $savedOk = (@(Get-ChildItem $WstOut -Filter 'saved-*').Count -gt $before) -and $saved -and ([IO.File]::ReadAllText($saved[0].FullName) -eq $clip)
                # the window text (minus the title/underline the copy adds) must be in the copy
                $winLines = @($rt.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $clipLines = @($clip -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $missing = @($winLines | Where-Object { $clipLines -notcontains $_ }).Count
                $heads = @($clip -split "`r?`n" | Select-String -Pattern '^-{3,}$' -Context 1, 0 | ForEach-Object { $_.Context.PreContext[0] }) -join '; '
                $ok = $clip.Length -gt 50 -and $missing -eq 0 -and $savedOk
                Add-WstResult 'info' $script:WstBtn.Text $(if ($ok) { 'PASS' } else { 'FAILED' }) ("window '{0}' after {1:N1} s; {2} lines; copy: {3} chars, {4} window lines missing; save: {5} ({6}); sections: {7}" -f $f2.Text, $secs, $winLines.Count, $clip.Length, $missing, $(if ($savedOk) { 'same text' } else { 'NOT SAVED OR DIFFERENT' }), $(if ($saved) { $saved[0].Name } else { '-' }), $heads)
                $close.PerformClick(); $script:WstState = 'next'
            }
            'tool' {
                $script:WstWait++
                foreach ($w in [WstSnap]::List()) {
                    $p = $w -split '\|', 4
                    if ($script:WstBefore.ContainsKey($p[0]) -or ([int]$p[1] -eq $me -and $p[2] -ne '#32770')) { continue }
                    if ($script:WstFound -notcontains $w) { $script:WstFound += $w }
                }
                foreach ($w in @($script:WstFound)) {
                    $q = $w -split '\|', 4
                    if ($q[2] -ne '#32770' -or [int]$q[1] -eq $me) { continue }
                    $kids = @([WstSnap]::Children([long]$q[0]))
                    if (@($kids | Where-Object { $_ -match '^Button\|&?Yes$' }).Count -and @($kids | Where-Object { $_ -match '^Button\|&?No$' }).Count) {
                        $txt = (($kids | Where-Object { $_ -match '^Static\|' } | ForEach-Object { ($_ -split '\|', 2)[1] }) -join ' ') -replace '\s+', ' '
                        $script:WstAsked += "asked first: '$txt' -> answered No"
                        [WstSnap]::PressNo([long]$q[0]); $script:WstFound = @($script:WstFound | Where-Object { $_ -ne $w })
                        $script:WstBefore[$q[0]] = 1     # the question is closed; do not count it as the tool's window
                    }
                }
                $own = @($script:WstFound | Where-Object { [int](($_ -split '\|')[1]) -eq $me })
                $exp = $WstExpect[$script:WstBtn.Text]
                $hit = @($script:WstFound | Where-Object { ($_ -split '\|', 4)[3] -match $exp })
                if ($own.Count -or $hit.Count -or $script:WstWait -ge 60) {
                    if (-not $hit.Count -and -not $own.Count) { Start-Sleep -Milliseconds 10 }
                    $secs = ((Get-Date) - $script:WstClickAt).TotalSeconds
                    $titles = ($script:WstFound | ForEach-Object { $q = $_ -split '\|', 4; try { $pn = (Get-Process -Id $q[1] -ErrorAction Stop).ProcessName } catch { $pn = '?' }; "'$($q[3])' [$pn]" }) -join ', '
                    $res = $(if ($own.Count) { 'ERROR MESSAGE' } elseif ($hit.Count) { 'PASS' } else { 'NO WINDOW' })
                    Add-WstResult 'tool' $script:WstBtn.Text $res ("after {0:N1} s: {1}{2}" -f $secs, $(if ($titles) { $titles } else { '(no new window in 15 s)' }), $(if ($script:WstAsked) { '; ' + ($script:WstAsked -join '; ') } else { '' }))
                    $script:WstState = 'close'; $script:WstWait = 0
                }
            }
            'close' {
                # close every new window again (also ones that appeared late), without touching what is inside
                $script:WstWait++
                $new = @([WstSnap]::List() | Where-Object { $p = $_ -split '\|', 4; -not $script:WstBefore.ContainsKey($p[0]) -and ([int]$p[1] -ne $me -or $p[2] -eq '#32770') })
                if ($script:WstWait -le 3) { foreach ($w in $new) { [WstSnap]::Close([long](($w -split '\|')[0])) }; return }
                if ($new.Count -and $script:WstWait -lt 40) { if ($script:WstWait % 8 -eq 0) { foreach ($w in $new) { [WstSnap]::Close([long](($w -split '\|')[0])) } }; return }
                if ($new.Count) { Write-WstLog ("still open after closing: " + (($new | ForEach-Object { ($_ -split '\|', 4)[3] }) -join ', ')) }
                $script:WstState = 'next'
            }
        }
    } catch { Write-WstLog "TEST ERROR: $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)"; $script:WstState = 'next' }
    finally { $script:WstBusy = $false }
})
$form.Add_Shown({ $script:WstTimer.Start() })
'@
$src = [regex]::Replace($src, '(?m)^(\[void\]\$(script:)?[Ff]orm\.ShowDialog\(\))', { param($m) $hook + "`r`n" + $m.Value })
Write-WstLog "start (admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))"
try { . ([scriptblock]::Create($src)) } catch { Write-WstLog "TOOL STOPPED: $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)" }
Write-WstLog 'tool closed'
