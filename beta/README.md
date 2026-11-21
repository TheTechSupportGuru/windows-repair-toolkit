# Beta: WinFixKit with Automation

`WinFixKit-beta-automation.ps1` (start it with `Launch-WinFixKit-beta-automation.bat`) is **WinFixKit 1.9 plus an Automation tab**. It's a queue of up to 10 of WinFixKit's status checks and fixes, run one after another. Each task runs in its own window with a pass / fail result, and there's a final summary and an HTML report. The tab is a port of WinSuperTool 1.9's Automation tab. Notes: [WinFixKit-1.9-beta-automation.1](../docs/changes/WinFixKit-1.9-beta-automation.1.md).

- **It's a beta.** The stable WinFixKit in [tools/](../tools) is unchanged. The beta keeps its data in the same `Desktop\WinFixKit` folder, plus `Task-Results`.
- **Automation needs administrator rights** (use "Relaunch as Administrator") and a running Windows, so it isn't available in WinPE.
- **Automation is changed in WinSuperTool first, then ported here** with `build/Port-AutomationToWinFixKit.ps1`. See [CONTRIBUTING.md](../CONTRIBUTING.md).

WinSuperTool's beta (1.9 beta 1 ... beta 5) became the stable **1.9** on 2026-11-21: see [V1.9](../docs/changes/V1.9.md).
