# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Port-AutomationToWinFixKit.ps1 - builds the AUTOMATION region of tools\WinFixKit.ps1 from tools\WinSuperTool.ps1:
# WinSuperTool's Automation code word for word (with the documented renames) + the WinFixKit parts in build\automation-port\.
# Run it after every Automation change in WinSuperTool (Automation is changed there FIRST - see CONTRIBUTING.md), then run
# tests\WinFixKitAutomation.Tests.ps1. It stops when WinSuperTool changed in a way the port does not expect (Edit-Once).
#   powershell -ExecutionPolicy Bypass -File .\build\Port-AutomationToWinFixKit.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$part = Join-Path $PSScriptRoot 'automation-port'
$wst = [IO.File]::ReadAllLines((Join-Path $repo 'tools\WinSuperTool.ps1'))
function Get-Lines([int]$a, [int]$b) { ($wst[($a - 1)..($b - 1)]) -join "`r`n" }
function Find-Line([string]$text) { for ($i = 0; $i -lt $wst.Count; $i++) { if ($wst[$i].StartsWith($text)) { return $i + 1 } }; throw "not found in WinSuperTool: $text" }
function Convert-Port([string]$t) {
    $t = $t -replace '\bNew-Ctl ', 'New-AutoCtl '
    $t = $t -replace '\bSafe \{', 'Invoke-AutoSafe {'
    $t = $t.Replace('$DataDir', '$script:RootDir')
    $t.Replace('WinSuperTool-Data\Task-Results', 'WinFixKit\Task-Results')
}
# exact replacement that must match once (a WinSuperTool change that breaks it stops the port)
function Edit-Once([string]$t, [string]$old, [string]$new) {
    $n = ([regex]::Matches($t, [regex]::Escape($old))).Count
    if ($n -ne 1) { throw "expected 1 match, found ${n}: $old" }
    $t.Replace($old, $new)
}
# a part file without its own header lines (licence + '# PART' notes)
function Get-Part([string]$n) { ((@([IO.File]::ReadAllLines((Join-Path $part $n))) | Select-Object -Skip 5) -join "`r`n").TrimEnd() }

$nc = Find-Line 'function New-Ctl('
$newCtl = (Get-Lines $nc ($nc + 9)) -replace '^function New-Ctl\(', 'function New-AutoCtl('
if ($newCtl -notmatch 'return \$c\s*\r?\n\}$') { throw 'New-Ctl is not 10 lines any more' }

$queue = Convert-Port (Get-Lines (Find-Line '$AutoMax = 10') ((Find-Line '#  Run any .ps1 elevated') - 2))
$n = ([regex]::Matches($queue, [regex]::Escape('; Monitor = $chkAutoMon.Checked; EnableSR'))).Count; if ($n -ne 2) { throw "expected the live-log option twice (state + run options), found $n" }
$queue = $queue.Replace('; Monitor = $chkAutoMon.Checked; EnableSR', '; EnableSR')
$queue = Edit-Once $queue '; $chkAutoMon.Checked = [bool]$s.Monitor' ''
$queue = Edit-Once $queue '$chkAutoPop, $chkAutoStop, $chkAutoMon, $chkAutoSR, $chkAutoHtml' '$chkAutoPop, $chkAutoStop, $chkAutoSR, $chkAutoHtml'
$queue = Edit-Once $queue "        if (`$A.Opt.Monitor) { [void](Start-TaskMonitors `$c) }`r`n" ''
# Start-AutoRun: WinFixKit has no Target Windows / offline queue, and the fixes need admin rights
$a = $queue.IndexOf('    # WinPE: the queue works on the Target Windows'); $b = $queue.IndexOf('    $bad = @($script:AutoQueue | Where-Object { Get-AutoWhyNot $_ })')
if ($a -lt 0 -or $b -lt $a) { throw 'Start-AutoRun changed (WinPE block)' }
$queue = $queue.Substring(0, $a) + "    # WinFixKit: no offline queue (Target Windows) here, and the fixes need administrator rights`r`n    `$win = ''`r`n    if (-not (Test-Admin)) { Msg 'Automation runs fixes, which need administrator rights. Use ""Relaunch as Administrator"" at the bottom, then start the queue again.' 'Automation' 'Warning'; return }`r`n" + $queue.Substring($b)
$a = $queue.IndexOf('    # chkdsk /f needs the drive to itself'); $b = $queue.IndexOf('    $names = (@($script:AutoQueue)')
if ($a -lt 0 -or $b -lt $a) { throw 'Start-AutoRun changed (chkdsk block)' }
$queue = $queue.Substring(0, $a) + $queue.Substring($b)
# the fixes that ask before they change something when run by hand: say so in the start question
$queue = Edit-Once $queue '    if (-not (Ask "Run these $($script:AutoQueue.Count) task(s) on $where, one after another?${NL}${NL}$names${NL}${NL}Each task opens its own window. Some tasks change the system (repairs, updates, app upgrades)." ''Start automation'' ''Question'' ''Button2'')) { return }' (
    "    # WinFixKit: list what the fixes that ask first (when run by hand) will change`r`n" +
    "    `$chg = @(@(`$script:AutoQueue) | ForEach-Object { Get-AutoCat `$_ } | Where-Object { `$_.Act -and `$_.Act.Confirm } | ForEach-Object { '  ' + `$_.Name + ':' + `$NL + '      ' + ((`$_.Act.Confirm -replace '\s+', ' ').Trim()) })`r`n" +
    "    `$chgText = if (`$chg.Count) { `"`${NL}`${NL}These fixes change the PC (they ask first when run by hand):`${NL}`" + (`$chg -join `$NL) } else { '' }`r`n" +
    '    if (-not (Ask "Run these $($script:AutoQueue.Count) task(s) on $where, one after another?${NL}${NL}$names$chgText${NL}${NL}Each task opens its own window." ''Start automation'' ''Warning'' ''Button2'')) { return }')

