@echo off
rem Version 1.2 (2026-11-26) - starts 7z-Encryptor with no console window. Drop files or folders on this file to
rem start with them in the list (saved next to the first one); double-click it to start with an empty list.
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
setlocal DisableDelayedExpansion
if not exist "%~dp07z-Encryptor.ps1" (
    echo 7z-Encryptor.ps1 was not found next to this launcher:
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
rem 1.1: Explorer passes dropped names with & or ^ (and no space) without quotes, so cmd would cut them up in %%*.
rem When this launcher is in cmd's own command line (a drop or a double-click), that line goes to the tool unparsed
rem in WRT_DROP_CMDLINE and the tool reads the items from it. Started from a console, %%* is used as before.
set "WRT_DROP_BAT=%~f0"
setlocal EnableDelayedExpansion
set "WRT_DROP_CMDLINE=!cmdcmdline!"
set "WRT_VIA_LINE="
if /i not "!cmdcmdline:%~nx0=!"=="!cmdcmdline!" set "WRT_VIA_LINE=1"
setlocal DisableDelayedExpansion
if not defined WRT_VIA_LINE goto :console
start "" "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp07z-Encryptor.ps1"
exit /b 0
:console
set "WRT_DROP_CMDLINE="
start "" "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp07z-Encryptor.ps1" %*