# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-PETest.ps1 - the toolkit in WinPE (for example Hiren's BootCD PE), working on a Windows that is NOT running:
#   0 the PE: is it WinPE, PowerShell / .NET / WinForms, the Windows tools the toolkit calls, firmware, disks
#   1 the Windows installations the tools find (WinSuperTool and WinRepairTool)
#   2 boot configuration of each one, READ-ONLY (bcdedit /enum, clones, boot menu timeout, partition letters)
#   3 real READ-ONLY offline scans read back by the summaries: DISM /image checkhealth + scanhealth,
#     sfc /verifyonly /offwindir, chkdsk /scan
#   4 every GUI tool started for 20 s: does it open, does it report errors
#   5 window sizes (resize audit, short)
#   6 unit tests, if Pester is in this PE
# Changes nothing (no repair, no boot change; the answer to every question in the tools is No) apart from writing the
# results. Results: <first Windows drive>\WRT-PE-Results-<date> (so they are there after booting that Windows) and a
# copy in X:\WRT-PE-Results. private\ = unmasked, share\ + WRT-PE-share.zip = masked: send that one.
param([string]$OutDir = '', [switch]$NoGui)
$ErrorActionPreference = 'Continue'
$Repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Harness.ps1')
$IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
$NL = "`r`n"
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
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
if (-not $OutDir) { $OutDir = $(if ($Win) { Join-Path "$Win\" "WRT-PE-Results-$stamp" } else { "X:\WRT-PE-Results-$stamp" }) }
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
        Check 'bcdedit /enum all reads the store' { $o = (& bcdedit.exe /enum all 2>&1 | Out-String); ($LASTEXITCODE -eq 0), ("{0} lines" -f ($o -split "`n").Count) }
    }
    # ---------- 3 offline scans ----------
    Step "3 Offline scans of $Win read back by the summaries (read-only, 10-30 minutes)"
    if (-not $IsWinPE) { W "  skipped: this is not WinPE, so $Win is the RUNNING Windows (offline scans need it not running)"; $cap = '' } else {
    $cap = & (Join-Path $PSScriptRoot 'Run-TaskCapture.ps1') -Script (Join-Path $Repo 'beta\WinSuperTool.ps1') -OutDir (Join-Path $Priv 'capture') -Windows $Win 2>&1 | Out-String
    Save-Both 'scans.txt' $cap
    foreach ($l in ($cap -split "`r?`n" | Where-Object { $_ -match '^=== |FIND:|QUOTE:' })) { W "  $l" }
    }
} else { Step '2 + 3 skipped: no Windows installation to work on' }

# ---------- 4 GUI tools start ----------
if (-not $NoGui -and $wf -eq 'loads') {
    Step '4 Every GUI tool started for 20 s (do not use the mouse)'
    $gui = @(Get-ChildItem (Join-Path $Repo 'tools'), (Join-Path $Repo 'beta') -Filter *.ps1 | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'Windows\.Forms\.Form' })
    foreach ($g in $gui) {
        $name = "$($g.Directory.Name)\$($g.Name)"; $tr = Join-Path $Priv ("start-" + ($name -replace '\\', '-') + '.txt')
        $extra = if ($g.Name -eq 'WinFixKit.ps1') { " -DataRoot '$Priv\wfk-data'" } else { '' }
        $p = Start-Process powershell.exe -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', "Start-Transcript -Path '$tr' | Out-Null; & '$($g.FullName)'$extra; Stop-Transcript | Out-Null"
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
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-ResizeAudit.ps1') -OutDir (Join-Path $Priv 'resize') -Parallel -Sizes 'min,75%,max' *> $null
    $f = Join-Path $Priv 'resize\summary.txt'
    if (Test-Path $f) { $t = [IO.File]::ReadAllText($f); Save-Both 'resize-summary.txt' $t; W ("  " + (($t -split "`r?`n" | Select-Object -Skip 3 | Where-Object { $_ -and $_ -notmatch 'Sizes actually' } | Select-Object -First 8) -join ' | ')) } else { W '  no result' }
} else { Step '4 + 5 skipped: WinForms does not load in this PE (or -NoGui)' }

# ---------- 6 unit tests ----------
if (Get-Module Pester -ListAvailable) {
    Step '6 Unit tests'
    foreach ($s in 'Beta', 'Toolkit', 'Suite') {
        $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$s.Tests.ps1") 2>&1 | Out-String
        Save-Both "unit-$s.txt" $o
        $fail = @([regex]::Matches($o, '(?m)^\s*\[-\].*$') | ForEach-Object { $_.Value.Trim() })
        W ("  {0,-8} passed {1}, failed {2}" -f $s, ([regex]::Matches($o, '\[\+\]')).Count, $fail.Count); foreach ($x in $fail) { W "     $(Protect-Text $x)" }
    }
} else { Step '6 skipped: Pester is not in this PE' }

# ---------- save ----------
Step 'Done'
$all = $log -join "`r`n"
[IO.File]::WriteAllText((Join-Path $Priv 'summary.txt'), $all); [IO.File]::WriteAllText((Join-Path $Share 'summary.txt'), (Protect-Text $all))
$zip = Join-Path $OutDir 'WRT-PE-share.zip'
try { Compress-Archive -Path (Join-Path $Share '*') -DestinationPath $zip -Force -ErrorAction Stop } catch { W "Could not zip (copy the share folder instead): $($_.Exception.Message)" }
if ($OutDir -notlike 'X:*') { try { Copy-Item $OutDir "X:\WRT-PE-Results-$stamp" -Recurse -Force -ErrorAction Stop } catch {} }
W "Results: $OutDir  (send WRT-PE-share.zip; private\ stays with you)"
if ($Win) { W "After booting $Win normally, the folder is at $($OutDir -replace '^[A-Z]:', 'C:') (the drive letter may change)." }
