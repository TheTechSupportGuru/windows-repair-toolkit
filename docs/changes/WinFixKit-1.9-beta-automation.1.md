# WinFixKit 1.9 beta-automation 1 (2026-11-21)

A beta of WinFixKit with an **Automation** tab: `beta/WinFixKit-beta-automation.ps1` and `beta/Launch-WinFixKit-beta-automation.bat`. The stable `tools/WinFixKit.ps1` is unchanged.

## What the Automation tab does
- **Queue:** up to 10 tasks, run one after another, each in its own window, which closes 15 s after the task ends.
- **The tasks are WinFixKit's own:**
  - every tab's status check (15);
  - every fix that needs no answer from you (50);
  - a system restore point.

  The fixes that ask for a folder or a computer name, and the "Open ..." buttons, stay on their tabs.
- **Presets:**
  - Health snapshot: 10 status checks, changes nothing.
  - Network repair: no restart needed.
  - Printing repair.
  - Windows Update repair.
  - Store and Start menu repair.
- **Results:**
  - **Status checks:** "STATUS SAVED"; the whole status is in the full output and the HTML report.
  - **Fixes:** "FIX RAN - no error messages", "FIX RAN - WITH ERROR MESSAGES" or "FIX FAILED", with " - RESTART NEEDED" when the fix says so. WinFixKit's fixes print free text, so the result says whether a fix ran to the end and whether it printed errors, not whether the problem is gone. To confirm, queue the tab's status check after the fix (the presets do).
- **Before it starts:** the start question lists what each fix that changes the PC will do (the same warning it shows when run by hand).
- **Like WinSuperTool:**
  - a summary pops up after each task (optional);
  - "Stop the queue if a task does not pass";
  - a final summary;
  - the HTML report.

  Everything is saved in `Desktop\WinFixKit\Task-Results`.
- **Requirements:** administrator rights and a running Windows (not WinPE).

## Ported from WinSuperTool: change it there first
- **The rule:** the engine (task windows, result rules, summaries, the queue, the HTML report) is WinSuperTool 1.9's code, copied word for word. Automation is changed in WinSuperTool first, then ported here (see CONTRIBUTING.md).
- **The port script:** `build/Port-AutomationToWinFixKit.ps1` rebuilds the `#region AUTOMATION` block from `tools/WinSuperTool.ps1` plus the WinFixKit parts in `build/automation-port/`. It stops if WinSuperTool changed in a way the port doesn't expect.
- **The check:** `tests/WinFixKitAutomation.Tests.ps1` (39 tests) checks:
  - that 27 ported functions, the task-window template and the restore point script still match WinSuperTool (one changed character in a ported function makes it fail; tried);
  - that nothing of WinFixKit outside the new region changed apart from the header, the title and one window set-up line;
  - the task list and presets;
  - that the code of every task parses;
  - the result rules.

## Found and fixed while building it
- **Every task would have failed to start.** A task's code includes WinFixKit's helper functions, which made it longer than Windows' 32 KB command-line limit. The code now goes into a `.ps1` file in Task-Results, and the window runs that file.
- **The Preset row lay on top of the HTML report option.** The tab was sized after its anchors were set. It's now built at its design size first.

## Tested (Windows 11 VM, 2 monitors, not admin)
- **Window regression:**
  - the resize audit at 6 sizes, every tab including Automation: no issues;
  - two monitors (move, maximize, span, monitor 2 off and on): no issues;
  - simulated 150 %: no issues;
  - captures of the Automation tab at the default and the smallest size: it scrolls instead of squeezing.
- **Task code:** all 66 tasks build code that parses.
- **Real runs:** three status checks (Overview, Network, Printer) ran for real in a separate PowerShell and read back as STATUS SAVED.
- **Results:** stand-in fixes gave FIX RAN, WITH ERROR MESSAGES + RESTART NEEDED, and FIX FAILED as expected.
- **Unit tests:** 402 / 402 pass (Suite, Toolkit, 1.9 features and the new WinFixKit Automation tests).
- **Not tested yet:**
  - a real queue run as administrator (the real fixes);
  - the per-task popups and final summary on screen;
  - the HTML report from this tool;
  - Windows 10;
  - Test Center doesn't run the new tests yet.
