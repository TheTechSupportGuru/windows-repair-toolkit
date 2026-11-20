# Test Results: Phase 3, part 1 (WinFixKit fixes + Service Killer)

**Date:** 2026-11-19 · **Machine:** the Windows 11 VirtualBox VM, run as admin · **Version tested:** `Edited scripts\V1.3\WinFixKit.ps1`
**How:** [Tests/Run-Phase3.ps1](../../tests/Run-Phase3.ps1) runs each fix headlessly (the fix's own code, with no GUI) and checks the result in five steps:
1. Capture the system state: 8 registry keys, every service's startup type, SMB client/server settings, network category, the Network Discovery / File and Printer Sharing firewall rules, and power plans.
2. Run the fix.
3. Capture the state again.
4. Undo it with WinFixKit's **own** `Restore-RegBackup`, exactly as the Registry Backups tab does.
5. Capture once more and compare with the state from before the fix.

The data folders went to `%TEMP%\suite-phase3`.

**Result: no critical or major bugs.** All 42 fix runs completed without a crash. **Every fix the tool can undo was undone correctly**, including the security-weakening ones (SMB signing / insecure guest, printer RPC privacy, Point-and-Print). The take-ownership protection and the Service Killer safety rules behaved correctly on the real system. 3 small new bugs were found (#22–#24).

---

## 7a: WinFixKit fixes

| Group | Fixes run | Result |
|---|---|---|
| **Printer share fixes** | Fix 1 (RpcAuthnLevelPrivacyEnabled=0), Fix 3 (PointAndPrint), Fix 1+3, Restart Spooler, Clear print queue | ✅ Values changed as described. **The undo restored the exact original** (Fix 1+3: 2 backups, both restored). |
| **SMB 24H2 fixes** | Method 3 (5 values), Method 2 (3 values, incl. policy + WOW6432Node), Method 1 step 2, Restart SMB services | ✅ SMB signing and insecure-guest settings changed, **then went back to the originals** (checked in both the registry and `Get-SmbClient/ServerConfiguration`). Methods 2 and 1 touch values Method 3 had already backed up and restored: they took **fresh** backups and restored correctly. This confirms the V1.3 fix #11 on the real system. |
| **Network sharing** | Start + enable discovery services (10 backups), Enable firewall rule groups, Public → Private | ✅ Service startup types and firewall rules went back to the originals (firewall restore via `reg import` worked while the firewall was running). ✅ The network went Private and **came back to Public**. Windows left one extra value behind (`CategoryType=0`) because `reg import` never deletes values. That's harmless and already documented. |
| **Power** | Set Balanced, Restore default plans, Battery report | ✅ No net change (this VM already used the default plans). The battery report on a PC with no battery returns without an error. |
| **Search** | Restart WSearch, Rebuild index | ✅ The index was reset: Windows created a new catalog signature and restarted crawling. `SetupCompletedSuccessfully` was restored. ⚠ **#23:** it reports "Windows.edb not found". |
| **Account / Store / Start / Audio / Devices** | Restart identity services, Resync clock, Reset token cache, Re-register Account Broker, Restart Store services, Re-register Store, Re-register Start/Shell, Tile DB (Win10 only), Restart audio, Re-enable audio, Rescan, Enable disabled devices, Export drivers | ✅ All ran without errors. The Win10-only tile fix says "Windows 11 detected – not applicable" ✅. No disabled devices on this VM, so it reports "No disabled devices found". |
| **Network (safe part)** | Flush DNS, Clear ARP, Reset WinHTTP proxy | ✅ |
| **Windows Update** | Scan now, **Reset components**, **Delete old backups** | ✅ Stopped 5 services, renamed SoftwareDistribution + catroot2 to `.bak_…`, cleared BITS, restarted the services. "Delete old backups" then removed exactly those two folders. Windows recreated SoftwareDistribution. |
| **Files and folders** | Show permissions; **Take ownership** of a test folder; then `C:\ProgramData`, `C:\Documents and Settings`, the user profile, `C:\Windows\System32` | ✅ The test folder: ACL backup saved, owner changed, permissions reset (3 items, 0 failures). ✅ **All 4 protected targets REFUSED** on the live system, including the junction (`C:\Documents and Settings` → "C:\Users is the Users folder"). Only 1 ACL backup was written. |
| **Shell** | Restart Start/Search/Shell, **Restart Explorer** (run from the admin session) | ✅ Explorer came back, and **not elevated**. A restart from an admin WinFixKit doesn't leave the user with an admin Explorer. |
| **Smb test tool** | Test access to `127.0.0.1` | ⚠ **#22** and **#24**: port 445 shows OPEN, but the result says `Open \\127.0.0.1 : FAILED`. |

**Overall check (start of run vs. end of run):** the only differences are values Windows maintains itself: the Search crawl counters (expected after a rebuild), the SMB server `Guid` (regenerated whenever the Server service restarts), and two Print-spooler counters. Nothing the tool changed was left behind.

## 7b: Service Killer (one real kill cycle)

| "Allow killing shared processes" | Service | Result |
|---|---|---|
| ON | Spooler | killed ✅ (restarted afterwards) |
| ON | RpcSs, EventLog | **REFUSED** ✅ |
| ON | **mpssvc**, **BFE** | **REFUSED** ✅ (the V1.2 fix #5 works: before, this combination would have rebooted the PC) |
| ON | WSearch | killed ✅ (restarted afterwards) |
| OFF | PimIndexMaintenanceSvc (shares its process with 2 others) | **SKIPPED** ✅ "shared with 2 other service(s) … Tick the box above to allow." |

All four services were Running again at the end.

## New bugs

| # | Sev | Script | Finding |
|---|---|---|---|
| 22 | S3 ✅ fixed in V1.5 | WinFixKit, "Test access to a PC / NAS" | The `Open \\<host>` line uses `Test-Path "\\host"`, which is **always false for a bare server name** (it only works for `\\host\share`). So it always prints **FAILED**, even when SMB works (port 445 was OPEN here). That's misleading when you're troubleshooting. Fix: test `\\host\IPC$`, or use the `net view` exit code. |
| 23 | S4 ✅ fixed in V1.5 | WinFixKit, "Rebuild search index" | It deletes `Windows.edb`, but **Windows 11 22H2+ stores the index as `Windows.db`**, so nothing is deleted and it says "not found". The rebuild still happens, because the `SetupCompletedSuccessfully=0` reset triggered a new catalog. *The file name couldn't be confirmed from the normal-user session.* Fix: handle both `Windows.edb` and `Windows.db`. |
| 24 | S4 ✅ fixed in V1.5 | WinFixKit, "Test access" | When the target is an IP address, "Name lookup: OK ()" shows an empty address (it returns a reverse-lookup record with no `IPAddress`). Cosmetic. |

---

# Phase 3, part 2: WinSuperTool 7c–7g (run 2026-11-19 20:24, **interrupted by a BCD problem**)

Runner: [Tests/Run-Phase3-WST.ps1](../../tests/Run-Phase3-WST.ps1), as admin, on V1.3. **69 checks, 55 passed, 14 failed.** Raw output is in `%TEMP%\suite-phase3-wst\`.

## ⚠ Incident: the BCD import left Windows unable to open any boot store
- Sequence:
  1. The Safe Mode tests (edit + clone) passed.
  2. A `/store` test then pointed bcdedit at the **live** system store through a second drive letter on the ESP.
  3. Then **"BCD: restore from backup (import)"** (`bcdedit /import <tool backup>`) failed with *"The store import operation has failed. The parameter is incorrect."*
- After that:
  - The system store was **unloaded** (`HKLM\BCD00000000` gone).
  - `bcdedit` failed on **every** store, even the untouched one on the install CD.
  - `reg load` failed on every hive ("The filename or extension is too long").
  - bcdboot failed ("Could not open the BCD template store").
  - The safety re-import of the baseline also failed.
- The files on disk look intact: the ESP's `BCD` (rewritten 20:24:56), the baseline export and all 4 tool backups are **valid registry hives** (signature, matching sequence numbers, checksum OK). It looks like a stuck in-memory state that a reboot should clear.
- **Resolved:** the VM rebooted normally, and the BCD was identical to the pre-test baseline. After the isolated import re-test it needed one more reboot. Re-checked afterwards ([Tests/Verify-AfterReboot.ps1](../../tests/Verify-AfterReboot.ps1)): store loaded, **0 differences from the baseline**, only C: and D: assigned. The isolated re-test showed that **`bcdedit /import` itself fails on this VM** (bug **#28**), so it wasn't caused by the test setup.
- Cleanup done: the S: and T: letters the test left behind were removed (`mountvol /D`).

## Results that are valid regardless of the incident

| Area | Result |
|---|---|
| **7c Mount, Storage mode** | ✅ The disk and 5 partitions are listed. ✅ Mounting the EFI (S:) and recovery partitions works; the BCD is visible, the letter is read back correctly, the mount memory reloads the real mount, and Dismount frees the letter. ✅ Stale memory is dropped ("Forgot remembered mount U:"). ✅ Unmounting C: is refused. ❌ **#25** below: the MSR partition can be given a letter. |
| **7c Mount, diskpart mode** | ✅ Real diskpart output is parsed correctly (disk list, 5 partitions, letters), and mounting works. ❌ **#26** below: those mounts are immediately "forgotten", so they can't be unmounted from the tool. |
| **7d Safe Mode (live `{current}`)** | ✅ Edit mode sets and clears `safeboot Minimal`, and answering No changes nothing. ✅ Clone mode creates exactly one clone with safeboot (normal entry untouched), a second Create is refused, and Delete removes it. ✅ The 4 boot-menu tools (legacy/standard F8 menu, Automatic Repair off/on) set and restore their values. ✅ An automatic backup was made before each change, and the backup tool writes a file. |
| **7d `/store` path** | ⚠ Test-design limit: Windows can't open the live store through `/store` while it's loaded, so this needs real WinPE. |
| **7f Recovery** | ✅ bcdboot builds `/f UEFI` for the FAT32 ESP with no warning. ✅ An NTFS partition on UEFI gets a warning, and No cancels. ✅ `/fixmbr` and `/fixboot` warn on UEFI. ✅ `bootrec` shows "not available". ✅ The chkdsk /scan and driver-list buttons build the right commands. ✅ `chkdsk C: /scan` ran ("found no problems"), and `dism /online /get-drivers` ran (5 third-party drivers). ⛔ The real bcdboot run failed only because of the incident; the ESP files were not changed. |
| **7e Unattend** | ✅ Well-formed XML with every option. ✅ Passes, amd64 and the public key token are correct. ✅ ComputerName, TimeZone and UILanguage are present, and the password decodes correctly. ✅ Deploy writes UTF-8 without BOM to the target drive (a SUBST drive was used), and a second Deploy backs up the old file first. ✅ The real `C:\Windows\Panther\Unattend` was untouched. |
| **7g Sysprep pre-flight** | ✅ All 3 modes run, and sysprep was **not** started. Mode A gives realistic warnings: 9.8 GB free, an existing `C:\Windows\Panther\unattend.xml` (left by Windows setup), and **"BitLocker active on C:"**. That last one is a real finding: device encryption is on, so the V1.3 WMI check (#16) works where the old English-text check would have missed it. ⚠ "Store app check skipped (Appx cmdlets unavailable)": `Get-AppxProvisionedPackage` failed in this context. Re-check after the reboot. |

## New bugs (part 2)

| # | Sev | Script | Finding |
|---|---|---|---|
| 25 | S3 | WinSuperTool, WinRepairTool (Mount, Storage mode) | `Add-PartitionAccessPath` gives the **MSR partition** a drive letter. It has no file system, so Explorer then offers to **format** it. The partition list should hide MSR (and other partitions without a volume), or Mount should refuse them. |
| 30 | S2 | WinSuperTool, WinRepairTool **V1.2+** (regression from fix #4) | Found while verifying V1.4. `Backup-Bcd` backs up an offline store with `bcdedit /store X /export Y`, which bcdedit rejects ("The store export command is invalid"). Since V1.2 refuses any BCD change without a backup, **every BCD change in WinPE was blocked**. **Fixed in V1.4** (file-copy backup). |
| 26 | S2 | WinSuperTool, WinRepairTool **V1.2+** (my fix #3) | *Confirmed by a two-process test while verifying V1.4: `Get-Partition` doesn't report diskpart-assigned letters even in a **new** process, so the mount memory forgot diskpart mounts on every restart. Fixed in V1.4 (letter → volume GUID → partition).* `Test-MountStillOurs` uses `Get-Partition`, whose cache **doesn't see letters assigned by diskpart**. In diskpart mode every new mount is immediately "forgotten", can't be unmounted from the tool, and stays assigned (EFI and recovery stayed as S:/T:). Fix: call `Update-HostStorageCache` before `Get-Partition`, or verify through diskpart / `mountvol` when the tool is in diskpart mode. |
| 27 | S4 | WinSuperTool, WinRepairTool | `Dismount-One` on an empty entry logs "Unmounted :" and returns success. It should refuse an empty letter. |
| 29 | S3 | WinSuperTool, WinRepairTool (Sysprep pre-flight) | `Get-AppxProvisionedPackage -Online` returns **"Access is denied" even as admin**, after a clean reboot too, in Windows PowerShell 5.1 on this build. The pre-flight then only reports *INFO: Store app check skipped*. So the check for **the most common reason generalize fails** (Store apps installed per user but not provisioned) silently doesn't run. Fix: fall back to `dism /online /get-provisionedappxpackages`, and report it as **WARN** (not INFO) when it can't be checked. |
| 28 | **S1** | WinSuperTool, WinRepairTool, **"BCD: restore from backup (import)"** | **Confirmed after the reboot** ([Tests/Verify-BCD-Import.ps1](../../tests/Verify-BCD-Import.ps1)). After the reboot the BCD was healthy and **identical to the pre-test baseline** (0 differences, no clones left). A plain `bcdedit /export` followed by `bcdedit /import` of **that same, fresh, valid file** (no ESP letter mounted, no `/store`) **fails again**: *"The store import operation has failed. The parameter is incorrect."* It leaves the system store **unloaded**, so every later bcdedit, Safe Mode, boot-menu or bcdboot action fails until a reboot. **The undo for every BCD change this tool makes doesn't work on this PC**, and the tool doesn't tell the user the store is now unloaded. The on-disk store survived both times (the VM booted with its pre-import content). The cause is most likely `/import` syncing UEFI firmware boot entries, which VirtualBox's NVRAM rejects. **This must be checked on a physical UEFI PC.** Recommended fix: (a) after a failed `/import`, show a clear error saying a reboot is required and no further BCD tools may be used until then; (b) offer an offline restore instead, i.e. copy the backup over `<ESP>\EFI\Microsoft\Boot\BCD` from WinPE, where the store isn't loaded. |

---

# Phase 3, part 3: network resets (V1.5 WinFixKit, 2 reboots)

Runner: [Tests/Run-NetReset.ps1](../../tests/Run-NetReset.ps1), as admin, in 3 stages: **pre** → reboot → **post** → **restore** → reboot → **post**. Data is in `%LOCALAPPDATA%\suite-net\`.

**Result: no critical or major bugs.** The VM was online with an identical IP configuration after every step and both reboots.

| Step | Result |
|---|---|
| **Full registry backup** (the GUI takes it before the first registry fix) | ✅ `HKLM\SYSTEM` (14 MB) and `HKLM\SOFTWARE` (77 MB) saved in 3.2 s. A restore point **could not be created** because System Restore is disabled on this VM, and the tool says so clearly and carries on. |
| **Release and renew DHCP lease** | ✅ Done instantly. Same address ([redacted]), gateway, DNS; internet OK straight away. |
| **FULL network reset** (DNS flush, ARP, WinHTTP proxy, Winsock reset, TCP/IP reset, DHCP renew) | ✅ The 4 network keys were exported first (Tcpip, Tcpip6, Winsock, Winsock2). The Winsock catalog was reset, and the VM stayed online before the reboot. ⚠ **#32** and **#33** below. |
| **After reboot #1** | ✅ Internet and DNS OK. IP, gateway, DNS, DHCP and proxy **identical to the baseline**. The reset really took effect: TCP/IP `IPEnableRouter` was removed and the **Winsock catalog was rebuilt** (91 registry differences). ⚠ The rebuild **dropped the Bluetooth RFCOMM provider** from the Winsock provider list (#33). |
| **Undo with WinFixKit's Registry Backups** (`Restore-RegBackup` on all 4 keys) | ✅ All 4 `reg import`s succeeded, and `IPEnableRouter` and the provider list (with RFCOMM) came back. As the tool warns, it's a **partial** undo for Winsock: keys added by the reset (`Protocol_Catalog_Before_Reset`, rewritten provider descriptions) stay. ⚠ **#31**: the successful imports were shown as `NativeCommandError` error blocks. |
| **After reboot #2** | ✅ Internet and DNS OK, and everything identical to the baseline. The network works after reset **and** after undo. |

## New bugs (part 3)

| # | Sev | Script | Finding |
|---|---|---|---|
| 31 | S3 ✅ fixed in V1.6 | WinFixKit `Restore-RegBackup` (Registry Backups tab, KEY rows) | `reg.exe import` writes *"The operation completed successfully."* to **stderr**, and `2>&1 \| Out-String` turns that into a PowerShell **`NativeCommandError` block**. A **successful** restore looks like a failure. It also never checks `$LASTEXITCODE`, so a **real** failure would look exactly the same. Fix: convert ErrorRecords to plain text and report OK/FAILED from the exit code. |
| 32 | S4 ✅ fixed in V1.6 | WinFixKit, "Reset TCP/IP stack" and "FULL network reset" | `netsh int ip reset` reported **1 of 34** items as `Resetting , failed. Access is denied.` (a known, usually harmless netsh behaviour on recent Windows; an earlier note said "a few", but that was a display artifact of my own log viewer), but the tool then says **"DONE"** without mentioning them. The help promises the log is saved in the logs folder, but **no `netsh-ip-reset.log` was written** on this build. Fix: count the failed lines and say they're normally harmless, and don't promise a log, or check that it exists. |
| 33 | S4 ✅ fixed in V1.6 | WinFixKit, "Reset Winsock catalog" and "FULL network reset" | The Winsock reset rebuilt the catalog **without the Bluetooth RFCOMM provider**. On a PC that uses Bluetooth serial / RFCOMM apps, that can break them until Bluetooth re-registers. The help only mentions "custom LSPs". Fix: mention it in the help and the confirmation. The Registry Backups undo does restore it (seen here). |

---

# Phase 3, part 4: fixes that open their own window, and log generation (2026-11-19)

**Windowed fixes** ([Tests/Run-Windowed.ps1](../../tests/Run-Windowed.ps1), V1.6 WinFixKit, run as admin through the tool's own `Start-InWindow`; each window's transcript was watched until it finished):

| Fix | Result |
|---|---|
| Repair system files (DISM + SFC) | ✅ 11.6 min. DISM *"The restore operation completed successfully"*, SFC *"did not find any integrity violations"* |
| Scan system drive (chkdsk, read-only) | ✅ *"Running CHKDSK in read-only mode … found no problems"* |
| Re-register ALL apps | ✅ 118/118 packages processed; Start menu still running afterwards |
| Remove KB5025221 | ⚠ wusa returned **exit code 87** (KB not installed), shown as "Not removed. Try Settings…". Misleading → **fixed in V1.7 (W2)** |
| Energy report (60 s) | ⚠ `powercfg /energy` returns in 0.3 s with exit code 0 and **no report** on this build (reproduced outside the tool). The tool said nothing about it → **V1.7 (W1)** now says so |
| WinSuperTool Recovery console windows | ✅ They open. `chkdsk /f` on C: stops at its Y/N question; answering N schedules nothing (dirty bit not set) |

**Log generation** ([Tests/Run-LogGen.ps1](../../tests/Run-LogGen.ps1)): all collectors in both tools, live and offline, then the AI log readers on the results. It found three new bugs, fixed in V1.7: **E1** (S2: a failed Event Viewer export counted as "skipped" with 0 failures), **B1** (S3: a binary `.etl` was sent to the AI as text), and **P1** (S3: my own V1.7 free-space check scanned all of C:\Windows, 53.8 s). After the fixes: 351 files, 504 MB, 0 failed. Full numbers are in [V1.7 CHANGES](../changes/V1.7.md).

**Test-environment note:** a test run started from inside this Claude app can't have `wevtutil` export into `%LOCALAPPDATA%`. The app's writes there are redirected to a private store, and the Event Log service can't see that folder. The tools' real output folders (Desktop, `%TEMP%`, other drives) are unaffected. This is what exposed E1.

## Not done in this part (needs a reboot or WinSuperTool)
- ~~Network resets~~: **done in part 3**, see above.
- **Window-only fixes:** DISM+SFC, chkdsk scan, Re-register ALL apps, energy report and KB5025221 removal. They open their own console windows, which needs someone watching. "Open …" buttons (Credential Manager, Sound, Indexing Options, gpedit, wsreset) only launch Windows tools.
- **WinSuperTool parts of Phase 3:** 7c Mount, 7d Safe Mode / BCD (reboots), 7e Unattend, 7f Recovery and 7g Sysprep.

Re-run (as admin, after a VM snapshot):

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-Phase3.ps1
```
