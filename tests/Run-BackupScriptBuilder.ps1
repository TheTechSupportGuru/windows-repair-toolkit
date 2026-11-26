# Run-BackupScriptBuilder.ps1 - tests Backup Script Builder without clicking: loads the tool with its window hidden, then
#   1. builds a script and compares it line by line with the reference FreeFileSync batch file below
#   2. destination folder rules, same-name folders, XML escaping
#   3. creates, reads back and deletes a scheduled task of every schedule type (in \BackupScriptBuilder\, as you)
#   4. layout: no control overlaps another, every "?" has help text
# Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
#   powershell -ExecutionPolicy Bypass -File .\tests\Run-BackupScriptBuilder.ps1
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$script:Fail = 0; $script:Pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:Pass++; Write-Host "PASS  $name" -ForegroundColor Green }
    else { $script:Fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}

$Reference = @'
<?xml version="1.0" encoding="utf-8"?>
<FreeFileSync XmlType="BATCH" XmlFormat="23">
    <Notes/>
    <Compare>
        <Variant>TimeAndSize</Variant>
        <Symlinks>Exclude</Symlinks>
        <IgnoreTimeShift/>
    </Compare>
    <Synchronize>
        <Changes>
            <Left Create="right" Update="right" Delete="right"/>
            <Right Create="none" Update="none" Delete="none"/>
        </Changes>
        <DeletionPolicy>Versioning</DeletionPolicy>
        <VersioningFolder Style="TimeStamp-Folder" MaxAge="365">H:\AutomaticFileBackups\Archive-Deleted</VersioningFolder>
    </Synchronize>
    <Filter>
        <Include>
            <Item>*</Item>
        </Include>
        <Exclude>
            <Item>\System Volume Information\</Item>
            <Item>\$Recycle.Bin\</Item>
            <Item>\RECYCLE?\</Item>
            <Item>\Recovery\</Item>
            <Item>*\thumbs.db</Item>
            <Item>*\desktop.ini</Item>
        </Exclude>
        <SizeMin Unit="None">0</SizeMin>
        <SizeMax Unit="None">0</SizeMax>
        <TimeSpan Type="None">0</TimeSpan>
    </Filter>
    <FolderPairs>
        <Pair>
            <Left>C:\Users\Public</Left>
            <Right>H:\AutomaticFileBackups\Current\Public</Right>
            <Synchronize>
                <Changes>
                    <Left Create="right" Update="right" Delete="right"/>
                    <Right Create="none" Update="none" Delete="none"/>
                </Changes>
                <DeletionPolicy>Versioning</DeletionPolicy>
                <VersioningFolder Style="TimeStamp-Folder" MaxAge="365">H:\AutomaticFileBackups\Archive-Deleted\Public</VersioningFolder>
            </Synchronize>
        </Pair>
        <Pair>
            <Left>C:\Users\Admin\Documents</Left>
            <Right>H:\AutomaticFileBackups\Current\Documents</Right>
            <Synchronize>
                <Changes>
                    <Left Create="right" Update="right" Delete="right"/>
                    <Right Create="none" Update="none" Delete="none"/>
                </Changes>
                <DeletionPolicy>Versioning</DeletionPolicy>
                <VersioningFolder Style="TimeStamp-Folder" MaxAge="365">H:\AutomaticFileBackups\Archive-Deleted\Documents</VersioningFolder>
            </Synchronize>
        </Pair>
    </FolderPairs>
    <Errors Ignore="true" Retry="0" Delay="5"/>
    <PostSyncCommand Condition="Completion"/>
    <LogFolder>H:\AutomaticFileBackups\Logs</LogFolder>
    <EmailNotification Condition="Always"/>
    <GridViewType>Action</GridViewType>
    <Batch>
        <ProgressDialog Minimized="false" AutoClose="true"/>
        <ErrorDialog>Show</ErrorDialog>
        <PostSyncAction>None</PostSyncAction>
    </Batch>
</FreeFileSync>
'@

