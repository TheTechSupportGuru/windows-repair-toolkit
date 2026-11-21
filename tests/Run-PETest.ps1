# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-PETest.ps1 - the toolkit in WinPE (for example Hiren's BootCD PE), working on a Windows that is NOT running:
#   0 the PE: is it WinPE, PowerShell / .NET / WinForms, the Windows tools the toolkit calls, firmware, disks
#   M mounting, NON-DESTRUCTIVE (drive letters only, with the tools' own Mount functions): when the Windows volume has no
#     letter in the PE it is mounted for the tests; a partition without a letter (System Reserved / EFI / Recovery) is
#     mounted, read, and unmounted with diskpart and with the Storage cmdlets; the MSR and the system drive must be
#     refused. Every letter the test added is removed at the end, also when something fails.
#   1 the Windows installations the tools find (WinSuperTool and WinRepairTool)
#   2 boot configuration of each one, READ-ONLY (bcdedit /enum, clones, boot menu timeout, partition letters)
#   3 real READ-ONLY offline scans read back by the summaries: DISM /image checkhealth + scanhealth,
#     sfc /verifyonly /offwindir, chkdsk /scan
#   A Automation on the offline Windows (1.9: the queue works on the Target Windows in WinPE), through the real tab:
#     checks; options (stop on fail, popups and HTML off); a queue with tasks that need the running Windows must be
#     refused; repair only if needed (DISM, SFC, chkdsk /f); full repairs (sfc /scannow, DISM restore health, component
#     cleanup). The repair queues CHANGE the offline Windows when they find something - take a VM snapshot first, or
#     use -NoRepairs.
#   4 every GUI tool started for 20 s: does it open, does it report errors
#   5 window sizes (resize audit, short)
#   6 unit tests, if Pester is in this PE
# Changes nothing (no repair, no boot change, no format; letters it adds are removed; every question is answered No) apart from writing the
# results. Results: <first Windows drive>\WRT-PE-Results-<date> (so they are there after booting that Windows) and a
# copy in X:\WRT-PE-Results. private\ = unmasked, share\ + WRT-PE-share.zip = masked: send that one.
param([string]$OutDir = '', [switch]$NoGui, [switch]$NoRepairs)
$ErrorActionPreference = 'Continue'
$Repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Harness.ps1')
$IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
$NL = "`r`n"
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
# the PowerShell that runs this script (Windows PowerShell 5.1, or PowerShell 7 = pwsh.exe, as in Hiren's PE 10)
$PsExe = (Get-Process -Id $PID).Path
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# masking: the same functions as the field test
$ft = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Run-FieldTest.ps1'), [ref]$null, [ref]$null)
foreach ($n in 'Protect-Text', 'Save-Both') { . ([scriptblock]::Create($ft.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true).Extent.Text)) }
$PcName = $env:COMPUTERNAME; $UserName = $env:USERNAME

