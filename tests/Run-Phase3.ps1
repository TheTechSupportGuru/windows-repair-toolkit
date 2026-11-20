# Run-Phase3.ps1 - Phase 3 / 7a + 7b: runs WinFixKit (newest Edited version) FIX buttons headlessly AS ADMIN on this VM.
# For every fix: capture state -> run -> capture -> restore with WinFixKit's own Restore-RegBackup -> capture -> compare to baseline.
# NOT run here (see report): network resets / DHCP renew (cut the network, need a reboot), "Open ..." UI launchers,
# Re-register ALL apps / DISM+SFC / chkdsk / energy report (long console windows), Empty Recycle Bin when it is not empty.
# Take a VM snapshot first. Output: %TEMP%\suite-phase3
param([string]$OutDir = (Join-Path $env:TEMP 'suite-phase3'))
$ErrorActionPreference = 'Continue'
Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
. (Join-Path $PSScriptRoot 'Harness.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
W ("Phase 3 run {0}  admin={1}  version={2}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator), (Resolve-SuitePath 'WinFixKit.ps1'))

# ---- load WinFixKit (functions + $Sections), data folders in TEMP ----
$DataRoot = Join-Path $OutDir 'wfk-data'
$script:RootDir = $DataRoot; $script:LogDir = Join-Path $DataRoot 'Logs'; $script:ReportDir = Join-Path $DataRoot 'Reports'
$script:RegDir = Join-Path $DataRoot 'RegistryBackups'; $script:RegKeyDir = Join-Path $script:RegDir 'Keys'; $script:RegFullDir = Join-Path $script:RegDir 'Full'
foreach ($d in $script:LogDir, $script:ReportDir, $script:RegKeyDir, $script:RegFullDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$script:LogFile = Join-Path $script:LogDir 'phase3.log'; $LogDir = $script:LogDir; $ReportDir = $script:ReportDir
$ast = Get-SuiteAst 'WinFixKit.ps1'
foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
function Write-Out($t, $c) { Add-Content -LiteralPath $script:LogFile -Value $t }
. ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' 'Sections')))
foreach ($v in 'script:KillCritical', 'script:KillBlockedProcs') { . ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' $v))) }
$Act = @{}; foreach ($s in $Sections) { foreach ($a in $s.Actions) { $Act["$($s.Name)|$($a.Label)"] = $a } }

# ---- state capture ----
$RegKeys = @(
    'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters', 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation', 'HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\LanmanWorkstation',
    'HKLM\SYSTEM\CurrentControlSet\Control\Print', 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint',
    'HKLM\SOFTWARE\Microsoft\Windows Search', 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles')
function Get-RegText($k) {
    $tmp = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N') + '.reg')
    $null = & reg.exe export $k $tmp /y 2>&1
    if (Test-Path $tmp) { $t = (Get-Content $tmp -Raw) -replace '(?m)^"(DateLastConnected|DateCreated|SetupCompletedSuccessfully_ts|LastUpdate\w*)"=.*$', ''; Remove-Item $tmp; $t } else { '(key absent)' }
}
function Get-State {
    $s = [ordered]@{}
    foreach ($k in $RegKeys) { $s["REG $k"] = Get-RegText $k }
    $s['SVC startmodes'] = (Get-CimInstance Win32_Service | Sort-Object Name | Where-Object { $_.Name -ne 'BITS' } | ForEach-Object { '{0}={1}' -f $_.Name, $_.StartMode }) -join "`n"
    $c = Get-SmbClientConfiguration; $sv = Get-SmbServerConfiguration
    $s['SMB'] = 'client guest={0} reqsign={1} enasign={2} | server reqsign={3} enasign={4}' -f $c.EnableInsecureGuestLogons, $c.RequireSecuritySignature, $c.EnableSecuritySignature, $sv.RequireSecuritySignature, $sv.EnableSecuritySignature
    $s['NETPROFILE'] = (Get-NetConnectionProfile | ForEach-Object { '{0}={1}' -f $_.Name, $_.NetworkCategory }) -join ','
    $s['FIREWALL'] = (Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Group -match 'FirewallAPI.dll,-(32752|28502)' } | Group-Object Enabled | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Count }) -join ' '
    $s['POWER'] = ((powercfg /list) -join "`n").Trim()
    $s
}
function Compare-State($a, $b) { foreach ($k in $a.Keys) { if ($a[$k] -ne $b[$k]) { $k } } }

$results = New-Object Collections.ArrayList
function Invoke-Fix([string]$Key, $Arg = $null) {
    $a = $Act[$Key]; if (-not $a) { W "  !! action not found: $Key"; return }
    $before = Get-State
    $t0 = Get-Date
    Start-Sleep -Milliseconds 1100     # backups/json written after this instant belong to this fix
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = try { (& $a.Run $Arg 2>&1 | Out-String -Width 220) } catch { "UNCAUGHT: $($_.Exception.Message)" }
    $sw.Stop()
    $after = Get-State
    $changed = @(Compare-State $before $after)
    $restored = 'n/a'; $left = @()
    $jsons = @(Get-ChildItem $script:RegKeyDir -Filter *.json | Where-Object { $_.LastWriteTime -gt $t0 })
    if ($a.Registry -or $jsons.Count) {
        $rout = foreach ($j in ($jsons | Sort-Object LastWriteTime -Descending)) { try { Restore-RegBackup $j.FullName 2>&1 | Out-String } catch { "RESTORE ERROR $($j.Name): $($_.Exception.Message)" } }
        Start-Sleep 2
        $rest = Get-State
        $left = @(Compare-State $before $rest)
        $restored = if ($left.Count) { 'INCOMPLETE' } else { 'OK' }
        Add-Content (Join-Path $OutDir 'restore-output.txt') -Value "=== $Key`n$($rout -join "`n")"
        if ($left.Count) { foreach ($k in $left) { Add-Content (Join-Path $OutDir 'not-restored.txt') -Value ("=== $Key :: $k`n--- BEFORE`n{0}`n--- AFTER RESTORE`n{1}`n" -f $before[$k], $rest[$k]) } }
    }
    $errs = @($out -split "`r?`n" | Where-Object { $_ -match '(?i)UNCAUGHT|FAILED|could not|error|exception|denied' })
    Add-Content (Join-Path $OutDir 'fix-output.txt') -Value "=== $Key`n$out"
    [void]$results.Add([pscustomobject]@{ Fix = $Key; Sec = [math]::Round($sw.Elapsed.TotalSeconds, 1); Backups = $jsons.Count; Changed = ($changed -join ', '); Restore = $restored; NotRestored = ($left -join ', '); ErrLines = $errs.Count; FirstErr = ($errs | Select-Object -First 1) })
    W ("  {0,-78} {1,5}s  backups={2}  changed=[{3}]  restore={4} {5}  errLines={6}" -f $Key, [math]::Round($sw.Elapsed.TotalSeconds, 1), $jsons.Count, ($changed -join ', '), $restored, $(if ($left) { '[' + ($left -join ', ') + ']' } else { '' }), $errs.Count)
    if ($errs) { W "        first error line: $($errs[0].Trim())" }
}

$B0 = Get-State
W "`r`n===== 7a WinFixKit fixes (fix -> restore -> compare with state before the fix)"
# printer
Invoke-Fix 'Printer Share Fixes|Fix 1: set RpcAuthnLevelPrivacyEnabled = 0'
Invoke-Fix 'Printer Share Fixes|Fix 3: let standard users install print server drivers'
Invoke-Fix 'Printer Share Fixes|Apply fixes 1 + 3 together'
Invoke-Fix 'Printer|Restart Print Spooler'
Invoke-Fix 'Printer|Clear stuck print queue'
# SMB
Invoke-Fix 'SMB 24H2 Fix|Method 3 (PowerShell): allow insecure guest + no signing'
Invoke-Fix 'SMB 24H2 Fix|Method 2 (registry): the three reg add values'
Invoke-Fix 'SMB 24H2 Fix|Method 1, step 2: disable client signing (both policies)'
Invoke-Fix 'SMB 24H2 Fix|Restart SMB Workstation + Server services'
Invoke-Fix 'SMB 24H2 Fix|Test access to a PC / NAS by name or IP...' '127.0.0.1'
# network sharing
Invoke-Fix 'Network Sharing|Start and enable discovery services'
Invoke-Fix 'Network Sharing|Enable Network Discovery + File/Printer Sharing rules'
Invoke-Fix 'Network Sharing|Set Public networks to Private'
# power / search
Invoke-Fix 'Power|Set Balanced as the active plan'
Invoke-Fix 'Power|Restore default power plans'
Invoke-Fix 'Power|Generate battery report'
Invoke-Fix 'Search and Indexing|Restart Windows Search service'
Invoke-Fix 'Search and Indexing|Rebuild search index'
# services / caches / misc
Invoke-Fix 'Microsoft Account|Restart identity services'
Invoke-Fix 'Microsoft Account|Resync system clock'
Invoke-Fix 'Microsoft Account|Reset sign-in token cache (current user)'
Invoke-Fix 'Microsoft Account|Re-register Account Broker plugin'
Invoke-Fix 'Store Apps|Restart Store licensing and AppX services'
Invoke-Fix 'Store Apps|Re-register Microsoft Store'
Invoke-Fix 'Start Menu|Re-register Start and Shell packages'
Invoke-Fix 'Start Menu|Rebuild tile database (Windows 10 only)'
Invoke-Fix 'Audio|Restart Windows Audio services'
Invoke-Fix 'Audio|Re-enable disabled audio devices'
Invoke-Fix 'Hardware and Devices|Rescan for hardware changes'
Invoke-Fix 'Hardware and Devices|Enable all disabled devices'
Invoke-Fix 'Hardware and Devices|Export installed driver list to the logs folder'
Invoke-Fix 'Network|Flush DNS cache'
Invoke-Fix 'Network|Clear ARP cache'
Invoke-Fix 'Network|Reset WinHTTP proxy'
Invoke-Fix 'Windows Update|Scan for updates now'
Invoke-Fix 'Windows Update|Reset Windows Update components'
Invoke-Fix 'Windows Update|Delete old update backups (.bak_ folders)'
# files and folders
$tf = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WFK-Phase3-Test'; New-Item -ItemType Directory -Force "$tf\sub" | Out-Null; 'x' | Set-Content "$tf\sub\file.txt"
Invoke-Fix 'Files and Folders|Show permissions of a folder...' $tf
Invoke-Fix 'Files and Folders|Take ownership + reset permissions of a folder...' $tf
foreach ($p in 'C:\ProgramData', 'C:\Documents and Settings', $env:USERPROFILE, 'C:\Windows\System32') { Invoke-Fix 'Files and Folders|Take ownership + reset permissions of a folder...' $p }
$aclBk = @(Get-ChildItem $script:ReportDir -Filter 'acl-backup-*' -ErrorAction SilentlyContinue)
W ("  take-ownership ACL backups written: {0} (expected 1: only the test folder)" -f $aclBk.Count)
Remove-Item $tf -Recurse -Force -ErrorAction SilentlyContinue
$rb = @((New-Object -ComObject Shell.Application).NameSpace(0xA).Items()).Count
if ($rb -eq 0) { Invoke-Fix 'Files and Folders|Empty Recycle Bin (all drives)' } else { W "  Empty Recycle Bin: SKIPPED ($rb items in the bin - not deleting your data)" }
# shell (visible: taskbar and Start restart)
Invoke-Fix 'Start Menu|Restart Start / Search / Shell processes'
Invoke-Fix 'Files and Folders|Restart Windows Explorer'
Start-Sleep 5
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class TokElev {
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr tok, int cls, out int val, int len, out int ret);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static int IsElevated(int pid) {
        IntPtr h = OpenProcess(0x1000, false, pid); if (h == IntPtr.Zero) return -1;
        IntPtr t; if (!OpenProcessToken(h, 8, out t)) { CloseHandle(h); return -1; }
        int v, r; bool ok = GetTokenInformation(t, 20, out v, 4, out r); CloseHandle(t); CloseHandle(h);
        return ok ? v : -1;
    }
}
'@
$ex = @(Get-Process explorer -ErrorAction SilentlyContinue)
W ("  explorer running again: {0}; elevated (1=yes, 0=no): {1}" -f ($ex.Count -gt 0), (($ex | ForEach-Object { [TokElev]::IsElevated($_.Id) }) -join ','))

$B1 = Get-State
W ("`r`n  OVERALL: state now vs. very start: {0}" -f $(if ($d = @(Compare-State $B0 $B1)) { 'DIFFERENT in ' + ($d -join ', ') } else { 'identical (everything restored)' }))
foreach ($k in @(Compare-State $B0 $B1)) { Add-Content (Join-Path $OutDir 'overall-diff.txt') -Value ("=== $k`n--- START`n{0}`n--- END`n{1}`n" -f $B0[$k], $B1[$k]) }

# ---- 7b Service Killer: one headless tick with fake GUI controls --------------------------------
W "`r`n===== 7b Service Killer (one tick, 'Allow shared' ON, then OFF)"
$shared = Get-CimInstance Win32_Service | Where-Object { $_.State -eq 'Running' -and $_.ProcessId -gt 0 } | Group-Object ProcessId | Where-Object { $_.Count -gt 1 } |
    Where-Object { -not ($_.Group | Where-Object { $script:KillCritical -contains $_.Name -or (Test-RebootOnFailure $_.Name) }) } | Select-Object -First 1
$sharedName = if ($shared) { $shared.Group[0].Name } else { '' }
$script:KillTimer = [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Stop -Value { } -PassThru | Add-Member -MemberType ScriptMethod -Name Start -Value { } -PassThru
foreach ($allow in $true, $false) {
    # Allow ON: only Spooler + WSearch may die. Allow OFF: the shared (non-critical) service must be skipped, not killed.
    $names = if ($allow) { @('Spooler', 'RpcSs', 'mpssvc', 'BFE', 'EventLog', 'WSearch', '') } else { @('RpcSs', 'mpssvc', 'BFE', 'EventLog', $sharedName, '', '') }
    $script:KillBoxes = @($names | ForEach-Object { [pscustomobject]@{ Text = $_ } })
    $script:KillLabels = @(1..7 | ForEach-Object { [pscustomobject]@{ Text = '' } })
    $script:KillCounts = @(0, 0, 0, 0, 0, 0, 0); $script:KillRunning = $false
    $script:KillAllowShared = [pscustomobject]@{ Checked = $allow }
    Invoke-KillTick
    W "  Allow shared = $allow"
    for ($i = 0; $i -lt 7; $i++) { if ($script:KillBoxes[$i].Text) { W ("    {0,-22} -> {1}" -f $script:KillBoxes[$i].Text, $script:KillLabels[$i].Text) } }
    foreach ($n in 'Spooler', 'WSearch') { $null = StartSvc $n }
}
Start-Sleep 3
W ("  after restart: Spooler={0} WSearch={1} mpssvc={2} BFE={3}" -f (Get-Service Spooler).Status, (Get-Service WSearch).Status, (Get-Service mpssvc).Status, (Get-Service BFE).Status)

$results | Export-Csv (Join-Path $OutDir 'results.csv') -NoTypeInformation
W "`r`nDONE $(Get-Date)"
