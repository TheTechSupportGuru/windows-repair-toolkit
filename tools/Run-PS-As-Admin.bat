@echo off
rem Version 2.0 (2026-11-26). What changed: docs/changes/V2.0.md
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Free software under the GNU General Public License v3 or (at your option) any later version, WITHOUT ANY WARRANTY. See LICENSE
setlocal EnableExtensions
title Run PowerShell script as Administrator

rem ---- Option: set to 1 to keep the PowerShell window open after the script ends
set "KEEPOPEN=0"

rem ---- Mode 1: a .ps1 was dragged onto this file (or passed as an argument)
set "PSFILE=%~1"
if defined PSFILE goto :validate

rem ---- Mode 2: nothing supplied, ask for the path
:prompt
echo.
set "PSFILE="
set /p "PSFILE=Paste the full path to the PowerShell script (.ps1): "
if not defined PSFILE goto :prompt
set "PSFILE=%PSFILE:"=%"

:validate
if not exist "%PSFILE%" goto :notfound
for %%F in ("%PSFILE%") do (
    set "PSFILE=%%~fF"
    set "PSEXT=%%~xF"
)
if /i not "%PSEXT%"==".ps1" goto :notps1
goto :launch

:notfound
echo.
echo File not found: "%PSFILE%"
set "PSFILE="
goto :prompt

:notps1
echo.
echo That is not a .ps1 file: "%PSFILE%"
set "PSFILE="
goto :prompt

:launch
echo.
echo Launching as Administrator: "%PSFILE%"
set "NOEXIT="
if "%KEEPOPEN%"=="1" set "NOEXIT='-NoExit',"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process powershell.exe -Verb RunAs -ArgumentList %NOEXIT%'-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',([char]34+$env:PSFILE+[char]34) } catch { Write-Host ('Launch cancelled or failed: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"

if errorlevel 1 (
    echo.
    pause
)
endlocal
exit /b
