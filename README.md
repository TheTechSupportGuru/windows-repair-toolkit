# Windows Repair Toolkit

A set of PowerShell tools for repairing and troubleshooting Windows 10/11 PCs, including from WinPE (Hiren's BootCD PE 10 and 11). Each tool is one `.ps1` file with a WinForms window. They need no extra libraries.

> [!WARNING]
> These scripts were written with AI. They have been tested on Windows 11, Windows 10 64-bit (MBR disk), and Hiren's BootCD PE 10 and 11, all in VMs. They have not been tested on many real PCs. Several tools change the boot configuration (BCD), the registry, services and network settings. **Use at your own risk.** Try them on a test machine first.

**Current version: 1.9** (2026-11-21). Every version is a git tag (`v1.1` to `v1.9`), so `git diff v1.8.3 v1.9` shows exactly what changed. Licensed under the [GNU GPL v3.0](#license).

## Download

Get a single tool from the [latest release](../../releases/latest). Each tool has its own zip (for example `WinSuperTool-v1.9.zip`) with the script, its launcher, a short read-me and the license. **Source code** contains everything. Every older version is on the [releases page](../../releases) too.

**Don't want AI?** `WinSuperTool-NoAI-v1.9.zip` is WinSuperTool without the AI Analyze tab:
- no phone login and no network listener;
- nothing is ever sent to Claude or Gemini;
- everything else is the same.

Windows marks downloaded files as blocked: right-click the zip > **Properties** > tick **Unblock** before extracting.

## New in 1.9

The 1.9 beta is now the stable WinSuperTool ([what changed in 1.9](docs/changes/V1.9.md)):

- **Recovery tab:** a **pass / fail summary** when sfc, DISM, chkdsk, bcdboot, bootrec or a driver tool finishes, for example **NO CORRUPTION DETECTED**, **CORRUPTION DETECTED - FIX WORKED** or **FIX DID NOT WORK**, quoting the tool's own message. Live log windows per task, and scan-only checks (`sfc /verifyonly`, DISM check / scan health).
- **System Info tab:** saved **Wi-Fi networks and passwords**; **Windows version**, product keys and activation; every **network connection**; **Bluetooth** devices; **video cards and every display** (resolution, scaling, position); **audio** with the defaults marked. Copy all / Save as..., and buttons for 42 built-in Windows tools.
- **Automation tab:** up to **10 tasks** in a row (restore point, SFC, DISM, chkdsk, Windows Update, `winget upgrade --all`, Defender), **"repair only if needed"**, a pass / fail pop-up per task, a final summary and an **HTML report**. Presets such as "Health check" and "Full maintenance".
- **Automation in WinPE:** the queue repairs the Windows that does not start (SFC, DISM, chkdsk, and **Check disk and REPAIR** `chkdsk /f`), tested in Hiren's BootCD PE 10 and PE 11.
- **All tools:** windows that fit every screen from 720p to 4K, at any scaling, on one or two monitors, also when the screen changes while a tool is open; WinPE fixes (PowerShell 7 only, offline Windows protected in WinFixKit).

If something gets a result wrong, please open a [bug report](../../issues/new?template=1-bug-report.yml), choose version **1.9**, and attach the saved output from `WinSuperTool-Data\Task-Results`.
## Bugs, ideas and questions

- **Something broken?** Open a [bug report](../../issues/new?template=1-bug-report.yml).
- **A specific change you want?** Open a [feature request](../../issues/new?template=2-feature-request.yml).
- **An idea to talk through?** Start a discussion in [Ideas](../../discussions/new?category=ideas).
- **A how-to question?** Ask in [Q&A](../../discussions/new?category=q-a).
- **A pull request?** Read [CONTRIBUTING.md](CONTRIBUTING.md) first. Code may only use the runtimes built into the supported systems (Windows 11, Windows 10 64-bit, and Hiren's BootCD PE 10 and 11): Windows PowerShell 5.1 (PowerShell 7 in PE 10), .NET / WinForms and cmd. Any program that comes with Windows is fine; other runtimes, modules and third-party tools are not.

Each form asks which tool and which part of it (tab or section) you mean, so reports reach the right place. Before posting logs or screenshots, remove your PC name, user name, IP addresses and any API key.

## The tools

All scripts are in [`tools/`](tools/). Start each one with its launcher, or right-click it and choose **Run with PowerShell**. Each tool asks for administrator rights itself.

| Tool | Launcher | What it is for |
|---|---|---|
| [WinSuperTool](#winsupertool) | `WinSuperTool.bat` | The all-in-one tool: logs, live monitor, AI analysis, mount, Safe Mode, Sysprep, unattend, boot repair, system info, automation |
| WinSuperTool no-AI edition | `WinSuperTool-NoAI.bat` | The same tool without the AI Analyze tab: no phone login, nothing sent to an AI service, no network listener |
| [WinFixKit](#winfixkit) | `Launch-WinFixKit.bat` | Troubleshooters for Windows Update, network, printers, audio, Store apps and more, with undo |
| [WinRepairTool](#winrepairtool) | (right-click > Run with PowerShell) | A smaller boot and deployment toolkit: mount, Safe Mode, Sysprep, boot repair |
| [Collect-Logs](#collect-logs) | (right-click > Run with PowerShell) | Copies all the useful Windows logs to a folder on the Desktop |
| [Monitor-Logs](#monitor-logs) | (right-click > Run with PowerShell) | Opens live-updating windows for chosen logs and Event Viewer channels |
| [ClaudeLogAnalyzer](#claudeloganalyzer) | `Start-ClaudeLogAnalyzer.bat` | Sends logs and screenshots to Claude or Gemini and shows the diagnosis |
| Run-PS-As-Admin | `Run-PS-As-Admin.bat` | Drag any `.ps1` onto it to run it as administrator (unchanged since v1.1) |

WinSuperTool contains the features of WinRepairTool, Collect-Logs, Monitor-Logs and ClaudeLogAnalyzer. The separate tools are kept for when you need only one job, and since v1.8 they have the same fixes.

### WinSuperTool

`WinSuperTool.ps1` + `WinSuperTool.bat`. Runs on Windows 10/11 and in WinPE. A **target Windows** bar at the top picks which Windows installation the tabs work on. If there is more than one, it warns you and never picks one for you.

| Tab | What it does |
|---|---|
| Collect Logs | Copies Windows Update, DISM/CBS, Event Viewer, crash, setup/upgrade and system-info logs. Works on the running Windows or on an offline install (WinPE or a second drive). |
| Live Monitor | Opens one window per log that follows new lines, plus live Event Viewer channels and folder watchers. |
| AI Analyze | Sends logs and screenshots to Claude or Gemini. You log in by scanning a QR code with your phone. The API key is encrypted with a one-time pad and kept in memory only, for 1 hour. |
| Mount | Mounts and unmounts partitions with diskpart or the Storage cmdlets. Only allows non-destructive commands, and remembers mounts between runs. |
| Safe Mode | Sets Safe Mode (minimal) on the boot entry, or adds a separate Safe Mode entry to the boot menu. |
| Sysprep | Generalize (optionally `/mode:vm`), audit mode or OOBE, with optional pre-flight checks and an answer file. |
| Unattend | Builds, previews, saves and deploys `unattend.xml` from checkboxes. |
| Recovery | Experimental boot-repair tools (bcdboot, bootrec, sfc, DISM, chkdsk, driver tools), with a pass / fail summary and live log windows per task. |
| System Info | Wi-Fi passwords, Windows version and keys, network, Bluetooth, video and displays, audio; buttons for 42 built-in Windows tools. |
| Automation | A queue of up to 10 tasks with "repair only if needed", summaries and an HTML report. In WinPE it works on the offline Windows. |

Every BCD change is backed up first. Mount memory, BCD backups and the activity log are kept in `WinSuperTool-Data` next to the script.

**No-AI edition:** `WinSuperTool-NoAI.ps1` + `WinSuperTool-NoAI.bat` has the same tabs without AI Analyze. It contains no code that contacts an AI service or listens on the network. Its tabs are numbered 1-9. It is generated from `WinSuperTool.ps1` by [`build/Build-NoAIEdition.ps1`](build/Build-NoAIEdition.ps1), which checks that result.

### WinFixKit

`WinFixKit.ps1` + `Launch-WinFixKit.bat`. A replacement for the troubleshooters Microsoft retired. One tab per area:

Overview, Windows Update, Files and Folders, Start Menu, Microsoft Account, Store Apps, Printer, Printer Share Fixes, Network, Audio, Hardware and Devices, Power, Search and Indexing, Network Sharing, SMB 24H2 Fix, plus a **Service Killer** and a **Registry Backups** tab.

On every tab:
- **Check status** shows the current state and changes nothing. It works without admin rights.
- **Fix buttons** take a snapshot before, run the fix, then take a snapshot after.
- **"?" buttons** explain what a fix does, which commands it runs and the risks.

The registry is backed up before each fix, with one-click restore. Folders are renamed instead of deleted where possible, so fixes can be undone. Logs, reports and backups go to `Desktop\WinFixKit`.

### WinRepairTool

`WinRepairTool-startup.ps1`. The older, smaller version of WinSuperTool's boot and deployment tabs. Runs on Windows 11 and in WinPE.

| Tab | What it does |
|---|---|
| Mount | Mount and unmount partitions (diskpart or Storage cmdlets, non-destructive commands only) |
| Safe Mode | Edit the boot entry, or create a separate Safe Mode entry in the boot menu |
| Sysprep | Fixed Sysprep commands, one at a time, optional `/mode:vm`, plus an unattend builder |
| Recovery | Experimental boot-repair tools |

### Collect-Logs

`Collect-Logs.ps1`. Copies Windows Update, DISM/CBS, Event Viewer, crash, setup and system-info logs to `<Desktop of the logged-in user>\logs`, with a summary file. Pick the categories, press Collect, and use **Stop** to cancel.

### Monitor-Logs

`Monitor-Logs.ps1`. Pick logs, press **Launch selected**, and each one opens in its own PowerShell window that shows new lines as they are written. Event Viewer channels can be followed live and filtered by event ID, and folders can be watched for new files.

### ClaudeLogAnalyzer

`ClaudeLogAnalyzer.ps1` + `Start-ClaudeLogAnalyzer.bat`. Drag in logs and screenshots, ask a question, and get an analysis from **Claude** (Anthropic) or **Gemini** (Google, which has a free tier). Login uses the same phone QR pairing as WinSuperTool. The request runs in the background and can be cancelled. Big logs are read from the end, binary files are skipped, and large screenshots are scaled down.

## What has been fixed

Testing and code review led to **more than 100 fixes** across 13 versions. Each version's full list, with severity and how it was verified, is in [`docs/changes/`](docs/changes/).

Severity: **S1** = can make the PC unbootable, lose data or act on the wrong disk. **S2** = a serious bug. **S3** = wrong result or bad behaviour. **S4** = minor.

| Version | Main fixes | Details |
|---|---|---|
| **1.2** | **S1:** WinFixKit's "Take ownership" refused nothing, so it could be pointed at system folders; it now refuses Windows, Program Files, user profiles, drive roots and more. Mount memory lost every saved mount once there were 2. Remembered mounts could unmount another drive's letter. A failed BCD backup no longer lets the change go ahead. The Service Killer can no longer stop the firewall or services that restart the PC. Boot entries and diskpart output are read in any Windows language. | [V1.2](docs/changes/V1.2.md) |
| **1.3** | Collect-Logs saved to the admin's Desktop instead of the logged-in user's. Paths with typographic apostrophes broke spawned windows. A device on the network could freeze the window through the QR pairing server. `bcdboot` now matches the PC's firmware and doesn't auto-pick USB sticks. Registry backups after a restore, BitLocker check in any language, unattend user names with `%`, launcher error messages. | [V1.3](docs/changes/V1.3.md) |
| **1.4** | **S1:** a failed BCD restore could leave the boot store unloaded; later BCD actions are now blocked until a restart, and offline stores are restored by a verified file copy. Mount refuses the Microsoft Reserved partition. Diskpart mounts were forgotten on restart. **A v1.2 regression blocked every BCD change in WinPE.** | [V1.4](docs/changes/V1.4.md) |
| **1.5** | WinFixKit: "Test access to a PC / NAS" reported FAILED even when sharing worked. "Rebuild search index" missed the Windows 11 SQLite index files. | [V1.5](docs/changes/V1.5.md) |
| **1.6** | WinFixKit: a successful registry restore showed a red error. The TCP/IP and Winsock resets now explain their results, including Bluetooth serial providers. | [V1.6](docs/changes/V1.6.md) |
| **1.7** | A logic and optimization pass from 4 code reviews (85 findings, about 50 fixed, plus 9 bugs found by testing). WinFixKit: firewall rule profiles were rewritten, failed registry restores were marked as done, and power settings only worked in English. WinSuperTool: one bad file cancelled the whole AI request, recovery consoles could be broken by `&` in paths, dual-boot BCD entries were not found, Event Viewer export failures were hidden, and binary `.etl` files were sent to the AI as text. | [V1.7](docs/changes/V1.7.md) |
| **1.8** | The fixes ported to WinRepairTool, Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer and the launchers. WinRepairTool's Recovery tab now works on the running Windows. ClaudeLogAnalyzer no longer freezes for up to 3 minutes, and uses 2 MB instead of 359 MB of memory on a big log. Both boot tools offer to fix a boot-menu timeout of 0, which made the new Safe Mode entry impossible to pick. | [V1.8](docs/changes/V1.8.md) |
| **1.8.1** | **All tools:** text was blurry or cut off on 125 / 150 / 200 % displays (for example "Run a .ps1..."), and resizing the window left empty space or cut off the right-hand buttons. The tools now scale their own windows, lists and logs grow with the window, and small windows scroll. Also new: a splash screen, the GNU GPL v3.0 license, and a **no-AI edition** of WinSuperTool. Missing event logs are greyed out in the monitors, and the AI login no longer stops after an unrelated startup error. | [V1.8.1](docs/changes/V1.8.1.md) |
| **1.8.2** | Two layout fixes for scaled displays: windows opened partly off the screen, because WinForms centres them before they scale; and controls inside tabs could land in the wrong place or overlap, because a tab page is a 200 x 100 placeholder until its tab control exists. | [V1.8.2](docs/changes/V1.8.2.md) |
| **1.8.3** | **Hotfix:** in 1.8.1 and 1.8.2, Collect-Logs, Monitor-Logs, WinFixKit and ClaudeLogAnalyzer closed by themselves 1-2 seconds after starting. Closing the splash screen also ended the main window. The splash is now hidden instead, and closed together with the tool. | [V1.8.3](docs/changes/V1.8.3.md) |
| **1.9** | **WinSuperTool:** Recovery pass / fail summaries, new **System Info** and **Automation** tabs (also in WinPE on the offline Windows), HTML report. **All tools:** windows fit every screen and follow screen changes (two monitors, scaling, docking); in WinPE, WinFixKit now protects the offline Windows' system folders, and task windows work where only PowerShell 7 exists. | [V1.9](docs/changes/V1.9.md) |

### Still open

- **K16 / S12 / R10:** a few long jobs (registry save, Store app scans, diskpart) still run on the window's thread, so the window can pause briefly.
- **R14:** WinRepairTool keeps no permanent activity log (WinSuperTool does).

## Testing

Testing was done on a Windows 11 Pro VM (VirtualBox, UEFI, two monitors), with field tests on Windows 10 64-bit (MBR disk, Legacy BIOS) and in Hiren's BootCD PE 10 and PE 11. The plan and every result are in [`docs/testing/`](docs/testing/).

| Check | v1.9 result |
|---|---|
| Unit tests (Pester 3.4: [`Suite`](tests/Suite.Tests.ps1), [`Toolkit`](tests/Toolkit.Tests.ps1), [`Beta`](tests/Beta.Tests.ps1)) | 288 / 288, 24 / 24, 54 / 54 pass |
| Full regression as admin ([`tests/Run-Regression.ps1`](tests/Run-Regression.ps1)) | Live Monitor 33 / 33, summaries on real scans 4 / 4, Automation with real tasks, System Info buttons 49 / 49, admin checks 9 / 9 |
| Window sizes, 720p to 4K, 100 % / 150 %, two monitors, mouse drag ([`tests/Run-ResizeAudit.ps1`](tests/Run-ResizeAudit.ps1)) | no issues |
| WinPE (Hiren's BootCD PE 10 and 11, [`tests/Run-PETest.ps1`](tests/Run-PETest.ps1)) | all tools open; offline scans and Automation on the offline Windows correct |
| Full log collection | 400 files, 0 failed |
| GUI smoke test as admin | 5 tools open and close cleanly, 0 errors |
| PSScriptAnalyzer | 0 errors, 0 warnings |

Earlier phases also ran every WinFixKit fix and undo as admin, the network resets with reboots, and the WinSuperTool Mount, Safe Mode, Unattend and Recovery tabs.

**Not tested:** a physical PC, non-English Windows, a 32-bit host, real Wi-Fi / Bluetooth hardware, a live Claude or Gemini call. What is left and how to run it: [`docs/testing/REMAINING-TESTS.md`](docs/testing/REMAINING-TESTS.md).

### Test Center: run the tests yourself

**Test Center** ([`tests/TestCenter.ps1`](tests/TestCenter.ps1)) is one window for every test that is run regularly. It has a tab per tool (Whole toolkit, WinSuperTool, WinFixKit, Log tools, Other PCs / WinPE) with a tick box per test. Tick what you want and press **Run selected**. The tests then run one after the other.

- **What to test:**
  - **Offline:** any folder with the toolkit scripts, including **your own edited build**.
  - **Online:** pick a release, a beta or `main` from GitHub and download it into a folder. Test Center then shows which of the downloaded scripts you have edited since.
- **Reports:** results go to `C:\Users\Public\wrt-testcenter-<date>`, as an **HTML report** and a **Markdown summary for GitHub**. The summary contains the tools version, the edited files, Windows and PowerShell versions, a results table and the script hashes, with no PC or user names. **Copy summary for GitHub** and **Report on GitHub** make it easy to post.
- **Scripted runs:** `TestCenter.ps1 -ToolsFolder <dir> -Run unit-suite,unit-toolkit -ExitWhenDone`.
- **Greyed out:** a test that can't run on the PC or with the chosen tools, for example the two-monitor tests on one monitor. Tests that change the PC ask first.

Details: [`docs/changes/TestCenter-1.0-beta.1.md`](docs/changes/TestCenter-1.0-beta.1.md).

Download `TestCenter-v1.0-beta.1.zip` from the [Test Center pre-release](https://github.com/TheTechSupportGuru/windows-repair-toolkit/releases/tag/testcenter-v1.0-beta.1), extract it and double-click `Start-TestCenter.bat`. Start it as administrator to get only one admin prompt. Test Center has its own version number and is updated only when the test procedures or the test scripts change. When a test fails, **Pack full results** makes a zip with every log for whoever fixes it. That zip contains PC details, so don't post it publicly.

To run the unit tests (they read the scripts' code and run no GUI or system changes):

```powershell
Invoke-Pester .\tests\Suite.Tests.ps1
```

Other test files:
- **`tests\Toolkit.Tests.ps1`** (24 / 24 pass): checks for all tools since 1.8.1. It covers the license headers, display scaling, the splash screen, the no-AI edition (rebuilt and compared), the HTML report and the PowerShell used for task windows.
- **`tests\Beta.Tests.ps1`** (54 / 54 pass): the tests of the 1.9 features (written during the beta): task summaries, Automation incl. WinPE, System Info.
- **`tests\Run-MonitorLive.ps1`** (start it elevated): opens every Live Monitor window hidden and checks that each one works and follows new activity.

The other scripts in `tests/` are the admin and windowed test runs used on the VM. Some of them change system settings and expect the original project folder layout; read one before running it.

## Repository layout

```
tools/            the current scripts and launchers (v1.9), incl. the generated no-AI edition
beta/             beta test builds - none at the moment (1.9 beta 5 became 1.9)
build/            Build-NoAIEdition.ps1 (generates the no-AI edition), Promote-Beta.ps1 (makes a beta stable)
docs/changes/     what each version fixed (V1.2 ... V1.9, and the 1.9 betas)
docs/testing/     the test plan, results of each phase, and the v1.6 code review
tests/            Pester unit tests, Test Center (TestCenter.ps1), the test harness and the VM test runs
LICENSE           GNU General Public License v3.0
```

The scripts are pure ASCII on purpose: Windows PowerShell 5.1 reads files without a BOM as ANSI. Keep them that way when editing.

Never edit `WinSuperTool-NoAI.ps1` by hand. Change `WinSuperTool.ps1`, keep any new AI code inside `#region AI-ANALYZE` blocks (or end a single line with `# [AI]`), then run `.\build\Build-NoAIEdition.ps1`. For a beta, add `-Source beta\WinSuperTool.ps1`.

## License

Copyright (C) 2026 TheTechSupportGuru.

This project is free software, licensed under the **GNU General Public License, version 3 or (at your option) any later version** (`GPL-3.0-or-later`). See [`LICENSE`](LICENSE) for the full text.

What that means in practice:
- You may use, study, share and change these tools.
- If you distribute them, changed or not, you must do so under the same license and include the source.
- They come **without any warranty**.

<!-- Easter egg: update the numbers at every major release (see the "Hours" lines). -->
<br><br>
<details>
<summary><sub><sup>&pi;</sup></sub></summary>

### You found the time sheet

How long this project has taken, as of **1.9 and Test Center 1.0 beta 1** (November 2026). For 1.1 onwards, the AI hours are measured from the session logs and the human hours are an honest guess. The original scripts are estimated by the Claude project that wrote them, which had no stopwatch either.

| | Human | AI |
|---|---:|---:|
| Writing the original scripts in claude.ai, Nov 12-19 (the earlier Claude project's own estimate: Windows repair tool, WinFixKit, log collector and monitor, log analyzer) | ~8 h | ~6 h |
| 1.1 to 1.9 and Test Center: fixing, testing, more testing, releasing | ~14 h | ~11 h of actual thinking and typing, over ~20 h of wall clock |
| VMs grinding through test runs while everyone else made coffee | ~0 h | ~10 h of machine time, unsupervised |
| **Total** | **~22 h** | **~17 h** (plus a lot of patient VMs) |

**By the numbers**
- 174 messages from the human, 3,867 replies from the AI. The AI talks too much, and it knows.
- About 9,600 lines of tool code, 5,100 lines of tests, 1,800 lines of docs.
- 363 unit tests, 16 releases, 36 commits. More than 100 bugs fixed. One of them was a splash screen that closed the whole app.
- 3 operating systems, 2 monitors, 1 VM that got its display scaling changed more times than any VM should.
- Number of times the AI mixed up which side the second monitor is on: 1. The human remembers.
- Number of times a short PowerShell alias (`H`, `R`) secretly turned into `Get-History`: 2. It doesn't forget either.

*Updated at every major release. If the human column ever drops below the AI column, someone owes someone a coffee.*

</details>
