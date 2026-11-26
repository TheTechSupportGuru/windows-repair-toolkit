# Backup Script Builder 1.3 (2026-11-26)

A new **Manual Backup** tab, single files, network paths and empty folders. Earlier notes: [1.2](BackupScriptBuilder-1.2.md), [1.1](BackupScriptBuilder-1.1.md), [1.0](BackupScriptBuilder-1.0.md).

## New
- **Manual Backup tab:** back up right now, without a script or a task. Pick folders and files (the same tree, plus **Add Network Path**), where to save (a drive or `\\server\share`), and what to make:
  - **A folder:** a plain copy (robocopy) in `Backup-<date>_<time>`.
  - **A zip file**, made by **Windows (built in)**, nothing to install, or by **7-Zip**. Compression **Store**, **Normal** or **Ultra**. Windows' own zip has nothing stronger than Normal, so Ultra is Normal there (the help says so); 7-Zip's Ultra is `-mx=9`.
  - **A 7z file** (7-Zip), Store / Normal / Ultra.
  - **Password** (only when 7-Zip makes the archive): AES-256. For 7z, **Also hide the file names** is on by default. It is typed twice, and can be shown.
  - **Self-extracting .exe** (7z): **windowed** (asks where to unpack) or **console**. It opens on any Windows PC without 7-Zip.
  - Every backup gets a new `Backup-<date>_<time>` name, so nothing is overwritten. It runs in the background with a **Cancel** button (a cancelled zip or 7z is deleted), and lists any file it could not read (in use or no access).
  - Without 7-Zip, the 7-Zip choices are greyed out and a link to https://www.7-zip.org/ is shown.
- **Back up single files (Robocopy and Xcopy):** with Robocopy or Xcopy selected, the button reads **Add Files/Folders** and the tree lists the files in each folder after its subfolders (hidden system files such as `desktop.ini` are left out). Tick any mix of folders and files. Files from the same folder share one backup folder under `Current\<folder name>`, and only the ticked files are copied: `/E`, `/S`, `/MIR` and `/T` are left off for them, so same-named files in subfolders are not copied and nothing is purged.
- A FreeFileSync batch still takes folders only. If files are in the list, **Build** says which ones and asks you to remove them or switch to Robocopy or Xcopy.
- **Network sources and destinations:** **Add Network Path** adds a folder on another PC or NAS typed as `\\server\share\folder` (or a single file, for Robocopy and Xcopy). The destination box takes a `\\server\share\Backups` path too. A path on a mapped drive (`Z:\...`), whether picked in the tree, typed or browsed, is saved as its `\\server\share` path, because a scheduled task often cannot see mapped drive letters. An unreachable path is refused with a message instead of being added.

## Fixed
- **A share root as a source** (`\\server\share`) was named `_-Drive` in the backup. It is now named after the share.

## Checked
- **Manual Backup:** the GUI test runs a folder backup, a Windows zip and a cancel in the background and checks what was made. Unit tests cover Store against Normal size, a locked file, two folders with the same name, never overwriting, and the exact 7-Zip command line for every option. The 7-Zip runs themselves were not tested here (7-Zip is not installed on the test PC).
- **Empty folders** (an empty Desktop, Documents or OneDrive, or any other folder in the user folder or on a drive) can be ticked like any other and are copied: `/E` is on by default for Robocopy and Xcopy, and FreeFileSync copies empty folders anyway. New tests run real Robocopy and Xcopy scripts (`.ps1` and `.bat`) on test folders to confirm this, and copy a network folder and file to a network destination through this PC's own `\\localhost\C$` share.
