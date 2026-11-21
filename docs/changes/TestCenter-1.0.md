# Test Center 1.0 (2026-11-21)

A new tool, `tests/TestCenter.ps1` (start it with `tests/Start-TestCenter.bat`). It gathers every test that is run regularly into one window: a tab per tool and a tick box per test. Anyone can run the regression on a release, or on their own edited build. Test Center has its own version number and is updated only when the test procedures change or a test script is fixed.

## Choosing the tools to test
- **Offline mode:** use any folder with the toolkit scripts (Browse...). It can be a release, a clone, or your own edited copy.
- **Online mode:**
  - **Get version list** reads the releases from GitHub: every release, every beta, and `main` (newest code, maybe unreleased).
  - **Download** puts the chosen version into a folder of your choice and selects its `tools` folder.
  - Test Center records the downloaded scripts' hashes. Later it shows **which scripts you edited** ("GitHub v1.9 + local edits (edited: WinFixKit.ps1)").
- Each run works on a copy, in `<results>\_run`, of the tests and the chosen tools (plus `build\` and `LICENSE`), so the chosen folder is never changed.
- The detected version and the number of scripts are shown. A test whose tool is missing from the folder is greyed out with the reason. So are tests that can't run on this PC (too few monitors, not in WinPE).

## Tests (tabs)
- **Whole toolkit:** the unit tests (Suite, Toolkit, 1.9 features), window sizes, two-monitor move/unplug and drag, starting every tool as admin, real 150 % / 200 % scaling.
- **WinSuperTool:** full regression, Live Monitor, Recovery scans, Automation, System Info buttons, Recovery console windows.
- **WinFixKit:** Check status as user and as admin; apply-and-undo (test VM only).
- **Log tools:** log collection and the AI log readers.
- **Other PCs / WinPE:** field test, Hiren's PE test.

## Running
- Tests run one after the other, each in its own minimized PowerShell window.
- Tests marked [admin] ask for elevation; "Restart as administrator" gives you a single prompt.
- Tests that change the PC, or sign you out, ask first. The scaling test always runs last.
- **Scripted runs:** `TestCenter.ps1 -ToolsFolder <dir> -Run unit-suite,unit-toolkit,sizes -ExitWhenDone`. `-Run all` runs every test that can run on this PC and doesn't ask a question.

## Results and reports
- Results go to `C:\Users\Public\wrt-testcenter-<date-time>\` (on X: in WinPE). Each test gets a folder with a transcript (`console.txt`) and a summary, and the run gets:
  - `report.txt`: the run log.
  - **`report.html`**: the results table, each test's summary, the environment, the tested scripts with their hashes (edited ones marked), and the run log. It's saved during the run, and **Export HTML...** saves a copy anywhere.
  - **`summary-for-github.md`**: a short Markdown summary for a GitHub issue or discussion. **Copy summary for GitHub** puts it on the clipboard, and **Report on GitHub** opens the issue forms. It contains the tools version and source, the edited files, Windows, the PowerShell version, the language, admin, the monitor sizes, a results table, details for failures, and the script hashes.
- The HTML and Markdown exports replace the PC name, user name, user profile path and run folder with placeholders.
- **Results:**
  - Pester tests: PASSED / FAILED, with the names of the failing tests.
  - Other tests:
    - **OK**: the summary has no failure words.
    - **CHECK**: words like "failed" or "error" were found, so read the summary.
    - **NO SUMMARY**: the test left no summary.
  - Tests without a summary.txt use the last lines they printed.

## Verified
- All 20 test definitions parse and match their scripts' parameters.
- Online:
  - the version list was read from GitHub;
  - v1.8.3 was downloaded;
  - an edit to WinFixKit.ps1 was detected.
- Scripted runs:
  - against the downloaded 1.8.3: the Toolkit and 1.9-feature tests FAIL as expected, since 1.8.3 lacks 1.9 features;
  - against 1.9: Toolkit 21 / 21 and 1.9 features 54 / 54 PASSED, and WinFixKit status as non-admin shows CHECK because of the access-denied sections.
- The exports contain no PC or user name.
- The window was checked by PrintWindow on the VM (2 monitors, not admin).
