# Backup Script Builder 1.6 (2026-11-26)

Part of the toolkit's 2.2 release.

- The **Destination folder** (Build Script tab) and **Save to** (Manual Backup tab) are remembered: saved when the tool closes, filled in when it starts. An empty box does not wipe a remembered folder.
- **Portable settings:** kept in `BackupScriptBuilder.settings.json` in the same folder as `BackupScriptBuilder.ps1`, so a USB stick or WinPE kit keeps them on every PC. If the folder is read-only, nothing is remembered and the tool works as before.
- The **?** help of both boxes says so.

Tested: 106 / 106 checks of `tests/Run-BackupScriptBuilder.ps1` (4 new: no file at first, both folders saved, an empty box keeps the remembered folder, the file is next to the script).