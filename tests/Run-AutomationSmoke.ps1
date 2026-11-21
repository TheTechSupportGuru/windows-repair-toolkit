# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-AutomationSmoke.ps1 - drives the Automation tab of WinSuperTool through its real code: System Info collectors,
# then a queue run with real task windows, real result read-back, "repair only if needed" chains, per-task popups,
# the final summary and the HTML report. Every question is answered Yes (the queue starts), message boxes are logged.
#   no -RealQueue : harmless TEST tasks (one finds "repairable corruption" -> the repair is added, one fails)
#   -RealQueue 'dism-check,sfc-verify,...' : real catalog tasks (needs admin; repairs / installs change the PC!)
# Output: -OutDir (msgs.txt, popups.txt, automation-summary.txt, bounds.txt, timing.txt, WinSuperTool-Data\Task-Results)
#   .\tests\Run-AutomationSmoke.ps1 -Script .\beta\WinSuperTool.ps1 -OutDir $env:TEMP\wrt-auto
param([string]$Script = (Join-Path (Split-Path $PSScriptRoot -Parent) 'beta\WinSuperTool.ps1'), [string]$OutDir = (Join-Path $env:TEMP 'wrt-auto'),
      [string]$RealQueue = '', [double]$Scale = 1.0, [switch]$StopOnFail, [switch]$NoPopups, [switch]$NoHtml)
New-Item -ItemType Directory -Force $OutDir | Out-Null
Set-Location $OutDir
$src = [IO.File]::ReadAllText($Script)
$src = $src.Replace('if ($PSCommandPath) {', 'if ($false) {')
$src = $src.Replace("function Msg(`$t, `$c = `$AppName, `$i = 'Information') { [void][Windows.Forms.MessageBox]::Show([string]`$t, [string]`$c, 'OK', `$i) }",
                    "function Msg(`$t, `$c = `$AppName, `$i = 'Information') { Add-Content -LiteralPath (Join-Path `$SmokeDir 'msgs.txt') -Value (`"[`$c] `$t`") }")
$src = $src.Replace("function Ask(`$t, `$c = 'Confirm', `$i = 'Question', `$def = 'Button1') { return ([Windows.Forms.MessageBox]::Show([string]`$t, [string]`$c, 'YesNo', `$i, `$def) -eq 'Yes') }",
                    "function Ask(`$t, `$c = 'Confirm', `$i = 'Question', `$def = 'Button1') { Add-Content -LiteralPath (Join-Path `$SmokeDir 'msgs.txt') -Value (`"ASK [`$c] `$t`"); return `$true }")
if ($src -notmatch 'ASK \[') { throw 'Ask stub not applied' }
$src = $src.Replace('Start-Process -FilePath $html;', '')
if ($Scale -ne 1.0) {   # simulated scaled display: fonts x Scale, every form told the display is Scale x
    $src = $src.Replace('New-Object Drawing.SizeF(96, 96)', ('New-Object Drawing.SizeF({0}, {0})' -f [int](96 / $Scale)))
    $src = [regex]::Replace($src, "(Drawing\.Font\('[^']+', )(\d+(?:\.\d+)?)", { param($m) $m.Groups[1].Value + ([double]$m.Groups[2].Value * $Scale).ToString([Globalization.CultureInfo]::InvariantCulture) })
}
$hook = @'
# real screen capture (a RichTextBox does not draw itself with DrawToBitmap)
# (regression run: no screen grabs - they show whatever window is on top; results come from text and window data)
function Save-Png($f, $name) { }

