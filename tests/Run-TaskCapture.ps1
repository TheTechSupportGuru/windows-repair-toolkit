# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run-TaskCapture.ps1 - runs real READ-ONLY scans through the beta's own task window (conhost), waits for each result
# file, then gives the output to the beta's Get-TaskVerdict - exactly what the Recovery tab and the Automation tab do.
# Shows the verdict, the quoted lines and whether the wording was recognised ("matched") or the exit code decided
# (matched=False: for example Windows in another display language). Run as administrator for sfc and DISM scanhealth.
#   .\tests\Run-TaskCapture.ps1 -Script .\tools\WinSuperTool.ps1 -OutDir $env:TEMP\wrt-capture -Elevated
param([string]$Script = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\WinSuperTool.ps1'), [string]$OutDir = (Join-Path $env:TEMP 'wrt-capture'), [switch]$Elevated,
      [string]$Windows = '')     # offline: the drive of a Windows that is not running (WinPE), e.g. D: - uses the tools' offline forms
$ErrorActionPreference = 'Stop'
$t = $null; $e = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$t, [ref]$e)
function Get-Assign($name) { $ast.Find({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left -is [Management.Automation.Language.VariableExpressionAst] -and $x.Left.VariablePath.UserPath -eq $name }, $true).Extent.Text }
function Get-Fn($name) { $ast.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name }, $true).Extent.Text }
$NL = "`r`n"
. ([scriptblock]::Create((Get-Fn 'New-TaskRule'))); . ([scriptblock]::Create((Get-Assign 'SfcCommon'))); . ([scriptblock]::Create((Get-Assign 'DismError')))
. ([scriptblock]::Create((Get-Assign 'TaskRules'))); . ([scriptblock]::Create((Get-Fn 'Get-TaskVerdict'))); . ([scriptblock]::Create((Get-Fn 'Read-TaskResult')))
. ([scriptblock]::Create((Get-Fn 'Esc-Sq'))); . ([scriptblock]::Create((Get-Assign 'tplTask')))
New-Item -ItemType Directory -Force $OutDir | Out-Null
if ($Windows) {
    # offline forms, as the Recovery tab builds them for a Windows that is not running (all read-only)
    $W = $Windows.TrimEnd('\')
    $jobs = @(
        @{ N = 'offline-dism-checkhealth'; K = 'dism-check';  Exe = 'dism.exe';   A = @("/image:$W\", '/cleanup-image', '/checkhealth') },
        @{ N = 'offline-dism-scanhealth';  K = 'dism-check';  Exe = 'dism.exe';   A = @("/image:$W\", '/cleanup-image', '/scanhealth', "/scratchdir:$W\Windows\Temp") },
        @{ N = 'offline-sfc-verifyonly';   K = 'sfc-verify';  Exe = 'sfc.exe';    A = @('/verifyonly', "/offbootdir=$W\", "/offwindir=$W\Windows") },
        @{ N = 'offline-chkdsk-scan';      K = 'chkdsk-scan'; Exe = 'chkdsk.exe'; A = @($W, '/scan') }
    )
} else {
$jobs = @(
    @{ N = 'dism-checkhealth'; K = 'dism-check';  Exe = 'dism.exe';   A = @('/online', '/cleanup-image', '/checkhealth') },
    @{ N = 'chkdsk-scan';      K = 'chkdsk-scan'; Exe = 'chkdsk.exe'; A = @($env:SystemDrive, '/scan') }
)
}
if ($Elevated -and -not $Windows) {
    $jobs += @{ N = 'sfc-verifyonly';  K = 'sfc-verify'; Exe = 'sfc.exe';  A = @('/verifyonly') }
    $jobs += @{ N = 'dism-scanhealth'; K = 'dism-check'; Exe = 'dism.exe'; A = @('/online', '/cleanup-image', '/scanhealth') }
}
# the PowerShell that runs this script (Windows PowerShell 5.1, or PowerShell 7 = pwsh.exe, as in Hiren's PE 10)
$ps = (Get-Process -Id $PID).Path
foreach ($j in $jobs) {
    $line = $j.Exe + ' ' + ($j.A -join ' ')
    $call = "& '" + (Esc-Sq $j.Exe) + "' " + (($j.A | ForEach-Object { "'" + (Esc-Sq $_) + "'" }) -join ' ')
    $res = Join-Path $OutDir "$($j.N).txt"; if (Test-Path -LiteralPath $res) { Remove-Item -LiteralPath $res }
    # the "Press Enter" at the end is answered automatically so the window closes by itself
    $cmd = $tplTask.Replace('__CMD__', $call).Replace('__TITLE__', "TEST: $($j.N)").Replace('__RESULT__', (Esc-Sq $res)).Replace('__LINE__', (Esc-Sq $line)).Replace("Read-Host 'Press Enter to close this window'", 'Start-Sleep 2').Replace('__CLOSE__', 'Start-Sleep 2')
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $p = Start-Process -FilePath "$env:windir\System32\conhost.exe" -PassThru -ArgumentList ('"{0}" -NoProfile -ExecutionPolicy Bypass -EncodedCommand {1}' -f $ps, $enc)
    $p.WaitForExit(1800000) | Out-Null
    if (Test-Path $res) {
        $r = Read-TaskResult $res; $v = Get-TaskVerdict $j.K $r.Output $r.Rc
        "=== $($j.N)  rc=$($r.Rc)  ok=$($v.Ok) tone=$($v.Tone)  matched=$($v.Matched)"
        "    FIND: $($v.Find)"
        foreach ($q in $v.Quote) { "    QUOTE: $q" }
        "    --- captured output ---"; ($r.Output -split "`r`n" | ForEach-Object { "    | $_" }) -join "`r`n"
    } else { "=== $($j.N): NO RESULT FILE" }
}
