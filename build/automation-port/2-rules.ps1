# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# PART of the WinFixKit Automation port: build\Port-AutomationToWinFixKit.ps1 puts it into beta\WinFixKit-beta-automation.ps1.
# Not a script to run on its own. Lines starting with '# PART' and the licence lines above are left out of the output.
# WinFixKit: the rules for the result lines the task script below prints around each fix / status check.
# A fix's own messages are free text, so the result says whether it ran to the end and whether it printed errors.
$WfkReboot = 'reboot (is )?(needed|required)|restart (is )?(needed|required)|restart the (PC|computer)|reboot to finish'
$TaskRules = @{
    # (ported) the restore point rule, word for word
    'restorepoint' = @(
        (New-TaskRule 'Restore point FAILED|was NOT created' $false 'Bad' 'NO RESTORE POINT - creating it failed' 'Turn on System Protection for the system drive (System Properties > System Protection > Configure), or tick "Turn on System Protection" on the Automation tab.')
        (New-TaskRule 'Restore point created' $true 'Good' 'RESTORE POINT CREATED' 'Nothing to do. You can roll back with System Restore (rstrui).')
    )
    'wfk-fix' = @(
        (New-TaskRule 'WinFixKit fix FAILED' $false 'Bad' 'FIX FAILED - it stopped with an error' 'The error is quoted above and in the full output. Run the tab''s status check to see the current state.')
        (New-TaskRule 'fix finished with \d+ error message' $true 'Warn' 'FIX RAN - WITH ERROR MESSAGES' 'Read the full output: a step may not have worked. Queue the tab''s status check after the fix to confirm.' '' $WfkReboot ' - RESTART NEEDED')
        (New-TaskRule 'fix finished without error messages' $true 'Good' 'FIX RAN - no error messages' 'Queue the tab''s status check after the fix to confirm the problem is gone.' '' $WfkReboot ' - RESTART NEEDED')
    )
    'wfk-status' = @(
        (New-TaskRule 'WinFixKit status check FAILED' $false 'Bad' 'STATUS CHECK FAILED - it stopped with an error' 'The error is quoted above and in the full output.')
        (New-TaskRule 'status check finished' $true 'Good' 'STATUS SAVED - read it in the full output' '"Show full output" or the HTML report has the whole status (read-only, nothing was changed).')
    )
}

