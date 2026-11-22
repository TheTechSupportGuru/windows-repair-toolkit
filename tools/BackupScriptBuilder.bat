@echo off
rem Version 1.0 (2026-11-22) - launches Backup Script Builder with no console window.
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
setlocal
if not exist "%~dp0BackupScriptBuilder.ps1" (
    echo BackupScriptBuilder.ps1 was not found next to this launcher:
    echo   "%~dp0"
    pause
    exit /b 1
)
set "BSB_SCRIPT=%~dp0BackupScriptBuilder.ps1"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "try { & $env:BSB_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show(('Backup Script Builder could not start:' + [Environment]::NewLine + $_.Exception.Message), 'Backup Script Builder', 'OK', 'Error'); exit 1 }"
