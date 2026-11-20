# Run-Windowed.ps1 - Phase 3: the fixes that open their OWN console window, run for real through the tools' own launch code.
# WinFixKit: Start-InWindow (new PowerShell window + transcript + "Press Enter" at the end). The runner watches each
# window's transcript until the work is finished, records the result, then closes the window.
# WinSuperTool Recovery: checks the "cmd.exe /c <tool> & pause" windows really start, and that chkdsk /f stops at its Y/N question.
# Run as admin. Long (DISM + SFC can take 30+ min). Output: %LOCALAPPDATA%\suite-windowed\summary.txt
$ErrorActionPreference = 'Continue'
$D = Join-Path $env:LOCALAPPDATA 'suite-windowed'; Remove-Item $D -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $D | Out-Null
$sum = Join-Path $D 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
. (Join-Path $PSScriptRoot 'Harness.ps1')
W ("Windowed fixes {0}  admin={1}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$script:LogDir = Join-Path $D 'Logs'; $script:ReportDir = Join-Path $D 'Reports'; foreach ($x in $script:LogDir, $script:ReportDir) { New-Item -ItemType Directory -Force $x | Out-Null }
$ast = Get-SuiteAst 'WinFixKit.ps1'
foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
. ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' 'Sections')))
W "WinFixKit file: $(Resolve-SuitePath 'WinFixKit.ps1')"

function Run-InWindow($label, [int]$timeoutMin, [scriptblock]$check) {
    $act = $null; foreach ($s in $Sections) { foreach ($a in $s.Actions) { if ($a.Label -eq $label) { $act = $a } } }
    W "`r`n===== $label"
    if (-not $act) { W '  !! action not found'; return }
    $before = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ForEach-Object ProcessId)
    $msg = Start-InWindow $act.Run $act.Label
    W "  launcher said: $msg"
    $tr = if ($msg -match 'Transcript: (.+)$') { $Matches[1].Trim() } else { $null }
    Start-Sleep 3
    $win = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $before -notcontains $_.ProcessId -and $_.CommandLine -match 'EncodedCommand' } | Select-Object -First 1
    W ("  window process started: {0}" -f [bool]$win)
    $sw = [Diagnostics.Stopwatch]::StartNew(); $done = $false
    while ($sw.Elapsed.TotalMinutes -lt $timeoutMin) {
        if ($tr -and (Test-Path -LiteralPath $tr) -and ((Get-Content -LiteralPath $tr -Raw -ErrorAction SilentlyContinue) -match 'transcript end')) { $done = $true; break }
        if ($win -and -not (Get-Process -Id $win.ProcessId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep 5
    }
    $alive = $win -and [bool](Get-Process -Id $win.ProcessId -ErrorAction SilentlyContinue)
    W ("  finished: {0}  after {1:N1} min; window still waiting for Enter: {2}" -f $done, $sw.Elapsed.TotalMinutes, $alive)
    if ($alive) { Stop-Process -Id $win.ProcessId -Force }
    $text = if ($tr -and (Test-Path -LiteralPath $tr)) { Get-Content -LiteralPath $tr -Raw } else { '' }
    if ($tr) { Copy-Item -LiteralPath $tr (Join-Path $D ((($label -replace '[^A-Za-z0-9]+', '_').Trim('_')) + '.transcript.txt')) -ErrorAction SilentlyContinue }
    $errs = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)FullyQualifiedErrorId|is not recognized|Exception' })
    W ("  PowerShell errors in transcript: {0}" -f $errs.Count); $errs | Select-Object -First 5 | ForEach-Object { W "     $($_.Trim())" }
    if ($check) { & $check $text }
}

# 1) KB5025221 removal (not installed on this build -> expected "not installed")
Run-InWindow 'Fix 2: remove update KB5025221 - opens a window' 5 { param($t) ($t -split "`r?`n" | Where-Object { $_ -match 'KB5025221|wusa exit|installed|Uninstalled|Not removed' } | Select-Object -First 4) | ForEach-Object { W "     $($_.Trim())" } }
# 2) energy report (60 s)
Run-InWindow 'Energy efficiency report (60 s) - opens a window' 5 { param($t)
    $f = Join-Path $script:ReportDir 'energy-report.html'
    W ("  energy-report.html written: {0} ({1:N0} KB)" -f (Test-Path $f), $(if (Test-Path $f) { (Get-Item $f).Length / 1KB } else { 0 }))
    ($t -split "`r?`n" | Where-Object { $_ -match '(?i)error|warning|information|energy' } | Select-Object -First 4) | ForEach-Object { W "     $($_.Trim())" } }
# 3) chkdsk read-only
Run-InWindow 'Scan system drive for errors (read-only) - opens a window' 20 { param($t) ($t -split "`r?`n" | Where-Object { $_ -match '(?i)found no problems|found problems|errors|read-only mode|scanned the file system' } | Select-Object -First 4) | ForEach-Object { W "     $($_.Trim())" } }
# 4) re-register ALL apps
$startBefore = [bool](Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue)
Run-InWindow 'Re-register ALL apps - opens a window' 30 { param($t)
    $n = ([regex]::Matches($t, '(?m)^Processed ')).Count
    W ("  packages processed: {0} (Get-AppxPackage -AllUsers count now: {1})" -f $n, @(Get-AppxPackage -AllUsers).Count)
    W ("  Start menu host running before/after: {0} / {1}" -f $startBefore, [bool](Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue)) }
# 5) DISM + SFC (long)
Run-InWindow 'Repair system files (DISM + SFC) - opens a window' 75 { param($t) ($t -split "`r?`n" | Where-Object { $_ -match '(?i)restore operation|component store|Error:|Windows Resource Protection|integrity violations|repaired|Verification' } | Select-Object -First 8) | ForEach-Object { W "     $($_.Trim())" } }

# ---- WinSuperTool Recovery windows ----
W "`r`n===== WinSuperTool Recovery: console windows really open (cmd.exe /c <tool> & pause)"
$line = 'dism.exe /online /get-drivers'
$before = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | ForEach-Object ProcessId)
Start-Process -FilePath cmd.exe -ArgumentList ('/c ' + $line + ' & pause')        # exactly what the Recovery button runs for window tools
Start-Sleep 15
$c = Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | Where-Object { $before -notcontains $_.ProcessId -and $_.CommandLine -match 'get-drivers' } | Select-Object -First 1
W ("  'Drivers: list third-party drivers' window running: {0}  cmdline: {1}" -f [bool]$c, $c.CommandLine)
if ($c) { Get-CimInstance Win32_Process -Filter "ParentProcessId=$($c.ProcessId)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
W "`r`n===== WinSuperTool 'Check disk and REPAIR (chkdsk /f)' on the running C: - answer N to the schedule question"
$o = (cmd.exe /c 'echo N| chkdsk.exe C: /f' 2>&1 | Out-String)
W ("  exit {0}; asks to schedule: {1}" -f $LASTEXITCODE, [bool]($o -match '(?i)schedule|next time the system restarts|Y/N'))
($o -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) | ForEach-Object { W "     $($_.Trim())" }
W ("  dirty bit / scheduled check after answering N: {0}" -f ((& fsutil.exe dirty query C: 2>&1) -join ' '))
W "`r`nDONE $(Get-Date)"