$tests = {
    # ---- 1. script output ----
    $r = New-BatchXml @('C:\Users\Public', 'C:\Users\Admin\Documents') 'H:\AutomaticFileBackups' 365
    $want = $Reference -split "`r?`n"; $got = ($r.Xml -split "`r`n") | Select-Object -SkipLast 1
    $diff = @(Compare-Object $want $got -SyncWindow 0)
    Check 'script matches the reference FreeFileSync file line for line' ($diff.Count -eq 0) (($diff | Out-String).Trim())
    Check 'script uses CRLF line ends' ($r.Xml -notmatch "[^`r]`n")
    $x = [xml]$r.Xml
    Check 'script is valid XML with 2 folder pairs' ($x.FreeFileSync.FolderPairs.Pair.Count -eq 2)
    $r2 = New-BatchXml @('C:\A\Docs', 'D:\B\Docs', 'E:\', 'C:\R&D') 'X:\Backups\AutomaticFileBackups' 30
    $rights = @(([xml]$r2.Xml).FreeFileSync.FolderPairs.Pair | ForEach-Object { $_.Right })
    Check 'same-name folders get -2, a drive root gets <letter>-Drive' (($rights -join '|') -eq 'X:\Backups\AutomaticFileBackups\Current\Docs|X:\Backups\AutomaticFileBackups\Current\Docs-2|X:\Backups\AutomaticFileBackups\Current\E-Drive|X:\Backups\AutomaticFileBackups\Current\R&D') ($rights -join '|')
    Check 'ampersand is escaped in the file' ($r2.Xml -match 'C:\\R&amp;D')
    Check 'keep days fills every MaxAge' (([regex]::Matches($r2.Xml, 'MaxAge="30"')).Count -eq 5)

    # ---- 2. destination rules + a real build into a temp folder ----
    $txtDest.Text = 'C:\Somewhere\Backups'; Check 'destination gets \AutomaticFileBackups added' ((Get-DestRoot) -eq 'C:\Somewhere\Backups\AutomaticFileBackups')
    $txtDest.Text = 'D:\AutomaticFileBackups\'; Check 'a folder already named AutomaticFileBackups is used as is' ((Get-DestRoot) -eq 'D:\AutomaticFileBackups')
    $tmp = Join-Path $env:TEMP ('bsb-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $src = Join-Path $tmp 'Source Folder'; [void](New-Item -ItemType Directory -Force $src)
    $dst = Join-Path $tmp 'Dest\AutomaticFileBackups'
    $rb = New-BatchXml @($src) $dst 365
    foreach ($d in $rb.Dirs) { [void][IO.Directory]::CreateDirectory($d) }
    [IO.File]::WriteAllText("$dst\BackupScript.ffs_batch", $rb.Xml, (New-Object Text.UTF8Encoding $false))
    $made = @('Current', 'Archive-Deleted', 'Logs', 'Current\Source Folder') | Where-Object { Test-Path (Join-Path $dst $_) }
    Check 'build creates Current, Archive-Deleted, Logs and the pair folder' ($made.Count -eq 4)
    $bytes = [IO.File]::ReadAllBytes("$dst\BackupScript.ffs_batch")
    Check 'script file is written without a BOM' ($bytes[0] -eq 0x3C)

    # ---- 3. scheduled tasks ----
    Add-ScriptChoice "$dst\BackupScript.ffs_batch"
    $exe = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
    $act = New-ScheduledTaskAction -Execute $exe -Argument ('"' + "$dst\BackupScript.ffs_batch" + '"')
    $at = [datetime]::Today.AddDays(1).AddHours(3).AddMinutes(15)
    $cases = [ordered]@{
        'zz-test once'   = @((New-ScheduledTaskTrigger -Once -At $at), $FreqOnce, 1, '')
        'zz-test daily'  = @((New-ScheduledTaskTrigger -Daily -At $at -DaysInterval 3), $FreqDaily, 3, '')
        'zz-test weekly' = @((New-ScheduledTaskTrigger -Weekly -At $at -WeeksInterval 2 -DaysOfWeek Monday, Thursday), $FreqWeekly, 2, 'Mon/Thu')
        'zz-test hours'  = @((New-ScheduledTaskTrigger -Once -At $at -RepetitionInterval (New-TimeSpan -Hours 6)), $FreqHours, 6, '')
        'zz-test logon'  = @((New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)), $FreqLogon, 1, '')
    }
    try {
        foreach ($k in $cases.Keys) {
            $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 8); $s.StartWhenAvailable = $true
            [void](Register-ScheduledTask -TaskPath $TaskFolder -TaskName $k -Action $act -Trigger $cases[$k][0] -Settings $s -Force)
        }
        Update-TaskList
        Check 'task list shows the test tasks' (@($cboTask.Items | Where-Object { $_ -like 'zz-test *' }).Count -eq 5)
        foreach ($k in $cases.Keys) {
            $cboTask.SelectedItem = $k
            $days = (@($dayBoxes | Where-Object Checked | ForEach-Object { $_.Text }) -join '/')
            $ok = ($cboFreq.SelectedItem -eq $cases[$k][1]) -and ([int]$numEvery.Value -eq $cases[$k][2]) -and ($days -eq $cases[$k][3]) -and
                  ($cboLimit.SelectedItem -eq '8 hours') -and $chkMissed.Checked -and ($cboScript.Text -eq "$dst\BackupScript.ffs_batch") -and ($txtExe.Text -eq $exe) -and
                  ($btnSave.Text -eq 'Save Changes') -and $btnDelete.Enabled
            if ($cases[$k][1] -ne $FreqLogon) { $ok = $ok -and ($dtTime.Value.TimeOfDay -eq $at.TimeOfDay) -and ($dtDate.Value.Date -eq $at.Date) }
            Check "task '$k' reads back into the form" $ok "freq=$($cboFreq.SelectedItem) every=$($numEvery.Value) days=$days limit=$($cboLimit.SelectedItem) missed=$($chkMissed.Checked) time=$($dtTime.Value)"
        }
        $cboTask.SelectedItem = $NewTaskText
        Check '<New task> resets the form' (($txtName.Text -eq '') -and ($btnSave.Text -eq 'Create Task') -and -not $btnDelete.Enabled)
    } finally {
        foreach ($k in $cases.Keys) { Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $k -Confirm:$false -ErrorAction SilentlyContinue }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    Update-TaskList
    Check 'test tasks are deleted' (@($cboTask.Items | Where-Object { $_ -like 'zz-test *' }).Count -eq 0)

    # (PerformClick does nothing on a window that was never shown, so raise the Click event directly)
    function Invoke-Click($b) { $b.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($b, @([EventArgs]::Empty)) }
    # ---- 3b. the real Create / Save / Delete buttons (message boxes answered "Yes" by the test) ----
    $tmp2 = Join-Path $env:TEMP ('bsb-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); [void](New-Item -ItemType Directory -Force $tmp2)
    $bat = Join-Path $tmp2 'BackupScript.ffs_batch'; Set-Content $bat 'x'
    try {
        $cboTask.SelectedItem = $NewTaskText
        $txtName.Text = 'zz-test button'; $cboScript.Text = $bat; $cboFreq.SelectedItem = $FreqWeekly; $numEvery.Value = 1
        foreach ($cb in $dayBoxes) { $cb.Checked = $cb.Tag -in 'Tuesday', 'Saturday' }
        $dtDate.Value = [datetime]::Today.AddDays(2); $dtTime.Value = [datetime]::Today.AddHours(21).AddMinutes(30)
        $chkMissed.Checked = $false; $cboLimit.SelectedItem = '30 minutes'
        Invoke-Click $btnSave
        $t = Get-ScheduledTask -TaskPath $TaskFolder -TaskName 'zz-test button' -ErrorAction SilentlyContinue
        Check 'Create Task button registers the task' ($t -and $t.Triggers[0].DaysOfWeek -eq (4 + 64) -and -not $t.Settings.StartWhenAvailable -and $t.Settings.ExecutionTimeLimit -eq 'PT30M' -and
            $t.Actions[0].Arguments -eq ('"' + $bat + '"') -and $t.Actions[0].Execute -eq 'C:\Program Files\FreeFileSync\FreeFileSync.exe') ([FakeMsg]::Last)
        Check 'the new task is selected afterwards' ($cboTask.SelectedItem -eq 'zz-test button')
        $txtName.Text = 'zz-test renamed'; $cboFreq.SelectedItem = $FreqDaily; $numEvery.Value = 2
        Invoke-Click $btnSave
        $old = Get-ScheduledTask -TaskPath $TaskFolder -TaskName 'zz-test button' -ErrorAction SilentlyContinue
        $new = Get-ScheduledTask -TaskPath $TaskFolder -TaskName 'zz-test renamed' -ErrorAction SilentlyContinue
        Check 'Save Changes with a new name replaces the old task' (-not $old -and $new -and $new.Triggers[0].DaysInterval -eq 2) ([FakeMsg]::Last)
        Invoke-Click $btnDelete
        Check 'Delete Task removes it' (-not (Get-ScheduledTask -TaskPath $TaskFolder -TaskName 'zz-test renamed' -ErrorAction SilentlyContinue))
        $cboTask.SelectedItem = $NewTaskText; $txtName.Text = 'zz-test bad'; $cboScript.Text = 'C:\does\not\exist.ffs_batch'
        Invoke-Click $btnSave
        Check 'a missing script is refused' (-not (Get-ScheduledTask -TaskPath $TaskFolder -TaskName 'zz-test bad' -ErrorAction SilentlyContinue) -and [FakeMsg]::Last -match 'exists')
        # (1.1) Robocopy / Xcopy tasks: a .ps1 runs with PowerShell, a .bat with cmd, and both read back with their type
        foreach ($c in @(@('Robocopy', 'BackupScript-Robocopy.ps1', 'powershell.exe'), @('Xcopy', 'BackupScript-Xcopy.bat', 'cmd.exe'))) {
            $sp = Join-Path $tmp2 $c[1]; Set-Content $sp 'rem test'
            $cboTask.SelectedItem = $NewTaskText; $cboType.SelectedItem = $c[0]; $txtName.Text = "zz-test $($c[0])"; $cboScript.Text = $sp; $cboFreq.SelectedItem = $FreqDaily
            Check "$($c[0]) type hides the FreeFileSync.exe row" (-not $txtExe.Visible -and -not $lblExe.Visible)
            Invoke-Click $btnSave
            $t = Get-ScheduledTask -TaskPath $TaskFolder -TaskName "zz-test $($c[0])" -ErrorAction SilentlyContinue
            Check "$($c[0]) task runs its script with $($c[2])" ($t -and $t.Actions[0].Execute -eq $c[2] -and $t.Actions[0].Arguments -like "*`"$sp`"" -and $t.Description -match $c[0]) ("$($t.Actions[0].Execute) $($t.Actions[0].Arguments) / " + [FakeMsg]::Last)
            $cboTask.SelectedItem = $NewTaskText; $cboTask.SelectedItem = "zz-test $($c[0])"
            Check "$($c[0]) task reads back as $($c[0]) with its script" ($cboType.SelectedItem -eq $c[0] -and $cboScript.Text -eq $sp) "$($cboType.SelectedItem) $($cboScript.Text)"
        }
    } finally {
        foreach ($k in 'zz-test button', 'zz-test renamed', 'zz-test bad', 'zz-test Robocopy', 'zz-test Xcopy') { Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $k -Confirm:$false -ErrorAction SilentlyContinue }
        Remove-Item -Recurse -Force $tmp2 -ErrorAction SilentlyContinue
    }

    # ---- 5. (1.1) folder picker: user folders, OneDrive, junctions ----
    $qf = @(Get-QuickFolders)
    Check 'Quick picks list Desktop and Documents (wherever they really are)' (($qf.Name -contains 'Desktop') -and ($qf.Name -contains 'Documents')) (($qf | ForEach-Object { $_.Name + '=' + $_.Path }) -join '; ')
    if ($env:OneDrive) { Check 'Quick picks list OneDrive' (@($qf | Where-Object { $_.Name -like 'OneDrive*' }).Count -gt 0) }
    $jt = Join-Path $env:TEMP ('bsb-junction-' + (Get-Random)); New-Item -ItemType Directory -Force "$jt\real" | Out-Null
    New-Item -ItemType Junction -Path "$jt\link" -Target "$jt\real" -ErrorAction SilentlyContinue | Out-Null
    Check 'a real folder is listed in the picker' (-not (Test-SkipFolder (New-Object IO.DirectoryInfo "$jt\real")))
    if (Test-Path "$jt\link") { Check 'a junction is still skipped (no loops)' (Test-SkipFolder (New-Object IO.DirectoryInfo "$jt\link")) }
    cmd /c rmdir "$jt\link" 2>$null; Remove-Item $jt -Recurse -Force -ErrorAction SilentlyContinue

    # ---- 5b. (1.2) nothing in the user folder is left out, nothing is listed twice, system folders on request ----
    $open = { param($path) $n = New-Object Windows.Forms.TreeNode 'x'; $n.Tag = $path; Add-DummyChild $n; Expand-FolderNode $n; $n }
    $script:ShowSystem = $false
    $links = @(cmd /c dir /b /al "$env:USERPROFILE" 2>$null)
    $real = @(Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force | Where-Object { $links -notcontains $_.Name } | ForEach-Object Name)
    $shown = @((& $open $env:USERPROFILE).Nodes | ForEach-Object Text)
    $miss = @($real | Where-Object { $shown -notcontains $_ })
    Check 'every real folder in the user folder is listed (hidden ones too)' ($miss.Count -eq 0 -and $real.Count -gt 3) ("missing: " + ($miss -join ', '))
    $dupe = @($shown | Where-Object { $links -contains $_ })
    Check 'the profile''s own junctions (My Documents, Application Data ...) are not listed' ($dupe.Count -eq 0) ($dupe -join ', ')
    if (Test-Path -LiteralPath "$env:USERPROFILE\Application Data") { Check 'a junction that denies reading is still recognised' (Test-SkipFolder (New-Object IO.DirectoryInfo "$env:USERPROFILE\Application Data")) }
    $usersShown = @((& $open (Split-Path $env:USERPROFILE)).Nodes | ForEach-Object Text)
    Check 'every user profile folder is listed under Users' ($usersShown -contains (Split-Path $env:USERPROFILE -Leaf) -and $usersShown -contains 'Public' -and $usersShown -notcontains 'All Users' -and $usersShown -notcontains 'Default User') ($usersShown -join ', ')
    $sysRoot = $env:SystemDrive + '\'
    $c = & $open $sysRoot; $t = @($c.Nodes | ForEach-Object Text)
    Check 'system folders are hidden by default (Windows, Program Files, ProgramData)' ($t -contains 'Users' -and $t -notcontains 'Windows' -and $t -notcontains 'Program Files' -and $t -notcontains 'ProgramData' -and $t -notcontains '$Recycle.Bin') ($t -join ', ')
    $script:ShowSystem = $true; Update-SystemNodes @($c); $t2 = @($c.Nodes | ForEach-Object Text)
    Check 'ticking "Show Windows and program folders" lists them, in order' ($t2 -contains 'Windows' -and $t2 -contains 'Program Files' -and $t2 -contains 'Users' -and $t2 -notcontains 'Documents and Settings' -and (($t2 -join '|') -eq ((@($t2 | Sort-Object)) -join '|'))) ($t2 -join ', ')
    $script:ShowSystem = $false; Update-SystemNodes @($c); $t3 = @($c.Nodes | ForEach-Object Text)
    Check 'unticking hides them again' (($t3 -join '|') -eq ($t -join '|')) ($t3 -join ', ')
    if (Test-Path -LiteralPath "$env:USERPROFILE\My Documents") { $na = & $open "$env:USERPROFILE\My Documents" } else { $na = & $open "$sysRoot`System Volume Information" }
    Check 'a folder that cannot be opened says so (and cannot be ticked)' ($na.Nodes.Count -eq 1 -and $na.Nodes[0].Name -eq 'info') (@($na.Nodes | ForEach-Object Text) -join ', ')
    $u = Get-UniqueFolders @('C:\Users\a\Desktop', 'C:\Users\a', 'c:\users\A\', 'D:\x', 'D:\xy', 'E:\', 'E:\Data', 'F:\One')
    Check 'ticked folders: no duplicates, nothing inside another ticked folder' (($u -join '|') -eq 'E:\|D:\x|D:\xy|F:\One|C:\Users\a') ($u -join '|')
    $qf2 = @(Get-QuickFolders)
    Check 'Quick picks have no duplicate paths' (@($qf2.Path | ForEach-Object { $_.ToLower() } | Sort-Object -Unique).Count -eq $qf2.Count)

    # the real dialog: buttons inside the window, the tick box works, Add Checked returns the folders
    $script:PickerChecks = @{}
    $tm = New-Object Windows.Forms.Timer; $tm.Interval = 300
    $tm.add_Tick({
        $tm.Stop(); $d = $script:PickerForm; $tr = $script:PickerTree
        try {
            $cw = $d.ClientSize.Width
            $script:PickerChecks.Buttons = @($d.AcceptButton, $d.CancelButton | Where-Object { $_.Visible -and ($_.Parent.Left + $_.Right) -le $cw -and $_.Left -ge 0 }).Count
            $drv = @($tr.Nodes | Where-Object { $_.Tag -and ([string]$_.Tag) -ieq ($env:SystemDrive + '\') })[0]
            $script:PickerChecks.UsersOpen = [bool]($drv -and $drv.IsExpanded -and @($drv.Nodes | Where-Object { $_.Text -eq 'Users' -and $_.IsExpanded }).Count)
            $script:PickerChecks.NoWindows = -not @($drv.Nodes | Where-Object { $_.Text -eq 'Windows' }).Count
            $script:PickerShowSystem.Checked = $true
            $script:PickerChecks.Windows = [bool]@($drv.Nodes | Where-Object { $_.Text -eq 'Windows' }).Count
            $script:PickerShowSystem.Checked = $false
            $q = $tr.Nodes[0]
            foreach ($n in $q.Nodes) { if ($n.Text -like 'Desktop  -  *' -or $n.Text -like 'Your user folder  -  *') { $n.Checked = $true } }
            $d.AcceptButton.PerformClick()
        } catch { $script:PickerChecks.Error = "$_"; $d.Close() }
    })
    $tm.Start(); $picked = @(Show-FolderPicker); $tm.Dispose()
    Check 'picker: Add Checked and Cancel are inside the window' ($script:PickerChecks.Buttons -eq 2) "$($script:PickerChecks.Error)"
    Check 'picker: opens with the Windows drive and Users expanded' ([bool]$script:PickerChecks.UsersOpen)
    Check 'picker: system folders appear only while the tick box is ticked' ($script:PickerChecks.NoWindows -and $script:PickerChecks.Windows)
    Check 'picker: Desktop + the user folder ticked gives just the user folder' ($picked.Count -eq 1 -and $picked[0] -ieq $env:USERPROFILE.TrimEnd('\')) ($picked -join '; ')

    # ---- 6. (1.1) Robocopy / Xcopy scripts, run for real on test folders ----
    $w = Join-Path $env:TEMP ('bsb-copy-' + (Get-Random)); New-Item -ItemType Directory -Force "$w\src\Docs\sub", "$w\src2\Pics", "$w\x" | Out-Null
    'one' | Set-Content "$w\src\Docs\a.txt"; 'two' | Set-Content "$w\src\Docs\sub\b.txt"; 'pic' | Set-Content "$w\src2\Pics\p.txt"
    # a second drive letter (subst, no admin needed) so the per-drive threads have two drives to run at once
    $sd = @('Q', 'R', 'S', 'T') | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
    if ($sd) { subst "${sd}:" "$w\src2" | Out-Null }
    $src2 = if ($sd) { "${sd}:\Pics" } else { "$w\src2\Pics" }
    $robo = @($RoboSwitches | Where-Object On | ForEach-Object { $_.Key }); $xc = @($XcopySwitches | Where-Object On | ForEach-Object { $_.Key })
    $cases = @(
        @{ T = 'Robocopy'; F = 'ps1'; P = $false; L = @{ Enabled = $true; Mode = 'New'; Date = $true; Time = $true } }
        @{ T = 'Robocopy'; F = 'bat'; P = $false; L = @{ Enabled = $true; Mode = 'Append' } }
        @{ T = 'Robocopy'; F = 'ps1'; P = $true;  L = @{ Enabled = $true; Mode = 'Append' } }
        @{ T = 'Robocopy'; F = 'bat'; P = $true;  L = @{ Enabled = $true; Mode = 'New'; Date = $true } }
        @{ T = 'Xcopy';    F = 'ps1'; P = $false; L = @{ Enabled = $true; Mode = 'Append' } }
        @{ T = 'Xcopy';    F = 'bat'; P = $false; L = @{ Enabled = $true; Mode = 'New'; Date = $true; Time = $true } }
        @{ T = 'Xcopy';    F = 'bat'; P = $false; L = @{ Enabled = $false } }
    )
    $n = 0
    foreach ($c in $cases) {
        $n++; $root = "$w\dest$n\AutomaticFileBackups"
        $sw = if ($c.T -eq 'Robocopy') { $robo | Where-Object { $_ -ne '/TEE' } } else { $xc }
        $r = New-CopyScript $c.T $c.F @("$w\src\Docs", $src2) $root $sw $c.L $c.P $(if ($c.T -eq 'Robocopy') { 4 } else { 0 })
        foreach ($d in $r.Dirs) { [void][IO.Directory]::CreateDirectory($d) }
        if ($c.F -eq 'bat') { [IO.File]::WriteAllText($r.File, $r.Text, [Text.Encoding]::Default) } else { [IO.File]::WriteAllText($r.File, $r.Text, (New-Object Text.UTF8Encoding $true)) }
        $label = "$($c.T) .$($c.F)" + $(if ($c.P) { ' per-drive threads' } else { '' }) + ' log ' + $(if ($c.L.Enabled) { $c.L.Mode } else { 'off' })
        $runs = if ($c.L.Mode -eq 'Append') { 2 } else { 1 }
        $code = 0
        for ($k = 0; $k -lt $runs; $k++) {
            if ($c.F -eq 'ps1') { $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $r.File 2>&1 } else { $null = & cmd.exe /c "`"$($r.File)`"" 2>&1 }
            $code = $LASTEXITCODE
        }
        $copied = (Test-Path "$root\Current\Docs\a.txt") -and (Test-Path "$root\Current\Docs\sub\b.txt") -and (Test-Path "$root\Current\Pics\p.txt")
        Check "$label : script runs and copies every folder (exit $code)" ($code -eq 0 -and $copied) ($r.File)
        $logs = @(Get-ChildItem "$root\Logs" -Filter *.log -ErrorAction SilentlyContinue)
        if (-not $c.L.Enabled) { Check "$label : no log written" ($logs.Count -eq 0) }
        else {
            $want = if ($c.P) { 2 } else { 1 }   # one log per drive when the drives run at the same time
            Check "$label : log files ($want expected)" ($logs.Count -eq $want) (($logs.Name) -join ', ')
            if ($c.L.Mode -eq 'New' -and $c.L.Date) { Check "$label : log name has the date" (@($logs | Where-Object { $_.Name -match '\d{4}-\d{2}-\d{2}' }).Count -eq $logs.Count) (($logs.Name) -join ', ') }
            if ($c.L.Mode -eq 'Append' -and -not $c.P) {
                $txt = Get-Content $logs[0].FullName -Raw
                $hits = ([regex]::Matches($txt, $(if ($c.T -eq 'Robocopy') { 'Started :' } else { 'File\(s\) copied' }))).Count
                Check "$label : the 2nd run appended to the same log" ($hits -ge 2) "$hits run(s) in the log"
            }
        }
    }
    if ($sd) { subst "${sd}:" /D | Out-Null }
    Remove-Item $w -Recurse -Force -ErrorAction SilentlyContinue

    # ---- 4. layout ----
    # the three "what to create" pages are alternatives in the same place: each is checked on its own
    $typePages = @($pnlFfs, $pnlRobo, $pnlXcopy)
    foreach ($page in @($tabBuild, $tabSched) + $typePages) {
        $ctl = @($page.Controls | Where-Object { $_.Visible -or $true })
        $bad = @()
        for ($i = 0; $i -lt $ctl.Count; $i++) { for ($j = $i + 1; $j -lt $ctl.Count; $j++) {
            $a = $ctl[$i]; $b = $ctl[$j]
            if ($typePages -contains $a -and $typePages -contains $b) { continue }
            $ra = $a.Bounds; $rb2 = $b.Bounds
            if ($a -is [Windows.Forms.Label] -and $a.AutoSize) { $ra.Size = $a.PreferredSize }
            if ($b -is [Windows.Forms.Label] -and $b.AutoSize) { $rb2.Size = $b.PreferredSize }
            if ($a -is [Windows.Forms.CheckBox]) { $ra.Size = $a.PreferredSize }
            if ($b -is [Windows.Forms.CheckBox]) { $rb2.Size = $b.PreferredSize }
            if ($ra.IntersectsWith($rb2)) { $bad += "$($a.GetType().Name)'$($a.Text)' x $($b.GetType().Name)'$($b.Text)'" }
        } }
        $pname = if ($page.Text) { $page.Text } else { 'type page ' + ($typePages.IndexOf($page) + 1) }
        Check "no overlapping controls on '$pname'" ($bad.Count -eq 0) ($bad -join '; ')
        $help = @($page.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '?' })
        $min = if ($typePages -contains $page) { 1 } elseif ($page -eq $tabBuild) { 3 } else { 4 }
        Check "'$pname' has ? buttons, all with help text" ($help.Count -ge $min -and -not @($help | Where-Object { -not $_.Tag[1] }).Count) "$($help.Count) buttons"
    }
    Check 'FreeFileSync link points at https://freefilesync.org/' ($lnkFfs.Text.Substring($lnkFfs.LinkArea.Start, $lnkFfs.LinkArea.Length) -eq 'https://freefilesync.org/')
}

# load the tool, but run the tests instead of showing the window (and with no splash screen)
$code = [IO.File]::ReadAllText((Join-Path $Root 'tools\BackupScriptBuilder.ps1'))
$code = $code.Replace("Show-WrtSplash 'Backup Script Builder'", '').Replace('[void]$form.ShowDialog()', '& $tests')
# message boxes are answered "Yes" (and remembered) instead of waiting for a click
Add-Type -TypeDefinition 'public static class FakeMsg { public static string Last = ""; public static string Show(params object[] a) { Last = a[0].ToString(); return "Yes"; } }'
$code = $code.Replace('[System.Windows.Forms.MessageBox]::Show(', '[FakeMsg]::Show(')
[void]$form   # (keeps PSScriptAnalyzer quiet about $form being set in the loaded code)
. ([scriptblock]::Create($code))
Write-Host ''
Write-Host "$script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 }
