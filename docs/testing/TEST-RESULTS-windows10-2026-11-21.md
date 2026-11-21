# Test results: Windows 10 (2026-11-21)

Field test (`tests/Run-FieldTest.cmd`) and two extra runs (`tests/Run-SystemInfoButtons.ps1`, `tests/Run-Windowed.ps1`), run by a second Claude session on a Windows 10 VM. Branch `resize-pass-2` at `69811f6`, scripts unchanged. The VM was snapshotted first.

Test PC: Windows 10 Pro 22H2 (build 19045), English, VirtualBox, **Legacy BIOS (MBR disk)**, .NET 4.8, two monitors (3840x2160 + 2560x1440) at 100 %, no Wi-Fi or Bluetooth, run as administrator.

**Result: the tools work on Windows 10.** Every failure was in a test script (fixed), except one unit test that is now made to explain itself on the next run.

## Results

| Area | Result |
|---|---|
| System Info, all 6 parts | pass |
| Window sizes, all 9 GUI scripts, both monitors | no issues |
| Real scans read back by the summaries (DISM checkhealth, chkdsk /scan, sfc /verifyonly, DISM scanhealth) | 4 / 4 correct. **sfc found real corruption** on this VM: "CORRUPTION DETECTED (scan only - nothing was repaired)" |
| Live Monitor | 33 / 33 |
| System Info buttons as administrator | 7 info windows and 42 tool buttons: 5 + 40 passed; the rest were test problems (below) |
| WinFixKit fixes that open their own window | all finished; see below |
| Unit tests | stable 280 / 286, toolkit 21 / 22, beta 50 / 50 (below) |

### A damaged system, repaired for real

WinFixKit's "Repair system files (DISM + SFC)" ran on this VM after sfc had found corruption: DISM "The restore operation completed successfully", then SFC "Windows Resource Protection found corrupt files and successfully repaired them". Given to the beta's summary logic (`Get-TaskVerdict`, kind `sfc`), that exact output reads **"CORRUPTION DETECTED - FIX WORKED (all corrupt files were repaired)"**. This is the first test of the repair path on a really damaged Windows (until now only Windows' wording in unit tests).

Other console fixes: energy report written (5 errors, 26 informational), chkdsk read-only scan "no problems", chkdsk /f asked to schedule and N left the volume clean, KB5025221 "not installed - nothing to remove". Re-register all apps: 91 packages, one Windows failure reported as such (`windows.immersivecontrolpanel`, 0x80073CF9 - the Settings app, which was in use).

## What failed, and why

| Failure | Cause | Fix |
|---|---|---|
| 4 unit tests: Test-IsMsr / Mount-Part refuses the MSR (stable WinSuperTool + WinRepairTool) | The tests assume disk 0 is a GPT disk with a Microsoft Reserved partition. This PC has an MBR disk (Legacy BIOS), so there is none, and the test passed an empty partition number. The tools are fine on MBR. | the tests are skipped when disk 0 has no MSR |
| 2 unit tests: Get-BitLockerState as administrator | BitLocker's WMI has no entry for C: on this PC, and the tools correctly say "unknown (volume not found in BitLocker WMI)" instead of claiming "Off". The test only accepted On / Off as administrator. | as administrator the test accepts "unknown" exactly when the WMI has no entry for the drive |
| 1 unit test: a centred window that grows when it scales ends up on the screen (simulated 150 %) | Not explained. This PC has .NET 4.8, the Windows 11 test VM 4.8.1; one possibility is that 4.8 scales the window after the Load event, so it is first centred with its smaller size. In the tools, the screen check that runs when the window appears would move it back on the screen. | the test now prints the window, the work area and the .NET release; the resize audit now checks where every tool window **opens**, and the field test runs it at a simulated 150 % |
| System Info: "Copy all" read back 0 characters in 2 of 7 windows (Save as... was correct) | The **test's** single clipboard read: another program (here most likely VirtualBox's clipboard sync) can hold the clipboard for a moment. The tools' Copy uses .NET's `SetText`, which already retries 10 times (checked with the clipboard held by another process: the copy still works). | the test reads the clipboard with retries |
| DirectX Diagnostic counted as PASS, but dxdiag first asked a question | On first use dxdiag asks "Do you want to allow DxDiag to check if your drivers are digitally signed?" in a box with the same title as dxdiag itself, so the test took the question for the tool. (Reported by the person running the test: dxdiag opened fine after answering No.) | the test recognises a Yes/No question box, records its text and answers No, then waits for the tool itself (checked with a stand-in box) |
| Windows Update / About this PC: "no new window" | A Settings window was already open and Settings reused it (as on Windows 11). | the test closes an open Settings window before testing a Settings page |

## Still open

Rerun the field test on Windows 10 (with these fixes) to see where windows open at a simulated 150 % on .NET 4.8, and the explaining unit test. Wi-Fi and Bluetooth hardware were not present on this PC either.
