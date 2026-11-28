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

    # ---- 3. scheduled tasks (1.9: Windows PE has no Task Scheduler: the tab is greyed out there with the reason) ----
    if ($SchedOff) {
        Check 'WinPE (1.9): Schedule Task tab greyed out, the reason shown, no task read' (-not $cboTask.Enabled -and -not $btnSave.Enabled -and -not $btnRun.Enabled -and $lblStatus.Text -match 'Windows PE' -and @(Get-OurTasks).Count -eq 0) $lblStatus.Text
    } else {
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
    }   # not WinPE

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
            # Test Center starts this script minimized, and Windows then shows the first window of the process (this
            # dialog) minimized too, 0 wide: measure it at its normal size
            if ($d.WindowState -eq 'Minimized') { $d.WindowState = 'Normal'; [Windows.Forms.Application]::DoEvents() }
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
    foreach ($page in @($tabBuild, $tabSched, $tabManual, $mGrpEngine) + $typePages) {
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
        $pname = if ($page -eq $mGrpEngine) { 'zip engine group' } elseif ($page.Text) { $page.Text } else { 'type page ' + ($typePages.IndexOf($page) + 1) }
        Check "no overlapping controls on '$pname'" ($bad.Count -eq 0) ($bad -join '; ')
        if ($page -eq $mGrpEngine) { continue }
        $help = @($page.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '?' })
        $min = if ($typePages -contains $page) { 1 } elseif ($page -eq $tabBuild) { 3 } else { 4 }
        Check "'$pname' has ? buttons, all with help text" ($help.Count -ge $min -and -not @($help | Where-Object { -not $_.Tag[1] }).Count) "$($help.Count) buttons"
    }
    Check 'FreeFileSync link points at https://freefilesync.org/' ($lnkFfs.Text.Substring($lnkFfs.LinkArea.Start, $lnkFfs.LinkArea.Length) -eq 'https://freefilesync.org/')

    # ---- 5. Manual Backup tab (1.3): which options are open, checks before starting, real runs in the background ----
    $real7 = $script:SevenZip
    $script:SevenZip = $null; $mRbFolder.Checked = $true; Update-ManualUi
    Check 'manual: without 7-Zip the 7z type, the 7-Zip engine and the password are off' (-not $mRb7z.Enabled -and -not $mRb7Engine.Enabled -and -not $mPw.Enabled -and $m7Status.Text -match '7-zip.org')
    Check 'manual: folder copy has no compression, engine or self-extracting choice' (-not $mLevel.Enabled -and -not $mGrpEngine.Enabled -and -not $mSfx.Enabled)
    $mRbZip.Checked = $true
    Check 'manual: Windows zip offers Store / Normal / Ultra, no password' ($mLevel.Enabled -and $mGrpEngine.Enabled -and $mRbWin.Checked -and -not $mPw.Enabled -and (($mLevel.Items | ForEach-Object { $_ }) -join ',') -eq 'Store,Normal,Ultra')
    # 1.8: Ultra is 7-Zip only - greyed out for Windows zip and cannot be picked
    $mLevel.SelectedItem = 'Ultra'
    Check 'manual: Windows zip: Ultra is greyed out and cannot be picked (goes back to Normal)' ($script:UltraOff -and [string]$mLevel.SelectedItem -eq 'Normal' -and $mLevel.DrawMode -eq 'OwnerDrawFixed')
    Check 'manual: Windows zip never asks for Ultra' ((Get-ManualOptions).Level -eq 'Normal')
    $script:SevenZip = 'C:\fake\7z.exe'; Update-ManualUi; $mRb7Engine.Checked = $true
    $mLevel.SelectedItem = 'Ultra'
    Check 'manual: zip by 7-Zip can pick Ultra' (-not $script:UltraOff -and [string]$mLevel.SelectedItem -eq 'Ultra' -and (Get-ManualOptions).Level -eq 'Ultra')
    $mRbWin.Checked = $true
    Check 'manual: switching back to Windows zip turns Ultra into Normal' ($script:UltraOff -and [string]$mLevel.SelectedItem -eq 'Normal')
    $mRb7Engine.Checked = $true
    Check 'manual: zip by 7-Zip opens the password, not the self-extractor' ($mPw.Enabled -and $mPw2.Enabled -and -not $mSfx.Enabled -and -not $mEncNames.Enabled)
    $mRb7z.Checked = $true
    Check 'manual: 7z opens password, hidden names and self-extracting' ($mPw.Enabled -and $mEncNames.Enabled -and $mSfx.Enabled -and -not $mGrpEngine.Enabled)
    $mSfx.SelectedIndex = 1; $mRbZip.Checked = $true
    Check 'manual: leaving 7z resets self-extracting to No' ($mSfx.SelectedIndex -eq 0)
    $script:SevenZip = $real7; $mRbWin.Checked = $true; Update-ManualUi

    # ---- 1.8: drag and drop from Explorer (the real DragEnter / DragDrop handlers, with an Explorer-style file list) ----
    $dd = Join-Path $env:TEMP ('bsb-drop-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    foreach ($x in "$dd\Folder A", "$dd\R&D [1]") { [void](New-Item -ItemType Directory -Force $x) }; 'x' | Set-Content "$dd\Folder A\f.txt"
    $bf = [Reflection.BindingFlags]'NonPublic, Instance'
    $fire = { param($ctl, $data) $e = New-Object Windows.Forms.DragEventArgs(([Windows.Forms.IDataObject]$data.psobject.BaseObject), 0, 0, 0, 'Copy', 'None'); $c0 = $ctl.psobject.BaseObject; $a0 = [object[]]@($e.psobject.BaseObject); [void][Windows.Forms.Control].GetMethod('OnDragEnter', $bf).Invoke($c0, $a0); if ($e.Effect -eq 'Copy') { [void][Windows.Forms.Control].GetMethod('OnDragDrop', $bf).Invoke($c0, $a0) }; [string]$e.Effect }
    $files = { param([string[]]$p) $o = New-Object Windows.Forms.DataObject; $sc = New-Object Collections.Specialized.StringCollection; $sc.AddRange($p); $o.SetFileDropList($sc); $o }
    $keepItems = @($mLst.Items); $keepMDest = $mDest.Text; $keepDest = $txtDest.Text; $mLst.Items.Clear()
    $eff = & $fire $mLst (& $files @("$dd\Folder A", "$dd\Folder A\f.txt", "$dd\gone.txt"))
    Check 'drop (1.8): files and folders dragged onto What to back up are added, a missing one is skipped' ($eff -eq 'Copy' -and $mLst.Items.Count -eq 2 -and $mLst.Items[0] -eq "$dd\Folder A" -and $mLst.Items[1] -eq "$dd\Folder A\f.txt") (($mLst.Items | ForEach-Object { $_ }) -join ' | ')
    [void](& $fire $mLst (& $files @("$dd\FOLDER A", "$dd\R&D [1]")))
    Check 'drop (1.8): an item already in the list is not added twice; R&D [1] arrives whole' ($mLst.Items.Count -eq 3 -and $mLst.Items[2] -eq "$dd\R&D [1]")
    $eff = & $fire $mLst (New-Object Windows.Forms.DataObject([Windows.Forms.DataFormats]::Text, 'C:\x'))
    Check 'drop (1.8): dragged text (not files) is refused' ($eff -eq 'None' -and $mLst.Items.Count -eq 3)
    $mDest.Text = ''; [void](& $fire $mDest (& $files @("$dd\R&D [1]")))
    Check 'drop (1.8): a folder dropped on Save to fills it in' ($mDest.Text -eq "$dd\R&D [1]")
    [void](& $fire $mDest (& $files @("$dd\Folder A\f.txt", "$dd\R&D [1]")))
    Check 'drop (1.8): a file dropped on Save to puts in its folder (the first item counts)' ($mDest.Text -eq "$dd\Folder A")
    [void](& $fire $txtDest (& $files @("$dd\R&D [1]")))
    Check 'drop (1.8): a folder dropped on the Build Script Destination folder fills it in' ($txtDest.Text -eq "$dd\R&D [1]")
    [void](& $fire $txtDest (& $files @("$dd\gone")))
    Check 'drop (1.8): a folder that is not there changes nothing' ($txtDest.Text -eq "$dd\R&D [1]")
    $all = New-Object Collections.ArrayList; $walk = { param($c) foreach ($k in $c.Controls) { [void]$all.Add($k); & $walk $k } }; & $walk $form
    $logBoxes = @($all | Where-Object { $_ -is [Windows.Forms.TextBox] -and $_.Location.X -eq 130 -and $_.Location.Y -eq 67 })
    $okLog = 0; foreach ($lb in $logBoxes) {
        $keepEn = $lb.Enabled; $lb.Enabled = $false; $offEff = & $fire $lb (& $files @("$dd\Folder A"))
        $lb.Enabled = $true; [void](& $fire $lb (& $files @("$dd\Folder A")))
        if ($offEff -eq 'None' -and $lb.Text -eq "$dd\Folder A") { $okLog++ }; $lb.Text = ''; $lb.Enabled = $keepEn }
    Check 'drop (1.8): the Robocopy and Xcopy Log folder boxes take a dropped folder, not while they are off' ($logBoxes.Count -eq 2 -and $okLog -eq 2) "$okLog of $($logBoxes.Count)"
    Check 'drop (1.8): every folder box and the list accept drops' ($mLst.AllowDrop -and $mDest.AllowDrop -and $txtDest.AllowDrop)
    $mLst.Items.Clear(); foreach ($i in $keepItems) { [void]$mLst.Items.Add($i) }; $mDest.Text = $keepMDest; $txtDest.Text = $keepDest
    Remove-Item -Recurse -Force $dd -ErrorAction SilentlyContinue

    $mw = Join-Path $env:TEMP ('bsb-manual-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory "$mw\src\Docs\Empty", "$mw\src\Pics" -Force | Out-Null
    'd' | Set-Content "$mw\src\Docs\d.txt"; 'p' | Set-Content "$mw\src\Pics\p.txt"; 'x' | Set-Content "$mw\src\Pics\x.txt"
    $mLst.Items.Clear(); [void]$mLst.Items.Add("$mw\src\Docs"); [void]$mLst.Items.Add("$mw\src\Pics\p.txt"); $mDest.Text = "$mw\out"
    $o = Get-ManualOptions
    Check 'manual: options read from the tab' ($o.Mode -eq 'Zip' -and $o.Engine -eq 'Windows' -and $o.Level -eq 'Normal' -and $o.Sources.Count -eq 2 -and $o.Dest -eq "$mw\out" -and -not $o.Password)
    Check 'manual: refuses a destination inside a source' ((Test-ManualOptions (@{} + $o + @{}) '') -eq '' -and (Test-ManualOptions @{ Sources = @("$mw\src"); Dest = "$mw\src\b" } '') -match 'inside')
    Check 'manual: refuses two different passwords' ((Test-ManualOptions @{ Sources = @('C:\a'); Dest = 'D:\b'; Password = 'one' } 'two') -match 'not the same')
Check 'manual: a non-ASCII password is refused for a 7-Zip zip, allowed for 7z' (((Test-ManualOptions @{ Sources = @('C:\a'); Dest = 'D:\b'; Mode = 'Zip'; Password = ('p' + [char]0xE9) } ('p' + [char]0xE9)) -match 'zip password') -and ((Test-ManualOptions @{ Sources = @('C:\a'); Dest = 'D:\b'; Mode = '7z'; Password = ('p' + [char]0xE9) } ('p' + [char]0xE9)) -eq ''))
    Check 'manual: refuses no sources and a relative destination' ((Test-ManualOptions @{ Sources = @(); Dest = 'D:\b' } '') -and (Test-ManualOptions @{ Sources = @('C:\a'); Dest = 'backups' } ''))
    function Wait-Manual { $t0 = Get-Date; while ($script:mState -and -not $script:mState.Done -and ((Get-Date) - $t0).TotalSeconds -lt 120) { Start-Sleep -Milliseconds 150 }; $mTimer.Stop(); $r = $script:mState.Result; [void]$script:mPs.EndInvoke($script:mHandle); $script:mPs.Runspace.Dispose(); $script:mPs.Dispose(); $script:mState = $null; $mStart.Enabled = $true; $r }
    foreach ($mode in 'Folder', 'Zip') {
        $o = Get-ManualOptions; $o.Mode = $mode; $o.Stamp = "t-$mode"
        Start-ManualBackup $o; $r = Wait-Manual
        if ($mode -eq 'Folder') {
            Check 'manual: folder backup in the background copies folders, the empty folder and only the picked file' ($r.Ok -and (Test-Path "$mw\out\Backup-t-Folder\Docs\Empty") -and (Test-Path "$mw\out\Backup-t-Folder\Pics\p.txt") -and -not (Test-Path "$mw\out\Backup-t-Folder\Pics\x.txt")) "$($r.Message)"
        } else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $z = [IO.Compression.ZipFile]::OpenRead("$mw\out\Backup-t-Zip.zip"); $names = @($z.Entries | ForEach-Object { $_.FullName }); $z.Dispose()
            Check 'manual: Windows zip in the background holds the folder, the empty folder and only the picked file' ($r.Ok -and $names -contains 'Docs/d.txt' -and $names -contains 'Docs/Empty/' -and $names -contains 'Pics/p.txt' -and $names -notcontains 'Pics/x.txt') (($names -join ', ') + ' ' + $r.Message)
        }
    }
    # Cancel: a big enough folder that the zip is still running when Cancel is pressed; the half-made zip is removed
    New-Item -ItemType Directory "$mw\big" -Force | Out-Null; $buf = New-Object byte[] (4MB); (New-Object Random 1).NextBytes($buf)
    1..40 | ForEach-Object { [IO.File]::WriteAllBytes("$mw\big\f$_.bin", $buf) }
    $o = Get-ManualOptions; $o.Sources = @("$mw\big"); $o.Stamp = 't-cancel'
    Start-ManualBackup $o; $t0 = Get-Date; while ($script:mState.Status -notmatch 'Zipping' -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 20 }; $script:mState.Cancel = $true; $r = Wait-Manual
    Check 'manual: Cancel stops the zip and removes the half-made file' ($r.Message -eq 'Cancelled.' -and -not (Test-Path "$mw\out\Backup-t-cancel.zip")) "$($r.Message)"
    # 7-Zip, when installed: zip with a password, 7z with hidden names, self-extracting .exe - made in the background like the button does
    $script:SevenZip = Find-7Zip; Update-ManualUi
    Check 'manual: Get 7-Zip shows the winget command; Install is off and Update on once 7-Zip is found' ($mWingetBox.Text -eq 'winget install -e --id 7zip.7zip' -and ($mInstall7.Enabled -ne [bool]$script:SevenZip) -and ($mUpdate7.Enabled -eq [bool]$script:SevenZip))
    Check 'manual: Update 7-Zip sits next to Install 7-Zip' ($mUpdate7.Top -eq $mInstall7.Top -and $mUpdate7.Left -gt $mInstall7.Right -and $mUpdate7.Left - $mInstall7.Right -lt 20)
    if ($script:SevenZip) { Check 'manual: the 7-Zip line shows its version' ($m7Status.Text -match '\(version [\d.]+\)') $m7Status.Text }
    $h7 = @($tabManual.Controls | Where-Object { $_.Text -eq '?' -and $_.Tag[0] -eq 'Get 7-Zip' })
    Check 'manual: Get 7-Zip help names install and upgrade' ($h7.Count -eq 1 -and $h7[0].Tag[1] -match 'winget install -e --id 7zip' -and $h7[0].Tag[1] -match 'winget upgrade -e --id 7zip')
    if ($script:SevenZip) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # 7-Zip writes 'Wrong password' to stderr on purpose here
        foreach ($c in @(@{ N = 'zip7pw'; Mode = 'Zip'; Engine = '7zip'; Password = 'pw 1'; Ext = '.zip' }, @{ N = '7zpw'; Mode = '7z'; Password = 'pw 1'; EncryptNames = $true; Ext = '.7z' }, @{ N = 'sfx'; Mode = '7z'; Sfx = 'Windowed'; Ext = '.exe' })) {
            $o = Get-ManualOptions; foreach ($k in $c.Keys) { $o[$k] = $c[$k] }; $o.Sources = @("$mw\src\Docs", "$mw\src\Pics\p.txt"); $o.Stamp = "t-$($c.N)"
            Start-ManualBackup $o; $r = Wait-Manual
            $out = "$mw\out\Backup-t-$($c.N)$($c.Ext)"
            $plain = & $script:SevenZip l -p $out 2>&1 | Out-String
            $withPw = & $script:SevenZip t "-p$($c.Password)" $out 2>&1 | Out-String
            $ok = $r.Ok -and (Test-Path $out) -and ($withPw -match 'Everything is Ok')
            if ($c.N -eq '7zpw') { $ok = $ok -and ($plain -notmatch 'd\.txt') }       # names hidden without the password
            if ($c.N -eq 'zip7pw') { $ok = $ok -and ((& $script:SevenZip t -pWRONG $out 2>&1 | Out-String) -notmatch 'Everything is Ok') }
            Check "manual: 7-Zip $($c.N) made in the background, opens (only) with its password" $ok "$($r.Message)"
        }
        $ErrorActionPreference = $eap
    }
    $mRbFolder.Checked = $true
    Check 'manual: Save as Script writes a script for the current choice' ((New-ManualScript (Get-ManualOptions) 'bat') -match 'robocopy' -and $mSave.Text -match 'Save as Script')
    Remove-Item $mw -Recurse -Force -ErrorAction SilentlyContinue
    # ---- 1.6: both destination folders are remembered, in a settings file in the tool's own folder ----
    Check 'settings: no file yet, the destination boxes start empty' (-not (Test-Path "$env:WRT_SETTINGS_DIR\BackupScriptBuilder.settings.json"))
    $sf = "$env:WRT_SETTINGS_DIR\BackupScriptBuilder.settings.json"
    Check 'remember: a Remember settings box at the bottom, off at first' ($chkRemember.Text -eq 'Remember settings' -and -not $chkRemember.Checked -and $chkRemember.Parent.Dock -eq 'Bottom')
    $txtDest.Text = 'H:\Backups [PC1]'; $mDest.Text = '\\nas\share\Manual'
    Save-BsbSettings
    Check 'remember: off, closing writes no settings file' (-not (Test-Path -LiteralPath $sf))
    $chkRemember.Checked = $true; Save-BsbSettings
    $sj = Get-Content -LiteralPath "$env:WRT_SETTINGS_DIR\BackupScriptBuilder.settings.json" -Raw | ConvertFrom-Json
    Check 'settings: closing saves both destination folders' ($sj.BuildDest -eq 'H:\Backups [PC1]' -and $sj.ManualDest -eq '\\nas\share\Manual')
    $txtDest.Text = ''; Save-BsbSettings
    Check 'settings: an empty box does not wipe the remembered folder' ((Read-BsbSettings).BuildDest -eq 'H:\Backups [PC1]')
    Check 'remember: the saved file says Remember = true' ((Read-BsbSettings).Remember -eq $true)
    # ---- 1.8: the Manual Backup type (folder / zip / 7z) and the zip engine are remembered ----
    $keepType = if ($mRbZip.Checked) { $mRbZip } elseif ($mRb7z.Checked) { $mRb7z } else { $mRbFolder }; $keepEng = if ($mRb7Engine.Checked) { $mRb7Engine } else { $mRbWin }; $real7s = $script:SevenZip
    $script:SevenZip = 'C:\fake\7z.exe'; Update-ManualUi
    $mRb7z.Checked = $true; Save-BsbSettings
    Check 'settings (1.8): closing saves the Manual Backup type: 7z' ((Read-BsbSettings).ManualType -eq '7z')
    $mRbZip.Checked = $true; $mRb7Engine.Checked = $true; Save-BsbSettings; $rs = Read-BsbSettings
    Check 'settings (1.8): zip, and who makes it (7-Zip), are saved' ($rs.ManualType -eq 'Zip' -and $rs.ZipEngine -eq '7zip')
    $script:SevenZip = $null; Update-ManualUi; Save-BsbSettings; $rs = Read-BsbSettings
    Check 'settings (1.8): on a PC without 7-Zip the fallback to a Windows zip keeps the remembered 7-Zip engine' ($mRbWin.Checked -and $rs.ZipEngine -eq '7zip' -and $rs.ManualType -eq 'Zip')
    $script:SevenZip = 'C:\fake\7z.exe'; Update-ManualUi; $mRb7z.Checked = $true; Save-BsbSettings
    $script:SevenZip = $null; Update-ManualUi; Save-BsbSettings
    Check 'settings (1.8): on a PC without 7-Zip a remembered 7z stays 7z (the tab shows zip)' ($mRbZip.Checked -and (Read-BsbSettings).ManualType -eq '7z')
    $mRbFolder.Checked = $true; Save-BsbSettings
    Check 'settings (1.8): a folder copy picked by hand is saved' ((Read-BsbSettings).ManualType -eq 'Folder')
    Check 'settings (1.8): the remembered type and engine are put back on the tab at start' ($script:BsbToolSource.Contains("switch ([string]`$bsbSettings.ManualType) { 'Zip' { `$mRbZip.Checked = `$true } '7z' { `$mRb7z.Checked = `$true }") -and $script:BsbToolSource.Contains("if (`$bsbSettings.ZipEngine -eq '7zip') { `$mRb7Engine.Checked = `$true }"))
    $script:SevenZip = $real7s; Update-ManualUi; $keepEng.Checked = $true; $keepType.Checked = $true; Update-ManualUi
    $chkRemember.Checked = $false; Save-BsbSettings
    Check 'remember: unticked, closing deletes the settings file' (-not (Test-Path -LiteralPath $sf))
    $bad = @('{not json', '', '[1,2]', 'null', '{"Remember":"yes","BuildDest":"H:\\x"}', '{"BuildDest":"H:\\x","ManualDest":"I:\\y"}')
    $n = 0; foreach ($b in $bad) { [IO.File]::WriteAllText($sf, $b); if ((Read-BsbSettings).Count -eq 0) { $n++ } }
    Check 'damaged file: bad JSON, empty, not an object, or no Remember = true -> no memory at all' ($n -eq $bad.Count) "$n of $($bad.Count)"
    [IO.File]::WriteAllText($sf, '{"Remember":true,"BuildDest":7,"ManualDest":"I:\\y"}'); $rs = Read-BsbSettings
    Check 'damaged file: values of the wrong type are dropped, the rest is kept' ($rs.Remember -and $rs.ManualDest -eq 'I:\y' -and -not $rs.ContainsKey('BuildDest'))
    [IO.File]::WriteAllText($sf, '{"Remember":true,"ManualType":"Rar","ZipEngine":5,"ManualDest":"I:\\y"}'); $rs = Read-BsbSettings
    Check 'damaged file (1.8): an unknown type or engine is dropped' ($rs.ManualDest -eq 'I:\y' -and -not $rs.ContainsKey('ManualType') -and -not $rs.ContainsKey('ZipEngine'))
    Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue
    $sv = $env:WRT_SETTINGS_DIR; $env:WRT_SETTINGS_DIR = ''
    Check 'settings: by default the file is next to the script (portable)' ($script:BsbToolSource.Contains('else { $PSScriptRoot }; if ($d) { Join-Path $d ''BackupScriptBuilder.settings.json'' }'))
    # 2.0 / 2.8: drag and drop onto the source list and the path boxes
    $dd = Join-Path $env:TEMP ('bsbdrop-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory "$dd\A" -Force | Out-Null; 'x' | Set-Content "$dd\f.txt"; 'x' | Set-Content "$dd\job.ps1"; 'x' | Set-Content "$dd\FreeFileSync.exe"
    $keepSrc = @($lstSrc.Items); $lstSrc.Items.Clear(); $rbRobo.Checked = $true
    Add-SourceDropped @("$dd\A", "$dd\A\", "$dd\f.txt")
    Check 'drop (2.0): folders and files dropped on Source folders are added once' ($lstSrc.AllowDrop -and $lstSrc.Items.Count -eq 2 -and $lstSrc.Items[0] -eq "$dd\A") (@($lstSrc.Items) -join ' | ')
    $lstSrc.Items.Clear(); foreach ($k in $keepSrc) { [void]$lstSrc.Items.Add($k) }; $rbFfs.Checked = $true
    & $script:PathDrops[$cboScript] "$dd\job.ps1"; & $script:PathDrops[$txtExe] "$dd\f.txt"; $exeBad = $txtExe.Text; & $script:PathDrops[$txtExe] "$dd\FreeFileSync.exe"
    Check 'drop (2.8): the script box and the FreeFileSync.exe box take a dropped file (an .exe only for FreeFileSync.exe)' ($cboScript.AllowDrop -and $cboScript.Text -eq "$dd\job.ps1" -and $exeBad -ne "$dd\f.txt" -and $txtExe.Text -eq "$dd\FreeFileSync.exe")
    Remove-Item $dd -Recurse -Force -ErrorAction SilentlyContinue
    $env:WRT_SETTINGS_DIR = $sv
}

# load the tool, but run the tests instead of showing the window (and with no splash screen)
$code = [IO.File]::ReadAllText((Join-Path $Root 'tools\BackupScriptBuilder.ps1'))
$code = $code.Replace("Show-WrtSplash 'Backup Script Builder'", '').Replace('[void]$form.ShowDialog()', '& $tests')
# message boxes are answered "Yes" (and remembered) instead of waiting for a click
Add-Type -TypeDefinition 'public static class FakeMsg { public static string Last = ""; public static string Show(params object[] a) { Last = a[0].ToString(); return "Yes"; } }'
$code = $code.Replace('[System.Windows.Forms.MessageBox]::Show(', '[FakeMsg]::Show(')
$env:WRT_SETTINGS_DIR = Join-Path $env:TEMP ('bsb-settings-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); [void][IO.Directory]::CreateDirectory($env:WRT_SETTINGS_DIR)
$script:BsbToolSource = $code
[void]$form   # (keeps PSScriptAnalyzer quiet about $form being set in the loaded code)
. ([scriptblock]::Create($code))
Remove-Item $env:WRT_SETTINGS_DIR -Recurse -Force -ErrorAction SilentlyContinue; $env:WRT_SETTINGS_DIR = $null
Write-Host ''
Write-Host "$script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 }
