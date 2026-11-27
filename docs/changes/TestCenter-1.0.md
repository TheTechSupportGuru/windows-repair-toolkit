# Test Center 1.0 (2026-11-26)

Out of beta: Test Center is now a regular download in the release, `TestCenter-v1.0.zip`, with a `READ ME FIRST.txt`. It still has its own version number and changes only when the test procedures or test scripts change.

- **Built with the 2.5 tools** (Backup Script Builder 1.8, 7z-Encryptor 1.5).
- **Backup Script Builder tab:**
  - Unit tests: saved manual backup scripts (a Windows zip never asks `tar` for Ultra) and finding 7-Zip in Windows PE (X: and Y:).
  - The full test: Ultra greyed out for a Windows zip, Remember settings keeping folder / zip / 7z, and dragging from Explorer onto the list, Save to, Destination and Log folder (132 checks).
- **7z-Encryptor tab:**
  - Unit tests: finding 7-Zip in Windows PE (47 tests).
  - The full test: Remember settings keeping 7z or zip, and dragging from Explorer onto the list (93 checks).
- The test descriptions say what is covered now.
- **Fixed:** the Backup Script Builder check 'picker: Add Checked and Cancel are inside the window' failed when run from Test Center (also with the 2.4 tools). Test Center starts each test minimized, and Windows then showed the folder picker, the first window of that test, minimized and 0 wide. The check now measures it at its normal size.

Tested: Test Center's own window check (40 / 40) and a scripted Test Center run of the Backup Script Builder and 7z-Encryptor tabs (all 4 passed).