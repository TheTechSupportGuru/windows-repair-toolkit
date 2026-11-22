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
    } finally {
        foreach ($k in 'zz-test button', 'zz-test renamed', 'zz-test bad') { Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $k -Confirm:$false -ErrorAction SilentlyContinue }
        Remove-Item -Recurse -Force $tmp2 -ErrorAction SilentlyContinue
    }

    # ---- 4. layout ----
    foreach ($page in $tabBuild, $tabSched) {
        $ctl = @($page.Controls | Where-Object { $_.Visible -or $true })
        $bad = @()
        for ($i = 0; $i -lt $ctl.Count; $i++) { for ($j = $i + 1; $j -lt $ctl.Count; $j++) {
            $a = $ctl[$i]; $b = $ctl[$j]
            $ra = $a.Bounds; $rb2 = $b.Bounds
            if ($a -is [Windows.Forms.Label] -and $a.AutoSize) { $ra.Size = $a.PreferredSize }
            if ($b -is [Windows.Forms.Label] -and $b.AutoSize) { $rb2.Size = $b.PreferredSize }
            if ($a -is [Windows.Forms.CheckBox]) { $ra.Size = $a.PreferredSize }
            if ($b -is [Windows.Forms.CheckBox]) { $rb2.Size = $b.PreferredSize }
            if ($ra.IntersectsWith($rb2)) { $bad += "$($a.GetType().Name)'$($a.Text)' x $($b.GetType().Name)'$($b.Text)'" }
        } }
        Check "no overlapping controls on '$($page.Text)'" ($bad.Count -eq 0) ($bad -join '; ')
        $help = @($page.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '?' })
        Check "'$($page.Text)' has ? buttons, all with help text" ($help.Count -ge 4 -and -not @($help | Where-Object { -not $_.Tag[1] }).Count) "$($help.Count) buttons"
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
