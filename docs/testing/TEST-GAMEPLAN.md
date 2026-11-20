# Script Suite Test Plan: this VM only

**Scope:** only tests that can run on this one Windows 11 VirtualBox VM. Anything that needs other hardware, WinPE, BIOS/MBR, a second Windows install or another language is listed in §9 as **not covered**.

> **Status (2026-11-19):** Phase 0 and Phase 1 are done, except U9 (QR decode). Results: [TEST-RESULTS-Phase0-1.md](TEST-RESULTS-Phase0-1.md). 147 unit tests: 127 passed, 20 failed. PSScriptAnalyzer: 0 errors, 250 warnings (3 of them real issues). In total: 1 S1, 5 S2 and 12 lower-severity bugs. **The S1/S2 bugs are fixed** (WinFixKit, WinSuperTool, WinRepairTool V1.1; originals kept in `_originals-2026-11-19`), and 167/173 unit tests now pass. **Phase 2 mostly done** on V1.2 ([TEST-RESULTS-Phase2.md](TEST-RESULTS-Phase2.md)): no S1/S2 bugs; new #19 (S4), #20 (S3), #21 (S4). L4, R4, R5 and R6 still need someone at the VM. Edited versions live in `Edited scripts\V<x.y>` with a CHANGES.md each. **V1.3** fixes all remaining known bugs (#7–#21) and passes all 208 unit tests. Its admin GUI smoke test passed: 5 tools, 0 errors. **Phase 3 part 1 done** ([TEST-RESULTS-Phase3.md](TEST-RESULTS-Phase3.md)): 42 WinFixKit fix runs plus the Service Killer as admin. Every undo was exact, the protection rules held on the live system, and there were no S1/S2 bugs. New minor bugs #22–#24. **Phase 3 part 2 (WinSuperTool 7c–7g) done:** Mount, Safe Mode, Unattend, Recovery and pre-flight mostly pass. **New S1 #28:** "BCD: restore from backup" (`bcdedit /import`) fails on this UEFI VM and leaves the boot store unloaded until a reboot (needs checking on a physical PC). New S2 #26 (diskpart mounts forgotten; caused by V1.2 fix #3), plus S3 #25 and S4 #27. **V1.4** ([CHANGES](../changes/V1.4.md)) fixes #25–#30. #30 was a V1.2 regression that blocked all BCD changes in WinPE. 222/222 unit tests pass, and every admin check of the fixes passed. **V1.5** ([CHANGES](../changes/V1.5.md)) fixes #22–#24 in WinFixKit, verified as admin; 229/229 unit tests pass. **All known bugs #1–#30 now have a fix in V1.5.** **Network resets done** (Phase 3 part 3): the network works after reset + reboot and after undo + reboot. New minor bugs #31 (S3: a successful registry restore shows an error block), #32 and #33 (S4) are **fixed in V1.6** ([CHANGES](../changes/V1.6.md); 234/234 unit tests). **All 33 known bugs now have a fix.** **V1.7** ([CHANGES](../changes/V1.7.md)) adds a logic and optimization pass over WinFixKit + WinSuperTool from 4 parallel code reviews ([REVIEW-V1.6.md](REVIEW-V1.6.md): 85 findings). It fixes ~50 of them and 9 more found by testing: the windowed fixes and a full log-generation run. 250/250 unit tests pass, and 19/19 admin checks plus the log run pass. **V1.8** ([CHANGES](../changes/V1.8.md)) ports the fixes to WinRepairTool, Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer and the launchers. It also closes R16 and R18 in both Windows tools. 286/286 unit tests pass, 9/9 admin checks pass, the log run has 0 failures (standalone Collect-Logs too), and all 5 GUIs pass the smoke test. **Newest complete set: `Edited scripts\V1.8`.** Still open: K16/S12/R10 (UI-thread work) and R14. Still to test: a live BCD import on a physical UEFI PC, real WinPE, and the windowed fixes (DISM+SFC, chkdsk, re-register all apps).

A **critical bug** is one that does any of these:
- leaves the VM unbootable or loses data,
- makes a change the tool's own undo can't reverse,
- runs a destructive command the user didn't pick, or acts on the wrong disk or partition,
- leaks an API key or opens a network port the user didn't intend.

---

