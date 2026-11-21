@echo off
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem WinFixKit "apply every fix, then undo it" test (Run-Phase3.ps1). It REALLY CHANGES this PC (registry, services,
rem firewall, sharing) and undoes each change with WinFixKit's own backups. ONLY on a test VM, and ONLY after taking a
rem VirtualBox snapshot (on the host: Machine > Take Snapshot) so the VM can be put back if anything goes wrong.
echo.
echo  This test CHANGES this PC and then undoes each change.
echo  Only run it on a TEST virtual machine, AFTER taking a snapshot of it in VirtualBox.
echo.
set /p "OK=Type YES (capitals) if the snapshot is taken: "
if not "%OK%"=="YES" ( echo Not started. & pause & exit /b 1 )
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('\"' + '%~dp0Run-Phase3.ps1' + '\"')"
echo Started in an administrator window. Results: %%TEMP%%\suite-phase3\summary.txt
pause