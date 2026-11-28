# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# Version 0.1 beta 1
<#
.SYNOPSIS
  Windows GUI for Get-DiagTools.ps1. Tick tools, pick an output folder, click Download.
.NOTES
  Needs Get-DiagTools.ps1 in the same folder. Downloads run one at a time on the UI thread.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Get-DiagTools.ps1')

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Diagnostic Tool Downloader'
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(700, 450)

$lblDir = New-Object System.Windows.Forms.Label
$lblDir.Text = 'Save to:'
$lblDir.Location = New-Object System.Drawing.Point(12, 15)
$lblDir.AutoSize = $true

$txtDir = New-Object System.Windows.Forms.TextBox
$txtDir.Location = New-Object System.Drawing.Point(70, 12)
$txtDir.Size = New-Object System.Drawing.Size(640, 23)
$txtDir.Anchor = 'Top,Left,Right'
$txtDir.Text = Join-Path $PSScriptRoot 'Downloads'

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(720, 10)
$btnBrowse.Size = New-Object System.Drawing.Size(150, 27)
$btnBrowse.Anchor = 'Top,Right'

$lvTools = New-Object System.Windows.Forms.ListView
$lvTools.Location = New-Object System.Drawing.Point(12, 45)
$lvTools.Size = New-Object System.Drawing.Size(858, 440)
$lvTools.Anchor = 'Top,Bottom,Left,Right'
$lvTools.View = 'Details'
$lvTools.FullRowSelect = $true
$lvTools.CheckBoxes = $true
$lvTools.GridLines = $true
[void]$lvTools.Columns.Add('Tool', 230)
[void]$lvTools.Columns.Add('Status', 480)
[void]$lvTools.Columns.Add('Source', 130)

$items = @{}
foreach ($t in $Tools) {
    $li = New-Object System.Windows.Forms.ListViewItem($t.Name)
    if ($t.Manual) {
        $li.SubItems.Add("Manual: $($t.Manual). Double-click to open the page.") | Out-Null
        $li.SubItems.Add('Manual') | Out-Null
        $li.Checked = $false
        $li.ForeColor = [System.Drawing.Color]::Gray
    } else {
        $li.SubItems.Add('Ready') | Out-Null
        $li.SubItems.Add(([uri]$t.Url).Host) | Out-Null
        $li.Checked = $true
    }
    $li.Tag = $t
    [void]$lvTools.Items.Add($li)
}

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = 'Select all'
$btnAll.Location = New-Object System.Drawing.Point(12, 495)
$btnAll.Size = New-Object System.Drawing.Size(100, 28)
$btnAll.Anchor = 'Bottom,Left'

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = 'Select none'
$btnNone.Location = New-Object System.Drawing.Point(120, 495)
$btnNone.Size = New-Object System.Drawing.Size(100, 28)
$btnNone.Anchor = 'Bottom,Left'

$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = 'Re-download files that already exist'
$chkForce.Location = New-Object System.Drawing.Point(240, 500)
$chkForce.AutoSize = $true
$chkForce.Anchor = 'Bottom,Left'

$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = 'Download selected'
$btnGo.Location = New-Object System.Drawing.Point(600, 493)
$btnGo.Size = New-Object System.Drawing.Size(150, 30)
$btnGo.Anchor = 'Bottom,Right'

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open folder'
$btnOpen.Location = New-Object System.Drawing.Point(760, 493)
$btnOpen.Size = New-Object System.Drawing.Size(110, 30)
$btnOpen.Anchor = 'Bottom,Right'

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 535)
$progress.Size = New-Object System.Drawing.Size(858, 18)
$progress.Anchor = 'Bottom,Left,Right'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Location = New-Object System.Drawing.Point(12, 558)
$lblStatus.Size = New-Object System.Drawing.Size(858, 20)
$lblStatus.Anchor = 'Bottom,Left,Right'

$form.Controls.AddRange(@($lblDir, $txtDir, $btnBrowse, $lvTools, $btnAll, $btnNone, $chkForce, $btnGo, $btnOpen, $progress, $lblStatus))

$btnBrowse.Add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Choose where to save the tools'
    $fb.SelectedPath = $txtDir.Text
    if ($fb.ShowDialog() -eq 'OK') { $txtDir.Text = $fb.SelectedPath }
})

$btnAll.Add_Click({ foreach ($li in $lvTools.Items) { if (-not $li.Tag.Manual) { $li.Checked = $true } } })
$btnNone.Add_Click({ foreach ($li in $lvTools.Items) { $li.Checked = $false } })

$btnOpen.Add_Click({
    New-Item -ItemType Directory -Force -Path $txtDir.Text | Out-Null
    Start-Process explorer.exe $txtDir.Text
})

$lvTools.Add_MouseDoubleClick({
    $hit = $lvTools.HitTest($_.Location)
    if ($hit.Item -and $hit.Item.Tag.Manual) { Start-Process $hit.Item.Tag.Url }
})

$btnGo.Add_Click({
    $chosen = @($lvTools.CheckedItems | Where-Object { -not $_.Tag.Manual })
    if ($chosen.Count -eq 0) { $lblStatus.Text = 'Nothing selected.'; return }
    $btnGo.Enabled = $false
    $progress.Maximum = $chosen.Count
    $progress.Value = 0
    $ok = 0; $fail = 0
    foreach ($li in $chosen) {
        $t = $li.Tag
        $dir = Join-Path $txtDir.Text $t.Name
        $lblStatus.Text = "Downloading $($t.Name)..."
        $li.SubItems[1].Text = 'Downloading...'
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $chkForce.Checked -and (Test-Path $dir) -and (Get-ChildItem $dir -File -ErrorAction SilentlyContinue)) {
            $li.SubItems[1].Text = 'Already downloaded (tick "Re-download" to replace)'
            $li.ForeColor = [System.Drawing.Color]::DarkGoldenrod
        } else {
            try {
                $file = Get-Tool $t $dir
                $li.SubItems[1].Text = $file
                $li.ForeColor = [System.Drawing.Color]::DarkGreen
                $ok++
            } catch {
                $li.SubItems[1].Text = 'FAILED: ' + $_.Exception.Message
                $li.ForeColor = [System.Drawing.Color]::Firebrick
                $fail++
            }
        }
        $progress.Value++
        [System.Windows.Forms.Application]::DoEvents()
    }
    $lblStatus.Text = "Done. $ok downloaded, $fail failed."
    $btnGo.Enabled = $true
})

[void]$form.ShowDialog()

