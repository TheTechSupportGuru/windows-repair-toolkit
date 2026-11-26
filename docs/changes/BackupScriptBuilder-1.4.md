# Backup Script Builder 1.4 (2026-11-26)

Update 7-Zip, and help texts checked. Earlier notes: [1.3](BackupScriptBuilder-1.3.md), [1.2](BackupScriptBuilder-1.2.md), [1.1](BackupScriptBuilder-1.1.md), [1.0](BackupScriptBuilder-1.0.md).

## New
- **Update 7-Zip** button next to **Install 7-Zip** at the bottom of the Manual Backup tab. It runs `winget upgrade -e --id 7zip.7zip` in a console window and finds 7-Zip again when it finishes. It is on only when 7-Zip is installed; **Install 7-Zip** is on only when it is not.
- The 7-Zip line shows the installed version, for example `7-Zip found: C:\Program Files\7-Zip\7z.exe (version 24.09)`.

## Fixed
Every **?** help text was checked against what the tool does. These were out of date:
- **Build Script** only talked about FreeFileSync. It now also describes the Robocopy and Xcopy scripts the button builds.
- **Destination folder** only described the FreeFileSync layout. It now says what a Robocopy or Xcopy script creates.
- **Backup script** (Schedule Task tab) said only `.ffs_batch` files. It now names Robocopy, Xcopy and manual backup scripts too.
- **Source folders** now names the **Add Files/Folders** button that Robocopy and Xcopy show.
- **Get 7-Zip** now describes the Update button.

## Tested
Run-BackupScriptBuilder.ps1: 101 / 101 pass, including the new buttons, the version line and that Update sits next to Install. BackupScriptBuilder.Tests.ps1: 63 / 63 pass. Not tested: running the winget upgrade itself.