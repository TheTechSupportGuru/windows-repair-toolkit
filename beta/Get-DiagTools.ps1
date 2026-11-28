# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# Version 0.1 beta 1
<#
.SYNOPSIS
  Downloads the diagnostic tools listed on linktr.ee/stech (everything above the "KT Links" section).
.DESCRIPTION
  Handles four kinds of source:
    1. Direct file URLs (.exe, .zip, .diagcab, redirects to files)
    2. GitHub release pages (uses the GitHub API to pick the Windows asset)
    3. Web pages that link to the real file (the script scans the page for a matching link)
    4. Manual items (registration, terms acceptance, multi-page guides) - listed, never fetched
  Downloads only. Nothing is executed. Verify each file yourself before running it.
.EXAMPLE
  .\Get-DiagTools.ps1 -List
  .\Get-DiagTools.ps1 -Only 'HDTune','BlueScreenView'
  .\Get-DiagTools.ps1
#>
param(
    [string[]]$Only,
    [string]$OutDir = (Join-Path $PSScriptRoot 'Downloads'),
    [switch]$List,
    [switch]$Force
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA             = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DiagDownloader/1.0'
$DefaultPattern = '(?i)\.(exe|msi|zip|7z|diagcab)(\?|$)'
$AssetDefault   = '(?i)\.(exe|msi|zip)$'
$AssetSkip      = '(?i)arm64|aarch64|mac|darwin|linux|\.dmg|source'

$Tools = @(
    @{ Name='RustDesk Windows';           Url='https://github.com/rustdesk/rustdesk/releases/download/1.5.3/rustdesk-1.5.3-x86_64.exe' }
    @{ Name='RustDesk Mac Apple silicon'; Url='https://github.com/rustdesk/rustdesk/releases/download/1.5.3/rustdesk-1.5.3-aarch64.dmg' }
    @{ Name='RustDesk Mac Intel';         Url='https://github.com/rustdesk/rustdesk/releases/download/1.5.3/rustdesk-1.5.3-x86_64.dmg' }
    @{ Name='GSmartControl';              Url='https://gsmartcontrol.shaduri.dev/downloads'; Pattern='(?i)\.exe(\?|$)' }
    @{ Name='CrystalDiskInfo';            Url='https://sourceforge.net/projects/crystaldiskinfo/files/9.9.2/CrystalDiskInfo9_9_2.zip/download' }
    @{ Name='HDTune';                     Url='https://www.hdtune.com/files/hdtune_255.exe' }
    @{ Name='HDDScan';                    Url='https://hddscan.com/download.html' }
    @{ Name='Macrium Reflect Free';       Url='https://www.majorgeeks.com/mg/get/macrium_reflect_free_edition,3.html'; Manual='MajorGeeks issues session-bound links; open the page in a browser' }
    @{ Name='FreeFileSync';               Url='https://freefilesync.org/download/FreeFileSync_14.11_Windows_Setup.exe' }
    @{ Name='Cobian Backup';              Url='https://files.cobiansoft.com/programs/cbSetup.exe' }
    @{ Name='Veeam Free';                 Url='https://www.veeam.com/products/free/backup-recovery.html'; Manual='Requires registration on the Veeam site' }
    @{ Name='SeraphSecure Scanner';       Url='https://cdn.seraphsecure.com/update/SeraphSecure.Desktop.Scan.Portable.exe' }
    @{ Name='Malwarebytes Ninite';        Url='https://ninite.com/malwarebytes' }
    @{ Name='ESET Online Scanner';        Url='https://download.eset.com/com/eset/tools/online_scanner/latest/esetonlinescanner.exe' }
    @{ Name='ClamWin Portable';           Url='https://portableapps.com/apps/security/clamwin_portable';   Pattern='\.paf\.exe(\?|$)' }
    @{ Name='Spybot Portable';            Url='https://portableapps.com/apps/security/spybot_portable';    Pattern='\.paf\.exe(\?|$)' }
    @{ Name='ADWCleaner';                 Url='https://adwcleaner.malwarebytes.com/adwcleaner?channel=release' }
    @{ Name='Sophos Scan and Clean';      Url='https://m.majorgeeks.com/mg/get/sophos_scan_clean,2.html' }
    @{ Name='Emsisoft Emergency Kit';     Url='https://www.emsisoft.com/en/emergency-kit/download';        Pattern='(?i)emergency.*\.exe(\?|$)' }
    @{ Name='Trellix Stinger';            Url='https://downloadcenter.trellix.com/products/mcafee-avert/Stinger/stinger64.exe'; Manual='Download page makes you accept terms first; open the link in a browser' }
    @{ Name='mssPortable';                Url='https://portableapps.com/apps/security/mssportable';        Pattern='\.paf\.exe(\?|$)' }
    @{ Name='BleachBit Portable';         Url='https://download.bleachbit.org/get/BleachBit-6.0.6-portable.zip' }
    @{ Name='CCleaner Portable';          Url='https://portableapps.com/apps/utilities/ccportable';        Pattern='\.paf\.exe(\?|$)' }
    @{ Name='Win11Debloat';               Url='https://github.com/Raphire/Win11Debloat/releases';          Pattern='(?i)\.zip$' }
    @{ Name='HWiNFO';                     Url='https://www.hwinfo.com/files/hwi_860.zip' }
    @{ Name='Reset Windows Update Tool';  Url='https://github.com/ManuelGil/Reset-Windows-Update-Tool/releases'; Pattern='(?i)\.(exe|zip)$' }
    @{ Name='LibreHardwareMonitor';       Url='https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases'; Pattern='(?i)\.zip$' }
    @{ Name='Speccy Portable';            Url='https://portableapps.com/apps/utilities/specportable';      Pattern='\.paf\.exe(\?|$)' }
    @{ Name='TreeSize Free Portable';     Url='https://www.jam-software.com/treesize_free/portable.shtml?ca=1'; Pattern='(?i)portable.*\.zip(\?|$)' }
    @{ Name='WizTree';                    Url='https://diskanalyzer.com/download';                         Pattern='(?i)wiztree.*\.(exe|zip)(\?|$)' }
    @{ Name='BlueScreenView';             Url='https://www.nirsoft.net/utils/bluescreenview-x64.zip' }
    @{ Name='Sysinternals Suite';         Url='https://learn.microsoft.com/en-us/sysinternals/downloads/sysinternals-suite'; Pattern='SysinternalsSuite\.zip(\?|$)' }
    @{ Name='Process Explorer';           Url='https://download.sysinternals.com/files/ProcessExplorer.zip' }
    @{ Name='Windows Uninstall Troubleshooter'; Url='https://download.microsoft.com/download/7/E/9/7E9188C0-2511-4B01-8B4E-0A641EC2F600/MicrosoftProgram_Install_and_Uninstall.meta.diagcab' }
    @{ Name='Hide Windows Updates';       Url='https://download.microsoft.com/download/f/2/2/f22d5fdb-59cd-4275-8c95-1be17bf70b21/wushowhide.diagcab?' }
    @{ Name='Microsoft 365 Troubleshooters'; Url='https://support.microsoft.com/en-us/support/get-help/microsoft-365-troubleshooters'; Manual='Several troubleshooters on one support page; pick them in a browser' }
    @{ Name='.NET Framework Repair Tool'; Url='https://www.microsoft.com/en-us/download/details.aspx?id=30135' }
    @{ Name='ShellExView';                Url='https://www.nirsoft.net/utils/shexview-x64.zip' }
    @{ Name='OpenedFilesView';            Url='https://www.nirsoft.net/utils/ofview-x64.zip' }
    @{ Name='LastActivityView';           Url='https://www.nirsoft.net/utils/lastactivityview.zip' }
    @{ Name='ProcessActivityView';        Url='https://www.nirsoft.net/utils/processactivityview-x64.zip' }
    @{ Name='FolderChangesView';          Url='https://www.nirsoft.net/utils/folderchangesview.zip' }
    @{ Name='WhatIsHang';                 Url='https://www.nirsoft.net/utils/whatishang-x64.zip' }
    @{ Name='NETworkManager';             Url='https://github.com/BornToBeRoot/NETworkManager/releases/download/2026.7.7.0/NETworkManager_2026.7.7.0_Portable.zip' }
    @{ Name='OpenNetMeter';               Url='https://github.com/Ashfaaq18/OpenNetMeter/releases';        Pattern='(?i)\.(exe|zip)$' }
    @{ Name='Nmap';                       Url='https://nmap.org/dist/nmap-7.993-setup.exe' }
    @{ Name='Wireshark';                  Url='https://2.na.dl.wireshark.org/win64/WiresharkPortable64_4.6.9.paf.exe' }
    @{ Name='WinSCP Portable';            Url='https://winscp.net/download/WinSCP-6.7.1-Portable.zip/download' }
    @{ Name='Advanced IP Scanner';        Url='https://www.advanced-ip-scanner.com/download';              Pattern='(?i)advanced.?ip.?scanner.*\.exe(\?|$)' }
)

function Open-Web([string]$Url) {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = $UA
    $req.Accept = '*/*'
    $req.AllowAutoRedirect = $true
    $req.Timeout = 60000
    return $req.GetResponse()
}

function Read-Html($resp) {
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    try { return $sr.ReadToEnd() } finally { $sr.Close() }
}

function Save-Response($resp, [string]$Dir) {
    $name = $null
    $cd = $resp.Headers['Content-Disposition']
    if ($cd -and $cd -match 'filename\*?=(?:UTF-8'')?"?([^";]+)') { $name = [Uri]::UnescapeDataString($Matches[1]) }
    if (-not $name) { $name = [Uri]::UnescapeDataString([IO.Path]::GetFileName($resp.ResponseUri.AbsolutePath)) }
    if (-not $name -or $name -notmatch '\.') { $name = 'download.bin' }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $path = Join-Path $Dir $name
    $in = $resp.GetResponseStream()
    $out = [IO.File]::Create($path)
    try { $in.CopyTo($out) } finally { $out.Close(); $in.Close() }
    return $path
}

function Find-Link([string]$Html, $Base, [string]$Pattern) {
    foreach ($m in [regex]::Matches($Html, 'href\s*=\s*["'']([^"'']+)["'']')) {
        $h = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        try { $abs = (New-Object Uri($Base, $h)).AbsoluteUri } catch { continue }
        if ($abs -match $Pattern) { return $abs }
    }
    return $null
}

function Get-Tool($t, [string]$Dir) {
    $url = $t.Url
    if ($url -match '^https://github\.com/([^/]+)/([^/]+)/releases/?$') {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Matches[1])/$($Matches[2])/releases/latest" -Headers @{ 'User-Agent' = $UA }
        $pat = if ($t.Pattern) { $t.Pattern } else { $AssetDefault }
        $asset = $rel.assets | Where-Object { $_.name -match $pat -and $_.name -notmatch $AssetSkip } | Select-Object -First 1
        if (-not $asset) { throw "no matching asset in release $($rel.tag_name)" }
        $url = $asset.browser_download_url
    }

    $resp = Open-Web $url
    $pat  = if ($t.Pattern) { $t.Pattern } else { $DefaultPattern }
    for ($hop = 0; $hop -lt 3 -and $resp.ContentType -match 'text/html'; $hop++) {
        $base = $resp.ResponseUri
        $html = Read-Html $resp
        $resp.Close()
        $link = Find-Link $html $base $pat
        if (-not $link) {
            $meta = [regex]::Match($html, '(?i)<meta[^>]+refresh[^>]*url=([^\x22\x27>\s;]+)')
            if ($meta.Success) { $link = (New-Object Uri($base, [Net.WebUtility]::HtmlDecode($meta.Groups[1].Value))).AbsoluteUri }
        }
        if (-not $link) { throw "no download link found on $url" }
        $resp = Open-Web $link
    }
    if ($resp.ContentType -match 'text/html') { $resp.Close(); throw 'still a web page after 3 hops' }
    try { return Save-Response $resp $Dir } finally { $resp.Close() }
}
# When dot-sourced (by the GUI), stop here so only the functions and $Tools load.
if ($MyInvocation.InvocationName -eq '.') { return }

