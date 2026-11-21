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

## Next

Run the kit again (ISO written 08:55, both folders): PE 11 for the Automation part, PE 10 for the Automation tasks under PowerShell 7.
