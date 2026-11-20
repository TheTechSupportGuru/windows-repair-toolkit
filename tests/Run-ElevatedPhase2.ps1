# Run-ElevatedPhase2.ps1 - Phase 2 checks that need admin. Start it ONCE elevated (one UAC prompt).
# Everything is read-only for the system: outputs go to %TEMP%\suite-phase2\elevated. Tools run from a TEMP copy so
# no data folders are created inside "Edited scripts". Each part writes its own section to summary.txt.
param([string]$OutDir = (Join-Path $env:TEMP 'suite-phase2\elevated'))
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
Set-Content -LiteralPath $sum -Value ("Phase 2 elevated run {0}  admin={1}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) -Encoding UTF8
. (Join-Path $PSScriptRoot 'Harness.ps1')
$verDir = $global:EditedVersions[0].FullName
W "Testing version folder: $verDir"

# ---- R1: WinFixKit status checks as admin ---------------------------------------------------------
W "`r`n===== R1 status checks (admin)"
W ((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-StatusChecks.ps1') -OutDir $OutDir) | Out-String)

# ---- R2: WinSuperTool log collectors on the live system --------------------------------------------
W "===== R2 Collect Logs (WinSuperTool collectors, live C:)"
& {
    $ST = 'WinSuperTool.ps1'; $NL = "`r`n"; $IsWinPE = $false
    $script:ColCount = 0; $script:ColFail = 0
    $sayLog = Join-Path $OutDir 'collect-say.txt'; Set-Content $sayLog '' -Encoding UTF8
    function Say([string]$m) { Add-Content -LiteralPath $sayLog -Value $m -Encoding UTF8 }
    . ([scriptblock]::Create((Get-FnText $ST 'Copy-One', 'Copy-Safe', 'Export-Evt', 'Get-InteractiveUser')))
    . ([scriptblock]::Create((Get-AssignText $ST 'EvtChannels')))
    . ([scriptblock]::Create((Get-AssignText $ST 'Collectors')))
    $root = Join-Path $OutDir 'collected'; Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    $prof = (Get-InteractiveUser).Profile
    foreach ($k in 'WU', 'DISM', 'EVT', 'CRASH', 'SETUP', 'INFO') {     # skipped: BIG (GBs), EVTALL (huge), SEC (sensitive)
        $c0 = $script:ColCount; $f0 = $script:ColFail; $sw = [Diagnostics.Stopwatch]::StartNew()
        Say "### $k"
        try { & $Collectors[$k].Run 'C:' $true $root $prof } catch { Say "UNCAUGHT in ${k}: $($_.Exception.Message)" }
        W ("  {0,-6} copied {1,4}  failed {2,3}  {3,6:N1}s" -f $k, ($script:ColCount - $c0), ($script:ColFail - $f0), $sw.Elapsed.TotalSeconds)
    }
    $files = @(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue)
    W ("  TOTAL files on disk {0}, {1:N1} MB; tool counted {2} copied / {3} failed" -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB), $script:ColCount, $script:ColFail)
    W "  FAILED / UNCAUGHT lines:"; Get-Content $sayLog | Where-Object { $_ -match 'FAILED|UNCAUGHT' } | Select-Object -First 15 | ForEach-Object { W "    $_" }
}

# ---- L1-L3: launchers from an elevated context (direct-start path, no UAC) -------------------------
W "`r`n===== L1-L3 launchers (elevated -> direct start)"
$lt = Join-Path $OutDir 'launch'; Remove-Item $lt -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $lt | Out-Null
$marker = Join-Path $lt 'markers'; New-Item -ItemType Directory $marker | Out-Null
$probe = "Set-Content -LiteralPath (Join-Path '$marker' ([guid]::NewGuid().ToString('N') + '.txt')) -Value `$PSCommandPath -Encoding UTF8"
$names = @('plain', 'with space', 'a&b', "it's", '100%', 'x^y', '(paren)', 'semi;colon', '!bang!')
$bats = @{ 'WinSuperTool.bat' = (Join-Path $verDir 'WinSuperTool.bat'); 'Run-PS-As-Admin.bat' = (Join-Path $global:SuiteDir 'PS suite V1.1\Run-PS-As-Admin.bat') }
foreach ($bn in $bats.Keys) {
    foreach ($n in $names) {
        Get-ChildItem $marker | Remove-Item -Force
        $d = Join-Path $lt $n; New-Item -ItemType Directory -Force -Path $d | Out-Null
        $ps = Join-Path $d 'probe test.ps1'; Set-Content -LiteralPath $ps -Value $probe -Encoding UTF8
        $p = Start-Process cmd.exe -ArgumentList '/c', "`"`"$($bats[$bn])`" `"$ps`"`"" -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(20000)) { Stop-Process -Id $p.Id -Force; $state = 'HUNG (bat kept prompting)' } else { $state = "exit $($p.ExitCode)" }
        Start-Sleep 4
        $m = @(Get-ChildItem $marker -File)
        $ok = $m.Count -eq 1 -and ((Get-Content $m[0].FullName -Raw).Trim() -eq $ps)
        W ("  {0,-20} folder {1,-14} -> {2,-26} ran right script: {3}" -f $bn, "'$n'", $state, $ok)
    }
}
# not-a-.ps1 then a good path piped in: should reject, re-prompt, then run the good one
Get-ChildItem $marker | Remove-Item -Force
$good = Join-Path $lt 'plain\probe test.ps1'; $txt = Join-Path $lt 'notes.txt'; 'x' | Set-Content $txt
$p = Start-Process cmd.exe -ArgumentList '/c', "echo $good| `"$($bats['WinSuperTool.bat'])`" `"$txt`"" -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $lt 'notps1.out')
if (-not $p.WaitForExit(20000)) { Stop-Process -Id $p.Id -Force; $st = 'HUNG' } else { $st = "exit $($p.ExitCode)" }
Start-Sleep 4
W ("  WinSuperTool.bat: .txt dropped, then valid path typed -> {0}; message shown: {1}; good script ran: {2}" -f $st, [bool](Select-String -Path (Join-Path $lt 'notps1.out') -Pattern 'not a .ps1' -Quiet), (@(Get-ChildItem $marker).Count -eq 1))

# ---- GUI smoke tests as admin (from a TEMP copy) --------------------------------------------------
W "`r`n===== GUI smoke tests (admin, 20 s each, closed via CloseMainWindow)"
$gt = Join-Path $OutDir 'gui'; Remove-Item $gt -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $gt | Out-Null
Copy-Item (Join-Path $verDir '*') $gt -Recurse
foreach ($s in 'WinSuperTool.ps1', 'WinRepairTool-startup.ps1', 'WinFixKit.ps1') {
    $tr = Join-Path $gt ($s + '.transcript.txt')
    $extra = if ($s -eq 'WinFixKit.ps1') { " -DataRoot '$gt\wfk-data'" } else { '' }
    $cmd = "Start-Transcript -Path '$tr' | Out-Null; & '$gt\$s'$extra; Stop-Transcript | Out-Null"
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', $cmd -PassThru
    Start-Sleep 20
    $p.Refresh(); $alive = -not $p.HasExited; $title = $p.MainWindowTitle
    $how = 'already exited'
    if ($alive) { [void]$p.CloseMainWindow(); if ($p.WaitForExit(8000)) { $how = "closed, exit $($p.ExitCode)" } else { Stop-Process -Id $p.Id -Force; $how = 'FORCE-killed (did not close)' } }
    $errs = @(Select-String -Path $tr -Pattern 'FullyQualifiedErrorId' -ErrorAction SilentlyContinue)
    W ("  {0,-26} alive after 20s: {1,-5} title: '{2}'  {3}  errors in transcript: {4}" -f $s, $alive, $title, $how, $errs.Count)
    Select-String -Path $tr -Pattern '^At .*:(\d+) char' -ErrorAction SilentlyContinue | Group-Object Line | ForEach-Object { W ("      {0}x  {1}" -f $_.Count, $_.Name.Trim()) }
}
W "`r`nmount memory files created by the smoke tests:"; Get-ChildItem $gt -Filter '*.json' -Recurse | ForEach-Object { W "  $($_.Name): $(Get-Content $_.FullName -Raw)" }
W "`r`nDONE $(Get-Date)"
