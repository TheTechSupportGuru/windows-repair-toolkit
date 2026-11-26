# 7z-Encryptor 1.0 (2026-11-26)

A new small tool: encrypts files and folders with 7-Zip and a password you pick.

## What it does
- **Main window:** tick files and folders in the same picker as Backup Script Builder 1.3 (Quick picks, drives, Users, files listed too). Choose:
  - **7z** with AES-256. **Full encryption: also hide the file names** is on by default.
  - **zip** with **Standard** encryption (ZipCrypto: opens in Windows Explorer with the password, but weak) or **AES-256** (needs 7-Zip or similar to open).
  - A password, typed twice, with **Show**.
  - **Save as:** filled in next to the first item, named after it (`Encrypted-<date>` for several items), or picked with **Browse**.
- **Drop files on `7z-Encryptor.bat`:** a small window asks 7z or zip and the password, and saves in the 7z-Encryptor folder. A tick box saves next to the dropped item instead.
- **Safety:** each new file is tested with the password (`7z t`), and one that fails is deleted, not reported as done. Originals are never changed. An existing file is never overwritten (` (2)` is added).
- **7-Zip:** the tool looks for 7-Zip when it starts. If it is missing, both windows ask once whether to install it now. **Install 7-Zip** runs `winget install -e --id 7zip.7zip` and **Update 7-Zip** runs `winget upgrade -e --id 7zip.7zip`, each in a console window, and the tool picks 7-Zip up again when winget finishes. The installed version is shown.

## Tested
`tests/Run-7zEncryptor.ps1`, on Windows 11 with 7-Zip 24: 42 / 42 pass.
- Real encryption in all four modes (7z full, 7z contents only, zip standard, zip AES-256). Each file is unpacked with the password and compared file by file with the originals (empty folder included), and refused with a wrong password.
- 7z full encryption hides the file names; zip standard really is ZipCrypto.
- Archive names, including a drive root (`C-Drive`) and a share root, and never overwriting. The checks before encrypting.
- Both windows: no overlapping controls, help texts, which options show for 7z and zip, where the file is saved.
- The 7-Zip row (version, Install / Update), the question at start when 7-Zip is missing, and every **?** text.
- A file with spaces in its name dropped on `7z-Encryptor.bat` opens the small window with that file.

Not tested: clicking through the windows by hand, Windows 10, and the winget install and upgrade themselves (7-Zip was already installed).