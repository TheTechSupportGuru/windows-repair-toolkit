# 7z-Encryptor 1.4 (2026-11-26)

- **One window for both ways of starting.** Files or folders dropped on `7z-Encryptor.bat` now open the normal window with them already in the list. The file picker (Add Files/Folders, Remove) and the Save as box with Browse... are there too. The small drop window is gone.
- **Where it is saved:**
  - Items dropped on the launcher are saved next to the first dropped item.
  - Started without a drop, the file goes in the remembered folder (with Remember settings ticked), or else next to the first item.
  - Browse... picks any other place.
- **Dropping the script on its own launcher** (`7z-Encryptor.ps1` on `7z-Encryptor.bat`) just starts the tool with an empty list. It no longer offers to encrypt the script.
- **Email with mailto:** a fourth email option with a box for the address.
  - Several addresses are separated with `;`. The box can also be left empty.
  - Send by email opens Windows' own `mailto:` link. Your default mail program starts a new email to that address, with the file name as the subject.
  - A `mailto:` link cannot attach files, so the encrypted file is also selected in Explorer for you to drag into the email.
  - Typing in the box picks this option. With Remember settings ticked, the address is remembered too, in the settings file next to the script.
- **Fixed, found by the new edge-case tests:**
  - **Names with `&` or `^` dropped on the launcher** were cut up. Explorer quotes a name only when it has a space, so cmd read `R&D.txt` as `R` and dropped the `^` from `x^y.txt`. Launcher 1.1 now passes cmd's own command line to the tool, which reads the names from it whole. Names with `% ! ; , = ( )` and a launcher folder with `&` in its name were checked too. Started from a console, the arguments are used as before.
  - **The two passwords had to match only ignoring case.** "Secret" and "secret" were taken as the same. They must now match exactly.
  - **Saving inside a folder that is being encrypted** (for example with Browse...) is refused. 7-Zip would pack the new file into itself.
  - **`\\server\file.7z` was taken as a full path.** A share path now needs a share folder: `\\server\share\file.7z`.
  - **`;;` between email addresses** is now tidied instead of refused.
- The drop window's "save next to the dropped item" tick is no longer saved. An old value in the settings file is ignored.
- `7z-Encryptor.bat` 1.1: see the first fix above.

Tested:

- 77 / 77 checks of `tests/Run-7zEncryptor.ps1`. New checks cover:
  - mailto:
  - the window started by a drop
  - names with `& ^ % !` dropped on a copy of the launcher, and the console start
  - odd names and a password with `& ^ % ! \`, accents and a trailing space, encrypted and unpacked with 7-Zip
  - a save folder that does not exist yet
- 39 / 39 tests in the new `tests/7zEncryptor.Tests.ps1`, the edge cases of every helper.