## 1. The test machine (checked 2026-11-19)

| Item | Value | What it means for testing |
|---|---|---|
| Platform | **VirtualBox** VM, 4 vCPU, 8 GB RAM, Guest Additions installed | Snapshots must be taken **from the VirtualBox host** (Machine → Take Snapshot). They can't be taken from inside the VM. |
| OS | Windows 11 Pro **build 26300 (Insider)**, 64-bit, en-US | Newer than what most users run. Sysprep often refuses to run on Insider builds. |
| Firmware / disk | **UEFI**, one 40 GB **GPT** disk: EFI, MSR, C: (11 GB free), 2 recovery partitions. D: is a CD (UDF). | We can test the UEFI paths only. Mount tests need a second virtual disk (see §2). |
| Windows installs | 1 | "Multiple installs detected" can't be tested |
| Account | a local admin account, running **unelevated** (UAC prompts on) | Every elevated step needs someone to click **Yes** on a UAC prompt |
| Network | VirtualBox **NAT** ([redacted]), network profile = **Public**, internet OK | **A phone on your Wi-Fi can't reach this VM**, so QR pairing needs a host change (§2) |
| Devices | Printer: only *Microsoft Print to PDF*. 2 audio endpoints. No battery. | Some fixes can only be tested for their "nothing to do" path |
| Tools on board | PowerShell 5.1, **Pester 3.4** (unit testing). No PSScriptAnalyzer, no Windows Sandbox, no `bootrec` (it only ships with WinRE). | |
| Restore points | 0 | VirtualBox snapshots are the safety net |

---

## 2. One-time setup (you, on the VirtualBox host)

1. **Take a snapshot called `00-clean-baseline`** before any test that changes the system.
2. **Optional but recommended:** attach a second blank 2 GB VHD (Settings → Storage → SATA → Add hard disk). Then initialise it in Disk Management with two small partitions and no letters. This gives the Mount tests a target that isn't the system disk.
3. **Optional, only for the QR phone-pairing test:** switch the network adapter from NAT to **Bridged**. Switch it back afterwards.
4. Get a throwaway Claude or Gemini API key with a $5 spend limit, only for §8. Revoke it when done.

---

## 3. Who does what

| Who | Can do |
|---|---|
| **Claude** (this session) | Static analysis. Pester unit tests that pull individual functions out of the scripts and test them **without opening the GUI**. Read-only system checks. Starting scripts. Before/after diffs (registry exports, service states, BCD exports). Reading logs. |
| **You** | Taking and restoring snapshots. Clicking **Yes** on UAC prompts. Clicking buttons in the WinForms windows. Rebooting. Confirming the VM boots afterwards. |
| Optional | Claude can drive the GUI with **computer use** (screen control) if you turn it on, instead of you clicking. |

---

## 4. Phase 0: static checks (Claude, no execution, about 1 hr)

| ID | Check | Pass when |
|---|---|---|
| S1 | Parse every script | 0 errors ✅ (done) |
| S2 | PSScriptAnalyzer (**needs your OK to download it from the PowerShell Gallery**) | No Error-level findings, and every warning has a decision |
| S3 | Review every destructive call site: diskpart, bcdedit, bcdboot, bootrec, sysprep, `chkdsk /f`, `Remove-Item`, `reg add/delete`, `Set-Service`, `taskkill`, `pnputil /delete-driver`, `wusa /uninstall` | Each one asks for confirmation, uses the target the user picked, and writes a log line |
| S4 | Diff the duplicate scripts against WinSuperTool's copies of the same functions | Shows where a fix in one copy is missing from the other |
| S5 | Grep the code for places the API key could reach a log, file or `$Error` | None |

## 5. Phase 1: unit tests with Pester (Claude, no system changes)

Each function is pulled out of its script (via the PowerShell parser), loaded alone, and tested. **This is the cheapest way to find logic bugs.** It also covers some things this VM can't test for real: the locale and BIOS/MBR parsing paths, run against sample text.

