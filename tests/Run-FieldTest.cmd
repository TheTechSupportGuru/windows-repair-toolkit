@echo off
rem Windows Repair Toolkit - Copyright (C) 2026 TheTechSupportGuru - SPDX-License-Identifier: GPL-3.0-or-later
rem Field test for another PC: double-click. Answer Yes to the admin prompt for the full test (No = the part without admin).
rem Takes 20-40 minutes. Results: a WRT-FieldTest-<date> folder on the Desktop; send only share\WRT-FieldTest-share.zip.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-FieldTest.ps1" -Elevate
