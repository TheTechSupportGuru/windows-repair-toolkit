# Test Center 1.0 beta 4 (2026-11-26)

- **7z-Encryptor tab:**
  - New **Unit tests: 7z-Encryptor edge cases** (`tests/7zEncryptor.Tests.ps1`, about 40 tests, no 7-Zip needed, changes nothing). It covers the 7-Zip arguments and quoting, file names and save paths, the checks before encrypting, dropped items, `mailto:` links, mail program switches and odd settings files (byte order mark, locked file, a folder in place of the file, wrong types).
  - **7z-Encryptor: encryption, window, drag-and-drop launcher** now covers the 1.4 window: it is started empty and by a drop, has the `mailto:` option and Remember settings. It also encrypts odd names with an odd password and drops names with `& ^ % !` on a copy of the launcher, as Explorer does. 85 checks (every ? text too), about 2 minutes.
- **New entries:** the WinFixKit Automation / Registry changes unit tests, and unit tests for Test Center's own result reader.
- **Backup Script Builder entry** now covers the folder picker checks.
- **Faster result reader:** its patterns are built once, and lists are used instead of growing arrays. The results are the same.
- **`Run-TestCenterGui.ps1`:** the tab check knows the Backup Script Builder and 7z-Encryptor tabs.