$selected = @($Tools | Where-Object { -not $Only -or $Only -contains $_.Name })
if ($Only) {
    $known = @($Tools | ForEach-Object { $_.Name })
    $unknown = $Only | Where-Object { $_ -notin $known }
    if ($unknown) { Write-Warning "Unknown name(s): $($unknown -join ', ')" }
}

if ($List) {
    $selected | ForEach-Object {
        $flag = if ($_.Manual) { 'MANUAL' } else { '' }
        '{0,-34} {1,-7} {2}' -f $_.Name, $flag, $_.Url
    }
    return
}

$results = @()
foreach ($t in $selected) {
    if ($t.Manual) {
        $results += [pscustomobject]@{ Name = $t.Name; Status = 'MANUAL'; Detail = "$($t.Manual): $($t.Url)" }
        continue
    }
    $dir = Join-Path $OutDir $t.Name
    if (-not $Force -and (Test-Path $dir) -and (Get-ChildItem $dir -File -ErrorAction SilentlyContinue)) {
        $results += [pscustomobject]@{ Name = $t.Name; Status = 'SKIP'; Detail = 'already downloaded (use -Force)' }
        continue
    }
    try {
        $file = Get-Tool $t $dir
        $results += [pscustomobject]@{ Name = $t.Name; Status = 'OK'; Detail = $file }
    } catch {
        $results += [pscustomobject]@{ Name = $t.Name; Status = 'FAILED'; Detail = $_.Exception.Message }
    }
}
$results | Format-Table Name, Status, Detail -AutoSize -Wrap






