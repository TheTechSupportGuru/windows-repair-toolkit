# Run-V18-Verify.ps1 - admin checks for the V1.8 ports (WinRepairTool, standalone tools), then the full log-generation
# run and the GUI smoke test. Start once elevated. Changes nothing permanent: BCD is only READ (Ask is stubbed to "No"),
# one test event is written to the "Windows PowerShell" log with its existing "PowerShell" source.
param([switch]$Quick)   # -Quick: skip the log-generation run and the GUI smoke test
$ErrorActionPreference = 'Continue'
# NOTE: not $Out - PowerShell names ignore case, and Invoke-Diskpart's own $out would hide it
$V18Out = Join-Path $env:TEMP 'suite-v18'; Remove-Item $V18Out -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $V18Out | Out-Null
$sum = Join-Path $V18Out 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
function Check($name, [scriptblock]$test) {
    try { $r = & $test; if ($r -is [bool]) { $ok = $r; $info = '' } else { $ok = [bool]$r[0]; $info = $r[1] } } catch { $ok = $false; $info = "EXCEPTION $($_.Exception.Message)" }
    W ("  [{0}] {1}  {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $info)
}
. (Join-Path $PSScriptRoot 'Harness.ps1')
$WRT = 'PS suite V1.1\WinRepairTool-startup.ps1'; $ML = 'PS suite V1.1\Monitor-Logs.ps1'
W ("V1.8 verification {0}  admin={1}  WRT={2}" -f (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator), (Resolve-SuitePath $WRT))

# ---------- WinRepairTool functions against the real system (read-only) ----------
& {
    $IsWinPE = $false; $NL = "`r`n"
    function Log($m) { Add-Content -LiteralPath (Join-Path $V18Out 'wrt-log.txt') -Value $m }
    function Msg($t, $c, $i) { Log "MSG: $t" }
    function Ask { $global:Asked = $args[0]; $false }        # never say yes: nothing is changed
    . ([scriptblock]::Create((Get-AssignText $WRT 'CloneMarkers')))
    . ([scriptblock]::Create((Get-FnText $WRT 'Get-WinInstalls', 'ConvertFrom-BcdText', 'Get-BcdAll', 'Resolve-BcdTarget', 'Get-Clones', 'Confirm-BootMenuShown', 'Get-DpPartLetter', 'Invoke-Diskpart')))
    . ([scriptblock]::Create((Get-AssignText $WRT 'DpAllow')))
    W "`r`n===== WinRepairTool (V1.8 port), read-only"
    Check 'Get-WinInstalls finds C: and marks it RUNNING (R6)' { $w = @(Get-WinInstalls); (@($w | Where-Object { $_.Drive -eq 'C:' -and $_.Running }).Count -eq 1), (($w | ForEach-Object Text) -join ' | ') }
    $t = Resolve-BcdTarget 'C:'
    Check 'Resolve-BcdTarget C: -> {current} in the loaded store' { ($t.Id -eq '{current}' -and -not $t.Store), "Id=$($t.Id) Safeboot='$($t.Safeboot)'" }
    Check 'Get-Clones reads the real store without error' { $c = @(Get-Clones $t 'C:'); $true, "clones: $($c.Count)" }
    Check 'Confirm-BootMenuShown reads the real {bootmgr} timeout (no change made)' {
        $global:Asked = $null; Confirm-BootMenuShown $t
        $o = (& bcdedit.exe /enum '{bootmgr}' | Out-String); $to = if ($o -match '(?m)^timeout\s+(\d+)') { $Matches[1] } else { '(none)' }
        (($to -eq '0') -eq [bool]$global:Asked), "timeout=$to asked=$([bool]$global:Asked)"
    }
    Check 'real diskpart: C: partition letter by column position' {
        $sys = Get-Partition -DriveLetter C
        $l = Get-DpPartLetter $sys.DiskNumber $sys.PartitionNumber; ($l -eq 'C'), "got '$l'"
    }
    Check 'recovery tool executables exist for the running Windows forms (sfc, dism, pnputil, chkdsk, bcdboot)' {
        $m = @('sfc.exe', 'dism.exe', 'pnputil.exe', 'chkdsk.exe', 'bcdboot.exe' | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }); ($m.Count -eq 0), "missing: $($m -join ', ')"
    }
    Check 'bootrec is reported as not available here (R12)' { (-not (Get-Command bootrec.exe -ErrorAction SilentlyContinue)), 'bootrec.exe not on this Windows (WinRE only)' }
}

# ---------- Monitor-Logs: the new event poller, live ----------
& {
    W "`r`n===== Monitor-Logs event poller (live)"
    . ([scriptblock]::Create((Get-AssignText $ML 'tplEvt')))
    $code = $tplEvt.Replace('__TITLE__', 'poller-test').Replace('__TARGET__', 'Windows PowerShell').Replace('__TAIL__', '1').Replace('__IDS__', '4321')
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $o = Join-Path $V18Out 'poller.txt'
    $had4321 = [bool](Get-WinEvent -FilterHashtable @{ LogName = 'Windows PowerShell'; Id = 4321 } -MaxEvents 1 -ErrorAction SilentlyContinue)
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc -RedirectStandardOutput $o -WindowStyle Hidden -PassThru
    Start-Sleep 4
    Write-EventLog -LogName 'Windows PowerShell' -Source 'PowerShell' -EventId 4321 -EntryType Warning -Message 'V18 poller test event A'
    Write-EventLog -LogName 'Windows PowerShell' -Source 'PowerShell' -EventId 1111 -EntryType Information -Message 'V18 poller test event (other id, must NOT show)'
    Start-Sleep 5
    Write-EventLog -LogName 'Windows PowerShell' -Source 'PowerShell' -EventId 4321 -EntryType Warning -Message 'V18 poller test event B'
    Start-Sleep 5
    Stop-Process -Id $p.Id -Force; Start-Sleep 1
    $txt = Get-Content $o -Raw
    # This log's "PowerShell" source has no message text for custom IDs, so count the ID lines instead of the text.
    # The monitor first prints the newest OLD 4321 event (tail 1) if an earlier run left one, then each new one once.
    $shown = [regex]::Matches($txt, 'ID 4321 ').Count
    Check 'the 2 new ID-4321 events are each shown exactly once' { ($shown -eq 2 + [int]$had4321), "lines: $shown (old event shown as tail: $had4321)" }
    Check 'the event with another ID (1111) is filtered out' { ($txt -notmatch 'ID 1111 '), '' }
    W ('  child output: ' + (($txt -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 4) -join ' || '))
}

if ($Quick) { W "DONE (quick) $(Get-Date)"; return }
W "`r`n===== log generation (Run-LogGen.ps1) - see %TEMP%\suite-logs\summary.txt"
& (Join-Path $PSScriptRoot 'Run-LogGen.ps1')
W "===== GUI smoke test (Run-ElevatedSmoke.ps1) - see %TEMP%\suite-smoke\summary.txt"
& (Join-Path $PSScriptRoot 'Run-ElevatedSmoke.ps1')
W "DONE $(Get-Date)"
