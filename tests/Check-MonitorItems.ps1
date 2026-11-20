# Check-MonitorItems.ps1 - Phase 2 / R3 (headless part): for every Live Monitor item in WinSuperTool and Monitor-Logs,
# build the exact code the tool would run in its new window, check that it parses, and check whether the target exists here.
# Nothing is launched (Start-Process is replaced by a stub).
. (Join-Path $PSScriptRoot 'Harness.ps1')
$res = @()

# ---- WinSuperTool ----
$ST = 'WinSuperTool.ps1'
$WinDir = $env:SystemRoot; $SysDrive = $env:SystemDrive
foreach ($v in 'tplFile', 'tplFilter', 'tplEvt', 'tplDir') { . ([scriptblock]::Create((Get-AssignText $ST $v))) }
. ([scriptblock]::Create((Get-FnText $ST 'New-MonItem', 'Esc-Sq', 'Start-Monitor')))
try { . ([scriptblock]::Create((Get-AssignText $ST 'MonItems'))) } catch { "MonItems load error: $($_.Exception.Message)" }
$script:MonProcs = New-Object Collections.ArrayList
$PsExePath = 'powershell.exe'
function Start-Process { param($FilePath, [switch]$PassThru, $ArgumentList) $global:LastArgs = $ArgumentList; [pscustomobject]@{ Id = 0; HasExited = $true } }
foreach ($it in $MonItems) {
    Start-Monitor $it 20
    $enc = $global:LastArgs[-1]
    $code = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($enc))
    $t = $null; $e = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$t, [ref]$e)
    $exists = switch ($it.Type) {
        'Evt'   { [bool](Get-WinEvent -ListLog $it.Target -ErrorAction SilentlyContinue) }
        default { Test-Path -LiteralPath $it.Target }
    }
    $res += [pscustomobject]@{ Tool = 'WinSuperTool'; Section = $it.Section; Name = $it.Name; Type = $it.Type; ParseErrors = $e.Count; TargetExists = $exists; Target = $it.Target }
}

# ---- Monitor-Logs.ps1 (standalone) ----
$ML = 'PS suite V1.1\Monitor-Logs.ps1'
. ([scriptblock]::Create((Get-FnText $ML 'Item', 'Esc')))
. ([scriptblock]::Create((Get-AssignText $ML 'Items')))
foreach ($it in $Items) {
    $exists = switch ($it.Type) { 'Evt' { [bool](Get-WinEvent -ListLog $it.Target -ErrorAction SilentlyContinue) } default { Test-Path -LiteralPath $it.Target } }
    $res += [pscustomobject]@{ Tool = 'Monitor-Logs'; Section = $it.Section; Name = $it.Name; Type = $it.Type; ParseErrors = $null; TargetExists = $exists; Target = $it.Target }
}

$res | Export-Csv (Join-Path $env:TEMP 'suite-phase2\monitor-items.csv') -NoTypeInformation
"Items: WinSuperTool=$(@($res | ? Tool -eq 'WinSuperTool').Count)  Monitor-Logs=$(@($res | ? Tool -eq 'Monitor-Logs').Count)"
"Generated code with parse errors: $(@($res | ? { $_.ParseErrors -gt 0 }).Count)"
"Targets missing on this VM:"; $res | ? { -not $_.TargetExists } | % { "  [$($_.Tool)] $($_.Name)  ->  $($_.Target)" }
