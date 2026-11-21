# Test results: two monitors, real scaling, 8 cores (2026-11-20)

Plan: [TEST-PLAN-multimonitor.md](TEST-PLAN-multimonitor.md). Branch `resize-pass-2` (1.8.4 / 1.9 beta 5 drafts). All 9 GUI scripts: WinSuperTool, WinSuperTool-NoAI, WinFixKit, WinRepairTool, Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer, beta WinSuperTool, beta WinSuperTool-NoAI.

Test machine: 8 cores, 8 GB, a 3840x2160 main monitor and a 2560x1440 monitor. In the first run Windows had the 2K monitor arranged **above** the 4K one; it is physically to the **right**, so it was moved there and the retest ran with both arrangements. Both monitors at 100 % unless a step changes it.

**All 5 bugs found are fixed** (see the last column and the retest below).

## Summary

| Area | Result |
|---|---|
| Unit tests (3 suites in parallel, 70 s) | stable 286 / 286, toolkit 22 / 22, beta 48 / 48 |
| Window sizes, 100 % and simulated 150 % (9 tools in parallel, 60 s per run) | no issues |
| Two monitors, 100 % and simulated 150 % | no layout issues; **1 bug** in the 1.8.4 screen watcher (#M1) |
| Second monitor at real 150 % while the tool is open | no issues |
| Second monitor switched off and on while the tool is on it | no issues |
| Popups with the tool on the second monitor | **1 bug** (#M2) |
| System Info on two monitors | **1 bug** (#M3) |
| All 9 tools started at once | all stay open; **1 minor bug** (#M4) |
| HTML Automation report at 3840 / 2560 / 1280 / 390 px | fine down to 1280; **1 minor bug** at phone width (#M5) |

## Bugs found

| # | Sev | Where | Bug | Seen | Fixed |
|---|---|---|---|---|---|
| M1 | S3 | shared window helpers (1.8.4 draft, not released) | **A window across the edge of two monitors is pulled completely onto one of them.** The screen watcher treats "the window is now mostly on another monitor" like a screen change and moves the window inside that monitor. While you drag a window from one monitor to the other, it can also be moved away from under the mouse (once a second). | `mon:2` then `span`: the window ended at `y=0` fully on monitor 1, for every tool. Straight after `mon:1` it stayed across the edge, because the monitor did not change. | 1.8.4: a window is only moved when part of it is on no screen, and never while a mouse button is down. The audit now reports a window pulled off the edge: the old helper fails it, the new one passes. |
| M2 | S3 | beta Automation | **The per-task summary popups open on the main monitor**, not on the monitor the tool is on (`Screen.PrimaryScreen`). The report window and the modal task summary open correctly next to the tool. | Main window on monitor 2: the Automation summary appeared at 3042,1534 on monitor 1. | beta 5: placed on the main window's monitor. Retest: all three popups on monitor 2. |
| M3 | S3 | beta System Info > Video | **Only one display is shown.** `Win32_VideoController` reports the resolution of the main monitor only (3840 x 2160), and `WmiMonitorID` returns no monitors on this PC, so the 2K monitor does not appear at all. | Real output on the two-monitor VM. | beta 5: a new "Displays" part lists every display with resolution, refresh rate, scaling, position and monitor name. Checked with monitor 2 on the right, at 150 % and above. |
| M4 | S4 | shared window helpers | **The main window can open minimized** when its process was started with a minimized start style and the splash screen was not the active window at that moment. Then the main window is not owned by the splash, and Windows applies the start style to it. `WinSuperTool.bat` starts the tool with a minimized style. Not seen with a normal start (double-click, self-elevation, the other launchers). | Starting 4 tools at the same moment with a minimized style: Collect-Logs and Monitor-Logs opened minimized in 2 of 2 and 1 of 2 tries. Started one at a time: always normal (8 of 8). WinSuperTool: always normal. | 1.8.4: a hidden or minimized main window is shown normally when it appears. Retest: 6 tools started together, 3 rounds each with a minimized and a hidden start style: 36 of 36 normal. |
| M5 | S4 | beta HTML report | **At phone width (390 px) the page scrolls sideways**: the result banner, the subtitle and the Result column are cut off at the right edge. | Edge, 390 x 844. | beta 5: the table scrolls inside its own box; smaller spacing on narrow screens. Measured in Edge: the page is exactly as wide as the screen at 390 and 320 px (before: 32-102 px wider). |

## Details

### Window sizes (R1-R3)

`Run-ResizeAudit.ps1 -Parallel`, every tab at min, 1280x680, 1920x1040, 2560x1400, 3840x2060, 75 %, maximized: **no issues** at 100 % and at simulated 150 %. With `-Parallel` all 9 tools run at the same time: 60 s for a run that takes several minutes one at a time.

### Two monitors (M-tests)

Steps: monitor 2, smallest size and 75 % there, maximized there, back to monitor 1, across the edge, monitor 2 at 150 % (real Windows scaling, applied while the tool is open), sizes and maximize at 150 %, back to 100 %, monitor 2 switched off and on.

- **Monitor 2** (above the main monitor, negative coordinates): every tool lands there, fits, and its minimum size is right. Maximized: 2576x1408 on monitor 2.
- **Monitor 2 to 150 % while the tool is on it:** this app sees the 2K monitor as 1707x912 then. The window shrinks to fit (for example 1920x1044 to 1705x910) and maximizes correctly (1723x928). Back at 100 % the window can be enlarged again. Note: at 150 % the two monitors no longer touch in this app's coordinates (480 px gap); no tool had a problem with it.
- **Monitor 2 switched off** with the tool on it, also maximized: Windows moves the window to the main monitor, and it fits. Switched on again: the window goes back to monitor 2.
- **Across the edge:** no layout issues, but see #M1.
- The same at simulated 150 %: **no issues**.

### Popups (F-tests)

Main window on monitor 2: report window (`Show-Report`) on monitor 2; task summary (modal) on monitor 2; Automation task summary on **monitor 1** (#M2).

### Start (F1)

All 9 tools started at the same moment: all still open after 15 s, CPU at 12 %. Started without admin rights, the SuperTools and WinRepairTool show "diskpart.exe failed to run: The requested operation requires elevation". That is expected in this test only; the real tools ask for admin rights first.

### HTML report (F3)

A 10-task report with long output, rendered by Edge (video acceleration) at 3840, 2560, 1280 and 390 px: readable and colour-coded at 1280 and wider; #M5 at 390 px. Rendering took 0.9-2.1 s per width.

## Test tool changes

`tests/Run-ResizeAudit.ps1`:
- New screen words: `mon:N`, `maxon:N`, `span`, `dpi2:NNN` / `dpi2:back`, `solo` / `extend`. Every screen change is checked: the window is on a screen, fits it, and its title bar can be grabbed.
- `-Parallel`: all tools at once (size steps only).
- One result file per tool, merged at the end. One "settled" line per step.
- Monitor scaling, resolution and monitor 2 are always put back.
- Screenshots come from the tool's own window.
- Tools start with a normal start style, like the launchers (a hidden start style hid some tools' windows, see #M4).

## Retest after the fixes

| Run | Result |
|---|---|
| Unit tests (parallel) | stable 286 / 286, toolkit 22 / 22, beta 50 / 50 (2 new: display position wording, every display listed) |
| Sizes, 9 tools in parallel, 100 % and simulated 150 % | no issues |
| Two-monitor matrix, monitor 2 on the right, 100 % and simulated 150 % (incl. 150 % on monitor 2, switched off and on, 4 x across the edge) | no issues; every across-the-edge step stayed across the edge |
| The same with monitor 2 above, 100 % | no issues |
| Popups with the tool on monitor 2 | all on monitor 2 |
| Start with a minimized / hidden start style, 6 tools at once | 36 / 36 normal |

## Not tested here (needs you at the VM)

P1-P5 in the plan: the **main** monitor at 150 % / 200 % (needs signing out), dragging with the mouse (#M1 will show there), how the stretched text looks on the 150 % monitor, and an Automation run as administrator.
