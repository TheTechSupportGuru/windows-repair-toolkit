# Resize test plan: real 4K monitor (1.8.4 / 1.9 beta 5)

The VM tested every size from 720p to 4K at 100 % and at a *simulated* 150 %. This plan covers what the VM cannot test: real Windows display scaling, changing the scaling while a tool is open, and several monitors.

Run it on the branch `resize-pass-2` (or the scripts copied from it). Every step lists what to look for. Write down **Pass**, or what went wrong plus a screenshot.

## What counts as a failure

- Controls overlapping, or text cut off or blurry.
- A button, list or text box that cannot be reached (neither visible nor reachable by scrolling).
- Part of the window off the screen, or a title bar you cannot grab.
- The window shrinking below a size where its contents still fit.
- The tool closing by itself, or an error message.

## A. The automatic audit at real scaling

For each scaling: Settings > System > Display > Scale. **Sign out and back in** after each change, then in PowerShell from the repo folder:

```powershell
.\tests\Run-ResizeAudit.ps1 -OutDir "$env:TEMP\wrt-4k-150"
```

| # | Display scaling | Expected |
|---|---|---|
| A1 | 3840x2160 at 150 % | `No issues found.` in `summary.txt` |
| A2 | 3840x2160 at 200 % | same |
| A3 | 3840x2160 at 100 % | same |
| A4 | 3840x2160 at 150 %, with `-Sizes 'min,75%,res:1280x720,min,res:back,min,max'` | same; the `res:back` lines say `scroll False` |
| A5 | 3840x2160 at 200 %, with `-Sizes 'res:1920x1080,min,res:1280x720,min,res:back,max'` | same; at 1280x720 the lines say `scroll True` |

Send the three files from each output folder (`issues.csv`, `sizes.txt`, `summary.txt`).

## B. By hand, at 150 % (then repeat at 200 %)

Open **WinSuperTool** (stable), then repeat with **beta WinSuperTool**, **WinFixKit** and **Monitor-Logs**.

| # | Step | Expected |
|---|---|---|
| B1 | Start the tool | The splash shows, then the main window, centred and fully on the screen. Text is sharp. The tool stays open. |
| B2 | Drag the bottom-right corner in as far as it goes | It stops at a size where everything still fits. Nothing overlaps. |
| B3 | Drag it out to the full screen size, then maximize and restore | Lists and logs grow with the window; buttons stay at their edges. |
| B4 | Click every tab at the smallest size | Every tab is usable; where a tab does not fit, it scrolls. |
| B5 | Drag only the width in, then only the height in | Same as B2. |
| B6 | Open a report or summary window (WinSuperTool: Run a scan, then its report) and resize it small and large | It stops at a minimum size; the text box fills the window. |

## C. Changing the screen while a tool is open

Keep WinSuperTool open for every step; each step should settle within about 2 seconds.

| # | Step | Expected |
|---|---|---|
| C1 | Change the resolution to 1920x1080 (scaling stays at 150 %) | The window shrinks if needed and stays fully on the screen. |
| C2 | Change it to 1280x720 | The window fits on the screen; if the screen is too small for its layout, it scrolls instead of squeezing. |
| C3 | Change it back to 3840x2160 | Scrolling is gone; the window can be enlarged again and stops at its normal minimum. |
| C4 | Change only the **scaling** (150 % to 200 %) without signing out | Windows may show the tool slightly blurry until the next start (expected for this kind of app). The window must stay usable and on the screen. Note what you see. |

## D. Two monitors (only if a second monitor is available)

| # | Step | Expected |
|---|---|---|
| D1 | Drag the tool from the 4K monitor to the other monitor | It stays fully on the second screen and usable there. |
| D2 | Maximize it on the second monitor, then restore | It restores onto the second monitor. |
| D3 | Unplug or switch off the second monitor while the tool is on it | Windows moves it to the 4K monitor; it fits there. |
| D4 | Start a tool while the second monitor is the main display | It opens on that monitor, fully visible. |

## After the test

If everything passes, 1.8.4 and 1.9 beta 5 are released: README rows, issue/discussion form version lists, per-tool zips, tag and GitHub release. Anything that fails gets fixed and the failing step is run again first.
