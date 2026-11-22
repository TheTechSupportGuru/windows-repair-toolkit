# Test Results: Phase 0 (static) + Phase 1 (unit tests)

**Date:** 2026-11-19 · **Machine:** the Windows 11 VirtualBox VM (build 26300, en-US, UEFI) · **Run by:** Claude
**Safety:** no script was run, nothing was elevated, and no GUI was opened. The tests pull single functions out of the scripts and run them with stubs in place of `diskpart`, `bcdedit`, `takeown` and `icacls`. The only things written were a throwaway `HKCU:\Software\WinFixKitHarnessTest` key and some `%TEMP%` files, and all of it was cleaned up afterwards.

**Unit tests: 147 total · 127 passed · 20 failed.** Each failed test points to a suspected bug, listed below.
Re-run with:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script '.\Tests\Suite.Tests.ps1'"
```

Files: [Tests/Harness.ps1](../../tests/Harness.ps1) (pulls functions out of the scripts) · [Tests/Suite.Tests.ps1](../../tests/Suite.Tests.ps1) (the tests) · `Tests/last-run.xml` (NUnit results of that run; not kept in the repository)

---

## Fixes applied (2026-11-19): all S1/S2 bugs, #1–#6
The originals are the [v1.1 release](https://github.com/TheTechSupportGuru/windows-repair-toolkit/releases/tag/v1.1) (tag `v1.1`).
**Unit tests after the fixes: 173 total, 167 passed, 6 failed.** The 6 failures are only the lower-severity bugs that weren't in scope (#7, #8, #11, #12, #13).
All three changed scripts still parse cleanly, and PSScriptAnalyzer still reports 0 errors.

| # | Fix | Where |
|---|-----|-------|
| 1 | New `Resolve-RealPath` (Win32 `GetFinalPathNameByHandle`: follows junctions, expands 8.3 names) and `Test-ProtectedFolder`. Take-ownership now refuses drive roots; Windows, Program Files and ProgramData (and everything under them); `C:\Users`; the Default and Public profiles; any whole user profile; anything under `AppData`; and root system folders (Recovery, System Volume Information, `$Recycle.Bin`, EFI, Boot ...). The help text now says ownership isn't restored. | WinFixKit |
| 2 | `Load-Mounts` enumerates the parsed JSON correctly (no `@()` wrap). A failed save is now logged instead of being silently ignored. | WinSuperTool, WinRepairTool (V1.1) |
| 3 | New `Test-MountStillOurs`: a remembered mount is trusted only if `Get-Partition -DriveLetter` still returns the same disk and partition. Otherwise it's dropped and logged. | WinSuperTool, WinRepairTool (V1.1) |
| 4 | `Backup-Bcd` now returns success or failure, and also checks that the file exists. `Invoke-Bcd` **refuses to run the change** if the backup failed and returns an error, which the existing callers already show to the user. | WinSuperTool, WinRepairTool (V1.1) |
| 5 | `mpssvc` and `BFE` added to the blocked list. New `Test-RebootOnFailure` reads the service's `FailureActions` registry value (works in any Windows language). The killer refuses any process that hosts a service whose recovery action is REBOOT, even when "Allow shared" is ticked. | WinFixKit |
| 6 | BCD: the identifier is matched by its position (the first line under `-----`) and its `{…}` value, not by the English word. diskpart: new `Get-DiskpartRows` reads the table rows under the `---  ---` underline, so it never looks for the words "Disk" or "Partition". | WinSuperTool, WinRepairTool (V1.1) |

**Not yet verified:**
- None of this has been tried in the real GUI or with admin rights yet. That's Phase 2/3 on this VM.
- The German behaviour is only tested against sample text.
- `Individual scripts - PS Suite\WinRepairTool-startup.ps1` (the duplicate) has been **synced** to the fixed V1.1 copy. Before the overwrite it was byte-identical to the backed-up original, so nothing was lost.
- The `.zip` files still hold the old, unfixed versions.

## Bugs found

| # | Sev | Script | Finding | Evidence |
|---|-----|--------|---------|----------|
| 1 | **S1** | WinFixKit | **"Take ownership + reset permissions" doesn't block some system folders.** It runs `takeown /r` + `icacls /reset /t` on **`C:\ProgramData`**, on the **`C:\Documents and Settings`** and **`C:\Users\All Users`** junctions (these point to *all user profiles* and to ProgramData), on `C:\Users\Default` and `C:\Users\Public`, and on a whole user profile. The ACL backup restores permissions but **not ownership**, so the change can't be fully undone. The check (line 537) only blocks drive roots, `C:\Users`, `C:\Windows*` and `Program Files*`. It also doesn't resolve junctions or 8.3 short names (`C:\PROGRA~1` gets through). | U8a: 7 failures. Verified with stub `takeown`; nothing was really changed. |
| 2 | **S2** | WinSuperTool, WinRepairTool | **The Mount tab forgets every remembered mount once 2 or more are saved.** `@(ConvertFrom-Json $j)` in PS 5.1 wraps the whole array as a single item, so Load-Mounts drops all of them. The partitions stay mounted (e.g. the EFI partition stays visible as a drive) and the tool no longer lists them for unmounting. | U12: save 1 → load 1 ✅, save 2 → load **0**, save 3 → load **0** |
| 3 | **S2** | WinSuperTool, WinRepairTool | **A remembered mount is trusted just because its drive letter still exists.** It doesn't check that the letter still belongs to the same disk and partition. If another drive now has that letter, **"Unmount all" removes the letter from that drive.** Reversible (only a letter is removed), but it acts on the wrong drive. | U12: a saved `D:` entry was adopted; on this VM D: is the CD-ROM |
| 4 | **S2** | WinSuperTool, WinRepairTool | **A BCD change still runs when the automatic backup fails.** `Backup-Bcd` only writes "FAILED" to the log, and then `Invoke-Bcd` runs `/set`, `/copy` or `/delete` anyway. That contradicts "Every BCD change is backed up first". | U4b |
| 5 | **S2** | WinFixKit | **Service Killer can reboot the PC.** `mpssvc` (Windows Firewall) has the recovery action **REBOOT** and isn't in `$KillCritical`. It shares a process with `BFE`, so it's blocked only until the user ticks "Allow killing shared processes". The checkbox text doesn't mention a reboot. | U8b, using a live read-only `sc qfailure` scan of all services |
| 6 | **S2** | WinSuperTool, WinRepairTool | **Probably broken on non-English Windows:** `ConvertFrom-BcdText` looks for the English word `identifier` and the diskpart parsers look for `Disk N`. On German Windows (`Bezeichner`, `Datenträger`) nothing is found. Offline BCD targets and clones aren't detected, and diskpart mode lists no disks. Storage-cmdlet mode and live `{current}` still work. | U2 and U3 fail, **but these used sample text I wrote.** Confirm on a real non-English install. |
| 7 | S3 | Collect-Logs.ps1 (standalone) | When a *different* admin account elevates, logs go to **that admin's** Desktop instead of the logged-in user's. **WinSuperTool already fixed this**; the standalone copy wasn't updated. | U11 |
| 8 | S3 | WinSuperTool, Monitor-Logs | Paths containing a typographic apostrophe (`’`, e.g. `O’Brien`) break the code in the spawned monitor window. PowerShell treats `’` as a quote, and `Esc-Sq`/`Esc` only escape `'`. (WinFixKit `Start-InWindow` uses the same pattern.) | U10: 2 parse errors |
| 9 | S3 | WinSuperTool, ClaudeLogAnalyzer | The QR-pairing listener is handled on the **GUI thread** in a `while (Pending())` loop with a 1.5 s read timeout per client. Any device on the LAN can freeze the window by opening connections and sending nothing. (Token, OTP pad and key handling look sound; see "Passed".) | Code review, WinSuperTool.ps1:2133 |
| 10 | S3 | WinSuperTool | Recovery → bcdboot picks **UEFI vs BIOS from the file system** (FAT32 = UEFI), not from the PC's firmware. The boot-partition list also auto-picks **any FAT32 drive under 1.1 GB, including USB sticks**. | Code review, lines 1536 and 1572 |
| 11 | S3 | WinFixKit | Registry undo always goes back to the **very first** value ever backed up, even if the value was legitimately changed later and the fix was run again. | U6 (expected 7, got 5) |
| 12 | S4 | WinFixKit | An empty REG_MULTI_SZ restores as one empty string instead of an empty list. | U6 |
| 13 | S4 | WinSuperTool | Unattend: `%VAR%` in a user name gets expanded in the FirstLogonCommand. | U5 |
| 14 | S4 | WinSuperTool, WinRepairTool | `Invoke-Bcd` only backs up for `/set /copy /delete /deletevalue /import`. Those are the only verbs used today, so this is a trap for future buttons (`/default`, `/displayorder`, `/bootsequence` ...). | Code review |
| 15 | S4 | WinSuperTool | `bootrec /fixmbr` has no warning for GPT disks. (bootrec isn't present on this VM, so the tool correctly shows "not available".) | Code review |
| 16 | S3 | WinSuperTool | The Sysprep pre-flight **BitLocker check reads English `manage-bde` text**. On non-English Windows, or if manage-bde fails, it reports **"OK – no BitLocker"** even when BitLocker is on. The code itself notes "English output only". Should use `Get-BitLockerVolume` / `Win32_EncryptableVolume`. | PSScriptAnalyzer (empty catch) + code review, line 1371 |
| 17 | S3 | WinFixKit | A **corrupt registry-backup .json is silently left off** the Registry Backups tab (`catch { }`, line 1870). That change then has no Restore button, and nothing tells the user. | PSScriptAnalyzer (empty catch) |
| 18 | S4 | WinSuperTool, WinRepairTool | `Save-Mounts` swallows write errors, so a failed save goes unnoticed (this makes #2 worse). The activity log write (WinSuperTool.ps1:98) does the same, so the audit trail can silently stop. | PSScriptAnalyzer (empty catch) |

### Process issue: the standalone copies have drifted
Compared function by function with WinSuperTool:
- **WinRepairTool-startup.ps1:** 27 of 41 functions differ.
- **ClaudeLogAnalyzer.ps1:** 8 of 18 differ.
- **Collect-Logs.ps1:** all 5 functions differ.
- **Monitor-Logs.ps1:** its main function differs.

Fixes made in WinSuperTool (e.g. #7) never reached the standalone files, and every fix from now on has to be made in several places. **Recommendation: retire the standalone scripts, or generate them from WinSuperTool.**

## Passed
- **diskpart allow-list:** 54 cases × 2 scripts. `clean`, `format`, `delete`, `create`, `convert`, `select volume C`, `assign letter=C`, newline-smuggled commands, `attributes`, `gpt attributes`, `set id` and others are all **blocked**. Normal mount/unmount commands are allowed.
- **BCD parsing (English):** reads `{current}`, clone entries and safeboot correctly. An unmounted `\Device\…` entry never matches a drive letter. Creating a clone rolls back if the second step fails (code review).
- **Unattend XML:** well-formed with `& < > " '` in every field. The password encodes back correctly. Computer names over 15 characters and user names with `'` are rejected.
- **Registry backup and restore** (HKCU test key): DWord (including 0xFFFFFFFF), QWord, String, ExpandString (stays unexpanded), MultiString, Binary, a value that didn't exist before (gets removed), a key the fix created (gets removed), and a whole-key export + reg import.
- **Service Killer:** the 12 listed critical services and the core processes are refused, and the PID parsing works on English `sc` output. The interval can't go below 250 ms, and closing the window stops the timer (code review).
- **API key (S5):** it's only placed in request headers (`x-api-key` / `x-goog-api-key`). It's never logged or written to disk, and it's cleared when the session ends or the window closes. The pairing pad travels in the URL `#fragment`, so it's never sent over the network. The key must match `sk-ant-…` or `AIza…`.
- **WinSuperTool `Get-InteractiveUser`:** returns the correct Desktop, with the raw-registry fix.

## PSScriptAnalyzer (S2)
I installed PSScriptAnalyzer 1.25.0 for the current user only (`Documents\WindowsPowerShell\Modules`), after your OK, and ran it on the 6 main scripts at **Error and Warning** severity.

**0 Errors and 250 Warnings.** Nearly all of the warnings are style issues that don't need action:

| Count | Rule | Verdict |
|---:|---|---|
| 82 | ReviewUnusedParameter | Not a bug. These are fixed signatures (`param($Arg)` on every WinFixKit action, `param($W,$Live,$Root,$Prof)` on every collector, event handlers). I checked each collector: wherever `$Live` matters, it's used. |
| 51 | UseShouldProcessForStateChangingFunctions | Style: GUI script, no `-WhatIf` needed |
| 50 | AvoidUsingEmptyCatchBlock | I reviewed all 50. Most are fine (cleanup or optional info). **3 hide real problems → #16, #17, #18.** |
| 27 | AvoidUsingCmdletAliases | All 27 are Monitor-Logs' own function named `Item`. Works, but rename it to something like `New-MonItem` (as WinSuperTool does). If it were ever undefined, PowerShell would silently run `Get-Item` instead. |
| 24 / 13 | UseSingularNouns / UseApprovedVerbs | Style |
| 2 | UseDeclaredVarsMoreThanAssignments | `$lblQrHow` (WinSuperTool:1796) and `$lblToolNote` (WinRepairTool:702): labels that are created but never referenced afterwards. Harmless. |
| 1 | AvoidUsingWriteHost | Style |

By file: WinSuperTool 89 · WinFixKit 74 · WinRepairTool 41 · Monitor-Logs 29 · ClaudeLogAnalyzer 14 · Collect-Logs 3.

Re-run with:

```bash
powershell -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning"
```

## Not done yet
- **U9 QR decode check:** skipped. It needs a QR decoder library loaded in a browser page.
- **U6 sc PID on non-English Windows:** unknown. It's safer to read the PID from `Win32_Service.ProcessId`, which doesn't depend on the language.

## Suggested fix order
1. **#1 Take-ownership check:** resolve the real path first (junctions and 8.3 names), and add ProgramData, the Users subfolders, profile roots and `System Volume Information` to the blocked list.
2. **#2 and #3 Mount memory:** load with `$j | ConvertFrom-Json | ForEach-Object { … }`, and save Disk + Partition + a volume ID, re-checked on load.
3. **#4:** stop the change if `Backup-Bcd` fails.
4. **#5:** add `mpssvc` and `BFE` to the blocked list, or better, refuse any service whose recovery action is REBOOT.
5. **#6:** replace text parsing with `Get-Disk`/`Get-Partition` and `bcdedit /enum /v`, or match GUIDs only. Then confirm on a non-English VM.
