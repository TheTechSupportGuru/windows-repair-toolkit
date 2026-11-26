# Run-7zEncryptor.ps1 - tests 7z-Encryptor without clicking: loads the tool with its window hidden, then checks
#   1. the 7-Zip command line, archive names and the checks before encrypting
#   2. real encryption (needs 7-Zip): 7z full / contents only, zip standard / AES-256 - each unpacked with the password
#      and compared with the originals, and refused with a wrong one
#   3. the window: layout, "?" help, which options show, where the file is saved, started empty or with dropped items
#   4. the launcher: a file with spaces in its name dropped on 7z-Encryptor.bat opens the window
#   5. names with & ^ % ! dropped on the launcher arrive whole; started from a console the arguments are used
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
        # 1.4 edge cases: odd names (& # % ! ^ ' , accents), a name starting with -, an empty file, a 7z password with
        # spaces, accents, & ^ % ! and a trailing backslash; a trailing space in the password is kept
        $odd = "$W\odd R&D #1 50% !^ it's, " + [char]0xE9 + [char]0x4E2D; [void][IO.Directory]::CreateDirectory($odd)
        [IO.File]::WriteAllText("$odd\-dash & " + [char]0xFC + '.txt', 'odd'); [IO.File]::WriteAllText("$odd\empty.txt", '')
        $opw = 'p ' + [char]0xE4 + ' &^%!x\ '
        $r = Invoke-Encrypt @{ SevenZip = $z; Sources = @($odd); Out = "$W\out\odd.7z"; Password = $opw; Format = '7z'; HideNames = $true }
        $xo = "$W\x-odd"; & $z x "-p$opw" "-o$xo" -y "$W\out\odd.7z" | Out-Null
        $leaf = Split-Path $odd -Leaf
        $back = (Test-Path -LiteralPath "$xo\$leaf\-dash & $([char]0xFC).txt") -and (Get-Content -LiteralPath "$xo\$leaf\-dash & $([char]0xFC).txt") -eq 'odd' -and (Test-Path -LiteralPath "$xo\$leaf\empty.txt") -and (Get-Item -LiteralPath "$xo\$leaf\empty.txt").Length -eq 0
        $trimmed = (& $z t "-p$($opw.TrimEnd())" "$W\out\odd.7z" 2>&1 | Out-String) -notmatch 'Everything is Ok'
        Check 'encrypt: odd names (& # % ! ^ accents, a leading -), an empty file and a password with & ^ % ! \ and accents unpack the same' ($r.Ok -and $back) "$($r.Message)"
        Check 'encrypt: a trailing space is part of the password (without it the file does not open)' $trimmed
        $r2 = Invoke-Encrypt @{ SevenZip = $z; Sources = @("$W\src\single file.txt"); Out = "$W\out\new\deeper\s.zip"; Password = 'pw'; Format = 'zip'; ZipMethod = 'AES256' }
        Check 'encrypt: a save folder that does not exist yet is made' ($r2.Ok -and (Test-Path -LiteralPath "$W\out\new\deeper\s.zip"))        $ErrorActionPreference = $eap
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
    & $layout 'main window' $m.Page 7
    $m.Opt.Rb7z.Checked = $true; $hide7 = (Test-Shown $m.Opt.Hide) -and -not (Test-Shown $m.Opt.ZipPanel)
    $m.Opt.RbZip.Checked = $true; $zipShown = (Test-Shown $m.Opt.ZipPanel) -and -not (Test-Shown $m.Opt.Hide) -and $m.Opt.RbCrypto.Checked
    Check 'main: 7z shows "hide the file names", zip shows Standard / AES-256 (Standard first)' ($hide7 -and $zipShown)
    & $layout 'main window with zip' $m.Page 7
    $m.Opt.Rb7z.Checked = $true
    [void]$m.List.Items.Add("$W\src\Folder A"); Update-MainOut
    Check 'main: Save as is filled in next to the first item, named after it' ($m.Out.Text -eq "$W\src\Folder A.7z")
    $m.Opt.RbZip.Checked = $true
    Check 'main: switching to zip changes the extension' ($m.Out.Text -like "$W\src\Folder A.*")
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
    # every ? button: there, and its text says what the window does now (1.4)
    $hb = @{}; foreach ($b in @($m.Page.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '?' })) { $hb[[string]$b.Tag[0]] = [string]$b.Tag[1] }
    Check 'help: a ? for Files and folders, Format, Password, Save as, Send by email, 7-Zip and Remember settings' ((@('Files and folders', 'Format', 'Password', 'Save as', 'Show in folder / Send by email', '7-Zip', 'Remember settings') | Where-Object { -not $hb.ContainsKey($_) }).Count -eq 0) (($hb.Keys | Sort-Object) -join ', ')
    Check 'help: Files and folders names the drop, Remove and one file' ($hb['Files and folders'] -match '7z-Encryptor\.bat' -and $hb['Files and folders'] -match "'Remove'" -and $hb['Files and folders'] -match 'ONE encrypted file')
    Check 'help: Password says case and spaces count, no double quote, zip limits, never saved' ($hb['Password'] -match 'Upper and lower case count' -and $hb['Password'] -match 'space' -and $hb['Password'] -match 'double quote \("\)' -and $hb['Password'] -match 'zip: only English' -and $hb['Password'] -match 'never saved')
    Check 'help: Save as says dropped items, not inside a folder being encrypted, share folder, never overwritten' ($hb['Save as'] -match 'dropped on 7z-Encryptor\.bat' -and $hb['Save as'] -match 'inside a folder that is being encrypted' -and $hb['Save as'] -match '\\\\server\\share\\file\.7z' -and $hb['Save as'] -match 'never overwritten')
    Check 'help: Send by email explains all four ways, mailto: cannot attach' ($hb['Show in folder / Send by email'] -match 'Send to > Mail recipient' -and $hb['Show in folder / Send by email'] -match 'Windows Share' -and $hb['Show in folder / Send by email'] -match 'Choose program' -and $hb['Show in folder / Send by email'] -match 'mailto: link cannot attach' -and $hb['Show in folder / Send by email'] -notmatch 'attaches it to a new email')
    Check 'help: Remember settings says off by default, what is kept, never a password, untick deletes' ($hb['Remember settings'] -match 'Off \(the default\)' -and $hb['Remember settings'] -match 'mailto: address' -and $hb['Remember settings'] -match 'Never a password' -and $hb['Remember settings'] -match 'Unticking it deletes')
    Check 'help: no text mentions the old small drop window' (-not @($hb.Values | Where-Object { $_ -match 'small window|drop window|quick window' }).Count)
    $rq = @($m.Page.Controls | Where-Object { $_.Text -eq '?' -and $_.Tag[0] -eq 'Remember settings' })[0]
    Check 'help: the Remember settings ? sits right of its box, on the same line' ($rq.Left -ge $m.Remember.Right -and [Math]::Abs($rq.Top - $m.Remember.Top) -le 4)
    Check 'main window has a destination picker (Save as + Browse... save dialog)' ($m.Out -is [Windows.Forms.TextBox] -and $m.Browse.Text -eq 'Browse...')
    # ---- 1.2: Show in folder, Send by email (3 ways), remembered settings next to the script ----
    Check 'main: Show in folder and Send by email are off until a file is encrypted' (-not $m.ShowDir.Enabled -and -not $m.Mail.Enabled -and $m.ShowDir.Text -eq 'Show in folder' -and $m.Mail.Text -eq 'Send by email')
    $m.Opt.RbZip.Checked = $true; $m.Opt.Rb7z.Checked = $true
    Check 'main: three email options, Send to > Mail recipient chosen by default (and not cleared by the 7z / zip choice)' ($m.RbClassic.Checked -and -not $m.RbShare.Checked -and -not $m.RbProgram.Checked -and (Get-MainEmailMode) -eq 'Classic')
    # ---- 1.3: a Remember settings box, off at first; nothing is written until it is ticked ----
    $sf = "$env:WRT_SETTINGS_DIR\7z-Encryptor.settings.json"
    Check 'remember: a Remember settings box, off at first' ($m.Remember.Text -eq 'Remember settings' -and -not $m.Remember.Checked -and -not $script:Settings.Remember)
    $m.RbShare.Checked = $true; Set-MainEmailMode $m.RbShare
    Check 'remember: off, choosing an option writes no settings file' (-not (Test-Path -LiteralPath $sf))
    $m.Remember.Checked = $true
    Check 'remember: ticking it saves what is chosen now' ((Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json).Remember -eq $true)
    $m.RbShare.Checked = $true; Set-MainEmailMode $m.RbShare
    $sj = Get-Content -LiteralPath "$env:WRT_SETTINGS_DIR\7z-Encryptor.settings.json" -Raw | ConvertFrom-Json
    Check 'settings: the email choice is saved in 7z-Encryptor.settings.json' ($sj.EmailMode -eq 'Share')
    Check 'settings: no password is ever saved' (-not ((Get-Content -LiteralPath "$env:WRT_SETTINGS_DIR\7z-Encryptor.settings.json" -Raw) -match 'abc'))
    Check 'email: Outlook and Thunderbird get the file attached, others get the file name' ((Get-MailProgramArgs 'C:\P\OUTLOOK.EXE' 'C:\a b.7z') -eq '/a "C:\a b.7z"' -and (Get-MailProgramArgs 'C:\P\thunderbird.exe' 'C:\a b.7z') -eq '-compose "attachment=''file:///C:/a%20b.7z''"' -and (Get-MailProgramArgs 'C:\P\mail.exe' 'C:\a b.7z') -eq '"C:\a b.7z"')
    Check 'email: a missing file / no program picked gives a message, nothing starts' ((Send-EncryptedFile "$W\nope.7z" 'Classic' '') -match 'not there' -and (Send-EncryptedFile "$W\src\single file.txt" 'Program' '') -match 'Pick the mail program')
    # ---- 1.4: mailto: with a typed address ----
    $u = Get-MailtoUri 'a.b@example.com' "$W\out\my file.7z"
    Check 'mailto: the address, the file name as subject, encoded' ($u -eq 'mailto:a.b@example.com?subject=my%20file.7z&body=Attached%3A%20my%20file.7z%20(encrypted).%20The%20password%20comes%20separately.') $u
    Check 'mailto: several addresses (; or ,), spaces ignored; empty is allowed' ((Get-MailtoUri ' a@x.org; b@y.net ' 'f.7z') -like 'mailto:a@x.org,b@y.net?subject=f.7z&*' -and (Get-MailtoUri '' 'f.7z') -like 'mailto:?subject=f.7z&*')
    Check 'mailto: no address / extra link parts are refused' ($null -eq (Get-MailtoUri 'not-an-address' 'f.7z') -and $null -eq (Get-MailtoUri 'a@x.org?cc=c@y.net' 'f.7z') -and $null -eq (Get-MailtoUri 'a@x.org&body=x' 'f.7z') -and $null -eq (Get-MailtoUri '"a"@x.org' 'f.7z'))
    Check 'mailto: a bad address gives a message, nothing starts' ((Send-EncryptedFile "$W\src\single file.txt" 'Mailto' '' ([IntPtr]::Zero) 'nope') -match 'Type an email address')
    Check 'window: a mailto: option with an address box under the other three' ($m.RbMailto.Text -eq 'mailto:' -and $m.MailTo -is [Windows.Forms.TextBox] -and $m.MailTo.Parent -eq $m.MailPanel -and $m.RbMailto.Top -gt $m.RbClassic.Bottom)
    $m.MailTo.Text = 'a@example.com'
    Check 'window: typing an address picks mailto: and it is remembered (with Remember settings ticked)' ($m.RbMailto.Checked -and (Get-MainEmailMode) -eq 'Mailto' -and (Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json).MailTo -eq 'a@example.com' -and (Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json).EmailMode -eq 'Mailto')
    & $layout 'main window with mailto:' $m.Page 7
    $m.RbShare.Checked = $true; Set-MainEmailMode $m.RbShare    Check 'email: Send to > Mail recipient is the MAPI call (Simple MAPI MAPISendMail with a dialog)' ([bool]('WrtMapi' -as [type]) -and $script:BsbEncSource -match 'MAPISendMail' -and $script:BsbEncSource -match 'fall back to the Windows Share window')
    $script:Settings.SaveFolder = "$W\out"; $m.OutEdited = $false; Update-MainOut
    Check 'settings: Save as uses the remembered folder of the last encrypted file' ($m.Out.Text -like "$W\out\Folder A.*")
    $script:Settings.SaveFolder = "$W\gone"; Update-MainOut
    Check 'settings: a remembered folder that is gone falls back to next to the first item' ($m.Out.Text -like "$W\src\Folder A.*")
    $script:Settings.Remove('SaveFolder')
    Check 'settings: by default the file is next to the script (portable)' ($script:BsbEncSource.Contains('else { $ScriptDir }') -and $script:BsbEncSource.Contains('Join-Path $d "$name.settings.json"'))
    # ---- 1.4: one window for both ways of starting; dropped items are in the list and saved next to the first one ----
    Check 'drop: the small window is gone (one window for both ways of starting)' (-not (Get-Command New-QuickWindow -ErrorAction SilentlyContinue) -and $script:BsbEncSource.Contains('try { $form = New-MainWindow $Files }'))
    $script:Settings.SaveFolder = "$W\out"
    $df = New-MainWindow @("$W\src\single file.txt", "$W\src\Folder A"); $d = $script:MainUi
    Check 'drop: the dropped items are in the list, with Add / Remove and Browse... there too' ($d.List.Items.Count -eq 2 -and $d.List.Items[0] -eq "$W\src\single file.txt" -and $d.Add.Text -eq 'Add Files/Folders' -and $d.Browse.Text -eq 'Browse...')
    Check 'drop: saved next to the first dropped item, not in the remembered folder' ($d.Out.Text -like "$W\src\Encrypted-*.7z") $d.Out.Text
    & $layout 'window started by a drop' $d.Page 7
    $df.Dispose(); $script:MainUi = $m; $script:Settings.Remove('SaveFolder')
    $ScriptDir = "$W\tooldir"
    $own = Get-DroppedItems @("`"$W\tooldir\7z-Encryptor.ps1`"", "$W\tooldir\7Z-ENCRYPTOR.BAT", '')
    $mix = Get-DroppedItems @("$W\tooldir\7z-Encryptor.ps1", "`"$W\src\single file.txt`"")
    Check 'drop: the script dropped on its own launcher starts it with an empty list' ($own.Count -eq 0 -and $mix.Count -eq 1 -and $mix[0] -eq "$W\src\single file.txt")
    Remove-Variable ScriptDir
    Check 'remember: the window has the Remember settings box, showing the same choice' ($m.Remember.Text -eq 'Remember settings' -and $m.Remember.Checked)
    $m.Remember.Checked = $false
    Check 'remember: unticking deletes the settings file' (-not (Test-Path -LiteralPath $sf) -and -not $script:Settings.Remember)
    $script:Settings.EmailMode = 'Program'; Save-EncSettings
    Check 'remember: unticked, later changes are not written' (-not (Test-Path -LiteralPath $sf))
    $bad = @('{not json', '', '[1,2]', 'null', '{"Remember":"yes","SaveFolder":"C:\\x"}', '{"SaveFolder":"C:\\x","EmailMode":"Share"}')
    $n = 0; foreach ($b in $bad) { [IO.File]::WriteAllText($sf, $b); if ((Read-Settings '7z-Encryptor' $EncSettingTypes).Count -eq 0) { $n++ } }
    Check 'damaged file: bad JSON, empty, not an object, or no Remember = true -> no memory at all' ($n -eq $bad.Count) "$n of $($bad.Count)"
    [IO.File]::WriteAllText($sf, '{"Remember":true,"SaveFolder":5,"QuickNextToItem":"x","EmailMode":["a"],"EmailProgram":"C:\\m.exe"}')
    $rs = Read-Settings '7z-Encryptor' $EncSettingTypes
    Check 'damaged file: values of the wrong type are dropped, the rest is kept' ($rs.Remember -and $rs.EmailProgram -eq 'C:\m.exe' -and -not $rs.ContainsKey('SaveFolder') -and -not $rs.ContainsKey('QuickNextToItem') -and -not $rs.ContainsKey('EmailMode'))
    [IO.File]::WriteAllText($sf, '{not json'); $keepS = $script:Settings; $script:Settings = Read-Settings '7z-Encryptor' $EncSettingTypes
    $qf3 = New-MainWindow @("$W\src\single file.txt")
    Check 'damaged file: the window still opens, Remember settings off, defaults used' (-not $script:MainUi.Remember.Checked -and $script:MainUi.RbClassic.Checked); $qf3.Dispose(); $script:MainUi = $m; $script:Settings = $keepS
    Check 'start: a window that fails with the remembered settings is built again with no memory' ($script:BsbEncSource.Contains('catch { if (-not $script:Settings.Count) { throw }; $script:Settings = @{}'))
    Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue
}

