# Test Results: Phase 2 (launchers + read-only features)

**Date:** 2026-11-19 · **Machine:** the Windows 11 VirtualBox VM · **Version tested:** `Edited scripts\V1.2` (plus `Run-PS-As-Admin.bat` and `Monitor-Logs.ps1` from V1.1, which have no edited copy)
**How:** headless runners in `Tests\`, run once as the normal user and once as admin (one UAC prompt). The tools' data and output went to `%TEMP%\suite-phase2`. Nothing was written to the Desktop or into `Edited scripts`.

**Result: no critical or major bugs found in Phase 2.** The status checks are read-only, log collection works with 0 failures, both launchers handle tricky folder names, and all three V1.2 tools open and close cleanly as admin. One silent-failure bug (L5) was confirmed, and one new cosmetic bug was found (#19).

---

## Results

| ID | Test | Result |
|---|---|---|
| R1 | **WinFixKit "Check status": all 15 tabs, user and admin.** A snapshot was taken before and after (services, network profile, power plan, SMB settings, printers, problem devices, print-spool files, Desktop). | ✅ Every tab finishes (slowest: Windows Update ~7 s, Network ~6 s). **No setting changed.** The only difference: the BITS service switched from Manual to Auto during the run and **switched back by itself** afterwards. That's Windows reacting to `Get-BitsTransfer` starting BITS, not the tool changing anything. As a normal user, 6 tabs show some "Access is denied" lines (expected, and the tool says status works best as admin). |
| R2 | **Collect Logs (WinSuperTool collectors) on live C:**: WU, DISM/CBS, Event logs, Crashes, Setup, System info | ✅ 122 files copied, **0 failed**, ~24 s. Counts match the files on disk. Missing items are reported honestly ("not found" for crash dumps or upgrade folders this VM doesn't have). ⚠ It came to **350 MB**, mostly one 179 MB `CbsPersist` log and a 95 MB Panther log. Worth a size warning in the UI. |
| R3 | **Live Monitor:** 26 items (WinSuperTool) + 25 (Monitor-Logs) | ✅ The code generated for each window **parses cleanly** for all items. 7 targets don't exist on this VM (no dumps, no upgrade folders, Delivery Optimization log channel absent on this build). The windows wait for them instead of failing. *Actually opening each window was not done.* |
| L1–L3 | **WinSuperTool.bat and Run-PS-As-Admin.bat** with a script in folders named `plain`, `with space`, `a&b`, `it's`, `100%`, `x^y`, `(paren)`, `semi;colon`, `!bang!` | ✅ **18/18 ran the right script.** Dropping a `.txt` shows "not a .ps1 file", asks again, and then runs the valid path that's typed in. (These ran from an admin session, so they took the "already elevated" path. The UAC path is L4 below.) |
| L5 | `Launch-WinFixKit.bat` (and `Start-ClaudeLogAnalyzer.bat`, same pattern) with a **broken** or **missing** .ps1 | ❌ **Confirmed bug #20:** the .bat exits 0, PowerShell dies with exit code 1 (syntax error) or -196608 (missing file) in a **hidden** window, and **the user sees nothing at all**. |
| GUI | **Smoke test:** open each V1.2 tool as admin for 20 s, then close it normally | ✅ **WinSuperTool** and **WinRepairTool** open, start up (including the fixed mount memory, which loaded an empty list) and close with **0 errors**. ✅ **WinFixKit** opens and closes fine as user and as admin, but logs **12 startup errors → bug #19**. |

## New bugs

| # | Sev | Script | Finding |
|---|---|---|---|
| 19 | S4 | WinFixKit (V1.1 and V1.2) | `Add-BottomButton` has a parameter `$Tip`. PowerShell variable names ignore case, so it **hides the global `$tip` ToolTip object**, and `$tip.SetToolTip(...)` fails at line 2021 (12× MethodNotFound at startup). The bottom-bar buttons have **no tooltips**. Fix: rename the parameter (e.g. `$TipText`). |
| 20 | S3 | Launch-WinFixKit.bat, Start-ClaudeLogAnalyzer.bat | They start PowerShell with `-WindowStyle Hidden`, so any startup failure is invisible: no window, no message, the .bat exits 0. Fix: start without hiding (the GUI can hide its own console), or wrap the call in a try/catch that shows a MessageBox. |
| 21 | S4 | WinFixKit | Status "Microsoft Account" runs `whoami /upn`, which prints a full red PowerShell error on local (non-Microsoft) accounts. It should say "local account – no UPN". |

## Phase 2 items still open (need you at the VM, or a later pass)
- **L4:** double-click `WinSuperTool.bat` and click **No** at UAC. Expected: "Launch cancelled" plus a pause, and no stuck window.
- **R4:** Sysprep tab → **pre-flight only** (don't start sysprep).
- **R5:** Recovery tab read-only tools (`chkdsk /scan`, list third-party drivers, `bootrec /scanos` → should say "not available").
- **R6:** set display scaling to 150% / 200% and look at each window.
- **R3 (visual):** open a few Live Monitor windows, close the tool, and check that no windows are left behind.

## Re-run
Each command below is one line:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-StatusChecks.ps1 -OutDir $env:TEMP\suite-phase2
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Check-MonitorItems.ps1
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-ElevatedPhase2.ps1
```

`Run-ElevatedPhase2.ps1` must be run as admin.
