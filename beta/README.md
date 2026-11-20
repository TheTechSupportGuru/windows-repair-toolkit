# Beta builds

> [!CAUTION]
> **These are test builds, not the stable release.** They have had less testing than the tools in [`tools/`](../tools/) and may get results wrong. Use them on a test machine first, and keep the stable version for real repairs.

## WinSuperTool 1.9 beta 1

`WinSuperTool.ps1` + `WinSuperTool.bat`, based on 1.8. The new parts are all on the **Recovery** tab:

- **Show a pass / fail summary when it ends**: on by default.
  - Says whether the task **passed or failed**, and what it found (for example "NO CORRUPTION DETECTED" or "CORRUPTION DETECTED - FIX WORKED").
  - Quotes the tool's own result message.
  - Saves the full output to `WinSuperTool-Data\Task-Results`.
- **Monitor this task's logs**: opens live windows for the logs the tool writes (`CBS.log` for sfc, `dism.log` for DISM, `setupapi.dev.log` for driver tools).
- **New scan-only tools**: `sfc /verifyonly`, DISM check health, DISM scan health.

Details and test results: [docs/changes/V1.9-beta.1.md](../docs/changes/V1.9-beta.1.md).

Known limits:
- Result messages are matched in English. On another display language, the summary uses the exit code.
- With the summary on, the task opens in a classic console window, not Windows Terminal.
- Not tested yet: an elevated run that actually scans or repairs, WinPE, Windows 10, non-English Windows.

Found a wrong result? Open a [bug report](https://github.com/TheTechSupportGuru/windows-repair-toolkit/issues/new?template=1-bug-report.yml) with version **1.9 beta 1**.