| ID | Function | Tests |
|---|---|---|
| U1 | diskpart allow-list `$DpAllow` / `Invoke-Diskpart` | `clean`, `format`, `delete partition`, `create`, `convert`, `select disk 0` + `clean`, mixed case, extra spaces, embedded newline → all **blocked**. The allowed commands still pass. Uses a stubbed `diskpart.exe`, so nothing runs for real. |
| U2 | `ConvertFrom-BcdText` / `Get-BcdAll` | English output from this VM. **German and French sample output** (likely breaks). Output with several entries. An offline `/store` |
| U3 | Parsing of diskpart `list disk / list partition` text | English plus a non-English sample. Disk numbers ≥ 10. |
| U4 | `Invoke-Bcd` backup trigger | Calls the backup for `/set /copy /delete /deletevalue /import`. Shows that `/default`, `/displayorder` and `/bootsequence` **skip the backup** (suspected gap). |
| U5 | `Build-Unattend` / `Write-Xml` | Values containing `& < > " '` and non-ASCII characters produce **valid XML**. Checks whether the password is stored in plain text. |
| U6 | WinFixKit `Backup-RegValue` / `Set-RegValueSafe` / `Restore-RegBackup` | Run against a **throwaway HKCU test key**: an existing value, a missing value (restoring it must **delete** the value), each value type, running restore twice |
| U7 | `Rename-WithStamp`, `Get-FolderSizeMB`, `ConvertTo-RegExePath` | Paths with spaces, a path that doesn't exist, a locked file |
| U8 | Service Killer `$KillCritical` list plus the `sc queryex` PID parsing | Covers RpcSs, DcomLaunch, LSM, EventLog, Winmgmt, CryptSvc, WinDefend, etc. PID parsing breaks on non-English `sc` output. |
| U9 | QR encoder (`New-QrMatrix`) | The generated QR decodes back to the same text, checked with a decoder in the browser pane |
| U10 | Quoting helpers `Esc`, `Esc-Sq` (Monitor) | Paths with `'`, `$`, `` ` `` and spaces can't inject commands into the spawned window |
| U11 | `Get-InteractiveUser`, `Get-DefaultLogRoot` | Return this VM's real Desktop |

## 6. Phase 2: launchers and read-only features (low risk)

| ID | Test | Who | Pass when |
|---|---|---|---|
| L1 | Each .bat from this folder (its path has spaces) | Claude starts it, you click UAC | The window opens |
| L2 | `WinSuperTool.bat` / `Run-PS-As-Admin.bat` with a copied test .ps1 at paths containing `&  '  %  ^  ( )` | Claude | Runs the right file or shows a clear error |
| L3 | Non-.ps1 file, then a missing file | Claude | Asks again with a clear message |
| L4 | Click **No** at UAC | You | Exits cleanly, no stuck window |
| L5 | Hidden-window launchers with a deliberately broken script | Claude | **Expected bug:** nothing appears and there's no error |
| R1 | WinFixKit: all 14 **Check status** buttons, unelevated and elevated | Claude runs the status scriptblocks headlessly, then you do a GUI spot-check | No errors. Registry export and service list are identical before and after. |
| R2 | Collect Logs (standalone and WinSuperTool tab 1) on this live system | You click, Claude verifies | `Desktop\logs` gets filled. The reported counts are honest. C:\Windows is untouched. |
| R3 | Live Monitor (standalone and tab 2): launch every item | You | Each window opens. Missing logs are handled. Nothing is orphaned after closing. |
| R4 | WinSuperTool Sysprep **pre-flight only** | You | Accurate report, sysprep isn't started |
| R5 | Recovery read-only: `chkdsk /scan`, list third-party drivers, `bootrec /scanos` | You | chkdsk and the driver list work. bootrec shows the **"missing from this system" hint**, not a crash. |
| R6 | 150% and 200% display scaling (change it in Settings) | You | WinForms windows are still usable |

## 7. Phase 3: fixes that change the system (**snapshot before each group**)

Loop for each fix: **Claude captures BEFORE** (`reg export` of the touched keys, `Get-Service`, `bcdedit /enum all`, `ipconfig /all`) → **you click the fix** → **Claude captures AFTER and diffs it** → reboot if needed → use the tool's **Restore** → Claude diffs against BEFORE (must match) → restore the snapshot.

