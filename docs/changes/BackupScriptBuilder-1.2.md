# Backup Script Builder 1.2 (2026-11-26)

A fix, regression and speed pass on the folder picker (**Add Folders...**). Earlier notes: [1.1](BackupScriptBuilder-1.1.md), [1.0](BackupScriptBuilder-1.0.md).

## Fixed
- **Junctions listed as folders:** the user folder's built-in junctions (`My Documents`, `Application Data`, `Cookies`, `Local Settings`, `Start Menu`, `SendTo`, `Recent`, `NetHood`, `PrintHood`, `Templates`) showed up as extra folders that opened empty, and `Documents and Settings` on the Windows drive the same. On PowerShell 5.1 these junctions report no link type because they deny listing, so 1.1 kept them. The picker now reads the reparse tag from the folder's directory entry (without opening it) and skips only junctions and symbolic links; OneDrive folders stay.
- **The tree did not open at Users:** it was meant to open the Windows drive at `Users`, but the folders were only filled once the window existed, so it opened collapsed. It now opens at `Users` on the drive Windows is on (not always `C:`).
- **A folder you have no access to** now says "(cannot open this folder - no access)" instead of an expand arrow that opens nothing.
- **The same folder twice:** ticking a folder and a folder inside it (for example the user folder and Desktop in Quick picks) added both, so the files were copied twice. Now only the outer folder is added, and a folder already in the list is not added again (also when the letters differ in case).

## New
- **Windows and program folders are hidden** until you tick **Show Windows and program folders** at the bottom of the picker: `Windows`, `Program Files`, `Program Files (x86)`, `ProgramData`, `Recovery`, `PerfLogs`, `System Volume Information`, `$Recycle.Bin` and other `$` folders on a drive, and hidden system folders anywhere. Ticking it inserts them in place (greyed when hidden); unticking removes them again. Ticks on other folders are kept.
- **Quick picks** also list Favorites, Saved Games, Contacts and the other user profiles on this PC (also ones kept on another drive).

## Faster
- One directory read per folder (no extra `Get-Item` per OneDrive or reparse folder), and the tree is redrawn once per opened folder instead of once per subfolder.

## Tested
`tests/Run-BackupScriptBuilder.ps1`: 77 / 77 on the Windows 11 VM. The 14 new checks:
- Every real folder in the user folder is listed, hidden ones included, and none of its junctions.
- Users lists every profile, without `All Users` and `Default User`.
- System folders are hidden by default, inserted in order when the box is ticked, and removed again when it is unticked.
- A folder with no access says so.
- No duplicate or nested folders in the result.
- The real dialog: its buttons are inside the window, it opens at Users, the tick box works, and ticking Desktop plus the user folder returns only the user folder.

The picker layout was also checked from window captures in both states.
