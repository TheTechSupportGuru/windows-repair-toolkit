# Plan: from 1.9 beta 5 to the stable 1.9

Goal: test the beta thoroughly (Automation above all), promote it to the stable WinSuperTool **1.9**, and end the beta. 1.9 also carries the unreleased 1.8.4 work (window resizing, two monitors, screen changes), which all tools share.

Everything below is prepared; nothing has run yet.

## 1. Hiren's BootCD PE 10 and PE 11 results

The kit is in `F:\Hirens PE 10 Tests` and `F:\Hirens PE 11 Tests` (`WRT-PE-Test.iso`, see READ ME FIRST.txt). When `WRT-PE-share.zip` is in those folders, Claude reads both, then fixes what they show (in `tools/` and `beta/` alike), with unit tests after each fix.

## 2. Full regression on the beta (before promoting)

| Run | How | Needs |
|---|---|---|
| Unit tests | `tests\Suite.Tests.ps1`, `Toolkit.Tests.ps1`, `Beta.Tests.ps1` (in parallel) | - |
| Window sizes | `tests\Run-ResizeAudit.ps1 -Parallel` at 100 % and `-Scale 1.5` | - |
| Two monitors | `Run-ResizeAudit.ps1` monitor matrix, monitor 2 right and above | - |
| Mouse drag | `tests\Run-DragTest.ps1` | - |
| **Elevated regression** | `tests\Run-Regression.ps1` (one UAC prompt): A Live Monitor, B summaries on real scans, **C Automation, 8 real check tasks**, **C2 Automation options** (stop on fail; popups and HTML report off), D WinFixKit status checks, E WinRepairTool / Monitor-Logs / log collection / every tool as admin, F every System Info button | admin |
| **Automation repairs** | `Run-Regression.ps1 -Parts C3` - SFC / DISM "repair only if needed", DISM restore health, sfc /scannow, component cleanup | admin + **VM snapshot** |
| Automation installs (optional) | `Run-Regression.ps1 -Parts C4` - Windows Update installs updates, winget upgrades every app | admin + snapshot + your OK |
| Windows 10 | the field test again on the Windows 10 VM (where windows open at a simulated 150 % on .NET 4.8) | the Windows 10 VM |
| Real scaling (optional) | `tests\Start-ScaleTest.ps1` (3 sign-outs) | you |

Automation is covered three ways: 8 real check tasks in one queue (C), the queue options (C2), and the real repair tasks (C3) - together with the "repair only if needed" chains, the per-task popups on the tool's monitor, the final summary and the HTML report each run writes.

## 3. Promote the beta

```powershell
.\build\Promote-Beta.ps1 -Version 1.9            # dry run: lists every change
.\build\Promote-Beta.ps1 -Version 1.9 -Apply
```

It makes `tools\WinSuperTool.ps1` / `.bat` the beta without any BETA label (window title "Windows Super Tool", version header 1.9), sets every tool's header to 1.9, points the tests at `tools\`, removes the beta scripts (beta\README.md says there is no beta), and rebuilds the no-AI edition. Checked beforehand: the beta contains every function of the stable WinSuperTool unchanged (plus 54 new ones), so nothing of the stable version is lost; the dry run finds every label and leaves no "BETA" in `tools\`.

By hand afterwards: `docs/changes/V1.9.md` (from V1.8.4 + V1.9-beta.1 ... beta.5), README (current version, version table, remove the Beta section, folder list), the issue / discussion forms ("1.9 (latest)", beta versions removed).

## 4. Regression on the promoted 1.9

The same as step 2 against `tools\`: unit tests, `Run-Regression.ps1 -Script .\tools\WinSuperTool.ps1`, window sizes and monitors, the no-AI edition (toolkit test T3 rebuilds and compares it).

## 5. Release

Merge `resize-pass-2` into `main`, tag `v1.9`, release with the 8 per-tool zips (WinSuperTool, WinSuperTool-NoAI, WinFixKit, WinRepairTool, Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer, Run-PS-As-Admin), marked latest. The beta releases get a note: "replaced by 1.9". Each push and the release only after your OK.

## Decisions for you

- Release 1.9 directly, with the 1.8.4 window work inside it (planned), or 1.8.4 on its own first.
- Whether to run the Automation install tasks (C4) - they install updates and upgrade apps on the test VM.
