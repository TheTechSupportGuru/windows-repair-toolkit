# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-TestCenterGui.ps1 - tests Test Center itself: opens its window and clicks every feature that needs no admin
# rights with Win32 messages (tabs, tick all / untick all, empty / partial tools folders, Online mode: version list,
# download, replace question, edit detection, a run + Stop, the report files, Copy summary for GitHub, Export HTML,
# Open results). Needs internet for the Online checks. Do not use the mouse or keyboard while it runs (~5 min).
#   powershell -STA -ExecutionPolicy Bypass -File .	ests\Run-TestCenterGui.ps1
# Results: the console and %TEMP%	c-gui-results.csv
param([string]$Tc = (Join-Path $PSScriptRoot 'TestCenter.ps1'))
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
  public static string Text(IntPtr h) { int n = (int)SendMessage(h, 0x0E, IntPtr.Zero, IntPtr.Zero); var s = new StringBuilder(n + 2); SendMessage(h, 0x0D, (IntPtr)(n + 1), s); return s.ToString(); }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static List<IntPtr> Children(IntPtr p) { var l = new List<IntPtr>(); EnumChildWindows(p, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static List<IntPtr> TopOf(uint pid) { var l = new List<IntPtr>(); EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
}
"@
$res = New-Object Collections.ArrayList
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @"
using System; using System.Runtime.InteropServices; using Accessibility;
public static class Acc {
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
  public static int State(IntPtr h) { Guid g = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o; if (AccessibleObjectFromWindow(h, 0xFFFFFFFC, ref g, out o) != 0) return -1; return (int)((IAccessible)o).get_accState(0); }
}
"@
function Add-Check($n, $ok, $d = '') { [void]$res.Add([pscustomobject]@{ Check = $n; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $d }); Write-Host ("{0}  {1}  {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) }
# every window of the Test Center process (main form, message boxes, dialogs) and their children
function Get-All { $l = @(); foreach ($t in [W]::TopOf([uint32]$p.Id)) { $l += $t; $l += [W]::Children($t) }; $l }
function Find-Ctl([string]$text, [string]$cls = '', [int]$wait = 10, [switch]$Like) {
    for ($i = 0; $i -lt $wait * 4; $i++) {
        foreach ($h in Get-All) { $t = [W]::Text($h); if ((($Like -and $t -like $text) -or $t -eq $text) -and (-not $cls -or [W]::Cls($h) -match $cls)) { return $h } }
        Start-Sleep -Milliseconds 250
    }
    [IntPtr]::Zero
}
function Click([IntPtr]$h) { if ($h -eq [IntPtr]::Zero) { Write-Host '   (control not found)'; return }; [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Milliseconds 400 }
function Get-Checked([IntPtr]$h) { ([Acc]::State($h) -band 0x10) -ne 0 }
function Get-Log { (Get-All | Where-Object { [W]::Cls($_) -match 'EDIT' } | ForEach-Object { [W]::Text($_) } | Sort-Object Length -Descending | Select-Object -First 1) }
function Wait-Log([string]$pattern, [int]$sec) { for ($i = 0; $i -lt $sec; $i++) { $l = Get-Log; if ($l -match $pattern) { return $l }; Start-Sleep 1 }; Get-Log }
function Set-EditText([string]$old, [string]$new) { $h = Find-Ctl $old 'EDIT' 2; if ($h -eq [IntPtr]::Zero) { return $false }; [void][W]::SendMessage($h, 0x000C, [IntPtr]::Zero, $new); $true }
function Get-Boxes { Get-All | Where-Object { [W]::Cls($_) -match 'BUTTON' -and [W]::Text($_) -match '\[.*min\]' } }
# tabs: select by sending a real click is not needed - the tab control takes TCM_SETCURFOCUS (raises the change)
function Select-Tab([int]$i) {
    $tc = Get-All | Where-Object { [W]::Cls($_) -match 'SysTabControl32' } | Select-Object -First 1
    [void][W]::SendMessage($tc, 0x1330, [IntPtr]$i, [IntPtr]::Zero); Start-Sleep -Milliseconds 600   # TCM_SETCURFOCUS
}

$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$Tc`"" -PassThru
for ($i = 0; $i -lt 40 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh() }
Start-Sleep 2; $p.Refresh()
Add-Check 'window opens' ($p.MainWindowHandle -ne 0) $p.MainWindowTitle
$toolsDefault = (Resolve-Path (Join-Path (Split-Path $Tc) '..\tools')).Path

# --- tabs: each tab shows its own tests
$expect = @('Unit tests: every tool', 'Full regression', 'Check status: every section (no admin)', 'Backup Script Builder: scripts, folder picker', 'Unit tests: 7z-Encryptor edge cases', 'Log collection', 'Field test')
for ($i = 0; $i -lt $expect.Count; $i++) {
    Select-Tab $i
    $vis = @(Get-Boxes | Where-Object { [W]::IsWindowVisible($_) } | ForEach-Object { [W]::Text($_) })
    Add-Check "tab $($i + 1) shows its tests" (($vis -join '|') -match [regex]::Escape($expect[$i])) ("{0} tests: {1}" -f $vis.Count, ($vis[0] -replace '\s+\[.*', ''))
}
# Tick all on the Other PCs tab: field test ticked, WinPE test disabled + reason
Click (Find-Ctl 'Tick all on this tab' 'BUTTON')
$field = Find-Ctl 'Field test*' 'BUTTON' -Like; $pe = Find-Ctl 'WinPE test*' 'BUTTON' -Like
Add-Check 'Tick all on this tab ticks the available test' (Get-Checked $field) ((Get-Boxes | Where-Object { [W]::IsWindowVisible($_) } | ForEach-Object { '{0}={1}' -f ([W]::Text($_).Substring(0, 12)), (Get-Checked $_) }) -join '; ')
Add-Check 'WinPE test greyed out outside WinPE (with reason)' ((-not [W]::IsWindowEnabled($pe)) -and ([W]::Text($pe) -match 'only inside WinPE') -and -not (Get-Checked $pe)) ([W]::Text($pe))
Click (Find-Ctl 'Untick all' 'BUTTON')
Add-Check 'Untick all' (-not (Get-Boxes | Where-Object { Get-Checked $_ }))
Click (Find-Ctl 'Run selected' 'BUTTON')
$mb = Find-Ctl 'Tick at least one test.' '' 5
Add-Check 'Run with nothing ticked warns' ($mb -ne [IntPtr]::Zero)
Click (Find-Ctl 'OK' 'BUTTON' 3)

# --- offline folder handling
$empty = Join-Path $env:TEMP 'tc-empty'; New-Item -ItemType Directory -Force $empty | Out-Null
Add-Check 'tools folder edit found' (Set-EditText $toolsDefault $empty)
Click (Find-Ctl 'Re-check' 'BUTTON')
Add-Check 'empty folder: "No scripts" + every test greyed out' (((Find-Ctl 'No scripts in that folder' '' 3) -ne [IntPtr]::Zero) -and -not (Get-Boxes | Where-Object { [W]::IsWindowEnabled($_) }))
[void](Set-EditText $empty $toolsDefault); Click (Find-Ctl 'Re-check' 'BUTTON')
Add-Check 'real folder: version shown, tests back' (((Find-Ctl 'Version *, * scripts' '' 3 -Like) -ne [IntPtr]::Zero) -and @(Get-Boxes | Where-Object { [W]::IsWindowEnabled($_) }).Count -ge 15)
$only = Join-Path $env:TEMP 'tc-only-wfk'; Remove-Item $only -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $only | Out-Null; Copy-Item (Join-Path $toolsDefault 'WinFixKit.ps1') $only
[void](Set-EditText $toolsDefault $only); Click (Find-Ctl 'Re-check' 'BUTTON')
$lm = Find-Ctl 'Live Monitor*' 'BUTTON' -Like; $ws = Find-Ctl 'Check status: every section (no admin)*' 'BUTTON' -Like
Add-Check 'folder with only WinFixKit: WinSuperTool tests greyed, WinFixKit tests not' ((-not [W]::IsWindowEnabled($lm)) -and ([W]::Text($lm) -match 'no WinSuperTool.ps1') -and [W]::IsWindowEnabled($ws)) ([W]::Text($lm) -replace '^.*not available', 'not available')
[void](Set-EditText $only $toolsDefault); Click (Find-Ctl 'Re-check' 'BUTTON')

# --- online
$bList = Find-Ctl 'Get version list' 'BUTTON'
Add-Check 'Offline mode: download controls disabled' (-not [W]::IsWindowEnabled($bList))
Click (Find-Ctl 'Online: download a version from GitHub' 'BUTTON')
Add-Check 'Online mode: download controls enabled' ([W]::IsWindowEnabled($bList))
Click $bList; $l = Wait-Log 'versions found|Could not read' 40
Add-Check 'Get version list' ($l -match 'GitHub: \d+ versions found') ([regex]::Match($l, 'GitHub: \d+ versions found').Value)
$dl = Join-Path $env:TEMP ('tc-dl-gui-' + (Get-Random)); $dlDefault = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WRT-TestCenter'
Add-Check 'download folder edit found' (Set-EditText $dlDefault $dl)
Click (Find-Ctl 'Download' 'BUTTON'); $l = Wait-Log 'Downloaded v|Download failed' 180
$got = Join-Path ([string](Get-ChildItem $dl -Directory -ErrorAction SilentlyContinue | Select-Object -First 1).FullName) 'tools'
Add-Check 'Download (latest release) into the chosen folder' ((Test-Path "$got\WinSuperTool.ps1") -and (Test-Path "$got\.wrt-source.json")) ([regex]::Match($l, '(Downloaded|Download failed)[^\r\n]*').Value)
Add-Check 'tools folder switched to the download' ((Find-Ctl $got 'EDIT' 3) -ne [IntPtr]::Zero)
Click (Find-Ctl 'Download' 'BUTTON'); $no = Find-Ctl '&No' 'Button' 10
Add-Check 'second download asks before replacing' ($no -ne [IntPtr]::Zero)
Click $no; Start-Sleep 2
Add-Check 'answering No keeps the folder' (Test-Path "$got\WinSuperTool.ps1")
Add-Content "$got\WinFixKit.ps1" '# local edit by the GUI test'
Click (Find-Ctl 'Re-check' 'BUTTON')
Add-Check 'edited script detected' ((Find-Ctl 'Version *, * scripts, 1 edited' '' 3 -Like) -ne [IntPtr]::Zero)

# --- run two tests, stop the second
Select-Tab 0
Click (Find-Ctl 'Untick all' 'BUTTON')
Click (Find-Ctl 'Unit tests: shared code*' 'BUTTON' -Like); Click (Find-Ctl 'Window sizes*' 'BUTTON' -Like)
Click (Find-Ctl 'Run selected' 'BUTTON')
$l = Wait-Log 'START   Window sizes' 240
Add-Check 'run: unit test result + count logged' ($l -match '(PASSED|FAILED)\s+Unit tests: shared code' -and $l -match 'Passed \d+  Failed \d+') ([regex]::Match($l, 'Passed \d+  Failed \d+  Skipped \d+').Value)
Add-Check 'run: Run disabled, Stop enabled while running' ((-not [W]::IsWindowEnabled((Find-Ctl 'Run selected' 'BUTTON'))) -and [W]::IsWindowEnabled((Find-Ctl 'Stop' 'BUTTON')))
Start-Sleep 15; Click (Find-Ctl 'Stop' 'BUTTON'); $l = Wait-Log 'ALL DONE' 60
Add-Check 'Stop ends the running test (STOPPED)' ($l -match 'STOPPED\s+Window sizes')
$root = [regex]::Match($l, 'C:\\Users\\Public\\wrt-testcenter-\d{8}-\d{6}').Value
Add-Check 'report.html + summary-for-github.md + report.txt written' ($root -and (Test-Path "$root\report.html") -and (Test-Path "$root\summary-for-github.md") -and (Test-Path "$root\report.txt")) $root
Add-Check 'each test has a folder with console.txt' ((Test-Path "$root\unit-toolkit\console.txt") -and (Test-Path "$root\sizes"))
Add-Check 'run used a copy of the downloaded (edited) tools' ((Get-Content "$root\_run\tools\WinFixKit.ps1" -Tail 1) -match 'local edit by the GUI test')
Start-Sleep 2
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $p.Id -and $_.Id -ne $PID -and $_.MainWindowTitle -match 'WinSuperTool|WinFixKit|Collect|Monitor|WinRepair|Claude|Windows Repair Tool' } | Stop-Process -Force -ErrorAction SilentlyContinue

# --- copy summary for GitHub
[Windows.Forms.Clipboard]::Clear()
Click (Find-Ctl 'Copy summary for GitHub' 'BUTTON'); Start-Sleep 1
$clip = [Windows.Forms.Clipboard]::GetText()
Add-Check 'Copy summary for GitHub -> clipboard' ($clip -match '### Test Center' -and $clip -match 'edited: WinFixKit.ps1' -and $clip -match 'STOPPED' -and $clip -match 'PASSED|FAILED') ("{0} chars" -f $clip.Length)
Add-Check 'summary: no user / PC name' ($clip -and -not ($clip -match [regex]::Escape($env:USERNAME) -or $clip -match $env:COMPUTERNAME))
$md = Get-Content "$root\summary-for-github.md" -Raw
Add-Check 'summary file = clipboard text' ($md.Trim() -eq $clip.Trim())

# --- export HTML through the save dialog
Click (Find-Ctl 'Export HTML...' 'BUTTON')
$out = Join-Path $env:TEMP ('tc-export-' + (Get-Random) + '.html')
$dlgEdit = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $dlgEdit -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 250
    foreach ($t in [W]::TopOf([uint32]$p.Id)) { if ([W]::Text($t) -eq 'Save As') { $dlgEdit = [W]::Children($t) | Where-Object { [W]::Cls($_) -eq 'Edit' -and [W]::IsWindowVisible($_) } | Select-Object -First 1; $dlg = $t } }
}
Add-Check 'Export HTML... opens the save dialog' ($dlgEdit -ne [IntPtr]::Zero)
if ($dlgEdit) {
    $cb = [W]::GetDlgItem($dlg, 1148); [void][W]::SendMessage($cb, 0x000C, [IntPtr]::Zero, $out)
    Click ([W]::GetDlgItem($dlg, 1)); Start-Sleep 4
}
$saved = if (Test-Path $out) { Get-Item $out } else { Get-ChildItem ([Environment]::GetFolderPath("MyDocuments")) -Filter "TestCenter-report-*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 }   # the typed name does not always reach the dialog; then it saves under its default name
$h = if ($saved) { Get-Content $saved.FullName -Raw } else { "" }; $out = "$saved"
Add-Check 'Export HTML... saves the report' ($h -match '<h1>Windows Repair Toolkit - Test Center' -and $h -match 'STOPPED' -and $h -match 'edited') $out
Add-Check 'HTML: no user / PC name' ($h -and -not ($h -match [regex]::Escape($env:USERNAME) -or $h -match $env:COMPUTERNAME))
# --- open results folder
Click (Find-Ctl 'Open results' 'BUTTON'); Start-Sleep 3
$shell = New-Object -ComObject Shell.Application
$open = @($shell.Windows() | Where-Object { $_.LocationURL -match 'wrt-testcenter' })
Add-Check 'Open results opens the folder' ($open.Count -gt 0)
$open | ForEach-Object { $_.Quit() }
# --- back to offline keeps working; close
Click (Find-Ctl 'Offline: use a folder on this PC' 'BUTTON')
Add-Check 'back to Offline disables download controls' (-not [W]::IsWindowEnabled($bList))
[void]$p.CloseMainWindow(); Add-Check 'closes cleanly' ($p.WaitForExit(10000))
''; $res | Format-Table -AutoSize | Out-String -Width 220
$res | Export-Csv (Join-Path $env:TEMP 'tc-gui-results.csv') -NoTypeInformation
