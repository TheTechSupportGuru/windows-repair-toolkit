# Final regression before promotion: 1.9 beta 5 (2026-11-21)

The full regression from [FINAL-RELEASE-PLAN-1.9.md](FINAL-RELEASE-PLAN-1.9.md), step 2, on branch `resize-pass-2` with every fix up to the Hiren's PE runs. Test VM: Windows 11, 4K + 2K monitor, 8 cores.

**Result: one bug found and fixed (R1); everything else passed.** Together with the Windows 10 field test and the Hiren's PE 10 / PE 11 runs, the beta is ready to be promoted.

## As administrator (`tests/Run-Regression.ps1`, 22 minutes)

| Part | Result |
|---|---|
| A Live Monitor, every item + live activity | **33 / 33** |
| B Recovery summaries on real scans (DISM checkhealth + scanhealth, sfc /verifyonly, chkdsk /scan) | **4 / 4** |
| C Automation, 8 real check tasks | 7 passed with real results (SFC, DISM x2, chkdsk clean; Windows Update: 1 Defender definition update available; winget: 3 upgrades available; Defender: no threats); the restore point **correctly failed** (System Protection is off on this VM, Windows' reason quoted) |
| C2 Automation options | stop on fail: correct; popups off and HTML report off: 0 popups, 0 reports, the queue still ran |
| D WinFixKit status checks | all sections ran, snapshot before / after: **nothing changed** |
| E WinRepairTool + Monitor-Logs checks; log collection; every stable tool opened as admin | **9 / 9**; 400 files (560 MB), 0 failed (the copy was deleted afterwards); all 5 tools open, 0 errors |
| F System Info: every button | **49 / 49** (7 info windows incl. Copy all and Save as..., 42 Windows tools) |

## Without admin

| Run | Result |
|---|---|
| Unit tests | stable 288 / 288, toolkit 24 / 24, beta 54 / 54 |
| Window sizes, 9 tools in parallel, 100 % and simulated 150 % | no issues |
| Two-monitor matrix (monitor 2 right; at 150 %; switched off and on; across the edge) | **1 bug (R1)**, then no issues after the fix |
| Mouse drag between the monitors (real mouse, button held across the edge) | 9 / 9 drags |

## R1 (fixed): WinSuperTool was minimized when the monitor it was on was removed

| | |
|---|---|
| Seen | Two-monitor matrix, step "monitor 2 switched off" with WinSuperTool on monitor 2: the main window ended **minimized** (160 x 28 at -32000,-32000), every time; the other tools simply moved to monitor 1. All four WinSuperTool scripts (stable, beta, no-AI). |
| Cause | WinSuperTool minimizes its console window at start with `ShowWindow(console, 6)` (SW_MINIMIZE, which also activates another window). With that line disabled the main window moved to monitor 1 normally; with 7 (SW_SHOWMINNOACTIVE, minimized without activating) and with 0 (hidden) too. |
| Fix | The console is minimized with 7: still minimized behind the tool, errors still readable there. Toolkit test: no WinSuperTool script uses 6 any more. |
| Check | Full two-monitor matrix, all 9 GUI scripts: no issues. |

Why the earlier two-monitor runs passed: R1 shows only when the console of the tool is a real minimized window; the earlier audit runs started the tools with a hidden console, and the matrix was changed to start them the way the launchers do after those runs.

## Not covered

As before (see [REMAINING-TESTS.md](REMAINING-TESTS.md)): the Automation repair and install tasks on the running Windows (`Run-Regression.ps1 -Repairs / -Installs`, need a snapshot), WinFixKit apply-and-undo (`Run-FixUndoTest.cmd`, snapshot), AI Analyze with a real key, real Wi-Fi / Bluetooth, the main monitor at real 150 % / 200 % (sign-out). The offline repair tasks did run for real in Hiren's PE 10 and PE 11.
