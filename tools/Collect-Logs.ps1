#requires -Version 5.1
# Version 1.3 (2026-11-19) - edited copy. What changed: Edited scripts\V1.3\CHANGES.md
<#
  Collect-Logs.ps1  -  Windows 11 log collector
  Copies Windows Update / DISM-CBS / Event Viewer / crash / setup logs
  into  <Desktop of logged-in user>\logs
  Right-click > "Run with PowerShell"  (it will ask for admin rights itself)
#>

# ---------- self-elevate ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- find the logged-in user's profile + desktop ----------
function Get-InteractiveUser {
    $profilePath = $env:USERPROFILE
    $desktop     = [Environment]::GetFolderPath('Desktop')
    try {
        $u = (Get-CimInstance Win32_ComputerSystem).UserName
        if ($u) {
            $sid  = (New-Object Security.Principal.NTAccount($u)).Translate([Security.Principal.SecurityIdentifier]).Value
            $prof = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath
            if ($prof) { $profilePath = $prof }
            # read the RAW value: Get-ItemProperty would expand %USERPROFILE% with the profile of whoever ELEVATED
            # (e.g. a different admin account), sending the logs to the wrong Desktop. (Same fix as WinSuperTool.)
            $key = Get-Item -LiteralPath "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop
            $raw = $key.GetValue('Desktop', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($raw) {
                $d = [regex]::Replace([string]$raw, '%USERPROFILE%', $profilePath.Replace('$', '$$'), 'IgnoreCase')
                $desktop = [Environment]::ExpandEnvironmentVariables($d)
            }
        }
    } catch {}
    [pscustomobject]@{ Profile = $profilePath; Desktop = $desktop }
}
$usr     = Get-InteractiveUser
$LogRoot = Join-Path $usr.Desktop 'logs'

# ---------- helpers ----------
$script:count = 0
$script:fail  = 0

function Say([string]$m) {
    $txtOut.AppendText($m + "`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Copy-One([string]$s, [string]$d) {
    New-Item -ItemType Directory -Path (Split-Path $d) -Force | Out-Null
    try {
        Copy-Item -LiteralPath $s -Destination $d -Force -ErrorAction Stop
        $script:count++
    } catch {
        # fallback for files held open by Windows (shared read)
        $in = $null; $out = $null
        try {
            $in  = [IO.File]::Open($s, 'Open', 'Read', 'ReadWrite,Delete')
            $out = [IO.File]::Create($d)
            $in.CopyTo($out)
            $script:count++
        } catch {
            $script:fail++
            Say "   FAILED: $s"
        } finally {
            if ($out) { $out.Dispose() }
            if ($in)  { $in.Dispose() }
        }
    }
}

# Copies a file, wildcard, or whole folder (recursively) into $dest
function Copy-Safe([string]$src, [string]$dest) {
    if (Test-Path -LiteralPath $src -PathType Container) {
        $root  = (Get-Item -LiteralPath $src -Force).FullName.TrimEnd('\')
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        if (-not $files) { Say "   (empty) $src"; return }
        $leaf = Split-Path $root -Leaf
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($root.Length).TrimStart('\')
            Copy-One $f.FullName (Join-Path (Join-Path $dest $leaf) $rel)
        }
    } else {
        $files = @(Get-ChildItem -Path $src -File -Force -ErrorAction SilentlyContinue)
        if (-not $files) { Say "   (not found) $src"; return }
        foreach ($f in $files) { Copy-One $f.FullName (Join-Path $dest $f.Name) }
    }
}

function Export-Evt([string]$name, [string]$dest) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $file = Join-Path $dest (($name -replace '[\\/]', '%4') + '.evtx')
    & wevtutil.exe epl $name $file /ow:true 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $script:count++ } else { Say "   skipped (channel missing/empty): $name" }
}

# ---------- collectors ----------
$Collectors = [ordered]@{

'WU' = @{ Label = 'Windows Update (ETL, ReportingEvents, USO, WaaSMedic, merged WindowsUpdate.log)'; Run = {
    $d = Join-Path $LogRoot '1_WindowsUpdate'
    Copy-Safe 'C:\Windows\Logs\WindowsUpdate'                          $d
    Copy-Safe 'C:\Windows\SoftwareDistribution\ReportingEvents.log'    $d
    Copy-Safe 'C:\Windows\WindowsUpdate.log'                           $d
    Copy-Safe 'C:\Windows\Logs\waasmedic'                              $d
    Copy-Safe 'C:\Windows\Logs\SIH'                                    $d
    Copy-Safe 'C:\ProgramData\USOShared\Logs'                          $d
    Say '   Building merged WindowsUpdate.log (can take a minute)...'
    try {
        Get-WindowsUpdateLog -LogPath (Join-Path $d 'WindowsUpdate_merged.log') -ErrorAction Stop | Out-Null
        $script:count++
    } catch { Say "   Get-WindowsUpdateLog failed: $($_.Exception.Message)" }
}}

'DISM' = @{ Label = 'DISM / CBS / servicing (dism.log, CBS.log, pending.xml, setupapi)'; Run = {
    $d = Join-Path $LogRoot '2_DISM_CBS'
    Copy-Safe 'C:\Windows\Logs\DISM'                       $d
    Copy-Safe 'C:\Windows\Logs\CBS'                        $d
    Copy-Safe 'C:\Windows\Logs\DPX'                        $d
    Copy-Safe 'C:\Windows\servicing\Sessions\Sessions.xml' $d
    Copy-Safe 'C:\Windows\WinSxS\pending.xml'              $d
    Copy-Safe 'C:\Windows\WinSxS\poqexec.log'              $d
    Copy-Safe 'C:\Windows\inf\setupapi*.log'               $d
}}

'EVT' = @{ Label = 'Event Viewer - key logs exported (System, Application, Setup, WU client, etc.)'; Run = {
    $d = Join-Path $LogRoot '3_EventViewer'
    $channels = @(
        'System','Application','Setup',
        'Microsoft-Windows-WindowsUpdateClient/Operational',
        'Microsoft-Windows-Bits-Client/Operational',
        'Microsoft-Windows-DeliveryOptimization/Operational',
        'Microsoft-Windows-Kernel-PnP/Configuration',
        'Microsoft-Windows-Kernel-Boot/Operational',
        'Microsoft-Windows-Diagnostics-Performance/Operational',
        'Microsoft-Windows-AppXDeploymentServer/Operational',
        'Microsoft-Windows-WER-Diag/Operational',
        'Microsoft-Windows-CodeIntegrity/Operational',
        'Microsoft-Windows-TaskScheduler/Operational'
    )
    foreach ($c in $channels) { Export-Evt $c $d }
}}

'SEC' = @{ Label = 'Event Viewer - Security log (large, sensitive)'; Run = {
    Export-Evt 'Security' (Join-Path $LogRoot '3_EventViewer')
}}

'EVTALL' = @{ Label = 'Event Viewer - ALL raw .evtx files (can be hundreds of MB)'; Run = {
    $d = Join-Path $LogRoot '3b_EventViewer_AllRaw'
    Copy-Safe 'C:\Windows\System32\winevt\Logs' $d
}}

'CRASH' = @{ Label = 'Crashes (Minidumps, WER reports, user CrashDumps, reliability history, bugcheck events)'; Run = {
    $d = Join-Path $LogRoot '4_Crashes'
    Copy-Safe 'C:\Windows\Minidump'                                     $d
    Copy-Safe 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'      $d
    Copy-Safe 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'        $d
    Copy-Safe (Join-Path $usr.Profile 'AppData\Local\CrashDumps')       $d
    Copy-Safe (Join-Path $usr.Profile 'AppData\Local\Microsoft\Windows\WER') (Join-Path $d 'UserWER')
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    try {
        Get-CimInstance Win32_ReliabilityRecords -ErrorAction Stop |
            Select-Object TimeGenerated, SourceName, EventIdentifier, ProductName, Message |
            Export-Csv (Join-Path $d 'ReliabilityHistory.csv') -NoTypeInformation
        $script:count++
    } catch { Say '   Reliability history unavailable' }
    try {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Id=41,1001,1074,1076,6005,6006,6008 } -ErrorAction Stop |
            Format-List TimeCreated, Id, ProviderName, Message |
            Out-File (Join-Path $d 'Crash_Shutdown_Events.txt') -Width 250
        $script:count++
    } catch { Say '   No crash/shutdown events found' }
}}

'BIG' = @{ Label = 'LARGE dumps (MEMORY.DMP + LiveKernelReports) - can be several GB'; Run = {
    $d = Join-Path $LogRoot '4b_LargeDumps'
    Copy-Safe 'C:\Windows\MEMORY.DMP'          $d
    Copy-Safe 'C:\Windows\LiveKernelReports'   $d
}}

'SETUP' = @{ Label = 'Setup / feature-upgrade logs (Panther, $WINDOWS.~BT, Rollback, MoSetup)'; Run = {
    $d = Join-Path $LogRoot '5_SetupUpgrade'
    Copy-Safe 'C:\Windows\Panther'                          (Join-Path $d 'Windows_Panther')
    Copy-Safe 'C:\$WINDOWS.~BT\Sources\Panther'             (Join-Path $d 'BT_Panther')
    Copy-Safe 'C:\$WINDOWS.~BT\Sources\Rollback'            (Join-Path $d 'BT_Rollback')
    Copy-Safe 'C:\$Windows.~WS\Sources\Panther'             (Join-Path $d 'WS_Panther')
    Copy-Safe 'C:\Windows\Logs\MoSetup'                     $d
    Copy-Safe 'C:\Windows\System32\Sysprep\Panther'         (Join-Path $d 'Sysprep_Panther')
    Copy-Safe 'C:\Windows\setupact.log'                     $d
    Copy-Safe 'C:\Windows\setuperr.log'                     $d
}}

'INFO' = @{ Label = 'System info (systeminfo, installed hotfixes, DISM packages list)'; Run = {
    $d = Join-Path $LogRoot '6_SystemInfo'
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    & systeminfo.exe | Out-File (Join-Path $d 'systeminfo.txt')
    try { Get-HotFix | Sort-Object InstalledOn -Descending | Format-Table -AutoSize | Out-File (Join-Path $d 'hotfixes.txt') -Width 250 } catch {}
    try { Get-WindowsPackage -Online -ErrorAction Stop | Format-Table PackageName, PackageState, InstallTime -AutoSize |
          Out-File (Join-Path $d 'dism_packages.txt') -Width 300 } catch {}
    $script:count += 2
}}
}

