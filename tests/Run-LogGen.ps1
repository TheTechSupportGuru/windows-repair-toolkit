# Run-LogGen.ps1 - full run of the log-generation code (newest Edited version), as admin:
#   A) WinSuperTool collectors, LIVE, all 9 categories (BIG skipped if > 2 GB)
#   B) WinSuperTool collectors in OFFLINE mode against C: (the WinPE code path: evtx copied as files, DISM /image)
#   C) standalone Collect-Logs.ps1 collectors, all categories
#   D) the AI log readers on the collected files: WinSuperTool Read-LogForAi vs ClaudeLogAnalyzer Read-Log
# Output under %TEMP%\suite-logs (contains this VM's logs incl. the Security log - delete when done).
$ErrorActionPreference = 'Continue'
# NOT under %LOCALAPPDATA%: when started from inside a packaged (MSIX) app, writes there are redirected to the app's private
# store, and wevtutil (the Event Log service writes the export) cannot see that folder -> "path not found".
$D = Join-Path $env:TEMP 'suite-logs'; Remove-Item $D -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $D | Out-Null
$sum = Join-Path $D 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
function SizeMB($p) { '{0:N1} MB' -f ((Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB) }
. (Join-Path $PSScriptRoot 'Harness.ps1')
W ("Log generation run {0}  admin={1}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
W ("free on C: before: {0:N1} GB" -f ((Get-PSDrive C).Free / 1GB))

# ---------------- A + B: WinSuperTool ----------------
& {
    $ST = 'WinSuperTool.ps1'; $NL = "`r`n"; $IsWinPE = $false
    W "WinSuperTool: $(Resolve-SuitePath $ST)"
    $sayLog = Join-Path $D 'wst-say.txt'
    function Say([string]$m) { Add-Content -LiteralPath $sayLog -Value $m -Encoding UTF8 }
    . ([scriptblock]::Create((Get-FnText $ST 'Copy-One', 'Copy-Safe', 'Export-Evt', 'Get-InteractiveUser', 'Fmt-Size')))
    . ([scriptblock]::Create((Get-AssignText $ST 'EvtChannels')))
    . ([scriptblock]::Create((Get-AssignText $ST 'Collectors')))
    $prof = (Get-InteractiveUser).Profile
    $bigMB = ((Get-ChildItem 'C:\Windows\MEMORY.DMP', 'C:\Windows\LiveKernelReports' -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
    foreach ($mode in @(@{ Name = 'LIVE'; Live = $true; Keys = @($Collectors.Keys) }, @{ Name = 'OFFLINE (C: as if from WinPE)'; Live = $false; Keys = @('WU', 'DISM', 'EVT', 'CRASH', 'SETUP', 'INFO') })) {
        W "`r`n===== WinSuperTool collectors - $($mode.Name)"
        $root = Join-Path $D ('wst-' + ($mode.Name -split ' ')[0].ToLower())
        foreach ($k in $mode.Keys) {
            if ($k -eq 'BIG' -and $bigMB -gt 2048) { W ("  {0,-7} SKIPPED ({1:N0} MB of dumps)" -f $k, $bigMB); continue }
            $script:ColCount = 0; $script:ColFail = 0; Say "### $($mode.Name) $k"
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try { & $Collectors[$k].Run 'C:' $mode.Live $root $prof } catch { Say "UNCAUGHT in ${k}: $($_.Exception.Message)" }
            W ("  {0,-7} copied {1,5}  failed {2,3}  {3,7:N1}s" -f $k, $script:ColCount, $script:ColFail, $sw.Elapsed.TotalSeconds)
        }
        $files = @(Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        W ("  TOTAL {0} files, {1}" -f $files.Count, (SizeMB $root))
        W "  FAILED / UNCAUGHT lines:"; Get-Content $sayLog | Where-Object { $_ -match 'FAILED|UNCAUGHT|failed' } | Select-Object -Unique -First 12 | ForEach-Object { W "    $_" }
        Clear-Content $sayLog
    }
}

# ---------------- C: standalone Collect-Logs ----------------
& {
    $CL = 'PS suite V1.1\Collect-Logs.ps1'
    W "`r`n===== standalone Collect-Logs: $(Resolve-SuitePath $CL)"
    $ast = Get-SuiteAst $CL
    foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
    $sayLog = Join-Path $D 'cl-say.txt'
    function Say([string]$m) { Add-Content -LiteralPath $sayLog -Value $m -Encoding UTF8 }
    $usr = Get-InteractiveUser; $LogRoot = Join-Path $D 'cl-live'
    $W = $env:SystemDrive; $script:StopRequested = $false      # V1.8: collectors use $W (no hard-coded C:) and honour Stop
    . ([scriptblock]::Create((Get-AssignText $CL 'Collectors')))
    W "  categories: $(@($Collectors.Keys) -join ', ')"
    foreach ($k in @($Collectors.Keys)) {
        $script:count = 0; $script:fail = 0
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { & $Collectors[$k].Run } catch { Say "UNCAUGHT in ${k}: $($_.Exception.Message)" }
        W ("  {0,-7} copied {1,5}  failed {2,3}  {3,7:N1}s" -f $k, $script:count, $script:fail, $sw.Elapsed.TotalSeconds)
    }
    W ("  TOTAL {0} files, {1}" -f @(Get-ChildItem $LogRoot -Recurse -File -Force -ErrorAction SilentlyContinue).Count, (SizeMB $LogRoot))
    W "  FAILED / UNCAUGHT lines:"; Get-Content $sayLog -ErrorAction SilentlyContinue | Where-Object { $_ -match 'FAILED|UNCAUGHT|failed' } | Select-Object -Unique -First 12 | ForEach-Object { W "    $_" }
}

# ---------------- D: AI readers on the collected logs ----------------
& {
    W "`r`n===== AI log readers on the collected files (cap 150,000 chars)"
    . ([scriptblock]::Create((Get-FnText 'WinSuperTool.ps1' 'Read-TextTail', 'Read-LogForAi')))
    # V1.8: ClaudeLogAnalyzer has its own copy of the WinSuperTool reader; older versions have Read-Log
    $claAst = Get-SuiteAst 'PS suite V1.1\ClaudeLogAnalyzer.ps1'
    if ($claAst.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Read-LogForAi' }, $true)) {
        . ([scriptblock]::Create(((Get-FnText 'PS suite V1.1\ClaudeLogAnalyzer.ps1' 'Read-TextTail', 'Read-LogForAi') -replace 'Read-TextTail', 'Read-TextTailCla' -replace 'Read-LogForAi', 'Read-LogForAiCla')))
        function Read-Log($p) { $x = Read-LogForAiCla $p 150000; if ($x.Binary) { throw 'BINARY - skipped' }; $x.Text }
    } else { . ([scriptblock]::Create((Get-FnText 'PS suite V1.1\ClaudeLogAnalyzer.ps1' 'Read-Log'))) }
    $MaxLogChars = 150000
    $live = Join-Path $D 'wst-live'
    $pick = @()
    $pick += Get-ChildItem $live -Recurse -File -Filter '*.log' | Sort-Object Length -Descending | Select-Object -First 2
    $pick += Get-ChildItem $live -Recurse -File -Filter 'System.evtx' | Select-Object -First 1
    $pick += Get-ChildItem $live -Recurse -File -Filter '*.etl' | Select-Object -First 1
    $pick += Get-ChildItem $live -Recurse -File -Filter '*.csv' | Select-Object -First 1
    foreach ($f in $pick | Where-Object { $_ }) {
        W ("  --- {0} ({1:N1} MB)" -f $f.Name, ($f.Length / 1MB))
        [gc]::Collect(); $m0 = [GC]::GetTotalMemory($true); $sw = [Diagnostics.Stopwatch]::StartNew()
        try { $r = Read-LogForAi $f.FullName 150000; $res = if ($r.Binary) { 'BINARY - skipped' } else { "{0:N0} chars, truncated={1}" -f $r.Text.Length, $r.Truncated } } catch { $res = "ERROR $($_.Exception.Message)" }
        W ("     WinSuperTool Read-LogForAi : {0}  {1:N1}s" -f $res, $sw.Elapsed.TotalSeconds)
        [gc]::Collect(); $sw.Restart()
        try { $t = Read-Log $f.FullName; $res2 = "{0:N0} chars" -f $t.Length; $peak = ([GC]::GetTotalMemory($false) - $m0) / 1MB; $res2 += (", managed memory after: +{0:N0} MB" -f $peak) } catch { $res2 = "ERROR $($_.Exception.Message)" }
        W ("     ClaudeLogAnalyzer Read-Log  : {0}  {1:N1}s" -f $res2, $sw.Elapsed.TotalSeconds)
        $t = $null; $r = $null
    }
}
W ("`r`nfree on C: after: {0:N1} GB   output folder: {1} ({2})" -f ((Get-PSDrive C).Free / 1GB), $D, (SizeMB $D))
W "DONE $(Get-Date)"
