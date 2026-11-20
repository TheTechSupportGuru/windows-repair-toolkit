# Run-V14-Verify.ps1 - admin verification of the V1.4 fixes on the real system. The live BCD is NOT modified
# (no live /import - known to close the store on this VM). Output: %TEMP%\suite-v14\summary.txt
$ErrorActionPreference = 'Continue'
$OutDir = Join-Path $env:TEMP 'suite-v14'; Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $OutDir | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
$script:Checks = 0; $script:Fails = 0
function Check($name, [bool]$ok, $detail = '') { $script:Checks++; if (-not $ok) { $script:Fails++ }; W ("  [{0}] {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($detail) { "  -- $detail" } else { '' })) }
. (Join-Path $PSScriptRoot 'Harness.ps1')
$Suite = $global:SuiteDir
W "V1.4 verification $(Get-Date)  admin=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
$enumBefore = (& bcdedit.exe /enum all /v | Out-String)

# loader used in this process AND in the child processes: defines one version's functions with GUI stubs
$loader = @'
param($ScriptPath, $StateFile)
$t = $null; $e = $null; $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$t, [ref]$e)
foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
foreach ($v in 'DpAllow') { $a = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq "`$$v" }, $true); . ([scriptblock]::Create($a.Extent.Text)) }
function Log($m) { $script:LastLog = $m }
function Msg($t, $c, $i) { $script:LastMsg = $t }
$rbStor = [pscustomobject]@{ Checked = $true }
'@
$loaderFile = Join-Path $OutDir 'loader.ps1'; Set-Content $loaderFile $loader -Encoding UTF8
function Free-Letter { foreach ($c in 'S', 'T', 'U', 'V', 'W') { if (-not (Test-Path "${c}:\")) { return $c } } }

foreach ($ver in 'V1.3', 'V1.4') {
    $sp = Join-Path $Suite "Edited scripts\$ver\WinSuperTool.ps1"
    W "`r`n===== #26 diskpart mount -> mount memory  [$ver]"
    $state = Join-Path $OutDir "mounts-$ver.json"
    . $loaderFile -ScriptPath $sp -StateFile $state; $StateFile = $state
    $esp = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'System').PartitionNumber
    $L = Free-Letter
    $rbStor.Checked = $false                      # diskpart mode
    $ok = Mount-Part 0 $esp $L
    $script:Mounts = New-Object Collections.ArrayList; [void]$script:Mounts.Add([pscustomobject]@{ Letter = $L; Disk = 0; Partition = $esp }); Save-Mounts
    Check "[$ver] diskpart mount of the ESP as ${L}:" $ok
    # same process (cache possibly stale)
    Load-Mounts; Check "[$ver] SAME process: memory keeps the diskpart mount" ($script:Mounts.Count -eq 1) "$script:LastLog"
    # new process = what really happens when the tool is started again
    $child = "& { . '$loaderFile' -ScriptPath '$sp' -StateFile '$state'; `$StateFile = '$state'; Load-Mounts; `$script:Mounts.Count }"
    $n = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $child | Select-Object -Last 1)
    Check "[$ver] NEW process (tool restarted): memory keeps the diskpart mount" ("$n".Trim() -eq '1') "child count: $n"
    # unmount in Storage mode right after a diskpart mount (stale cache test)
    $rbStor.Checked = $true
    $err = ''; try { Unmount-Letter $L } catch { $err = $_.Exception.Message }
    Start-Sleep 1
    Check "[$ver] Storage-mode Unmount right after a diskpart mount works" (-not (Test-Path "${L}:\")) $err
    if (Test-Path "${L}:\") { & mountvol.exe "${L}:" /D | Out-Null }
}

W "`r`n===== #25 MSR refused, #27 empty letter  [V1.4]"
. $loaderFile -ScriptPath (Join-Path $Suite 'Edited scripts\V1.4\WinSuperTool.ps1') -StateFile (Join-Path $OutDir 'm.json')
$msr = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'Reserved').PartitionNumber
foreach ($mode in 'Storage', 'diskpart') {
    $rbStor.Checked = ($mode -eq 'Storage'); $L = Free-Letter; $err = ''
    try { [void](Mount-Part 0 $msr $L) } catch { $err = $_.Exception.Message }
    Check "[$mode] Mount-Part refuses the MSR, no letter assigned" (($err -match 'Microsoft Reserved') -and -not (Test-Path "${L}:\")) $err
    if (Test-Path "${L}:\") { & mountvol.exe "${L}:" /D | Out-Null }
}
$script:Mounts = New-Object Collections.ArrayList
Check "Dismount-One refuses an empty letter" (-not (Dismount-One ([pscustomobject]@{ Letter = '' })))

W "`r`n===== #28 offline BCD restore by file copy (on COPIES - the live store is not touched)"
$NL = "`r`n"; $BcdBackupDir = Join-Path $OutDir 'bcdbk'; $DataOnRam = $false
$work = Join-Path $OutDir 'bcdwork'; New-Item -ItemType Directory -Force $work | Out-Null
& bcdedit.exe /export "$work\store.bcd" | Out-Null                      # stands in for an offline <ESP>\EFI\Microsoft\Boot\BCD
& bcdedit.exe /export "$work\good.bak" | Out-Null                       # the backup to restore
$o = (& bcdedit.exe /store "$work\store.bcd" /export "$work\viaexport.bak" 2>&1 | Out-String).Trim()
W "  evidence: 'bcdedit /store <file> /export <file>' -> exit $LASTEXITCODE  $o"
$t = @{ Store = "$work\store.bcd"; Id = '{default}' }
& bcdedit.exe /store "$work\store.bcd" /set '{bootmgr}' timeout 7 | Out-Null    # "damage" the offline store
Check "offline copy was changed (timeout 7)" (((& bcdedit.exe /store "$work\store.bcd" /enum '{bootmgr}') | Out-String) -match '(?m)^timeout\s+7')
$r = Restore-BcdBackup $t "$work\good.bak"
Check "Restore-BcdBackup (offline) succeeds and verifies" ($r.Rc -eq 0) $r.Out
Check "restored offline store opens in bcdedit and has the original timeout" (((& bcdedit.exe /store "$work\store.bcd" /enum '{bootmgr}') | Out-String) -notmatch '(?m)^timeout\s+7')
Check "a backup of the damaged offline store was taken first" (@(Get-ChildItem $BcdBackupDir -Filter 'BCD_*.bak' -ErrorAction SilentlyContinue).Count -eq 1)

W "`r`n===== #29 Sysprep pre-flight Store-app check  [V1.4]"
$form = [pscustomobject]@{ Cursor = 'Default' }
$pf = @(Get-Preflight 'A')
$app = @($pf | Where-Object { $_.Text -match 'Store app|for one user only|provisioned' })
foreach ($i in $app) { W "    $($i.Level): $($i.Text)" }
Check "pre-flight A runs the Store-app check (OK or WARN with a reason - not 'skipped')" ($app.Count -eq 1 -and $app[0].Level -in 'OK', 'WARN' -and $app[0].Text -notmatch 'skipped')

W "`r`n===== end state"
Check "live BCD unchanged by this run" ((& bcdedit.exe /enum all /v | Out-String) -eq $enumBefore)
Check "only C: and D: have letters" ((@([IO.DriveInfo]::GetDrives().Name) -join '') -eq 'C:\D:\') (@([IO.DriveInfo]::GetDrives().Name) -join ' ')
W ("`r`nTOTAL: {0} checks, {1} failed.  DONE {2}" -f $script:Checks, $script:Fails, (Get-Date))
