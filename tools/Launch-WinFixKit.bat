@echo off
rem Launches WinFixKit with no console window and no execution-policy prompt.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0WinFixKit.ps1"
