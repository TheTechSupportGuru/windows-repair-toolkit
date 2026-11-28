# Diagnostic Tool Downloader 0.1 beta 1 (2026-11-27)

A beta side tool, in `beta/`. It is not part of WinSuperTool yet and does not change the toolkit's version.

- **Downloads the diagnostic tools listed on linktr.ee/stech** (everything above the "KT Links" section): 49 entries.
- **Window** (`DiagDownloader.bat` or `Get-DiagToolsGui.ps1`): tick tools, pick the save folder, click Download. Manual entries are greyed out; double-click one to open its page in your browser. Each row shows its status while the batch runs.
- **Command line** (`Get-DiagTools.ps1`): `-List`, `-Only`, `-OutDir`, `-Force`.
- **Source handling:** direct file links, GitHub release pages (the Windows asset is picked through the GitHub API), vendor pages that link to the real file (up to 3 hops, including meta-refresh pages), and Microsoft diagcab / exe pages.
- **Nothing is run.** Downloads only. Verify each file yourself before running it.

Last full run: 40 OK, 4 manual (Macrium Reflect Free, Veeam Free, Trellix Stinger, Microsoft 365 Troubleshooters), 5 failed (Sophos Scan and Clean, HWiNFO (403), WizTree, OpenNetMeter (no asset), Wireshark). Failures are listed in the README and are not retried yet.

Known limits: pages that need JavaScript or a session fail; online installers (for example Speccy's) are not turned into files; there is no hash check.
