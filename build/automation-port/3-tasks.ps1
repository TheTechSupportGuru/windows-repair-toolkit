# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# PART of the WinFixKit Automation port: build\Port-AutomationToWinFixKit.ps1 puts it into beta\WinFixKit-beta-automation.ps1.
# Not a script to run on its own. Lines starting with '# PART' and the licence lines above are left out of the output.
# ---- WinFixKit: the task list is WinFixKit itself ----
# Every tab's status check and every fix that needs no answer from you (fixes that ask for a folder or a name, and
# the "Open ..." buttons, stay on their tabs), plus the restore point above.
# The helper functions a fix calls, as text for the task window: every function WinFixKit defines before $Sections.
function Get-WfkPrelude {
    if ($script:WfkPrelude) { return $script:WfkPrelude }
    $ast = [Management.Automation.Language.Parser]::ParseFile($script:WfkSelf, [ref]$null, [ref]$null)
    $secAt = ($ast.FindAll({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$Sections' }, $false) | Select-Object -First 1).Extent.StartOffset
    $from = ($ast.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Test-Admin' }, $false) | Select-Object -First 1).Extent.StartOffset
    $fns = $ast.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Extent.StartOffset -ge $from -and $x.Extent.StartOffset -lt $secAt }, $false)
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('$ErrorActionPreference = ''Continue''')
    foreach ($n in 'RootDir', 'LogDir', 'ReportDir', 'RegDir', 'RegKeyDir', 'RegFullDir') {
        [void]$sb.AppendLine(('$script:{0} = ''{1}''' -f $n, (Esc-Sq ([string](Get-Variable -Scope Script -Name $n -ValueOnly)))))
    }
    [void]$sb.AppendLine(('$script:LogFile = ''{0}''' -f (Esc-Sq (Join-Path $script:LogDir ('Automation-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))))))
    [void]$sb.AppendLine('$LogDir = $script:LogDir; $ReportDir = $script:ReportDir')
    foreach ($f in $fns) { [void]$sb.AppendLine($f.Extent.Text) }
    $script:WfkPrelude = $sb.ToString()
    return $script:WfkPrelude
}
# The task-window code of one fix or status check: the helpers, the block itself (its output shows live), then one
# result line that the rules above read.
function Get-WfkCall($c) {
    $isFix = [bool]$c.Act
    $what = if ($isFix) { 'fix' } else { 'status check' }
    $block = if ($isFix) { $c.Act.Run.ToString() } else { $c.Sec.Status.ToString() }
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine((Get-WfkPrelude))
    [void]$sb.AppendLine('$WfkE0 = $Error.Count; $WfkOk = $true')
    [void]$sb.AppendLine('try {')
    if ($isFix -and $c.Act.Registry) {
        [void]$sb.AppendLine('    Write-Host ''--- REGISTRY SAFETY: full backup + per-item originals ---'' -ForegroundColor Yellow')
        [void]$sb.AppendLine('    (Ensure-FullRegBackup | Out-String -Width 220).TrimEnd() | Write-Host')
    }
    [void]$sb.AppendLine('    Write-Host ''--- RUNNING ---'' -ForegroundColor Yellow')
    [void]$sb.AppendLine('    & {')
    [void]$sb.AppendLine($block)
    [void]$sb.AppendLine('    } $null 2>&1 | Out-Host')
    [void]$sb.AppendLine('} catch { $WfkOk = $false; Write-Host ''''; Write-Host (''WinFixKit ' + $what + ' FAILED: '' + $_.Exception.Message) -ForegroundColor Red }')
    if ($isFix) {
        [void]$sb.AppendLine('$WfkN = $Error.Count - $WfkE0')
        [void]$sb.AppendLine('if ($WfkOk) { Write-Host ''''; if ($WfkN -gt 0) { Write-Host (''WinFixKit fix finished with {0} error message(s) - read the output above.'' -f $WfkN) -ForegroundColor Yellow } else { Write-Host ''WinFixKit fix finished without error messages.'' -ForegroundColor Green } }')
    } else {
        # a status check reports what it could not read as part of its output, so errors there are normal
        [void]$sb.AppendLine('if ($WfkOk) { Write-Host ''''; Write-Host ''WinFixKit status check finished.'' -ForegroundColor Green }')
    }
    [void]$sb.AppendLine('$global:LASTEXITCODE = $(if ($WfkOk) { 0 } else { 1 })')
    # the code is written to a file and dot-sourced: with all the helper functions it is too long for a command line
    $file = (Get-TaskFileBase ($c.Name + '-script')) + '.ps1'
    [IO.File]::WriteAllText($file, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
    return ". '$(Esc-Sq $file)'"
}
function New-WfkTasks {
    $slug = { param($s) ($s -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower() }
    foreach ($sec in $Sections) {
        if ($sec.Status) {
            $help = 'Read-only. ' + ((@(($sec.StatusHelp -split "`r?`n") | Where-Object { $_.Trim() }) -join ' ') -replace '^Read-only\.\s*', '')
            $t = New-AutoTask ('status-' + (& $slug $sec.Name)) "$($sec.Name): check status" 'wfk-status' $help @() { param($o) throw 'built by Get-WfkCall' }
            $t | Add-Member -NotePropertyName Sec -NotePropertyValue $sec; $t | Add-Member -NotePropertyName Act -NotePropertyValue $null
            $t
        }
        foreach ($a in @($sec.Actions)) {
            if ($a.Prompt -or $a.Label -like 'Open *') { continue }
            $help = (@(($a.Help -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Skip 1) -join ' ')
            if ($a.Confirm) { $help = 'CHANGES THE PC (asks first when run by hand). ' + $help }
            $t = New-AutoTask ('fix-' + (& $slug $sec.Name) + '-' + (& $slug $a.Label)) "$($sec.Name): $($a.Label)" 'wfk-fix' $help @() { param($o) throw 'built by Get-WfkCall' }
            $t | Add-Member -NotePropertyName Sec -NotePropertyValue $sec; $t | Add-Member -NotePropertyName Act -NotePropertyValue $a
            $t
        }
    }
}
$AutoRestore = New-AutoTask 'restore-point' 'Create a system restore point' 'restorepoint' 'Creates a restore point of the system drive, so the changes made by the next tasks can be rolled back with System Restore. Needs System Protection on for the system drive (tick the option below to turn it on).' @() { param($o) @{ Call = $AutoScriptRestore.Replace('__ENABLE__', $(if ($o.EnableSR) { '$true' } else { '$false' })); Line = 'Checkpoint-Computer (restore point)' } }
$AutoRestore | Add-Member -NotePropertyName Sec -NotePropertyValue $null; $AutoRestore | Add-Member -NotePropertyName Act -NotePropertyValue $null
$AutoCatalog = @($AutoRestore) + @(New-WfkTasks)
# presets by tab name + button label (a label that is not in this version is simply left out)
function Get-WfkPreset([string[]]$items) {
    foreach ($i in $items) {
        if ($i -eq 'restore-point') { 'restore-point'; continue }
        $sec, $lab = $i -split '\|', 2
        $c = $AutoCatalog | Where-Object { $_.Sec -and $_.Sec.Name -eq $sec -and $(if ($lab -eq 'status') { -not $_.Act } else { $_.Act -and $_.Act.Label -eq $lab }) } | Select-Object -First 1
        if ($c) { $c.Id }
    }
}
$AutoPresets = [ordered]@{
    'Health snapshot (status checks only, changes nothing)' = @(Get-WfkPreset 'Overview|status', 'Windows Update|status', 'Network|status', 'Printer|status', 'Store Apps|status', 'Start Menu|status', 'Audio|status', 'Hardware and Devices|status', 'Power|status', 'Search and Indexing|status')
    'Network repair (no restart)'                           = @(Get-WfkPreset 'restore-point', 'Network|status', 'Network|Flush DNS cache', 'Network|Clear ARP cache', 'Network|Release and renew DHCP lease', 'Network|Reset WinHTTP proxy', 'Network|status')
    'Printing repair'                                       = @(Get-WfkPreset 'Printer|status', 'Printer|Restart Print Spooler', 'Printer|Clear stuck print queue', 'Printer|status')
    'Windows Update repair'                                 = @(Get-WfkPreset 'restore-point', 'Windows Update|status', 'Windows Update|Reset Windows Update components', 'Windows Update|Scan for updates now', 'Windows Update|status')
    'Store and Start menu repair'                           = @(Get-WfkPreset 'Store Apps|status', 'Store Apps|Reset Microsoft Store cache (wsreset)', 'Store Apps|Restart Store licensing and AppX services', 'Store Apps|Re-register Microsoft Store', 'Start Menu|Restart Start / Search / Shell processes', 'Store Apps|status')
}
# WinFixKit: every task needs the running Windows (no offline queue from WinPE)
function Get-AutoWhyNot([string]$id) {
    if ($IsWinPE) { return 'needs the running Windows - WinFixKit''s fixes cannot work on an offline Windows from WinPE' }
    return ''
}
function Get-AutoCode($c, $opt, [string]$win = '') {
    if ($c.Sec) { return @{ Call = (Get-WfkCall $c); Line = $(if ($c.Act) { "WinFixKit fix: $($c.Sec.Name) > $($c.Act.Label)" } else { "WinFixKit status check: $($c.Sec.Name)" }) } }
    return (& $c.Code $opt)
}
