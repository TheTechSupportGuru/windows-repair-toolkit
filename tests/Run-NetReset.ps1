# Run-NetReset.ps1 - Phase 3: WinFixKit network-reset fixes on the real VM, in stages around reboots. Run as admin.
#   -Stage pre     : baseline, "Release and renew DHCP lease", then "FULL network reset"   -> then REBOOT
#   -Stage post    : after the reboot: connectivity + compare with the baseline
#   -Stage restore : undo with WinFixKit's own Restore-RegBackup (network keys), compare keys with the baseline -> REBOOT, then -Stage post
# Everything is kept in %LOCALAPPDATA%\suite-net (survives reboots).
param([ValidateSet('pre', 'post', 'restore')][string]$Stage = 'pre')
$ErrorActionPreference = 'Continue'
$D = Join-Path $env:LOCALAPPDATA 'suite-net'; New-Item -ItemType Directory -Force $D | Out-Null
$sum = Join-Path $D 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
. (Join-Path $PSScriptRoot 'Harness.ps1')
# WinFixKit functions + sections, data folders persistent
$script:RootDir = Join-Path $D 'wfk'; $script:LogDir = Join-Path $script:RootDir 'Logs'; $script:ReportDir = Join-Path $script:RootDir 'Reports'
$script:RegDir = Join-Path $script:RootDir 'RegistryBackups'; $script:RegKeyDir = Join-Path $script:RegDir 'Keys'; $script:RegFullDir = Join-Path $script:RegDir 'Full'
foreach ($x in $script:LogDir, $script:ReportDir, $script:RegKeyDir, $script:RegFullDir) { New-Item -ItemType Directory -Force $x | Out-Null }
$script:LogFile = Join-Path $script:LogDir 'net.log'; $LogDir = $script:LogDir
$ast = Get-SuiteAst 'WinFixKit.ps1'
foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
function Write-Out($t, $c) { }
. ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' 'Sections')))
function Act($label) { foreach ($s in $Sections) { foreach ($a in $s.Actions) { if ($a.Label -eq $label) { return $a } } } }

