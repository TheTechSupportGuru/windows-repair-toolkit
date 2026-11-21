# Test Center 1.0 (2026-11-21)

A new tool, `tests/TestCenter.ps1` (start it with `tests/Start-TestCenter.bat`). It gathers every test that is run regularly into one window: a tab per tool and a tick box per test. It has its own version number and is updated only when the test procedures change or a test script is fixed.

- **Tabs:**
  - Whole toolkit: the unit tests, window sizes, two-monitor move/unplug and drag, the admin start of every tool, real 150 % / 200 % scaling;
  - WinSuperTool: full regression, Live Monitor, Recovery scans, Automation, System Info buttons, Recovery console windows;
  - WinFixKit: Check status as user and as admin, apply-and-undo (test VM only);
  - Log tools: log collection and the AI log readers;
  - Other PCs / WinPE: field test, Hiren's PE test.
- **Running the tests:**
  - The tests run one after the other, each in its own minimized PowerShell window.
  - Tests marked [admin] ask for elevation; "Restart as administrator" gets you a single prompt.
  - Tests that change the PC, or sign you out, ask first. The scaling test always runs last.
  - A test that can't run on the PC is greyed out with the reason (too few monitors, not in WinPE, needs a running Windows).
- **Results:** `C:\Users\Public\wrt-testcenter-<date-time>\<test>\` (on X: in WinPE). Each test gets a transcript (`console.txt`), and the whole run gets `report.txt`. Pester tests report PASSED / FAILED with their counts.
- **Release:** `TestCenter-v1.0.zip` holds the `tests` folder and the `tools` folder of the release it is attached to, plus `Start-TestCenter.bat`.

Verified: all 20 test definitions parse and match their scripts' parameters. The Toolkit unit tests were run through Test Center's own command builder (21 / 21 pass). The window was checked by PrintWindow on the VM (2 monitors, not admin).
