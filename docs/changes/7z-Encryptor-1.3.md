# 7z-Encryptor 1.3 (2026-11-26)

Part of the toolkit's 2.3 release.

- **Remember settings** box in the main window and the drop window. It is **off at first**:
  - Off: nothing is written. Your choices stay in use until you close the tool, then they are forgotten.
  - Ticked: the save folder, email choice and program, and the drop window's tick are saved in `7z-Encryptor.settings.json` next to the script, right away and whenever they change. Never a password.
  - Unticked again: the settings file is deleted.
- **A damaged settings file means no memory.** The file is only used when it is a JSON object with `"Remember": true`. Bad JSON, an empty file, a list, or a 2.2 file without the Remember flag is ignored, and the box starts off. A value of the wrong type (a number where a folder belongs, for example) is dropped and the rest is kept.
- If the window still fails to open with the remembered settings, it is opened again with no memory.

Tested: 64 / 64 checks of `tests/Run-7zEncryptor.ps1` (10 new: the box is off at first and writes nothing, ticking saves, unticking deletes, six kinds of damaged file give no memory, wrong-type values are dropped, the drop window opens with defaults on a damaged file).