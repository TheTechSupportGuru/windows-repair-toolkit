# Backup Script Builder 1.0 (2026-11-22)

A new tool, `tools/BackupScriptBuilder.ps1` (start it with `tools/BackupScriptBuilder.bat`). It builds backup jobs for **[FreeFileSync](https://freefilesync.org/)**, the free open source folder sync tool, and schedules them in Task Scheduler. It needs FreeFileSync installed to run the backups, and nothing else beyond Windows itself (PowerShell 5.1 and WinForms). Backup Script Builder has its own version number.

## Build Script tab
- **Source folders:** "Add Folders..." opens a tree of every drive with a tick box per folder (it opens at `C:\Users`). Tick as many as you like. Each folder becomes one folder pair in the script.
- **Destination folder:** any folder (Browse... or type it). The tool creates `<folder>\AutomaticFileBackups` with:
  - `Current\<folder name>` - the mirror of each source folder
  - `Archive-Deleted\<folder name>` - deleted and changed files, in time-stamped folders (FreeFileSync versioning)
  - `Logs` - FreeFileSync's log of each run
  - `BackupScript.ffs_batch` - the batch job
- **Keep days:** how long archived files are kept (the script's `MaxAge`, 365 by default).
- Same-name folders (two users' `Documents`) get `-2`, `-3`, a drive root becomes `<letter>-Drive`, and `&` and other XML characters are escaped.
- Refuses a destination inside a source folder, and asks before overwriting an existing script.
- The script is written in exactly the layout of a FreeFileSync 14 batch file (`XmlFormat="23"`): mirror left to right, compare by time and size, symlinks excluded, the usual system folders and `thumbs.db` / `desktop.ini` filtered out, errors ignored, logs kept.

## Schedule Task tab
- **Task** dropdown: `<New task>` or any task this tool made. Selecting one loads all its settings to change (**Save Changes**), **Run Now** or **Delete Task**.
- All tasks live in their own Task Scheduler folder, **`\BackupScriptBuilder\`**, so the tool only ever lists and changes its own tasks. Renaming a task replaces the old one.
- **Backup script:** the script just built, the scripts of existing tasks, or Browse... for any `.ffs_batch`.
- **FreeFileSync.exe:** `C:\Program Files\FreeFileSync\FreeFileSync.exe` by default, with Browse... The task runs it with the script as its argument.
- **Schedule:** Once, Daily (every N days), Weekly (ticked days, every N weeks), Every X hours, At log on.
- **Run as soon as possible after a missed start** (on / off).
- **Stop task after:** no limit, 30 minutes, 1 / 2 / 4 / 8 / 12 hours, 1 or 3 days.
- Tasks run as the current user while logged on; no password is stored and no admin rights are needed.

## Like the other tools
- A **?** next to every option: hover for a tooltip, click for the full explanation.
- The shared window helpers: sharp at 125-200 % scaling, splash screen, fits the screen.
- A link to https://freefilesync.org/ at the bottom of the window.

## Tests
`tests/Run-BackupScriptBuilder.ps1` (28 checks, no clicking, about 10 s): the built script against a reference FreeFileSync file line for line, CRLF and no BOM, same-name folders and XML escaping, the folders it creates, every schedule type created / read back / deleted, the real Create / Save / rename / Delete buttons, a missing script refused, no overlapping controls, help text on every **?**. `tests/Toolkit.Tests.ps1` covers it as the 8th GUI tool (license header, ASCII, identical window helpers, splash).

Not tested yet: a real FreeFileSync run started by a scheduled task, Windows 10, and the window at 150 % / 200 % scaling.
