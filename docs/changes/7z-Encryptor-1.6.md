# 7z-Encryptor 1.6 (2026-11-26)

From the Hiren's BootCD PE 10 / 11 regression test of 2.5.

- **7-Zip's warnings are shown.** When 7-Zip skips files ("Encrypted, but some files were skipped"), the message now lists 7-Zip's own WARNING lines with the file names (at most 5). In the PE test, Hiren's 7-Zip 21.02 skipped a file with an unusual name; the next PE run shows why.
- **The launcher** (`7z-Encryptor.bat` 1.2) starts the tool with PowerShell 7 (`pwsh.exe`, on the PATH or on X: / Y:) when there is no Windows PowerShell, as in Hiren's PE 10. Dropping files on it works there too.

Tested: `tests/7zEncryptor.Tests.ps1` (the WARNING lines with the file name, at most 5, nothing when there are none); `tests/Run-7zEncryptor.ps1` also accepts 7-Zip versions such as "21.02 alpha" and the PowerShell 7 spelling of mailto links (`%28` / `%29`).
