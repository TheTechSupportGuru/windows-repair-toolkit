# Backup Script Builder 1.7 (2026-11-26)

Part of the toolkit's 2.3 release.

- **Remember settings** box at the bottom left, next to the FreeFileSync link. It is **off at first**:
  - Off: nothing is written when you close the tool.
  - Ticked: the Destination folder (Build Script) and Save to (Manual Backup) are saved in `BackupScriptBuilder.settings.json` next to the script when you close the tool.
  - Unticked again: the settings file is deleted when you close the tool.
- **A damaged settings file means no memory.** The file is only used when it is a JSON object with `"Remember": true`. Bad JSON, an empty file, a list, or a 1.6 file without the Remember flag is ignored and the box starts off. A value of the wrong type is dropped and the rest is kept.

Tested: 112 / 112 checks of `tests/Run-BackupScriptBuilder.ps1` (6 new).