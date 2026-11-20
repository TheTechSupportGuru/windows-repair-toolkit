@echo off
rem Version 1.8 (2026-11-19) - edited copy. What changed: Edited scripts\V1.8\CHANGES.md
setlocal
rem Starts ClaudeLogAnalyzer with no console window. If the script is missing or cannot start, you now get a message.
if not exist "%~dp0ClaudeLogAnalyzer.ps1" (
    echo ClaudeLogAnalyzer.ps1 was not found next to this launcher:
    echo   "%~dp0"
    pause
    exit /b 1
)
set "CLA_SCRIPT=%~dp0ClaudeLogAnalyzer.ps1"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "try { & $env:CLA_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show(('Claude Log Analyzer could not start:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + $_.InvocationInfo.PositionMessage), 'Claude Log Analyzer', 'OK', 'Error'); exit 1 }"
