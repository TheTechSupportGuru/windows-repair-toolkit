# 7z-Encryptor 1.2 (2026-11-26)

Part of the toolkit's 2.2 release.

- **Show in folder** and **Send by email** buttons under the Encrypt button. They turn on after a file is encrypted (the status line says which file); a failed run still shows its message box.
- **Email with** (three options, remembered):
  - **Send to > Mail recipient:** the classic Windows way, the same Simple MAPI call as right-click > Send to > Mail recipient. Opens a new email with the file attached in a classic mail program (Outlook classic, Thunderbird, ...). If no classic mail program answers (for example only the new Outlook or webmail), the **Windows Share** window opens instead; if that is missing too, Explorer opens with the file selected and a message says so.
  - **Windows Share:** the Windows 10 / 11 Share window (Explorer's Share command), for mail apps, nearby sharing and so on.
  - **Choose program...:** pick a mail program once. Outlook gets `/a <file>`, Thunderbird gets `-compose attachment=...`, any other program is started with the file name.
- **Remembered between runs:** the folder of the last encrypted file (used for "Save as" next time; when that folder is gone, it is next to the first item again), the email choice and program, and the drop window's "Save next to the dropped item" tick.
- **Portable settings:** kept in `7z-Encryptor.settings.json` in the same folder as `7z-Encryptor.ps1`, so a USB stick or WinPE kit keeps them on every PC. Never a password. If the folder is read-only, nothing is remembered and the tool works as before.
- The **?** help explains the buttons and says to send the password another way, never in the same email.

Tested: 54 / 54 checks of `tests/Run-7zEncryptor.ps1` (11 new: the buttons and options, the settings file and that it holds no password, the remembered folder and its fallback, the mail program command lines, the messages when there is no file or no program). Found and fixed by the new tests before release: the email options shared a radio group with 7z / zip, so picking a format cleared them; they now have their own panel.

Not tested by clicking: the mail and Share windows themselves were not opened. On the test PC the Share command and `mapi32.dll` are there but no classic mail program is registered, so "Send to > Mail recipient" would fall back to the Share window there.