# Test Center 1.0 beta 1 (2026-11-21)

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
- **WinSuperTool:** full regression, Live Monitor, Recovery scans, Automation, System Info buttons.
- **WinFixKit:** Check status as user and as admin; fixes that open their own window (changes the PC, asks first); apply-and-undo (test VM only).
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

- **Pack full results** zips the whole results folder (without the `_run` copy of the scripts) to `C:\Users\Public\wrt-testcenter-<date-time>-full.zip`, logs where it went, and shows it in Explorer. That zip contains the PC's name and logs, so send it only to whoever fixes the failures, never to GitHub.
- **Release:** `TestCenter-v1.0-beta.1.zip` holds Test Center, the tests, the `tools` of toolkit 1.9, `build\` and `LICENSE`. It's published as a pre-release, so the toolkit's latest release stays 1.9.

## Found and fixed during the beta test

| | Fixed |
|---|---|
| **The "Recovery console windows" test was not read-only** | It runs WinFixKit fixes for real: it removes KB5025221 if installed, re-registers all apps, and runs a DISM + SFC repair. It's now "Fixes that open their own window (CHANGES this PC)" on the WinFixKit tab, with a warning, and `-Run all` leaves it out. |
| **Results read from the wrong file** | Tests that write `progress.txt`, `<name>-summary.txt`, `results.csv` (System Info buttons) or `status-summary-*.csv` (WinFixKit status) are now read properly instead of from the console. |
| **CHECK for things that were fine** | Several kinds of line no longer count as problems:<br>- the transcript's record of errors the tests handled themselves (`PS>TerminatingError`);<br>- section headings;<br>- "errors in transcript: 0";<br>- each test's own deliberate failures (Automation's "winget missing" task, offline DISM run against the live C:);<br>- the PC's own log messages in WinFixKit status. |
| **CHECK didn't say why** | The line that caused it now comes first ("NEEDS A LOOK: ..."), in the log, the GitHub summary and the HTML report. |
| **Copy summary for GitHub sometimes copied nothing** | It now retries for 2 s when another program holds the clipboard. If it still can't, it says so and names the file to copy from. |
| **Toolkit unit test failed with the mouse pointer on monitor 2** | A centred window opens on the monitor with the pointer. The test compared it with the main monitor, which is probably also why it once failed on the Windows 10 PC. It now compares with the monitor the window is on, and passes with the pointer on either monitor. |

## Verified (Windows 11 VM, 2 monitors)

- **Every Test Center feature that needs no admin rights:** 38 / 38 with `tests/Run-TestCenterGui.ps1`, which drives the real window:
  - tabs, Tick all / Untick all, and the empty-selection warning;
  - empty and partial tools folders;
  - Online mode: version list, download, the replace question, and edit detection;
  - a run and Stop, and the report files;
  - Copy summary for GitHub, Export HTML (through the Save dialog) and Open results;
  - no PC or user names in the exports.
- **Every test that needs only a UAC prompt**, run through Test Center as administrator (`-Run all`), 17 tests in 1 h 54 min:
  - unit tests 288 / 21 / 54 PASSED;
  - window sizes, two monitors and drag OK;
  - every tool started as admin OK;
  - Live Monitor 33 / 33, the Recovery scans, the System Info buttons (48 PASS) and the field test OK;
  - Automation, WinFixKit status and log collection OK once the result reading above was fixed.
- **The full regression shows CHECK for one real finding:** "Create a system restore point" fails because System Restore is switched off on the test VM. WinSuperTool says "Restore point FAILED: ... the service cannot be started because it is disabled". The report is correct, but the next toolkit version could say it in plainer words ("System Restore is turned off on this PC").
- **Online mode was also checked from scripts:**
  - an older release (v1.8.3) was downloaded and run: its Toolkit and 1.9-feature tests fail as expected;
  - a local edit was detected;
  - scripted runs (`-ToolsFolder`, `-Run`, `-ExitWhenDone`) work.
- **Not tested:**
  - the tests that need a sign-out (150 % / 200 % scaling), a VM snapshot (WinFixKit apply-and-undo) or WinPE;
  - "Report on GitHub" (it only opens the issue page);
  - "Pack full results".
