@echo off
rem Version 2.6 (2026-11-26). What changed: docs/changes/V2.6.md
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Free software under the GNU General Public License v3 or (at your option) any later version, WITHOUT ANY WARRANTY. See LICENSE
setlocal
rem Launches WinFixKit with no console window and no execution-policy prompt.
rem If the script is missing or cannot start, you now get a message instead of nothing at all.
if not exist "%~dp0WinFixKit.ps1" (
    echo WinFixKit.ps1 was not found next to this launcher:
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
set "WFK_SCRIPT=%~dp0WinFixKit.ps1"
start "" "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "try { & $env:WFK_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show(('WinFixKit could not start:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + $_.InvocationInfo.PositionMessage), 'WinFixKit', 'OK', 'Error'); exit 1 }"
