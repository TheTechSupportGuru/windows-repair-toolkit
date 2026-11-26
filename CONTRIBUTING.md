# Contributing

Bug reports, ideas and pull requests are welcome. Please read this first.

## The one rule: only the runtimes built into the supported systems

The toolkit has to work on a PC that is broken, offline, or booted from a rescue disk. So **code may only run on the runtimes that are already built into all three supported systems**:

| Supported system | Built-in runtimes |
|---|---|
| **Windows 11** (64-bit) | Windows PowerShell 5.1, .NET Framework 4.x, cmd |
| **Windows 10** (64-bit, also on MBR disks / Legacy BIOS) | Windows PowerShell 5.1, .NET Framework 4.x, cmd |
| **Hiren's BootCD PE 10 and PE 11** (WinPE) | Hiren's PE 11: Windows PowerShell 5.1. Hiren's PE 10: PowerShell 7 only (`Y:\Programs\PowerShell Core_x64`), so code must run on both 5.1 and 7 |

That means:
- **Write it in PowerShell**, with .NET / WinForms for windows, C# only through `Add-Type` using what .NET already includes, and `.bat` / `cmd` for launchers. The syntax must work on PowerShell 5.1 and run on 7.
- **No other runtimes or installs.** No Python, Node, Java, AutoHotkey, Git or other interpreters. No PowerShell Gallery modules (`Install-Module`), no NuGet packages, no third-party `.exe` / `.dll`, nothing downloaded at run time.
- **Windows' own programs are fine.** You can use any program, cmdlet or console that comes with Windows (`dism`, `sfc`, `netsh`, `.msc` consoles and so on), including ones the tools don't use yet. If it isn't on every supported system (for example `winget`, `bootrec`, or `gpedit.msc` on Home editions), check for it first and say clearly when it's missing. The tool must never fail without a message.
- **Scripts stay pure ASCII**, one `.ps1` per tool, with the licence header (GPL-3.0-or-later).
- **Network use** only where the user asks for it (the optional AI analysis and Test Center's Online mode). Nothing may phone home.

Pull requests that need another runtime or an install will be asked to remove it.

## What the tools use today (for reference)

This is what the tools call now. It isn't a limit: other built-in Windows programs are welcome under the rule above.

**PowerShell and .NET**
- Windows PowerShell 5.1 (`powershell.exe`), and PowerShell 7 where it is the only one (Hiren's PE 10)
- Built-in cmdlets and modules: Storage (`Get-Disk`, `Get-Partition`), NetAdapter / NetConnection, SmbShare, PrintManagement, PnpDevice, CimCmdlets (`Get-CimInstance`), Defender (`Get-MpPreference`, `Get-MpThreat`), `Get-WinEvent`, `Get-AppxPackage`
- .NET assemblies: `System.Windows.Forms`, `System.Drawing`, `Microsoft.VisualBasic` (input box only)
- Win32 functions through `Add-Type` (user32 and kernel32 only: window position, DPI, display settings)
- Pester 3.4 (the version built into Windows) for the unit tests

**Command-line programs (in System32)**
- Boot and disks: `bcdedit`, `bcdboot`, `bootrec` (WinPE / recovery only, checked first), `diskpart`, `mountvol`, `format`, `label`, `fsutil`, `manage-bde` (BitLocker status, in messages)
- Repair: `sfc`, `dism`, `chkdsk`, `pnputil`, `wusa`, `sysprep` (pre-flight checks only by default), `wsreset`, `cleanmgr`
- Files and permissions: `takeown`, `icacls`, `expand`, `copy`, `more`, `where`
- Registry and services: `reg`, `sc`, `net`
- Network: `netsh`, `ipconfig`, `ping`, `arp`, `route`, `cmdkey`, `w32tm`
- System and logs: `systeminfo`, `wevtutil`, `powercfg`, `whoami`, `taskkill`, `shutdown`
- Optional, checked before use: `winget` (not on Windows 10 without App Installer, not in WinPE)
- Consoles: `cmd.exe`, `conhost.exe`

**Windows tools the System Info tab only opens (never required)**
- Programs: `msinfo32`, `dxdiag`, `devmgmt.msc`, `diskmgmt.msc`, `compmgmt.msc`, `eventvwr.msc`, `services.msc`, `taskschd.msc`, `lusrmgr.msc`, `fsmgmt.msc`, `certmgr.msc`, `gpedit.msc`, `secpol.msc`, `printmanagement.msc`, `wf.msc`, `taskmgr`, `resmon`, `perfmon`, `regedit`, `msconfig`, `mdsched`, `rstrui`, `dfrgui`, `optionalfeatures`, `SystemPropertiesAdvanced`, `winver`, `notepad`, `explorer`, `control`, `rundll32`
- Control Panel pages: `appwiz.cpl`, `ncpa.cpl`, `sysdm.cpl`, `mmsys.cpl`, `inetcpl.cpl`, `powercfg.cpl`

Some of these are missing on Home editions or in WinPE (for example `gpedit.msc`, `secpol.msc`). The tools say so instead of failing.

## Automation: WinSuperTool first, then WinFixKit

WinSuperTool's **Automation** tab (the queue of tasks, the pass / fail summaries, the HTML report) is the original. WinFixKit (`tools/WinFixKit.ps1`, since 2.1) has a port of it in its `#region AUTOMATION` block.

- **Every change to Automation is made in `tools/WinSuperTool.ps1` first**, then ported to WinFixKit. Never the other way round, and never in WinFixKit only.
- The ported code is WinSuperTool's word for word, with a short list of renames: `New-Ctl` -> `New-AutoCtl`, `Safe` -> `Invoke-AutoSafe`, `$DataDir` -> `$script:RootDir`, `WinSuperTool-Data` -> `WinFixKit`.
- Only the parts marked `WinFixKit:` differ on purpose:
  - the task list (WinFixKit's own status checks and fixes);
  - no live-log option;
  - no offline queue from WinPE;
  - the admin check.
- After changing Automation in WinSuperTool, run `build/Port-AutomationToWinFixKit.ps1`. It rebuilds the region from WinSuperTool and stops if WinSuperTool changed in a way the port doesn't expect. The WinFixKit-only parts are in `build/automation-port/`.
- `tests/WinFixKitAutomation.Tests.ps1` fails when a ported function no longer matches WinSuperTool's.

## Before you open a pull request

1. Change the scripts in `tools/` only. Never edit `WinSuperTool-NoAI.ps1` by hand. Rebuild it with `build/Build-NoAIEdition.ps1`.
2. Run the tests with **Test Center** (`tests/Start-TestCenter.bat`): choose your edited `tools` folder (Offline mode) and run at least the three unit-test sets and the tests for the tool you changed.
3. Paste Test Center's **"Copy summary for GitHub"** text into the pull request. It lists your edited files and the results, and contains no PC or user names.
4. Say which of the supported systems you tested on.
5. Don't include anything that identifies you or a PC (names, IPs, MAC addresses, paths with user names) in code, comments, test results or screenshots.

## Reporting bugs and ideas

Use the [issue forms](https://github.com/TheTechSupportGuru/windows-repair-toolkit/issues/new/choose) or [Discussions](https://github.com/TheTechSupportGuru/windows-repair-toolkit/discussions). For a bug, Test Center's summary for GitHub is the most useful thing to include.
