@echo off
rem Version 1.1 (2026-11-26) - launches Backup Script Builder with no console window.
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
setlocal
if not exist "%~dp0BackupScriptBuilder.ps1" (
    echo BackupScriptBuilder.ps1 was not found next to this launcher:
    echo   "%~dp0"
    pause
    exit /b 1
)
rem ---- PowerShell: Windows PowerShell, else PowerShell 7 (pwsh.exe), the only one in Hiren's BootCD PE 10 (not on the PATH there)
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" for /f "delims=" %%P in ('where powershell.exe 2^>nul') do set "PSEXE=%%P"
set "PWSH="
if not exist "%PSEXE%" for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if not exist "%PSEXE%" for %%D in (X Y) do if not defined PWSH if exist %%D:\ for /f "delims=" %%P in ('dir /s /b %%D:\pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if defined PWSH set "PSEXE=%PWSH%"
set "BSB_SCRIPT=%~dp0BackupScriptBuilder.ps1"
start "" "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "try { & $env:BSB_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show(('Backup Script Builder could not start:' + [Environment]::NewLine + $_.Exception.Message), 'Backup Script Builder', 'OK', 'Error'); exit 1 }"
