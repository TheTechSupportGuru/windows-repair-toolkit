@echo off
rem Version 1.9 BETA 3 (2026-11-20) - launcher for the beta WinSuperTool.ps1 in this folder. What changed: docs/changes/V1.9-beta.3.md
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Free software under the GNU General Public License v3 or (at your option) any later version, WITHOUT ANY WARRANTY. See LICENSE
setlocal EnableExtensions
title Windows Super Tool launcher

rem =====================================================================
rem  WinSuperTool.bat
rem   - Double-click            : starts WinSuperTool.ps1 from this folder as admin
rem   - Drag a .ps1 onto it     : runs THAT script as admin, no questions
rem   - Nothing dragged and no WinSuperTool.ps1 here : asks you to paste a path
rem  In WinPE, or when already elevated, it starts directly (no UAC prompt).
rem =====================================================================

rem ---- Option: set to 1 to keep the PowerShell window open after a dragged / pasted script ends
set "KEEPOPEN=0"

rem ---- always use 64-bit PowerShell, even when started from a 32-bit program
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
rem The ELEVATED copy is started BY the 64-bit PowerShell above, where Sysnative does not exist: give it the System32 path.
set "PSEXE64=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

set "ISMAIN=0"

rem ---- Mode 1: a .ps1 was dragged onto this file (or passed as an argument)
set "PSFILE=%~1"
if defined PSFILE goto :validate

rem ---- Double-click: the super tool next to this file
if exist "%~dp0WinSuperTool.ps1" (
    set "PSFILE=%~dp0WinSuperTool.ps1"
    set "ISMAIN=1"
    goto :validate
)

rem ---- Mode 2: nothing supplied, ask for the path
:prompt
set "ISMAIN=0"
echo.
set "PSFILE="
set /p "PSFILE=Paste the full path to the PowerShell script (.ps1): "
if not defined PSFILE goto :prompt
set "PSFILE=%PSFILE:"=%"
rem expand %variables% in a pasted path, e.g. %USERPROFILE%\Desktop\x.ps1. `call set` also eats ^ characters,
rem so if the expanded path does not exist, keep the path exactly as pasted.
set "PSRAW=%PSFILE%"
call set "PSFILE=%PSFILE%"
if not exist "%PSFILE%" set "PSFILE=%PSRAW%"

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
goto :prompt

:notps1
echo.
echo That is not a .ps1 file: "%PSFILE%"
goto :prompt

:launch
set "NOEXIT="
if "%KEEPOPEN%"=="1" if "%ISMAIN%"=="0" set "NOEXIT=-NoExit"
set "WINSTYLE=Normal"
if "%ISMAIN%"=="1" set "WINSTYLE=Minimized"

rem ---- WinPE (runs as SYSTEM) or already elevated: start directly
reg query "HKLM\SYSTEM\CurrentControlSet\Control\MiniNT" >nul 2>&1 && goto :direct
fltmc >nul 2>&1 && goto :direct

echo.
echo Launching as Administrator: "%PSFILE%"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $a = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',([char]34 + $env:PSFILE + [char]34)); if ($env:NOEXIT) { $a = @($env:NOEXIT) + $a }; Start-Process -FilePath $env:PSEXE64 -Verb RunAs -WindowStyle $env:WINSTYLE -ArgumentList $a -ErrorAction Stop } catch { Write-Host ('Launch cancelled or failed: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"
if errorlevel 1 (
    echo.
    pause
)
goto :end

:direct
echo.
echo Starting: "%PSFILE%"
if "%WINSTYLE%"=="Minimized" (
    start "" /min "%PSEXE%" %NOEXIT% -NoProfile -ExecutionPolicy Bypass -STA -File "%PSFILE%"
) else (
    start "" "%PSEXE%" %NOEXIT% -NoProfile -ExecutionPolicy Bypass -STA -File "%PSFILE%"
)

:end
endlocal
exit /b
