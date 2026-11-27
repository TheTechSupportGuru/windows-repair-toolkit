# 7zEncryptor.Tests.ps1 - edge-case unit tests for 7z-Encryptor's helpers: 7-Zip arguments and quoting, names and
# save paths, the checks before encrypting, dropped items, mailto: links, mail program switches and the settings
# file. Needs no 7-Zip and shows no window. Nothing is written outside $TestDrive.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   Invoke-Pester .\tests\7zEncryptor.Tests.ps1
$encFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\7z-Encryptor.ps1'
$encAst = [Management.Automation.Language.Parser]::ParseFile($encFile, [ref]$null, [ref]$null)
foreach ($fn in $encAst.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'ConvertTo-ProcessArg', 'New-EncryptArgs', 'Get-ItemName', 'Get-ArchivePath', 'Test-EncryptInput', 'Get-MailtoUri', 'Get-MailProgramArgs', 'Get-DroppedItems', 'Get-SettingsFile', 'Read-Settings', 'Save-Settings', 'Remove-Settings', 'Get-UniqueFolders', 'Find-7Zip', 'Find-7ZipUnder', 'Test-WinPe' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
# the settings value types, read from the script itself so the test follows it
$typesAst = $encAst.Find({ $args[0] -is [Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -eq '$EncSettingTypes' }, $true)
$EncSettingTypes = & ([scriptblock]::Create($typesAst.Right.Extent.Text))
function Join-Out($r) { @($r) -join '|' }

Describe '7-Zip command line' {
    It 'arguments with spaces or quotes are quoted the Windows way; plain ones are left alone' {
        ConvertTo-ProcessArg 'plain' | Should Be 'plain'
        ConvertTo-ProcessArg 'a b' | Should Be '"a b"'
        ConvertTo-ProcessArg 'C:\a b\' | Should Be '"C:\a b\\"'
        ConvertTo-ProcessArg 'say "hi"' | Should Be '"say \"hi\""'
        ConvertTo-ProcessArg '' | Should Be '""'
    }
    It 'a password with spaces, & and a trailing backslash reaches 7-Zip whole' {
        $a = New-EncryptArgs 'C:\o.7z' @('C:\x') '7z' 'p w&x\' $true
        ConvertTo-ProcessArg $a[5] | Should Be '"-pp w&x\\"'
    }
    It 'items starting with - come after -- so 7-Zip never reads them as switches' {
        $a = New-EncryptArgs 'C:\o.7z' @('-rf.txt') '7z' 'pw' $true
        [array]::IndexOf($a, '--') | Should BeLessThan ([array]::IndexOf($a, '-rf.txt'))
    }
    It '7z without hidden names has no -mhe; zip never gets -mhe' {
        Join-Out (New-EncryptArgs 'o' @('a') '7z' 'p' $false) | Should Not Match 'mhe'
        Join-Out (New-EncryptArgs 'o' @('a') 'zip' 'p' $true) | Should Not Match 'mhe'
    }
}
Describe 'Names and where the file is saved' {
    It 'drive roots in any spelling are <letter>-Drive' { Get-ItemName 'c:' | Should Be 'C-Drive'; Get-ItemName 'D:\' | Should Be 'D-Drive'; Get-ItemName ' e:\ ' | Should Be 'E-Drive' }
    It 'a share root with a trailing backslash is the share name; a folder in a share is its own name' { Get-ItemName '\\nas\photos\' | Should Be 'photos'; Get-ItemName '\\nas\photos\2024' | Should Be '2024' }
    It 'a folder with a trailing backslash is named after the folder' { Get-ItemName 'C:\Data\Tax\' | Should Be 'Tax' }
    It 'a name with dots keeps them (only the format extension is added)' { Get-ArchivePath @("$TestDrive\my.report.v2.pdf") $TestDrive '7z' | Should Be "$TestDrive\my.report.v2.pdf.7z" }
    It 'empty entries are ignored: one real item is still named after it' { Get-ArchivePath @('', "$TestDrive\one.txt", $null) $TestDrive 'zip' | Should Be "$TestDrive\one.txt.zip" }
    It 'an existing file and its (2) are both skipped' {
        'x' | Set-Content "$TestDrive\a.txt.7z"; 'x' | Set-Content "$TestDrive\a.txt (2).7z"
        Get-ArchivePath @("$TestDrive\a.txt") $TestDrive '7z' | Should Be "$TestDrive\a.txt (3).7z"
    }
    It 'an existing FOLDER with the name is skipped too' { New-Item -ItemType Directory "$TestDrive\b.txt.zip" | Out-Null; Get-ArchivePath @("$TestDrive\b.txt") $TestDrive 'zip' | Should Be "$TestDrive\b.txt (2).zip" }
}
Describe 'Checks before encrypting' {
    BeforeEach { New-Item -ItemType Directory "$TestDrive\src\sub" -Force | Out-Null; 'x' | Set-Content "$TestDrive\src\f.txt" }
    It 'only empty entries counts as nothing added' { Test-EncryptInput @('', $null) 'a' 'a' "$TestDrive\o.7z" | Should Match 'Add at least one' }
    It 'a password that only differs in case is not the same' { Test-EncryptInput @("$TestDrive\src") 'Secret' 'secret' "$TestDrive\o.7z" | Should Match 'not the same' }
    It 'spaces only is a password (7-Zip takes it)' { Test-EncryptInput @("$TestDrive\src") '   ' '   ' "$TestDrive\o.7z" | Should Be '' }
    It 'zip: symbols and spaces are fine, a tab or an accent is refused' {
        Test-EncryptInput @("$TestDrive\src") 'a !#$%&()*+,-./:;<=>?@[\]^_{|}~' 'a !#$%&()*+,-./:;<=>?@[\]^_{|}~' "$TestDrive\o.zip" 'zip' | Should Be ''
        Test-EncryptInput @("$TestDrive\src") "a`tb" "a`tb" "$TestDrive\o.zip" 'zip' | Should Match 'zip password'
    }
    It 'a share path is a full path; a path without a drive or share is not' {
        Test-EncryptInput @("$TestDrive\src") 'a' 'a' '\\nas\share\o.7z' | Should Be ''
        Test-EncryptInput @("$TestDrive\src") 'a' 'a' '\o.7z' | Should Match 'full path'
        Test-EncryptInput @("$TestDrive\src") 'a' 'a' '\\nas\o.7z' | Should Match 'full path'
    }
    It 'saving over an item is refused' { Test-EncryptInput @("$TestDrive\src\f.txt") 'a' 'a' "$TestDrive\src\f.txt" | Should Match 'already exists|cannot replace' }
    It 'saving INSIDE a folder that is being encrypted is refused (any depth, any case)' {
        Test-EncryptInput @("$TestDrive\src") 'a' 'a' "$TestDrive\src\o.7z" | Should Match 'inside'
        Test-EncryptInput @("$TestDrive\src") 'a' 'a' ("$TestDrive\SRC\sub\o.7z") | Should Match 'inside'
        Test-EncryptInput @("$TestDrive\src\") 'a' 'a' "$TestDrive\src\o.7z" | Should Match 'inside'
    }
    It 'a folder whose name only starts the same is not "inside" (src2 next to src)' { Test-EncryptInput @("$TestDrive\src") 'a' 'a' "$TestDrive\src2\o.7z" | Should Be '' }
    It 'next to a dropped FILE is fine (its folder is not being encrypted)' { Test-EncryptInput @("$TestDrive\src\f.txt") 'a' 'a' "$TestDrive\src\f.txt.7z" | Should Be '' }
}
Describe 'Dropped items' {
    $ScriptDir = "$TestDrive\tool"
    It 'the tool''s own files are left out in any case, quoted, with spaces or a .\ in the path' {
        Join-Out (Get-DroppedItems @("`"$TestDrive\tool\7z-Encryptor.ps1`"", "$TestDrive\TOOL\7z-encryptor.BAT", " $TestDrive\tool\.\7z-Encryptor.ps1 ", "$TestDrive\x\..\tool\7z-Encryptor.ps1")) | Should Be ''
    }
    It 'other files, also one named 7z-Encryptor.ps1 in ANOTHER folder, are kept' {
        Join-Out (Get-DroppedItems @("$TestDrive\other\7z-Encryptor.ps1", "$TestDrive\a b.txt")) | Should Be "$TestDrive\other\7z-Encryptor.ps1|$TestDrive\a b.txt"
    }
    It 'empty, blank and "" entries are dropped; nothing dropped gives an empty list' {
        (Get-DroppedItems @('', '  ', '""')).Count | Should Be 0
        (Get-DroppedItems @()).Count | Should Be 0
        (Get-DroppedItems $null).Count | Should Be 0
    }
}
Describe 'mailto: links' {
    It 'subject and body are encoded; & # ? % in the file name cannot break the link' {
        $u = Get-MailtoUri 'a@x.org' 'C:\t\R&D #1 ?50%.7z'
        $u | Should Match '^mailto:a@x\.org\?subject=R%26D%20%231%20%3F50%25\.7z&body='
        ([regex]::Matches($u, '\?')).Count | Should Be 1
    }
    It 'a non-English file name is encoded as UTF-8' { Get-MailtoUri '' ('C:\t\f' + [char]0xFC + '.7z') | Should Match 'subject=f%C3%BC\.7z' }
    It 'commas, semicolons, spaces and empty parts between addresses are tidied' { Get-MailtoUri ' a@x.org ;; b@y.net, ' 'f.7z' | Should Match '^mailto:a@x\.org,b@y\.net\?' }
    It 'whitespace only means no address (allowed)' { Get-MailtoUri "  `t " 'f.7z' | Should Match '^mailto:\?subject=' }
    It 'refused: no @, two @, header tricks, quotes, angle brackets, a % escape' {
        foreach ($bad in 'nobody', 'a@b@c.org', 'a@x.org?cc=b@y.org', 'a@x.org&bcc=b@y.org', 'a@x.org#x', '"a"@x.org', '<a@x.org>', 'a%40x.org', '@x.org', 'a@') { Get-MailtoUri $bad 'f.7z' | Should Be $null }
    }
    It 'one good and one bad address is refused as a whole' { Get-MailtoUri 'a@x.org; nobody' 'f.7z' | Should Be $null }
}
Describe 'Mail program switches' {
    It 'Outlook and Thunderbird are found in any case and any folder' {
        Get-MailProgramArgs 'D:\Apps\Office\outlook.EXE' 'C:\a.7z' | Should Be '/a "C:\a.7z"'
        Get-MailProgramArgs 'C:\TB\THUNDERBIRD.exe' 'C:\a.7z' | Should Match '^-compose "attachment=''file:///C:/a\.7z''"$'
    }
    It 'a program that only contains the name (outlook-helper.exe) is not treated as Outlook' { Get-MailProgramArgs 'C:\outlook-helper.exe' 'C:\a.7z' | Should Be '"C:\a.7z"' }
    It 'Thunderbird gets a proper file URI for a share and for a name with # and spaces' {
        Get-MailProgramArgs 'thunderbird.exe' '\\nas\s\a b#1.7z' | Should Be ('-compose "attachment=''' + ([Uri]'\\nas\s\a b#1.7z').AbsoluteUri + '''"')
    }
}
Describe 'Settings file' {
    BeforeEach { $env:WRT_SETTINGS_DIR = "$TestDrive\set"; Remove-Item "$TestDrive\set" -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory "$TestDrive\set" | Out-Null }
    AfterEach { $env:WRT_SETTINGS_DIR = $null }
    $sf = "$TestDrive\set\7z-Encryptor.settings.json"
    It 'the mailto: address is one of the kept values; a wrong type is dropped' {
        [IO.File]::WriteAllText($sf, '{"Remember":true,"MailTo":["a@x.org"],"EmailMode":"Mailto"}')
        $s = Read-Settings '7z-Encryptor' $EncSettingTypes
        $s.ContainsKey('MailTo') | Should Be $false; $s.EmailMode | Should Be 'Mailto'
    }
    It 'unknown keys (like the old drop-window tick) are ignored' {
        [IO.File]::WriteAllText($sf, '{"Remember":true,"QuickNextToItem":true,"MailTo":"a@x.org"}')
        $s = Read-Settings '7z-Encryptor' $EncSettingTypes
        $s.ContainsKey('QuickNextToItem') | Should Be $false; $s.MailTo | Should Be 'a@x.org'
    }
    It 'a UTF-8 file with a byte order mark (saved by Notepad) still loads' {
        [IO.File]::WriteAllText($sf, '{"Remember":true,"SaveFolder":"C:\\x"}', (New-Object Text.UTF8Encoding $true))
        (Read-Settings '7z-Encryptor' $EncSettingTypes).SaveFolder | Should Be 'C:\x'
    }
    It 'Remember: 1 or "true" (not a real true) means no memory' {
        foreach ($j in '{"Remember":1,"SaveFolder":"C:\\x"}', '{"Remember":"true","SaveFolder":"C:\\x"}', '{"Remember":false,"SaveFolder":"C:\\x"}') { [IO.File]::WriteAllText($sf, $j); (Read-Settings '7z-Encryptor' $EncSettingTypes).Count | Should Be 0 }
    }
    It 'a settings FOLDER in place of the file, or a locked file, means no memory and no error' {
        New-Item -ItemType Directory $sf | Out-Null
        { Read-Settings '7z-Encryptor' $EncSettingTypes } | Should Not Throw
        (Read-Settings '7z-Encryptor' $EncSettingTypes).Count | Should Be 0
        Remove-Item $sf -Force
        [IO.File]::WriteAllText($sf, '{"Remember":true}'); $lock = [IO.File]::Open($sf, 'Open', 'ReadWrite', 'None')
        try { (Read-Settings '7z-Encryptor' $EncSettingTypes).Count | Should Be 0 } finally { $lock.Dispose() }
    }
    It 'saving to a folder that does not exist (read-only stick, gone share) fails quietly' {
        $env:WRT_SETTINGS_DIR = "$TestDrive\nope\deeper"
        { Save-Settings '7z-Encryptor' @{ Remember = $true; SaveFolder = 'C:\x' } } | Should Not Throw
        Test-Path "$TestDrive\nope" | Should Be $false
    }
    It 'save then read gives the same values back; remove deletes the file and is fine to repeat' {
        Save-Settings '7z-Encryptor' @{ Remember = $true; SaveFolder = 'C:\a [1]'; EmailMode = 'Mailto'; MailTo = 'a@x.org,b@y.net'; EmailProgram = 'C:\P\o.exe' }
        $s = Read-Settings '7z-Encryptor' $EncSettingTypes
        "$($s.SaveFolder)|$($s.EmailMode)|$($s.MailTo)|$($s.EmailProgram)" | Should Be 'C:\a [1]|Mailto|a@x.org,b@y.net|C:\P\o.exe'
        Remove-Settings '7z-Encryptor'; Test-Path $sf | Should Be $false
        { Remove-Settings '7z-Encryptor' } | Should Not Throw
    }
}
Describe 'Finding 7-Zip in Windows PE: X: and Y:, up to 3 folders deep (7z-Encryptor 1.5)' {
    function New-Fake7z($path) { New-Item -ItemType Directory (Split-Path $path) -Force | Out-Null; 'x' | Set-Content $path }
    It 'finds 7z.exe in a Hiren''s-style folder (Programs\7-Zip) and at the drive root' {
        $r = Join-Path $TestDrive 'pe1'; New-Fake7z "$r\Programs\7-Zip\7z.exe"
        Find-7ZipUnder $r | Should Be "$r\Programs\7-Zip\7z.exe"
        $r2 = Join-Path $TestDrive 'pe2'; New-Fake7z "$r2\7z.exe"
        Find-7ZipUnder $r2 | Should Be "$r2\7z.exe"
    }
    It 'takes the shallowest one first' {
        $r = Join-Path $TestDrive 'pe3'; New-Fake7z "$r\a\b\c\7z.exe"; New-Fake7z "$r\z\7z.exe"
        Find-7ZipUnder $r | Should Be "$r\z\7z.exe"
    }
    It 'goes 3 folders deep, not 4' {
        $r = Join-Path $TestDrive 'pe4'; New-Fake7z "$r\a\b\c\d\7z.exe"
        Find-7ZipUnder $r | Should Be $null
        New-Fake7z "$r\a\b\c\7z.exe"
        Find-7ZipUnder $r | Should Be "$r\a\b\c\7z.exe"
    }
    It 'skips Windows, boot and $ folders' {
        $r = Join-Path $TestDrive 'pe5'
        foreach ($d in 'Windows', 'Windows\System32', 'Boot', 'EFI', 'sources', '$Recycle.Bin', 'System Volume Information') { New-Fake7z "$r\$d\7z.exe" }
        Find-7ZipUnder $r | Should Be $null
    }
    It 'a missing drive, an empty root or a file as root gives nothing, without an error' {
        Find-7ZipUnder (Join-Path $TestDrive 'nothere') | Should Be $null
        Find-7ZipUnder '' | Should Be $null
        $f = Join-Path $TestDrive 'afile.txt'; 'x' | Set-Content $f
        Find-7ZipUnder $f | Should Be $null
    }
    It 'stops after the folder limit, so a big drive cannot hang the tool' {
        $r = Join-Path $TestDrive 'pe6'; foreach ($i in 1..9) { New-Item -ItemType Directory "$r\d$i" -Force | Out-Null }; New-Fake7z "$r\zz\7z.exe"
        Find-7ZipUnder $r 3 5 | Should Be $null
        Find-7ZipUnder $r 3 50 | Should Be "$r\zz\7z.exe"
    }
    It 'Find-7Zip looks on the PE drives only in Windows PE' {
        $r = Join-Path $TestDrive 'pe7'; New-Fake7z "$r\Program Files\7-Zip\7z.exe"
        $keep = @{ P = $env:ProgramFiles; X = ${env:ProgramFiles(x86)}; W = $env:ProgramW6432 }
        try {
            $env:ProgramFiles = $env:ProgramW6432 = Join-Path $TestDrive 'nopf'; ${env:ProgramFiles(x86)} = Join-Path $TestDrive 'nopf'
            Mock Get-ItemProperty { }; Mock Get-Command { }
            Find-7Zip @("$TestDrive\nothere", $r) $true | Should Be "$r\Program Files\7-Zip\7z.exe"
            Find-7Zip @($r) $false | Should Be $null
        } finally { $env:ProgramFiles = $keep.P; ${env:ProgramFiles(x86)} = $keep.X; $env:ProgramW6432 = $keep.W }
    }
    It 'Test-WinPe is false on a normal Windows' { if ($env:SystemDrive -ne 'X:') { Test-WinPe | Should Be $false } }
}
