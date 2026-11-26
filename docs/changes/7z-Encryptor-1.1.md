# 7z-Encryptor 1.1 (2026-11-26)

Part of the toolkit's 2.0 release. Found by the 2.0 edge-case pass.

- **Zip passwords:** a password with letters outside English (for example `é`, `ü` or Cyrillic) is now refused for zip, with a message to use 7z instead. Before, 7-Zip stopped with "The parameter is incorrect" and nothing was made. 7z accepts any characters, as before.
- The 7-Zip process is now always released (disposed) when it ends, also after an error.

Checked on the way (no change needed): passwords with spaces at either end, `%`, `&`, `^`, `|`, `<`, `>`, a leading `-` and backslashes (also a trailing one) all reach 7-Zip as typed. This was verified by opening the result with Windows' own `tar.exe` and the typed password. A `"` in a password was already refused, because 7-Zip's command line cannot carry it reliably. Files and folders with `[ ]`, `'`, `&` or `%` in their names encrypt and test correctly from the main window.

Tested: 43 / 43 checks of `tests/Run-7zEncryptor.ps1` (one new: the zip password check), with real 7-Zip.
