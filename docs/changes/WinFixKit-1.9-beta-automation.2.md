# WinFixKit 1.9 beta-automation 2 (2026-11-21)

The first **full test with real fixes**: every one of the 66 Automation tasks (restore point, 15 status checks, 50 fixes) ran through the real queue as administrator on a Windows 11 test VM, from a snapshot. Beta 1 and its notes: [beta-automation 1](WinFixKit-1.9-beta-automation.1.md).

## Found and fixed

| | Problem | Fixed |
|---|---|---|
| 1 | **Two fixes lost their result line** ("Re-register Start and Shell packages", "Re-register Account Broker plugin"): Add-AppxPackage's progress bars are drawn over the console text the summary reads back, so the result showed "no known result message". | Task windows run with progress display off. |
| 2 | **"WITH ERROR MESSAGES" for fixes that were fine**, for example "Restart Start / Search / Shell processes" and "Remove update KB5025221". The count included errors a fix silences on purpose, such as stopping a process "if it is running". | Only errors the fix actually shows are counted (its error stream), and they're printed in red. |
| 3 | **Real failures looked clean** once (2) was fixed. The Store re-registers catch their errors and print "Failed Microsoft.WindowsStore: ... 0x80073D02" (apps in use) as text. | Lines in which a fix says a step failed ("Failed ...", "FAILED ...", "Error ...") count as failed steps: "FIX RAN - WITH ERROR MESSAGES". |
| 4 | **"Empty Recycle Bin" FAILED when the bin was already empty**: `Clear-RecycleBin` throws "The system cannot find the path specified" (Win32 error 3). This was also the confusing message when run by hand. | An empty bin now says "The Recycle Bin was already empty - nothing to remove". It's recognised by the error number, so it works in any display language. This is a fix to WinFixKit itself, marked in the code as a beta-automation fix, and should go into the stable WinFixKit when the beta is promoted. |

Not a bug: "Energy efficiency report" says "No report was written (powercfg exit code 0 after 0 s)". `powercfg /energy` doesn't work on this Windows 11 build (26300), and the fix already says so in plain words.

## Results (second full run, after the fixes)

- **All 66 tasks PASSED.** That's the restore point, 15 status checks and 50 fixes; each ran to the end.
  - The network resets (Winsock, TCP/IP, full reset) say "RESTART NEEDED".
  - DISM + SFC took 12 minutes; re-registering all apps took 2 minutes.
- **Targeted re-run of the changed parts:**
  - the Store re-registers report "WITH ERROR MESSAGES" for their real "apps in use" failures;
  - the empty Recycle Bin, Start/Search restart, Start re-register and KB5025221 report "FIX RAN - no error messages".
- **On screen:**
  - a summary window after every task;
  - the final summary ("7 task(s) ran: 7 passed", "Restart needed: no");
  - the HTML report, whose banner flags the two Store results as needing attention.
  - Every queue of the full run produced its final summary and HTML report.
- **Unit tests:** `tests/WinFixKitAutomation.Tests.ps1` now also checks the result counting with stand-in fixes: a silenced error, a shown error, a thrown error, and a failure printed as text.

## How to run it

`tests/Run-WinFixKitAutomation.ps1 -All` (as administrator, **only on a test VM with a snapshot**: the fixes really change the PC). It runs every task through the beta's real queue, 10 per queue, with the network-disrupting fixes last. It writes `report.txt` and, per queue, the results, popups, final summary and HTML report.

## Not tested yet

- Windows 10.
- A PC where the fixes have real problems to fix (this VM was healthy).
- The window-size regression was not repeated: nothing in the window changed since beta 1.
