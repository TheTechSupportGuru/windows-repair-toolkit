#requires -Version 5.1
# Version 1.8 (2026-11-19) - edited copy. What changed: Edited scripts\V1.8\CHANGES.md
<#
  Monitor-Logs.ps1  -  Live log monitor launcher for Windows 11
  Pick logs, press "Launch selected", and each log opens in its OWN PowerShell
  window running:  Get-Content <log> -Tail 20 -Wait
  Event Viewer logs are tailed live with Get-WinEvent (evtx files can't be tailed as text).
  Right-click > "Run with PowerShell"  (asks for admin rights itself)
#>

# ---------- 64-bit + admin ----------
# A 32-bit host would see SysWOW64 and the 32-bit view of the logs: relaunch 64-bit first.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    exit
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" -ErrorAction Stop
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show("The log monitor needs administrator rights, and the UAC prompt was cancelled or failed:`r`n`r`n$($_.Exception.Message)", 'Live Log Monitor', 'OK', 'Warning')
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$W = $env:SystemDrive     # Windows drive (was hard-coded C:)
$PsExePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------- what can be monitored ----------
# Type: File = Get-Content -Wait | Filter = same, but only lines matching Pattern
#       Evt  = live Event Viewer channel (optional Ids) | Dir = watch a folder for new files
function Item($section, $name, $type, $target, $extra = $null) {
    [pscustomobject]@{ Section = $section; Name = $name; Type = $type; Target = $target; Extra = $extra }
}

$Items = @(
    # --- Windows Update ---
    Item 'Windows Update' 'ReportingEvents.log'                          'File' "$W\Windows\SoftwareDistribution\ReportingEvents.log"
    Item 'Windows Update' 'Event: WindowsUpdateClient/Operational'       'Evt'  'Microsoft-Windows-WindowsUpdateClient/Operational'
    Item 'Windows Update' 'Event: Delivery Optimization/Operational'     'Evt'  'Microsoft-Windows-DeliveryOptimization/Operational'
    Item 'Windows Update' 'Event: BITS-Client/Operational'               'Evt'  'Microsoft-Windows-Bits-Client/Operational'

    # --- SFC / DISM / CBS ---
    Item 'SFC / DISM / CBS' 'dism.log'                                   'File' "$W\Windows\Logs\DISM\dism.log"
    Item 'SFC / DISM / CBS' 'CBS.log (full)'                             'File' "$W\Windows\Logs\CBS\CBS.log"
    Item 'SFC / DISM / CBS' 'CBS.log - SFC lines only ([SR])'            'Filter' "$W\Windows\Logs\CBS\CBS.log" '\[SR\]'
    Item 'SFC / DISM / CBS' 'DPX setupact.log'                           'File' "$W\Windows\Logs\DPX\setupact.log"
    Item 'SFC / DISM / CBS' 'poqexec.log (pending operations)'           'File' "$W\Windows\WinSxS\poqexec.log"
    Item 'SFC / DISM / CBS' 'setupapi.dev.log (drivers/devices)'         'File' "$W\Windows\inf\setupapi.dev.log"

    # --- Setup / Upgrade ---
    Item 'Setup / Upgrade' 'Windows\Panther\setupact.log'                'File' "$W\Windows\Panther\setupact.log"
    Item 'Setup / Upgrade' 'Windows\Panther\setuperr.log'                'File' "$W\Windows\Panther\setuperr.log"
    Item 'Setup / Upgrade' '$WINDOWS.~BT Panther\setupact.log'           'File' (Join-Path $W '$WINDOWS.~BT\Sources\Panther\setupact.log')
    Item 'Setup / Upgrade' '$WINDOWS.~BT Panther\setuperr.log'           'File' (Join-Path $W '$WINDOWS.~BT\Sources\Panther\setuperr.log')
    Item 'Setup / Upgrade' 'MoSetup BlueBox.log'                         'File' "$W\Windows\Logs\MoSetup\BlueBox.log"

    # --- Event Viewer (live) ---
    Item 'Event Viewer (live)' 'System'                                  'Evt'  'System'
    Item 'Event Viewer (live)' 'Application'                             'Evt'  'Application'
    Item 'Event Viewer (live)' 'Setup'                                   'Evt'  'Setup'
    Item 'Event Viewer (live)' 'Security'                                'Evt'  'Security'
    Item 'Event Viewer (live)' 'CodeIntegrity/Operational'               'Evt'  'Microsoft-Windows-CodeIntegrity/Operational'

    # --- Crashes ---
    Item 'Crashes' 'System: crash/shutdown events (41,1001,1074,1076,6008)' 'Evt' 'System'      '41,1001,1074,1076,6008'
    Item 'Crashes' 'Application: crashes/hangs (1000,1001,1002)'            'Evt' 'Application' '1000,1001,1002'
    Item 'Crashes' 'Watch folder: Windows\Minidump'                      'Dir' "$W\Windows\Minidump"
    Item 'Crashes' 'Watch folder: WER ReportQueue'                          'Dir' "$W\ProgramData\Microsoft\Windows\WER\ReportQueue"
    Item 'Crashes' 'Watch folder: LiveKernelReports'                        'Dir' "$W\Windows\LiveKernelReports"
)

# ---------- child-window script templates ----------
$tplFile = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$p = '__TARGET__'
Write-Host "Monitoring: $p   (Ctrl+C to stop)" -ForegroundColor Cyan
while (-not (Test-Path -LiteralPath $p)) { Write-Host "Waiting for file to exist..." -ForegroundColor Yellow; Start-Sleep 3 }
Get-Content -LiteralPath $p -Tail __TAIL__ -Wait
'@

$tplFilter = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$p = '__TARGET__'
Write-Host "Monitoring: $p  filter: __PATTERN__   (Ctrl+C to stop)" -ForegroundColor Cyan
while (-not (Test-Path -LiteralPath $p)) { Write-Host "Waiting for file to exist..." -ForegroundColor Yellow; Start-Sleep 3 }
Get-Content -LiteralPath $p -Tail __FILTERTAIL__ -Wait | Select-String -Pattern '__PATTERN__'
'@

$tplEvt = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$log = '__TARGET__'; $ids = @(__IDS__); $tail = __TAIL__
try { Get-WinEvent -ListLog $log -ErrorAction Stop | Out-Null }
catch { Write-Host "Cannot open event log '$log': $($_.Exception.Message)" -ForegroundColor Red; return }
function Show($e) {
    $msg = ($e.Message -split "`r?`n")[0]
    $col = switch ($e.Level) { 1 {'Red'} 2 {'Red'} 3 {'Yellow'} default {'Gray'} }
    Write-Host ('{0:yyyy-MM-dd HH:mm:ss} [{1}] ID {2} {3}: {4}' -f $e.TimeCreated, $e.LevelDisplayName, $e.Id, $e.ProviderName, $msg) -ForegroundColor $col
}
$idq = if ($ids.Count) { ' and (' + (($ids | ForEach-Object { "EventID=$_" }) -join ' or ') + ')' } else { '' }
function Get-Ev($max) {
    $f = @{ LogName = $log }
    if ($ids.Count) { $f.Id = $ids }
    Get-WinEvent -FilterHashtable $f -MaxEvents $max -ErrorAction SilentlyContinue
}
function Get-Top { try { (Get-WinEvent -LogName $log -MaxEvents 1 -ErrorAction Stop).RecordId } catch { 0 } }
Write-Host "Live event monitor: $log   (Ctrl+C to stop)" -ForegroundColor Cyan
$last = [long](Get-Top)
Get-Ev $tail | Sort-Object RecordId | ForEach-Object { Show $_ }
while ($true) {
    Start-Sleep 2
    # one cheap read of the newest record; only when something new arrived, ask Windows for exactly the new records
    # (it used to read and render the newest 100 events every 2 seconds, in every monitor window)
    $top = [long](Get-Top)
    if ($top -lt $last) { Write-Host '--- the log was cleared ---' -ForegroundColor Yellow; $last = 0 }
    if ($top -gt $last) {
        Get-WinEvent -LogName $log -FilterXPath "*[System[EventRecordID>$last$idq]]" -ErrorAction SilentlyContinue |
            Sort-Object RecordId | ForEach-Object { Show $_ }
        $last = $top
    }
}
'@

$tplDir = @'
$Host.UI.RawUI.WindowTitle = '__TITLE__'
$d = '__TARGET__'
Write-Host "Watching folder: $d   (Ctrl+C to stop)" -ForegroundColor Cyan
while (-not (Test-Path -LiteralPath $d)) { Write-Host "Waiting for folder to exist..." -ForegroundColor Yellow; Start-Sleep 3 }
$seen = @{}
Write-Host "Existing files:" -ForegroundColor Gray
Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
    $seen[$_.FullName] = $_.Length
    Write-Host ('{0:yyyy-MM-dd HH:mm:ss}  {1,12:N0} bytes  {2}' -f $_.LastWriteTime, $_.Length, $_.FullName) -ForegroundColor Gray
}
Write-Host "--- waiting for new files ---" -ForegroundColor Cyan
while ($true) {
    Start-Sleep 3
    Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $seen.ContainsKey($_.FullName)) {
            $seen[$_.FullName] = $_.Length
            Write-Host ('{0:yyyy-MM-dd HH:mm:ss}  NEW  {1:N0} bytes  {2}' -f (Get-Date), $_.Length, $_.FullName) -ForegroundColor Green
        }
    }
}
'@

