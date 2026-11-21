# Run-StatusChecks.ps1 - Phase 2 / R1: runs every WinFixKit "Check status" block headlessly (no GUI),
# times it, records errors, and compares a system snapshot before/after to prove the checks are read-only.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-StatusChecks.ps1 -OutDir <folder>
param([Parameter(Mandatory)][string]$OutDir)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Harness.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$tag = if ($isAdmin) { 'admin' } else { 'user' }

# WinFixKit's data folders -> a throwaway folder, never the real Desktop\WinFixKit
$DataRoot = Join-Path $OutDir "wfk-data-$tag"
$script:RootDir = $DataRoot; $script:LogDir = Join-Path $DataRoot 'Logs'; $script:ReportDir = Join-Path $DataRoot 'Reports'
$script:RegDir = Join-Path $DataRoot 'RegistryBackups'; $script:RegKeyDir = Join-Path $script:RegDir 'Keys'; $script:RegFullDir = Join-Path $script:RegDir 'Full'
foreach ($d in $script:LogDir, $script:ReportDir, $script:RegKeyDir, $script:RegFullDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$script:LogFile = Join-Path $script:LogDir 'headless.log'

# load every function + the $Sections table (definitions only - nothing runs)
$ast = Get-SuiteAst 'WinFixKit.ps1'
$fns = $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)
foreach ($f in $fns) { . ([scriptblock]::Create($f.Extent.Text)) }
. ([scriptblock]::Create((Get-AssignText 'WinFixKit.ps1' 'Sections')))

function Get-Snapshot {
    [pscustomobject]@{
        # BITS is left out: Windows (SYSTEM) switches its start type between Manual and Automatic by itself whenever
        # downloads are queued or finished (event 7040), which made this read-only check report a false change (2026-11-20)
        Services   = (Get-CimInstance Win32_Service | Where-Object Name -ne 'BITS' | Sort-Object Name | ForEach-Object { '{0}|{1}' -f $_.Name, $_.StartMode }) -join "`n"
        NetProfile = (Get-NetConnectionProfile | ForEach-Object { '{0}|{1}' -f $_.Name, $_.NetworkCategory }) -join "`n"
        PowerPlan  = (powercfg /getactivescheme | Out-String).Trim()
        SmbClient  = (Get-SmbClientConfiguration -ErrorAction SilentlyContinue | ForEach-Object { '{0}|{1}' -f $_.EnableInsecureGuestLogons, $_.RequireSecuritySignature }) -join ''
        Printers   = ((Get-Printer -ErrorAction SilentlyContinue).Name | Sort-Object) -join ','
        Devices    = (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object Status -eq 'Error' | Measure-Object).Count
        SpoolFiles = (Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" -ErrorAction SilentlyContinue | Measure-Object).Count
        Desktop    = (Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Force | Sort-Object Name | ForEach-Object Name) -join ','
    }
}

$before = Get-Snapshot
$rows = foreach ($sec in $Sections) {
    $err0 = $Error.Count
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = try { (& $sec.Status 2>&1 | Out-String -Width 220) } catch { "UNCAUGHT: $($_.Exception.Message)" }
    $sw.Stop()
    $file = Join-Path $OutDir ("status-{0}-{1}.txt" -f $tag, ($sec.Name -replace '[^A-Za-z0-9]+', '_'))
    $out | Set-Content -LiteralPath $file -Encoding UTF8
    $errLines = @($out -split "`r?`n" | Where-Object { $_ -match '(?i)^\s*(ERROR|UNCAUGHT|.*Exception)|access is denied|requires elevation|not recognized as' })
    [pscustomobject]@{
        Section = $sec.Name; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); Lines = ($out -split "`n").Count
        ErrorLines = $errLines.Count; NewPsErrors = $Error.Count - $err0; FirstError = ($errLines | Select-Object -First 1)
    }
}
$after = Get-Snapshot
$diff = foreach ($p in $before.PSObject.Properties.Name) { if ($before.$p -ne $after.$p) { $p } }

$rows | Export-Csv (Join-Path $OutDir "status-summary-$tag.csv") -NoTypeInformation
@{ Admin = $isAdmin; Changed = @($diff); Before = $before; After = $after } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir "snapshot-$tag.json") -Encoding UTF8
"RUN AS: $tag"
$rows | Format-Table Section, Seconds, Lines, ErrorLines, NewPsErrors -AutoSize | Out-String -Width 200
"FIRST ERROR PER SECTION:"; $rows | Where-Object ErrorLines | ForEach-Object { "  [$($_.Section)] $($_.FirstError)" }
"SNAPSHOT CHANGED: " + $(if ($diff) { $diff -join ', ' } else { 'nothing (read-only confirmed)' })
