# Backup Script Builder 1.8 (2026-11-26)

Part of the toolkit's 2.5 release.

- **Ultra compression is 7-Zip only.** On the Manual Backup tab, with **Zip made by: Windows (built in)**, the Compression list shows Ultra greyed out as "Ultra (7-Zip only)", and it cannot be picked. Switching from 7-Zip back to Windows turns Ultra into Normal.
  - Why: backing up now zips with .NET, whose strongest setting in Windows PowerShell 5.1 is the same as Normal, while the saved script used `tar.exe` with a real level 9. The same choice made two different zips. Now Store and Normal give the same zip both ways, on Windows 10, 11 and PE.
  - The saved script no longer passes `zip:compression-level=9` to `tar`. Store (`zip:compression=store`) is unchanged.
  - With 7-Zip (zip or 7z), Store / Normal / Ultra stay (`-mx=0 / 5 / 9`).
- **7-Zip is found in Windows PE.** In Windows PE (Hiren's BootCD PE 10 / 11 and others) the tools also look for 7-Zip on the X: and Y: drives, up to 3 folders deep, and in the PATH. On a normal Windows the X: and Y: drives are not searched (they may be network drives). The search skips Windows, boot and system folders and stops after 4000 folders.
- **Remember settings keeps the Manual Backup type.** With Remember settings ticked, closing the tool also saves the type (folder, zip or 7z) and who makes the zip (Windows or 7-Zip), and they are put back the next time.
  - On a PC without 7-Zip the tab falls back to a Windows zip by itself; that fallback does not overwrite the remembered 7z or 7-Zip choice, so it comes back on the next PC that has 7-Zip. A folder copy picked by hand is saved as usual.
  - An unknown type or engine in the settings file is dropped, the rest is kept.
- **Drag and drop from Explorer.**
  - Files and folders dragged onto the Manual Backup list are added, like Add Files/Folders: never twice, mapped drives as `\\server\share`, and an item that is not there is skipped.
  - A folder dragged onto the Destination folder (Build Script), the Log folder (Robocopy and Xcopy pages) or Save to (Manual Backup) fills in the box; a dropped file puts in the folder it is in. A box that is off (Log folder with logging off) takes no drop.
  - Drag and drop does not work while the tool runs as administrator and Explorer does not (Windows blocks it). The launcher does not ask for administrator rights.
- The **?** texts: What to back up, Destination folder, Log and Save to mention dragging; Back up to says Ultra needs 7-Zip and what is remembered; Get 7-Zip says where the tool looks.

Tested:
- 132 / 132 checks of `tests/Run-BackupScriptBuilder.ps1` (20 new):
  - Ultra: greyed out and not pickable with Windows zip, never sent as Ultra, pickable with 7-Zip, back to Normal when switching to Windows.
  - Drag and drop, through the real DragEnter / DragDrop handlers with an Explorer-style file list: the list (added, missing skipped, never twice, `R&D [1]` whole, text refused), Save to (a folder; a file gives its folder), Destination (a missing folder changes nothing), both Log folder boxes (not while off).
  - Remember settings: 7z, zip with 7-Zip and a folder copy are saved; without 7-Zip the fallback keeps the remembered 7z / 7-Zip; the remembered type is put back at start; an unknown value is dropped.
- Started the tool with four settings files (7z; zip by 7-Zip; zip by Windows; Remember false): the tab showed what each file says, and nothing for the last one.
- Pester: a Windows zip script never asks `tar` for a level and Store stays store; the saved-script runs cover a Windows zip at Normal; 8 new tests for the PE search (Hiren's-style folder, drive root, shallowest first, 3 folders deep and not 4, skipped folders, missing drive, folder limit, PE only).