# ---------- launching ----------
$script:procs = New-Object System.Collections.ArrayList

# PowerShell also treats the typographic quotes U+2018-U+201B as single quotes (e.g. O<U+2019>Brien), so double those too
function Esc([string]$s) { $s -replace "(['$([char]0x2018)-$([char]0x201B)])", '$1$1' }

function Start-Monitor($item, [int]$tail) {
    $title = Esc ("MONITOR: " + $item.Name)
    $tpl = switch ($item.Type) {
        'File'   { $tplFile }
        'Filter' { $tplFilter }
        'Evt'    { $tplEvt }
        'Dir'    { $tplDir }
    }
    # event IDs go into the child script as CODE, so only whole numbers are allowed (was pasted in as-is)
    $ids = ''
    if ($item.Type -eq 'Evt' -and $item.Extra) { $ids = (@("$($item.Extra)" -split ',' | ForEach-Object { [int]$_.Trim() }) -join ',') }
    $code = $tpl.Replace('__TITLE__', $title).
                 Replace('__TARGET__', (Esc $item.Target)).
                 Replace('__FILTERTAIL__', "$([Math]::Max($tail, 300))").
                 Replace('__TAIL__', "$tail").
                 Replace('__PATTERN__', (Esc "$($item.Extra)")).
                 Replace('__IDS__', $ids)
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $p = Start-Process -FilePath $PsExePath -PassThru -ArgumentList '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc
    # forget windows the user already closed (the list used to grow forever)
    foreach ($old in @($script:procs)) { if ($old.HasExited) { $script:procs.Remove($old); $old.Dispose() } }
    [void]$script:procs.Add($p)
}