# load the tool, but run the tests instead of showing the window (no splash, message boxes answered "Yes")
$code = [IO.File]::ReadAllText((Join-Path $Root 'tools\7z-Encryptor.ps1'))
$script:BsbEncSource = $code; $env:WRT_SETTINGS_DIR = "$W\settings"; [void][IO.Directory]::CreateDirectory($env:WRT_SETTINGS_DIR)
$code = $code.Replace("Show-WrtSplash '7z-Encryptor'", '').Replace('[void]$form.ShowDialog()', '& $tests')
Add-Type -TypeDefinition 'public static class FakeMsg7 { public static string Last = ""; public static string Answer = "Yes"; public static string Show(params object[] a) { Last = a[0].ToString(); return Answer; } }'
$code = $code.Replace('[System.Windows.Forms.MessageBox]::Show(', '[FakeMsg7]::Show(')
try { . ([scriptblock]::Create($code)) } finally { }

# ---- 4. the launcher: drop a file whose name has spaces on the .bat; the window must open ----
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

# ---- 5. names cmd would cut up: the launcher passes its own command line on (7z-Encryptor.bat 1.1) ----
# Explorer quotes a dropped name only when it has a space, so R&D.txt or x^y.txt reach cmd bare. A copy of the
# launcher, in a folder with & and a space, starts the tool's real start code, which writes what the window would list.
$dd = Join-Path $W 'drop R&D'; [void][IO.Directory]::CreateDirectory($dd)
$batText = [IO.File]::ReadAllText("$Root\tools\7z-Encryptor.bat") -replace 'start "" powershell\.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp07z-Encryptor\.ps1"', 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0args.ps1"'
[IO.File]::WriteAllText("$dd\7z-Encryptor.bat", $batText); [IO.File]::WriteAllText("$dd\7z-Encryptor.ps1", 'x')
$src0 = [IO.File]::ReadAllText("$Root\tools\7z-Encryptor.ps1"); $a0 = $src0.IndexOf('# ---------- start ----------'); $b0 = $src0.IndexOf('# if the window cannot be built')
[IO.File]::WriteAllText("$dd\args.ps1", 'param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files); $ScriptDir = $PSScriptRoot' + "`n" + $src0.Substring($a0, $b0 - $a0) + "`n" + '[IO.File]::WriteAllText("$PSScriptRoot\got.txt", ($Files -join "`n"))')
$cases = @(@('R&D.txt'), @('x^y.txt'), @('R&D.txt', 'two words.txt'), @('a b&c.txt'), @('50%off.txt'), @('Wow!.txt'), @('x^^&!%y%.txt', 'p q.txt'), @('(1).txt', 'a;b,c=d.txt'), @('7z-Encryptor.ps1'), @(), @('Sub Dir'))
$badDrops = @()
foreach ($case in $cases) {
    Remove-Item "$dd\got.txt" -ErrorAction SilentlyContinue
    $paths = @($case | ForEach-Object { if ($_ -eq 'Sub Dir') { [void][IO.Directory]::CreateDirectory("$dd\$_") } elseif ($_ -ne '7z-Encryptor.ps1') { [IO.File]::WriteAllText("$dd\$_", 'x') }; "$dd\$_" })
    $argText = ($paths | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }) -join ' '
    Start-Process cmd.exe -ArgumentList "/c `"`"$dd\7z-Encryptor.bat`" $argText`"" -WindowStyle Hidden -Wait
    $got = if (Test-Path "$dd\got.txt") { (Get-Content "$dd\got.txt") -join '|' } else { '(nothing)' }
    if ($got -ne (($paths | Where-Object { $_ -notlike '*\7z-Encryptor.ps1' }) -join '|')) { $badDrops += "$($case -join ' + ') -> $got" }
}
Check "launcher: dropped names with & ^ % ! ; , = ( ) and spaces arrive whole, also in a folder with & ($($cases.Count) drops)" ($badDrops.Count -eq 0) ($badDrops -join '; ')
# started from an open console (cmd's own line is just cmd.exe): the arguments are used as before
Remove-Item "$dd\got.txt" -ErrorAction SilentlyContinue
$cmdIn = "`"$dd\7z-Encryptor.bat`" `"$dd\p q.txt`" `"$dd\R&D.txt`"`r`nexit`r`n"; [IO.File]::WriteAllText("$W\console-in.txt", $cmdIn)
Start-Process cmd.exe -ArgumentList '/q' -RedirectStandardInput "$W\console-in.txt" -RedirectStandardOutput "$W\console-out.txt" -WindowStyle Hidden -Wait
$got = if (Test-Path "$dd\got.txt") { (Get-Content "$dd\got.txt") -join '|' } else { '(nothing)' }
Check 'launcher: started from a console with quoted names, they arrive as typed' ($got -eq "$dd\p q.txt|$dd\R&D.txt") $got
$fn = { param($l, $b) $s = [IO.File]::ReadAllText("$Root\tools\7z-Encryptor.ps1"); $ast = [Management.Automation.Language.Parser]::ParseInput($s, [ref]$null, [ref]$null); . ([scriptblock]::Create($ast.Find({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-LauncherItems' }, $true).Extent.Text)); Get-LauncherItems $l $b }
Check 'launcher line: no launcher in it, or nothing at all, means "use the arguments"' ($null -eq (& $fn 'C:\WINDOWS\system32\cmd.exe' 'C:\t\7z-Encryptor.bat') -and $null -eq (& $fn '' 'C:\t\7z-Encryptor.bat'))
Check 'launcher line: a double-click is an empty list; cmd /k and a launcher path in another case work too' ((& $fn 'C:\WINDOWS\system32\cmd.exe /c ""C:\t\7z-Encryptor.bat" "' 'C:\t\7z-Encryptor.bat').Count -eq 0 -and ((& $fn 'cmd.exe /K ""c:\T\7Z-ENCRYPTOR.BAT" C:\a&b.txt"' 'C:\t\7z-Encryptor.bat') -join '|') -eq 'C:\a&b.txt')
$env:WRT_SETTINGS_DIR = $null
Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "$script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 }
exit 0
