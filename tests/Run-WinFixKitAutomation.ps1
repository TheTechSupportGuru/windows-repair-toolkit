# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-WinFixKitAutomation.ps1 - runs the Automation tab of tools\WinFixKit.ps1 through its REAL code:
# real task windows, real fixes, result read-back, per-task popups, the final summary and the HTML report. Every
# question is answered Yes (message boxes are logged), every summary window is read and closed.
# THE FIXES REALLY CHANGE THE PC (registry, services, network, apps). ONLY on a test VM, AFTER taking a snapshot.
#   -All            : every catalog task, 10 per queue, network-disrupting fixes in the last queue (run AS ADMINISTRATOR)
#   -Queue 'a,b,c'  : one queue of these task ids
#   -List           : write the task ids to tasks.txt and stop
# Output: -OutDir (report.txt = everything in one file; per queue: msgs.txt, popups.txt, automation-summary.txt,
#         results.csv, the HTML report, and WinFixKit's own data folder with Task-Results)
#   powershell -ExecutionPolicy Bypass -File .\tests\Run-WinFixKitAutomation.ps1 -All -OutDir C:\Users\Public\wfk-auto-test
param([string]$Script = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\WinFixKit.ps1'),
      [string]$OutDir = 'C:\Users\Public\wfk-auto-test', [string]$Queue = '', [switch]$All, [switch]$List, [int]$BatchMinutes = 120)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Report = Join-Path $OutDir 'report.txt'
