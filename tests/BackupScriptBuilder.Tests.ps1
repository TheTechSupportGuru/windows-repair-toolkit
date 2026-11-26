# BackupScriptBuilder.Tests.ps1 - edge-case unit tests for Backup Script Builder's pure helpers (pair names, drive keys,
# log stamps, XML escaping, ticked-folder de-duplication, reading tasks back). Nothing is written outside $TestDrive.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   Invoke-Pester .\tests\BackupScriptBuilder.Tests.ps1
$bsbFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\BackupScriptBuilder.ps1'
$bsbAst = [Management.Automation.Language.Parser]::ParseFile($bsbFile, [ref]$null, [ref]$null)
foreach ($fn in $bsbAst.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'ConvertTo-XmlText', 'Get-PairName', 'Get-DriveKey', 'Get-LogStampFormat', 'Get-UniqueFolders', 'Get-ScriptFromAction', 'Get-ScriptType', 'New-CopyScript', 'Get-PickerFiles', 'Get-SubFolders', 'Test-SkipFolder', 'Test-SystemFolder', 'ConvertTo-UncPath' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
function Join-Out($r) { @($r) -join '|' }

Describe 'Pair names, drive keys, log stamps, XML' {
    It "Get-PairName returns first char plus '-Drive' when path leaf is empty" { Get-PairName -path "C:\" -used @{} | Should Be "C-Drive" }
    It "Get-PairName appends incrementing number when name already exists in used hashtable" { Get-PairName -path "C:\folder" -used @{"folder"=$true} | Should Be "folder-2" }
    It "Get-DriveKey returns uppercased UNC root for network paths" { Get-DriveKey -path "\\Server\Share" | Should Be "\\SERVER\SHARE" }
    It "Get-DriveKey returns first two characters uppercased for short relative paths" { Get-DriveKey -path "rel" | Should Be "RE" }
    It "Get-LogStampFormat returns empty string when mode is not New" { Get-LogStampFormat -log @{Mode='Append'} | Should Be "" }
    It "ConvertTo-XmlText escapes XML special characters" { ConvertTo-XmlText -s "<>&" | Should Be "&lt;&gt;&amp;" }
    It 'Get-PairName: same name in another case still gets -2, then -3' { $u = @{}; Get-PairName 'C:\Docs' $u | Out-Null; Get-PairName 'D:\docs' $u | Should Be 'docs-2'; Get-PairName 'E:\DOCS' $u | Should Be 'DOCS-3' }
    It 'Get-PairName: UNC share root uses the share name' { Get-PairName '\\srv\share' @{} | Should Be 'share' }
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
Describe 'Files and empty folders (1.3): scripts really run, only into $TestDrive' {
    $src = Join-Path $TestDrive 'src'; New-Item -ItemType Directory "$src\Docs\Empty", "$src\Docs\Sub", "$src\Loose\Sub" -Force | Out-Null
    'a' | Set-Content "$src\Docs\a.txt"; 'b' | Set-Content "$src\Docs\Sub\b.txt"
    'k' | Set-Content "$src\Loose\keep.txt"; 'k2' | Set-Content "$src\Loose\Sub\keep.txt"; 'x' | Set-Content "$src\Loose\skip.txt"; 'm' | Set-Content "$src\Loose\me & you.txt"
    $sources = @("$src\Docs", "$src\Loose\keep.txt", "$src\Loose\me & you.txt")
    $log = @{ Enabled = $false }
    foreach ($case in @(@('Robocopy', 'ps1', @('/E', '/R:0', '/W:0', '/NP')), @('Robocopy', 'bat', @('/E', '/R:0', '/W:0')), @('Xcopy', 'ps1', @('/E', '/I', '/Y', '/Q')), @('Xcopy', 'bat', @('/E', '/I', '/Y', '/Q')))) {
        $tool, $fmt, $sw = $case
        It "$tool $fmt copies the empty folder and only the picked files" {
            $root = Join-Path $TestDrive "out-$tool-$fmt"
            $r = New-CopyScript $tool $fmt $sources $root $sw $log
            foreach ($d in $r.Dirs) { [void][IO.Directory]::CreateDirectory($d) }
            [IO.File]::WriteAllText($r.File, $r.Text)
            if ($fmt -eq 'ps1') { & powershell -NoProfile -ExecutionPolicy Bypass -File $r.File | Out-Null } else { & cmd /c "`"$($r.File)`"" | Out-Null }
            $LASTEXITCODE | Should Be 0
            Test-Path "$root\Current\Docs\Empty" -PathType Container | Should Be $true
            Test-Path "$root\Current\Docs\Sub\b.txt" | Should Be $true
            Test-Path "$root\Current\Loose\keep.txt" | Should Be $true
            Test-Path "$root\Current\Loose\me & you.txt" | Should Be $true
            Test-Path "$root\Current\Loose\skip.txt" | Should Be $false
            Test-Path "$root\Current\Loose\Sub" | Should Be $false
        }
    }
    It 'files of one folder share one pair' { $r = New-CopyScript 'Robocopy' 'bat' $sources (Join-Path $TestDrive 'o2') @('/E') $log; ([regex]::Matches($r.Text, '(?m)^robocopy ')).Count | Should Be 2 }
    It 'the picker lists an empty folder (it can be ticked) and lists files without desktop.ini' {
        $d = Join-Path $TestDrive 'pick'; New-Item -ItemType Directory "$d\EmptyOne" -Force | Out-Null; 'f' | Set-Content "$d\f.txt"
        'i' | Set-Content "$d\desktop.ini"; (Get-Item "$d\desktop.ini").Attributes = 'Hidden, System'
        @(Get-SubFolders $d).Name | Should Be 'EmptyOne'
        @(Get-PickerFiles $d).Name | Should Be 'f.txt'
        (Get-PickerFiles (Join-Path $TestDrive 'nope')).Count | Should Be 0
    }
}
Describe 'Network paths (1.3)' {
    $map = @{ 'Z:' = '\\nas\backup'; 'Y:' = '\\srv\share\' }
    It 'a path on a mapped drive becomes its \\server\share path' { ConvertTo-UncPath 'z:\Docs\x' $map | Should Be '\\nas\backup\Docs\x' }
    It 'a mapped drive root becomes the share' { ConvertTo-UncPath 'Z:\' $map | Should Be '\\nas\backup'; ConvertTo-UncPath 'Y:' $map | Should Be '\\srv\share' }
    It 'local drives, UNC paths and empty input are left alone' {
        ConvertTo-UncPath 'C:\Users' $map | Should Be 'C:\Users'; ConvertTo-UncPath '\\a\b\c' $map | Should Be '\\a\b\c'; ConvertTo-UncPath '' $map | Should Be ''
        ConvertTo-UncPath 'Z:\x' @{} | Should Be 'Z:\x'
    }
    It 'a UNC share root is named after the share and keyed by server\share' { Get-PairName '\\nas\backup' @{} | Should Be 'backup'; Get-DriveKey '\\nas\backup\docs' | Should Be '\\NAS\BACKUP' }
    # real copies through the admin share of this PC (\\localhost\C$), read and written only under $TestDrive
    $unc = '\\localhost\' + ($TestDrive -replace ':', '$')
    $reach = Test-Path -LiteralPath $unc
    foreach ($case in @(@('Robocopy', 'ps1', @('/E', '/R:0', '/W:0', '/NP')), @('Xcopy', 'bat', @('/E', '/I', '/Y', '/Q')))) {
        $tool, $fmt, $sw = $case
        It "$tool ${fmt}: network folder and file as source, network folder as destination" -Skip:(-not $reach) {
            $s = Join-Path $TestDrive "net-$tool"; New-Item -ItemType Directory "$s\Share\Empty" -Force | Out-Null; 'n' | Set-Content "$s\Share\n.txt"; 'f' | Set-Content "$s\one.txt"; 'x' | Set-Content "$s\other.txt"
            $root = "$unc\net-$tool-out\AutomaticFileBackups"
            $r = New-CopyScript $tool $fmt @("$unc\net-$tool\Share", "$unc\net-$tool\one.txt") $root $sw @{ Enabled = $true; Mode = 'Append' }
            foreach ($d in $r.Dirs) { [void][IO.Directory]::CreateDirectory($d) }
            [IO.File]::WriteAllText($r.File, $r.Text)
            if ($fmt -eq 'ps1') { & powershell -NoProfile -ExecutionPolicy Bypass -File $r.File | Out-Null } else { Push-Location $TestDrive; & cmd /c "`"$($r.File)`"" | Out-Null; Pop-Location }
            $LASTEXITCODE | Should Be 0
            $out = "$TestDrive\net-$tool-out\AutomaticFileBackups\Current"
            Test-Path "$out\Share\n.txt" | Should Be $true
            Test-Path "$out\Share\Empty" -PathType Container | Should Be $true
            Test-Path "$out\net-$tool\one.txt" | Should Be $true
            Test-Path "$out\net-$tool\other.txt" | Should Be $false
            Test-Path "$TestDrive\net-$tool-out\AutomaticFileBackups\Logs\Backup-$tool.log" | Should Be $true
        }
    }
}