$script:Grab = @{ N = 0; Done = $false }
$form.Add_Shown({
    $grab = New-Object Windows.Forms.Timer; $grab.Interval = 600
    $grab.Add_Tick({
        foreach ($f in @([Windows.Forms.Application]::OpenForms)) {
            if ($f -eq $form -or -not $f.Visible) { continue }
            $script:Grab.N++
            $nm = ($f.Text -replace '[^A-Za-z0-9]+', '-').Trim('-')
            $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea
            Add-Content (Join-Path $SmokeDir 'bounds.txt') ('{0,-60} bounds {1}  on screen: {2}' -f $f.Text, $f.Bounds, $wa.Contains($f.Bounds))
            Save-Png $f ('{0:D2}-{1}.png' -f $script:Grab.N, $nm)
            $rtx = $f.Controls | Where-Object { $_ -is [Windows.Forms.TextBox] -or $_ -is [Windows.Forms.RichTextBox] } | Select-Object -First 1
            if ($rtx) { Add-Content (Join-Path $SmokeDir 'popups.txt') ("===== $($f.Text)
" + $rtx.Text) }
            if ($f.Text -eq 'Automation summary') {
                $rt = $f.Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] } | Select-Object -First 1
                if ($rt) { [IO.File]::WriteAllText((Join-Path $SmokeDir 'automation-summary.txt'), $rt.Text) }
                $script:Grab.Done = $true
            }
            $f.Close()
        }
        if ($script:Grab.Done) { $this.Stop(); Add-Content (Join-Path $SmokeDir 'options.txt') ("popups $(-not $NoPopups), stop on fail $([bool]$StopOnFail), html $(-not $NoHtml)"); $form.Close() }
    })
    $grab.Start()
    # 1) collectors -> text + timing
    foreach ($n in 'Get-WindowsInfo', 'Get-NetInfo', 'Get-GpuInfo', 'Get-AudioInfo', 'Get-BtInfo', 'Get-WifiInfo') {
        $t0 = Get-Date
        try { $bl = @(& $n); [IO.File]::WriteAllText((Join-Path $SmokeDir "$n.txt"), (Format-InfoText $bl $n)); Add-Content (Join-Path $SmokeDir 'timing.txt') ('{0,-16} {1,5:N1} s  {2} blocks' -f $n, ((Get-Date) - $t0).TotalSeconds, $bl.Count) }
        catch { Add-Content (Join-Path $SmokeDir 'timing.txt') "$n ERROR: $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)" }
    }
    # 2) tool buttons that are greyed out here
    [IO.File]::WriteAllLines((Join-Path $SmokeDir 'wintools.txt'), [string[]]@($WinTools | ForEach-Object { '{0,-28} {1}' -f $_.Name, $(if (Test-WinTool $_) { 'available' } else { 'NOT AVAILABLE' }) }))
    # 3) screenshots of the tabs and two info windows
    $tabs.SelectedTab = $tpInfo; $form.Refresh(); Save-Png $form 'tab-systeminfo.png'
    Show-Info 'Network connections' @(Get-NetInfo) 'Connected adapters first; the one used for internet is marked.'
    Show-Info 'Windows version and product keys' @(Get-WindowsInfo)
    # 4) automation with harmless test tasks (real task windows)
    $script:AutoCatalog = @($AutoCatalog) + @(
        (New-AutoTask 'test-scan' 'TEST: scan that finds repairable corruption' 'dism-check' 'test' @() { param($o) @{ Call = "Write-Host 'The component store is repairable.'; Write-Host 'The operation completed successfully.'; `$global:LASTEXITCODE = 0"; Line = 'test scan' } } @{ If = 'can be repaired'; Add = 'test-fix'; Why = 'added because DISM found repairable corruption' })
        (New-AutoTask 'test-fix' 'TEST: repair' 'dism-restore' 'test' @() { param($o) @{ Call = "Start-Sleep 2; Write-Host 'The restore operation completed successfully.'; Write-Host 'The component store corruption was repaired.'; `$global:LASTEXITCODE = 0"; Line = 'test repair' } })
        (New-AutoTask 'test-fail' 'TEST: winget missing' 'winget' 'test' @() { param($o) @{ Call = "Write-Host 'winget is not available for this account.'; `$global:LASTEXITCODE = 1"; Line = 'test winget' } })
    )
    $tabs.SelectedTab = $tpAuto
    $script:AutoQueue.Clear()
    if ($RealQueue) { foreach ($id in ($RealQueue -split ',')) { [void]$script:AutoQueue.Add($id) } }
    else { [void]$script:AutoQueue.Add('test-scan'); [void]$script:AutoQueue.Add('test-fail') }
    Update-AutoList
    $form.Refresh(); Save-Png $form 'tab-automation-before.png'
    $tpAuto.Controls | Sort-Object Top, Left | ForEach-Object { Add-Content (Join-Path $SmokeDir 'auto-layout.txt') ('{0,-12} {1,-45} y {2,4}-{3,4}  x {4,4}-{5,4}  anchor {6}' -f $_.GetType().Name, ($_.Text -replace '\s+', ' ').Substring(0, [Math]::Min(45, ($_.Text -replace '\s+', ' ').Length)), $_.Top, $_.Bottom, $_.Left, $_.Right, $_.Anchor) }; Add-Content (Join-Path $SmokeDir 'auto-layout.txt') ('page client {0}  display {1}  minsize {2}  form {3}' -f $tpAuto.ClientSize, $tpAuto.DisplayRectangle, $tpAuto.AutoScrollMinSize, $form.Size)
    $chkAutoPop.Checked = -not $NoPopups; $chkAutoStop.Checked = [bool]$StopOnFail; if (Get-Variable chkAutoHtml -ErrorAction SilentlyContinue) { $chkAutoHtml.Checked = -not $NoHtml }
    Start-AutoRun
    $script:AutoShot = New-Object Windows.Forms.Timer; $script:AutoShot.Interval = 9000
    $script:AutoShot.Add_Tick({ Save-Png $form ('tab-automation-running-{0:HHmmss}.png' -f (Get-Date)); if (-not $script:Auto.Running) { $this.Stop() } })
    $script:AutoShot.Start()
})
[void]$form.ShowDialog()
'@
$src = $src.Replace('[void]$form.ShowDialog()', $hook)
$SmokeDir = $OutDir
. ([scriptblock]::Create($src))
'smoke done'