$Keys = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters', 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters', 'HKLM\SYSTEM\CurrentControlSet\Services\Winsock', 'HKLM\SYSTEM\CurrentControlSet\Services\Winsock2'
$Volatile = '^"(Lease\w*|T1|T2|DhcpIPAddress|DhcpSubnetMask|DhcpServer|DhcpDefaultGateway|DhcpNameServer|DhcpDomain|DhcpInterfaceOptions|DhcpGatewayHardware\w*|Dhcpv6\w*|AddressType|IsServerNapAware|DhcpConnForceBroadcastFlag)"='
function Export-Keys($tag) {
    foreach ($k in $Keys) {
        $name = (($k -split '\\')[-2..-1]) -join '_'
        $f = Join-Path $D ("{0}-{1}.reg" -f $tag, $name)
        $null = & reg.exe export $k $f /y 2>&1
    }
}
function Compare-Keys($a, $b) {
    $n = 0
    foreach ($k in $Keys) {
        $name = ($k -split '\\')[-2..-1] -join '_'
        $fa = Join-Path $D "$a-$name.reg"; $fb = Join-Path $D "$b-$name.reg"
        if (-not (Test-Path $fa) -or -not (Test-Path $fb)) { W "    $name : missing export"; continue }
        # one logical line per value (join binary continuation lines), then drop the DHCP lease values that change by themselves
        $ta = ((Get-Content $fa -Raw) -replace "\\\r?\n\s*", '') -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch $Volatile }
        $tb = ((Get-Content $fb -Raw) -replace "\\\r?\n\s*", '') -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch $Volatile }
        $diff = @(Compare-Object $ta $tb)      # (not $d: PowerShell names ignore case and $D is the data folder)
        $n += $diff.Count
        W ("    {0,-28} differences: {1}" -f $name, $diff.Count)
        $diff | Select-Object -First 12 | ForEach-Object { $l = $_.InputObject; W ("       {0} {1}" -f $_.SideIndicator, $l.Substring(0, [Math]::Min(140, $l.Length))) }
    }
    return $n
}
function Get-Net {
    $c = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    $dns = (Get-DnsClientServerAddress -InterfaceIndex $c.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ','
    $dhcp = [string](Get-NetIPInterface -InterfaceIndex $c.InterfaceIndex -AddressFamily IPv4).Dhcp
    $cat = @(netsh winsock show catalog | Select-String 'Catalog Entry|Description').Count
    $web = try { (Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 10).Content.Trim() } catch { "FAILED: $($_.Exception.Message)" }
    $res = try { (Resolve-DnsName 'www.microsoft.com' -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1).IPAddress } catch { 'FAILED' }
    [pscustomobject]@{ Adapter = $c.InterfaceAlias; IPv4 = ($c.IPv4Address.IPAddress -join ','); Gateway = ($c.IPv4DefaultGateway.NextHop -join ','); DNS = $dns; Dhcp = $dhcp
        WinsockLines = $cat; DnsLookup = $res; Web = $web; Proxy = ((netsh winhttp show proxy) -join ' ' -replace '\s+', ' ').Trim() }
}
function Show-Net($n, $title) { W "  $title"; foreach ($p in $n.PSObject.Properties) { W ("     {0,-12} {1}" -f $p.Name, $p.Value) } }

W ("`r`n################ STAGE {0}  {1}  file={2}" -f $Stage.ToUpper(), (Get-Date), (Resolve-SuitePath 'WinFixKit.ps1'))
switch ($Stage) {
    'pre' {
        Remove-Item (Join-Path $D '*.reg'), (Join-Path $D 'baseline.json') -ErrorAction SilentlyContinue
        Get-ChildItem $script:RegKeyDir -ErrorAction SilentlyContinue | Remove-Item -Force
        $b = Get-Net; $b | ConvertTo-Json | Set-Content (Join-Path $D 'baseline.json'); Show-Net $b 'BASELINE'
        Export-Keys 'base'
        W "`r`n  --- Full registry backup (the GUI takes it before the first registry fix of a session)"
        $sw = [Diagnostics.Stopwatch]::StartNew(); $o = @(Invoke-FullRegBackup 2>&1 | ForEach-Object { "$_" }); $sw.Stop()
        $o | ForEach-Object { W "       $_" }; W ("     took {0:N1}s" -f $sw.Elapsed.TotalSeconds)
        $hv = @(Get-ChildItem $script:RegFullDir -Recurse -Filter *.hiv); W ("     hive files: {0}" -f (($hv | ForEach-Object { '{0} {1:N0} MB' -f $_.Name, ($_.Length / 1MB) }) -join ', '))
        W "`r`n  --- Release and renew DHCP lease"
        $sw = [Diagnostics.Stopwatch]::StartNew(); $o = (& (Act 'Release and renew DHCP lease').Run $null | Out-String); $sw.Stop()
        W ("     took {0:N1}s; renew output mentions IPv4: {1}" -f $sw.Elapsed.TotalSeconds, [bool]($o -match 'IPv4'))
        Start-Sleep 3; Show-Net (Get-Net) 'after DHCP release/renew'
        W "`r`n  --- FULL network reset"
        $sw = [Diagnostics.Stopwatch]::StartNew(); $o = (& (Act 'FULL network reset (all of the above)').Run $null 2>&1 | Out-String -Width 200); $sw.Stop()
        $o | Set-Content (Join-Path $D 'full-reset-output.txt')
        W ("     took {0:N1}s. Output lines: " -f $sw.Elapsed.TotalSeconds)
        ($o -split "`r?`n" | Where-Object { $_ -match 'Backed|backup|export|Flush|ARP|WinHTTP|Winsock|TCP|Renew|reboot|Restart|error|fail|Successfully reset|resetlog' }) | Select-Object -First 25 | ForEach-Object { W "       $($_.Trim())" }
        W ("     netsh ip reset log written: {0}" -f (Test-Path (Join-Path $script:LogDir 'netsh-ip-reset.log')))
        W ("     WinFixKit key backups: {0}" -f ((Get-ChildItem $script:RegKeyDir -Filter *.json | ForEach-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).Key }) -join ' | '))
        Start-Sleep 3; Show-Net (Get-Net) 'after FULL reset (before reboot)'
        Export-Keys 'afterreset'
        W "  registry: after FULL reset vs. baseline"; [void](Compare-Keys 'base' 'afterreset')
        W "`r`n  >>> NOW REBOOT, then run -Stage post"
    }
    'post' {
        $b = Get-Content (Join-Path $D 'baseline.json') -Raw | ConvertFrom-Json
        $n = Get-Net; Show-Net $n 'NOW'
        $bd = if ("$($b.Dhcp)" -eq '1') { 'Enabled' } elseif ("$($b.Dhcp)" -eq '0') { 'Disabled' } else { "$($b.Dhcp)" }   # older baseline stored the enum number
        foreach ($p in 'IPv4', 'Gateway', 'DNS', 'Proxy') { W ("     {0,-8} same as baseline: {1}" -f $p, ("$($n.$p)" -eq "$($b.$p)")) }
        W ("     Dhcp     same as baseline: {0}" -f ("$($n.Dhcp)" -eq $bd))
        W ("     internet OK: {0}   DNS lookup OK: {1}" -f ($n.Web -eq 'Microsoft Connect Test'), ($n.DnsLookup -ne 'FAILED'))
        $tag = 'post' + (Get-Date -Format HHmmss); Export-Keys $tag
        W "  registry now vs. baseline"; [void](Compare-Keys 'base' $tag)
    }
    'restore' {
        $js = @(Get-ChildItem $script:RegKeyDir -Filter *.json)
        W "  restoring $($js.Count) WinFixKit key backup(s) with Restore-RegBackup (what the Registry Backups tab does)"
        foreach ($j in $js) { W ("     " + ((Restore-RegBackup $j.FullName 2>&1 | Out-String).Trim() -replace "`r?`n", ' / ')) }
        Export-Keys 'restored'
        W "  registry after restore vs. baseline"; $d = Compare-Keys 'base' 'restored'
        W "  >>> total differences after restore: $d.  NOW REBOOT, then run -Stage post again"
    }
}
W "  stage done $(Get-Date)"
