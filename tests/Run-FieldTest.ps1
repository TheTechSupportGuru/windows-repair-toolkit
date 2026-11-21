# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-FieldTest.ps1 - the toolkit's checks on ANOTHER PC: Windows 10, Windows in another language, a physical PC, a
# laptop with Wi-Fi and Bluetooth. Start it with Run-FieldTest.cmd (double-click). Changes nothing on the PC apart from
# one test event in the "Windows PowerShell" event log (Live Monitor check, admin only) and temporary files.
#   1 the PC: Windows version and language, real or virtual, Wi-Fi / Bluetooth hardware, monitors and scaling
#   2 unit tests (skipped with -Quick)
#   3 System Info: Windows, network, video + displays, audio, Bluetooth, Wi-Fi
#   4 window sizes on this PC's screen(s) (resize audit; the tools' windows open and close by themselves)
#   5 as administrator: real read-only scans read back by the Recovery / Automation summaries (DISM, chkdsk, sfc) -
#     on Windows in another language this shows whether the wording is recognised or the exit code decides
#   6 as administrator: Live Monitor (every log window type)
# Output on the Desktop, folder WRT-FieldTest-<date>:
#   private\   everything, unmasked (product keys, Wi-Fi passwords, addresses) - keep it to yourself
#   share\     the same with private details masked, and WRT-FieldTest-share.zip of it - this is what you send
param([string]$OutDir = '', [switch]$Quick, [switch]$Elevate)
$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Elevate -and -not $isAdmin) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $(if ($Quick) { '-Quick' } else { @() }) + $(if ($OutDir) { @('-OutDir', "`"$OutDir`"") } else { @() })
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $a -ErrorAction Stop; return } catch { Write-Host 'No administrator rights - running the checks that do not need them.' -ForegroundColor Yellow }
}
$Repo = Split-Path $PSScriptRoot -Parent
$Beta = Join-Path $Repo 'beta\WinSuperTool.ps1'
if (-not $OutDir) { $OutDir = Join-Path ([Environment]::GetFolderPath('Desktop')) ('WRT-FieldTest-' + (Get-Date -Format 'yyyyMMdd-HHmm')) }
$Priv = Join-Path $OutDir 'private'; $Share = Join-Path $OutDir 'share'
New-Item -ItemType Directory -Force $Priv, $Share | Out-Null
try { Get-ChildItem -LiteralPath $Repo -Recurse -File | Unblock-File -ErrorAction SilentlyContinue } catch {}     # a downloaded zip marks every file as "from the internet"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$Sum = Join-Path $Priv 'summary.txt'
function W([string]$m) { Add-Content -LiteralPath $Sum $m -Encoding UTF8; Write-Host $m }
function Step([string]$m) { W ''; W "===== $m  ($(Get-Date -Format 'HH:mm:ss'))" }

# ---------- masking: what goes into share\ ----------
$PcName = $env:COMPUTERNAME; $UserName = $env:USERNAME
function Protect-Text([string]$t, [bool]$Ip = $true) {
    if (-not $t) { return $t }
    foreach ($n in @($PcName, $UserName, $env:USERDOMAIN) | Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object Length -Descending) { $t = [regex]::Replace($t, [regex]::Escape($n), '<name>', 'IgnoreCase') }
    $t = [regex]::Replace($t, '\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b', 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX')                       # product keys
    $t = [regex]::Replace($t, '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b', 'xx:xx:xx:xx:xx:xx')                            # MAC addresses
    if ($Ip) { $t = [regex]::Replace($t, '\b(?!255\.|0\.0\.0\.0)(\d{1,3}\.){3}\d{1,3}\b', 'a.b.c.d') }                     # IPv4 (not masks)
    $t = [regex]::Replace($t, '(?i)\b[0-9a-f]{0,4}::[0-9a-f:]*(%\d+)?|\b(?=[0-9a-f:]*[a-f])(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}(%\d+)?\b', 'ipv6')  # IPv6, not clock times
    $t = [regex]::Replace($t, '\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?', '{guid}')
    $t
}
# Wi-Fi network names and passwords, Bluetooth device names: masked in the data, before it becomes text
function Protect-Blocks($blocks) {
    $sec = ''; $n = 0
    foreach ($b in @($blocks)) {
        $c = $b.PSObject.Copy()
        if ($c.K -eq 'H') { $sec = $c.T }
        elseif ($c.K -eq 'KV') {
            if ($c.Key -eq 'Network' -and $sec -match '^Saved Wi-Fi') { $n++; $c.T = "Wi-Fi network $n" + $(if ($b.T -match 'CONNECTED NOW') { '   <- CONNECTED NOW' } else { '' }) }
            elseif ($c.Key -eq 'Network') { $c.T = $c.T -replace '^[^(]*', '(name hidden)  ' }
            elseif ($c.Key -match 'key ends in') { $c.T = 'xxxxx' }
            elseif ($c.Key -match 'address|gateway|DNS|DHCP|server' -and $c.Key -notmatch 'MAC') { $c.T = [regex]::Replace($c.T, '\b(?!255\.|0\.0\.0\.0)(\d{1,3}\.){3}\d{1,3}\b', 'a.b.c.d') }
            elseif ($c.Key -match '^\s*(Password|Profile name)$' -and $c.T -notmatch '^\(') { $c.T = '********' }
            elseif ($sec -match '^Paired devices') { $n++; $c.Key = "Device $n" }
            elseif ($sec -match 'Wi-Fi' -and $c.Key -match 'SSID|Network name') { $c.T = 'xxxx' }
        }
        elseif ($c.K -eq 'T' -and $sec -match 'in range') { $c.T = $c.T -replace '^(B?SSID \d+\s*:\s*).*$', '$1xxxx' -replace '^(\S.*?:\s*).*$', '$1' }
        $c
    }
}
function Save-Both([string]$name, [string]$text) { [IO.File]::WriteAllText((Join-Path $Priv $name), $text); [IO.File]::WriteAllText((Join-Path $Share $name), (Protect-Text $text)) }

# ---------- 1 the PC ----------
Step '1 This PC'
$os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
W ("Windows      : {0}  {1}  build {2}.{3}  ({4})" -f $os.Caption, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR, $os.OSArchitecture)
W ("Language     : display {0}, format {1}, installed {2}" -f (Get-UICulture).Name, (Get-Culture).Name, ($os.MUILanguages -join ', '))
W ("PC           : {0} {1}  ({2})" -f $cs.Manufacturer, $cs.Model, $(if ($cs.Model -match 'Virtual|VMware|VirtualBox|KVM|HVM' -or $cs.Manufacturer -match 'QEMU|Xen|innotek|Microsoft Corporation') { 'virtual machine' } else { 'physical PC' }))
W ("Firmware     : {0}" -f $(if ($env:firmware_type) { $env:firmware_type } else { 'unknown' }))
W ("PowerShell   : {0}   Pester: {1}   admin: {2}" -f $PSVersionTable.PSVersion, ((Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version), $isAdmin)
$wifi = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -match '802\.11' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN' })
$bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match 'Bluetooth|Radio|Adapter' })
W ("Wi-Fi        : {0}" -f $(if ($wifi.Count) { ($wifi | ForEach-Object { "$($_.InterfaceDescription) ($($_.Status))" }) -join '; ' } else { 'no Wi-Fi adapter' }))
W ("Bluetooth    : {0}" -f $(if ($bt.Count) { ($bt | ForEach-Object FriendlyName | Select-Object -First 3) -join '; ' } else { 'no Bluetooth adapter' }))
W ("Monitors     : {0}" -f (([Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.DeviceName -replace '^\\\\\.\\', '') $($_.Bounds.Width)x$($_.Bounds.Height)$(if ($_.Primary) { ' (main)' })" }) -join '; '))
$g = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); W ("Scaling      : main display {0:N0} %" -f ($g.DpiX / 0.96)); $g.Dispose()

# ---------- 2 unit tests ----------
if (-not $Quick) {
    Step '2 Unit tests'
    foreach ($s in 'Suite', 'Toolkit', 'Beta') {
        $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$s.Tests.ps1") 2>&1 | Out-String
        Save-Both "unit-$s.txt" $o
        $fail = @([regex]::Matches($o, '(?m)^\s*\[-\].*$') | ForEach-Object { $_.Value.Trim() })
        W ("{0,-8} passed {1}, failed {2}" -f $s, ([regex]::Matches($o, '\[\+\]')).Count, $fail.Count)
        foreach ($f in $fail) { W "   $(Protect-Text $f)" }
    }
}

# ---------- 3 System Info ----------
Step '3 System Info (beta)'
$tk = $null; $pe = $null; $ast = [Management.Automation.Language.Parser]::ParseFile($Beta, [ref]$tk, [ref]$pe)
# every top-level function of the beta (definitions only - nothing of the tool runs); none has the name of one of ours
foreach ($fd in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [Management.Automation.Language.ScriptBlockAst] }, $true)) { . ([scriptblock]::Create($fd.Extent.Text)) }
$script:AudioApiLoaded = $false; $script:DispApiLoaded = $false; $IsWinPE = $false
foreach ($n in 'Get-WindowsInfo', 'Get-NetInfo', 'Get-GpuInfo', 'Get-AudioInfo', 'Get-BtInfo', 'Get-WifiInfo') {
    $t0 = Get-Date
    try {
        $bl = @(& $n)
        [IO.File]::WriteAllText((Join-Path $Priv "$n.txt"), (Format-InfoText $bl $n))
        [IO.File]::WriteAllText((Join-Path $Share "$n.txt"), (Protect-Text (Format-InfoText @(Protect-Blocks $bl) $n) $false))
        W ("{0,-16} {1,5:N1} s  {2} lines" -f $n, ((Get-Date) - $t0).TotalSeconds, $bl.Count)
    } catch { W ("{0,-16} ERROR: {1}" -f $n, (Protect-Text $_.Exception.Message)) }
}

# ---------- 4 window sizes ----------
Step '4 Window sizes on this PC (the tools open and close by themselves - please do not use the mouse)'
$aud = Join-Path $Priv 'resize'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-ResizeAudit.ps1') -OutDir $aud -Parallel -Sizes 'min,1280x680,75%,max' *> $null
if ([Windows.Forms.Screen]::AllScreens.Count -gt 1) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-ResizeAudit.ps1') -OutDir "$aud-monitors" -Sizes 'mon:2,min,maxon:2,mon:1,span,mon:2' *> $null }
foreach ($o in $aud, "$aud-monitors") { $f = Join-Path $o 'summary.txt'; if (Test-Path $f) { $t = [IO.File]::ReadAllText($f); Save-Both "$(Split-Path $o -Leaf)-summary.txt" $t; W ("{0}: {1}" -f (Split-Path $o -Leaf), (($t -split "`r?`n" | Select-Object -Skip 3 | Where-Object { $_ -and $_ -notmatch 'Sizes actually' } | Select-Object -First 6) -join ' | ')) } }

# ---------- 5 + 6 as administrator ----------
if ($isAdmin) {
    Step '5 Real scans read back by the summaries (DISM, chkdsk, sfc - read-only, about 10-20 minutes)'
    $cap = & (Join-Path $PSScriptRoot 'Run-TaskCapture.ps1') -Script $Beta -OutDir (Join-Path $Priv 'capture') -Elevated 2>&1 | Out-String
    Save-Both 'scans.txt' $cap
    foreach ($l in ($cap -split "`r?`n" | Where-Object { $_ -match '^=== |FIND:' })) { W $l }
    if ($cap -match 'matched=False') { W 'NOTE: at least one result was decided by the exit code, not by Windows'' wording (expected on Windows in another language)' }
    Step '6 Live Monitor (writes one test event to the "Windows PowerShell" log)'
    $mon = & (Join-Path $PSScriptRoot 'Run-MonitorLive.ps1') -Script $Beta -OutDir (Join-Path $Priv 'monitor') 2>&1 | Out-String
    Save-Both 'monitor.txt' $mon
    W ("Live Monitor: {0} passed, {1} failed" -f @($mon -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\s+PASS' }).Count, @($mon -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\s+FAIL' }).Count)
    foreach ($l in ($mon -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\s+FAIL' })) { W "   $(Protect-Text $l.Trim())" }
} else { Step '5 + 6 skipped: they need administrator rights (start Run-FieldTest.cmd and answer Yes)' }

# ---------- share ----------
Step 'Done'
[IO.File]::WriteAllText((Join-Path $Share 'summary.txt'), (Protect-Text ([IO.File]::ReadAllText($Sum))))
$zip = Join-Path $OutDir 'WRT-FieldTest-share.zip'
try { Compress-Archive -Path (Join-Path $Share '*') -DestinationPath $zip -Force; W "To send: $zip (private details masked - please look through it before sending)" } catch { W "Could not zip the share folder: $($_.Exception.Message)" }
W "Everything unmasked (keep private): $Priv"
try { Start-Process explorer.exe $OutDir } catch {}