# ---------- GUI ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'Live Log Monitor'
$form.Size = New-Object Drawing.Size(660, 680)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

$lbl = New-Object Windows.Forms.Label
$lbl.Text = 'Tick the logs to watch, then press "Launch selected". Each log opens in its own window.'
$lbl.Location = '12,8'; $lbl.Size = '620,22'
$form.Controls.Add($lbl)

$panel = New-Object Windows.Forms.Panel
$panel.Location = '12,34'; $panel.Size = '620,396'
$panel.AutoScroll = $true; $panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

$checks = @{}    # item name+section -> checkbox
$y = 6
foreach ($sec in ($Items | Select-Object -ExpandProperty Section -Unique)) {
    $hdr = New-Object Windows.Forms.Label
    $hdr.Text = $sec
    $hdr.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
    $hdr.Location = "6,$y"; $hdr.Size = '300,22'
    $panel.Controls.Add($hdr)

    $secBoxes = New-Object System.Collections.ArrayList
    $bAll = New-Object Windows.Forms.Button
    $bAll.Text = 'All'; $bAll.Location = '420,' + ($y - 1); $bAll.Size = '50,24'
    $bNone = New-Object Windows.Forms.Button
    $bNone.Text = 'None'; $bNone.Location = '474,' + ($y - 1); $bNone.Size = '50,24'
    $bGo = New-Object Windows.Forms.Button
    $bGo.Text = 'Launch section'; $bGo.Location = '528,' + ($y - 1); $bGo.Size = '84,24'
    $bGo.Font = New-Object Drawing.Font('Segoe UI', 8)
    $panel.Controls.AddRange(@($bAll, $bNone, $bGo))
    $y += 28

    foreach ($it in ($Items | Where-Object Section -eq $sec)) {
        $cb = New-Object Windows.Forms.CheckBox
        $cb.Text = $it.Name
        $cb.Tag = $it
        $cb.Location = "22,$y"; $cb.Size = '570,22'
        $panel.Controls.Add($cb)
        [void]$secBoxes.Add($cb)
        $checks["$sec|$($it.Name)"] = $cb
        $y += 24
    }
    $y += 10

    $bAll.Tag  = $secBoxes; $bNone.Tag = $secBoxes; $bGo.Tag = $secBoxes
    $bAll.Add_Click({  foreach ($c in $this.Tag) { $c.Checked = $true  } })
    $bNone.Add_Click({ foreach ($c in $this.Tag) { $c.Checked = $false } })
    $bGo.Add_Click({
        foreach ($c in $this.Tag) { Start-Monitor $c.Tag ([int]$numTail.Value); Start-Sleep -Milliseconds 250 }
        $status.Text = "Launched section. Open monitor windows: $(@($script:procs | Where-Object { -not $_.HasExited }).Count)"
    })
}

# ---- paste-a-path section ----
$lblPaste = New-Object Windows.Forms.Label
$lblPaste.Text = 'Paste log path(s) from anywhere (one per line; quotes and %variables% are OK):'
$lblPaste.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$lblPaste.Location = '12,438'; $lblPaste.Size = '620,20'

