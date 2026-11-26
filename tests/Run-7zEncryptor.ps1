# Run-7zEncryptor.ps1 - tests 7z-Encryptor without clicking: loads the tool with its window hidden, then checks
#   1. the 7-Zip command line, archive names and the checks before encrypting
#   2. real encryption (needs 7-Zip): 7z full / contents only, zip standard / AES-256 - each unpacked with the password
#      and compared with the originals, and refused with a wrong one
#   3. both windows: layout, "?" help, which options show, where the file is saved
#   4. the launcher: a file with spaces in its name dropped on 7z-Encryptor.bat opens the small window
# Everything is made in a temporary folder and removed afterwards; the originals are only read.
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   powershell -ExecutionPolicy Bypass -File .\tests\Run-7zEncryptor.ps1
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$script:Fail = 0; $script:Pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:Pass++; Write-Host "PASS  $name" -ForegroundColor Green }
    else { $script:Fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
# a control's own Visible flag (.Visible is false for everything on a form that was never shown)
function Test-Shown($c) { [bool][Windows.Forms.Control].GetMethod('GetState', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($c, @(2)) }
$W = Join-Path $env:TEMP ('7zenc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$tests = {
    # ---- 1. command line, names, checks ----
    Check 'args: 7z full encryption hides names' (((New-EncryptArgs 'o.7z' @('a') '7z' 'pw' $true) -join '|') -eq 'a|-t7z|-mx=5|-y|-ssw|-ppw|-mhe=on|--|o.7z|a')
    Check 'args: 7z contents only' (((New-EncryptArgs 'o.7z' @('a') '7z' 'pw' $false) -join '|') -eq 'a|-t7z|-mx=5|-y|-ssw|-ppw|--|o.7z|a')
    Check 'args: zip standard is ZipCrypto, AES-256 on request' (((New-EncryptArgs 'o.zip' @('a') 'zip' 'pw' $true) -join '|') -eq 'a|-tzip|-mx=5|-y|-ssw|-ppw|-mem=ZipCrypto|--|o.zip|a' -and ((New-EncryptArgs 'o.zip' @('a', 'b') 'zip' 'pw' $true 'AES256') -join '|') -eq 'a|-tzip|-mx=5|-y|-ssw|-ppw|-mem=AES256|--|o.zip|a|b')
    New-Item -ItemType Directory "$W\src\Folder A\Empty", "$W\src\Folder A\Sub", "$W\out" -Force | Out-Null
    [IO.File]::WriteAllText("$W\src\Folder A\report one.txt", ('secret report ' * 5000)); [IO.File]::WriteAllText("$W\src\Folder A\Sub\b.txt", 'b'); [IO.File]::WriteAllText("$W\src\single file.txt", 'single')
    Check 'name: one file is named after it' ((Get-ArchivePath @("$W\src\single file.txt") "$W\out" '7z') -eq "$W\out\single file.txt.7z")
    Check 'name: one folder is named after it' ((Get-ArchivePath @("$W\src\Folder A") "$W\out" 'zip') -eq "$W\out\Folder A.zip")
    Check 'name: several items get Encrypted-<date>' ((Get-ArchivePath @("$W\src\Folder A", "$W\src\single file.txt") "$W\out" '7z') -match '\\Encrypted-\d{4}-\d\d-\d\d_\d{6}\.7z$')
    'x' | Set-Content "$W\out\taken.txt.7z"; New-Item -ItemType File "$W\src\taken.txt" -Force | Out-Null
    Check 'name: an existing file is never reused (adds (2))' ((Get-ArchivePath @("$W\src\taken.txt") "$W\out" '7z') -eq "$W\out\taken.txt (2).7z")
    Check 'name: a drive root is C-Drive, a share root is the share name (not the current folder)' ((Get-ArchivePath @('C:\') "$W\out" '7z') -eq "$W\out\C-Drive.7z" -and (Get-ArchivePath @('\\nas\photos') "$W\out" '7z') -eq "$W\out\photos.7z")
    Check 'check: no items / no password / passwords differ' ((Test-EncryptInput @() 'a' 'a' "$W\o.7z") -match 'Add' -and (Test-EncryptInput @("$W\src") '' '' "$W\o.7z") -match 'Type' -and (Test-EncryptInput @("$W\src") 'a' 'b' "$W\o.7z") -match 'not the same')
    Check 'check: missing item / relative or existing output / quote in password' ((Test-EncryptInput @("$W\nope") 'a' 'a' "$W\o.7z") -match 'Not found' -and (Test-EncryptInput @("$W\src") 'a' 'a' 'o.7z') -match 'full path' -and (Test-EncryptInput @("$W\src") 'a' 'a' "$W\out\taken.txt.7z") -match 'already exists' -and (Test-EncryptInput @("$W\src") 'a"b' 'a"b' "$W\o.7z") -match 'quote')
    Check 'check: all good gives no message' ((Test-EncryptInput @("$W\src") 'p w' 'p w' "$W\o.7z") -eq '')
Check 'check: a non-ASCII password is refused for zip but allowed for 7z' (((Test-EncryptInput @("$W\src") ('p' + [char]0xE9) ('p' + [char]0xE9) "$W\o.zip" 'zip') -match 'zip password') -and ((Test-EncryptInput @("$W\src") ('p' + [char]0xE9) ('p' + [char]0xE9) "$W\o.7z" '7z') -eq ''))

    # ---- 2. real encryption ----
    if (-not $script:SevenZip) { Check '7-Zip is installed (needed for the encryption tests)' $false 'install it: winget install -e --id 7zip.7zip' }
    else {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'      # 7-Zip writes "Wrong password" to stderr on purpose below
        $z = $script:SevenZip; $pw = 'Tr0ub & dor 9'
        $hash = { param($d) Get-ChildItem $d -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($d.Length) + '=' + (Get-FileHash $_.FullName).Hash } }
        $want = & $hash "$W\src\Folder A"
        foreach ($c in @(@{ N = '7z-full'; Format = '7z'; HideNames = $true }, @{ N = '7z-contents'; Format = '7z'; HideNames = $false }, @{ N = 'zip-standard'; Format = 'zip'; ZipMethod = 'ZipCrypto' }, @{ N = 'zip-aes'; Format = 'zip'; ZipMethod = 'AES256' })) {
            $out = "$W\out\$($c.N).$($c.Format)"
            $r = Invoke-Encrypt (@{ SevenZip = $z; Sources = @("$W\src\Folder A", "$W\src\single file.txt"); Out = $out; Password = $pw } + $c)
            $x = "$W\x-$($c.N)"; & $z x "-p$pw" "-o$x" -y $out | Out-Null
            $same = (((& $hash "$x\Folder A") -join '|') -eq ($want -join '|')) -and (Test-Path "$x\Folder A\Empty") -and ((Get-Content "$x\single file.txt") -eq 'single')
            $wrong = (& $z t -pWRONG $out 2>&1 | Out-String) -notmatch 'Everything is Ok'
            $list = & $z l -slt -p $out 2>&1 | Out-String
            Check "encrypt $($c.N): created, tested, unpacks to the same files with the password, refused with a wrong one" ($r.Ok -and $same -and $wrong) "$($r.Message)"
            switch ($c.N) {
                '7z-full' { Check '7z full: without the password not even the file names can be read' ($list -notmatch 'report one') }
                '7z-contents' { Check '7z contents only: names readable, contents not' ($list -match 'report one' -and $wrong) }
                'zip-standard' { Check 'zip standard uses ZipCrypto (opens in Windows Explorer)' ($list -match 'Method = ZipCrypto') }
                'zip-aes' { Check 'zip AES-256 uses AES-256' ($list -match 'Method = AES-256') }
            }
        }
        $ErrorActionPreference = $eap
        $r = Invoke-Encrypt @{ SevenZip = $null; Sources = @("$W\src"); Out = "$W\out\n.7z"; Password = 'a'; Format = '7z' }
        Check 'without 7-Zip it says so and makes nothing' (-not $r.Ok -and $r.Message -match 'not installed' -and -not (Test-Path "$W\out\n.7z"))
    }

    # ---- 3. windows ----
    $layout = {
        param($name, $page, [int]$minHelp)
        $ctl = @($page.Controls); $bad = @()
        for ($i = 0; $i -lt $ctl.Count; $i++) { for ($j = $i + 1; $j -lt $ctl.Count; $j++) {
            $a = $ctl[$i]; $b = $ctl[$j]; if (-not ((Test-Shown $a) -and (Test-Shown $b))) { continue }
            $ra = $a.Bounds; $rb = $b.Bounds
            if (($a -is [Windows.Forms.Label] -or $a -is [Windows.Forms.CheckBox]) -and $a.AutoSize) { $ra.Size = $a.PreferredSize }
            if (($b -is [Windows.Forms.Label] -or $b -is [Windows.Forms.CheckBox]) -and $b.AutoSize) { $rb.Size = $b.PreferredSize }
            if ($ra.IntersectsWith($rb)) { $bad += "$($a.GetType().Name)'$($a.Text)' x $($b.GetType().Name)'$($b.Text)'" }
        } }
        Check "$name : no overlapping controls" ($bad.Count -eq 0) ($bad -join '; ')
        $help = @($ctl | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '?' })
        Check "$name : ? buttons with help text" ($help.Count -ge $minHelp -and -not @($help | Where-Object { -not $_.Tag[1] }).Count) "$($help.Count)"
    }
    $m = $script:MainUi
    & $layout 'main window' $m.Page 4
    $m.Opt.Rb7z.Checked = $true; $hide7 = (Test-Shown $m.Opt.Hide) -and -not (Test-Shown $m.Opt.ZipPanel)
    $m.Opt.RbZip.Checked = $true; $zipShown = (Test-Shown $m.Opt.ZipPanel) -and -not (Test-Shown $m.Opt.Hide) -and $m.Opt.RbCrypto.Checked
    Check 'main: 7z shows "hide the file names", zip shows Standard / AES-256 (Standard first)' ($hide7 -and $zipShown)
    & $layout 'main window with zip' $m.Page 4
    $m.Opt.Rb7z.Checked = $true
    [void]$m.List.Items.Add("$W\src\Folder A"); Update-MainOut
    Check 'main: Save as is filled in next to the first item, named after it' ($m.Out.Text -eq "$W\src\Folder A.7z")
    $m.Opt.RbZip.Checked = $true
    Check 'main: switching to zip changes the extension' ($m.Out.Text -eq "$W\src\Folder A.zip")
    $m.Opt.Pw.Text = 'abc'; $m.Opt.HideNames = $true
    $ch = Get-EncryptChoice $m.Opt
    Check 'main: the choice read from the window' ($ch.Format -eq 'zip' -and $ch.ZipMethod -eq 'ZipCrypto' -and $ch.Password -eq 'abc')
    Check 'main: Encrypt is on only when 7-Zip is found; Get 7-Zip shows the winget command' ($m.Go.Enabled -eq [bool]$script:SevenZip -and $m.Get7.Box.Text -eq 'winget install -e --id 7zip.7zip' -and ($m.Get7.Btn.Enabled -ne [bool]$script:SevenZip))
    $script:ScriptDir = "$W\tooldir"
    $g = $m.Get7
    if ($script:SevenZip) { Check '7-Zip row: shows the version, Install off, Update on' ($g.Lbl.Text -match '^7-Zip [\d.]+ installed$' -and -not $g.Btn.Enabled -and $g.BtnUp.Enabled) $g.Lbl.Text }
    $help7 = @($m.Page.Controls | Where-Object { $_.Text -eq '?' -and $_.Tag[0] -eq '7-Zip' })
    Check '7-Zip help names both winget commands' ($help7.Count -eq 1 -and $help7[0].Tag[1] -match 'winget install -e --id 7zip\.7zip' -and $help7[0].Tag[1] -match 'winget upgrade -e --id 7zip\.7zip')
    $keep7 = $script:SevenZip; $script:SevenZip = $null; Update-Get7Row $g
    Check '7-Zip row without 7-Zip: Install on, Update off, says it is needed' ($g.Btn.Enabled -and -not $g.BtnUp.Enabled -and $g.Lbl.Text -match 'needed')
    [FakeMsg7]::Answer = 'No'; [FakeMsg7]::Last = ''
    Request-7ZipInstall $g
    Check 'start without 7-Zip: asks to install it with winget (answered No: nothing runs)' ([FakeMsg7]::Last -match 'not installed' -and [FakeMsg7]::Last -match 'winget install -e --id 7zip\.7zip' -and -not $g.Proc)
    $script:SevenZip = $keep7; [FakeMsg7]::Last = ''; Request-7ZipInstall $g
    Check 'start with 7-Zip: no question' ([FakeMsg7]::Last -eq ''); [FakeMsg7]::Answer = 'Yes'; Update-Get7Row $g
    Check 'main window has a destination picker (Save as + Browse... save dialog)' ($m.Out -is [Windows.Forms.TextBox] -and $m.Browse.Text -eq 'Browse...')
    $qf = New-QuickWindow @("$W\src\single file.txt"); $q = $script:QuickUi
    & $layout 'drop window' $qf.Controls[0] 3
    $script:ScriptDir = "$W\tooldir"
    Check 'drop window: saves in the 7z-Encryptor folder by default' ((Get-QuickOut) -eq "$W\tooldir\single file.txt.7z")
    $q.Next.Checked = $true
    Check 'drop window: ticked, it saves next to the dropped item' ((Get-QuickOut) -eq "$W\src\single file.txt.7z")
    $q.Opt.RbZip.Checked = $true
    Check 'drop window: zip changes the name and the Saves as line' ((Get-QuickOut) -eq "$W\src\single file.txt.zip" -and $q.Where.Text -match 'single file\.txt\.zip$')
    Check 'drop window: title names what is encrypted' ($q.What.Text -eq 'Encrypt single file.txt')
    $qf.Dispose()
}

# load the tool, but run the tests instead of showing the window (no splash, message boxes answered "Yes")
$code = [IO.File]::ReadAllText((Join-Path $Root 'tools\7z-Encryptor.ps1'))
$code = $code.Replace("Show-WrtSplash '7z-Encryptor'", '').Replace('[void]$form.ShowDialog()', '& $tests')
Add-Type -TypeDefinition 'public static class FakeMsg7 { public static string Last = ""; public static string Answer = "Yes"; public static string Show(params object[] a) { Last = a[0].ToString(); return Answer; } }'
$code = $code.Replace('[System.Windows.Forms.MessageBox]::Show(', '[FakeMsg7]::Show(')
try { . ([scriptblock]::Create($code)) } finally { }

# ---- 4. the launcher: drop a file whose name has spaces on the .bat; the small window must open ----
$drop = "$W\src\single file.txt"
Add-Type -AssemblyName UIAutomationClient
# started on its own (not through this console) so the tool's window never holds this script's output open
Start-Process cmd.exe -ArgumentList '/c', "`"`"$Root\tools\7z-Encryptor.bat`" `"$drop`"`"" -WindowStyle Hidden
$proc = $null; $title = ''; $t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 40) {
    Start-Sleep -Milliseconds 500
    $proc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '7z-Encryptor\.ps1' -and $_.CommandLine -match [regex]::Escape("`"$drop`"") } | Select-Object -First 1
    # the hidden console is the process's "main" window, so its windows are read with UI Automation
    if ($proc) { $title = (@([Windows.Automation.AutomationElement]::RootElement.FindAll('Children', (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$proc.ProcessId))) | ForEach-Object { $_.Current.Name }) -join ','); if ($title -match '(^|,)7z-Encryptor(,|$)') { break } }
}
if ($proc) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue }
$win = [bool]$proc -and $title -match '(^|,)7z-Encryptor(,|$)'; $cmdOk = [bool]$proc
Check 'launcher: a dropped file with spaces opens the 7z-Encryptor window with that file' ($win -and $cmdOk) "window title: '$title'"

Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "$script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 }
