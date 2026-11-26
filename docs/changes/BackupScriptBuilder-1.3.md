# Backup Script Builder 1.3 (2026-11-26)

Single files and empty folders. Earlier notes: [1.2](BackupScriptBuilder-1.2.md), [1.1](BackupScriptBuilder-1.1.md), [1.0](BackupScriptBuilder-1.0.md).

## New
- **Back up single files (Robocopy and Xcopy):** with Robocopy or Xcopy selected, the button reads **Add Files/Folders** and the tree lists the files in each folder after its subfolders (hidden system files such as `desktop.ini` are left out). Tick any mix of folders and files. Files from the same folder share one backup folder under `Current\<folder name>`, and only the ticked files are copied: `/E`, `/S`, `/MIR` and `/T` are left off for them, so same-named files in subfolders are not copied and nothing is purged.
- A FreeFileSync batch still takes folders only. If files are in the list, **Build** says which ones and asks you to remove them or switch to Robocopy or Xcopy.

## Checked
- **Empty folders** (an empty Desktop, Documents or OneDrive, or any other folder in the user folder or on a drive) can be ticked like any other and are copied: `/E` is on by default for Robocopy and Xcopy, and FreeFileSync copies empty folders anyway. New tests run real Robocopy and Xcopy scripts (`.ps1` and `.bat`) on test folders to confirm this.
