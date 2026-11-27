@echo off
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Test Center: every regular test of the toolkit, a tab per tool. Keep this folder next to the "tools" folder.
setlocal
rem ---- PowerShell: Windows PowerShell, else PowerShell 7 (pwsh.exe), the only one in Hiren's BootCD PE 10 (not on the PATH there)
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" for /f "delims=" %%P in ('where powershell.exe 2^>nul') do set "PSEXE=%%P"
set "PWSH="
if not exist "%PSEXE%" for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if not exist "%PSEXE%" for %%D in (X Y) do if not defined PWSH if exist %%D:\ for /f "delims=" %%P in ('dir /s /b %%D:\pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if defined PWSH set "PSEXE=%PWSH%"
start "" "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0TestCenter.ps1"