function Write-Report([string]$m) { $l = '{0:HH:mm:ss}  {1}' -f (Get-Date), $m; Add-Content -LiteralPath $Report -Value $l; Write-Host $l }
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---- the catalog, read from the script with the parser (no window) ----
function Get-Catalog {
    $ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
    $tmp = Join-Path $env:TEMP ('wfk-cat-' + [guid]::NewGuid().ToString('N'))
    $script:RootDir = $tmp; $script:LogDir = "$tmp\Logs"; $script:ReportDir = "$tmp\Reports"; $script:RegDir = "$tmp\Reg"; $script:RegKeyDir = "$tmp\Reg\Keys"; $script:RegFullDir = "$tmp\Reg\Full"
    $script:WfkSelf = $Script; $IsWinPE = $false; $NL = "`r`n"
    foreach ($fn in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -in 'Esc-Sq', 'New-TaskRule', 'New-AutoTask', 'New-WfkTasks', 'Get-WfkPreset' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
    foreach ($s in $ast.EndBlock.Statements) { if ($s.Extent.Text -match '^\$(Sections|AutoScriptRestore|AutoRestore|AutoCatalog) *=|^\$AutoRestore \| Add-Member') { . ([scriptblock]::Create($s.Extent.Text)) } }
    $AutoCatalog
}

if ($List) {
    Get-Catalog | ForEach-Object { '{0,-70} {1,-10} {2}' -f $_.Id, $_.Kind, $_.Name } | Set-Content (Join-Path $OutDir 'tasks.txt')
    return
}

if ($All) {
    if (-not $IsAdmin) { Write-Report 'NOT STARTED: run this AS ADMINISTRATOR (the fixes need it).'; return }
    $cat = @(Get-Catalog)
    # network-disrupting fixes last (they can drop the connection for a moment; some need a restart to finish)
    $late = '^fix-network-(release|reset|full)|^fix-smb-24h2-fix-restart'
    $status = @($cat | Where-Object { $_.Kind -eq 'wfk-status' })
    $fixes = @($cat | Where-Object { $_.Kind -eq 'wfk-fix' -and $_.Id -notmatch $late })
    $lateFix = @($cat | Where-Object { $_.Kind -eq 'wfk-fix' -and $_.Id -match $late })
    $order = @('restore-point') + @($status.Id) + @($fixes.Id)
    $batches = New-Object Collections.ArrayList
    for ($i = 0; $i -lt $order.Count; $i += 10) { [void]$batches.Add(@($order[$i..([Math]::Min($i + 9, $order.Count - 1))])) }
    if ($lateFix.Count) { [void]$batches.Add(@($lateFix.Id)) }
    Write-Report ("START: {0} tasks ({1} status checks, {2} fixes + restore point) in {3} queues. Script: {4}" -f $cat.Count, $status.Count, ($fixes.Count + $lateFix.Count), $batches.Count, $Script)
    $n = 0
    foreach ($b in $batches) {
        $n++; $qd = Join-Path $OutDir ('queue-{0:D2}' -f $n)
        Write-Report ("QUEUE $n of $($batches.Count): " + ($b -join ', '))
        $p = Start-Process powershell.exe -PassThru -WindowStyle Minimized -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"", '-Script', "`"$Script`"", '-OutDir', "`"$qd`"", '-Queue', ($b -join ',')
        if (-not $p.WaitForExit($BatchMinutes * 60000)) { Write-Report "  TIMEOUT after $BatchMinutes min - stopped"; try { $p.Kill() } catch {} }
        $csv = Join-Path $qd 'results.csv'
        if (Test-Path $csv) { foreach ($r in Import-Csv $csv) { Write-Report ('  {0,-8} {1,-62} {2}' -f $r.Status, $r.Name, $r.Find) } }
        else { Write-Report '  NO RESULTS (see msgs.txt / error.txt in the queue folder)' }
        foreach ($f in 'msgs.txt', 'error.txt', 'not-started.txt') { $x = Join-Path $qd $f; if (Test-Path $x) { Get-Content $x | Where-Object { $_ -notmatch '^ASK \[Start automation\]' -and $_ -match '^\S' -and $_ -notmatch '^(These fixes change|Each task opens)' } | Select-Object -First 8 | ForEach-Object { Write-Report "  $f> $_" } } }
    }
    Write-Report 'DONE'
    return
}

# ---- one queue: the beta itself, with the queue started by this script ----
$src = [IO.File]::ReadAllText($Script)
$rep = @(
    @("function Msg(`$t, `$c = `$AppName, `$i = 'Information') { [void][Windows.Forms.MessageBox]::Show([string]`$t, [string]`$c, 'OK', `$i) }",
      "function Msg(`$t, `$c = `$AppName, `$i = 'Information') { Add-Content -LiteralPath (Join-Path `$SmokeDir 'msgs.txt') -Value (`"[`$c] `$t`") }"),
    @("function Ask(`$t, `$c = 'Confirm', `$i = 'Question', `$def = 'Button1') { return ([Windows.Forms.MessageBox]::Show([string]`$t, [string]`$c, 'YesNo', `$i, `$def) -eq 'Yes') }",
      "function Ask(`$t, `$c = 'Confirm', `$i = 'Question', `$def = 'Button1') { Add-Content -LiteralPath (Join-Path `$SmokeDir 'msgs.txt') -Value (`"ASK [`$c] `$t`"); return `$true }"),
    @('$script:WfkSelf = $PSCommandPath', "`$script:WfkSelf = '$($Script.Replace("'", "''"))'"),
    @('Start-Process -FilePath $html;', '')
)
foreach ($r in $rep) { if (-not $src.Contains($r[0])) { throw "stub not applied: $($r[0].Substring(0, 50))" }; $src = $src.Replace($r[0], $r[1]) }
$hook = @'
$script:Grab = @{ Done = $false }
$script:Form.Add_Shown({
    $grab = New-Object Windows.Forms.Timer; $grab.Interval = 700
    $grab.Add_Tick({
        foreach ($f in @([Windows.Forms.Application]::OpenForms)) {
            if ($f -eq $script:Form -or -not $f.Visible) { continue }
            $rtx = $f.Controls | Where-Object { $_ -is [Windows.Forms.TextBox] -or $_ -is [Windows.Forms.RichTextBox] } | Select-Object -First 1
            $ban = $f.Controls | Where-Object { $_ -is [Windows.Forms.Label] } | Select-Object -First 2 | ForEach-Object { $_.Text }
            Add-Content (Join-Path $SmokeDir 'popups.txt') ("===== $($f.Text)`r`n" + ($ban -join "`r`n") + "`r`n" + $(if ($rtx) { $rtx.Text }))
            if ($f.Text -eq 'Automation summary') {
                $rt = $f.Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] } | Select-Object -First 1
                if ($rt) { [IO.File]::WriteAllText((Join-Path $SmokeDir 'automation-summary.txt'), $rt.Text) }
                $script:Grab.Done = $true
            }
            $f.Close()
        }
        if ($script:Grab.Done) {
            $this.Stop()
            $rows = @($script:AutoRun | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Status = $_.Status; Tone = $_.Tone; Find = $_.Find; Rc = $_.Rc; Started = $_.Started; Ended = $_.Ended; OutFile = $_.OutFile; Quote = (@($_.Quote) -join ' | ') } })
            $rows | Export-Csv (Join-Path $SmokeDir 'results.csv') -NoTypeInformation
            if ($script:LastAutoHtml) { Copy-Item -LiteralPath $script:LastAutoHtml (Join-Path $SmokeDir 'report.html') -ErrorAction SilentlyContinue }
            $script:Form.Close()
        }
    })
    $grab.Start()
    try {
        $script:Tabs.SelectedTab = $tpAuto
        $script:AutoQueue.Clear(); foreach ($id in ($SmokeQueue -split ',')) { if ($id) { [void]$script:AutoQueue.Add($id) } }
        Update-AutoList
        $chkAutoPop.Checked = $true; $chkAutoStop.Checked = $false; $chkAutoHtml.Checked = $true; $chkAutoSR.Checked = $true
        Start-AutoRun
        if (-not $script:Auto.Running) { Set-Content (Join-Path $SmokeDir 'not-started.txt') 'the queue was not started (see msgs.txt)'; $script:Grab.Done = $true }
    } catch { Add-Content (Join-Path $SmokeDir 'error.txt') "$($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"; $script:Grab.Done = $true }
})
[void]$script:Form.ShowDialog()
'@
if (-not $src.Contains('[void]$script:Form.ShowDialog()')) { throw 'ShowDialog line not found' }
$src = $src.Replace('[void]$script:Form.ShowDialog()', $hook)
$SmokeDir = $OutDir; $SmokeQueue = $Queue
try { . ([scriptblock]::Create($src)) -DataRoot (Join-Path $OutDir 'WinFixKit') }
catch { Add-Content (Join-Path $OutDir 'error.txt') "$($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" }
