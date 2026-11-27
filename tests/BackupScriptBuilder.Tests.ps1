# BackupScriptBuilder.Tests.ps1 - edge-case unit tests for Backup Script Builder's pure helpers (pair names, drive keys,
# log stamps, XML escaping, ticked-folder de-duplication, reading tasks back). Nothing is written outside $TestDrive.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   Invoke-Pester .\tests\BackupScriptBuilder.Tests.ps1
$bsbFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\BackupScriptBuilder.ps1'
$bsbAst = [Management.Automation.Language.Parser]::ParseFile($bsbFile, [ref]$null, [ref]$null)
foreach ($fn in $bsbAst.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'ConvertTo-XmlText', 'Get-PairName', 'Get-DriveKey', 'Get-LogStampFormat', 'Get-UniqueFolders', 'Get-ScriptFromAction', 'Get-ScriptType', 'New-CopyScript', 'Get-PickerFiles', 'Get-SubFolders', 'Test-SkipFolder', 'Test-SystemFolder', 'ConvertTo-UncPath', 'ConvertTo-ProcessArg', 'New-7ZipArgs', 'Invoke-BuiltinZip', 'Invoke-ManualBackup', 'Invoke-ManualCopy', 'Wait-BackupProcess', 'New-ManualScript', 'Find-7Zip', 'Find-7ZipUnder', 'Test-WinPe' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
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
Describe 'Manual backup: 7-Zip command line (1.3)' {
    It 'leaves simple arguments unquoted, quotes spaces and empty' { ConvertTo-ProcessArg 'simple' | Should Be 'simple'; ConvertTo-ProcessArg 'C:\My Docs' | Should Be '"C:\My Docs"'; ConvertTo-ProcessArg '' | Should Be '""' }
    It 'a trailing backslash is doubled only when the argument is quoted' { ConvertTo-ProcessArg 'path\to\' | Should Be 'path\to\'; ConvertTo-ProcessArg 'C:\My Docs\' | Should Be '"C:\My Docs\\"' }
    It 'quotes inside are escaped, backslashes before them doubled' { ConvertTo-ProcessArg 'say "hi"' | Should Be '"say \"hi\""'; ConvertTo-ProcessArg 'a\"b' | Should Be '"a\\\"b"' }
    It 'Store / Normal / Ultra are -mx=0 / 5 / 9' { foreach ($p in @(@('Store', 0), @('Normal', 5), @('Ultra', 9))) { (New-7ZipArgs 'o.7z' @('s') '7z' $p[0] '' '') -join '|' | Should Be "a|-t7z|-mx=$($p[1])|-y|-ssw|-bb1|--|o.7z|s" } }
    It 'zip with a password uses AES-256' { (New-7ZipArgs 'a.zip' @('f.txt') 'zip' 'Normal' 's3cret' '') -join '|' | Should Be 'a|-tzip|-mx=5|-y|-ssw|-bb1|-ps3cret|-mem=AES256|--|a.zip|f.txt' }
    It '7z with a password hides the names unless told not to' {
        (New-7ZipArgs 'a.7z' @('f') '7z' 'Ultra' 'pw' '') -join '|' | Should Be 'a|-t7z|-mx=9|-y|-ssw|-bb1|-ppw|-mhe=on|--|a.7z|f'
        (New-7ZipArgs 'a.7z' @('f') '7z' 'Ultra' 'pw' '' $false) -join '|' | Should Be 'a|-t7z|-mx=9|-y|-ssw|-bb1|-ppw|--|a.7z|f'
    }
    It 'self-extracting is always 7z and names the module' { (New-7ZipArgs 'a.exe' @('f') 'zip' 'Normal' '' 'C:\7-Zip\7z.sfx') -join '|' | Should Be 'a|-t7z|-mx=5|-y|-ssw|-bb1|-sfxC:\7-Zip\7z.sfx|--|a.exe|f' }
    It 'several sources, and "--" keeps a source starting with - from being read as a switch' { (New-7ZipArgs 'o.zip' @('a b', '-x') 'zip' 'Store' '' '') -join '|' | Should Be 'a|-tzip|-mx=0|-y|-ssw|-bb1|--|o.zip|a b|-x' }
}
Describe 'Manual backup: Windows zip and checks (1.3)' {
    $src = Join-Path $TestDrive 'msrc'; New-Item -ItemType Directory "$src\A\Empty", "$src\B" -Force | Out-Null
    [IO.File]::WriteAllText("$src\A\big.txt", ('x' * 200000)); 'b' | Set-Content "$src\B\b.txt"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    It 'Store keeps the size, Normal shrinks it' {
        $st = @{ Cancel = $false }
        (Invoke-BuiltinZip "$TestDrive\s.zip" @("$src\A") 'Store' $st).Ok | Should Be $true
        (Invoke-BuiltinZip "$TestDrive\n.zip" @("$src\A") 'Normal' $st).Ok | Should Be $true
        (Get-Item "$TestDrive\s.zip").Length | Should BeGreaterThan 200000
        (Get-Item "$TestDrive\n.zip").Length | Should BeLessThan 10000
    }
    It 'a locked file is listed as not backed up and the rest is still zipped' {
        $fs = [IO.File]::Open("$src\B\b.txt", 'Open', 'ReadWrite', 'None')
        try { $r = Invoke-BuiltinZip "$TestDrive\l.zip" @("$src\A", "$src\B") 'Normal' @{ Cancel = $false } } finally { $fs.Dispose() }
        $r.Ok | Should Be $false; @($r.Failed) -join '' | Should Match 'b\.txt$'
        $z = [IO.Compression.ZipFile]::OpenRead("$TestDrive\l.zip"); $n = @($z.Entries.FullName); $z.Dispose()
        ($n -contains 'A/big.txt') | Should Be $true
    }
    It 'two picked folders with the same name do not overwrite each other in the zip' {
        New-Item -ItemType Directory "$TestDrive\u1\Docs", "$TestDrive\u2\Docs" -Force | Out-Null; '1' | Set-Content "$TestDrive\u1\Docs\a.txt"; '2' | Set-Content "$TestDrive\u2\Docs\a.txt"
        [void](Invoke-BuiltinZip "$TestDrive\d.zip" @("$TestDrive\u1\Docs", "$TestDrive\u2\Docs") 'Normal' @{ Cancel = $false })
        $z = [IO.Compression.ZipFile]::OpenRead("$TestDrive\d.zip"); $n = @($z.Entries.FullName); $z.Dispose()
        (($n -contains 'Docs/a.txt') -and ($n -contains 'Docs-2/a.txt')) | Should Be $true
    }
    It 'an existing backup is never overwritten' { 'x' | Set-Content "$TestDrive\dup.zip"; { Invoke-BuiltinZip "$TestDrive\dup.zip" @("$src\B") 'Normal' @{ Cancel = $false } } | Should Throw }
    It '7z, zip by 7-Zip and self-extracting refuse to start without 7-Zip' {
        foreach ($o in @(@{ Mode = '7z' }, @{ Mode = 'Zip'; Engine = '7zip' }, @{ Mode = '7z'; Sfx = 'Windowed' })) {
            $o.Sources = @("$src\B"); $o.Dest = "$TestDrive\no7"; $o.SevenZip = $null; $o.Level = 'Normal'
            (Invoke-ManualBackup $o @{ Cancel = $false }).Message | Should Match '7-Zip is not installed'
        }
    }
}
Describe 'Manual backup: saved scripts really run (1.3), only into $TestDrive' {
    $src = Join-Path $TestDrive 'ssrc'; New-Item -ItemType Directory "$src\Docs\Empty", "$src\Pics" -Force | Out-Null
    [IO.File]::WriteAllText("$src\Docs\d.txt", ('hello ' * 20000)); 'p' | Set-Content "$src\Pics\p.txt"; 'x' | Set-Content "$src\Pics\x.txt"
    $z7 = Find-7Zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $cases = @(
        @{ N = 'folder'; Mode = 'Folder' }, @{ N = 'winzip-store'; Mode = 'Zip'; Engine = 'Windows'; Level = 'Store' }, @{ N = 'winzip-normal'; Mode = 'Zip'; Engine = 'Windows'; Level = 'Normal' },
        @{ N = 'zip7'; Mode = 'Zip'; Engine = '7zip'; Level = 'Normal'; Need7 = $true }, @{ N = '7z'; Mode = '7z'; Level = 'Ultra'; Need7 = $true }, @{ N = 'sfx'; Mode = '7z'; Level = 'Normal'; Sfx = 'Console'; Need7 = $true })
    foreach ($c in $cases) { foreach ($fmt in 'bat', 'ps1') {
        It "$($c.N) as .$fmt makes a backup with the folder, the empty folder and only the picked file" -Skip:($c.Need7 -and -not $z7) {
            $dest = Join-Path $TestDrive "sout-$($c.N)-$fmt"
            $o = @{} + $c; $o.Sources = @("$src\Docs", "$src\Pics\p.txt"); $o.Dest = $dest; $o.SevenZip = $z7
            $file = Join-Path $TestDrive "s-$($c.N).$fmt"; [IO.File]::WriteAllText($file, (New-ManualScript $o $fmt))
            if ($fmt -eq 'ps1') { & powershell -NoProfile -ExecutionPolicy Bypass -File $file | Out-Null } else { & cmd /c "`"$file`"" | Out-Null }
            $LASTEXITCODE | Should Be 0
            $made = @(Get-ChildItem $dest -Filter 'Backup-*'); $made.Count | Should Be 1; $made[0].Name | Should Match '^Backup-\d{4}-\d\d-\d\d_\d{6}'
            $m = $made[0].FullName
            if ($c.Mode -eq 'Folder') { $names = @(Get-ChildItem $m -Recurse | ForEach-Object { $_.FullName.Substring($m.Length + 1).Replace('\', '/') }) }
            elseif ($c.Engine -eq 'Windows') { $zz = [IO.Compression.ZipFile]::OpenRead($m); $names = @($zz.Entries | ForEach-Object { $_.FullName.TrimEnd('/') }); $zz.Dispose() }
            else { $names = @([regex]::Matches((& $z7 l -slt $m | Out-String), '(?m)^Path = (.+)$') | Select-Object -Skip 1 | ForEach-Object { $_.Groups[1].Value.Trim().Replace('\', '/') }) }
            ($names -contains 'Docs/d.txt') | Should Be $true
            ($names -contains 'Docs/Empty') | Should Be $true
            (@($names | Where-Object { $_ -match 'p\.txt$' }).Count) | Should Be 1
            (@($names | Where-Object { $_ -match 'x\.txt$' }).Count) | Should Be 0
            if ($c.N -eq 'sfx') { $m | Should Match '\.exe$' }
            if ($c.N -eq 'winzip-store') { (Get-Item $m).Length | Should BeGreaterThan 100000 }
            if ($c.N -eq 'winzip-normal') { (Get-Item $m).Length | Should BeLessThan 5000 }
        }
    } }
    It 'Windows zip (1.9): Windows'' own .NET zip, never tar.exe (not in Windows PE); Ultra is made as Normal, Store stays Store' {
        foreach ($fmt in 'bat', 'ps1') {
            $u = New-ManualScript @{ Mode = 'Zip'; Engine = 'Windows'; Level = 'Ultra'; Sources = @('C:\a', "D:\it's"); Dest = 'D:\b' } $fmt
            $u | Should Not Match '(?i)\btar(\.exe)?\b'
            $u | Should Match ([regex]::Escape("Invoke-BuiltinZip (`$Out + '.zip') @('C:\a', 'D:\it''s') 'Normal'"))
            $u | Should Match 'function Invoke-BuiltinZip \{'
            $u | Should Match 'function Get-PairName \{'
            $s = New-ManualScript @{ Mode = 'Zip'; Engine = 'Windows'; Level = 'Store'; Sources = @('C:\a'); Dest = 'D:\b' } $fmt
            $s | Should Match ([regex]::Escape("@('C:\a') 'Store'"))
        }
    }
    It 'a .bat (1.9) finds PowerShell itself: Windows PowerShell, else pwsh.exe on the PATH or on X: / Y: (Hiren''s PE 10)' {
        foreach ($c in @(@{ Mode = 'Zip'; Engine = 'Windows'; Level = 'Normal' }, @{ Mode = 'Folder' }, @{ Mode = '7z'; Level = 'Normal'; SevenZip = 'C:\7-Zip\7z.exe' })) {
            $o = @{} + $c; $o.Sources = @('C:\a'); $o.Dest = 'D:\b'
            $b = New-ManualScript $o 'bat'
            $b | Should Match ([regex]::Escape("for /f ""delims="" %%P in ('where pwsh.exe 2^>nul') do if not defined PS set ""PS=%%P"""))
            $b | Should Match ([regex]::Escape("for %%D in (X Y) do if not defined PS if exist %%D:\ for /f ""delims="" %%P in ('dir /s /b %%D:\pwsh.exe 2^>nul')"))
            $b | Should Match ([regex]::Escape("for /f %%a in ('call ""%PS%"" -NoProfile -Command"))
            $b | Should Not Match "\('powershell -NoProfile"
        }
        # the zip code sits after exit /b, where cmd never reads it
        $z = New-ManualScript @{ Mode = 'Zip'; Engine = 'Windows'; Level = 'Normal'; Sources = @('C:\a'); Dest = 'D:\b' } 'bat'
        $z.IndexOf('#BSB-ZIP-CODE') | Should BeGreaterThan $z.LastIndexOf('exit /b 0')
    }
    It 'a password is never written into the script; 7-Zip asks for it (-p)' {
        foreach ($fmt in 'bat', 'ps1') {
            $s = New-ManualScript @{ Mode = '7z'; Level = 'Normal'; Password = 'Secret#42'; Sources = @('C:\a'); Dest = 'D:\b'; SevenZip = 'C:\7-Zip\7z.exe' } $fmt
            $s | Should Not Match 'Secret#42'; $s | Should Match "(^| |')-p('| |$)"; $s | Should Match 'asks for the password'
        }
    }
    It 'a % in a path is doubled in a .bat, a quote doubled in a .ps1' {
        $o = @{ Mode = 'Folder'; Sources = @("C:\100% done"); Dest = "D:\Bob's"; SevenZip = $null }
        New-ManualScript $o 'bat' | Should Match 'C:\\100%% done'
        New-ManualScript $o 'ps1' | Should Match "D:\\Bob''s"
    }
}
Describe 'Finding 7-Zip in Windows PE: X: and Y:, up to 3 folders deep (Backup Script Builder 1.8)' {
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
