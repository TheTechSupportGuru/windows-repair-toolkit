# Run-ElevatedSmoke.ps1 - opens each GUI tool of the NEWEST "Edited scripts\V<x.y>" as admin for 20 s and closes it.
# Runs from a TEMP copy (so no data folders appear inside "Edited scripts"). Start it once elevated.
# ClaudeLogAnalyzer is skipped on purpose: it opens a LAN listener at start-up, which pops a Windows Firewall prompt.
param([string]$OutDir = (Join-Path $env:TEMP 'suite-smoke'))
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Harness.ps1')
# the repo's tools\ folder (the old "Edited scripts\V<x.y>" folders only exist outside the repo)
$verDir = if (@($global:EditedVersions).Count) { $global:EditedVersions[0].FullName } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'tools' }
Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path "$OutDir\gui" | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
W ("Smoke test of {0}  {1}  admin={2}" -f $verDir, (Get-Date), ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Copy-Item (Join-Path $verDir '*') "$OutDir\gui" -Recurse
foreach ($s in 'WinSuperTool.ps1', 'WinRepairTool-startup.ps1', 'Collect-Logs.ps1', 'Monitor-Logs.ps1', 'WinFixKit.ps1') {
    if (-not (Test-Path "$OutDir\gui\$s")) { W "  $s : not in this version folder (skipped)"; continue }
    $tr = "$OutDir\gui\$s.transcript.txt"
    $extra = if ($s -eq 'WinFixKit.ps1') { " -DataRoot '$OutDir\gui\wfk-data'" } else { '' }
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', "Start-Transcript -Path '$tr' | Out-Null; & '$OutDir\gui\$s'$extra; Stop-Transcript | Out-Null" -PassThru
    Start-Sleep 20
    $p.Refresh(); $alive = -not $p.HasExited; $title = $p.MainWindowTitle; $how = 'already exited'
    if ($alive) { [void]$p.CloseMainWindow(); if ($p.WaitForExit(8000)) { $how = "closed, exit $($p.ExitCode)" } else { Stop-Process -Id $p.Id -Force; $how = 'FORCE-killed' } }
    $errs = @(Select-String -Path $tr -Pattern 'FullyQualifiedErrorId' -ErrorAction SilentlyContinue)
    W ("  {0,-26} alive after 20s: {1,-5} title: '{2}'  {3}  transcript errors: {4}" -f $s, $alive, $title, $how, $errs.Count)
    Select-String -Path $tr -Pattern '^At .*:(\d+) char' -ErrorAction SilentlyContinue | Group-Object Line | ForEach-Object { W ("      {0}x  {1}" -f $_.Count, $_.Name.Trim()) }
}
W "DONE $(Get-Date)"
