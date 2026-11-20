# Run-V15-Verify.ps1 - admin check of the V1.5 WinFixKit fixes (#22 #23 #24) on the real system.
# Rebuild search index runs for real (index is only a cache); its registry change is undone with WinFixKit's own restore.
$ErrorActionPreference = 'Continue'
$OutDir = Join-Path $env:TEMP 'suite-v15'; Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $OutDir | Out-Null
$sum = Join-Path $OutDir 'summary.txt'
function W($m) { Add-Content -LiteralPath $sum -Value $m -Encoding UTF8 }
. (Join-Path $PSScriptRoot 'Harness.ps1')
W "V1.5 verification $(Get-Date)  file=$(Resolve-SuitePath 'WinFixKit.ps1')"
$script:LogDir = Join-Path $OutDir 'Logs'; $script:ReportDir = Join-Path $OutDir 'Reports'; $script:RegKeyDir = Join-Path $OutDir 'Keys'; $script:RegFullDir = Join-Path $OutDir 'Full'
foreach ($d in $script:LogDir, $script:ReportDir, $script:RegKeyDir, $script:RegFullDir) { New-Item -ItemType Directory -Force $d | Out-Null }
$script:LogFile = Join-Path $script:LogDir 'v15.log'
$ast = Get-SuiteAst 'WinFixKit.ps1'
foreach ($f in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
function Write-Out($t, $c) { }

$dir = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
function Files { (Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | ForEach-Object { '{0} ({1:N0} KB, {2:HH:mm:ss})' -f $_.Name, ($_.Length / 1KB), $_.LastWriteTime }) -join "`n      " }
W "`r`n===== #23 Rebuild search index"
W "  index folder BEFORE:`n      $(Files)"
$out = (& (Get-ActionRun 'WinFixKit.ps1' 'Rebuild search index') | Out-String)
W "  action output:`n$(($out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '      ' + $_ }) -join "`n")"
W "  index folder right AFTER:`n      $(Files)"
Start-Sleep 30
W "  index folder 30 s later (WSearch recreating it):`n      $(Files)"
W "  WSearch: $((Get-Service WSearch).Status)"
foreach ($j in Get-ChildItem $script:RegKeyDir -Filter *.json) { W ("  undo registry change: " + ((Restore-RegBackup $j.FullName) -join ' ')) }

W "`r`n===== #22 / #24 Test access"
$ta = Get-ActionRun 'WinFixKit.ps1' 'Test access to a PC / NAS by name or IP...'
foreach ($h in '127.0.0.1', 'localhost', $env:COMPUTERNAME, 'no-such-host-xyz') {
    W "  --- target: $h"
    (& $ta $h | Out-String -Width 200) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 8 | ForEach-Object { W "      $_" }
}
W "`r`nDONE $(Get-Date)"
