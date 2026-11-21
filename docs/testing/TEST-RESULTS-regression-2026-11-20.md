# Regression test results (2026-11-20, branch `resize-pass-2`)

A regression pass over everything that was last tested on an older version: the beta's Automation, Live Monitor and Recovery summaries (last tested on beta 4), and the stable tools' functions (last tested on 1.8). Run on the two-monitor test VM, mostly as administrator. Code: 1.8.4 / 1.9 beta 5 drafts with all fixes up to commit `98fb2b0`.

**Result: no regressions.** Everything gives the same results as in its last real test. No bugs found in the tools; two problems in the test scripts were fixed.

## Without admin rights

| Check | Result |
|---|---|
| Unit tests | stable 286 / 286, toolkit 22 / 22, beta 50 / 50 |
| Automation GUI, beta and no-AI beta: 2 test tasks (one finds "repairable corruption", one fails) | Both: the "repair only if needed" step was added automatically, the failing task reported FAILED, 3 popups + final summary ("3 task(s) ran: 2 passed, 1 failed"), HTML report written with the beta 5 phone layout |
| System Info collectors, both betas | all 6 return data (0.3-4.3 s) |

## As administrator (one UAC prompt, 15 minutes)

| Part | Check | Result |
|---|---|---|
| A | Live Monitor: all 27 items + 6 live-activity checks (`Run-MonitorLive.ps1`) | **33 / 33** (beta 4: 33 / 33) |
| B | Recovery summaries on real scans in the task window: DISM checkhealth, sfc /verifyonly, chkdsk /scan, DISM scanhealth | **4 / 4 correct**, quoting Windows' own result lines (beta 4: 4 / 4) |
| C | Automation, 7 real tasks: restore point, DISM check, SFC "repair only if needed", chkdsk scan, Windows Update check, winget list, Defender update + quick scan | **Same as beta 4** in 3 min 13 s: 6 passed with the right results (no corruption, no problems, up to date, 3 app upgrades available, no threats); the restore point **correctly failed** (System Protection is off on this VM; Windows' reason quoted). 7 popups + final summary on screen, HTML report "1 FAILED, 6 passed". |
| D | WinFixKit: every "Check status" section, with a system snapshot before and after (`Run-StatusChecks.ps1`) | All 15 sections ran. See the two notes below. |
| E | WinRepairTool read-only checks against the real boot store and disks | **7 / 7** |
| E | Monitor-Logs live event poller | **2 / 2** (new events shown once, other IDs filtered out) |
| E | Full log collection (WinSuperTool live + offline, Collect-Logs) and the AI log readers | 389 files, 546 MB, **0 failed**; both AI readers handle every file type |
| E | All 5 stable tools opened as administrator for 20 s | all stay open, **0 errors** in their transcripts |

### Notes on part D (not tool bugs)

- **"SNAPSHOT CHANGED: Services"**: the only change was the start type of **BITS** (Manual to Automatic). The System log shows Windows itself (`NT AUTHORITY\SYSTEM`, event 7040) switching BITS between Manual and Automatic three times in 6 minutes, also during a later run without admin rights, which cannot change a start type at all. BITS does this whenever downloads are queued or finished (the Windows Update and Defender tasks of part C had just queued some). The test now leaves BITS out of the snapshot.
- **Store Apps "error 0x80073D02"**: that is the status check correctly **showing** an entry from Windows' AppX event log (a Microsoft app update failed because the app was in use). The test counts every line containing "error".

## Test script fixes

- `tests/Run-ElevatedSmoke.ps1` looked for the old `Edited scripts` folders, which are not in the repo; it now tests `tools\`.
- `tests/Run-StatusChecks.ps1` ignores BITS' start type (see above).

## Not covered

Unchanged from the earlier plans: WinFixKit's fixes applied and undone (`Run-Phase3.ps1`, needs a VM snapshot first), AI Analyze with a real API key and phone pairing, real Wi-Fi / Bluetooth hardware, repair results on a damaged system, WinPE, Windows 10, non-English Windows, a physical PC, the main monitor at 150 % / 200 % and dragging windows with the mouse.

Test output (contains this PC's name, logs and addresses) stays on the VM under `C:\Users\Public\wst-reg`; the 1.5 GB log-collection copy was deleted after the run.
