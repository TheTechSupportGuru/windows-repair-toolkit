# Run-Phase3-WST.ps1 - Phase 3 / 7c-7g for WinSuperTool (newest Edited version), headless, AS ADMIN on this VM.
# Uses WinSuperTool's own functions and its real button handlers (extracted from the script) with fake GUI controls.
#   7c Mount   : real mount/unmount of the EFI + recovery partitions (Storage AND diskpart mode), mount memory with real data
#   7d BCD     : Safe Mode edit + clone (live {current} AND /store path), boot-menu tools, backup/import  - NO reboot
#   7e Unattend: build + validate XML, deploy handler into a SUBST drive (never C:\Windows\Panther)
#   7f Recovery: tool argument building + warnings, bcdboot for real (BCD exported first), read-only chkdsk /scan + driver list
#   7g Sysprep : pre-flight checks only - sysprep.exe is NEVER started
# Safety: the whole BCD store is exported first and re-imported at the end if anything differs. Take a VM snapshot first.
param([string]$OutDir = (Join-Path $env:TEMP 'suite-phase3-wst'))
$ErrorActionPreference = 'Continue'
Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
function Check($name, [bool]$ok, $detail = '') { $script:Checks++; if (-not $ok) { $script:Fails++ }; W ("  [{0}] {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($detail) { "  -- $detail" } else { '' })) }
$script:Checks = 0; $script:Fails = 0
. (Join-Path $PSScriptRoot 'Harness.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$ST = 'WinSuperTool.ps1'
W ("Phase 3 WinSuperTool run {0}  admin={1}  version={2}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator), (Resolve-SuitePath $ST))

# ---- environment the functions expect ----
$NL = "`r`n"; $IsWinPE = $false; $AppName = 'Windows Super Tool'; $DataOnRam = $false
$DataDir = Join-Path $OutDir 'data'; New-Item -ItemType Directory -Force $DataDir | Out-Null
$BcdBackupDir = Join-Path $DataDir 'BCD-Backups'; $StateFile = Join-Path $DataDir 'mounts.json'; $ActivityLog = Join-Path $DataDir 'activity.log'
$ast = Get-SuiteAst $ST
foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
foreach ($v in 'DpAllow', 'CloneMarkers', 'BcdSetBuild', 'Tools') { . ([scriptblock]::Create((Get-AssignText $ST $v))) }
# GUI stubs (after loading, so they replace the real ones)
$script:LogLines = New-Object Collections.ArrayList
function Log([string]$m) { [void]$script:LogLines.Add($m); Add-Content -LiteralPath (Join-Path $OutDir 'tool-log.txt') -Value $m }
function Msg($t, $c, $i) { $script:LastMsg = [string]$t; Add-Content -LiteralPath (Join-Path $OutDir 'tool-log.txt') -Value "MSG: $t" }
$script:AskAnswer = $true
function Ask($t, $c, $i, $d) { $script:LastAsk = [string]$t; Add-Content -LiteralPath (Join-Path $OutDir 'tool-log.txt') -Value "ASK($($script:AskAnswer)): $t"; return $script:AskAnswer }
function Safe([scriptblock]$Do) { try { & $Do } catch { $script:LastErr = $_.Exception.Message; Log "ERROR: $($_.Exception.Message)" } }
function Update-SafeStatus { } ; function Update-AfterMountChange { Save-Mounts }
$rbStor = [pscustomobject]@{ Checked = $true }; $rbClone = [pscustomobject]@{ Checked = $false }
$form = [pscustomobject]@{ Cursor = 'Default' }
$script:Target = $null; function Get-TargetWin { $script:Target }
function Get-Handler([string]$ctl) {
    $h = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $x.Expression.Extent.Text -eq $ctl -and $x.Member.Extent.Text -eq 'Add_Click' }, $true)
    $t = $h.Arguments[0].Extent.Text.Trim(); [scriptblock]::Create($t.Substring(1, $t.Length - 2))
}
function Free-Letter { foreach ($c in 'S', 'T', 'U', 'V', 'W') { if (-not (Test-LetterUsed $c)) { return $c } } }
$espPart = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'System' | Select-Object -First 1).PartitionNumber
$recPart = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'Recovery' | Select-Object -Last 1).PartitionNumber
$msrPart = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'Reserved' | Select-Object -First 1).PartitionNumber

