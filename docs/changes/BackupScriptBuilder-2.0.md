# Backup Script Builder 2.0 (2026-11-27)

- **Drag and drop onto Source folders.** The Build Script tab's Source folders list now takes folders dragged from Explorer (before, only Destination and the Manual Backup list did). Mapped drives are saved as their \\server\share path, duplicates are skipped, and single files are added for Robocopy / Xcopy (a FreeFileSync batch backs up folders only, so dropped files are skipped with a message).

Tested: `tests/Run-BackupScriptBuilder.ps1` and `tests/BackupScriptBuilder.Tests.ps1`.