$txtPaste = New-Object Windows.Forms.TextBox
$txtPaste.Multiline = $true; $txtPaste.ScrollBars = 'Vertical'; $txtPaste.WordWrap = $false
$txtPaste.Location = '12,460'; $txtPaste.Size = '470,58'

$btnPaste = New-Object Windows.Forms.Button
$btnPaste.Text = 'Monitor pasted log(s)'; $btnPaste.Location = '490,460'; $btnPaste.Size = '142,28'

$btnPasteClear = New-Object Windows.Forms.Button
$btnPasteClear.Text = 'Clear box'; $btnPasteClear.Location = '490,490'; $btnPasteClear.Size = '142,28'

# bottom controls
$lblTail = New-Object Windows.Forms.Label
$lblTail.Text = 'Tail lines:'; $lblTail.Location = '14,536'; $lblTail.Size = '65,22'
$numTail = New-Object Windows.Forms.NumericUpDown
$numTail.Minimum = 1; $numTail.Maximum = 5000; $numTail.Value = 20
$numTail.Location = '82,533'; $numTail.Size = '65,24'

$btnLaunch = New-Object Windows.Forms.Button
$btnLaunch.Text = 'Launch selected'; $btnLaunch.Location = '160,530'; $btnLaunch.Size = '130,32'

$btnCustom = New-Object Windows.Forms.Button
$btnCustom.Text = 'Browse for file...'; $btnCustom.Location = '298,530'; $btnCustom.Size = '140,32'

$btnClear = New-Object Windows.Forms.Button
$btnClear.Text = 'Uncheck all'; $btnClear.Location = '446,530'; $btnClear.Size = '90,32'

$btnClose = New-Object Windows.Forms.Button
$btnClose.Text = 'Close all monitors'; $btnClose.Location = '12,570'; $btnClose.Size = '150,32'

$status = New-Object Windows.Forms.Label
$status.Text = 'Ready.'; $status.Location = '175,577'; $status.Size = '460,22'

$form.Controls.AddRange(@($lblPaste, $txtPaste, $btnPaste, $btnPasteClear,
                          $lblTail, $numTail, $btnLaunch, $btnCustom, $btnClear, $btnClose, $status))

$btnLaunch.Add_Click({
    $sel = @($checks.Values | Where-Object Checked)
    if (-not $sel) { [Windows.Forms.MessageBox]::Show('Tick at least one log first.') | Out-Null; return }
    foreach ($c in $sel) { Start-Monitor $c.Tag ([int]$numTail.Value); Start-Sleep -Milliseconds 250 }
    $status.Text = "Launched $($sel.Count) monitor(s). Open monitor windows: $(@($script:procs | Where-Object { -not $_.HasExited }).Count)"
})

$btnCustom.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose a text log file to monitor'
    $dlg.Filter = 'Log/text files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        $it = Item 'Custom' (Split-Path $dlg.FileName -Leaf) 'File' $dlg.FileName
        Start-Monitor $it ([int]$numTail.Value)
        $status.Text = "Launched: $($dlg.FileName)"
    }
})

$btnPaste.Add_Click({
    $launched = 0; $notes = @()
    foreach ($line in ($txtPaste.Text -split "`r?`n")) {
        $p = $line.Trim().Trim('"').Trim("'").Trim()
        if (-not $p) { continue }
        $p = [Environment]::ExpandEnvironmentVariables($p)
        if ($p -match '\.evtx$') { $notes += "Skipped (.evtx can't be tailed as text): $p"; continue }
        $name = Split-Path $p -Leaf
        if (-not $name) { $name = $p }
        $type = if (Test-Path -LiteralPath $p -PathType Container) { 'Dir' } else { 'File' }
        Start-Monitor (Item 'Pasted' $name $type $p) ([int]$numTail.Value)
        $launched++
        if (-not (Test-Path -LiteralPath $p)) { $notes += "Not found yet (will wait for it): $p" }
        Start-Sleep -Milliseconds 250
    }
    if (-not $launched -and -not $notes) { [Windows.Forms.MessageBox]::Show('Paste at least one path first.') | Out-Null; return }
    $status.Text = "Launched $launched pasted monitor(s)." + $(if ($notes) { '  ' + ($notes -join ' | ') } else { '' })
})

$btnPasteClear.Add_Click({ $txtPaste.Clear() })

$btnClear.Add_Click({ foreach ($c in $checks.Values) { $c.Checked = $false } })

$btnClose.Add_Click({
    foreach ($p in $script:procs) { try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch {} }
    $script:procs.Clear()
    $status.Text = 'All monitor windows closed.'
})

[void]$form.ShowDialog()
