# Diag-Energy.ps1 - why does powercfg /energy return after a few seconds without a report? Read-only (writes a report to TEMP). Run as admin.
$o = Join-Path $env:LOCALAPPDATA 'suite-windowed\diag-energy.txt'
$f = Join-Path $env:LOCALAPPDATA 'suite-windowed\energy-test.html'
$sw = [Diagnostics.Stopwatch]::StartNew()
$out = (& powercfg.exe /energy /duration 10 /output $f 2>&1 | Out-String)
$rc = $LASTEXITCODE
@("exit code: $rc   seconds: $([math]::Round($sw.Elapsed.TotalSeconds,1))", "report written: $(Test-Path $f)", '--- output:', $out,
  '--- running kernel trace sessions:', ((& logman.exe query -ets 2>&1) -join "`n")) | Set-Content $o -Encoding UTF8
