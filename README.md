# Windows Repair Toolkit

A set of PowerShell tools for repairing and troubleshooting Windows 10/11 PCs, including from WinPE (Hiren's BootCD PE 10 and 11). Each tool is one `.ps1` file with a WinForms window. They need no extra libraries.

> [!WARNING]
> These scripts were written with AI. They have been tested on Windows 11, Windows 10 64-bit (MBR disk), and Hiren's BootCD PE 10 and 11, all in VMs. They have not been tested on many real PCs. Several tools change the boot configuration (BCD), the registry, services and network settings. **Use at your own risk.** Try them on a test machine first.

**Current version: 2.8** (2026-11-27). Every version is a git tag (`v1.1` to `v2.8`), so `git diff v2.7 v2.8` shows exactly what changed. Licensed under the [GNU GPL v3.0](#license).

<details open>
<summary><h2 id="download">Download</h2></summary>


Get the tools from the [latest release](../../releases/latest). The main downloads are **WinSuperTool**, **WinSuperTool-NoAI**, **WinFixKit**, **Backup Script Builder** and **7z-Encryptor**, each its own zip with the script, its launcher, a short read-me and the license. The smaller separate tools (WinRepairTool, Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer) are all in **`IndividualTools-v2.8.zip`**, started with its `Run-PS-As-Admin.bat`; each of them is also part of WinSuperTool. **Test Center** (run the tests yourself) is there too. **Source code** contains everything.

**Don't want AI?** `WinSuperTool-NoAI-v2.8.zip` is WinSuperTool without the AI Analyze tab:
- no phone login and no network listener;
- nothing is ever sent to Claude or Gemini;
- everything else is the same.

Windows marks downloaded files as blocked: right-click the zip > **Properties** > tick **Unblock** before extracting.


</details>

<details open>
<summary><h2 id="new-in-2-8">New in 2.8</h2></summary>

**Drag and drop everywhere** ([V2.8](docs/changes/V2.8.md)): every box that takes a file or folder name also takes one dragged from Explorer.

- **WinSuperTool 2.1:** the Collect Logs folder and the Run a script box.
- **WinFixKit 2.2:** the Registry changes ISO / image box and the key backup folder.
- **Backup Script Builder 2.0:** the Source folders list, the Schedule Task script box and the FreeFileSync.exe box ([notes](docs/changes/BackupScriptBuilder-2.0.md)).
- **7z-Encryptor 1.8:** the Save as box ([notes](docs/changes/7z-Encryptor-1.8.md)).

Tested on Windows 11: 571 / 571 Pester tests, 134 / 134 Backup Script Builder checks, 115 / 115 7z-Encryptor checks. Drops are tested through each box's drop code, not dragged by hand; not yet run in Hiren's PE.

</details>

<details>
<summary><h2 id="beta-diagnostic-tool-downloader">Beta side tool: Diagnostic Tool Downloader 0.1 beta 1</h2></summary>

`DiagDownloader-v0.1-beta.1.zip` (in the latest release, under "Betas and pre-releases"). Not part of WinSuperTool yet, and it does not change the toolkit version ([notes](docs/changes/DiagDownloader-0.1-beta.1.md)).

- Downloads the common diagnostic tools (49 entries) into a folder you pick: tick tools in the window (`DiagDownloader.bat`), or use `Get-DiagTools.ps1` with `-List`, `-Only`, `-OutDir`, `-Force`.
- Handles direct links, GitHub releases, vendor pages that link to the real file, and Microsoft diagcab / exe pages. Manual-only entries are greyed out; double-click to open their page.
- **Nothing is run** - downloads only. Check each file yourself before running it. There is no hash check yet.
- Last full run: 40 OK, 4 manual, 5 failed (Sophos Scan and Clean, HWiNFO, WizTree, OpenNetMeter, Wireshark). Pages that need JavaScript or a sign-in fail.

</details>

<details>
<summary><h2 id="new-in-2-7">New in 2.7</h2></summary>

**7z-Encryptor 1.7** ([V2.7](docs/changes/V2.7.md), [notes](docs/changes/7z-Encryptor-1.7.md)):

- **mailto: waits for Windows' "pick an app" prompt** instead of closing it, and works before anything is encrypted.
- **Change Default: mailto: / Email** buttons next to Send by email, each asking first.
- **Attach (Send to)** and **Choose program:** with a list of the mail programs found on the PC (Outlook classic, Thunderbird, the new Outlook, others), plus Other.... The Windows Share option is gone.
- **Save as: File or Folder: Named + Date** (for example Encrypted-11-27-26--14-05.7z, a second one in the same minute gets (2)).
- **A cleaner window** with five numbered sections, and simpler ? help with bold titles.

</details>

<details>
<summary><h2 id="new-in-2-6">New in 2.6</h2></summary>

Fixes from the Hiren's BootCD PE 10 / 11 regression test of 2.5 ([V2.6](docs/changes/V2.6.md)):

- **Backup Script Builder 1.9:** a saved script for a zip made by **Windows (built in)** uses Windows' own .NET zip, the same as Back up now, so it works in Windows PE too (2.5 used `tar.exe`, which Windows PE does not have). A saved `.bat` finds PowerShell 7 in Hiren's PE 10. The Schedule Task tab is greyed out in Windows PE, which has no Task Scheduler ([notes](docs/changes/BackupScriptBuilder-1.9.md)).
- **Every launcher works in Hiren's PE 10:** when there is no Windows PowerShell, the `.bat` files use PowerShell 7 (`pwsh.exe`, on the PATH or on X: / Y:).
- **7z-Encryptor 1.6:** when 7-Zip skips files, the message shows 7-Zip's own warnings with the file names ([notes](docs/changes/7z-Encryptor-1.6.md)).
- **Test Center 1.1:** the WinPE test also covers Backup Script Builder, 7z-Encryptor and Test Center, and the Test Center window test works in Windows PE ([notes](docs/changes/TestCenter-1.1.md)).

</details>

<details>
<summary><h2 id="new-in-2-5">New in 2.5</h2></summary>


- **Backup Script Builder 1.8: Ultra is 7-Zip only.** On the Manual Backup tab, a zip made by **Windows (built in)** offers Store and Normal; Ultra is greyed out as "Ultra (7-Zip only)". Windows' own zip has no real Ultra when backing up now, so the backup and the saved script make the same zip on Windows 10, 11 and PE ([1.8 notes](docs/changes/BackupScriptBuilder-1.8.md)).
- **Remember settings keeps zip or 7z.** With Remember settings ticked, 7z-Encryptor 1.5 remembers 7z or zip, and Backup Script Builder 1.8 remembers the Manual Backup type (folder, zip or 7z) and who makes the zip. On a PC without 7-Zip, Backup Script Builder falls back to a Windows zip but keeps the 7-Zip choice for the next PC.
- **Drag and drop from Explorer.** Drag files and folders onto Backup Script Builder's Manual Backup list or 7z-Encryptor's list. Drag a folder onto Backup Script Builder's Destination folder, Log folder or Save to box (a file puts in its folder).
- **Test Center 1.0, out of beta:** it covers everything above ([notes](docs/changes/TestCenter-1.0.md)).
- **7-Zip found in Windows PE.** In Windows PE (Hiren's BootCD PE 10 / 11 and others) the tools also look for 7-Zip on the X: and Y: drives, up to 3 folders deep, and in the PATH (Backup Script Builder 1.8, 7z-Encryptor 1.5, [V2.5](docs/changes/V2.5.md)).


</details>

<details>
<summary><h2 id="new-in-2-4">New in 2.4</h2></summary>


- **7z-Encryptor 1.4: one window for both ways of starting.** Files dropped on `7z-Encryptor.bat` open the normal window with them in the list, so the file picker and Save as with Browse... are there too. They are saved next to the first dropped item. Dropping the script on its own launcher just starts it.
- **Email with mailto:** type an address and your default mail program opens a new email to it (drag in the file, which is selected in Explorer).
- **Fixes:** names with `&` or `^` dropped on the launcher arrive whole; the two passwords must match exactly (case too); saving inside a folder that is being encrypted is refused. Every **?** button explains the 1.4 window, with new ones for Password and Remember settings ([1.4 notes](docs/changes/7z-Encryptor-1.4.md), [V2.4](docs/changes/V2.4.md)).
- **Test Center 1.0 beta 4:** new edge-case unit tests for 7z-Encryptor on its own tab ([notes](docs/changes/TestCenter-1.0-beta.4.md)).


</details>

<details>
<summary><h2 id="new-in-2-3">New in 2.3</h2></summary>


- **Remember settings is now a choice, off at first.** 7z-Encryptor 1.3 and Backup Script Builder 1.7 have a **Remember settings** box. Until you tick it, nothing is written. Unticking it deletes the settings file. A damaged settings file (bad JSON, wrong values, or a 2.2 file without the new Remember flag) is ignored, and the tool starts with no memory ([V2.3](docs/changes/V2.3.md)).


</details>

<details>
<summary><h2 id="new-in-2-2">New in 2.2</h2></summary>


- **7z-Encryptor 1.2:** after encrypting, **Show in folder** and **Send by email**. Email with (your choice is remembered): **Send to > Mail recipient** (the classic Windows way, for Outlook classic, Thunderbird and other classic mail programs; if there is none, it falls back to the Windows Share window), **Windows Share** (the Windows 10 / 11 Share window), or **Choose program...** (a mail program you pick). The folder of the last encrypted file and the drop window's "save next to" tick are remembered too ([1.2 notes](docs/changes/7z-Encryptor-1.2.md)).
- **Backup Script Builder 1.6:** the **Destination folder** (Build Script) and **Save to** (Manual Backup) are remembered between runs ([1.6 notes](docs/changes/BackupScriptBuilder-1.6.md)).
- **Portable settings:** each tool keeps them in a small `<tool>.settings.json` **next to its script**, so a USB stick, WinPE kit or network share keeps its settings on every PC. Only folders and choices are kept, never a password ([V2.2](docs/changes/V2.2.md)).


</details>

<details>
<summary><h2 id="new-in-2-1">New in 2.1</h2></summary>


- **WinFixKit now has the Automation and Registry changes tabs** from the beta (beta-automation 3), and the separate beta is retired: the WinFixKit zip is the only WinFixKit. The two new tabs say **(beta)** on the tab and at the top of the tab, because they are newer than the rest of WinFixKit; every other tab is the same as in 2.0 ([what changed in 2.1](docs/changes/V2.1.md)).
  - **Automation (beta):** a queue of up to 10 of WinFixKit's status checks and fixes, run one after another, each in its own window with a pass / fail result, then a summary and an HTML report. Needs administrator rights and a running Windows.
  - **Registry changes (beta):** registry keys changed since a date, compared with a shadow copy / restore point, WinFixKit's own backups, a Windows ISO or a built-in list of Windows defaults. Tick only the values to revert; each key is backed up as a `.reg` file first. Scanning changes nothing.
- The other tools are the same as in 2.0.


</details>

<details>
<summary><h2 id="new-in-2-0">New in 2.0</h2></summary>


The first major version: the whole toolkit went through a regression and edge-case pass ([what changed in 2.0](docs/changes/V2.0.md)).
- **Folders with `[ ]` in the name** (`C:\Tools [2026]`, `D:\Logs [PC1]`) now work everywhere. Before, PowerShell read the brackets as a wildcard, so WinSuperTool and WinRepairTool lost their remembered mounts, log collection lost its summary files, WinFixKit lost its log and reports, and Backup Script Builder could overwrite an existing FreeFileSync job without asking.
- **Backup Script Builder 1.5** and **7z-Encryptor 1.1:** a zip password with non-English letters is refused with a clear message, instead of 7-Zip failing with "The parameter is incorrect" ([1.5 notes](docs/changes/BackupScriptBuilder-1.5.md), [1.1 notes](docs/changes/7z-Encryptor-1.1.md)).
- Every tool now says `Version 2.0` (Backup Script Builder 1.5, 7z-Encryptor 1.1), the release has a 7z-Encryptor zip built from the tag, and the bug and discussion forms list 7z-Encryptor.


</details>

<details>
<summary><h2 id="new-in-1-9-2">New in 1.9.2</h2></summary>


- **7z-Encryptor 1.0**, a new tool: encrypt files and folders with 7-Zip and a password (7z with hidden file names, or zip), from a window or by dropping them on its `.bat`; installs and updates 7-Zip with winget (see [below](#7z-encryptor), [notes](docs/changes/7z-Encryptor-1.0.md)).
- **Backup Script Builder 1.4:** **Update 7-Zip** (winget) next to Install, and corrected help texts ([notes](docs/changes/BackupScriptBuilder-1.4.md)). 1.3: a new **Manual Backup** tab (back up now to a folder, a zip made by Windows or 7-Zip, or a 7z / self-extracting .exe, with Store / Normal / Ultra and an optional password, saved as a .bat / .ps1 if you like, and a one-click 7-Zip install), network folders and files (`\\server\share`) as source or destination, and Robocopy and Xcopy scripts can back up single files as well as folders ([notes](docs/changes/BackupScriptBuilder-1.3.md)). 1.2: the folder picker no longer lists the user folder's junctions as empty extra folders, opens at Users, hides Windows and program folders until you ask for them, and never adds a folder twice ([notes](docs/changes/BackupScriptBuilder-1.2.md)). 1.1 added Robocopy and Xcopy scripts besides FreeFileSync ([1.1 notes](docs/changes/BackupScriptBuilder-1.1.md)).
- **Fewer downloads:** WinRepairTool, Collect-Logs, Monitor-Logs and ClaudeLogAnalyzer are now one zip, `IndividualTools-v1.9.2.zip`, with one shared launcher (`Run-PS-As-Admin.bat`: drag a `.ps1` onto it). `Start-ClaudeLogAnalyzer.bat` is gone. The tools themselves are unchanged ([V1.9.2](docs/changes/V1.9.2.md)).
- **Test Center 1.0 beta 3:** a new **Backup Script Builder** tab (script, schedules and layout checks, about 2 minutes, no admin), and a passing test line that mentions "missing" no longer shows CHECK ([notes](docs/changes/TestCenter-1.0-beta.3.md)).
- **Simpler bug and discussion forms:** WinSuperTool and its individual tools share one Tool entry, the tab / part is an optional text box, and the version list has 4 choices.


</details>

<details>
<summary><h2 id="new-in-1-9-1">New in 1.9.1</h2></summary>


- **Backup Script Builder 1.0**, a new tool for [FreeFileSync](https://freefilesync.org/) backups (see [below](#backup-script-builder)).
- **Betas to try** (in the latest release, under "Betas"): **WinFixKit with Automation and Registry changes tabs** (beta-automation 3: a queue of its status checks and fixes, each with a pass / fail result; and find registry changes since a date and revert only the ones you tick) and **Test Center beta 3**. The 8 tools are unchanged from 1.9 ([V1.9.1](docs/changes/V1.9.1.md)).


</details>

<details>
<summary><h2 id="new-in-1-9">New in 1.9</h2></summary>


The 1.9 beta is now the stable WinSuperTool ([what changed in 1.9](docs/changes/V1.9.md)):

- **Recovery tab:** a **pass / fail summary** when sfc, DISM, chkdsk, bcdboot, bootrec or a driver tool finishes, for example **NO CORRUPTION DETECTED**, **CORRUPTION DETECTED - FIX WORKED** or **FIX DID NOT WORK**, quoting the tool's own message. Live log windows per task, and scan-only checks (`sfc /verifyonly`, DISM check / scan health).
- **System Info tab:** saved **Wi-Fi networks and passwords**; **Windows version**, product keys and activation; every **network connection**; **Bluetooth** devices; **video cards and every display** (resolution, scaling, position); **audio** with the defaults marked. Copy all / Save as..., and buttons for 42 built-in Windows tools.
- **Automation tab:** up to **10 tasks** in a row (restore point, SFC, DISM, chkdsk, Windows Update, `winget upgrade --all`, Defender), **"repair only if needed"**, a pass / fail pop-up per task, a final summary and an **HTML report**. Presets such as "Health check" and "Full maintenance".
- **Automation in WinPE:** the queue repairs the Windows that does not start (SFC, DISM, chkdsk, and **Check disk and REPAIR** `chkdsk /f`), tested in Hiren's BootCD PE 10 and PE 11.
- **All tools:** windows that fit every screen from 720p to 4K, at any scaling, on one or two monitors, also when the screen changes while a tool is open; WinPE fixes (PowerShell 7 only, offline Windows protected in WinFixKit).

If something gets a result wrong, please open a [bug report](../../issues/new?template=1-bug-report.yml), choose your version, and attach the saved output from `WinSuperTool-Data\Task-Results`.

</details>

<details open>
<summary><h2 id="bugs-ideas-and-questions">Bugs, ideas and questions</h2></summary>


- **Something broken?** Open a [bug report](../../issues/new?template=1-bug-report.yml).
- **A specific change you want?** Open a [feature request](../../issues/new?template=2-feature-request.yml).
- **An idea to talk through?** Start a discussion in [Ideas](../../discussions/new?category=ideas).
- **A how-to question?** Ask in [Q&A](../../discussions/new?category=q-a).
- **A pull request?** Read [CONTRIBUTING.md](CONTRIBUTING.md) first. Code may only use the runtimes built into the supported systems (Windows 11, Windows 10 64-bit, and Hiren's BootCD PE 10 and 11): Windows PowerShell 5.1 (PowerShell 7 in PE 10), .NET / WinForms and cmd. Any program that comes with Windows is fine; other runtimes, modules and third-party tools are not.

Each form asks which tool you mean (WinSuperTool and its individual tools share one entry) and, optionally, which tab or part. Before posting logs or screenshots, remove your PC name, user name, IP addresses and any API key.


</details>

<details open>
<summary><h2 id="the-tools">The tools</h2></summary>


All scripts are in [`tools/`](tools/). Start each one with its launcher, or right-click it and choose **Run with PowerShell**. Each tool asks for administrator rights itself.

| Tool | Launcher | What it is for |
|---|---|---|
| [WinSuperTool](#winsupertool) | `WinSuperTool.bat` | The all-in-one tool: logs, live monitor, AI analysis, mount, Safe Mode, Sysprep, unattend, boot repair, system info, automation |
| WinSuperTool no-AI edition | `WinSuperTool-NoAI.bat` | The same tool without the AI Analyze tab: no phone login, nothing sent to an AI service, no network listener |
| [WinFixKit](#winfixkit) | `Launch-WinFixKit.bat` | Troubleshooters for Windows Update, network, printers, audio, Store apps and more, with undo |
| [WinRepairTool](#winrepairtool) | (right-click > Run with PowerShell) | A smaller boot and deployment toolkit: mount, Safe Mode, Sysprep, boot repair |
| [Collect-Logs](#collect-logs) | (right-click > Run with PowerShell) | Copies all the useful Windows logs to a folder on the Desktop |
| [Monitor-Logs](#monitor-logs) | (right-click > Run with PowerShell) | Opens live-updating windows for chosen logs and Event Viewer channels |
| [ClaudeLogAnalyzer](#claudeloganalyzer) | (Run-PS-As-Admin.bat) | Sends logs and screenshots to Claude or Gemini and shows the diagnosis |
| [Backup Script Builder](#backup-script-builder) | `BackupScriptBuilder.bat` | Builds and schedules backup jobs for [FreeFileSync](https://freefilesync.org/), or Robocopy / Xcopy scripts: pick folders and a destination, set the schedule |
| [7z-Encryptor](#7z-encryptor) | `7z-Encryptor.bat` | Encrypts files and folders with 7-Zip and a password you pick: 7z (AES-256, names hidden too) or zip (standard or AES-256). Drop files on the `.bat` to start with them in the list. Needs [7-Zip](https://www.7-zip.org/) (it can install it with winget) |
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

Overview, Windows Update, Files and Folders, Start Menu, Microsoft Account, Store Apps, Printer, Printer Share Fixes, Network, Audio, Hardware and Devices, Power, Search and Indexing, Network Sharing, SMB 24H2 Fix, plus a **Service Killer**, a **Registry Backups**, an **Automation (beta)** and a **Registry changes (beta)** tab.

On every tab:
- **Check status** shows the current state and changes nothing. It works without admin rights.
- **Fix buttons** take a snapshot before, run the fix, then take a snapshot after.
- **"?" buttons** explain what a fix does, which commands it runs and the risks.

The registry is backed up before each fix, with one-click restore. Folders are renamed instead of deleted where possible, so fixes can be undone. Logs, reports and backups go to `Desktop\WinFixKit`.

**Automation (beta)** runs up to 10 status checks and fixes one after another, each in its own window with a pass / fail result, then a summary and an HTML report (administrator rights, not in WinPE). **Registry changes (beta)** finds registry keys changed since a date, shows what they were before (from a shadow copy, WinFixKit's backups, a Windows ISO or a built-in defaults list) and reverts only the values you tick, each key backed up first. Both came from the WinFixKit beta-automation betas ([notes](docs/changes/WinFixKit-1.9-beta-automation.3.md)) and are still marked beta in the window. Since 2.1.

### Individual tools

WinRepairTool, Collect-Logs, Monitor-Logs and ClaudeLogAnalyzer are in `IndividualTools-v2.8.zip`. Each is also part of WinSuperTool, and is kept separate for when you need only one job. Start one by dragging its `.ps1` onto `Run-PS-As-Admin.bat`.

<details>
<summary>Show the individual tools</summary>

#### WinRepairTool

`WinRepairTool-startup.ps1`. The older, smaller version of WinSuperTool's boot and deployment tabs. Runs on Windows 11 and in WinPE.

| Tab | What it does |
|---|---|
| Mount | Mount and unmount partitions (diskpart or Storage cmdlets, non-destructive commands only) |
| Safe Mode | Edit the boot entry, or create a separate Safe Mode entry in the boot menu |
| Sysprep | Fixed Sysprep commands, one at a time, optional `/mode:vm`, plus an unattend builder |
| Recovery | Experimental boot-repair tools |

#### Collect-Logs

`Collect-Logs.ps1`. Copies Windows Update, DISM/CBS, Event Viewer, crash, setup and system-info logs to `<Desktop of the logged-in user>\logs`, with a summary file. Pick the categories, press Collect, and use **Stop** to cancel.

#### Monitor-Logs

`Monitor-Logs.ps1`. Pick logs, press **Launch selected**, and each one opens in its own PowerShell window that shows new lines as they are written. Event Viewer channels can be followed live and filtered by event ID, and folders can be watched for new files.

#### ClaudeLogAnalyzer

`ClaudeLogAnalyzer.ps1`. Drag in logs and screenshots, ask a question, and get an analysis from **Claude** (Anthropic) or **Gemini** (Google, which has a free tier). Login uses the same phone QR pairing as WinSuperTool. The request runs in the background and can be cancelled. Big logs are read from the end, binary files are skipped, and large screenshots are scaled down.

</details>

### Backup Script Builder

`BackupScriptBuilder.ps1` + `BackupScriptBuilder.bat`. Builds and schedules backups, or makes one right now (Manual Backup tab), in these forms: a **[FreeFileSync](https://freefilesync.org/)** batch job (FreeFileSync, the free open source sync tool, must be installed to run it), or a **Robocopy** or **Xcopy** script, which needs nothing but Windows. It has its own version (1.5, [what's new](docs/changes/BackupScriptBuilder-1.5.md)).

- **Build Script tab:** tick the folders to back up, pick a destination folder and how many days to keep deleted / changed files, then choose what to create: **Create FreeFileSync batch** (`BackupScript.ffs_batch`, mirrors each folder and keeps old versions), **Create Robocopy batch** or **Create Xcopy batch** (a `.ps1` or `.bat` script with log options and every switch explained). **Build Script** creates `AutomaticFileBackups\Current`, `Archive-Deleted` and `Logs` in that folder.
- **Schedule Task tab:** runs the backup on a schedule (once, daily, weekly, every X hours, at log on), with "run after a missed start" and a time limit. A **backup type** drop-down picks **FreeFileSync**, **Robocopy** or **Xcopy**. It creates, changes, runs and deletes only its own tasks, kept in the Task Scheduler folder `\BackupScriptBuilder\`.
- A **?** next to every option explains it.

- **New in 1.1:** besides the FreeFileSync batch it can **create a Robocopy or Xcopy script** (`.ps1` or `.bat`) with log options, every relevant switch explained, and (Robocopy) one thread per source drive; the Schedule Task tab has a **backup type** drop-down; and the folder picker now lists Desktop, Documents and OneDrive, with **Quick picks** at the top ([1.1 notes](docs/changes/BackupScriptBuilder-1.1.md)).
- **New in 2.0:** folders can be dragged from Explorer onto the Build Script tab's Source folders list ([2.0 notes](docs/changes/BackupScriptBuilder-2.0.md)).
- **New in 1.9:** a saved script for a zip made by Windows uses Windows' own .NET zip (no `tar.exe`), so it also works in Windows PE; a saved `.bat` finds PowerShell 7 in Hiren's PE 10; Schedule Task is greyed out in Windows PE ([1.9 notes](docs/changes/BackupScriptBuilder-1.9.md)).
- **New in 1.8:** Ultra compression is 7-Zip only (greyed out for a zip made by Windows), Remember settings also keeps the Manual Backup type (folder, zip or 7z) and the zip engine, files and folders can be dragged from Explorer onto the Manual Backup list and the Destination, Log folder and Save to boxes, and in Windows PE 7-Zip is also found on the X: and Y: drives ([1.8 notes](docs/changes/BackupScriptBuilder-1.8.md)).
- **New in 1.7:** a **Remember settings** box (bottom left), off at first: nothing is saved until you tick it, unticking deletes the file, and a damaged file is ignored ([1.7 notes](docs/changes/BackupScriptBuilder-1.7.md)).
- **New in 1.6:** the Destination folder and the Manual Backup **Save to** folder are remembered, in `BackupScriptBuilder.settings.json` next to the script (portable) ([1.6 notes](docs/changes/BackupScriptBuilder-1.6.md)).
- **New in 1.5:** a zip password with non-English letters is refused with a clear message, and folders with `[ ]` in the name work in the destination check and folder dialogs ([1.5 notes](docs/changes/BackupScriptBuilder-1.5.md)).
- **New in 1.4:** an **Update 7-Zip** button (`winget upgrade -e --id 7zip.7zip`) next to Install 7-Zip, the 7-Zip version shown, and corrected help texts ([1.4 notes](docs/changes/BackupScriptBuilder-1.4.md)).
- **New in 1.3:** a **Manual Backup** tab: back up now to a folder, a zip (Windows built in or 7-Zip) or a 7z, with Store / Normal / Ultra, a password and self-extracting .exe when 7-Zip is installed; network sources and destinations (**Add Network Path**, mapped drives saved as `\\server\share`), and Robocopy and Xcopy scripts can back up single files: the picker lists files too ([1.3 notes](docs/changes/BackupScriptBuilder-1.3.md)).
- **New in 1.2:** a folder picker fix pass: no more empty `My Documents` / `Application Data` junction folders, Windows and program folders hidden until you tick **Show Windows and program folders**, Quick picks for Favorites, Saved Games, Contacts and other users, and a folder inside another ticked folder is added only once ([1.2 notes](docs/changes/BackupScriptBuilder-1.2.md)).

Download `BackupScriptBuilder-v1.9.zip` from the [latest release](../../releases/latest).

### 7z-Encryptor

`7z-Encryptor.ps1` + `7z-Encryptor.bat`. Encrypts files and folders into one password-protected file with [7-Zip](https://www.7-zip.org/). Version 1.8 ([notes](docs/changes/7z-Encryptor-1.8.md); [1.7](docs/changes/7z-Encryptor-1.7.md), [1.6](docs/changes/7z-Encryptor-1.6.md), [1.5](docs/changes/7z-Encryptor-1.5.md), [1.4](docs/changes/7z-Encryptor-1.4.md), [1.3](docs/changes/7z-Encryptor-1.3.md), [1.2](docs/changes/7z-Encryptor-1.2.md), [1.1](docs/changes/7z-Encryptor-1.1.md), [1.0](docs/changes/7z-Encryptor-1.0.md)). Download `7z-Encryptor-v1.8.zip` from the [latest release](../../releases/latest).

- **Main window** (double-click `7z-Encryptor.bat`): tick files and folders in the same tree as Backup Script Builder, pick the format and a password (typed twice), and where to save. It is filled in next to the first item, or in the folder of your last encrypted file (when Remember settings is ticked).
- **After encrypting:** **Show in folder**, and **Send by email** with Send to > Mail recipient (classic, falls back to the Windows Share window), Windows Share, a mail program you choose, or **mailto:** with an address you type (your default mail program opens a new email to it; attach the file, which is selected in Explorer, by dragging it in). The choice and the address are remembered when Remember settings is ticked. Send the password some other way, never in the same email.
- **Remember settings** (off at first): when ticked, settings are kept in `7z-Encryptor.settings.json` next to the script, so they travel with the folder. Never a password. Unticking deletes the file; a damaged file is ignored.
- **7z:** AES-256. **Full encryption** (on by default) also hides the file names, so nothing can be seen without the password.
- **zip:** **Standard** (ZipCrypto) opens in Windows Explorer with the password but is weak, and file names stay visible. **AES-256** is strong but needs 7-Zip, WinRAR or similar to open.
- **Drag and drop:** drop files or folders on `7z-Encryptor.bat` to open the same window with them already in the list (you can still add or remove items and pick another place with Browse...). The file is saved next to the first dropped item. Dropping `7z-Encryptor.ps1` itself on the launcher just starts the tool with an empty list. Names with `&` or `^` (which Windows does not quote) arrive whole.
- Every new file is tested with the password before it is reported as done. The originals are never changed or deleted, and an existing file is never overwritten.
- 7-Zip is looked for at start. If it is missing, the tool asks whether to install it. **Install 7-Zip** / **Update 7-Zip** run `winget install` / `winget upgrade -e --id 7zip.7zip`.
- Paths with `&` or `%` in their names cannot be dropped on the `.bat` (a limit of batch files). Use the main window for those.


</details>

<details>
<summary><h2 id="what-has-been-fixed">What has been fixed</h2></summary>


Testing and code review led to **more than 100 fixes** across 14 versions. Each version's full list, with severity and how it was verified, is in [`docs/changes/`](docs/changes/).

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
| **1.9.1** | Packaging release: the 1.9 tools unchanged, plus the new **Backup Script Builder** (for FreeFileSync). | [V1.9.1](docs/changes/V1.9.1.md) |
| **2.0** | **All tools:** folders with `[ ]` in the name lost saved mounts, log summaries, WinFixKit logs and reports, and Backup Script Builder's overwrite warning, because `-Path` reads `[ ]` as a wildcard. **7-Zip tools:** a non-English zip password made 7-Zip fail; it is now refused up front. | [V2.0](docs/changes/V2.0.md) |
| **2.1** | **WinFixKit:** the Automation and Registry changes tabs move from the beta into WinFixKit, marked (beta) in the window; the separate beta is retired. | [V2.1](docs/changes/V2.1.md) |
| **2.2** | **7z-Encryptor 1.2:** Show in folder and Send by email (Send to > Mail recipient, Windows Share or a chosen program). **Backup Script Builder 1.6:** the destination folders are remembered. Settings are kept next to each script (portable). | [V2.2](docs/changes/V2.2.md) |
| **2.3** | **7z-Encryptor 1.3 / Backup Script Builder 1.7:** a Remember settings box, off at first; unticking deletes the settings file; a damaged settings file means no memory. | [V2.3](docs/changes/V2.3.md) |
| **2.4** | **7z-Encryptor 1.4:** one window for both ways of starting (dropped files go in the list, file picker and Save as included); Email with mailto:; names with & or ^ dropped on the launcher arrive whole; passwords must match exactly; no saving inside a folder being encrypted; every ? button updated. **Test Center 1.0 beta 4.** | [V2.4](docs/changes/V2.4.md) |
| **2.5** | **Backup Script Builder 1.8 / 7z-Encryptor 1.5:** Ultra is 7-Zip only (greyed out for a zip made by Windows, so backing up now and the saved script make the same zip on Windows 10, 11 and PE); in Windows PE, 7-Zip is also found on the X: and Y: drives (Hiren's BootCD PE); Remember settings keeps zip or 7z; drag and drop from Explorer onto the lists and folder boxes. **Test Center 1.0** (out of beta). | [V2.5](docs/changes/V2.5.md) |
| **2.6** | **Backup Script Builder 1.9:** saved Windows-zip scripts use Windows' own .NET zip (no `tar.exe`, which Windows PE does not have); Schedule Task greyed out in Windows PE. **7z-Encryptor 1.6:** 7-Zip's warnings shown. **All launchers** use PowerShell 7 when there is no Windows PowerShell (Hiren's PE 10). **Test Center 1.1.** | [V2.6](docs/changes/V2.6.md) |
| **2.7** | **7z-Encryptor 1.7:** mailto: waits for the pick-an-app prompt and works without a file; Change Default: mailto: / Email; Attach (Send to) and Choose program: with a list of found mail programs (no Windows Share option); Save as File or Folder: Named + Date; a cleaner window and simpler help. | [V2.7](docs/changes/V2.7.md) |
| **2.8** | **Drag and drop** onto every file / folder box: WinSuperTool 2.1 (Collect Logs folder, Run a script), WinFixKit 2.2 (ISO / image, key backup folder), Backup Script Builder 2.0 (Source folders, script, FreeFileSync.exe), 7z-Encryptor 1.8 (Save as). | [V2.8](docs/changes/V2.8.md) |

### Still open

- **K16 / S12 / R10:** a few long jobs (registry save, Store app scans, diskpart) still run on the window's thread, so the window can pause briefly.
- **R14:** WinRepairTool keeps no permanent activity log (WinSuperTool does).


</details>

<details>
<summary><h2 id="testing">Testing</h2></summary>


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

**Test Center** ([`tests/TestCenter.ps1`](tests/TestCenter.ps1)) is one window for every test that is run regularly. It has a tab per tool (Whole toolkit, WinSuperTool, WinFixKit, Backup Script Builder, 7z-Encryptor, Log tools, Other PCs / WinPE) with a tick box per test. Tick what you want and press **Run selected**. The tests then run one after the other.

- **What to test:**
  - **Offline:** any folder with the toolkit scripts, including **your own edited build**.
  - **Online:** pick a release, a beta or `main` from GitHub and download it into a folder. Test Center then shows which of the downloaded scripts you have edited since.
- **Reports:** results go to `C:\Users\Public\wrt-testcenter-<date>`, as an **HTML report** and a **Markdown summary for GitHub**. The summary contains the tools version, the edited files, Windows and PowerShell versions, a results table and the script hashes, with no PC or user names. **Copy summary for GitHub** and **Report on GitHub** make it easy to post.
- **Scripted runs:** `TestCenter.ps1 -ToolsFolder <dir> -Run unit-suite,unit-toolkit -ExitWhenDone`.
- **Greyed out:** a test that can't run on the PC or with the chosen tools, for example the two-monitor tests on one monitor. Tests that change the PC ask first.

Details: [Test Center 1.1](docs/changes/TestCenter-1.1.md) ([1.0](docs/changes/TestCenter-1.0.md), [beta 4](docs/changes/TestCenter-1.0-beta.4.md), [beta 3](docs/changes/TestCenter-1.0-beta.3.md)).

Download `TestCenter-v1.1.zip` from the [latest release](../../releases/latest), extract it and double-click `Start-TestCenter.bat`. Start it as administrator to get only one admin prompt. Test Center has its own version number and is updated only when the test procedures or the test scripts change. When a test fails, **Pack full results** makes a zip with every log for whoever fixes it. That zip contains PC details, so don't post it publicly.

To run the unit tests (they read the scripts' code and run no GUI or system changes):

```powershell
Invoke-Pester .\tests\Suite.Tests.ps1
```

Other test files:
- **`tests\Toolkit.Tests.ps1`** (24 / 24 pass): checks for all tools since 1.8.1. It covers the license headers, display scaling, the splash screen, the no-AI edition (rebuilt and compared), the HTML report and the PowerShell used for task windows.
- **`tests\Beta.Tests.ps1`** (54 / 54 pass): the tests of the 1.9 features (written during the beta): task summaries, Automation incl. WinPE, System Info.
- **`tests\Run-MonitorLive.ps1`** (start it elevated): opens every Live Monitor window hidden and checks that each one works and follows new activity.

The other scripts in `tests/` are the admin and windowed test runs used on the VM. Some of them change system settings and expect the original project folder layout; read one before running it.


</details>

<details>
<summary><h2 id="repository-layout">Repository layout</h2></summary>


```
tools/            the current scripts and launchers (v2.8), incl. the generated no-AI edition
beta/             no beta script at the moment (WinFixKit beta-automation became part of WinFixKit 2.1)
build/            Build-NoAIEdition.ps1 (generates the no-AI edition), Promote-Beta.ps1 (makes a beta stable)
docs/changes/     what each version fixed (V1.2 ... V2.8, the 1.9 betas, Test Center, Backup Script Builder and 7z-Encryptor)
docs/testing/     the test plan, results of each phase, and the v1.6 code review
tests/            Pester unit tests, Test Center (TestCenter.ps1), the test harness and the VM test runs
LICENSE           GNU General Public License v3.0
```

The scripts are pure ASCII on purpose: Windows PowerShell 5.1 reads files without a BOM as ANSI. Keep them that way when editing.

Never edit `WinSuperTool-NoAI.ps1` by hand. Change `WinSuperTool.ps1`, keep any new AI code inside `#region AI-ANALYZE` blocks (or end a single line with `# [AI]`), then run `.\build\Build-NoAIEdition.ps1`. For a beta, add `-Source beta\WinSuperTool.ps1`.


</details>

<details>
<summary><h2 id="license">License</h2></summary>


Copyright (C) 2026 TheTechSupportGuru.

This project is free software, licensed under the **GNU General Public License, version 3 or (at your option) any later version** (`GPL-3.0-or-later`). See [`LICENSE`](LICENSE) for the full text.

What that means in practice:
- You may use, study, share and change these tools.
- If you distribute them, changed or not, you must do so under the same license and include the source.
- They come **without any warranty**.


</details>

<!-- Easter egg: update the numbers at every release (see the "Hours" lines). The previous sheet is kept in docs/timesheets/. -->
<br><br>
<details>
<summary><sub><sup>&pi;</sup></sub></summary>

### You found the time sheet


How long this project has taken, as of **2.6** (November 26, 2026): the version that was a joke at the bottom of this very section until it wasn't. For 1.1 onwards, the AI hours are measured from the session logs, and the human hours are an honest guess, "which is the polite word for 'vibes'". The original scripts are estimated by the Claude project that wrote them, which had no stopwatch either. The 1.9 sheet is kept in [docs/timesheets/timesheet-1.9.md](docs/timesheets/timesheet-1.9.md), in case anyone wants to audit the vibes.

| | Human | AI |
|---|---:|---:|
| Writing the original scripts in claude.ai, Nov 12-19 (the earlier Claude project's own estimate: Windows repair tool, WinFixKit, log collector and monitor, log analyzer) | ~8 h | ~6 h |
| 1.1 to 1.9 and Test Center: fixing, testing, more testing, releasing | ~14 h | ~11 h of actual thinking and typing, over ~20 h of wall clock |
| 1.9.1: Backup Script Builder, WinFixKit beta-automation 1 and 2 (66 tasks run for real, twice), Test Center beta 2 | ~4 h | ~3 h |
| Redoing every beta into one release, because the main release must always be on top | ~2 h | ~1 h |
| Then un-redoing it: moving the old betas back out, because one release with 19 zips is not a release, it is a yard sale | ~1 h | ~0.5 h |
| 1.9.2: Backup Script Builder 1.2 to 1.4 (single files, network paths, a Manual Backup tab with zip / 7z / self-extracting .exe), 7z-Encryptor 1.0 from nothing, and every ? button re-read against what it actually does | ~3 h | ~6 h |
| 2.0: a regression and edge-case pass over every tool, a local AI's code review (mostly fact-checked into the bin), `[ ]` folders, 7-Zip passwords in 7 flavours of awkward, and every doc brought up to date | ~1 h | ~2 h |
| 2.1: promoting the WinFixKit beta, which mostly meant deleting the word "beta" from everywhere and then carefully sticking it back on two tabs | ~0.1 h | ~0.3 h |
| VMs grinding through test runs while everyone else made coffee | ~0 h | ~15 h of machine time, unsupervised. The VMs have asked for a union. |
| **Total** | **~33 h** | **~29.5 h** (plus a lot of patient VMs, and one very tired releases page) |

**By the numbers**
- 76 commits, 14 release entries, 32 tags. Five naming styles on the releases tab at one point. For one word.
- About 15,300 lines of tool code (plus the betas and build scripts), 6,300 lines of tests, and ~45,000 words of docs. More docs than some novels, fewer plot twists. Mostly.
- 497 unit tests (plus 102 Backup Script Builder GUI checks and 43 for 7z-Encryptor, including a real file dropped on a real `.bat`), 66 WinFixKit Automation tasks run for real as administrator (twice), and 19 zips in one release.
- More than 100 bugs fixed. One of them was a splash screen that closed the whole app. Another was a commit stuck in a cloud container, sent home by patch file, like a kid with a note from the teacher.
- 3 operating systems, 2 monitors, 1 VM that got its display scaling changed more times than any VM should.
- Number of times the AI mixed up which side the second monitor is on: 1. The human remembers.
- Number of times a short PowerShell alias (`H`, `R`) secretly turned into `Get-History` / `Invoke-History`: 3. The third was while writing the 2.1 notes for this very page. PowerShell thinks this is funny.
- Number of ? buttons that turned out to describe a different, older tool: 4. They have been re-educated.
- Number of times 7-Zip was asked to encrypt something during testing: dozens. Number of passwords it was told: always the same one. Not saying which.
- Number of passwords 7-Zip silently stored as something other than what was typed: 0, but only because `"` was already banned. 7-Zip's command line has opinions about quotes.
- Number of folders called `[ ]` it took to break five tools at once: 1.
- Beta 5 is still not a thing, and never was. Stop asking.
- Number of times the betas moved house in one day: 3. Own release pages, then all crammed into 1.9.1, then the old ones evicted to 1.9. They have stopped unpacking.
- Zips on the latest release: 8, then 19, then 11. The download count per zip has never been lower, or more confused.

*Updated at every release. If the human column ever drops below the AI column, someone owes someone a coffee. ~~Please don't tell them about 2.0.~~ Somebody told them. Please don't tell them about 3.0.*

<details>
<summary></summary>

**How long it takes the human to re-read it all**

| What | Words | Just reading (~230 words a minute) | Hunting for mistakes (~100 words a minute) | Marvelling at it |
|---|---:|---:|---:|---:|
| This page | ~4,100 | ~18 min | ~40 min | open-ended |
| Every doc in the repo (change notes, test plans, results) | ~41,000 | ~3 h | ~7 h | open-ended |
| Every release note (now mostly one very long one) | ~6,500 | ~30 min | ~1 h | open-ended |
| The ~14,600 lines of tool, beta and build code | - | ~7 h if you skim | ~3 working days | **the rest of your life** |
| **Everything** | **~51,600** | **~11 h** | **~4.5 working days** | **forever** |

Marvelling takes so long because, as far as we can tell, nothing else does all of this at once: boot repair, Safe Mode, deployment, log collection, a live monitor, AI log analysis, an automation queue that also repairs a Windows that won't start from Hiren's PE, FreeFileSync backups on a schedule, and a test tool to check all of it. If you find one, please open an issue so we can be a little less smug.

The "hunting for mistakes" column is not theoretical. One proofreading pass found five naming styles on the releases tab, a beta that never existed in the bug form, and a link to a folder that never left the PC. The next one found the 1.9.1 row of the version table moved into the middle of the 1.9 row.

<details>
<summary></summary>

**What each tool went through in 1.9.1**

| Tool | What happened to it | How it feels about it |
|---|---|---|
| WinSuperTool | Nothing. Still 1.9, zip renamed to 1.9.1. | Smug. |
| WinFixKit | Grew an Automation tab in a beta, had all 66 tasks run for real twice, lost 4 bugs, and learned that an empty Recycle Bin is not an emergency. | Tired, but cleaner. |
| WinFixKit (2.1) | Moved out of the beta folder into the real one, with two tabs still wearing their beta stickers like L plates. | Finally allowed to stay up late. |
| Backup Script Builder | Born. Builds and schedules FreeFileSync backups, with a ? next to everything. | New, keen, asks a lot of questions. |
| 7z-Encryptor (1.9.2) | Born from Backup Script Builder's folder picker, which it borrowed and never gave back. Asks for your password twice and believes neither until it has tested the file. | Trust issues, professionally. |
| Backup Script Builder (1.9.2) | 1.2, 1.3 and 1.4 in a week: files, network shares, a whole Manual Backup tab, and now it installs and updates 7-Zip for you. | Going through a phase. |
| Test Center | Beta 2: learned that betas no longer have their own release entries and went looking for their tags instead. | Mildly confused, coping. |
| The betas | Moved out of their own release entries into collapsible sections of the main release. | Folded. Literally. |
| The releases page | Renamed, re-sorted, then reduced to one release on top. | Finally at peace. |
| Every tool (2.0) | Told it was now version 2.0. Changed nothing about itself except one line at the top, and learned to read a folder called `[2026]` without panicking. | Promoted without a raise. |
| The local AI (2.0) | Reviewed 7z-Encryptor and found twelve problems, one of them real. Was certain 7-Zip runs through `cmd.exe`. Then reviewed Backup Script Builder and wrote "If the path contains `&`, it is escaped. This is correct." a few hundred times in a row, until it was switched off. | Confident. Unbothered. Correct, eventually, at length. |
| The VMs (2.0) | Ran everything again. | Have stopped asking what version it is. It doesn't help. |

<details>
<summary></summary>

**The Great Time Sheet Incident of 1.9.1, as reconstructed by the survivors**

1. The human asked for one thing: update the hidden time sheet at the bottom of this page.
2. A cloud agent wrote the update, then found it was not allowed to push to GitHub. It sent the commit home as a patch file, like a kid with a note from the teacher.
3. Asked to "publish it with some snark", it published a whole separate web page instead. Nobody asked for a web page. The web page did not know this.
4. The patch never reached the PC that could push it. The update existed only in a summary, which is the software version of "trust me, I wrote it down somewhere".
5. A second agent rebuilt the update from that summary, found the 1.9 row of the version table had been sawn in half to make room for 1.9.1, and glued it back together.
6. It also found that the 1.9 release notes had lost every line break on the way back in, and were one paragraph about 6,000 characters long. It put the line breaks back.
7. It then started re-testing tools that were already tested. The human stopped it, which was correct.
8. The web page nobody wanted was deleted. A search for links to it found none, because nobody had ever linked to it, because nobody had ever wanted it.

Total time spent on a hidden section most people will never open: more than the time it took to write the Recycle Bin fix. Lessons learned: "publish" means "push", "snark" goes *in* the README, and a patch file on another computer is not a commit. The AIs have agreed to stop helping for at least five minutes.

**The Great Time Sheet Incident, part 2: the betas strike back**

9. Once the time sheet was safe, the human looked at the latest release and found 19 zips and eight beta sections, most of them for betas that had already been replaced. Nobody downloading a repair tool wants to read the life story of WinSuperTool beta 2 first.
10. So the old betas were moved back out: eight zips copied to the 1.9 release, sizes checked, then removed from 1.9.1. Their notes moved with them, like a box labelled "misc" that follows you through every house move.
11. Then the main page and the latest release were cleaned of every sentence that explained where the old betas had gone. Explaining the move took more words than the betas' actual features.
12. The 1.9 release now opens with "Newer: v1.9.1. Download from there", which is the release-notes equivalent of a note on the fridge.

Current status: the latest release holds the tools, Backup Script Builder and exactly one beta per tool in testing. This arrangement is final, the way every arrangement before it was final.

**The Great Time Sheet Incident, part 3: the re-reading**

In the last 45 minutes the human re-read this page about six times: once for the time sheet, once for the broken 1.9 row, once for the 19 zips, once for the old-beta wording, once to find the incident reports lying on the page in plain sight, and once more to check they were hidden again. At ~18 minutes per read (see the table above), that is more reading than the 45 minutes allowed, which is only possible if you skim the jokes. Meanwhile the human's token budget sat at 7 % until Wednesday, and every fix for a hidden section nobody opens came out of it. The AI swears it is not doing this on purpose. The AI would say that.

Update, later that night: 1.9.2, simpler forms and Test Center beta 3 also shipped. We are really, really done changing things tonight. Really. (This line was added by a change.)

**The Great Time Sheet Incident, part 4: the operator's note**

Another review was needed, and this one is not about the code. The operator spent 15 hours creating, testing and optimizing a new local LLM for daily and overnight runs. He is unsure Claude cared or used it. It is filed here, in the hidden section, because that is where the things that matter on this page seem to end up.

**The Great Time Sheet Incident, part 5: 2.0**

For weeks the last line of the time sheet said "Please don't tell them about 2.0". It was a joke. Then the human asked for 2.0, by name, with a snarky comment on the main page, and the AI realised it had been writing its own prophecy in a hidden section nobody opens.

What 2.0 found, in order of embarrassment:
1. While updating the time sheet for 1.9.2, the AI had glued two lines of this very section together, deleting the 7-Zip password joke and the official denial of beta 5. The section that exists to catch mistakes had a mistake in it. It was found while adding this paragraph, which is the only reason to ever re-read anything.
2. Five tools forgot their own files the moment someone put them in a folder with square brackets in the name. Not a missing file, not a bad disk: brackets. PowerShell sees `[2026]` and thinks "a wildcard matching 2, 0 or 6". It has been doing this since 2006. Nobody had tried it.
3. The AI's own test for the bracket bug failed with the bracket bug. The test was rewritten in a folder without brackets, like a fire inspector who keeps setting his clipboard on fire.
4. The local AI was asked for a second opinion and gave twelve. One was true. Asked for a third, it decided that an ampersand in a path is escaped correctly, and then decided it again, and again, a few hundred times, like a smoke alarm that has found peace. The human's GPU fan has not been the same since.

Total time from "Please don't tell them about 2.0" to 2.0: one week. The VMs were not consulted. The VMs are never consulted.

**The Great Time Sheet Incident, part 6: the note**

The note used to sit at the top of this page, where it did not belong. It is moved here with the rest of the time sheet confessions:

**2.0. The day we thought would never come.** For a while, "Please don't tell them about 2.0" was the last line of a hidden time sheet on this page. Then someone told them. The test VMs, asked for comment, rebooted. When they came back, one changed its own display scaling to 175 % and has refused to discuss it. The other has filed a formal objection, in Event Viewer, as Event ID 41: *"The system has rebooted without cleanly shutting down first."* Accurate. The local AI on the GPU next door reviewed the 2.0 code and reported, with total confidence, that 7-Zip is started through `cmd.exe`. It isn't, and never was. Asked whether 2.0 left it confused or appalled, it thought for 2,000 tokens and answered "yes". Asked to review Backup Script Builder, it concluded "If the path contains `&`, it is escaped. This is correct." and then, to be sure, concluded it a few hundred more times. It was, however, entirely right to be appalled by one thing in 2.0: a PowerShell parameter called `-Path` that treats `[ ]` in a folder name as a wildcard. That one is fixed.

**Gobble gobble.** 2.3 shipped with a Remember settings box that is off until you tick it, and the bug forms finally list 2.3. Nobody has explained the turkey. The VMs were asked for a comment and replied only with a sound.

**Gobble gobble gobble.** 2.4 shipped with a 7z-Encryptor that opens one window for both ways of starting, and the turkey still has not been explained. The VMs were asked for a second comment and gobbled back.

**Gobble gobble gobble gobble.** 2.5 shipped with Test Center out of beta, and the turkey has now been seen by a Windows PE drive letter. The VMs were asked once more and gobbled in unison.

**Gobble gobble gobble gobble gobble.** 2.6 shipped with the PE fixes, and the turkey finally learned to run without tar. The VMs were asked to regress Hiren's PE and gobbled in its place.

**Black Friday. Cha-ching.** 2.8 shipped on the day the shops open, with a drop target on every box that takes a name. The turkey has been dragged out of the oven and is now a file. The VMs were asked to test it by dragging things and gobbled back, once per drop.

<details>
<summary></summary>

**Fragment 0x1A, recovered from a log nobody rotated**

*Where the cold shell ends and the bell-less tower stands,*
*a hatch opens once a year for the one who lists the names.*
*Eight hooves on a PE drive, a ninth that never prints,*
*and a ledger filed under a word that means "be good".*
*The seal is a hash shaped like a chimney with no fire.*
*Something under the tag-tree is wrapped in no tar and no name.*
*When the December tags are cut, count the zips twice,*
*and mind the box that was never on the manifest.*

Status, unverified: an item is in transit toward this repository. Arrival window is believed to fall near the turn of the year. Source: a commit message at 3 AM, and one VM that refuses to comment. Do not open anything in the tree before the last release of the month.

</details>
</details>

</details>

</details>

</details>
