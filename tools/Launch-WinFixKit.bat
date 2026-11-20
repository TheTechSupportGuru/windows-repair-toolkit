@echo off
rem Version 1.3 (2026-11-19) - edited copy. What changed: Edited scripts\V1.3\CHANGES.md
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
