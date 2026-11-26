# WinFixKit 1.9 beta-automation 3 (2026-11-25)

Adds a **Registry changes (beta)** tab: find registry keys changed since a date, see what each value was before, and put back only the values you tick. Scanning changes nothing. Earlier notes: [beta-automation 2](WinFixKit-1.9-beta-automation.2.md), [beta-automation 1](WinFixKit-1.9-beta-automation.1.md).

The Automation tab is unchanged from beta 2.

## The Registry changes tab

- **Changed since** a date: lists keys whose last-change time (Windows keeps one for every key) is on or after it.
- **Areas to scan**, each with a tick box: Power, UAC and administrator, Defender and firewall, SMB / Remote Desktop / printing, Policies, Run and startup keys, Services (start types), Explorer and Start, plus Software and Everything (off by default: slow, and full of harmless changes by programs).
- **Reference sources** - where the old value comes from. Tick the ones to use and set their order with Move up / Move down; the first source that knows a value wins, and the results say which one it was. The choice and order are remembered.
  - **Shadow copy / restore point**: the real earlier registry, from a snapshot of the system drive you pick in the list. Needs administrator rights.
  - **WinFixKit registry backups**: the originals WinFixKit saved before its own fixes.
  - **Windows ISO / install image**: the registry of a fresh install of the edition you pick from an ISO, install.wim or install.esd. Mounted read-only; only the registry files are copied out. Needs administrator rights; warns if the build differs from this PC.
  - **Built-in defaults list**: 71 settings whose Windows 10 / 11 default is known for certain (UAC, sign-in, Remote Desktop, printing and SMB policies, firewall, Defender and Update policies, fast startup, Explorer, service start types).
- **The results window** (resizable): one row per changed value with a **Revert? yes / no** tick box, the current value, the old / default value and its source.
  - Rows that can be reverted are listed first; rows no reference knows are greyed and can't be ticked.
  - Sort by any column, filter, Tick all shown / Untick all, Details (or double-click) for the full path and values.
  - **Back up the original keys to:** a folder of your choice (default: WinFixKit's RegistryBackups\Keys).
  - **Revert ticked items...** asks first, listing what will change. Each key is exported as a .reg file to the backup folder and backed up the usual WinFixKit way (so it shows in the Registry Backups tab), then the value is set back or removed. You get a result per item and a summary file.
- A **?** button on everything.

## Tested

- **Unit tests** (`tests/WinFixKitAutomation.Tests.ps1`, new W4 block, on a throw-away key under HKCU): key times, the scan, the defaults list is well-formed, the reference-path mapping, the difference rows, and a real revert with its .reg and WinFixKit backups. 67 of 67 pass together with `Toolkit.Tests.ps1`; the "nothing else in WinFixKit changed" check still passes.
- **In the window**, as a standard user on Windows 11: a scan of the last 7 days (Services + Explorer areas, WinFixKit backups + built-in defaults) found 1,091 changed keys; 5 values could be reverted (HideFileExt and four service start types), listed first. The window layout was checked from window captures; this found and fixed the Scan button sitting below the visible part of the tab and the results window's Close / Browse buttons being off the right edge.

## Not tested yet

- **Shadow copy and ISO / WIM sources** with administrator rights (the code paths are written, but they've only run where they skip without admin).
- Reverting from the window itself (the revert function is tested; nothing was reverted on the test PC).
- Windows 10.
