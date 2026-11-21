# Test results: Hiren's BootCD PE 10 and PE 11 (2026-11-21, first run)

`tests/Run-PETest.ps1` from the kit ISO, run in Hiren's on the Windows 10 VM, working on its Windows (C:, offline). PE 11 ran with the kit from before the Automation part was added; PE 10 with the kit that has it.

| | Hiren's PE 11 | Hiren's PE 10 |
|---|---|---|
| PE base | Windows 11 build 22621 | Windows 10 build 19041 |
| PowerShell | Windows PowerShell 5.1 | **only PowerShell 7.1.3** (`Y:\Programs\PowerShell Core_x64\pwsh.exe`) |
| .NET Framework | 4.8.1 | 4.8 |
| Storage cmdlets / Pester | yes / yes | no / no |
| Screen | 1024 x 768 | 1024 x 768 |

## Results

| Part | PE 11 | PE 10 |
|---|---|---|
| WinForms loads, all 9 GUI scripts open in WinPE mode, 0 errors | pass | pass (under PowerShell 7) |
| Windows found (C:, offline), boot store `C:\Boot\BCD`, clones, boot menu timeout, BitLocker "unknown" | pass | pass |
| `bcdedit /enum all` | fail - **test bug** (below) | fail - test bug |
| Offline scans read back by the summaries: DISM checkhealth + scanhealth, sfc /verifyonly /offwindir, chkdsk C: /scan | **4 / 4** | **4 / 4** (task window under PowerShell 7) |
| Mounting | refusals pass; nothing to mount (every partition had a letter) | same (diskpart only, no Storage cmdlets) |
| Window sizes at 1024 x 768 | no issues | no issues |
| Automation on the offline Windows | not in this kit | queue, offline commands, summary, HTML report, options, refusal: **pass**; every task **failed to start** (below) |
| Unit tests | beta 50 / 50, toolkit 22 / 22, stable 244 / 268 (below) | no Pester in this PE |

## Problems found, and fixed

| # | Problem | Cause | Fix |
|---|---|---|---|
| P1 | PE 10: every Automation task ended at once ("its window was closed before the task ended") | The task windows were started with `$PSHOME\powershell.exe`; under PowerShell 7 that file does not exist (`pwsh.exe`). The same applied to WinRepairTool, Monitor-Logs (fixed Windows PowerShell path) and WinFixKit's console fixes. | Windows PowerShell when it exists, else the PowerShell the tool runs in. The PE test's own task window already ran the 4 offline scans this way under PowerShell 7. Toolkit test T5. |
| P2 | PE 11 unit test: WinFixKit "Take ownership" did not refuse `C:\Windows` | Its protected folders came from the running system's environment (`%SystemRoot%`, `%ProgramFiles%`, the profile list) - in WinPE that is X:, so the offline Windows' system folders, Users, profiles and AppData were not protected. | The same folders of every Windows installation on any drive are protected too; data folders stay allowed. Checked with a stand-in second Windows; new unit test. |
| P3 | PE 11 unit test: reading an empty `.evtx` threw "The parameter is incorrect" | Get-WinEvent can throw even with `-ErrorAction SilentlyContinue` | Both log readers (WinSuperTool, ClaudeLogAnalyzer) report "could not be read here: <reason>" instead; new unit test. |
| P4 | `bcdedit /enum all` failed in both | Test bug: in WinPE the default boot store is the PE's own; the tools correctly read `C:\Boot\BCD` | The check reads the offline Windows' store |

The other stable unit tests that failed in PE 11 (protected profile folders, mount history, Dismount-One letter ownership, the live event poller) assume a running Windows with a user profile, a mount history and event logs - which a WinPE does not have. They are not tool problems; P2 also covers the folder tests' real concern.

## Second run (kit 08:55, with the fixes above)

**Automation works on the offline Windows in both PEs - PE 10 under PowerShell 7 too** (the P1 fix).

| Automation queue on C: (offline, from WinPE) | PE 11 | PE 10 (PowerShell 7) |
|---|---|---|
| A1 checks: DISM check health, DISM scan health, sfc /verifyonly, chkdsk /scan | 4 / 4 passed | 4 / 4 passed |
| A2 options: stop on fail, no popups, no HTML report | 2 / 2 passed; no popups, no report | same |
| A3 a queue with Windows Update + Defender | refused, both named with the reason | same |
| A4 repair only if needed: DISM scan-fix, SFC verify-fix, chkdsk /f | DISM and SFC passed (nothing to repair); chkdsk /f **not run** (below) | same |
| A5 full repairs: sfc /scannow, DISM restore health, component cleanup | 3 / 3 passed | 3 / 3 passed |
| Every task used the offline form, summary + HTML report name the offline Windows | yes | yes |

Also both: `bcdedit` reads the offline Windows' store (119 lines from `C:\Boot\BCD`), all offline scans 4 / 4, all 9 GUI scripts open, no window-size issues. Unit tests in PE 11: beta 54 / 54, toolkit 23 / 23, stable 260 / 270.

| # | Finding | Fix |
|---|---|---|
| P5 | chkdsk /f asked to force a dismount of C:, and the person running the test rightly answered No: **the test was writing its results and logs to C:** (a test oversight). The tool reported it correctly as "NOT RUN - the volume is in use". | The test writes to the RAM drive X: while it runs and copies the results to the Windows drive at the very end; it now checks that chkdsk /f ran straight away. |
| P6 | The same can happen to a person: WinSuperTool keeps its data and task logs next to itself, and when it is started from the Windows drive that chkdsk /f should repair, that drive is in use. | Starting a queue with "Check disk and REPAIR" warns first when the data folder is on that drive (answer N to chkdsk's question, or start WinSuperTool from a USB stick or X:). |
| P7 | The 10 stable unit tests that failed in PE 11 assume a running Windows: user profile folders (in WinPE `X:\Users\Default`, which the new protection rightly refuses), an event log WinPE can read, the live System log, and the running system drive as a real partition (X: is a RAM drive; the CD drive letter differs). | In WinPE those tests use the first real partition / an existing letter, or are skipped with the reason. Not tool problems. |

Next run (kit 10:15, both folders): A4 should now show chkdsk /f running on C:, and PE 11's stable unit tests should pass apart from the skipped ones.