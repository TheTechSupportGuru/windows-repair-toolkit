# Windows Repair Toolkit

A set of PowerShell tools for repairing and troubleshooting Windows 10/11 PCs, including from WinPE (Hiren's BootCD PE 11). Each tool is one `.ps1` file with a WinForms window. They need no extra libraries.

> [!WARNING]
> These scripts were written with AI. They have been tested on one Windows 11 VM, but not extensively. Several tools change the boot configuration (BCD), the registry, services and network settings. **Use at your own risk.** Try them on a test machine first.

**Current version: 1.8** (2026-11-19). Every version is a git tag (`v1.1` to `v1.8`), so `git diff v1.7 v1.8` shows exactly what changed.

## Download

Get a single tool from the [latest release](../../releases/latest): each tool has its own zip (for example `WinSuperTool-v1.8.zip`) with the script, its launcher and a short read-me. **Source code** contains everything. Every older version is on the [releases page](../../releases) too.

Windows marks downloaded files as blocked: right-click the zip > **Properties** > tick **Unblock** before extracting.

## Beta: WinSuperTool 1.9 beta 1

> [!CAUTION]
> **Beta = test build.** It has had less testing than 1.8 and may get results wrong. Try it on a test machine, and keep using **1.8** for real repairs. Only WinSuperTool is in the beta; the other tools are unchanged.

The beta adds three things to WinSuperTool's **Recovery** tab:

- **A pass / fail summary.** When sfc, DISM, chkdsk, bcdboot, bootrec or a driver tool finishes, a window says whether the task **passed or failed**, and what it found, for example **NO CORRUPTION DETECTED**, **CORRUPTION DETECTED - FIX WORKED** or **FIX DID NOT WORK**. It quotes the tool's own message word for word.
- **Live log windows per task.** For example `CBS.log` for sfc, and `dism.log` for DISM.
- **Scan-only checks:** `sfc /verifyonly`, DISM **check health** and **scan health**.

Download **`WinSuperTool-v1.9-beta.1.zip`** from the [beta pre-release](../../releases/tag/v1.9-beta.1), or use [`beta/`](beta/). What changed and what was tested: [V1.9-beta.1](docs/changes/V1.9-beta.1.md). If the summary gets something wrong, please open a [bug report](../../issues/new?template=1-bug-report.yml), choose version **1.9 beta 1**, and attach the saved output from `WinSuperTool-Data\Task-Results`.

## Bugs, ideas and questions

- **Something broken?** Open a [bug report](../../issues/new?template=1-bug-report.yml).
- **A specific change you want?** Open a [feature request](../../issues/new?template=2-feature-request.yml).
- **An idea to talk through?** Start a discussion in [Ideas](../../discussions/new?category=ideas).
- **A how-to question?** Ask in [Q&A](../../discussions/new?category=q-a).

Each form asks which tool and which part of it (tab or section) you mean, so reports reach the right place. Before posting logs or screenshots, remove your PC name, user name, IP addresses and any API key.

## The tools

All scripts are in [`tools/`](tools/). Start each one with its launcher, or right-click it and choose **Run with PowerShell**. Each tool asks for administrator rights itself.

| Tool | Launcher | What it is for |
|---|---|---|
| [WinSuperTool](#winsupertool) | `WinSuperTool.bat` | The all-in-one tool: logs, live monitor, AI analysis, mount, Safe Mode, Sysprep, unattend, boot repair |
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
| Recovery | Experimental boot-repair tools (bcdboot, bootrec, sfc, DISM, chkdsk, driver tools). |

Every BCD change is backed up first. Mount memory, BCD backups and the activity log are kept in `WinSuperTool-Data` next to the script.

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

Testing and code review led to **more than 100 fixes** across 7 versions. Each version's full list, with severity and how it was verified, is in [`docs/changes/`](docs/changes/).

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

### Still open

- **K16 / S12 / R10:** a few long jobs (registry save, Store app scans, diskpart) still run on the window's thread, so the window can pause briefly.
- **R14:** WinRepairTool keeps no permanent activity log (WinSuperTool does).

## Testing

All testing was done on one Windows 11 Pro VM (VirtualBox, UEFI). The plan and every result are in [`docs/testing/`](docs/testing/).

| Check | v1.8 result |
|---|---|
| Unit tests (Pester 3.4, [`tests/Suite.Tests.ps1`](tests/Suite.Tests.ps1)) | 286 / 286 pass |
| Admin checks on the real system ([`tests/Run-V18-Verify.ps1`](tests/Run-V18-Verify.ps1)) | 9 / 9 pass |
| Full log collection | WinSuperTool: 351 files, 0 failed. Collect-Logs: 350 files, 0 failed |
| GUI smoke test as admin | 5 tools open and close cleanly, 0 errors |
| PSScriptAnalyzer | 0 errors, 0 warnings |

Earlier phases also ran every WinFixKit fix and undo as admin, the network resets with reboots, and the WinSuperTool Mount, Safe Mode, Unattend and Recovery tabs.

**Not tested:** real WinPE, a physical PC, BIOS/MBR, non-English Windows, a 32-bit host, a live Claude or Gemini call, and ClaudeLogAnalyzer's window.

To run the unit tests (they read the scripts' code and run no GUI or system changes):

```powershell
Invoke-Pester .\tests\Suite.Tests.ps1
```

The beta has its own unit tests (34 / 34 pass): `Invoke-Pester .\tests\Beta.Tests.ps1`.

The other scripts in `tests/` are the admin and windowed test runs used on the VM. Some of them change system settings and expect the original project folder layout; read one before running it.

## Repository layout

```
tools/            the current scripts and launchers (v1.8)
beta/             BETA test builds (now: WinSuperTool 1.9 beta 1) - not for real repairs yet
docs/changes/     what each version fixed (V1.2 ... V1.8, V1.9-beta.1)
docs/testing/     the test plan, results of each phase, and the v1.6 code review
tests/            Pester unit tests, the test harness and the VM test runs
```

The scripts are pure ASCII on purpose: Windows PowerShell 5.1 reads files without a BOM as ANSI. Keep them that way when editing.
