# Backup Script Builder 1.1 (2026-11-25)

## New: Robocopy and Xcopy scripts
The Build Script tab now asks **what to create**:
- **Create FreeFileSync batch** - as in 1.0 (a `.ffs_batch` with versioning).
- **Create Robocopy batch** / **Create Xcopy batch** - a simple backup script that needs nothing but Windows, for the same source folders and destination (`<destination>\AutomaticFileBackups\Current\<folder>`), saved as `BackupScript-Robocopy` / `BackupScript-Xcopy`.

Each of the two new pages has:
- **Script type:** PowerShell (`.ps1`) or batch file (`.bat`).
- **Log:** on / off, the log folder (empty = `Logs` next to the backup), **append to one log** or a **new log every run**, and for new logs the **date and / or time in the name** (`Backup-Robocopy-2026-11-25_230000.log`).
- **Switches** (a section at the bottom): every switch that matters for a backup, each explained, safe ones ticked: Robocopy `/E /MIR /Z /B /J /COPY:DAT /DCOPY:T /SEC /XO /FFT /XJ /R:n /W:n /NP /NDL /NFL /TEE /XD`, Xcopy `/E /I /H /C /K /R /Y /D /Q /Z /J /O /X`.
- **Robocopy threads:** one drive at a time, or **one thread per source drive** (folders on different drives or network shares copy at the same time, each with its own log), plus `/MT` threads per copy (0 = off).
- The script ends with exit code 0, or 1 when the copy failed (robocopy 8+, xcopy 2+), so Task Scheduler shows the result.

## Schedule Task tab
- A **Backup type** drop-down: **FreeFileSync** (starts FreeFileSync.exe with the `.ffs_batch`, as before), **Robocopy** or **Xcopy** (a `.ps1` runs with PowerShell, a `.bat` with cmd). Existing tasks are read back with their type.

## Fixed
- **Folders missing from "Add Folders..."** (Desktop, Documents, OneDrive and everything in OneDrive): OneDrive marks its folders as reparse points (files on demand), and 1.0 skipped every reparse point to avoid junction loops. Now only real junctions and symbolic links are skipped.
- New **Quick picks** group at the top of the folder list: Desktop, Documents, Pictures, Music, Videos, Downloads (wherever they really are, also when moved into OneDrive), every OneDrive folder, and your user folder.

## Tested
`tests/Run-BackupScriptBuilder.ps1`: 63 / 63 on the Windows 11 VM, including Quick picks and junction handling, a real run of every script kind (Robocopy and Xcopy, `.ps1` and `.bat`, one at a time and per-drive threads on two drives, append and new logs with date / time names), Robocopy and Xcopy scheduled tasks created and read back, the 1.0 FreeFileSync tests and the layout checks.
