# Beta builds

> [!CAUTION]
> **These are test builds, not the stable release.** They have had less testing than the tools in [`tools/`](../tools/) and may get results wrong. Use them on a test machine first, and keep the stable version for real repairs.

## WinSuperTool 1.9 beta 2

`WinSuperTool.ps1` + `WinSuperTool.bat`, based on 1.8.

- **Recovery tab:**
  - **Pass / fail summary.** Says whether the task passed or failed and what it found, in the tool's own words.
  - **Monitor this task's logs.** Live windows for the logs the task writes.
  - **Scan-only tools:** `sfc /verifyonly`, DISM check health and scan health.
- **9. System Info.** Easy-to-read windows with Copy and Save buttons, for:
  - Wi-Fi networks and passwords;
  - Windows version and product keys;
  - network connections;
  - Bluetooth devices;
  - video cards;
  - audio devices.

  Plus 42 buttons for the built-in Windows tools.
- **10. Automation.** Up to 10 tasks run one after another, in the order you set:
  - a restore point, SFC, DISM (repair only if needed), chkdsk, Windows Update, winget and a Defender scan;
  - a summary after each task, and a final summary.

What changed and what was tested:
- [docs/changes/V1.9-beta.2.md](../docs/changes/V1.9-beta.2.md)
- [docs/changes/V1.9-beta.1.md](../docs/changes/V1.9-beta.1.md)

Known limits:
- Result messages are matched in English. On another display language, the summary uses the exit code.
- Task windows open as classic console windows, not Windows Terminal, so their whole output can be read back.
- Automation runs on the running Windows only, not in WinPE.
- **Not tested yet:**
  - the repair, corruption-found and update-install results (the test VM is healthy and was only scanned);
  - real Wi-Fi and Bluetooth hardware (the VM has neither);
  - WinPE;
  - Windows 10;
  - non-English Windows.

Found a wrong result? Open a [bug report](https://github.com/TheTechSupportGuru/windows-repair-toolkit/issues/new?template=1-bug-report.yml) with version **1.9 beta 2**.
