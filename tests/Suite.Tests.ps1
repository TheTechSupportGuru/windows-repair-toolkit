# Suite.Tests.ps1 - Phase 1 unit tests (Pester 3.4, Windows PowerShell 5.1)
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script .\Tests\Suite.Tests.ps1"
# Nothing here elevates, opens a GUI, or touches the system outside HKCU:\Software\WinFixKitHarnessTest and %TEMP%.
# diskpart / bcdedit / takeown / icacls / Start-Process are replaced by stub FUNCTIONS (functions win over .exe lookup).
# A FAILING test = a suspected bug. Test names say what SHOULD happen.

. (Join-Path $PSScriptRoot 'Harness.ps1')
$ST  = 'WinSuperTool.ps1'
$WRT = 'PS suite V1.1\WinRepairTool-startup.ps1'
$WFK = 'WinFixKit.ps1'

function Log($m) { }
function Msg($t, $c, $i) { $global:LastMsg = $t }

# ---------------------------------------------------------------------------------------------
Describe 'U1 diskpart allow-list blocks destructive commands' {
    foreach ($src in $ST, $WRT) {
        . ([scriptblock]::Create((Get-AssignText $src 'DpAllow')))
        . ([scriptblock]::Create((Get-FnText $src 'Invoke-Diskpart')))
        function diskpart.exe { $global:DpRan += , @(Get-Content -LiteralPath $args[1]); 'stub-ok' }

        $blocked = 'clean', 'clean all', 'format fs=ntfs quick', 'delete partition override', 'delete volume',
                   'create partition primary', 'convert gpt', 'convert mbr', 'select volume C', 'assign letter=C',
                   'remove letter=C', 'select disk 0 clean', "list disk`nclean", "select disk 0`r`nclean",
                   'online disk', 'offline disk', 'attributes disk clear readonly', 'active', 'inactive',
                   'set id=c12a7328-f81f-11d2-ba4b-00a0c93ec93b', 'gpt attributes=0x8000000000000001', 'shrink desired=100',
                   'extend', 'import', 'automount scrub', 'assign mount=C:\x', 'select volume C:'
        foreach ($c in $blocked) {
            It "[$src] blocks: $($c -replace "`r?`n", '\n')" {
                $global:DpRan = @()
                { Invoke-Diskpart @('list disk', $c) } | Should Throw 'Blocked diskpart command'
                $global:DpRan.Count | Should Be 0
            }
        }
        $allowed = 'list disk', 'LIST DISK', 'list partition', 'list volume', 'select disk 0', 'select disk 12',
                   'select partition 3', 'select volume E', 'detail partition', 'assign letter=E', 'remove letter=Z'
        foreach ($c in $allowed) {
            It "[$src] allows: $c" {
                $global:DpRan = @()
                { Invoke-Diskpart @($c) } | Should Not Throw
                $global:DpRan.Count | Should Be 1
            }
        }
        It "[$src] a trailing newline cannot smuggle a second command" {
            $global:DpRan = @()
            { Invoke-Diskpart @("assign letter=E`n") } | Should Not Throw
            @($global:DpRan[0] | Where-Object { $_ -and $_.Trim() }).Count | Should Be 1
        }
    }
}

# ---------------------------------------------------------------------------------------------
$bcdEn = @'
Windows Boot Loader
-------------------
identifier              {current}
device                  partition=C:
path                    \Windows\system32\winload.efi
description             Windows 11
locale                  en-US
osdevice                partition=C:
systemroot              \Windows
bootmenupolicy          Standard

Windows Boot Loader
-------------------
identifier              {0a1b2c3d-1111-2222-3333-444455556666}
device                  partition=C:
path                    \Windows\system32\winload.efi
description             Safe Mode (minimal) [WinSuperTool]
osdevice                partition=C:
systemroot              \Windows
safeboot                Minimal

Windows Boot Loader
-------------------
identifier              {9f9f9f9f-aaaa-bbbb-cccc-ddddeeeeffff}
device                  partition=\Device\HarddiskVolume7
description             Windows 10
osdevice                partition=\Device\HarddiskVolume7
'@ -replace "`r?`n", "`r`n"

# German bcdedit output: element names stay English, but the header and "identifier" are localized.
# (Sample written from known German output - confirm on a real German install.)
$bcdDe = @'
Windows-Startladeprogramm
-------------------------
Bezeichner              {current}
device                  partition=C:
path                    \Windows\system32\winload.efi
description             Windows 11
locale                  de-DE
osdevice                partition=C:
systemroot              \Windows
'@ -replace "`r?`n", "`r`n"