### 7a. WinFixKit (snapshot `10-winfixkit`)
| Priority | Buttons | Notes for this VM |
|---|---|---|
| **1** | SMB Methods 1–3 (insecure guest, signing off); Printer Fix 1 (`RpcAuthnLevelPrivacyEnabled=0`); Fix 3; "Apply 1+3" | **They weaken security.** Restoring must bring back the exact original state, including **deleting** values that didn't exist before. |
| **1** | Printer Fix 2: remove KB5025221 | The KB isn't on build 26300, so test the "not installed" path |
| **1** | Take ownership + reset permissions | Point it at a **test folder**. Then **try `C:\`, `C:\Windows`, `C:\Users`**: it must refuse or strongly warn. Click **No** at the confirmation. |
| **1** | Set Public → Private | This VM *is* Public, so it's a real test. Then restore. |
| **1** | Registry Backups tab: full backup, restore one item, restore after restarting the tool | |
| 2 | Network: flush DNS, ARP, DHCP renew, WinHTTP reset, Winsock, TCP/IP, **FULL reset** + reboot | The VM must still reach the internet afterwards. Claude's session may drop, so do this group last. |
| 2 | Discovery services and firewall rules, SMB service restart | |
| 2 | Re-register Start, Store, ALL apps; tile DB (Win10-only → should say so) | Start menu and Settings still open afterwards |
| 2 | Search: restart, **rebuild index**. Power: restore default plans, set Balanced. Battery report (**no battery** path). Energy report. | |
| 3 | Services and caches: Explorer restart, Recycle Bin, Spooler restart, clear print queue, audio restart, re-enable audio and devices, rescan, export drivers, identity services, clock resync, token cache, wsreset, Store licensing | Batch these per tab |
| 3 | Windows Update reset, scan, DISM+SFC, delete .bak_ folders | DISM+SFC takes 15–30 minutes. Needs about 5 GB free; C: has 11 GB. |
| — | Run any fix **unelevated** | Clear "needs admin" message, not a half-applied change |

### 7b. Service Killer (snapshot `20-killer`)
Pick only safe targets: `Spooler`, `WSearch`, `FDResPub`.
- Enter RpcSs, LSM or EventLog → **REFUSED**.
- Shared svchost service with "allow shared" off → refused.
- STOP with "start again" checked → the services come back.
- Close the window mid-run → killing stops.
- Interval 0 / 1 ms → clamped, no CPU lock.

### 7c. Mount (snapshot `30-mount`; better with the second VHD from §2)
- Mount and unmount the **EFI** and **recovery** partitions on disk 0, in **both** diskpart mode and Storage-cmdlet mode.
- A letter that's already in use (C:, D:) → refused.
- Remembered mounts: mount → close → **detach the second VHD on the host** → reopen. The tool must not act on the wrong partition.
- After every test, Claude confirms with `Get-Partition` that no letter or partition was left changed.

### 7d. Safe Mode / BCD (snapshot `40-bcd`)
- **Edit-entry mode**: Enable → reboot (safe mode) → Remove flag → reboot (normal).
- **Clone mode**: Create → check the boot menu → Delete clones. Only `[WinRepairTool]` entries may be removed. Claude diffs `bcdedit /enum all` before and after.
- A BCD backup file exists for each change. `bcdedit /import` of the backup restores the store exactly.

### 7e. Unattend (snapshot `50-unattend`)
- Build with every option, preview, **save to a test folder**. Claude validates the XML.
- Deploy to this live install: a `.bak_` copy of the existing file is made first. **Restore the snapshot afterwards.** A stray `unattend.xml` affects future sysprep and setup.

### 7f. Recovery tools that write (snapshot `60-recovery`)
- `DISM /online /restorehealth`: runs, gets logged.
- `chkdsk C: /f`: should offer to **schedule** the check at reboot; reboot and confirm.
- `bcdboot C:\Windows /s <EFI letter> /f UEFI` on the healthy VM: BCD is rebuilt and the VM still boots.
- **Break-and-fix (optional):** mount EFI and rename `\EFI\Microsoft\Boot\BCD`. Reboot, which should fail. Restore the snapshot. *Repairing it from inside isn't possible here without WinPE (see §9).* Only the "doesn't make it worse" side gets tested.
- `/fixmbr` and `/fixboot`: bootrec isn't present, so confirm the hint. Check whether the tool warns that `/fixmbr` is wrong for a GPT disk.
- Driver removal: **skip** unless there's a harmless oem driver. VBox Guest Additions drivers are oem*.inf and removing them breaks the display and mouse.

### 7g. Sysprep (snapshot `90-sysprep`, **last test, optional**)
- Cancel at the confirmation → nothing runs.
- B1 Audit mode → reboot → B2 OOBE. **Expect it may fail on Insider build 26300.** The pass is the tool **reporting the failure clearly** (setupact.log in Panther).
- A Generalize ends this VM's usable state. Run it only if you're fine restoring the snapshot afterwards. Claude's session won't survive it.

## 8. Phase 4: AI Analyze / QR pairing security

| ID | Test | Pass when |
|---|---|---|
| A1 | Show the QR code. Claude lists the listening ports (`Get-NetTCPConnection -State Listen`) | The listener is on `0.0.0.0:<random>` (all interfaces; **flag it**). It closes after pairing, after the 5-minute expiry, after **5 bad tokens**, and when the window closes. |
| A2 | Claude connects to the port from inside the VM with a wrong token, an oversized body and a slow, never-finishing request | Rejected. **The GUI doesn't freeze.** |
| A3 | Firewall prompt on first run (network is Public) | Note what Windows offers and what gets allowed |
| A4 | Real phone pairing | **Needs Bridged networking (§2)**, otherwise skip |
| A5 | Claude and Gemini requests: small log + screenshot, then a 200 KB log (over `$MaxLogChars`), then a bad key | Works. Truncates. Shows a readable 401/413/429 error. |
| A6 | After the session, Claude searches `%TEMP%`, the script folders, logs and PowerShell history for the key | Not found |
| A7 | 60-minute expiry | Key is cleared and pairing is needed again |

---

## 9. NOT covered on this VM (needs other setups later)

- **WinPE / Hiren's PE**: offline log collection, offline BCD `/store`, offline DISM, offline Unattend deploy, real boot repair
- **BIOS/MBR systems**: `bcdboot /f BIOS`, `/fixmbr`, `/fixboot`
- **Two Windows installs**: "multiple installations" detection and the target picker
- **Non-English Windows**: only covered by sample-text unit tests (U2, U3, U8), not by a real install
- **Windows 10**: Win10-only buttons
- **Real printers, printer shares, NAS / SMB peers, a battery**: only the "nothing to do" and registry paths get tested
- **Domain-joined PCs**, Controlled Folder Access / ASR (could be switched on here later)

---

## 10. Tracking and done criteria

Track each finding with: **ID · Script · Tab/Button · Snapshot · Steps · Expected · Actual · Severity · Log · Fixed in · Re-tested**

- **S1 Critical**: unbootable, data loss, wrong target, can't be undone, key leak or open port → blocks release
- **S2 Major**: the fix or restore doesn't work → fix it or disable the button
- **S3 Minor** / **S4 Cosmetic**

**Done for this VM when:** every ID in §4–§8 has run · there are 0 open S1 · every S2 is fixed or disabled · each fix has been re-tested from a fresh snapshot · the README says what's verified on Win11 UEFI and what's still untested (§9).

## 11. Order and effort

| # | Step | Who | Est. |
|---|---|---|---|
| 1 | Setup (§2) | You | 15 min |
| 2 | Phase 0 static + Phase 1 Pester unit tests | Claude | ½–1 day |
| 3 | Phase 2 launchers and read-only | Both | ½ day |
| 4 | 7a WinFixKit (network group last) | Both | 1–1½ days |
| 5 | 7b–7f Killer, Mount, BCD, Unattend, Recovery | Both | 1 day |
| 6 | Phase 4 AI and pairing | Both | ½ day |
| 7 | 7g Sysprep (optional, last) | You | 1 hr |

## Suspected issues to confirm
1. Mount, BCD and Service Killer read English command output and probably **break on non-English Windows** (U2, U3, U8).
2. The pairing listener accepts connections on **all network interfaces** (A1).
3. The hidden-window launchers **hide startup errors** (L5).
4. `Invoke-Bcd` skips the backup for `/default`, `/displayorder` and `/bootsequence` (U4).
5. Several WinFixKit fixes **weaken security**. Their restore path is top priority (7a).
6. Old copies in the zips can be run by mistake. Archive them.