# ---- BCD safety net ----
$bcdBase = Join-Path $OutDir 'BCD-baseline.bak'
& bcdedit.exe /export $bcdBase | Out-Null
$enumBase = (& bcdedit.exe /enum all /v | Out-String)
$enumBase | Set-Content (Join-Path $OutDir 'bcd-enum-before.txt')
W "  BCD baseline exported: $(Test-Path $bcdBase)"

# =====================================================================================================
W "`r`n===== 7c Mount (disk 0: EFI = partition $espPart, recovery = partition $recPart, MSR = partition $msrPart)"
foreach ($mode in 'Storage', 'diskpart') {
    $rbStor.Checked = ($mode -eq 'Storage')
    $disks = @(Get-DiskList); Check "[$mode] Get-DiskList finds disk 0" ($disks.Num -contains 0) (($disks.Text) -join ' | ')
    $parts = @(Get-PartList 0); Check "[$mode] Get-PartList 0 finds 5 partitions" ($parts.Count -eq 5) (($parts.Text) -join ' | ')
    foreach ($pn in $espPart, $recPart) {
        $L = Free-Letter
        $ok = $false; try { $ok = Mount-Part 0 $pn $L } catch { $script:LastErr = $_.Exception.Message }
        Check "[$mode] mount partition $pn as ${L}:" $ok $script:LastErr
        if ($ok) {
            Check "[$mode] Get-PartLetter 0 $pn = $L" ((Get-PartLetter 0 $pn) -eq $L)
            if ($pn -eq $espPart) { Check "[$mode] ${L}:\EFI\Microsoft\Boot\BCD visible" (Test-Path "${L}:\EFI\Microsoft\Boot\BCD") }
            $m = [pscustomobject]@{ Letter = $L; Disk = 0; Partition = $pn }
            $script:Mounts = New-Object Collections.ArrayList; [void]$script:Mounts.Add($m); Save-Mounts; Load-Mounts
            Check "[$mode] mount memory reloads the real mount" ($script:Mounts.Count -eq 1)
            Check "[$mode] Dismount-One frees ${L}:" ((Dismount-One $script:Mounts[0]) -and -not (Test-LetterUsed $L))
        }
    }
    $L = Free-Letter; $script:LastErr = ''
    $okMsr = $false; try { $okMsr = Mount-Part 0 $msrPart $L } catch { $script:LastErr = $_.Exception.Message }
    Check "[$mode] MSR partition cannot be mounted and fails cleanly (no letter left behind)" ((-not $okMsr) -and -not (Test-LetterUsed $L)) $script:LastErr
    if (Test-LetterUsed $L) { try { Unmount-Letter $L } catch {} }
}
$rbStor.Checked = $true
# stale memory: remember S on the EFI partition, then give that letter to the recovery partition
$L = Free-Letter
[void](Mount-Part 0 $espPart $L); $script:Mounts = New-Object Collections.ArrayList; [void]$script:Mounts.Add([pscustomobject]@{ Letter = $L; Disk = 0; Partition = $espPart }); Save-Mounts
Unmount-Letter $L; Start-Sleep 1; [void](Mount-Part 0 $recPart $L)
Load-Mounts
Check "stale memory: ${L}: now on the recovery partition is NOT adopted" ($script:Mounts.Count -eq 0) ("log: " + ($script:LogLines | Select-Object -Last 1))
Unmount-Letter $L
$script:Mounts = New-Object Collections.ArrayList
Check "Dismount-One refuses the system drive" ((-not (Dismount-One ([pscustomobject]@{ Letter = 'C'; Disk = 0; Partition = 4 }))) -and (Test-Path 'C:\'))
Check "no drive letters left assigned by the test" ((@([IO.DriveInfo]::GetDrives().Name) -join '') -eq 'C:\D:\') (@([IO.DriveInfo]::GetDrives().Name) -join ' ')

# =====================================================================================================
W "`r`n===== 7d Safe Mode / BCD (no reboot)"
$script:Target = [pscustomobject]@{ Drive = 'C:'; Text = 'C:\Windows (test)'; Running = $true }
$t = Resolve-BcdTarget 'C:'
Check "Resolve-BcdTarget C: -> {current}" ($t.Id -eq '{current}' -and -not $t.Store) "safeboot now: '$($t.Safeboot)'"
$on = Get-Handler '$btnSafeOn'; $off = Get-Handler '$btnSafeOff'
function Get-Cur { @(ConvertFrom-BcdText ((& bcdedit.exe /enum '{current}') | Out-String))[0] }
# edit mode
$rbClone.Checked = $false; $script:AskAnswer = $true
& $on;  Check "edit mode: Enable sets safeboot Minimal on {current}" ((Get-Cur).Safeboot -eq 'Minimal')
& $off; Check "edit mode: Remove flag clears safeboot" (-not (Get-Cur).Safeboot)
$script:AskAnswer = $false; & $on; Check "edit mode: answering No changes nothing" (-not (Get-Cur).Safeboot); $script:AskAnswer = $true
# clone mode (live)
$rbClone.Checked = $true
& $on;  $cl = @(Get-Clones $t 'C:'); Check "clone mode: creates exactly 1 Safe Mode clone" ($cl.Count -eq 1) ($cl.Id -join ',')
if ($cl.Count) { $e = @(ConvertFrom-BcdText ((& bcdedit.exe /enum $cl[0].Id) | Out-String))[0]; Check "clone has safeboot Minimal, normal entry untouched" ($e.Safeboot -eq 'Minimal' -and -not (Get-Cur).Safeboot) }
$script:LastMsg = ''; & $on; Check "clone mode: second Create is refused ('already exists')" ($script:LastMsg -match 'already exists' -and @(Get-Clones $t 'C:').Count -eq 1)
& $off; Check "clone mode: Delete removes the clone" (@(Get-Clones $t 'C:').Count -eq 0)
# /store path (what WinPE uses): mount the ESP and pretend we are in WinPE
$L = Free-Letter; [void](Mount-Part 0 $espPart $L); $IsWinPE = $true
$ts = Resolve-BcdTarget 'C:'
Check "/store path: Resolve-BcdTarget finds ${L}:\EFI\Microsoft\Boot\BCD and the C: entry" ($ts.Store -eq "${L}:\EFI\Microsoft\Boot\BCD" -and $ts.Id -match '^\{') "store=$($ts.Store) id=$($ts.Id)"
& $on;  Check "/store path: clone created in the store" (@(Get-Clones $ts 'C:').Count -eq 1)
& $off; Check "/store path: clone deleted" (@(Get-Clones $ts 'C:').Count -eq 0)
$IsWinPE = $false; $rbClone.Checked = $false
# boot-menu tools via $BcdSetBuild
function Get-Val($name) { if (((& bcdedit.exe /enum '{current}') | Out-String) -match "(?m)^$name\s+(\S+)") { $Matches[1] } else { '' } }
$origPolicy = Get-Val 'bootmenupolicy'; $origRec = Get-Val 'recoveryenabled'
foreach ($pair in @(@('Boot menu: enable legacy F8 menu', 'bootmenupolicy', 'Legacy'), @('Boot menu: restore standard menu', 'bootmenupolicy', 'Standard'),
                    @('Automatic Repair loop: disable', 'recoveryenabled', 'No'), @('Automatic Repair loop: re-enable', 'recoveryenabled', 'Yes'))) {
    $tool = $Tools | Where-Object Name -eq $pair[0]
    $def = & $tool.Build @{ Win = 'C:'; Live = $true; Esp = ''; EspFS = '' } $tool
    & $def.Run $def.RunArg
    Check ("tool '{0}' -> {1} = {2}" -f $pair[0], $pair[1], $pair[2]) ((Get-Val $pair[1]) -eq $pair[2]) "now: $(Get-Val $pair[1])"
}
Check "boot-menu values back to original (policy '$origPolicy', recovery '$origRec')" ((Get-Val 'bootmenupolicy') -eq $origPolicy -and (Get-Val 'recoveryenabled') -eq $origRec)
# backup + import tools
$bk0 = @(Get-ChildItem $BcdBackupDir -Filter 'BCD_*.bak' -ErrorAction SilentlyContinue).Count
$tool = $Tools | Where-Object Name -eq 'BCD: back up store (export)'; $def = & $tool.Build @{ Win = 'C:'; Live = $true } $tool; Start-Sleep 1; & $def.Run $def.RunArg
$bks = @(Get-ChildItem $BcdBackupDir -Filter 'BCD_*.bak' | Sort-Object LastWriteTime)
Check "BCD backup tool writes a file" ($bks.Count -gt $bk0)
W ("  automatic BCD backups made during 7d: {0} (one per change)" -f $bks.Count)
$r = Invoke-Bcd $t @('/import', $bks[-1].FullName)
Check "bcdedit /import of a tool backup works (and backs up first)" ($r.Rc -eq 0) $r.Out.Trim()
Unmount-Letter $L

# =====================================================================================================
W "`r`n===== 7f Recovery tools"
$L = Free-Letter; [void](Mount-Part 0 $espPart $L)
$cmbEsp = [pscustomobject]@{ Items = (New-Object Collections.ArrayList); SelectedIndex = -1; SelectedItem = $null }
try { Update-Esp } catch { W "  (Update-Esp error: $($_.Exception.Message))" }
$picked = if ($cmbEsp.SelectedIndex -ge 0) { $cmbEsp.Items[$cmbEsp.SelectedIndex] } else { $null }
Check "boot-partition list auto-picks the mounted FAT32 ESP ${L}: (fixed disk)" ($picked -and $picked.Drive -eq "${L}:" -and -not $picked.Removable) (($cmbEsp.Items | ForEach-Object Text) -join ' | ')
$bcdbootTool = $Tools | Where-Object Name -eq 'Rebuild boot files (bcdboot)'
$script:AskAnswer = $false; $script:LastAsk = ''
$a1 = @(& $bcdbootTool.Argv @{ Win = 'C:'; Live = $true; Esp = "${L}:"; EspFS = 'FAT32' })
Check "bcdboot args on this UEFI VM with the FAT32 ESP: /f UEFI, no warning" (($a1 -join ' ') -eq "C:\Windows /s ${L}: /f UEFI" -and -not $script:LastAsk) ($a1 -join ' ')
$a2 = @(& $bcdbootTool.Argv @{ Win = 'C:'; Live = $true; Esp = 'C:'; EspFS = 'NTFS' })
Check "bcdboot with an NTFS partition on UEFI: warns, and No cancels" ($a2.Count -eq 0 -and $script:LastAsk -match 'UEFI mode') $script:LastAsk
foreach ($n in 'Write new MBR (bootrec /fixmbr)', 'Write boot sector (bootrec /fixboot)') {
    $script:LastAsk = ''; $a = @(& ($Tools | Where-Object Name -eq $n).Argv @{ Win = 'C:' })
    Check "$n on UEFI: warns, No cancels" ($a.Count -eq 0 -and $script:LastAsk -match 'UEFI') }
# real tool runs through the real Recovery button handler
$runTool = Get-Handler '$btnTool'
$cmbTool = [pscustomobject]@{ SelectedItem = $null }
function Start-Process { param($FilePath, $ArgumentList) $script:Spawned = "$FilePath $ArgumentList" }   # window tools: capture, don't open
$script:AskAnswer = $true
$cmbTool.SelectedItem = $Tools | Where-Object Name -eq 'Scan for Windows installs (bootrec /scanos)'
$script:LastMsg = ''; & $runTool; Check "bootrec /scanos on a system without bootrec -> 'not available' message" ($script:LastMsg -match 'not available') $script:LastMsg
$cmbTool.SelectedItem = $Tools | Where-Object Name -eq 'Check disk, read-only scan (chkdsk /scan)'
$script:Spawned = ''; & $runTool; Check "chkdsk /scan button builds 'chkdsk.exe C: /scan' in its own window" ($script:Spawned -match 'chkdsk\.exe C: /scan & pause') $script:Spawned
$cmbTool.SelectedItem = $Tools | Where-Object Name -eq 'Drivers: list third-party drivers'
$script:Spawned = ''; & $runTool; Check "driver list button builds 'dism.exe /online /get-drivers'" ($script:Spawned -match 'dism\.exe /online /get-drivers') $script:Spawned
Remove-Item Function:\Start-Process
$o = (& chkdsk.exe C: /scan 2>&1 | Out-String); Check "chkdsk C: /scan really runs (read-only)" ($LASTEXITCODE -in 0, 1) ("exit $LASTEXITCODE; " + (($o -split "`r?`n" | Where-Object { $_ -match 'found no problems|errors|problems' } | Select-Object -First 1)))
$o = (& dism.exe /online /get-drivers 2>&1 | Out-String); Check "dism /online /get-drivers really runs (read-only)" ($LASTEXITCODE -eq 0) ("{0} third-party drivers" -f ([regex]::Matches($o, 'oem\d+\.inf')).Count)
# bcdboot for real (BCD exported at the start), via the button handler
$espFiles0 = (Get-ChildItem "${L}:\EFI\Microsoft\Boot\bootmgfw.efi").LastWriteTime
$cmbTool.SelectedItem = $bcdbootTool; $script:Target = [pscustomobject]@{ Drive = 'C:'; Text = 'C:\Windows (test)'; Running = $true }
$cmbEsp.SelectedItem = [pscustomobject]@{ Drive = "${L}:"; FS = 'FAT32' }
$script:LogLines.Clear(); & $runTool
$bcdbootOut = ($script:LogLines -join ' | ')
Check "bcdboot C:\Windows /s ${L}: /f UEFI succeeds" ($bcdbootOut -match 'successfully') $bcdbootOut
$enumAfterBoot = (& bcdedit.exe /enum all /v | Out-String); $enumAfterBoot | Set-Content (Join-Path $OutDir 'bcd-enum-after-bcdboot.txt')
W ("  ESP bootmgfw.efi time before/after: {0} / {1}" -f $espFiles0, (Get-ChildItem "${L}:\EFI\Microsoft\Boot\bootmgfw.efi").LastWriteTime)
Unmount-Letter $L

# =====================================================================================================
W "`r`n===== 7e Unattend (deploy goes to a SUBST drive, never the real C:\Windows\Panther)"
$txtUser = [pscustomobject]@{ Text = 'Tech User' }; $txtPC = [pscustomobject]@{ Text = 'LAB-PC-01' }; $txtLoc = [pscustomobject]@{ Text = 'en-US' }
$txtPass = [pscustomobject]@{ Text = 'P@ss w<o>rd&1' }
foreach ($c in 'chkSkip', 'chkUser', 'chkPC', 'chkRegion', 'chkLogon', 'chkNoExp') { Set-Variable $c ([pscustomobject]@{ Checked = $true }) }
$cmbTz = [pscustomobject]@{ SelectedItem = 'Pacific Standard Time' }; $cmbGroup = [pscustomobject]@{ SelectedItem = 'Administrators' }
$x = Build-Unattend; $doc = $null; try { $doc = [xml]$x } catch {}
Check "Build-Unattend with every option -> well-formed XML" ([bool]$doc)
if ($doc) {
    $ns = New-Object Xml.XmlNamespaceManager $doc.NameTable; $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    Check "passes: specialize + oobeSystem" ((@($doc.SelectNodes('//u:settings', $ns) | ForEach-Object { $_.pass }) -join ',') -eq 'specialize,oobeSystem')
    Check "components target amd64 with the Microsoft public key token" (@($doc.SelectNodes('//u:component', $ns) | Where-Object { $_.processorArchitecture -ne 'amd64' -or $_.publicKeyToken -ne '31bf3856ad364e35' }).Count -eq 0)
    Check "ComputerName / TimeZone / UILanguage present" ($doc.SelectSingleNode('//u:ComputerName', $ns).InnerText -eq 'LAB-PC-01' -and $doc.SelectSingleNode('//u:TimeZone', $ns).InnerText -eq 'Pacific Standard Time' -and $doc.SelectSingleNode('//u:UILanguage', $ns).InnerText -eq 'en-US')
    $pv = $doc.SelectSingleNode('//u:LocalAccount/u:Password/u:Value', $ns).InnerText
    Check "local account password decodes to the typed password" ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($pv)) -eq 'P@ss w<o>rd&1Password')
}
$sub = Join-Path $OutDir 'subst-root'; New-Item -ItemType Directory -Force "$sub\Windows\Panther\Unattend" | Out-Null
$SL = Free-Letter; & subst.exe "${SL}:" $sub
$script:Target = [pscustomobject]@{ Drive = "${SL}:"; Text = "${SL}:\Windows (subst test)"; Running = $false }
$deploy = Get-Handler '$btnUDeploy'
& $deploy; $dest = "${SL}:\Windows\Panther\Unattend\unattend.xml"
Check "Deploy writes ${SL}:\Windows\Panther\Unattend\unattend.xml (UTF-8, no BOM)" ((Test-Path $dest) -and ([IO.File]::ReadAllBytes($dest)[0] -eq 0x3C))
Start-Sleep 1; & $deploy
Check "Deploy again backs up the existing file first (.bak_<time>)" (@(Get-ChildItem "${SL}:\Windows\Panther\Unattend" -Filter 'unattend.xml.bak_*').Count -eq 1)
& subst.exe "${SL}:" /d
Check "real C:\Windows\Panther\Unattend\unattend.xml untouched (absent)" (-not (Test-Path 'C:\Windows\Panther\Unattend\unattend.xml'))

# =====================================================================================================
W "`r`n===== 7g Sysprep pre-flight only (sysprep.exe is NOT started)"
foreach ($mode in 'A', 'B1', 'B2') {
    $pf = @(Get-Preflight $mode)
    W ("  mode {0}: {1}" -f $mode, (($pf | ForEach-Object { "$($_.Level)" }) -join ' '))
    foreach ($i in $pf | Where-Object Level -ne 'OK') { W ("      {0}: {1}" -f $i.Level, $i.Text) }
}
$pfA = @(Get-Preflight 'A')
Check "pre-flight A reports BitLocker state from WMI (OK or WARN, never silently skipped)" (@($pfA | Where-Object Text -match 'BitLocker').Count -eq 1)
Check "sysprep.exe was not started" (-not (Get-Process sysprep -ErrorAction SilentlyContinue))

# =====================================================================================================
W "`r`n===== BCD final check"
$enumEnd = (& bcdedit.exe /enum all /v | Out-String); $enumEnd | Set-Content (Join-Path $OutDir 'bcd-enum-end.txt')
$norm = { param($s) ($s -split "`r?`n" | Where-Object { $_ -notmatch '^\s*(resumeobject|custom:)' }) -join "`n" }
$same = (& $norm $enumBase) -eq (& $norm $enumEnd)
if (-not $same) {
    Compare-Object ($enumBase -split "`r?`n") ($enumEnd -split "`r?`n") | ForEach-Object { W ("    {0} {1}" -f $_.SideIndicator, $_.InputObject) }
}
Check "BCD after all tests identical to the start (before any re-import)" $same
if (-not $same) { $r = & bcdedit.exe /import $bcdBase 2>&1 | Out-String; W "  RE-IMPORTED the baseline BCD: $($r.Trim())"; Check "BCD identical after re-import" ((& $norm ((& bcdedit.exe /enum all /v) | Out-String)) -eq (& $norm $enumBase)) }
Check "no extra drive letters at the end" ((@([IO.DriveInfo]::GetDrives().Name) -join '') -eq 'C:\D:\') (@([IO.DriveInfo]::GetDrives().Name) -join ' ')
W ("`r`nTOTAL: {0} checks, {1} failed.   DONE {2}" -f $script:Checks, $script:Fails, (Get-Date))
