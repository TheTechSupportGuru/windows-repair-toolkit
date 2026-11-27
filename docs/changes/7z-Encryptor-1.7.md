# 7z-Encryptor 1.7 (2026-11-27)

- **mailto: no longer closes the "pick an app" prompt.** With no default mail program set, Windows asks which app should open mailto: links. The tool used to open Explorer at once, which closed that prompt. It now waits until the prompt is gone (an app picked or the prompt closed, at most 10 minutes) and then selects the file in Explorer.
- **New "Default..." button** left of the mailto: option: opens Windows Settings > Default apps to change the mail program for mailto: links. In Windows PE (no such page) it says so.

Tested: `tests/Run-7zEncryptor.ps1` (93 passed, no overlapping controls with the new button).
