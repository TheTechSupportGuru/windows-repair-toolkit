# Run-MonitorLive.ps1 - LIVE test of every Live Monitor item in WinSuperTool (default: the beta).
# For each item it runs the exact code the tool would open in a monitor window, hidden, with its output captured,
# and checks the window starts, shows the log and reports no error. Then it proves each window TYPE follows new
# activity: a line appended to a file, a filtered line, a new event (and the event-ID filter), a new file in a
# folder, and a pasted path that only appears after the window opened.
# Start elevated (CBS.log and the Security log need admin). Writes one test event (ID 9999 / 9998) to the
# "Windows PowerShell" log with its existing "PowerShell" source; everything else is temp files.
param([string]$Script = (Join-Path (Split-Path $PSScriptRoot -Parent) 'beta\WinSuperTool.ps1'),
      [string]$OutDir = 'C:\Users\Public\wst-monitor-test', [int]$Seconds = 14)
$ErrorActionPreference = 'Continue'
Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $OutDir | Out-Null
# read a file the monitor window still has open for writing
function Read-Shared([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return '' }
    try { $fs = New-Object IO.FileStream($p, 'Open', 'Read', 'ReadWrite, Delete'); $sr = New-Object IO.StreamReader($fs); try { $sr.ReadToEnd() } finally { $sr.Dispose() } } catch { '' }
}
$tk = $null; $pe = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$tk, [ref]$pe)
function Get-A($n) { $ast.Find({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left -is [Management.Automation.Language.VariableExpressionAst] -and $x.Left.VariablePath.UserPath -eq $n }, $true).Extent.Text }
function Get-F($n) { $ast.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true).Extent.Text }
$WinDir = $env:windir
foreach ($v in 'tplFile', 'tplFilter', 'tplEvt', 'tplDir') { . ([scriptblock]::Create((Get-A $v))) }
. ([scriptblock]::Create((Get-F 'New-MonItem'))); . ([scriptblock]::Create((Get-F 'Esc-Sq'))); . ([scriptblock]::Create((Get-F 'Start-Monitor')))
. ([scriptblock]::Create((Get-A 'MonItems')))
$script:MonProcs = New-Object Collections.ArrayList; $PsExePath = 'powershell.exe'
# capture the code Start-Monitor would launch instead of opening a window
function Start-Process { param($FilePath, [switch]$PassThru, $ArgumentList) $global:LastEnc = $ArgumentList[-1]; [pscustomobject]@{ Id = 0; HasExited = $true } }
function Get-MonCode($item, $tail) { $global:LastEnc = $null; Start-Monitor $item $tail; if (-not $global:LastEnc) { throw 'Start-Monitor was not captured' }; [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($global:LastEnc)) }

# ---- live checks on temp targets (the same templates) ----
$tmp = Join-Path $OutDir 'targets'; New-Item -ItemType Directory -Force $tmp | Out-Null
$f1 = Join-Path $tmp 'file.log';   Set-Content $f1 'existing line 1', 'existing line 2'
$f2 = Join-Path $tmp 'filter.log'; Set-Content $f2 'noise', '[SR] existing match'
$d1 = Join-Path $tmp 'watch';      New-Item -ItemType Directory -Force $d1 | Out-Null; Set-Content (Join-Path $d1 'old.txt') 'x'
$late = Join-Path $tmp 'appears-later.log'
$live = @(
    @{ Name = 'LIVE File: appended line shows';            Item = (New-MonItem 'Test' 'file' 'File' $f1);                                        Expect = 'LIVE-APPENDED-LINE' }
    @{ Name = 'LIVE Filter: matching line shows';          Item = (New-MonItem 'Test' 'filter' 'Filter' $f2 '\[SR\]');                             Expect = 'LIVE-SR-MATCH'; NotExpect = 'LIVE-NOISE' }
    @{ Name = 'LIVE Evt: new event shows';                 Item = (New-MonItem 'Test' 'evt' 'Evt' 'Windows PowerShell');                          Expect = 'ID 9999' }
    @{ Name = 'LIVE Evt with ID filter: only listed IDs';  Item = (New-MonItem 'Test' 'evtids' 'Evt' 'Windows PowerShell' '9999');                 Expect = 'ID 9999'; NotExpect = 'ID 9998' }
    @{ Name = 'LIVE Dir: new file shows';                  Item = (New-MonItem 'Test' 'dir' 'Dir' $d1);                                           Expect = 'NEW .*new-file\.txt' }
    @{ Name = 'LIVE Pasted path that appears later';       Item = (New-MonItem 'Pasted' 'late' 'File' $late);                                     Expect = 'LIVE-LATE-LINE' }
)
$all = @()
$i = 0
foreach ($it in $MonItems) { $i++; $all += @{ Name = "[$($it.Section)] $($it.Name)"; Item = $it; Real = $true; N = $i } }
foreach ($l in $live) { $i++; $l.N = $i; $all += $l }
$procs = @()
foreach ($a in $all) {
    $code = Get-MonCode $a.Item 20
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $o = Join-Path $OutDir ('{0:D2}.out.txt' -f $a.N); $e = Join-Path $OutDir ('{0:D2}.err.txt' -f $a.N)
    $p = Microsoft.PowerShell.Management\Start-Process -FilePath powershell.exe -PassThru -WindowStyle Hidden -RedirectStandardOutput $o -RedirectStandardError $e -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc
    $a.P = $p; $a.Out = $o; $a.Err = $e
}
# wait until every window has printed its header (many PowerShell windows start at once, that can take a while)
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 60) {
    $notReady = @($all | Where-Object { ((Read-Shared $_.Out) -notmatch 'Monitoring|Live event monitor|Watching folder|Cannot open|does not exist') })
    if (-not $notReady.Count) { break }
    Start-Sleep -Milliseconds 500
}
Start-Sleep -Seconds 3      # the folder watcher lists existing files before it starts watching
# generate activity
Add-Content $f1 'LIVE-APPENDED-LINE'
Add-Content $f2 'LIVE-NOISE'; Add-Content $f2 '[SR] LIVE-SR-MATCH'
try { Write-EventLog -LogName 'Windows PowerShell' -Source PowerShell -EventId 9998 -EntryType Information -Message 'WinSuperTool monitor test (not in the ID filter)' -ErrorAction Stop
      Write-EventLog -LogName 'Windows PowerShell' -Source PowerShell -EventId 9999 -EntryType Information -Message 'WinSuperTool monitor test' -ErrorAction Stop } catch { "Could not write the test events: $($_.Exception.Message)" }
