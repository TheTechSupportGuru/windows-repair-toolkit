# Test Center 1.1 (2026-11-26)

- **The WinPE test (`tests/Run-PETest.ps1`)** now also tests Backup Script Builder, 7z-Encryptor and Test Center (step 7): finding 7-Zip on X: and Y: the way both tools do, then their full window tests. It runs every unit test file (not 3 of them), starts Test Center with the other tools, lists whether `tar` is there, and also counts PowerShell 7's error lines (Hiren's PE 10) when a tool starts.
- **The Test Center window test** works in Windows PE: it uses the PowerShell it runs in (PowerShell 7 in Hiren's PE 10), reads tick boxes without a compiled Accessibility reference, waits for the tabs, and expects what Test Center offers in PE (only the tests that need no running Windows; the run checks use the unit test suite there).
- `Start-TestCenter.bat` starts Test Center with PowerShell 7 when there is no Windows PowerShell.
