# Run-V17-Verify.ps1 - admin verification of V1.7 on the real VM, plus the full log-generation run. Run as admin.
# Output: %LOCALAPPDATA%\suite-v17\summary.txt (log generation: %LOCALAPPDATA%\suite-logs\summary.txt, smoke: %TEMP%\suite-smoke)
$ErrorActionPreference = 'Continue'
$D = Join-Path $env:LOCALAPPDATA 'suite-v17'; Remove-Item $D -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $D | Out-Null
$sum = Join-Path $D 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
$script:Checks = 0; $script:Fails = 0
function Check($name, [bool]$ok, $detail = '') { $script:Checks++; if (-not $ok) { $script:Fails++ }; W ("  [{0}] {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($detail) { "  -- $detail" } else { '' })) }
. (Join-Path $PSScriptRoot 'Harness.ps1')
W ("V1.7 verification {0}  admin={1}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$ps = Join-Path $PSHOME 'powershell.exe'

# ---------- WinFixKit V1.7 ----------
& {
    W "`r`n===== WinFixKit $(Resolve-SuitePath 'WinFixKit.ps1')"
    $script:RootDir = Join-Path $D 'wfk'; $script:LogDir = Join-Path $script:RootDir 'Logs'; $script:ReportDir = Join-Path $script:RootDir 'Reports'
    $script:RegDir = Join-Path $script:RootDir 'RegistryBackups'; $script:RegKeyDir = Join-Path $script:RegDir 'Keys'; $script:RegFullDir = Join-Path $script:RegDir 'Full'
    foreach ($x in $script:LogDir, $script:ReportDir, $script:RegKeyDir, $script:RegFullDir) { New-Item -ItemType Directory -Force $x | Out-Null }
    $ast = Get-SuiteAst 'WinFixKit.ps1'
    foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
    function Write-Out($t, $c) { }
    . ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' 'script:FwGroups')))
    . ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' 'Sections')))
    function Act($l) { foreach ($s in $Sections) { foreach ($a in $s.Actions) { if ($a.Label -eq $l) { return $a } } } }

    # firewall fix: profiles must not change; only rules that never apply to Public get enabled
    $snap = { @(foreach ($g in $script:FwGroups.Values) { Get-NetFirewallRule -Group $g }) | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Enabled = [string]$_.Enabled; Profile = [int]$_.Profile } } }
    $before = & $snap
    $out = (& (Act 'Enable Network Discovery + File/Printer Sharing rules').Run $null) -join ' | '
    $after = & $snap
    $profChanged = @(Compare-Object $before $after -Property Name, Profile).Count
    $wrongOn = @($after | Where-Object { $_.Enabled -eq 'True' -and (($_.Profile -band 4) -or $_.Profile -eq 0) -and ($before | Where-Object Name -eq $_.Name).Enabled -ne 'True' }).Count
    $shouldOn = @($after | Where-Object { $_.Profile -ne 0 -and -not ($_.Profile -band 4) -and $_.Enabled -ne 'True' }).Count
    Check 'firewall fix: no rule profile changed' ($profChanged -eq 0) "$profChanged changed"
    Check 'firewall fix: no Public/Any rule newly enabled' ($wrongOn -eq 0)
    Check 'firewall fix: every Private/Domain-only rule is enabled' ($shouldOn -eq 0) $out
    foreach ($r in $before | Where-Object Enabled -ne 'True') { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
    Check 'firewall rules put back to their original state' (@(Compare-Object $before (& $snap) -Property Name, Enabled, Profile).Count -eq 0)

    # full backup: honest restore point message (System Restore is disabled on this VM)
    $fb = (Invoke-FullRegBackup) -join ' | '
    Check 'full registry backup: hives saved, restore point reported honestly' (($fb -match 'SYSTEM saved') -and ($fb -match 'SOFTWARE saved') -and ($fb -match 'Restore point NOT created|restore point created')) $fb
    Check 'full backup marked done only on success' ($script:FullBackupDone -eq $true)
    Remove-Item (Join-Path $script:RegFullDir '*') -Recurse -Force -ErrorAction SilentlyContinue

    # take ownership on a test folder (real icacls / takeown)
    $tf = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WFK-V17-Test'; New-Item -ItemType Directory -Force "$tf\sub" | Out-Null; 'x' | Set-Content "$tf\sub\f.txt"
    $o = (& (Act 'Take ownership + reset permissions of a folder...').Run $tf) -join ' | '
    Check 'take ownership on a test folder: backup saved, done, no ABORT/WARNING' (($o -match 'Saving current permissions') -and ($o -notmatch 'ABORTED|WARNING') -and ($o -match 'Owner after')) ($o.Substring(0, [Math]::Min(220, $o.Length)))
    Remove-Item $tf -Recurse -Force -ErrorAction SilentlyContinue

    # status checks with V1.7 (power settings, winsock count, cmdkey, search index, firewall table)
    foreach ($sec in $Sections | Where-Object { $_.Name -in 'Power', 'Network', 'Microsoft Account', 'Search and Indexing', 'Network Sharing', 'Store Apps', 'Hardware and Devices' }) {
        $t = (& $sec.Status 2>&1 | Out-String -Width 220)
        $t | Set-Content (Join-Path $D ("status-" + ($sec.Name -replace '\W', '_') + '.txt'))
        $err = @($t -split "`r?`n" | Where-Object { $_ -match 'FullyQualifiedErrorId|UNCAUGHT' }).Count
        $extra = switch ($sec.Name) {
            'Power' { 'power lines: ' + @($t -split "`r?`n" | Where-Object { $_ -match ' (AC|DC): ' }).Count }
            'Network' { ($t -split "`r?`n" | Where-Object { $_ -match 'Catalog entries' } | Select-Object -First 1) }
            'Search and Indexing' { ($t -split "`r?`n" | Where-Object { $_ -match '^Windows.*\.(db|edb) :|No index' } | Select-Object -First 3) -join '; ' }
            'Store Apps' { ($t -split "`r?`n" | Where-Object { $_ -match '^Installed \(' } | Select-Object -First 1) }
            default { '' }
        }
        Check "status '$($sec.Name)' runs without PowerShell errors" ($err -eq 0) "$extra"
    }
}

# ---------- WinSuperTool V1.7: diskpart letter reader + Recovery console ----------
& {
    W "`r`n===== WinSuperTool $(Resolve-SuitePath 'WinSuperTool.ps1')"
    $ST = 'WinSuperTool.ps1'; $NL = "`r`n"; $IsWinPE = $false
    $ast = Get-SuiteAst $ST
    foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
    foreach ($v in 'DpAllow', 'BcdSetBuild', 'Tools', 'PsExePath') { . ([scriptblock]::Create((Get-AssignText $ST $v))) }
    function Log($m) { Add-Content (Join-Path $D 'wst-log.txt') $m }
    function Msg($t, $c, $i) { $script:LastMsg = [string]$t }
    function Ask($t, $c, $i, $d) { $true }
    function Safe([scriptblock]$Do) { try { & $Do } catch { $script:LastErr = $_.Exception.Message } }
    $part = @{}; foreach ($p in Get-Partition -DiskNumber 0) { $part[[string]$p.Type] = $p.PartitionNumber }
    Check "real diskpart: C: partition -> 'C'" ((Get-DpPartLetter 0 $part['Basic']) -eq 'C')
    Check "real diskpart: MSR -> 'NOVOLUME'" ((Get-DpPartLetter 0 $part['Reserved']) -eq 'NOVOLUME') (Get-DpPartLetter 0 $part['Reserved'])
    Check "real diskpart: EFI partition without letter -> ''" ((Get-DpPartLetter 0 $part['System']) -eq '') "'$(Get-DpPartLetter 0 $part['System'])'"
    # Recovery: a window tool now opens a PowerShell console (not cmd /c)
    $script:Consoles = New-Object Collections.ArrayList
    $h = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $x.Expression.Extent.Text -eq '$btnTool' -and $x.Member.Extent.Text -eq 'Add_Click' }, $true)
    $tx = $h.Arguments[0].Extent.Text.Trim(); $run = [scriptblock]::Create($tx.Substring(1, $tx.Length - 2))
    $cmbTool = [pscustomobject]@{ SelectedItem = ($Tools | Where-Object Name -eq 'Drivers: list third-party drivers') }
    $cmbEsp = [pscustomobject]@{ SelectedItem = $null }
    function Get-TargetWin { [pscustomobject]@{ Drive = 'C:'; Text = 'C:\Windows'; Running = $true } }
    & $run
    Start-Sleep 12
    $c = @($script:Consoles | Where-Object { $_ })
    $alive = $c.Count -and -not $c[0].HasExited
    $cl = if ($c.Count) { (Get-CimInstance Win32_Process -Filter "ProcessId=$($c[0].Id)").CommandLine } else { '' }
    Check 'Recovery window tool opens a PowerShell console (-EncodedCommand), still open waiting for Enter' ($alive -and $cl -match 'powershell\.exe.*-EncodedCommand') $cl.Substring(0, [Math]::Min(120, $cl.Length))
    foreach ($p in $c) { try { Stop-Process -Id $p.Id -Force } catch {} }
    $cmbTool.SelectedItem = $Tools | Where-Object Name -eq 'Scan for Windows installs (bootrec /scanos)'
    $script:LastMsg = ''; & $run
    Check 'bootrec missing -> "not available" message (unchanged)' ($script:LastMsg -match 'not available')
}

# ---------- full log generation + GUI smoke test (child processes, already elevated) ----------
W "`r`n===== log generation (Run-LogGen.ps1)"
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-LogGen.ps1') | Out-Null
Get-Content (Join-Path $env:LOCALAPPDATA 'suite-logs\summary.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "  $_" }
W "`r`n===== GUI smoke test (Run-ElevatedSmoke.ps1)"
& $ps -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $PSScriptRoot 'Run-ElevatedSmoke.ps1') | Out-Null
Get-Content (Join-Path $env:TEMP 'suite-smoke\summary.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "  $_" }
W ("`r`nTOTAL own checks: {0}, failed {1}.  DONE {2}" -f $script:Checks, $script:Fails, (Get-Date))
