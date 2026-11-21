@echo off
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Test Center: every regular test of the toolkit, a tab per tool. Keep this folder next to the "tools" folder.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0TestCenter.ps1"
