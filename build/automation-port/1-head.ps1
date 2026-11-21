# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# PART of the WinFixKit Automation port: build\Port-AutomationToWinFixKit.ps1 puts it into beta\WinFixKit-beta-automation.ps1.
# Not a script to run on its own. Lines starting with '# PART' and the licence lines above are left out of the output.
#region AUTOMATION
# =============================================================================================
#  AUTOMATION (BETA) - a queue of up to 10 status checks and fixes, run one after another, each in its own window,
#  with a pass / fail result per task, a final summary and an HTML report.
#  PORTED FROM WinSuperTool 1.9 ("10. AUTOMATION" and "task summaries"). The parts marked "(ported)" are
#  WinSuperTool's code word for word, with only these renames: New-Ctl -> New-AutoCtl and Safe -> Invoke-AutoSafe
#  (WinFixKit has its own New-Ctl and Safe with other meanings), $DataDir -> $script:RootDir, WinSuperTool-Data ->
#  WinFixKit. Parts marked "WinFixKit:" are adapted: the task list, no live-log option, no offline / WinPE queue,
#  the admin check.
#  RULE: change Automation in WinSuperTool FIRST, then port the change here (tests\Beta.Tests.ps1 checks that the
#  ported functions still match WinSuperTool's).
# =============================================================================================
# ---- WinFixKit: the small helpers WinSuperTool's Automation code expects ----
$AppName = 'WinFixKit (beta: Automation)'
$NL = "`r`n"
$IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
$PsExePath = Join-Path $PSHOME 'powershell.exe'; if (-not [IO.File]::Exists($PsExePath)) { $PsExePath = (Get-Process -Id $PID).Path }
$script:Consoles = New-Object Collections.ArrayList
$script:WfkSelf = $PSCommandPath
function Msg($t, $c = $AppName, $i = 'Information') { [void][Windows.Forms.MessageBox]::Show([string]$t, [string]$c, 'OK', $i) }
function Ask($t, $c = 'Confirm', $i = 'Question', $def = 'Button1') { return ([Windows.Forms.MessageBox]::Show([string]$t, [string]$c, 'YesNo', $i, $def) -eq 'Yes') }
function Log([string]$m) { Write-Out $m 'LightSkyBlue' }
function Invoke-AutoSafe([scriptblock]$Do) { try { & $Do } catch { Log "ERROR: $($_.Exception.Message)"; Msg $_.Exception.Message 'Error' 'Error' } }
function Esc-Sq([string]$s) { return ($s -replace "(['$([char]0x2018)-$([char]0x201B)])", '$1$1') }
# WinSuperTool's New-Ctl (type, parent, position, size, text); WinFixKit's own New-Ctl takes a property table
