# 7z-Encryptor 1.5 (2026-11-26)

Part of the toolkit's 2.5 release.

- **7-Zip is found in Windows PE.** In Windows PE (Hiren's BootCD PE 10 / 11 and others) the tools also look for 7-Zip on the X: and Y: drives, up to 3 folders deep, and in the PATH (the same search as Backup Script Builder 1.8). On a normal Windows the X: and Y: drives are not searched (they may be network drives). The search skips Windows, boot and system folders and stops after 4000 folders.
- **Remember settings keeps 7z or zip.** With Remember settings ticked, the format is saved as soon as you pick it, and the window opens with it next time. Anything other than zip in the file means 7z.
- **Drag and drop from Explorer:** files and folders dragged onto the list are added, like Add Files/Folders: never twice, not the tool's own files, and an item that is not there is skipped. Save as follows them as usual.
- The **?** texts: Files and folders mentions dragging; 7-Zip says where the tool looks; Remember settings lists 7z or zip.

Tested: 8 new Pester tests for the search (Hiren's-style folder, drive root, shallowest first, 3 folders deep and not 4, skipped folders, missing drive, folder limit, PE only); 93 / 93 checks of `tests/Run-7zEncryptor.ps1` (8 new: zip and 7z saved when picked; a remembered zip, 7z or unknown value opens the window with the right format; dragging onto the list through the real handlers: added, the tool itself and a missing file skipped, never twice, text refused, Save as follows).