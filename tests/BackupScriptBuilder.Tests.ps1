# BackupScriptBuilder.Tests.ps1 - edge-case unit tests for Backup Script Builder's pure helpers (pair names, drive keys,
# log stamps, XML escaping, ticked-folder de-duplication, reading tasks back). Nothing is written outside $TestDrive.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   Invoke-Pester .\tests\BackupScriptBuilder.Tests.ps1
$bsbFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\BackupScriptBuilder.ps1'
$bsbAst = [Management.Automation.Language.Parser]::ParseFile($bsbFile, [ref]$null, [ref]$null)
foreach ($fn in $bsbAst.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'ConvertTo-XmlText', 'Get-PairName', 'Get-DriveKey', 'Get-LogStampFormat', 'Get-UniqueFolders', 'Get-ScriptFromAction', 'Get-ScriptType' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
function Join-Out($r) { @($r) -join '|' }

Describe 'Pair names, drive keys, log stamps, XML' {
    It "Get-PairName returns first char plus '-Drive' when path leaf is empty" { Get-PairName -path "C:\" -used @{} | Should Be "C-Drive" }
    It "Get-PairName appends incrementing number when name already exists in used hashtable" { Get-PairName -path "C:\folder" -used @{"folder"=$true} | Should Be "folder-2" }
    It "Get-DriveKey returns uppercased UNC root for network paths" { Get-DriveKey -path "\\Server\Share" | Should Be "\\SERVER\SHARE" }
    It "Get-DriveKey returns first two characters uppercased for short relative paths" { Get-DriveKey -path "rel" | Should Be "RE" }
    It "Get-LogStampFormat returns empty string when mode is not New" { Get-LogStampFormat -log @{Mode='Append'} | Should Be "" }
    It "ConvertTo-XmlText escapes XML special characters" { ConvertTo-XmlText -s "<>&" | Should Be "&lt;&gt;&amp;" }
    It 'Get-PairName: same name in another case still gets -2, then -3' { $u = @{}; Get-PairName 'C:\Docs' $u | Out-Null; Get-PairName 'D:\docs' $u | Should Be 'docs-2'; Get-PairName 'E:\DOCS' $u | Should Be 'DOCS-3' }
    It 'Get-PairName: UNC share root uses the share name' { Get-PairName '\srv\share' @{} | Should Be 'share' }
    It 'Get-LogStampFormat: New with date and time / date / time / neither' {
        Get-LogStampFormat @{ Mode = 'New'; Date = $true; Time = $true } | Should Be 'yyyy-MM-dd_HHmmss'
        Get-LogStampFormat @{ Mode = 'New'; Date = $true } | Should Be 'yyyy-MM-dd'
        Get-LogStampFormat @{ Mode = 'New'; Time = $true } | Should Be 'HHmmss'
        Get-LogStampFormat @{ Mode = 'New' } | Should Be ''
    }
    It 'ConvertTo-XmlText escapes quotes and apostrophes' { ConvertTo-XmlText "a'b`"c" | Should Be 'a&apos;b&quot;c' }
}
Describe 'Get-UniqueFolders' {
    It 'a ticked folder inside another (any case) is dropped' { Join-Out (Get-UniqueFolders @('C:\Test', 'c:\test\sub')) | Should Be 'C:\Test' }
    It 'trailing backslash duplicates collapse' { Join-Out (Get-UniqueFolders @('C:\Data\', 'C:\Data')) | Should Be 'C:\Data' }
    It 'a name prefix is not a parent (D:\x and D:\xy both kept)' { Join-Out (Get-UniqueFolders @('D:\xy', 'D:\x')) | Should Be 'D:\x|D:\xy' }
    It 'a drive root covers everything on that drive only' { Join-Out (Get-UniqueFolders @('E:\a', 'E:\', 'F:\a')) | Should Be 'E:\|F:\a' }
    It 'empty and null entries are ignored' { Join-Out (Get-UniqueFolders @('', $null, 'C:\Root')) | Should Be 'C:\Root' }
    It 'no input gives an empty list' { (Get-UniqueFolders @()).Count | Should Be 0 }
}
Describe 'Reading tasks back' {
    It 'returns trimmed arguments when no quotes exist' { (Get-ScriptFromAction -a ([PSCustomObject]@{Arguments='  cmd /c dir  '})) | Should Match '^cmd /c dir$' }
    It 'returns the last quoted string when multiple quotes are present' { (Get-ScriptFromAction -a ([PSCustomObject]@{Arguments='/run "C:\first" "C:\last"'})) | Should Match '^C:\\last$' }
    It 'returns FreeFileSync when script extension is .ffs_batch' { Get-ScriptType -exe 'C:\sync.exe' -script 'C:\batch.ffs_batch' | Should Be 'FreeFileSync' }
    It 'returns Xcopy when script file content contains Xcopy' { Set-Content -LiteralPath "$TestDrive\script.bat" -Value "xcopy /s src dst"; Get-ScriptType -exe 'cmd.exe' -script "$TestDrive\script.bat" | Should Be 'Xcopy' }
    It 'returns FreeFileSync over Xcopy when exe contains FreeFileSync' { Get-ScriptType -exe 'C:\FreeFileSync\app.exe' -script 'C:\xcopy.bat' | Should Be 'FreeFileSync' }
    It 'Get-ScriptType: a path containing robocopy is Robocopy' { Get-ScriptType 'powershell.exe' 'C:\x\robocopy-backup.ps1' | Should Be 'Robocopy' }
    It 'Get-ScriptType: an unreadable script falls back to Robocopy' { Get-ScriptType 'cmd.exe' 'C:\nope\missing.bat' | Should Be 'Robocopy' }
    It 'Get-ScriptFromAction: empty arguments give an empty string' { Get-ScriptFromAction ([pscustomobject]@{ Arguments = $null }) | Should Be '' }
}
