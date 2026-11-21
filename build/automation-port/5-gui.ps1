# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# PART of the WinFixKit Automation port: build\Port-AutomationToWinFixKit.ps1 puts it into beta\WinFixKit-beta-automation.ps1.
# Not a script to run on its own. Lines starting with '# PART' and the licence lines above are left out of the output.

# ---- the Automation tab (ported layout; WinFixKit: no "live log windows" option, its own tab page) ----
$tpAuto = New-Ctl TabPage @{ Text = 'Automation (beta)'; Padding = (New-Object System.Windows.Forms.Padding 6); AutoScroll = $true }
# built at its design size and added to the tabs only after the anchors are set: anchors set on a page that already has
# another size are measured from that size, which pushed the Preset row onto the HTML report option
$tpAuto.Size = New-Object Drawing.Size(954, 470)
$lblAutoHead = New-AutoCtl 'Label' $tpAuto 12 6 930 32 'BETA. Run up to 10 status checks and fixes one after another on THIS PC. Each task opens its own window (it closes 15 seconds after the task ends) and gets a pass / fail result; a final summary lists them all. Needs administrator rights.'
$lblAutoHead.ForeColor = [Drawing.Color]::FromArgb(200, 110, 0)
[void](New-AutoCtl 'Label' $tpAuto 12 42 300 18 'Available tasks (double-click to add):')
$lstAutoCat = New-AutoCtl 'ListBox' $tpAuto 12 62 300 240; $lstAutoCat.DisplayMember = 'Name'; $lstAutoCat.HorizontalScrollbar = $true
foreach ($c in $AutoCatalog) { [void]$lstAutoCat.Items.Add($c) }
$lblAutoHelp = New-AutoCtl 'Label' $tpAuto 12 306 300 64 ''; $lblAutoHelp.ForeColor = 'DimGray'
$btnAutoAdd = New-AutoCtl 'Button' $tpAuto 318 150 72 30 'Add >'
[void](New-AutoCtl 'Label' $tpAuto 12 378 60 20 'Preset:')
$cmbAutoPreset = New-AutoCtl 'ComboBox' $tpAuto 62 375 250 24
foreach ($k in $AutoPresets.Keys) { [void]$cmbAutoPreset.Items.Add($k) }; $cmbAutoPreset.SelectedIndex = 0; $cmbAutoPreset.DropDownWidth = 360
$btnAutoPreset = New-AutoCtl 'Button' $tpAuto 318 374 72 26 'Load'
$tip.SetToolTip($btnAutoPreset, 'Replaces the queue with the chosen preset (you can still change it).')
[void](New-AutoCtl 'Label' $tpAuto 398 42 260 18 'Queue - runs from top to bottom:')
$lblAutoCount = New-AutoCtl 'Label' $tpAuto 760 42 182 18 ''; $lblAutoCount.TextAlign = 'TopRight'
$lvAuto = New-Object Windows.Forms.ListView
$lvAuto.Location = New-Object Drawing.Point(398, 62); $lvAuto.Size = New-Object Drawing.Size(544, 240)
$lvAuto.View = 'Details'; $lvAuto.FullRowSelect = $true; $lvAuto.HideSelection = $false; $lvAuto.MultiSelect = $false; $lvAuto.GridLines = $true
foreach ($col in @(@('#', 30), @('Task', 230), @('Status', 66), @('Result', 160), @('Time', 50))) { [void]$lvAuto.Columns.Add($col[0], $col[1]) }
$tpAuto.Controls.Add($lvAuto)
$btnAutoUp     = New-AutoCtl 'Button' $tpAuto 398 306 90 26 'Move up'
$btnAutoDown   = New-AutoCtl 'Button' $tpAuto 492 306 90 26 'Move down'
$btnAutoRemove = New-AutoCtl 'Button' $tpAuto 586 306 90 26 'Remove'
$btnAutoClear  = New-AutoCtl 'Button' $tpAuto 680 306 90 26 'Clear'
$chkAutoPop  = New-AutoCtl 'CheckBox' $tpAuto 398 338 270 22 'Pop up a summary after each task'; $chkAutoPop.Checked = $true
$chkAutoStop = New-AutoCtl 'CheckBox' $tpAuto 672 338 270 22 'Stop the queue if a task does not pass'
$chkAutoSR   = New-AutoCtl 'CheckBox' $tpAuto 398 362 270 22 'Turn on System Protection if it is off'
$tip.SetToolTip($chkAutoSR, 'For "Create a system restore point": turns System Protection on for the system drive first (Enable-ComputerRestore).')
$chkAutoHtml = New-AutoCtl 'CheckBox' $tpAuto 12 408 300 22 'Save an HTML report and open it at the end'; $chkAutoHtml.Checked = $true
$tip.SetToolTip($chkAutoHtml, 'An easy-to-read report: overall result and a colour-coded summary table at the top, every task''s details and full output below. Saved in WinFixKit\Task-Results.')
$btnAutoHtml = New-AutoCtl 'Button' $tpAuto 12 432 180 26 'Open last HTML report'
$chkAutoHtml.Anchor = 'Bottom,Left'; $btnAutoHtml.Anchor = 'Bottom,Left'
$btnAutoStart   = New-AutoCtl 'Button' $tpAuto 398 394 170 34 'Start queue'
$btnAutoStart.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$btnAutoStopReq = New-AutoCtl 'Button' $tpAuto 574 394 170 34 'Stop after this task'; $btnAutoStopReq.Enabled = $false
$lblAutoStatus  = New-AutoCtl 'Label' $tpAuto 750 392 192 44 ''
if ($IsWinPE) { $lblAutoStatus.Text = 'Automation needs a running Windows - not available in WinPE.'; $lblAutoStatus.ForeColor = 'Red' }
elseif (-not (Test-Admin)) { $lblAutoStatus.Text = 'Needs administrator rights: use "Relaunch as Administrator" at the bottom.'; $lblAutoStatus.ForeColor = [Drawing.Color]::FromArgb(200, 110, 0) }
# (ported) what grows with the window and what stays at the right edge
function Set-Anchor([string]$a, [object[]]$ctls) { foreach ($c in $ctls) { if ($c) { $c.Anchor = $a } } }
Set-Anchor 'Top,Left,Right'        @($lblAutoHead)
Set-Anchor 'Top,Bottom,Left'       @($lstAutoCat)
Set-Anchor 'Top,Bottom,Left,Right' @($lvAuto)
Set-Anchor 'Top,Right'             @($lblAutoCount)
Set-Anchor 'Bottom,Left'           (@($lblAutoHelp, $cmbAutoPreset, $btnAutoPreset, $btnAutoUp, $btnAutoDown, $btnAutoRemove, $btnAutoClear, $chkAutoPop, $chkAutoStop, $chkAutoSR, $btnAutoStart, $btnAutoStopReq) + @($tpAuto.Controls | Where-Object { $_.Text -eq 'Preset:' }))
Set-Anchor 'Bottom,Left,Right'     @($lblAutoStatus)
$script:Tabs.TabPages.Add($tpAuto)
# WinFixKit: the tab needs more height than the other tabs - give it more of the window while it is shown
$script:Tabs.Add_SelectedIndexChanged({
    try {
        $k = Get-WrtScale $script:Form
        if ($script:Tabs.SelectedTab -eq $tpAuto) { $split.SplitterDistance = [Math]::Max([int](340 * $k), [Math]::Min([int](520 * $k), $split.Height - [int](110 * $k))) }
        else { $split.SplitterDistance = [int](340 * $k) }
    } catch {}
})
# (ported) the shared timer: finished task windows
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    try { if ($script:TaskWatch.Count -and -not $script:InSummary) { Update-TaskWatch } }
    catch { if (-not $script:TickErr2) { $script:TickErr2 = $true; Log "Timer error (task windows): $($_.Exception.Message)" } }
})
