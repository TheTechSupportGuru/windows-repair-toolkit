@echo off
rem Version 1.8.1 (2026-11-20). What changed: docs/changes/V1.8.1.md
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-only
rem Free software under the GNU General Public License v3, WITHOUT ANY WARRANTY. See LICENSE or https://www.gnu.org/licenses/gpl-3.0.html
setlocal
rem Launches WinFixKit with no console window and no execution-policy prompt.
rem If the script is missing or cannot start, you now get a message instead of nothing at all.
if not exist "%~dp0WinFixKit.ps1" (
    echo WinFixKit.ps1 was not found next to this launcher:
    echo   "%~dp0"
    pause
    exit /b 1
)
set "WFK_SCRIPT=%~dp0WinFixKit.ps1"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "try { & $env:WFK_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show(('WinFixKit could not start:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + $_.InvocationInfo.PositionMessage), 'WinFixKit', 'OK', 'Error'); exit 1 }"