$log = New-Object Collections.ArrayList
function W([string]$m) { [void]$log.Add($m); Write-Host $m }
function Step([string]$m) { W ''; W "===== $m  ($(Get-Date -Format 'HH:mm:ss'))" }
function Check($name, [scriptblock]$t) {
    try { $r = & $t; if ($r -is [bool]) { $ok = $r; $info = '' } else { $ok = [bool]$r[0]; $info = [string]$r[1] } } catch { $ok = $false; $info = "EXCEPTION $($_.Exception.Message)" }
    W ("  [{0}] {1}  {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $info)
}

# ---------- 0 the PE ----------
Step '0 This PE'
W ("WinPE        : {0}   admin: {1}   firmware: {2}" -f $IsWinPE, $isAdmin, $(if ($env:firmware_type) { $env:firmware_type } else { 'unknown' }))
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
W ("PE base      : {0} build {1}.{2}  ({3})" -f $cv.ProductName, $cv.CurrentBuild, $cv.UBR, $env:PROCESSOR_ARCHITECTURE)
$hb = @(Get-ChildItem 'X:\' -Filter '*HBCD*' -ErrorAction SilentlyContinue | ForEach-Object Name) + @(Get-ChildItem 'X:\Program Files' -Directory -ErrorAction SilentlyContinue | Where-Object Name -match 'HBCD|Hiren' | ForEach-Object Name)
W ("Hiren's      : {0}" -f $(if ($hb) { $hb -join ', ' } else { 'no Hiren''s marker found on X:' }))
$net = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
W ("PowerShell   : {0}   .NET release: {1}   Pester: {2}" -f $PSVersionTable.PSVersion, $(if ($net) { $net } else { 'NOT FOUND' }), ((Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version))
$wf = try { Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop; 'loads' } catch { "DOES NOT LOAD: $($_.Exception.Message)" }
W "WinForms     : $wf"
if ($wf -eq 'loads') { W ("Screen       : {0}  ({1} monitor(s))" -f [Windows.Forms.Screen]::PrimaryScreen.Bounds.Size, [Windows.Forms.Screen]::AllScreens.Count) }
$exe = foreach ($e in 'bcdedit', 'bcdboot', 'bootrec', 'dism', 'sfc', 'chkdsk', 'diskpart', 'reg', 'wevtutil', 'mountvol', 'pnputil', 'robocopy', 'conhost') { '{0}{1}' -f $e, $(if (Get-Command "$e.exe" -ErrorAction SilentlyContinue) { '' } else { ' (MISSING)' }) }
W ("Tools        : {0}" -f ($exe -join ', '))
W ("Storage cmds : Get-Partition {0}, Get-Volume {1}, Get-CimInstance {2}" -f [bool](Get-Command Get-Partition -ErrorAction SilentlyContinue), [bool](Get-Command Get-Volume -ErrorAction SilentlyContinue), [bool](Get-Command Get-CimInstance -ErrorAction SilentlyContinue))
$vols = @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | ForEach-Object { '{0} {1} {2:N0} GB {3}' -f $_.DeviceID, $_.FileSystem, ($_.Size / 1GB), $_.VolumeName })
W ("Drives       : {0}" -f ($vols -join '; '))


# ---------- M mounting (drive letters only) ----------
Step 'M Mounting with the tools'' Mount functions (drive letters only - nothing is formatted or changed)'
function Log($m) { $script:MountLog += "$m" }
$script:MountLog = @(); $script:Mounts = New-Object Collections.ArrayList; $script:Added = @()
$rbStor = [pscustomobject]@{ Checked = $false }
. ([scriptblock]::Create((Get-AssignText 'WinSuperTool.ps1' 'DpAllow')))
. ([scriptblock]::Create((Get-FnText 'WinSuperTool.ps1' 'Invoke-Diskpart', 'Get-DiskpartRows', 'Fmt-Size', 'Sync-StorageCache', 'Test-IsMsr', 'Test-LetterUsed', 'Get-LetterPartition', 'Get-DpPartLetter', 'Mount-Part', 'Unmount-Letter', 'Dismount-One', 'Get-DiskList', 'Get-PartList')))
$hasStor = [bool](Get-Command Get-Partition -ErrorAction SilentlyContinue)
function Get-FreeLetter { foreach ($c in [char[]]'TSRQPONMLKJ') { if (-not (Test-LetterUsed $c)) { return [string]$c } }; return '' }
# every partition: disk, number, letter ('' = none, NOVOLUME = no file system: MSR / unformatted), size text
$parts = @()
foreach ($d in @(Get-DiskList)) { foreach ($pp in @(Get-PartList $d.Num)) { $parts += [pscustomobject]@{ Disk = $d.Num; Part = $pp.Num; Letter = (Get-DpPartLetter $d.Num $pp.Num); Text = $pp.Text } } }
W ("  disks and partitions (diskpart): " + (($parts | ForEach-Object { "disk $($_.Disk)/p$($_.Part) $(if ($_.Letter -eq 'NOVOLUME') { 'no file system' } elseif ($_.Letter) { "$($_.Letter):" } else { 'no letter' })" }) -join '; '))
$noLetter = @($parts | Where-Object { $_.Letter -eq '' })
# the Windows volume has no letter in this PE: mount it for the tests (and remove the letter at the end)
$winFound = $false; foreach ($dr in [IO.DriveInfo]::GetDrives()) { $l = $dr.Name.Substring(0, 2); if ($l -ne 'X:' -and [IO.File]::Exists("$l\Windows\System32\ntoskrnl.exe")) { $winFound = $true } }
if (-not $winFound) {
    foreach ($c in $noLetter) {
        $L = Get-FreeLetter; if (-not $L) { break }
        if (Mount-Part $c.Disk $c.Part $L) {
            if ([IO.File]::Exists("${L}:\Windows\System32\ntoskrnl.exe")) { $script:Added += [pscustomobject]@{ Letter = $L; Disk = $c.Disk; Partition = $c.Part }; W "  the Windows volume had no letter: mounted disk $($c.Disk) partition $($c.Part) as ${L}: for the tests"; $c.Letter = $L; break }
            [void](Dismount-One ([pscustomobject]@{ Letter = $L; Disk = $c.Disk; Partition = $c.Part }))
        }
    }
}
$cand = @($parts | Where-Object { $_.Letter -eq '' } | Select-Object -First 1)
if (-not $cand.Count) { W '  no partition without a letter to test with (every partition already has one) - mount/unmount steps skipped' }
$engines = @('diskpart') + $(if ($hasStor) { 'Storage cmdlets' } else { @() })
foreach ($eng in $engines) {
    if (-not $cand.Count) { break }
    $rbStor.Checked = ($eng -ne 'diskpart'); $c = $cand[0]; $L = Get-FreeLetter
    Check "[$eng] mount disk $($c.Disk) partition $($c.Part) ($($c.Text -replace '^Partition \d+\s+-\s+', '')) as ${L}:" { $r = Mount-Part $c.Disk $c.Part $L; if ($r) { $script:Added += [pscustomobject]@{ Letter = $L; Disk = $c.Disk; Partition = $c.Part } }; [bool]$r, "letter there: $r" }
    if (Test-LetterUsed $L) {
        Check "[$eng] its files can be read" { $n = @(Get-ChildItem "${L}:\" -Force -ErrorAction Stop | ForEach-Object Name); ($n.Count -gt 0), ("top folder: " + (($n | Select-Object -First 8) -join ', ')) }
        Check "[$eng] unmount ${L}: with Dismount-One" { $m = [pscustomobject]@{ Letter = $L; Disk = $c.Disk; Partition = $c.Part }; [void]$script:Mounts.Add($m); $r = Dismount-One $m; if ($r) { $script:Added = @($script:Added | Where-Object { $_.Letter -ne $L }) }; ($r -and -not (Test-LetterUsed $L)), "letter gone: $(-not (Test-LetterUsed $L))" }
    }
}
$msr = @($parts | Where-Object { $_.Letter -eq 'NOVOLUME' } | Where-Object { Test-IsMsr $_.Disk $_.Part } | Select-Object -First 1)
if ($msr.Count) { Check "Mount-Part refuses the MSR (disk $($msr[0].Disk) partition $($msr[0].Part)) before touching it" { $L = Get-FreeLetter; try { [void](Mount-Part $msr[0].Disk $msr[0].Part $L); $false, 'NOT refused' } catch { (-not (Test-LetterUsed $L) -and $_.Exception.Message -match 'Microsoft Reserved'), $_.Exception.Message } } }
else { W '  no MSR on this PC (MBR disk / Legacy BIOS): the MSR refusal is covered by the unit tests' }
$sysL = $env:SystemDrive.Substring(0, 1)
Check "Dismount-One refuses the system drive ${sysL}:" { $r = Dismount-One ([pscustomobject]@{ Letter = $sysL; Disk = 0; Partition = 0 }); (-not $r -and (Test-LetterUsed $sysL)), 'refused' }
Check 'Dismount-One refuses an entry without a drive letter' { $r = Dismount-One ([pscustomobject]@{ Letter = ''; Disk = 0; Partition = 1 }); (-not $r), 'refused' }
# ---------- 1 Windows installations ----------
Step '1 Windows installations found by the tools'
$installs = @()
& {
    function Log($m) { }; function Msg($t, $c, $i) { }; function Ask { $false }
    . ([scriptblock]::Create((Get-FnText 'WinSuperTool.ps1' 'Get-WinInstalls')))
    $script:installs = @(Get-WinInstalls)
}
foreach ($w in $installs) { W ("  WinSuperTool : {0}" -f $w.Text) }
if (-not $installs.Count) { W '  WinSuperTool : NO Windows installation found' }
$target = @($installs | Where-Object { -not $_.Running -and $_.Drive -and $_.Drive -ne 'X:' } | Select-Object -First 1)
if (-not $target.Count) { $target = @($installs | Where-Object { $_.Drive -ne 'X:' } | Select-Object -First 1) }
$Win = if ($target.Count) { $target[0].Drive } else { '' }
W ("  Target for the offline tests: {0}" -f $(if ($Win) { $Win } else { 'none - steps 2 and 3 are skipped' }))

# where the results go: the target Windows (still there after booting it), else X:
if (-not $OutDir) { $OutDir = $(if ($Win) { Join-Path "$Win\" "WRT-PE-Results-$stamp" } else { "X:\WRT-PE-Results-$stamp" }) }   # (a letter the test added is removed at the end, but the files stay on that volume)
$Priv = Join-Path $OutDir 'private'; $Share = Join-Path $OutDir 'share'
New-Item -ItemType Directory -Force $Priv, $Share | Out-Null

# ---------- 2 boot configuration, read-only ----------
if ($Win) {
    Step "2 Boot configuration of $Win (read-only: every question is answered No)"
    & {
        function Log($m) { Add-Content -LiteralPath (Join-Path $Priv 'wrt-log.txt') -Value $m }
        function Msg($t, $c, $i) { Log "MSG: $t" }
        function Ask { $global:Asked = $args[0]; $false }
        $WRT = 'PS suite V1.1\WinRepairTool-startup.ps1'
        . ([scriptblock]::Create((Get-AssignText $WRT 'CloneMarkers')))
        . ([scriptblock]::Create((Get-FnText $WRT 'Get-WinInstalls', 'ConvertFrom-BcdText', 'Get-BcdAll', 'Resolve-BcdTarget', 'Get-Clones', 'Confirm-BootMenuShown', 'Get-DpPartLetter', 'Invoke-Diskpart', 'Get-FirmwareType', 'Get-BitLockerState')))
        . ([scriptblock]::Create((Get-AssignText $WRT 'DpAllow')))
        Check 'WinRepairTool finds the same installations' { $w2 = @(Get-WinInstalls); ($w2.Count -eq $installs.Count), (($w2 | ForEach-Object { $_.Drive }) -join ', ') }
        Check 'firmware type' { $f = Get-FirmwareType; [bool]$f, $f }
        $script:BcdT = $null
        Check "Resolve-BcdTarget $Win finds its boot entry" { $script:BcdT = Resolve-BcdTarget $Win; [bool]$script:BcdT.Id, ("Id=$($script:BcdT.Id)  store=$(if ($script:BcdT.Store) { $script:BcdT.Store } else { '(system store)' })") }
        if ($script:BcdT) {
            Check 'Get-Clones reads that store without error' { $c = @(Get-Clones $script:BcdT $Win); $true, "clones: $($c.Count)" }
            Check 'Confirm-BootMenuShown reads the boot menu timeout (no change)' { $global:Asked = $null; Confirm-BootMenuShown $script:BcdT; $true, "asked to change it: $([bool]$global:Asked)" }
        }
        Check "BitLocker state of $Win" { $b = Get-BitLockerState $Win; [bool]$b, $b }
        # in WinPE the default store is the PE's own: read the store that boots the offline Windows
        Check 'bcdedit /enum all reads that boot store' { $ba = @(); if ($script:BcdT -and $script:BcdT.Store) { $ba += '/store'; $ba += $script:BcdT.Store }; $o = (& bcdedit.exe @ba /enum all 2>&1 | Out-String); ($LASTEXITCODE -eq 0), ("{0} lines from {1}" -f ($o -split "`n").Count, $(if ($ba) { $ba[1] } else { 'the system store' })) }
    }
    # ---------- 3 offline scans ----------
    Step "3 Offline scans of $Win read back by the summaries (read-only, 10-30 minutes)"
    if (-not $IsWinPE) { W "  skipped: this is not WinPE, so $Win is the RUNNING Windows (offline scans need it not running)"; $cap = '' } else {
    $cap = & (Join-Path $PSScriptRoot 'Run-TaskCapture.ps1') -Script (Join-Path $Repo 'beta\WinSuperTool.ps1') -OutDir (Join-Path $Priv 'capture') -Windows $Win 2>&1 | Out-String
    Save-Both 'scans.txt' $cap
    foreach ($l in ($cap -split "`r?`n" | Where-Object { $_ -match '^=== |FIND:|QUOTE:' })) { W "  $l" }
    }
} else { Step '2 + 3 skipped: no Windows installation to work on' }

# ---------- A Automation on the offline Windows ----------
if ($Win -and $IsWinPE -and $wf -eq 'loads') {
    Step "A Automation on the offline Windows $Win (the real Automation tab; do not use the mouse)"
    $runs = @(
        @('A1-checks', @('-RealQueue', 'dism-check,dism-scan,sfc-verify,chkdsk-scan'), 'runs'),
        @('A2-options', @('-RealQueue', 'dism-check,chkdsk-scan', '-StopOnFail', '-NoPopups', '-NoHtml'), 'runs'),
        @('A3-refused', @('-RealQueue', 'dism-check,winupdate-check,defender'), 'refused')
    )
    if (-not $NoRepairs) {
        $runs += ,@('A4-repair-if-needed', @('-RealQueue', 'dism-scan-fix,sfc-verify-fix,chkdsk-fix'), 'runs')
        $runs += ,@('A5-full-repairs', @('-RealQueue', 'sfc-scannow,dism-restore,dism-cleanup'), 'runs')
    } else { W '  repair queues A4 + A5 skipped (-NoRepairs)' }
    foreach ($r in $runs) {
        $o = Join-Path $Priv "auto-$($r[0])"
        $a = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\Run-AutomationSmoke.ps1`"", '-Script', "`"$(Join-Path $Repo 'beta\WinSuperTool.ps1')`"", '-OutDir', "`"$o`"", '-Target', $Win) + $r[1]
        $t0 = Get-Date; $pr = Start-Process $PsExe -PassThru -ArgumentList $a
        if (-not $pr.WaitForExit(7200000)) { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue; W "  $($r[0]): TIMEOUT after 2 hours"; continue }
        $sumF = Join-Path $o 'automation-summary.txt'; $notF = Join-Path $o 'not-started.txt'
        $opt = (Get-Content (Join-Path $o 'options.txt') -ErrorAction SilentlyContinue) -join '; '
        if ($r[2] -eq 'refused') {
            $why = @(Get-Content (Join-Path $o 'msgs.txt') -ErrorAction SilentlyContinue | Where-Object { $_ -match ' - needs the running Windows' } | ForEach-Object { $_.Trim() })
            Check "$($r[0]): a queue with tasks that need the running Windows is refused" { ((Test-Path $notF) -and -not (Test-Path $sumF) -and $why.Count -eq 2), ($why -join ' | ') }
            continue
        }
        $s = @(Get-Content $sumF -ErrorAction SilentlyContinue)
        Check ("{0}: the queue ran on {1} ({2:N0} min)" -f $r[0], $Win, ((Get-Date) - $t0).TotalMinutes) { ($s.Count -gt 0 -and -not (Test-Path $notF)), (($s | Where-Object { $_ -match 'task\(s\) ran' }) -join '').Trim() }
        foreach ($l in ($s | Where-Object { $_ -match '^\s+\d+\.\s' })) { W ("      " + (Protect-Text $l.Trim())) }
        Check "$($r[0]): the summary names the offline Windows" { $w2 = ($s | Where-Object { $_ -match '^\s+Windows\s' }) -join ''; ($w2 -match [regex]::Escape($Win) -and $w2 -match 'offline'), $w2.Trim() }
        # the commands, from the tool's activity log ("AUTOMATION 1/4: <task>  (<command>)")
        $cmds = @(Get-Content (Join-Path $o 'WinSuperTool-Data\activity.log') -ErrorAction SilentlyContinue | Where-Object { $_ -match 'AUTOMATION \d+/\d+: .*\((.+)\)\s*$' } | ForEach-Object { $Matches[1] })
        Check "$($r[0]): every task used the offline form (no /online)" { (@($cmds | Where-Object { $_ -match '/online' }).Count -eq 0 -and $cmds.Count -gt 0), ($cmds -join ' | ') }
        $html = @(Get-ChildItem (Join-Path $o 'WinSuperTool-Data\Task-Results') -Filter '*Automation-report.html' -ErrorAction SilentlyContinue)
        if ($opt -match 'html False') { Check "$($r[0]): no HTML report (option off)" { ($html.Count -eq 0), "$($html.Count) report(s)" } }
        else { Check "$($r[0]): HTML report written and names the offline Windows" { ($html.Count -eq 1 -and ([IO.File]::ReadAllText($html[0].FullName) -match 'offline, from WinPE')), $(if ($html) { $html[0].Name } else { 'none' }) } }
        $pops = @(Get-Content (Join-Path $o 'bounds.txt') -ErrorAction SilentlyContinue | Where-Object { $_ -match '^Task summary' }).Count
        if ($opt -match 'popups False') { Check "$($r[0]): no per-task popups (option off)" { ($pops -eq 0), "$pops popup(s)" } } else { W "      per-task popups: $pops" }
        Save-Both "auto-$($r[0]).txt" (($s -join "`r`n") + "`r`n`r`noptions: $opt`r`ncommands: " + ($cmds -join ' | '))
    }
} elseif ($Win) { Step 'A Automation skipped: needs WinPE and WinForms' }

# ---------- 4 GUI tools start ----------
if (-not $NoGui -and $wf -eq 'loads') {
    Step '4 Every GUI tool started for 20 s (do not use the mouse)'
    $gui = @(Get-ChildItem (Join-Path $Repo 'tools'), (Join-Path $Repo 'beta') -Filter *.ps1 | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'Windows\.Forms\.Form' })
    foreach ($g in $gui) {
        $name = "$($g.Directory.Name)\$($g.Name)"; $tr = Join-Path $Priv ("start-" + ($name -replace '\\', '-') + '.txt')
        $extra = if ($g.Name -eq 'WinFixKit.ps1') { " -DataRoot '$Priv\wfk-data'" } else { '' }
        $p = Start-Process $PsExe -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', "Start-Transcript -Path '$tr' | Out-Null; & '$($g.FullName)'$extra; Stop-Transcript | Out-Null"
        Start-Sleep -Seconds 20
        $p.Refresh(); $alive = -not $p.HasExited; $title = $p.MainWindowTitle
        if ($alive) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(8000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
        Start-Sleep -Milliseconds 500
        $errs = @(Select-String -Path $tr -Pattern 'FullyQualifiedErrorId' -ErrorAction SilentlyContinue)
        W ("  {0,-34} open after 20 s: {1,-5} window: '{2}'  errors: {3}" -f $name, $alive, $title, $errs.Count)
        foreach ($e in ($errs | Select-Object -First 2)) { W ("      " + (Protect-Text $e.Line.Trim())) }
    }
    # ---------- 5 window sizes ----------
    Step '5 Window sizes (short resize audit)'
    & $PsExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-ResizeAudit.ps1') -OutDir (Join-Path $Priv 'resize') -Parallel -Sizes 'min,75%,max' *> $null
    $f = Join-Path $Priv 'resize\summary.txt'
    if (Test-Path $f) { $t = [IO.File]::ReadAllText($f); Save-Both 'resize-summary.txt' $t; W ("  " + (($t -split "`r?`n" | Select-Object -Skip 3 | Where-Object { $_ -and $_ -notmatch 'Sizes actually' } | Select-Object -First 8) -join ' | ')) } else { W '  no result' }
} else { Step '4 + 5 skipped: WinForms does not load in this PE (or -NoGui)' }

# ---------- 6 unit tests ----------
if (Get-Module Pester -ListAvailable) {
    Step '6 Unit tests'
    foreach ($s in 'Beta', 'Toolkit', 'Suite') {
        $o = & $PsExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$s.Tests.ps1") 2>&1 | Out-String
        Save-Both "unit-$s.txt" $o
        $fail = @([regex]::Matches($o, '(?m)^\s*\[-\].*$') | ForEach-Object { $_.Value.Trim() })
        W ("  {0,-8} passed {1}, failed {2}" -f $s, ([regex]::Matches($o, '\[\+\]')).Count, $fail.Count); foreach ($x in $fail) { W "     $(Protect-Text $x)" }
    }
} else { Step '6 skipped: Pester is not in this PE' }

# ---------- save ----------
Step 'Done'
[IO.File]::WriteAllText((Join-Path $Priv 'mount-log.txt'), ($script:MountLog -join "`r`n"))
if (@($script:Added).Count) { W ("  letters added by the test, removed after saving: " + ((@($script:Added) | ForEach-Object { "$($_.Letter):" }) -join ', ')) }
$all = $log -join "`r`n"
[IO.File]::WriteAllText((Join-Path $Priv 'summary.txt'), $all); [IO.File]::WriteAllText((Join-Path $Share 'summary.txt'), (Protect-Text $all))
$zip = Join-Path $OutDir 'WRT-PE-share.zip'
try { Compress-Archive -Path (Join-Path $Share '*') -DestinationPath $zip -Force -ErrorAction Stop } catch { W "Could not zip (copy the share folder instead): $($_.Exception.Message)" }
if ($OutDir -notlike 'X:*') { try { Copy-Item $OutDir "X:\WRT-PE-Results-$stamp" -Recurse -Force -ErrorAction Stop } catch {} }
W "Results: $OutDir  (send WRT-PE-share.zip; private\ stays with you)"
if ($Win) { W "After booting $Win normally, the folder is at $($OutDir -replace '^[A-Z]:', 'C:') (the drive letter may change)." }

# ---------- clean up: remove every letter this test added ----------
foreach ($a in @($script:Added)) {
    if (Test-LetterUsed $a.Letter) { $rbStor.Checked = $false; [void]$script:Mounts.Add($a); [void](Dismount-One $a); if (Test-LetterUsed $a.Letter) { & mountvol.exe ('{0}:' -f $a.Letter) /D 2>$null | Out-Null } }
    Write-Host ("  letter {0}: added by the test - removed: {1}" -f $a.Letter, (-not (Test-LetterUsed $a.Letter)))
}
