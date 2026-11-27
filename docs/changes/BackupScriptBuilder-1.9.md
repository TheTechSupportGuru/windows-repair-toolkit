# Backup Script Builder 1.9 (2026-11-26)

Fixes from the Hiren's BootCD PE 10 / 11 regression test of 2.5.

- **Saved Windows-zip scripts no longer use `tar.exe`.** A manual backup script for a zip made by **Windows (built in)** now writes Windows' own .NET zip into the script: the same code as **Back up now** (Store or Normal, folders keep their name, empty folders kept, only the picked files). `tar.exe` is not in Windows PE, so in 1.8 these scripts failed in Hiren's PE 11 (and PE 10). A `.bat` keeps the zip code at its end, after `exit /b`, and runs it with PowerShell.
- **A saved `.bat` finds PowerShell itself:** Windows PowerShell, else PowerShell 7 (`pwsh.exe`) on the PATH or on X: / Y:. Hiren's PE 10 has only PowerShell 7, and it is not on the PATH there. Before, the `.bat`'s date line (and so the backup's name) needed `powershell.exe`.
- **Schedule Task in Windows PE:** Windows PE has no Task Scheduler (PE 10 has no ScheduledTasks commands, PE 11's fail). The tab is now greyed out there with the reason, and the tool no longer shows a `Get-ScheduledTask` error when it starts in PE 10.
- **The launcher** (`BackupScriptBuilder.bat` 1.1) starts the tool with PowerShell 7 when there is no Windows PowerShell (Hiren's PE 10).
- The **?** text for saving a script says the zip works in Windows 10, 11 and Windows PE.

Tested:
- `tests/BackupScriptBuilder.Tests.ps1`: every saved script type (folder, Windows zip Store / Normal, 7-Zip zip, 7z, self-extracting) as `.bat` and `.ps1` really runs and makes a backup with a dated name; a Windows-zip script never mentions tar and holds the .NET zip code; every `.bat` has the PowerShell 7 fallback and keeps the zip code after `exit /b`.
- `tests/Run-BackupScriptBuilder.ps1`: in Windows PE the Schedule Task tab is greyed out with the reason (the scheduled-task checks run only outside PE).