Describe 'U2 BCD text parsing (ConvertFrom-BcdText)' {
    . ([scriptblock]::Create((Get-FnText $ST 'ConvertFrom-BcdText')))
    $r = @(ConvertFrom-BcdText $bcdEn)
    It 'parses all 3 English entries' { $r.Count | Should Be 3 }
    It 'reads {current} on C:' { $r[0].Id | Should Be '{current}'; $r[0].Dev | Should Be 'C:' }
    It 'reads safeboot + description of the clone' { $r[1].Safeboot | Should Be 'Minimal'; $r[1].Desc | Should Be 'Safe Mode (minimal) [WinSuperTool]' }
    It 'leaves Dev empty for an unmounted \Device\ path (never matches a drive letter)' { $r[2].Dev | Should Be '' }
    It 'still finds the entry on German Windows (LOCALE)' { @(ConvertFrom-BcdText $bcdDe).Count | Should Be 1 }
    It 'German entry has the right id and drive' { $g = @(ConvertFrom-BcdText $bcdDe)[0]; $g.Id | Should Be '{current}'; $g.Dev | Should Be 'C:' }
    It 'WinRepairTool copy parses German too' {
        . ([scriptblock]::Create((Get-FnText $WRT 'ConvertFrom-BcdText')))
        @(ConvertFrom-BcdText $bcdDe).Count | Should Be 1
        @(ConvertFrom-BcdText $bcdEn).Count | Should Be 3
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U3 diskpart list parsing (diskpart mode of the Mount tab)' {
    . ([scriptblock]::Create((Get-FnText $ST 'Get-DiskpartRows', 'Get-DiskList', 'Get-PartList', 'Get-PartLetter', 'Fmt-Size')))
    try { . ([scriptblock]::Create((Get-FnText $ST 'Get-DpPartLetter'))) } catch { }   # V1.7+
    $rbStor = [pscustomobject]@{ Checked = $false }
    $enDisk = "`r`n  Disk ###  Status         Size     Free     Dyn  Gpt`r`n  --------  -------------  -------  -------  ---  ---`r`n  Disk 0    Online           40 GB  1024 KB        *`r`n  Disk 11   Online         2048 MB  1984 MB        *`r`n"
    $deDisk = "`r`n  Datenträger ###  Status         Größe    Frei     Dyn  GPT`r`n  ---------------  -------------  -------  -------  ---  ---`r`n  Datenträger 0    Online           40 GB  1024 KB        *`r`n"
    It 'English: finds Disk 0 and Disk 11' {
        function Invoke-Diskpart { $enDisk }
        $d = @(Get-DiskList); $d.Count | Should Be 2; $d[1].Num | Should Be 11
    }
    It 'German: still lists the disks (LOCALE)' {
        function Invoke-Diskpart { $deDisk }
        @(Get-DiskList).Count | Should Be 1
    }
    It 'list partition: ignores the "Disk 0 is now the selected disk" line and the header' {
        function Invoke-Diskpart { "`r`nDisk 0 is now the selected disk.`r`n`r`n  Partition ###  Type              Size     Offset`r`n  -------------  ----------------  -------  -------`r`n  Partition 1    Recovery           300 MB  1024 KB`r`n  Partition 2    System             100 MB   301 MB`r`n* Partition 4    Primary             38 GB   529 MB`r`n`r`nLeaving DiskPart...`r`n" }
        $p = @(Get-PartList 0); $p.Count | Should Be 3; $p[2].Num | Should Be 4
    }
    It 'German list partition still parses (LOCALE)' {
        function Invoke-Diskpart { "`r`nDatenträger 0 ist jetzt der gewählte Datenträger.`r`n`r`n  Partition ###  Typ               Größe    Offset`r`n  -------------  ----------------  -------  -------`r`n  Partition 1    Wiederherstellung  300 MB  1024 KB`r`n" }
        @(Get-PartList 0).Count | Should Be 1
    }
    It 'WinRepairTool copy lists German disks too' {
        . ([scriptblock]::Create((Get-FnText $WRT 'Get-DiskpartRows', 'Get-DiskList')))
        function Invoke-Diskpart { $deDisk }
        @(Get-DiskList).Count | Should Be 1
    }
    It 'reads the drive letter from detail partition' {
        function Invoke-Diskpart { "Partition 2`r`nType  : c12a7328`r`n`r`n  Volume ###  Ltr  Label        Fs     Type        Size     Status     Info`r`n  ----------  ---  -----------  -----  ----------  -------  ---------  --------`r`n* Volume 3     S                FAT32  Partition    100 MB  Healthy    System`r`n" }
        Get-PartLetter 0 2 | Should Be 'S'
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U4 Invoke-Bcd always backs up before changing the BCD' {
    . ([scriptblock]::Create((Get-FnText $ST 'Invoke-Bcd')))
    function Backup-Bcd($t) { $global:Backups++ }
    function bcdedit.exe { $global:LASTEXITCODE = 0; 'ok' }
    $t = @{ Store = $null; Id = '{current}' }
    # V1.3+: every verb except the read-only ones must back up first (V1.2 only covered the 5 verbs in use)
    foreach ($verb in '/set', '/copy', '/delete', '/deletevalue', '/import', '/default', '/displayorder', '/bootsequence', '/create', '/timeout', '/toolsdisplayorder', '/bootems', '/ems', '/bootdebug', '/debug', '/hypervisorsettings', '/createstore', '/mirror') {
        It "backs up before bcdedit $verb" {
            $global:Backups = 0
            [void](Invoke-Bcd $t @($verb, '{current}', 'x'))
            $global:Backups | Should Be 1
        }
    }
    It 'does NOT back up for read-only /enum' { $global:Backups = 0; [void](Invoke-Bcd $t @('/enum')); $global:Backups | Should Be 0 }
}

foreach ($src in $ST, $WRT) {
Describe "U4b a failed BCD backup stops the change [$src]" {
    . ([scriptblock]::Create((Get-FnText $src 'Invoke-Bcd', 'Backup-Bcd')))
    $BcdBackupDir = Join-Path $env:TEMP 'WST-harness-bcd'; $StateDir = $BcdBackupDir; $DataOnRam = $false
    It 'does not run /set when /export failed, and reports an error' {
        function bcdedit.exe { $global:BcdCalls += , ($args -join ' '); if ($args -contains '/export') { $global:LASTEXITCODE = 1; 'Access is denied.' } else { $global:LASTEXITCODE = 0; 'ok' } }
        $global:BcdCalls = @()
        $r = Invoke-Bcd @{ Store = $null } @('/set', '{current}', 'safeboot', 'minimal')
        @($global:BcdCalls | Where-Object { $_ -like '/set*' }).Count | Should Be 0
        $r.Rc | Should Not Be 0
    }
    It 'runs /set when the backup succeeded' {
        function bcdedit.exe { $global:BcdCalls += , ($args -join ' '); if ($args -contains '/export') { [IO.File]::WriteAllText($args[-1], 'x') }; $global:LASTEXITCODE = 0; 'ok' }
        $global:BcdCalls = @()
        $r = Invoke-Bcd @{ Store = $null } @('/set', '{current}', 'safeboot', 'minimal')
        @($global:BcdCalls | Where-Object { $_ -like '/set*' }).Count | Should Be 1
        $r.Rc | Should Be 0
    }
    Remove-Item -LiteralPath $BcdBackupDir -Recurse -Force -ErrorAction SilentlyContinue
}
}

# ---------------------------------------------------------------------------------------------
Describe 'U5 unattend.xml builder' {
    . ([scriptblock]::Create((Get-FnText $ST 'Build-Unattend')))
    $NL = "`r`n"
    function New-Fake($p) { [pscustomobject]$p }
    $txtUser = New-Fake @{ Text = 'Tech&Co $x' }; $txtPC = New-Fake @{ Text = 'PC-01' }; $txtLoc = New-Fake @{ Text = 'en-US' }
    $txtPass = New-Fake @{ Text = 'p<a>&ss"''word' }
    $chkSkip = New-Fake @{ Checked = $true }; $chkUser = New-Fake @{ Checked = $true }; $chkPC = New-Fake @{ Checked = $true }
    $chkRegion = New-Fake @{ Checked = $true }; $chkLogon = New-Fake @{ Checked = $true }; $chkNoExp = New-Fake @{ Checked = $true }
    $cmbTz = New-Fake @{ SelectedItem = 'Pacific Standard Time' }; $cmbGroup = New-Fake @{ SelectedItem = 'Administrators' }
    $x = Build-Unattend
    It 'produces well-formed XML with every option and special characters' { { [xml]$x } | Should Not Throw }
    $doc = [xml]$x
    It 'keeps the user name exactly' { $doc.unattend.settings[1].component[1].UserAccounts.LocalAccounts.LocalAccount.Name | Should BeExactly 'Tech&Co $x' }
    It 'encodes the password so Windows decodes it back' {
        $v = $doc.unattend.settings[1].component[1].UserAccounts.LocalAccounts.LocalAccount.Password.Value
        [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($v)) | Should BeExactly ('p<a>&ss"''word' + 'Password')
    }
    It 'FirstLogonCommand cannot get %VARIABLES% from the user name (user names with % are rejected)' {
        $txtUser.Text = 'a%TEMP%b'; Build-Unattend | Should BeNullOrEmpty; $txtUser.Text = 'Tech&Co $x'
    }
    It 'rejects a typographic apostrophe in the user name (would break the quoted FirstLogonCommand)' {
        $txtUser.Text = 'O' + [char]0x2019 + 'Brien'; Build-Unattend | Should BeNullOrEmpty; $txtUser.Text = 'Tech&Co $x'
    }
    It 'rejects a computer name longer than 15 characters' { $txtPC.Text = 'ABCDEFGHIJKLMNOP'; Build-Unattend | Should BeNullOrEmpty; $txtPC.Text = 'PC-01' }
    It 'rejects an apostrophe in the user name' { $txtUser.Text = "O'Brien"; Build-Unattend | Should BeNullOrEmpty; $txtUser.Text = 'Tech' }
}

# ---------------------------------------------------------------------------------------------
Describe 'U6 WinFixKit registry backup / restore round-trip (HKCU test key only)' {
    . ([scriptblock]::Create((Get-FnText $WFK 'ConvertTo-RegExePath', 'Get-BackupId', 'Get-RegVal', 'Backup-RegValue', 'Backup-RegKey', 'Set-RegValueSafe', 'Restore-RegBackup')))
    try { . ([scriptblock]::Create((Get-FnText $WFK 'Test-BackupPending'))) } catch { function Test-BackupPending($f) { Test-Path -LiteralPath $f } }   # V1.2 and older have no helper
    try { . ([scriptblock]::Create((Get-FnText $WFK 'ConvertTo-PlainText'))) } catch { }   # V1.6+
    $K = 'HKCU:\Software\WinFixKitHarnessTest'
    $script:RegKeyDir = Join-Path $env:TEMP ('wfk-harness-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:RegKeyDir -Force | Out-Null
    function Reset-Test { Remove-Item -LiteralPath $K -Recurse -Force -ErrorAction SilentlyContinue; Get-ChildItem $script:RegKeyDir | Remove-Item -Force }
    function Restore-Last { Get-ChildItem $script:RegKeyDir -Filter *.json | ForEach-Object { [void](Restore-RegBackup $_.FullName) } }
    function Raw($n) { (Get-Item -LiteralPath $K).GetValue($n, $null, 'DoNotExpandEnvironmentNames') }
    function Kind($n) { (Get-Item -LiteralPath $K).GetValueKind($n).ToString() }

    $cases = @(
        @{ N = 'DWord';        T = 'DWord';        Orig = 5;                       New = 1 },
        @{ N = 'DWordHighBit'; T = 'DWord';        Orig = -1;                      New = 0 },   # 0xFFFFFFFF
        @{ N = 'QWord';        T = 'QWord';        Orig = [int64]9007199254740993; New = 1 },
        @{ N = 'String';       T = 'String';       Orig = 'hello';                 New = 'x' },
        @{ N = 'Expand';       T = 'ExpandString'; Orig = '%SystemRoot%\x';        New = 'y' },
        @{ N = 'Multi';        T = 'MultiString';  Orig = [string[]]@('a', 'b');   New = 'z' },
        @{ N = 'MultiOne';     T = 'MultiString';  Orig = [string[]]@('only');     New = 'z' },
        @{ N = 'MultiEmpty';   T = 'MultiString';  Orig = [string[]]@();           New = 'z' },
        @{ N = 'Binary';       T = 'Binary';       Orig = [byte[]](1, 2, 255);     New = 0 }
    )
    foreach ($c in $cases) {
        It "restores $($c.N) ($($c.T)) exactly, including its type" {
            Reset-Test
            New-Item -Path $K -Force | Out-Null
            New-ItemProperty -LiteralPath $K -Name $c.N -Value $c.Orig -PropertyType $c.T -Force | Out-Null
            [void](Set-RegValueSafe $K $c.N $c.New 'DWord' 'test')
            Restore-Last
            Kind $c.N | Should Be $c.T
            ((@(Raw $c.N) | ForEach-Object { "$_" }) -join '|') | Should BeExactly ((@($c.Orig) | ForEach-Object { "$_" }) -join '|')
            @(Raw $c.N).Count | Should Be @($c.Orig).Count
        }
    }
    It 'removes a value that did not exist before the fix' {
        Reset-Test; New-Item -Path $K -Force | Out-Null
        [void](Set-RegValueSafe $K 'NewVal' 1 'DWord'); Restore-Last
        (Get-Item -LiteralPath $K).GetValueNames() -contains 'NewVal' | Should Be $false
    }
    It 'removes a key the fix created' {
        Reset-Test
        [void](Set-RegValueSafe "$K\Created" 'V' 1 'DWord'); Restore-Last
        Test-Path -LiteralPath "$K\Created" | Should Be $false
    }
    It 'after restore -> user change -> same fix again, restore returns the value from just before the 2nd fix' {
        Reset-Test; New-Item -Path $K -Force | Out-Null
        New-ItemProperty -LiteralPath $K -Name 'V' -Value 5 -PropertyType DWord -Force | Out-Null
        [void](Set-RegValueSafe $K 'V' 1 'DWord'); Restore-Last                       # back to 5
        Set-ItemProperty -LiteralPath $K -Name 'V' -Value 7                           # user/admin changes it later
        [void](Set-RegValueSafe $K 'V' 1 'DWord'); Restore-Last                       # fix again, then undo
        Raw 'V' | Should Be 7
    }
    It 'key export (Backup-RegKey) restores with reg import' {
        Reset-Test; New-Item -Path $K -Force | Out-Null
        New-ItemProperty -LiteralPath $K -Name 'A' -Value 'orig' -PropertyType String -Force | Out-Null
        [void](Backup-RegKey $K 'test'); Set-ItemProperty -LiteralPath $K -Name 'A' -Value 'changed'; Restore-Last
        Raw 'A' | Should Be 'orig'
    }
    It 'ConvertTo-RegExePath handles HKLM: and HKCU: (the only forms WinFixKit uses)' {
        ConvertTo-RegExePath 'HKLM:\SOFTWARE\X' | Should Be 'HKLM\SOFTWARE\X'
        ConvertTo-RegExePath 'HKCU:\Software\X' | Should Be 'HKCU\Software\X'
    }
    Reset-Test; Remove-Item -LiteralPath $script:RegKeyDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------------------------
Describe 'U7 small WinFixKit helpers' {
    . ([scriptblock]::Create((Get-FnText $WFK 'Rename-WithStamp', 'Get-FolderSizeMB')))
    It 'Get-FolderSizeMB says "not found" for a missing folder' { Get-FolderSizeMB 'C:\nope\nope' | Should Be 'not found' }
    It 'Rename-WithStamp renames and reports it' {
        $p = Join-Path $env:TEMP ('wfk-ren-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $p | Out-Null
        Rename-WithStamp $p | Should Match 'Renamed'
        Test-Path $p | Should Be $false
        Get-ChildItem $env:TEMP -Directory -Filter ((Split-Path $p -Leaf) + '.bak_*') | Remove-Item -Recurse -Force
    }
    It 'Rename-WithStamp says something when the path is missing (not silent)' { Rename-WithStamp 'C:\nope\nope' | Should Not BeNullOrEmpty }
}

# ---------------------------------------------------------------------------------------------
Describe 'U8a Take ownership + reset permissions refuses protected folders' {
    $run = Get-ActionRun $WFK 'Take ownership + reset permissions of a folder...'
    . ([scriptblock]::Create((Get-FnText $WFK 'Resolve-RealPath', 'Test-ProtectedFolder')))
    $script:ReportDir = $env:TEMP
    function takeown { $global:Took += , ($args -join ' '); $global:LASTEXITCODE = 0 }
    function icacls { $i = [array]::IndexOf($args, '/save'); if ($i -ge 0) { 'x' | Set-Content -LiteralPath $args[$i + 1] }; $global:LASTEXITCODE = 0 }   # V1.7 aborts without a real backup file
    $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder('C:\Program Files').ShortPath
    $protected = @('C:\', 'C:\Windows', 'C:\Windows\System32', 'C:\Program Files', 'C:\Program Files (x86)', 'C:\Users',
                   $short, 'C:\Documents and Settings', 'C:\ProgramData', 'C:\Users\All Users', $env:USERPROFILE, 'C:\Users\Default', 'C:\Users\Public',
                   'C:\Users\Default User', (Join-Path $env:USERPROFILE 'AppData'), (Join-Path $env:LOCALAPPDATA 'Temp'), 'C:\Recovery', 'C:\System Volume Information',
                   'C:\Documents and Settings\All Users', 'C:\Windows\..\ProgramData')
    foreach ($p in $protected) {
        It "refuses $p" {
            $global:Took = @()
            $out = (& $run $p) -join "`n"
            $global:Took.Count | Should Be 0
            $out | Should Match 'REFUSED'
        }
    }
    It 'allows a normal data folder (Documents subfolder)' {
        $global:Took = @()
        $f = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'wfk-own-test'; New-Item -ItemType Directory $f -Force | Out-Null
        [void](& $run $f); $global:Took.Count | Should Be 1
        Remove-Item $f -Force
    }
    It 'allows a data folder on the Desktop' {
        $global:Took = @()
        $f = Join-Path ([Environment]::GetFolderPath('Desktop')) 'wfk-own-test2'; New-Item -ItemType Directory $f -Force | Out-Null
        [void](& $run $f); $global:Took.Count | Should Be 1
        Remove-Item $f -Force
    }
}

Describe 'U8b Service Killer refuses services whose crash reboots Windows (live, read-only query)' {
    . ([scriptblock]::Create((Get-AssignText $WFK 'script:KillCritical')))
    $rebooters = foreach ($s in Get-CimInstance Win32_Service) {
        if ((sc.exe qfailure $s.Name 2>$null | Out-String) -match 'REBOOT\s+--\s+Delay') { $s.Name }
    }
    foreach ($n in $rebooters) {
        It "KillCritical contains $n (its recovery action is REBOOT)" { ($script:KillCritical -contains $n) | Should Be $true }
    }
    . ([scriptblock]::Create((Get-FnText $WFK 'Test-RebootOnFailure')))
    foreach ($n in $rebooters) {
        It "Test-RebootOnFailure (registry, language-independent) flags $n" { Test-RebootOnFailure $n | Should Be $true }
    }
    It 'Test-RebootOnFailure does not flag Spooler / missing services' {
        Test-RebootOnFailure 'Spooler' | Should Be $false
        Test-RebootOnFailure 'NoSuchService123' | Should Be $false
    }
    It 'reads the PID from English sc queryex output' {
        (sc.exe queryex Spooler | Out-String) -match 'PID\s*:\s*(\d+)' | Should Be $true
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U10 paths with a typographic apostrophe cannot break the spawned PowerShell code' {
    # PowerShell treats U+2018/U+2019 (‘ ’) as single quotes too, so escaping only ' is not enough.
    $evil = 'C:\Logs\O' + [char]0x2019 + 'Brien\app.log'
    function Get-ParsedP($code) {
        $t = $null; $e = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$t, [ref]$e)
        $a = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$p' }, $true)
        [pscustomobject]@{ Errors = $e.Count; Value = $(if ($a) { $a.Right.Expression.Value }) }
    }
    It 'WinSuperTool Esc-Sq + monitor template keeps the path intact' {
        . ([scriptblock]::Create((Get-FnText $ST 'Esc-Sq')))
        . ([scriptblock]::Create((Get-AssignText $ST 'tplFile')))
        $r = Get-ParsedP ($tplFile.Replace('__TITLE__', 'x').Replace('__TARGET__', (Esc-Sq $evil)).Replace('__TAIL__', '20'))
        $r.Errors | Should Be 0; $r.Value | Should BeExactly $evil
    }
    It 'Monitor-Logs.ps1 Esc keeps the path intact' {
        . ([scriptblock]::Create((Get-FnText 'PS suite V1.1\Monitor-Logs.ps1' 'Esc')))
        $r = Get-ParsedP ("`$p = '" + (Esc $evil) + "'")
        $r.Errors | Should Be 0; $r.Value | Should BeExactly $evil
    }
    It 'WinFixKit ConvertTo-SqEscaped (used by Start-InWindow) keeps the path intact' {
        . ([scriptblock]::Create((Get-FnText $WFK 'ConvertTo-SqEscaped')))
        $r = Get-ParsedP ("`$p = '" + (ConvertTo-SqEscaped ($evil + "\it's")) + "'")
        $r.Errors | Should Be 0; $r.Value | Should BeExactly ($evil + "\it's")
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U0 edited scripts stay pure ASCII (no BOM -> Windows PowerShell 5.1 reads them as ANSI)' {
    foreach ($rel in $WFK, $ST, $WRT, 'PS suite V1.1\Collect-Logs.ps1', 'PS suite V1.1\Monitor-Logs.ps1', 'PS suite V1.1\ClaudeLogAnalyzer.ps1') {
        It "$rel has no non-ASCII characters" {
            $p = Resolve-SuitePath $rel
            ([regex]::Matches([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), '[^\x00-\x7F]')).Count | Should Be 0
        }
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U16 BCD restore safety (V1.4)' {
    foreach ($src in $ST, $WRT) {
        . ([scriptblock]::Create((Get-FnText $src 'Invoke-Bcd', 'Restore-BcdBackup')))
        $NL = "`r`n"
        function Backup-Bcd($t) { $global:Bk++; $true }
        It "[$src] offline store: restore is a verified file copy over a hidden+system BCD file" {
            $d = Join-Path $env:TEMP ('bcdr-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
            [IO.File]::WriteAllBytes("$d\BCD", [byte[]](1, 2, 3)); [IO.File]::SetAttributes("$d\BCD", 'Hidden,System')
            [IO.File]::WriteAllBytes("$d\backup.bak", [byte[]](9, 8, 7, 6))
            $global:Bk = 0
            $r = Restore-BcdBackup @{ Store = "$d\BCD" } "$d\backup.bak"
            $r.Rc | Should Be 0
            ([IO.File]::ReadAllBytes("$d\BCD") -join ',') | Should Be '9,8,7,6'
            ([IO.File]::GetAttributes("$d\BCD").ToString()) | Should Match 'Hidden'
            $global:Bk | Should Be 1
            Remove-Item $d -Recurse -Force
        }
        It "[$src] missing backup file -> error, nothing touched" { (Restore-BcdBackup @{ Store = 'C:\nope\BCD' } 'C:\nope\x.bak').Rc | Should Be 1 }
        It "[$src] Backup-Bcd of an OFFLINE store is a file copy (bcdedit /store + /export is not supported)" {
            . ([scriptblock]::Create((Get-FnText $src 'Backup-Bcd')))
            $d = Join-Path $env:TEMP ('bcdb-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
            $BcdBackupDir = "$d\bk"; $StateDir = $d; $DataOnRam = $false
            [IO.File]::WriteAllBytes("$d\BCD", [byte[]](5, 6, 7)); [IO.File]::SetAttributes("$d\BCD", 'Hidden,System')
            function bcdedit.exe { $global:BcdeditCalled = $true; $global:LASTEXITCODE = 1 }
            $global:BcdeditCalled = $false
            Backup-Bcd @{ Store = "$d\BCD" } | Should Be $true
            $global:BcdeditCalled | Should Be $false
            $bk = @(Get-ChildItem $d -Recurse -Filter 'BCD_*.bak')
            $bk.Count | Should Be 1
            ([IO.File]::ReadAllBytes($bk[0].FullName) -join ',') | Should Be '5,6,7'
            Remove-Item $d -Recurse -Force
            . ([scriptblock]::Create('function Backup-Bcd($t) { $global:Bk++; $true }'))
        }
        It "[$src] a failed live command that CLOSES the system store blocks every later BCD action" {
            $script:BcdLoadedAtStart = $true; $script:BcdStoreLost = $false
            function bcdedit.exe { $global:Ran++; $global:LASTEXITCODE = 1; 'The store import operation has failed.' }
            function Test-Path { param($LiteralPath, $Path) if ("$Path$LiteralPath" -eq 'HKLM:\BCD00000000') { return $false }; Microsoft.PowerShell.Management\Test-Path @PSBoundParameters }
            function Msg($t, $c, $i) { $global:WarnShown = $t }
            $global:Ran = 0; $global:WarnShown = ''
            $r = Invoke-Bcd @{ Store = $null } @('/import', 'x.bak')
            $script:BcdStoreLost | Should Be $true
            $global:WarnShown | Should Match 'CLOSED'
            $r2 = Invoke-Bcd @{ Store = $null } @('/set', '{current}', 'safeboot', 'minimal')
            $r2.Rc | Should Be 1; $r2.Out | Should Match 'Restart Windows'
            $global:Ran | Should Be 1        # the second command never reached bcdedit
            Remove-Item Function:\Test-Path; $script:BcdStoreLost = $false
        }
    }
}

Describe 'U17 Mount safety (V1.4): MSR refused, empty letter refused' {
    foreach ($src in $ST, $WRT) {
        . ([scriptblock]::Create((Get-FnText $src 'Sync-StorageCache', 'Test-IsMsr', 'Mount-Part', 'Dismount-One', 'Test-LetterUsed')))
        $rbStor = [pscustomobject]@{ Checked = $true }
        $msr = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'Reserved' | Select-Object -First 1).PartitionNumber
        $esp = (Get-Partition -DiskNumber 0 | Where-Object Type -eq 'System' | Select-Object -First 1).PartitionNumber
        # an MBR disk (Legacy BIOS PC) has no MSR and no EFI partition: nothing to check there (seen on the Windows 10 test PC)
        It "[$src] Test-IsMsr: disk 0 partition $msr (MSR) = true, partition $esp (EFI) = false" -Skip:(-not $msr) {
            Test-IsMsr 0 $msr | Should Be $true
            Test-IsMsr 0 $esp | Should Be $false
        }
        It "[$src] Mount-Part refuses the MSR before touching anything" -Skip:(-not $msr) {
            function Add-PartitionAccessPath { $global:Assigned++ }
            $global:Assigned = 0
            { Mount-Part 0 $msr 'S' } | Should Throw 'Microsoft Reserved'
            $global:Assigned | Should Be 0
        }
        It "[$src] Dismount-One refuses an entry without a drive letter" {
            $script:Mounts = New-Object Collections.ArrayList
            Dismount-One ([pscustomobject]@{ Letter = $null }) | Should Be $false
            Dismount-One ([pscustomobject]@{ Letter = '' }) | Should Be $false
        }
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U18 WinFixKit "Test access to a PC / NAS" (V1.5: #22 #24)' {
    $run = Get-ActionRun $WFK 'Test access to a PC / NAS by name or IP...'
    function Test-TcpPort($h, $p, $t) { $p -eq 445 }
    It 'IP target: no "Name lookup: OK ()", says lookup not needed' {
        function Resolve-DnsName { [pscustomobject]@{ NameHost = 'box.lan'; IPAddress = $null } }
        function net.exe { $global:LASTEXITCODE = 0; 'There are no entries in the list.' }
        $o = (& $run '192.168.1.25') -join "`n"
        $o | Should Match 'not needed \(target is an IP address\); reverse name: box\.lan'
        $o | Should Not Match 'OK \(\)'
    }
    It 'name whose first DNS answer is a CNAME still shows the IP' {
        function Resolve-DnsName { [pscustomobject]@{ NameHost = 'real.lan'; IPAddress = $null }, [pscustomobject]@{ IPAddress = '10.0.0.5' } }
        function net.exe { $global:LASTEXITCODE = 0; 'Share name  Type' }
        (& $run 'nas') -join "`n" | Should Match 'Name lookup: OK \(10\.0\.0\.5\)'
    }
    It 'share list OK when net view succeeds (no more "Open \\host : FAILED")' {
        function Resolve-DnsName { [pscustomobject]@{ IPAddress = '10.0.0.5' } }
        function net.exe { $global:LASTEXITCODE = 0; 'Share name  Type' }
        $o = (& $run '\\nas') -join "`n"
        $o | Should Match 'Share list \(net view \\\\nas\): OK'
        $o | Should Not Match 'FAILED'
    }
    It 'share list FAILED with the exit code when net view fails' {
        function Resolve-DnsName { throw 'no such host' }
        function net.exe { $global:LASTEXITCODE = 2; 'System error 53 has occurred.' }
        $o = (& $run 'ghost') -join "`n"
        $o | Should Match 'Name lookup: failed'
        $o | Should Match 'FAILED \(exit code 2\)'
    }
}

Describe 'U19 WinFixKit "Rebuild search index" deletes the Windows 10 AND Windows 11 index files (V1.5: #23)' {
    $run = Get-ActionRun $WFK 'Rebuild search index'
    function StopSvc($n) { } ; function StartSvc($n) { } ; function Set-RegValueSafe { }
    try { . ([scriptblock]::Create((Get-FnText $WFK 'Get-SearchIndexDir'))) } catch { }   # V1.7+
    $fake = Join-Path $env:TEMP ('pd-' + [guid]::NewGuid().ToString('N')); $dir = "$fake\Microsoft\Search\Data\Applications\Windows"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $del = 'Windows.db', 'Windows.db-wal', 'Windows.db-shm', 'Windows-gather.db', 'Windows-usn.db', 'Windows.edb'
    $keep = 'MSS.log', 'Windows.jfm', 'notes.txt'
    foreach ($n in $del + $keep) { 'x' | Set-Content "$dir\$n" }
    $old = $env:ProgramData; $env:ProgramData = $fake
    try { $out = (& $run) -join "`n" } finally { $env:ProgramData = $old }
    It 'deletes every index database file (.edb, .db, -gather/-usn, -wal/-shm)' { foreach ($n in $del) { Test-Path "$dir\$n" | Should Be $false } }
    It 'leaves other files alone' { foreach ($n in $keep) { Test-Path "$dir\$n" | Should Be $true } }
    It 'reports what it deleted' { $out | Should Match 'Deleted Windows\.db' }
    Remove-Item $fake -Recurse -Force
}

# ---------------------------------------------------------------------------------------------
Describe 'U20 WinFixKit network reset + restore messages (V1.6: #31 #32 #33)' {
    . ([scriptblock]::Create((Get-FnText $WFK 'ConvertTo-PlainText', 'Restore-RegBackup', 'Invoke-IpReset', 'Invoke-WinsockReset')))
    $script:RegKeyDir = Join-Path $env:TEMP ('wfk-u20-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $script:RegKeyDir | Out-Null
    $script:LogDir = $script:RegKeyDir
    'x' | Set-Content "$script:RegKeyDir\k.reg"
    function New-KeyJson { '{"Type":"Key","Key":"HKLM:\\SOFTWARE\\X","RegFile":"k.reg","RestoredAt":null}' | Set-Content "$script:RegKeyDir\k.json" }
    It '#31 a successful reg import that writes to stderr shows plain text, no NativeCommandError, and is marked restored' {
        New-KeyJson
        function reg.exe { Write-Error 'The operation completed successfully.'; $global:LASTEXITCODE = 0 }
        $o = (Restore-RegBackup "$script:RegKeyDir\k.json" 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $o | Should Match 'Imported the original export'
        $o | Should Not Match 'NativeCommandError|CategoryInfo|FullyQualifiedErrorId'
        (Get-Content "$script:RegKeyDir\k.json" -Raw | ConvertFrom-Json).RestoredAt | Should Not BeNullOrEmpty
    }
    It '#31 a FAILED reg import says FAILED with the exit code and is NOT marked restored' {
        New-KeyJson
        function reg.exe { Write-Error 'ERROR: Error accessing the registry.'; $global:LASTEXITCODE = 1 }
        $o = (Restore-RegBackup "$script:RegKeyDir\k.json" 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $o | Should Match 'FAILED .* exit code 1'
        $o | Should Not Match 'Imported the original'
        (Get-Content "$script:RegKeyDir\k.json" -Raw | ConvertFrom-Json).RestoredAt | Should BeNullOrEmpty
    }
    It '#32 TCP/IP reset counts "failed" items, explains them, and is honest about the missing log' {
        function netsh.exe { 'Resetting Global, OK!'; 'Resetting , failed.'; Write-Error 'Access is denied.'; 'Resetting , OK!'; $global:LASTEXITCODE = 1 }
        $o = (Invoke-IpReset) -join "`n"
        $o | Should Match 'reported 1 item\(s\) as failed \(exit code 1\)'
        $o | Should Match 'normal'
        $o | Should Match 'did not write its own log'
        $o | Should Not Match 'NativeCommandError'
    }
    It '#32 a clean TCP/IP reset adds no NOTE' {
        function netsh.exe { 'Resetting Global, OK!'; $global:LASTEXITCODE = 0 }
        (Invoke-IpReset) -join "`n" | Should Not Match 'NOTE'
    }
    It '#33 Winsock reset names providers the rebuilt catalog dropped (RFCOMM = Bluetooth)' {
        $global:Calls = 0
        function Get-ItemProperty { $global:Calls++; if ($global:Calls -eq 1) { [pscustomobject]@{ 'Provider List' = @('RFCOMM', 'Tcpip6', 'Tcpip') } } else { [pscustomobject]@{ 'Provider List' = @('Tcpip6', 'Tcpip') } } }
        function netsh.exe { 'Sucessfully reset the Winsock Catalog.'; $global:LASTEXITCODE = 0 }
        $o = (Invoke-WinsockReset) -join "`n"
        $o | Should Match 'no longer lists these providers: RFCOMM'
        $o | Should Match 'Bluetooth'
    }
    Remove-Item $script:RegKeyDir -Recurse -Force
}

# ---------------------------------------------------------------------------------------------
Describe 'U21 V1.7 language-independent parsers (diskpart letter, powercfg, firewall profile filter)' {
    . ([scriptblock]::Create((Get-FnText $ST 'Get-DpPartLetter')))
    $en = "Partition 2`r`nType  : c12a7328`r`n`r`n  Volume ###  Ltr  Label        Fs     Type        Size     Status     Info`r`n  ----------  ---  -----------  -----  ----------  -------  ---------  --------`r`n* Volume 3     S   EFI          FAT32  Partition    100 MB  Healthy    System`r`n"
    $de = "Partition 2`r`nTyp  : c12a7328`r`n`r`n  Volume ###  Bst  Bezeichnung  DS     Typ         Groesse  Status     Info`r`n  ----------  ---  -----------  -----  ----------  -------  ---------  --------`r`n* Volume 3     T   EFI          FAT32  Partition    100 MB  Fehlerfre  System`r`n"
    $noLetter = "Partition 5`r`n`r`n  Volume ###  Ltr  Label        Fs     Type        Size     Status     Info`r`n  ----------  ---  -----------  -----  ----------  -------  ---------  --------`r`n* Volume 4         Recovery     NTFS   Partition    892 MB  Healthy    Hidden`r`n"
    $noVol = "Partition 3`r`nType  : e3c9e316-0b5c-4db8-817d-f92df00215ae`r`nHidden: Yes`r`n`r`nThere is no volume associated with this partition.`r`n"
    It 'English detail partition -> S' { Get-DpPartLetter 0 2 $en | Should BeExactly 'S' }
    It 'German detail partition -> T (no English words needed)' { Get-DpPartLetter 0 2 $de | Should BeExactly 'T' }
    It 'volume without a letter -> empty (a one-word label is not mistaken for a letter)' { Get-DpPartLetter 0 5 $noLetter | Should BeExactly '' }
    It 'no volume table at all -> NOVOLUME' { Get-DpPartLetter 0 3 $noVol | Should BeExactly 'NOVOLUME' }

    . ([scriptblock]::Create((Get-FnText $WFK 'Get-PowerSettings')))
    It 'Get-PowerSettings reads GERMAN powercfg output (only GUIDs and hex values)' {
        function powercfg { @(
            'GUID des Energieschemas: 381b4222-f694-41f0-9685-ff5bb260df2e  (Ausbalanciert)',
            '  GUID der Untergruppe: 238c9fa8-0aad-41ed-83f4-97be242c8f20  (Energie sparen)',
            '    GUID-Alias: SUB_SLEEP',
            '    Energieeinstellungs-GUID: 29f6c1db-86da-48c5-9fdb-f2b67b1f44da  (Standbymodus nach)',
            '      GUID-Alias: STANDBYIDLE',
            '      Minimale moegliche Einstellung: 0x00000000',
            '      Maximale moegliche Einstellung: 0xffffffff',
            '      Moegliche Einstellungsschritte: 0x00000001',
            '      Einheiten moeglicher Einstellungen: Sekunden',
            '    Index der aktuellen Wechselstromeinstellung: 0x00000384',
            '    Index der aktuellen Gleichstromeinstellung: 0x0000012c') }
        $o = @(Get-PowerSettings SUB_SLEEP)
        $o.Count | Should Be 2
        $o[0] | Should Match 'Standbymodus nach\s+AC: raw 900'
        $o[1] | Should Match 'DC: raw 300'
    }
    It 'firewall: only rules that never apply to Public are selected (Any=0 Domain=1 Private=2 Public=4)' {
        $rules = 0, 1, 2, 3, 4, 5, 6, 7 | ForEach-Object { [pscustomobject]@{ Profile = $_ } }
        $sel = @($rules | Where-Object { $pf = [int]$_.Profile; $pf -ne 0 -and -not ($pf -band 4) } | ForEach-Object Profile)
        ($sel -join ',') | Should Be '1,2,3'
    }
    It 'WinFixKit enables rules by group resource ID, never with Set-NetFirewallRule -Profile' {
        $code = @([IO.File]::ReadAllLines((Resolve-SuitePath $WFK)) | Where-Object { $_.TrimStart() -notlike '#*' })   # ignore comments
        @($code | Where-Object { $_ -match 'Set-NetFirewallRule[^\r\n]*-Profile' }).Count | Should Be 0
        ($code -join "`n") | Should Match '@FirewallAPI\.dll,-32752'
    }
}

Describe 'U22 V1.7 WinFixKit safety: failed value restore, take-ownership backup, wrong-user' {
    . ([scriptblock]::Create((Get-FnText $WFK 'ConvertTo-PlainText', 'Restore-RegBackup')))
    $script:RegKeyDir = Join-Path $env:TEMP ('wfk-u22-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $script:RegKeyDir | Out-Null
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    It 'a value restore that cannot write (HKLM, not admin) says FAILED and is NOT marked restored' {
        if ($isAdmin) { return }    # only meaningful without admin rights
        '{"Type":"Value","Key":"HKLM:\\SOFTWARE\\WinFixKitU22DenyTest","Name":"V","KeyExisted":false,"Existed":true,"Kind":"DWord","Data":1,"RestoredAt":null}' | Set-Content "$script:RegKeyDir\v.json"
        $o = (Restore-RegBackup "$script:RegKeyDir\v.json") -join ' '
        $o | Should Match 'FAILED'
        (Get-Content "$script:RegKeyDir\v.json" -Raw | ConvertFrom-Json).RestoredAt | Should BeNullOrEmpty
    }
    Remove-Item $script:RegKeyDir -Recurse -Force
    It 'take ownership aborts BEFORE takeown when the permission backup fails' {
        $run = Get-ActionRun $WFK 'Take ownership + reset permissions of a folder...'
        . ([scriptblock]::Create((Get-FnText $WFK 'Resolve-RealPath', 'Test-ProtectedFolder')))
        $script:ReportDir = $env:TEMP
        function icacls { $global:LASTEXITCODE = 5; 'Access is denied.' }
        function takeown { $global:Took++ }
        $global:Took = 0
        $f = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'wfk-u22'; New-Item -ItemType Directory $f -Force | Out-Null
        $o = (& $run $f) -join ' '
        Remove-Item $f -Force
        $o | Should Match 'ABORTED'
        $global:Took | Should Be 0
    }
    It 'Get-WrongUserWarning is silent when the tool runs as the signed-in user' {
        . ([scriptblock]::Create((Get-FnText $WFK 'Get-WrongUserWarning')))
        Get-WrongUserWarning | Should BeNullOrEmpty
    }
}

Describe 'U23 V1.7 WinSuperTool: AI request survives bad files; mount ownership re-check' {
    . ([scriptblock]::Create((Get-FnText $ST 'Read-TextTail', 'Read-LogForAi', 'Get-ImagePart', 'ConvertTo-JsonText', 'New-AiRequest')))
    foreach ($v in 'AiImageTypes', 'AiConvertTypes', 'AiMaxTotalChars', 'AiMaxFileChars', 'AiMaxImageBytes', 'AiMaxTotalImageB64', 'AiImageMaxEdge', 'AiModelClaude', 'AiSystemPrompt') { try { . ([scriptblock]::Create((Get-AssignText $ST $v))) } catch { } }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $d = Join-Path $env:TEMP ('ai-u23-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
    $null = & wevtutil.exe epl System "$d\empty.evtx" '/q:*[System[(EventID=65000)]]' 2>&1      # a real but EMPTY event log
    [IO.File]::WriteAllBytes("$d\broken.png", [byte[]](1, 2, 3, 4))                                # not a picture
    'line 1' | Set-Content "$d\ok.log"
    $aiFiles = @("$d\empty.evtx", "$d\broken.png", "$d\ok.log"); $script:ApiKey = 'sk-ant-test'
    $txtPrompt = [pscustomobject]@{ Text = '' }; $lblAiStatus = [pscustomobject]@{ Text = '' }
    It 'empty .evtx is read as "(this event log contains no events)", not an exception' {
        (Read-LogForAi "$d\empty.evtx" 1000).Text | Should Match 'contains no events'
    }
    It 'a broken image and an empty log do not cancel the request; the image is listed as not sent' {
        $req = New-AiRequest $false
        $body = [Text.Encoding]::UTF8.GetString($req.Body)
        $body | Should Match 'line 1'
        $body | Should Match 'not sent \(Image ''broken\.png'''
        { $body | ConvertFrom-Json } | Should Not Throw
    }
    It 'Claude request uses max_tokens 16000 and the refusal fallback (beta header)' {
        $req = New-AiRequest $false
        [Text.Encoding]::UTF8.GetString($req.Body) | Should Match '"max_tokens":16000,"fallbacks":"default"'
        $req.Headers['anthropic-beta'] | Should Be 'server-side-fallback-2026-07-01'
    }
    It 'evtx text longer than the cap keeps the START (newest events + header)' {
        $null = & wevtutil.exe epl System "$d\sys.evtx" '/q:*[System[(Level=1 or Level=2 or Level=3)]]' 2>&1   # readable copy
        if (-not (Test-Path "$d\sys.evtx")) { return }
        $r = Read-LogForAi "$d\sys.evtx" 300
        $r.Truncated | Should Be $true
        $r.Text | Should Match '^(Critical|Newest)'
    }
    Remove-Item $d -Recurse -Force

    . ([scriptblock]::Create((Get-FnText $ST 'Dismount-One', 'Test-LetterUsed')))
    It 'Dismount-One forgets (and does NOT unmount) a letter that now belongs to another partition' {
        function Get-LetterPartition($L) { [pscustomobject]@{ DiskNumber = 0; PartitionNumber = 4 } }   # C: is disk 0 / partition 4
        function Unmount-Letter($L) { $global:Unmounted = $L }
        function Log($m) { $global:LastLog = $m }
        $global:Unmounted = $null
        $script:Mounts = New-Object Collections.ArrayList
        $m = [pscustomobject]@{ Letter = 'D'; Disk = 1; Partition = 2 }; [void]$script:Mounts.Add($m)   # D: exists on this VM (CD)
        Dismount-One $m | Should Be $false
        $global:Unmounted | Should BeNullOrEmpty
        $script:Mounts.Count | Should Be 0
        $global:LastLog | Should Match 'NOT unmounting'
    }
}

Describe 'U24 V1.7 QR pairing: a client trickling bytes is cut off by the overall deadline' {
    . ([scriptblock]::Create((Get-FnText $ST 'Invoke-PairClient', 'Send-Resp')))
    It 'returns within ~2 s even if the client sends a byte every 400 ms' {
        $script:Token = 'abc'; $script:PairConns = 0; $script:Pad = New-Object byte[] 16; $PairPageHtml = 'x'
        $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0; $l.Start()
        $cl = New-Object Net.Sockets.TcpClient; $cl.Connect('127.0.0.1', $l.LocalEndpoint.Port)
        $srv = $l.AcceptTcpClient()
        $ps = [PowerShell]::Create().AddScript({ param($c) $s = $c.GetStream(); foreach ($i in 1..20) { try { $s.WriteByte(65); $s.Flush() } catch { break }; Start-Sleep -Milliseconds 400 } }).AddArgument($cl)
        $h = $ps.BeginInvoke()
        $sw = [Diagnostics.Stopwatch]::StartNew(); try { Invoke-PairClient $srv } catch {}; $sw.Stop()
        $srv.Close(); $cl.Close(); $l.Stop(); try { $ps.Stop(); $ps.Dispose() } catch {}
        $sw.Elapsed.TotalSeconds | Should BeLessThan 2.5
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U13 firmware + BitLocker helpers (V1.3)' {
    foreach ($src in $ST, $WRT) {
        . ([scriptblock]::Create((Get-FnText $src 'Get-FirmwareType', 'Get-BitLockerState')))
        It "[$src] Get-FirmwareType reports this VM's firmware ($env:firmware_type)" {
            $exp = if ($env:firmware_type -eq 'Legacy') { 'BIOS' } else { $env:firmware_type }
            Get-FirmwareType | Should Be $exp
        }
        It "[$src] Get-BitLockerState never claims 'Off' when it cannot read BitLocker (pre-flight must not give a false OK)" {
            $s = Get-BitLockerState $env:SystemDrive
            $s | Should Not BeNullOrEmpty
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            # as admin: On / Off - or 'unknown' when BitLocker's WMI really has no entry for the drive (Windows 10 test PC)
            $ev = $null; try { $ev = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction Stop } catch {}
            if (-not $isAdmin) { $s | Should Match '^unknown' } elseif ($ev) { $s | Should Match '^(On|Off)$' } else { $s | Should Match '^unknown \(volume not found' }
        }
        It "[$src] Get-BitLockerState on a drive that does not exist -> unknown, not Off" { Get-BitLockerState 'Q:' | Should Match '^unknown' }
    }
}

Describe 'U14 WinFixKit backup bookkeeping + UI fixes (V1.3)' {
    . ([scriptblock]::Create((Get-FnText $WFK 'Test-BackupPending')))
    $d = Join-Path $env:TEMP ('wfk-pend-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
    It 'a backup that was never restored is kept' { '{"Type":"Value","RestoredAt":null}' | Set-Content "$d\a.json"; Test-BackupPending "$d\a.json" | Should Be $true }
    It 'a restored backup may be replaced by a fresh one' { '{"Type":"Value","RestoredAt":"2026-11-19 10:00:00"}' | Set-Content "$d\b.json"; Test-BackupPending "$d\b.json" | Should Be $false }
    It 'an unreadable backup is never overwritten' { 'not json {' | Set-Content "$d\c.json"; Test-BackupPending "$d\c.json" | Should Be $true }
    It 'no backup file -> nothing pending' { Test-BackupPending "$d\none.json" | Should Be $false }
    Remove-Item $d -Recurse -Force
    It 'Add-BottomButton has no parameter that hides the global $tip ToolTip' {
        $f = (Get-SuiteAst $WFK).Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Add-BottomButton' }, $true)
        @($f.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'tip' }).Count | Should Be 0
    }
    It 'Registry Backups list warns about unreadable backup files instead of an empty catch' {
        (Get-FnText $WFK 'Update-RegBackupList') | Should Match 'unreadable'
    }
}

Describe 'U15 QR pairing: a silent client cannot hold the GUI thread for long (V1.3)' {
    foreach ($pair in @(@($ST, 'Invoke-PairClient'), @('PS suite V1.1\ClaudeLogAnalyzer.ps1', 'Handle-Client'))) {
        $src = $pair[0]; $fn = $pair[1]
        It "[$src] $fn gives up on a client that sends nothing within ~0.7 s and counts the connection" {
            . ([scriptblock]::Create((Get-FnText $src $fn, 'Send-Resp')))
            $script:Token = 'abc'; $script:PairConns = 0; $script:Pad = New-Object byte[] 16; $PairPageHtml = 'x'
            $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0; $l.Start()
            $cl = New-Object Net.Sockets.TcpClient; $cl.Connect('127.0.0.1', $l.LocalEndpoint.Port)
            $srv = $l.AcceptTcpClient()
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try { & $fn $srv } catch {}
            $sw.Stop(); $srv.Close(); $cl.Close(); $l.Stop()
            $sw.Elapsed.TotalSeconds | Should BeLessThan 1.2
            $script:PairConns | Should Be 1
        }
    }
}

# ---------------------------------------------------------------------------------------------
Describe 'U12 remembered mounts are only trusted if the letter still points at the same partition' {
    . ([scriptblock]::Create((Get-FnText $ST 'Load-Mounts', 'Test-LetterUsed', 'Test-MountStillOurs')))
    try { . ([scriptblock]::Create((Get-FnText $ST 'Sync-StorageCache', 'Get-LetterPartition'))) } catch { function Sync-StorageCache { } }   # V1.4+
    $sys = Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1))   # the real C: on this VM (read-only)
    $StateFile = Join-Path $env:TEMP ('wst-mounts-' + [guid]::NewGuid().ToString('N') + '.json')
    # Remembered from an earlier run: E-like mount on Disk 1 / Partition 2 ... but on THIS VM, D: is the CD-ROM drive.
    '[{"Letter":"D","Disk":1,"Partition":2}]' | Set-Content -LiteralPath $StateFile -Encoding UTF8
    It 'does not adopt D: (now a different volume) as a tool mount, so "Unmount all" cannot remove its letter' {
        Load-Mounts
        @($script:Mounts | Where-Object { $_.Letter -eq 'D' }).Count | Should Be 0
    }
    . ([scriptblock]::Create((Get-FnText $ST 'Save-Mounts')))
    foreach ($n in 1, 2, 3) {
        It "remembers $n mount(s) across a restart (Save-Mounts -> Load-Mounts)" {
            $script:Mounts = New-Object Collections.ArrayList
            foreach ($i in 1..$n) { [void]$script:Mounts.Add([pscustomobject]@{ Letter = 'C'; Disk = [int]$sys.DiskNumber; Partition = [int]$sys.PartitionNumber }) }
            Save-Mounts; Load-Mounts
            $script:Mounts.Count | Should Be $n
        }
    }
    It 'drops a remembered mount whose letter now belongs to a DIFFERENT partition' {
        "[{`"Letter`":`"C`",`"Disk`":$($sys.DiskNumber),`"Partition`":$([int]$sys.PartitionNumber + 1)}]" | Set-Content -LiteralPath $StateFile -Encoding UTF8
        Load-Mounts
        $script:Mounts.Count | Should Be 0
    }
    It 'WinRepairTool copy: remembers 2 mounts and drops a stale one' {
        . ([scriptblock]::Create((Get-FnText $WRT 'Load-Mounts', 'Save-Mounts', 'Test-MountStillOurs')))
        $script:Mounts = New-Object Collections.ArrayList
        1..2 | ForEach-Object { [void]$script:Mounts.Add([pscustomobject]@{ Letter = 'C'; Disk = [int]$sys.DiskNumber; Partition = [int]$sys.PartitionNumber }) }
        [void]$script:Mounts.Add([pscustomobject]@{ Letter = 'D'; Disk = 1; Partition = 2 })
        Save-Mounts; Load-Mounts
        $script:Mounts.Count | Should Be 2
    }
    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------------------------
Describe 'U11 log destination = the logged-in user''s Desktop' {
    It 'WinSuperTool Get-InteractiveUser returns this VM''s Desktop' {
        $IsWinPE = $false
        . ([scriptblock]::Create((Get-FnText $ST 'Get-InteractiveUser')))
        (Get-InteractiveUser).Desktop | Should Be ([Environment]::GetFolderPath('Desktop'))
    }
    It 'Collect-Logs Get-InteractiveUser returns this VM''s Desktop' {
        . ([scriptblock]::Create((Get-FnText 'PS suite V1.1\Collect-Logs.ps1' 'Get-InteractiveUser')))
        (Get-InteractiveUser).Desktop | Should Be ([Environment]::GetFolderPath('Desktop'))
    }
    It 'Collect-Logs: when an OTHER admin elevates, logs still go to the logged-in user (not the admin)' {
        # Simulates over-the-shoulder elevation: process profile = C:\Users\Admin, interactive user = this account.
        . ([scriptblock]::Create((Get-FnText 'PS suite V1.1\Collect-Logs.ps1' 'Get-InteractiveUser')))
        $real = Get-InteractiveUser
        function Get-ItemProperty { param($Path, $ErrorAction)
            if ($Path -like '*ProfileList*') { [pscustomobject]@{ ProfileImagePath = $real.Profile } }
            else { [pscustomobject]@{ Desktop = 'C:\Users\Admin\Desktop' } }   # what PowerShell returns: %USERPROFILE% already expanded with the ADMIN's profile
        }
        (Get-InteractiveUser).Desktop | Should Be ([Environment]::GetFolderPath('Desktop'))
    }
}

# =============================================================================================
# V1.8: fixes ported to WinRepairTool and the standalone tools
# =============================================================================================
$CL  = 'PS suite V1.1\Collect-Logs.ps1'
$ML  = 'PS suite V1.1\Monitor-Logs.ps1'
$CLA = 'PS suite V1.1\ClaudeLogAnalyzer.ps1'

Describe 'U25 standalone Collect-Logs (V1.8)' {
    function Say([string]$m) { $global:Said += , $m }
    . ([scriptblock]::Create((Get-FnText $CL 'Copy-One', 'Copy-Safe', 'Export-Evt')))
    $script:StopRequested = $false
    It 'a FAILED Event Viewer export is counted as failed (was "skipped" with 0 failures)' {
        # a FOLDER named System.evtx where the export should go: wevtutil fails with a real error (not "channel missing")
        $dst = Join-Path $env:TEMP 'cl-u25-fail'; [void][IO.Directory]::CreateDirectory((Join-Path $dst 'System.evtx'))
        $script:count = 0; $script:fail = 0; $global:Said = @()
        Export-Evt 'System' $dst
        Remove-Item $dst -Recurse -Force
        $script:fail | Should Be 1
        ($global:Said -join ' ') | Should Match 'FAILED'
    }
    It 'a channel that does not exist is skipped, not failed (exit code 15007)' {
        $script:count = 0; $script:fail = 0; $global:Said = @()
        Export-Evt 'No-Such-Channel/Operational' (Join-Path $env:TEMP 'cl-u25')
        $script:fail | Should Be 0
        ($global:Said -join ' ') | Should Match 'skipped'
    }
    It 'Stop: Copy-Safe copies nothing once Stop was pressed' {
        $script:count = 0; $script:StopRequested = $true
        Copy-Safe (Join-Path $env:windir 'Logs\CBS') (Join-Path $env:TEMP 'cl-u25')
        $script:count | Should Be 0
        $script:StopRequested = $false
    }
    It 'INFO counts only real successes (it used to add 2 whatever happened)' {
        (Get-AssignText $CL 'Collectors') | Should Not Match 'count \+= 2'
    }
    It 'no hard-coded C:\ paths in the collectors' {
        (Get-AssignText $CL 'Collectors') | Should Not Match "'C:\\"
    }
    It 'the window refuses to close while collecting, and the buttons come back in finally' {
        $t = [IO.File]::ReadAllText((Resolve-SuitePath $CL))
        $t | Should Match 'if \(\$script:Busy\) \{\s*\$e\.Cancel = \$true'
        $t | Should Match 'finally \{[^}]*\$script:Busy = \$false'
    }
    Remove-Item (Join-Path $env:TEMP 'cl-u25') -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'U26 standalone Monitor-Logs (V1.8)' {
    . ([scriptblock]::Create((Get-FnText $ML 'Esc', 'Start-Monitor')))
    . ([scriptblock]::Create((Get-AssignText $ML 'tplEvt')))
    $tplFile = 'x'; $tplFilter = 'x'; $tplDir = 'x'; $PsExePath = 'powershell.exe'
    $script:procs = New-Object Collections.ArrayList
    function Start-Process { $global:Started = $args; [pscustomobject]@{ HasExited = $false; Id = 1 } }
    It 'event IDs are code in the child script: anything but numbers is refused' {
        { Start-Monitor ([pscustomobject]@{ Name = 'x'; Type = 'Evt'; Target = 'System'; Extra = '41); Remove-Item C:\x; (1' }) 20 } | Should Throw
    }
    It 'valid IDs are passed as numbers' {
        Start-Monitor ([pscustomobject]@{ Name = 'x'; Type = 'Evt'; Target = 'System'; Extra = '41, 1001' }) 20
        $enc = $global:Started[-1][-1]
        [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($enc)) | Should Match '\$ids = @\(41,1001\)'
    }
    It 'closed monitor windows are dropped from the list' {
        $old = [pscustomobject]@{ HasExited = $true; Id = 9 } | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru
        $script:procs.Clear(); [void]$script:procs.Add($old)
        Start-Monitor ([pscustomobject]@{ Name = 'x'; Type = 'File'; Target = 'C:\x.log'; Extra = $null }) 20
        $script:procs.Count | Should Be 1
    }
    It 'the event poller asks only for records newer than the last one (XPath), on the real System log' {
        $top = (Get-WinEvent -LogName System -MaxEvents 1).RecordId
        $n = @(Get-WinEvent -LogName System -FilterXPath "*[System[EventRecordID>$($top - 3)]]" -ErrorAction SilentlyContinue)
        $n.Count | Should BeLessThan 4
        $n.Count | Should BeGreaterThan 0
        $tplEvt | Should Match 'EventRecordID>\$last\$idq'
        $tplEvt | Should Not Match 'Get-Ev 100'
    }
}

Describe 'U27 standalone ClaudeLogAnalyzer (V1.8)' {
    . ([scriptblock]::Create((Get-FnText $CLA 'Read-TextTail', 'Read-LogForAi', 'Get-AnswerText', 'Send-Resp', 'Handle-Client')))
    It 'reads a log that another program holds open for writing (ReadAllText failed here)' {
        $f = Join-Path $env:TEMP 'cla-open.log'; [IO.File]::WriteAllText($f, ('line ' * 1000))
        $h = [IO.File]::Open($f, 'Open', 'ReadWrite', 'ReadWrite')
        try { (Read-LogForAi $f 150000).Text.Length | Should Be 5000 } finally { $h.Dispose(); Remove-Item $f }
    }
    It 'reads only the newest part of a big log (it used to load the whole file)' {
        $f = Join-Path $env:TEMP 'cla-big.log'; [IO.File]::WriteAllText($f, ('a' * 400000) + 'THE END')
        $r = Read-LogForAi $f 1000
        $r.Text.Length | Should Be 1000; $r.Truncated | Should Be $true; $r.Text | Should Match 'THE END$'
        Remove-Item $f
    }
    It 'never sends an .etl trace as text' {
        $f = Join-Path $env:TEMP 'cla.etl'; [IO.File]::WriteAllBytes($f, [byte[]](1..255)); (Read-LogForAi $f 1000).Binary | Should Be $true; Remove-Item $f
    }
    It 'Gemini: a blocked prompt (no candidates) gives a message instead of a crash' {
        $resp = [pscustomobject]@{ promptFeedback = [pscustomobject]@{ blockReason = 'SAFETY' } }
        Get-AnswerText $resp $true | Should Match 'SAFETY'
    }
    It 'Claude: a cut-off answer says so, and a refusal is shown as a refusal' {
        Get-AnswerText ([pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = 'partial' }); stop_reason = 'max_tokens' }) $false | Should Match 'cut off'
        Get-AnswerText ([pscustomobject]@{ content = @(); stop_reason = 'refusal'; stop_details = [pscustomobject]@{ category = 'cyber' } }) $false | Should Match 'declined.*cyber'
        Get-AnswerText ([pscustomobject]@{ content = @(); stop_reason = 'end_turn' }) $false | Should Match 'No response text'
    }
    It 'request: max_tokens 16000, fallback header, reply decoded as UTF-8 in a background runspace' {
        $t = [IO.File]::ReadAllText((Resolve-SuitePath $CLA))
        $t | Should Match '"max_tokens":16000'
        $t | Should Match 'server-side-fallback-2026-07-01'
        $t | Should Match 'UTF8\.GetString\(\$w\.RawContentStream'
        $t | Should Match 'BeginInvoke'
        $t | Should Not Match 'Invoke-RestMethod'
    }
    It 'a rejected key ends the QR code at once, and the HTTP status line is correct' {
        $script:Token = 'abc'; $script:PairConns = 0; $script:Attempts = 0; $script:Pad = New-Object byte[] 16; $script:PageHtml = 'x'
        $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0; $l.Start()
        $cl = New-Object Net.Sockets.TcpClient; $cl.Connect('127.0.0.1', $l.LocalEndpoint.Port)
        $srv = $l.AcceptTcpClient()
        $req = [Text.Encoding]::ASCII.GetBytes("POST /abc/key HTTP/1.1`r`nContent-Length: 4`r`n`r`nzzzz")
        $cl.GetStream().Write($req, 0, $req.Length)
        Handle-Client $srv
        $buf = New-Object byte[] 512; $n = $cl.GetStream().Read($buf, 0, 512)
        $srv.Close(); $cl.Close(); $l.Stop()
        $script:Attempts | Should Be 5
        [Text.Encoding]::ASCII.GetString($buf, 0, $n) | Should Match '^HTTP/1\.1 400 Bad Request'
    }
    It 'dropped text (not files) is ignored, file names with [ ] are accepted' {
        $t = [IO.File]::ReadAllText((Resolve-SuitePath $CLA))
        $t | Should Match 'GetDataPresent\(\[Windows\.Forms\.DataFormats\]::FileDrop\)'
        (Get-FnText $CLA 'Add-Files') | Should Match '-LiteralPath'
    }
}

Describe 'U28 WinRepairTool (V1.8 port)' {
    It 'sees and deletes Safe Mode clones made by WinSuperTool too (R3)' {
        . ([scriptblock]::Create((Get-AssignText $WRT 'CloneMarkers')))
        . ([scriptblock]::Create((Get-FnText $WRT 'Get-Clones')))
        function Get-BcdAll { @([pscustomobject]@{ Dev = 'D:'; Desc = 'Safe Mode (minimal) [WinSuperTool]'; Id = '{11111111-2222-3333-4444-555555555555}' },
                                [pscustomobject]@{ Dev = 'D:'; Desc = 'Windows 11'; Id = '{11111111-2222-3333-4444-555555555556}' }) }
        @(Get-Clones @{} 'd:').Count | Should Be 1
    }
    It 'recovery tools use the ONLINE forms on the running Windows (R6)' {
        $NL = "`r`n"
        . ([scriptblock]::Create((Get-AssignText $WRT 'Tools')))
        $sfc  = $Tools | Where-Object Exe -eq 'sfc.exe'
        $dism = $Tools | Where-Object Name -eq 'DISM: restore health'
        (& $sfc.Argv @{ Win = 'C:'; Live = $true }) -join ' ' | Should Be '/scannow'
        (& $dism.Argv @{ Win = 'C:'; Live = $true }) -join ' ' | Should Be '/online /cleanup-image /restorehealth'
        (& $dism.Argv @{ Win = 'D:'; Live = $false }) -join ' ' | Should Match '^/image:D:\\'
    }
    It 'Get-WinInstalls marks the running Windows, and the Run button passes it on as Live (R6)' {
        # (the real scan needs admin: the SYSTEM hive is not visible to a standard user)
        (Get-FnText $WRT 'Get-WinInstalls') | Should Match 'Running = \$running'
        [IO.File]::ReadAllText((Resolve-SuitePath $WRT)) | Should Match '\$ctx\.Live = \[bool\]\$w\.Running'
    }
    It 'Dismount-One does not unmount a letter that now belongs to another partition (R2)' {
        . ([scriptblock]::Create((Get-FnText $WRT 'Dismount-One')))
        function Test-LetterUsed { $true }; function Get-LetterPartition { [pscustomobject]@{ DiskNumber = 0; PartitionNumber = 4 } }
        function Unmount-Letter { $global:Unmounted = $true }
        $global:Unmounted = $false; $script:Mounts = New-Object Collections.ArrayList
        $m = [pscustomobject]@{ Letter = 'Q'; Disk = 1; Partition = 2 }; [void]$script:Mounts.Add($m)
        Dismount-One $m | Should Be $false
        $global:Unmounted | Should Be $false
        $script:Mounts.Count | Should Be 0
    }
    It 'diskpart letter is read by column position (German output)' {
        . ([scriptblock]::Create((Get-FnText $WRT 'Get-DpPartLetter')))
        $de = "Partition 4`r`nTyp: ebd0a0a2`r`n`r`n  Volume ###  Bst  Bezeichnung  DS     Typ        Groesse  Status     Info`r`n  ----------  ---  -----------  -----  ---------  -------  ---------  --------`r`n* Volume 1     C                NTFS   Partition    49 GB  Fehlerfre  Startpar`r`n"
        Get-DpPartLetter 0 4 $de | Should Be 'C'
    }
    It 'answer file is never overwritten when its backup fails (R7), clone deletion is checked (R15)' {
        $t = [IO.File]::ReadAllText((Resolve-SuitePath $WRT))
        $t | Should Match "Copy-Item -LiteralPath \`$dest -Destination \('\{0\}\.bak_\{1\}'[^\r\n]*-ErrorAction Stop"
        $t | Should Match "\`$bad = @\(\`$cl \| Where-Object \{ \(Invoke-Bcd"
    }
    It 'asks before auto-unmounting while a repair console is still open (R1)' {
        [IO.File]::ReadAllText((Resolve-SuitePath $WRT)) | Should Match 'repair console window\(s\) started by this tool are still running'
    }
    It 'relaunches as 64-bit from a 32-bit host (R17), says so when UAC is cancelled' {
        $t = [IO.File]::ReadAllText((Resolve-SuitePath $WRT))
        $t | Should Match 'Is64BitProcess'
        $t | Should Match 'UAC prompt was cancelled'
    }
}

Describe 'U29 both tools: boot menu timeout 0 and "password never expires" (R16, R18)' {
    foreach ($src in $ST, $WRT) {
        It "[$src] offers to set a 5 s timeout when the boot menu timeout is 0" {
            . ([scriptblock]::Create((Get-FnText $src 'Confirm-BootMenuShown')))
            $NL = "`r`n"
            function bcdedit.exe { "Windows Boot Manager`r`n--------------------`r`nidentifier              {bootmgr}`r`ntimeout                 0`r`n" }
            function Ask { $true }
            function Invoke-Bcd($t, $a) { $global:BcdArgs = $a; [pscustomobject]@{ Rc = 0 } }
            $global:BcdArgs = $null
            Confirm-BootMenuShown @{ Store = $null }
            ($global:BcdArgs -join ' ') | Should Be '/timeout 5'
        }
        It "[$src] leaves a timeout of 30 s alone" {
            . ([scriptblock]::Create((Get-FnText $src 'Confirm-BootMenuShown')))
            function bcdedit.exe { "identifier              {bootmgr}`r`ntimeout                 30`r`n" }
            function Invoke-Bcd($t, $a) { $global:BcdArgs = $a; [pscustomobject]@{ Rc = 0 } }
            $global:BcdArgs = $null
            Confirm-BootMenuShown @{ Store = $null }
            $global:BcdArgs | Should Be $null
        }
        It "[$src] refuses 'password never expires' for a standard (Users) account" {
            (Get-FnText $src 'Build-Unattend') | Should Match "chkNoExp\.Checked -and \[string\]\`$cmbGroup\.SelectedItem -ne 'Administrators'"
        }
    }
}

Describe 'U30 launchers (V1.8)' {
    $bat = [IO.File]::ReadAllText((Resolve-SuitePath 'WinSuperTool.bat'))
    It 'WinSuperTool.bat: the elevated copy is started with the System32 path (Sysnative does not exist there)' {
        $bat | Should Match 'Start-Process -FilePath \$env:PSEXE64 -Verb RunAs'
    }
    It 'WinSuperTool.bat: a pasted path with ^ is kept when %variable% expansion mangles it' {
        $bat | Should Match 'if not exist "%PSFILE%" set "PSFILE=%PSRAW%"'
    }
    foreach ($b in 'Start-ClaudeLogAnalyzer.bat', 'Launch-WinFixKit.bat') {
        It "$b keeps its variables local (setlocal)" { [IO.File]::ReadAllText((Resolve-SuitePath $b)) | Should Match '(?m)^setlocal' }
    }
}
