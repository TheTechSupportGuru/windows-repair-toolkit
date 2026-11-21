@echo off
rem WinFixKit 1.9 beta-automation 1 (2026-11-21). What changed: docs/changes/WinFixKit-1.9-beta-automation.1.md
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Free software under the GNU General Public License v3 or (at your option) any later version, WITHOUT ANY WARRANTY. See LICENSE
setlocal
rem Launches WinFixKit (BETA with the Automation tab) with no console window and no execution-policy prompt.
rem If the script is missing or cannot start, you now get a message instead of nothing at all.
if not exist "%~dp0WinFixKit-beta-automation.ps1" (
    echo WinFixKit-beta-automation.ps1 was not found next to this launcher:
    echo   "%~dp0"
    pause
    exit /b 1
)
set "WFK_SCRIPT=%~dp0WinFixKit-beta-automation.ps1"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "try { & $env:WFK_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show(('WinFixKit (beta automation) could not start:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + $_.InvocationInfo.PositionMessage), 'WinFixKit', 'OK', 'Error'); exit 1 }"
