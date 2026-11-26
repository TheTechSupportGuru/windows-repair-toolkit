# Backup Script Builder 1.5 (2026-11-26)

Part of the toolkit's 2.0 release. Found by the 2.0 edge-case pass.

- **Manual Backup, zip with 7-Zip and a password:** a password with letters outside English (for example `é`, `ü` or Cyrillic) is now refused with a clear message (use 7z instead). Before, 7-Zip stopped with "The parameter is incorrect". 7z backups accept any characters, as before.
- **Folders with `[ ]` in the name:** the destination check before **Build Script**, and the folder dialogs of the Build Script and Manual Backup tabs, treated `[ ]` as a wildcard. An existing `BackupScript.ffs_batch` in a folder like `Backups [PC1]` was overwritten without asking, and the dialogs did not open in that folder. They now use the path exactly as typed.
- The 7-Zip / Robocopy / Xcopy process of a Manual Backup is now always released (disposed) when it ends, also when cancelled.

Tested: 102 / 102 checks of `tests/Run-BackupScriptBuilder.ps1` (one new: the zip password check) and 63 / 63 unit tests.