Set-Content (Join-Path $d1 'new-file.txt') 'new'
Set-Content $late 'LIVE-LATE-LINE'
Start-Sleep -Seconds $Seconds
foreach ($a in $all) { try { if ($a.P -and -not $a.P.HasExited) { Stop-Process -Id $a.P.Id -Force } } catch {} }
Start-Sleep -Milliseconds 800

$rows = foreach ($a in $all) {
    $out = Read-Shared $a.Out
    # stderr of a redirected PowerShell is CLIXML; only its Error entries are real errors (the rest is progress data)
    $err = ''
    if (Test-Path $a.Err) {
        $raw = Read-Shared $a.Err
        $err = (@([regex]::Matches($raw, '<S S="Error">([^<]*)</S>') | ForEach-Object { $_.Groups[1].Value -replace '_x000D__x000A_', ' ' }) -join ' ').Trim()
        if (-not $err -and $raw.Trim() -and -not $raw.TrimStart().StartsWith('#< CLIXML')) { $err = $raw.Trim() }
    }
    $lines = @($out -split "`r?`n" | Where-Object { $_.Trim() })
    $started = $out -match 'Monitoring|Live event monitor|Watching folder|does not exist on this PC'
    $problem = @()
    if (-not $started) { $problem += 'window did not start' }
    if ($err) { $problem += 'stderr: ' + ($err -split "`r?`n")[0] }
    if ($out -match 'Cannot open event log') { $problem += 'cannot open the event log' }
    if ($a.Expect -and $out -notmatch $a.Expect) { $problem += "did not show '$($a.Expect)'" }
    if ($a.NotExpect -and $out -match [regex]::Escape($a.NotExpect)) { $problem += "showed '$($a.NotExpect)' (filter broken)" }
    $note = ''
    if ($a.Real) {
        $exists = if ($a.Item.Type -eq 'Evt') { [bool](Get-WinEvent -ListLog $a.Item.Target -ErrorAction SilentlyContinue) } else { Test-Path -LiteralPath $a.Item.Target }
        if (-not $exists) { $note = 'target not on this PC'; if ($out -notmatch 'Waiting for|does not exist on this PC') { $problem += 'missing target but no clear message' } }
        elseif ($lines.Count -le 1 -and $a.Item.Type -ne 'Filter') { $note = 'target exists but is empty / quiet' }
    }
    [pscustomobject]@{ N = $a.N; Result = $(if ($problem.Count) { 'FAIL' } else { 'PASS' }); Name = $a.Name; Type = $a.Item.Type; Lines = $lines.Count; Note = (@($note) + $problem | Where-Object { $_ }) -join '; '
        First = $(if ($lines.Count -gt 1) { $lines[1].Trim() } else { '' }) }
}
$rows | Export-Csv (Join-Path $OutDir 'report.csv') -NoTypeInformation
$sum = "Monitor live test {0}  admin={1}  script={2}`r`nPASS {3}  FAIL {4}`r`n" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator), (Split-Path $Script -Leaf), @($rows | Where-Object Result -eq 'PASS').Count, @($rows | Where-Object Result -eq 'FAIL').Count
$sum += ($rows | Format-Table N, Result, Type, Lines, Name, Note -AutoSize | Out-String -Width 250)
[IO.File]::WriteAllText((Join-Path $OutDir 'report.txt'), $sum)
$sum
