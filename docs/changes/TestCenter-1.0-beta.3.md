# Test Center 1.0 beta 3 (2026-11-22)

- **New tab: Backup Script Builder.** Runs `tests/Run-BackupScriptBuilder.ps1`: builds a FreeFileSync script and compares it line by line with a reference, checks the destination folder rules, creates, reads back and deletes a scheduled task of every schedule type (in `\BackupScriptBuilder\`, as you), and checks the layout and every **?** help text. Ticked by default, about 2 minutes, no admin needed. Greyed out when the chosen tools folder has no `BackupScriptBuilder.ps1`.
- **Fix:** a summary line that starts with `PASS` no longer counts as a problem (`PASS  a missing script is refused` made the new test show CHECK).
- Tested: the new tab through Test Center's scripted run, 28 / 28 passed, result OK.
- The included tools are 1.9.2.

Everything else is as in [beta 2](TestCenter-1.0-beta.2.md) and [beta 1](TestCenter-1.0-beta.1.md).
