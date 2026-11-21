# Remaining tests: what is left, and how to run each one

Everything that could be tested from inside the test VM has been tested (see [TEST-RESULTS-multimonitor.md](TEST-RESULTS-multimonitor.md) and [TEST-RESULTS-regression-2026-11-20.md](TEST-RESULTS-regression-2026-11-20.md)). This page lists what is left, easiest first. Each test that could be scripted has a kit in `tests/`; the rest need hardware, an account or a decision.

| # | Test | Effort | What it needs | Kit |
|---|---|---|---|---|
| 1 | Main monitor at real 150 % and 200 % | easy: 3 sign-outs | the test VM | `tests/Start-ScaleTest.ps1` |
| 2 | Another PC: Windows 10, Windows in another language, a physical PC, real Wi-Fi and Bluetooth | easy: double-click | that PC | `tests/Run-FieldTest.cmd` |
| 3 | WinFixKit: apply every fix, then undo it | easy, but **snapshot first** | the test VM + a VirtualBox snapshot | `tests/Run-FixUndoTest.cmd` |
| 4 | AI Analyze with a real API key; phone pairing by QR code | medium | an API key with a spend limit; a phone on the same Wi-Fi | steps below |
| 5 | Repair results on a damaged Windows (SFC / DISM actually repairing) | advanced | a snapshot, and deliberate damage | not prepared, see below |
| 6 | WinPE (Hiren's BootCD PE): the tools working on a Windows that is not running | medium: attach an ISO, double-click | Hiren's BootCD PE + the kit ISO | `tests/Run-PETest.ps1` (kit ISO built from it) |

**Done since the last list:** dragging windows between monitors with the mouse is now automated (`tests/Run-DragTest.ps1`, real mouse, button held across the edge) and passed for Collect-Logs, WinSuperTool and the beta. Run against the code from before the M1 fix, the same test catches the window being pulled away while the button is held, so it would notice if that bug came back.

---

## 1. Main monitor at real 150 % and 200 %

Why it needs you: the tools take the main monitor's scaling only when Windows starts your session, so each step needs a sign-out. Signing out also closes the Claude app, which is why the script carries on by itself.

1. Save your work and close other programs.
2. In PowerShell, in the repo folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tests\Start-ScaleTest.ps1
   ```
3. It sets the main monitor to 150 % and asks **Sign out now?** Answer Yes.
4. Sign in again and **do not use the mouse or keyboard** (about 15-25 minutes). The tools' windows open and close by themselves.
5. It asks to sign out again for 200 %: Yes. Same again.
6. At the end it puts your scaling back, opens the results in Notepad and asks for one last sign-out.

Results: `C:\Users\Public\wrt-scale-test\summary.txt`. Pass when every line says "No issues found". To stop at any point: run the same command with `-Step cancel`.

## 2. Another PC (Windows 10, another language, physical PC, Wi-Fi and Bluetooth)

One kit covers all of these; run it on each PC you can (a laptop covers Wi-Fi and Bluetooth). It changes nothing apart from one test event in the "Windows PowerShell" event log.

1. On that PC: GitHub > the repo > switch the branch to `resize-pass-2` > **Code > Download ZIP**. Unzip it anywhere.
2. In the unzipped folder, open `tests` and double-click **Run-FieldTest.cmd**. Answer **Yes** to the admin prompt (No runs the part that does not need admin).
3. Wait 20-40 minutes; do not use the mouse while tool windows open and close by themselves.
4. A folder `WRT-FieldTest-<date>` opens on the Desktop:
   - `private\` - everything unmasked (product keys, Wi-Fi passwords, addresses). Keep it to yourself.
   - `WRT-FieldTest-share.zip` - the same with private details masked (PC and user name, keys, addresses, Wi-Fi network names and passwords, Bluetooth device names). Look through it, then send it to Claude.

What it checks: the PC (Windows version and language, physical or virtual, Wi-Fi / Bluetooth hardware, monitors and scaling), the unit tests, all six System Info parts, window sizes on that screen, real read-only scans (DISM, chkdsk, sfc) read back by the summaries, and the Live Monitor. On Windows in another language the summary says whether a result was recognised from Windows' wording or decided by the exit code.

Wi-Fi and Bluetooth on the test VM instead: plug a USB Wi-Fi or Bluetooth stick into the host and give it to the VM (VirtualBox: Devices > USB > the stick), then run the field test in the VM.

## 3. WinFixKit: apply every fix, then undo it

This test **really changes the PC** (registry, services, firewall, sharing) and undoes each change with WinFixKit's own backups. In earlier versions every undo was exact, but it must only run on the test VM with a snapshot to fall back on.

1. On the host (the real PC, not inside the VM): VirtualBox > select the VM > **Machine > Take Snapshot**, name it `before-fix-undo`.
2. In the VM: double-click `tests\Run-FixUndoTest.cmd`, type `YES`, answer Yes to the admin prompt.
3. It runs 42 fixes one after another (about 10 minutes) and compares the PC before and after each undo.

Results: `%TEMP%\suite-phase3\summary.txt`. Pass when every fix says the state is back to the baseline. If anything looks wrong: restore the snapshot (VirtualBox > Snapshots > `before-fix-undo` > Restore). Not included, as before: network resets (they cut the network and need a restart) and the long console fixes.

## 4. AI Analyze and phone pairing

Not scripted: they need a paid account and a phone.

**AI Analyze** (WinSuperTool, tab 3; the no-AI edition does not have it):
1. Create an API key with a **$5 spend limit** (Anthropic Console, or Google AI Studio for Gemini). Use it only for this test.
2. WinSuperTool > tab 1 Collect Logs: collect a small category (for example System).
3. Tab 3 AI Analyze: paste the key, pick the collected log, start the analysis.
4. Pass when an answer comes back that talks about that log, and the key is not in the activity log or the saved files (search `WinSuperTool-Data` for the first 8 characters of the key).
5. Delete the key in the console afterwards.

**Phone pairing by QR code:** the VM's network must be reachable from the phone: VM settings > Network > Adapter 1 > **Bridged Adapter** (switch back to NAT afterwards). Then in tab 3 show the QR code, scan it with a phone on the same Wi-Fi, and allow the Windows Firewall prompt for **private** networks only. Pass when the phone page opens and an analysis started from the phone shows its result.

## 5. Repair results on a damaged Windows

The Recovery and Automation summaries for "corruption found and repaired" are tested with Windows' real wording (unit tests B2-B8), but never on a PC that really was damaged: the test VM is healthy. A real test means deliberately damaging system files in a snapshotted VM, then running SFC / DISM repair through the tool. Not prepared yet, because it is the riskiest test; ask Claude to prepare it when a snapshot can be taken.

## 6. WinPE (Hiren's BootCD PE)

The tools have a WinPE mode: they work on a Windows that is not running (offline repair). `tests/Run-PETest.ps1` tests it, read-only:

- the PE itself: WinPE or not, PowerShell / .NET / WinForms, the Windows tools the toolkit calls, disks;
- which Windows installations the tools find;
- the boot configuration of the offline Windows (bcdedit, clones, boot menu timeout, BitLocker), every question answered No;
- real offline scans read back by the summaries: `DISM /image: /checkhealth` and `/scanhealth`, `sfc /verifyonly /offwindir`, `chkdsk /scan`;
- every GUI tool started for 20 s, a short resize audit, and the unit tests if Pester is in the PE.

A ready kit is built as an ISO (WinPE usually cannot see VirtualBox shared folders): attach `WRT-PE-Test.iso` as a second CD drive of the VM, boot Hiren's, double-click `Start-PETest.cmd` on that CD. It copies itself to the RAM drive X: (a CD is read-only and the tools write data next to themselves) and writes its results to `WRT-PE-Results-<date>` on the Windows drive, so they are there after booting Windows normally. Send `WRT-PE-share.zip` (masked) from that folder. If the PE has no PowerShell the launcher says so and stops.