$events = Convert-Port (Get-Lines (Find-Line 'function Edit-AutoQueue') ((Find-Line '# ---- form ----') - 1))
$events = Edit-Once $events '@($chkAutoPop, $chkAutoStop, $chkAutoMon, $chkAutoSR)' '@($chkAutoPop, $chkAutoStop, $chkAutoSR)'

$o = New-Object Text.StringBuilder
function W([string]$t) { [void]$o.AppendLine($t) }
W (Get-Part '1-head.ps1')
W $newCtl
W '$form = $script:Form     # the parent of the summary windows (WinSuperTool''s name for the main window)'
W ''
W '# ---- task summaries (ported) ----'
W (Convert-Port (Get-Lines (Find-Line '# Each tool with a Kind gets its result') (Find-Line 'function New-TaskRule')))
W (Get-Part '2-rules.ps1')
W ''
W (Convert-Port (Get-Lines (Find-Line '# Pass / fail for one finished task.') ((Find-Line '$TaskDir = Join-Path $DataDir') - 1)))
W '$TaskDir = Join-Path $script:RootDir ''Task-Results'''
W (Convert-Port (Get-Lines ((Find-Line '$TaskDir = Join-Path $DataDir') + 1) ((Find-Line '# live monitor windows for the logs a Recovery task writes') - 1)))
W ''
W '# ---- easy-to-read info window (ported) ----'
W (Convert-Port (Get-Lines (Find-Line '# Blocks: InfoH = heading') ((Find-Line 'function Invoke-Busy') - 1)))
W ''
W '# ---- the queue (ported; the restore point script says WinFixKit instead of WinSuperTool) ----'
W ((Convert-Port (Get-Lines (Find-Line '# Script tasks print their own result messages') ((Find-Line '$AutoScriptWU = @''') - 1))).Replace('$desc = ''WinSuperTool '' + (Get-Date', '$desc = ''WinFixKit '' + (Get-Date'))
W (Convert-Port (Get-Lines (Find-Line '# Catalog. Code: param($opt)') (Find-Line 'function New-AutoTask')))
W (Get-Part '3-tasks.ps1')
W $queue
W (Get-Part '5-gui.ps1')
W ''
W '# ---- (ported) the Automation tab''s buttons ----'
W $events
W '# WinFixKit: load the queue and start the timer when the window opens; ask before closing during a run (ported text)'
W '$script:Form.Add_Shown({ $timer.Start(); Invoke-AutoSafe { Load-AutoState; Update-AutoList; Set-AutoEditing $true; if ($lstAutoCat.Items.Count) { $lstAutoCat.SelectedIndex = 0 } } })'
W '$script:Form.Add_FormClosing({'
W '    if ($script:Auto.Running -and -not (Ask "The automation queue is still running (task $($script:Auto.Index + 1) of $(@($script:AutoRun).Count)).${NL}${NL}Close anyway? The current task''s window keeps running, but the rest of the queue does not run and there is no final summary." ''Automation running'' ''Warning'' ''Button2'')) { $_.Cancel = $true; return }'
W '    try { $timer.Stop() } catch {}'
W '})'
W '#endregion AUTOMATION'
$region = $o.ToString()

# insert into the beta copy: after the Registry Backups tab, and the tab scrolls when the window is small
$bf = Join-Path $repo 'tools\WinFixKit.ps1'
$t = [IO.File]::ReadAllText($bf)
if ($t -match '(?m)^#region AUTOMATION\r?$') { $s = [regex]::Match($t, '(?m)^#region AUTOMATION\r?$').Index; $e = [regex]::Match($t, '(?m)^#endregion AUTOMATION').Index + '#endregion AUTOMATION'.Length; if ($e -le $s) { throw 'region end not found' }; $t = $t.Substring(0, $s) + $region.TrimEnd() + $t.Substring($e) }
else {
    $anchor = '$script:Tabs.TabPages.Add($rpage)'
    $i = $t.IndexOf($anchor); if ($i -lt 0) { throw 'anchor not found' }
    $i += $anchor.Length
    $t = $t.Substring(0, $i) + "`r`n`r`n" + $region.TrimEnd() + $t.Substring($i)
    $t = Edit-Once $t 'Initialize-WrtWindow $script:Form @() 900 600' 'Initialize-WrtWindow $script:Form @($tpAuto) 900 600'
}
$t = $t -replace "(?<!\r)\n", "`r`n"
[IO.File]::WriteAllText($bf, $t, (New-Object Text.ASCIIEncoding))
"region lines: $(($region -split "`n").Count)"
