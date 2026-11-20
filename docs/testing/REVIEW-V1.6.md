# Code review of V1.6 (2026-11-19): 4 parallel read-only reviews

Four review agents each read one area of `Edited scripts\V1.6`. None of them edited or ran anything that changes the system. **These findings are claims by the reviewers until I verify them** while building V1.7. Each one is re-checked in the code before it gets fixed, and any I reject are marked as such in V1.7's CHANGES.md.

Totals: **85 findings: 0 S1, 18 S2, 36 S3, 31 S4.** The IDs are prefixed by area: **K** = WinFixKit, **S** = WinSuperTool, **R** = WinRepairTool, **A** = standalone scripts (Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer) and the .bat launchers.

## WinFixKit (22)

| ID | Sev | Finding | Proposed fix |
|---|---|---|---|
| K1 | S2 | "Enable Network Discovery + File/Printer Sharing" uses `Set-NetFirewallRule -DisplayGroup … -Profile 'Private,Domain'`. `-Profile` **sets** the profile, it doesn't filter, so the rules' profile definitions are permanently rewritten. `-DisplayGroup` is localized, so it also does nothing on non-English Windows. The status check uses the same localized group name. | Select by `-Group '@FirewallAPI.dll,-32752'` / `'-28502'`, keep only rules whose Profile isn't Any and doesn't include Public, then `Enable-NetFirewallRule`. |
| K2 | S2 | `Restore-RegBackup` VALUE branch: `New-Item`/`New-ItemProperty`/`Remove-ItemProperty` have no `-ErrorAction Stop`, so a failure still prints "Restored" **and sets `RestoredAt`**. The original can then be overwritten later. | try/catch with `-ErrorAction Stop`; return FAILED without marking the backup restored. |
| K3 | S2 | Take ownership: `takeown /d y` uses a localized answer letter (J, O …), so it fails on non-English Windows. No exit codes are checked, so `/reset` runs even when the ACL `/save` backup failed. | Abort if `/save` fails. If takeown fails, fall back to `icacls /setowner *S-1-5-32-544`. Warn on a `/reset` error. |
| K4 | S2 | `Get-PowerSettings` and the USB-suspend status parse English `powercfg /q` labels, so they're empty on non-English Windows. | Parse GUID lines and hex values only; the last 2 hex values are AC and DC. |
| K5 | S2 | "Reset sign-in token cache" and "Rebuild tile DB" are marked Admin=$false but stop services, and the failure is hidden by `Out-Null`. When run elevated as another user, `%LOCALAPPDATA%` points at the wrong profile. | Show the result of the stop and rename, and abort on failure. Warn when the elevated user isn't the console user. |
| K6 | S2/S4 | Status parses localized output: `netsh winsock show catalog \| Select-String 'Catalog Entry'` and `cmdkey /list \| Select-String 'Target:'`. | Count `Protocol_Catalog9` registry entries; for cmdkey, use lines containing `=`. |
| K7 | S3 | `Checkpoint-Computer` only warns (it doesn't throw) when a restore point already exists from the last 24 h, yet the tool prints "created". | Compare the restore point count before and after. |
| K8 | S3 | Full backup: success is judged by `Test-Path`, not `reg save`'s exit code, and `FullBackupDone=$true` is set unconditionally. | Use the exit code; set the flag only if both hives were saved. |
| K9 | S3 | KB removal: 2359302 (0x240006) means *already installed*; the not-installed code is 2359303 (0x240007). | Fix the switch. |
| K10 | S3 | Test access: `\\nas\public` becomes `nas\public`, so every test fails. | Keep only the host part. |
| K11 | S3 | Set Public→Private and SMB Method 3 print success without checking the result. | try/catch with `-ErrorAction Stop`. |
| K12 | S3 | WinHTTP proxy reset changes `WinHttpSettings` with no backup. | Back up the value and set Registry=$true. |
| K13 | S3 | WU reset: the `qmgr*.dat` filter matches nothing on Win10/11 (qmgr.db + edb logs). `Get-BitsTransfer` after stopping BITS restarts it. DoSvc isn't stopped. | Clear jobs first, stop DoSvc, use the new filter. |
| K14 | S3 | Search status only looks for `Windows.edb` and ignores `DataDirectory`. | Use the same file list as the rebuild. |
| K15 | S3 | Restart Explorer from an elevated tool can start an **elevated** Explorer if the shell doesn't auto-restart within 2 s. | Wait up to 5 s; never start Explorer elevated. |
| K16 | S3 | Long work on the UI thread (reg save, restore point, Appx loops, ipconfig /renew, print jobs). | DoEvents/status, or move the work to a window or runspace. |
| K17–K20 | S4 | Optimization: unfiltered `Win32_PnPSignedDriver` (1.5 s), `Get-AppxPackage -AllUsers` called 3×, `Get-Printer` called repeatedly, `Get-HotFix` (1.6 s). | Add filters and reuse results. |
| K21 | S4 | "Set Balanced" (Registry=$true) triggers a full hive backup plus a restore point for a trivial change. | Remove the flag. |
| K22 | S4 | Help text says "logs folder" for Reports. "Re-register ALL" help mentions red errors that are suppressed. The unreadable-backup warning repeats after every fix. | Correct the text; warn only when the list changes. |

## WinSuperTool (21)

| ID | Sev | Finding | Proposed fix |
|---|---|---|---|
| S1 | S2 | AI request: a single empty `.evtx` (the fallback `-ErrorAction Stop` throws "No events") or one undecodable image aborts the **whole** request, and the status stays stuck. | Handle an empty evtx; try/catch per file and add a note. |
| S2 | S2 | Truncating an evtx keeps the **end** of a newest-first list, so the header and newest events are lost. | Truncate evtx text from the start. |
| S3 | S2 | Pairing: the 700 ms timeout is per read, so a trickling client can hold the UI thread up to about 80 min. | 1.5 s overall deadline per request. |
| S4 | S2 | Recovery window tools: `cmd /c <line> & pause` only quotes args containing spaces, so `&`, `^` and `%` in a driver path break or inject commands. | Run in a PowerShell window with `-EncodedCommand` and single-quoted args. |
| S5 | S2 | A second Windows booted from the running PC's ESP: the store found on the mounted ESP is the **loaded** system hive, so the backup copy fails and every BCD tool is blocked. | On live Windows, look in the system store first (`Store=$null`). |
| S6 | S2 | Log collection runs on the UI thread. Closing mid-collection auto-unmounts the source drive, and other tabs stay usable during the copy. | Busy flag; disable tabs; cancel FormClosing while busy; progress with DoEvents every N files. |
| S7 | S3 | The help says every BCD change is backed up, but bcdboot and `bootrec /rebuildbcd` aren't. | Back up before those tools. |
| S8 | S3 | Non-window recovery tools never check the exit code or show the result. | Show a message with the exit code. |
| S9 | S3 | WinPE without Storage cmdlets: the mount memory drops everything, with a misleading log. | diskpart fallback (letter column). |
| S10 | S3 | `Get-PartLetter` still matches English diskpart words (`no volume`, `Volume`). | Read the column by position under the underline. |
| S11 | S3 | No total image budget: up to 60 × 4.5 MB images can exceed API request limits. | Cap images at about 15 MB total. |
| S12 | S3 | `New-AiRequest`, `Get-Preflight` (Appx) and repeated diskpart calls block the UI. | DoEvents/status; reuse `detail partition` output. |
| S13 | S3 | The one-time pad is reused across up to 5 rejected key attempts (key XOR key leaks). | Cancel the QR after the first rejected key. |
| S14 | S3/opt | `Resolve-BcdTarget` scans every drive (network, optical), and `Update-SafeStatus` runs twice per rescan. | Fixed/Removable only; suppress the duplicate event. |
| S15 | S4 | Gemini `MAX_TOKENS` truncation isn't flagged. | Add a note. |
| S16 | S4 | Failed offline restore: store attributes aren't put back. | Restore attributes in `finally`. |
| S17 | S4 | `Get-ImagePart` leaks GDI objects on error. | Dispose in `finally`. |
| S18 | S4/opt | Copy-One uses Copy-Item per file (slow, double exception on locked files). BIG has no free-space check. | `[IO.File]::Copy` first; free-space check. |
| S19 | S4 | INFO counts systeminfo/dism files without checking the exit code. | Count per success. |
| S20 | S4 | The crash-events catch reports every error as "no events found". | Separate "no events" from real errors. |
| S21 | S4 | Help text mismatches: version header, backup-tool summary, webp/gif not downscaled, "-Tail 20". | Correct the text. |

Unconfirmed, still to test: whether the Unattend `<Group>Administrators</Group>` works on localized Windows; "Password never expires" for standard users (it runs as the new user); and whether Claude's 5 MB image limit counts the base64 size.

## WinRepairTool (18): the reviewer recommends retiring it

The two tools share 49 functions: 23 are byte-identical, 16 differ only in style, and 10 differ in behaviour. **In every case WinSuperTool is equal or better.**

| ID | Sev | Finding |
|---|---|---|
| R1 | S2 | (both tools) Auto-unmount on close happens while a repair console started by the tool may still be using the drive. |
| R2 | S2 | (both) `Dismount-One` doesn't re-check that the letter still belongs to the remembered partition (only Load-Mounts checks), so it can remove another volume's letter. |
| R3 | S2 | (R only) Knows only its own clone marker, so it can't see or delete WinSuperTool's Safe Mode clones and creates duplicates. |
| R4 | S3 | (both) `Resolve-BcdTarget` takes the first store that matches; same root cause as S5 for a live dual boot. |
| R5 | S3 | (R only) `Update-Esp` throws away the user's boot-partition choice on every refresh. |
| R6 | S3 | (R only) The running Windows can be selected, but its recovery tools only use offline syntax (`/image:C:\`, `sfc /offwindir`), so they fail. |
| R7 | S3 | (both) Unattend deploy: if backing up the existing file fails, it's overwritten anyway. |
| R8 | S3 | (both) = S10. |
| R9 | S3 | (both) = S4. |
| R10 | S3 | (both) = S12 UI blocking. |
| R11–R14 | S4 | (R only) Install choice cleared on rescan; no check that the exe exists (bootrec); wrong RAM-disk note; no persistent activity log. |
| R15 | S4 | (both) Clone deletion ignores the bcdedit result. |
| R16 | S4 | (both) The clone may be unreachable when the boot-manager timeout is 0. |
| R17 | S4 | (both) A 32-bit host makes sysprep "not found". |
| R18 | S4 | (both) "Password never expires" runs as the new user. |

## Standalone scripts and launchers (24)

| ID | Sev | Finding |
|---|---|---|
| A1 | S2 | ClaudeLogAnalyzer: the whole AI request (`Invoke-RestMethod -TimeoutSec 180`) runs on the UI thread, with no cancel and no session-expiry enforcement while it runs. |
| A2 | S2 | ClaudeLogAnalyzer: `max_tokens=2500` and `stop_reason` isn't checked, so a blank or cut-off answer is shown as "Done". |
| A3 | S2 | ClaudeLogAnalyzer `Read-Log`: `ReadAllText` fails on logs Windows has open and loads whole multi-hundred-MB files. |
| A4 | S2 | ClaudeLogAnalyzer: `Invoke-RestMethod` decodes the reply as ISO-8859-1, so non-ASCII answers are garbled. |
| A5 | S2 | Collect-Logs: copies on the UI thread; closing mid-run leaves a hidden handler copying. |
| A6–A9 | S3 | ClaudeLogAnalyzer: `-Path` wildcard bug with `[ ]` in file names; Gemini blocked prompt throws; no total size budget or binary check; raw 5 MB image check without downscaling. |
| A10 | S3 | WinSuperTool.bat: from a 32-bit host, the elevated relaunch uses a Sysnative path that doesn't exist for the 64-bit PowerShell, so elevation fails. |
| A11–A14 | S3 | Collect-Logs: output not cleared between runs and no try/finally; INFO count is wrong; Monitor `__IDS__` injection; no UAC-cancel message or 64-bit relaunch in the standalone tools. |
| A15–A24 | S4 | Hard-coded `C:\Windows`; per-file New-Item; missing `Get-WindowsUpdateLog` check; event monitor fetches 100 events every 2 s; Monitor process list never pruned; "400 OK" status line; RNG/QR/tick hygiene; drag-drop of non-files; `call set` mangles `^`; launcher variables leak (no `setlocal`). |

**The reviewer's main point:** ClaudeLogAnalyzer, Collect-Logs and Monitor-Logs are old copies that lack most of WinSuperTool's improvements (a table of 22 missing features was supplied). Like WinRepairTool, they're better **retired in favour of WinSuperTool**, or rebuilt from it, than patched separately.
