@echo off
rem Version 0.1 beta 1 - starts the Diagnostic Tool Downloader (GUI) with no console window.
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
setlocal
if not exist "%~dp0Get-DiagToolsGui.ps1" (
    echo Get-DiagToolsGui.ps1 was not found next to this launcher.
    pause
    exit /b 1
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Get-DiagToolsGui.ps1"
exit /b 0
