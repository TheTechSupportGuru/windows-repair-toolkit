@echo off
rem Version 1.0 (2026-11-26) - starts 7z-Encryptor with no console window. Drop files or folders on this file to
rem encrypt them in a small window (saved in this folder); double-click it for the main window.
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
setlocal
if not exist "%~dp07z-Encryptor.ps1" (
    echo 7z-Encryptor.ps1 was not found next to this launcher:
    echo   "%~dp0"
    pause
    exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp07z-Encryptor.ps1" %*