## What this changes

<!-- Which tool(s) and what the change does. -->

## Checklist (see CONTRIBUTING.md)

- [ ] Runs only on the **built-in runtimes** of Windows 11, Windows 10 64-bit and Hiren's BootCD PE 10 / 11: Windows PowerShell 5.1 (and works on PowerShell 7 for PE 10), .NET / WinForms, cmd. No other runtimes, modules, installers or third-party programs. Windows' own programs (dism, netsh, ...) are fine.
- [ ] A program that is missing on one of those systems is checked for first, with a clear message.
- [ ] Changed `tools/` only. The no-AI edition was rebuilt with `build/Build-NoAIEdition.ps1`, not edited by hand.
- [ ] Scripts are pure ASCII and keep the GPL-3.0-or-later header.
- [ ] Nothing identifying (names, IPs, MACs, user paths) in code, comments or results.

## Tested on

- [ ] Windows 11
- [ ] Windows 10 64-bit
- [ ] Hiren's BootCD PE 10
- [ ] Hiren's BootCD PE 11

## Test Center results

<!-- Paste the "Copy summary for GitHub" text from Test Center here. -->