# ---------- GUI ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'Windows Log Collector'
$form.Size = New-Object Drawing.Size(640, 640)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

$lbl = New-Object Windows.Forms.Label
$lbl.Text = "Select logs to collect.`nOutput: $LogRoot"
$lbl.Location = '12,10'; $lbl.Size = '600,38'
$form.Controls.Add($lbl)

$boxes = @{}
$y = 55
foreach ($k in $Collectors.Keys) {
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = $Collectors[$k].Label
    $cb.Location = "16,$y"; $cb.Size = '590,24'
    $cb.Checked = ($k -in 'WU','DISM','EVT','CRASH')
    $form.Controls.Add($cb)
    $boxes[$k] = $cb
    $y += 28
}

$btnAll = New-Object Windows.Forms.Button
$btnAll.Text = 'Select / clear all'; $btnAll.Location = "16,$($y+8)"; $btnAll.Size = '130,30'
$btnAll.Add_Click({
    $any = $boxes.Values | Where-Object { -not $_.Checked }
    foreach ($b in $boxes.Values) { $b.Checked = [bool]$any }
})
$form.Controls.Add($btnAll)

$btnGo = New-Object Windows.Forms.Button
$btnGo.Text = 'Submit'; $btnGo.Location = "160,$($y+8)"; $btnGo.Size = '130,30'
$form.Controls.Add($btnGo)

$txtOut = New-Object Windows.Forms.TextBox
$txtOut.Multiline = $true; $txtOut.ScrollBars = 'Vertical'; $txtOut.ReadOnly = $true
$txtOut.Location = "16,$($y+50)"; $txtOut.Size = "590,$(600 - ($y+50) - 40)"
$txtOut.Font = New-Object Drawing.Font('Consolas', 9)
$form.Controls.Add($txtOut)

$btnGo.Add_Click({
    $sel = @($Collectors.Keys | Where-Object { $boxes[$_].Checked })
    if (-not $sel) { [Windows.Forms.MessageBox]::Show('Pick at least one item.') | Out-Null; return }
    $btnGo.Enabled = $false; $btnAll.Enabled = $false
    $script:count = 0; $script:fail = 0
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Say "Started $(Get-Date)  ->  $LogRoot"
    foreach ($k in $sel) {
        Say "`r`n[$k] $($Collectors[$k].Label)"
        try { & $Collectors[$k].Run } catch { Say "   ERROR: $($_.Exception.Message)" }
    }
    Say "`r`nDone. Files copied/exported: $($script:count)   Failed: $($script:fail)"
    $txtOut.Text | Out-File (Join-Path $LogRoot '_collection_summary.txt')
    Start-Process explorer.exe $LogRoot
    $btnGo.Enabled = $true; $btnAll.Enabled = $true
})

[void]$form.ShowDialog()
