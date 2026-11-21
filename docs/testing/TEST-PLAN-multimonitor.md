# Test plan: two monitors, real scaling, 8 cores (1.8.4 / 1.9 beta 5)

The test VM was upgraded on 2026-11-20. This plan tests everything new since 1.8, using what the new VM can do that the old one could not:

| Item | Before | Now | Used for |
|---|---|---|---|
| CPU | 4 vCPU | **8 cores** | the tools and test suites run **in parallel** (9 tools at once, 3 unit suites at once) |
| Monitors | one virtual screen | **two**: a 3840x2160 monitor (main) and a 2560x1440 monitor **to its right**; also tested arranged **above** it (negative screen coordinates) | moving windows between monitors, maximizing on the second one, across the edge, removing a monitor |
| Display scaling | 100 % only (150 % was simulated) | each monitor can be **scaled on its own** | a real 150 % monitor next to a 100 % one, changed while the tool is open |
| Graphics | basic | WDDM with **video acceleration** | the HTML report rendered by Edge at 4K, 2K, 1280 and phone width |

Not possible from inside the VM, so **done by you** (section 7): scaling the **main** monitor (Windows applies it to these tools only after signing out, which ends the test session), dragging a window with the mouse, and checking the picture on the physical 4K screen.

## 1. What is tested

Everything new since 1.8:

| Since | Feature |
|---|---|
| 1.8.1 | sharp scaling on high-DPI screens, splash screen, no-AI edition, GPL v3 |
| 1.8.2 | layout fixes for scaled displays, windows centred with their final size |
| 1.8.3 | tools no longer close by themselves after the splash |
| 1.8.4 / beta 5 | hard minimum sizes, the window follows screen changes, scrolling only when the screen is too small |
| beta 1-4 | Recovery pass / fail summaries and log monitors, **System Info** tab, **Automation** tab, HTML Automation report |

## 2. How to run

```powershell
.\tests\Run-ResizeAudit.ps1 -Parallel -Sizes 'min,1280x680,1920x1040,2560x1400,3840x2060,75%,max'
.\tests\Run-ResizeAudit.ps1 -Sizes 'mon:2,min,75%,max,maxon:2,mon:1,span,mon:2,dpi2:150,mon:2,min,maxon:2,span,mon:1,mon:2,dpi2:back,mon:2,solo,extend,mon:2'
```

New words for `-Sizes` in `tests/Run-ResizeAudit.ps1`:

| Word | What it does | What must be true afterwards |
|---|---|---|
| `mon:N` | moves the window to monitor N (centred) | it is on monitor N, completely inside its work area |
| `maxon:N` | maximizes it on monitor N | maximized on monitor N |
| `span` | puts it across the edge between monitor 1 and 2 | the title bar is on a screen; no layout issues |
| `dpi2:150` / `dpi2:back` | changes the scaling of monitor 2 while the tool is open | the window fits the screen it is on |
| `solo` / `extend` | switches monitor 2 off (as if unplugged) and on again at its old place | the window ends up on a screen, fits it, and the title bar can be grabbed |

After every screen change the audit also runs its normal checks on every tab: overlapping controls, cut-off controls, text that does not fit, and the minimum size. Monitor scaling, resolution and monitor 2 are always put back, also when a tool fails. `-Parallel` runs all tools at the same time (size steps only; screen changes always run one tool at a time). Screenshots (`-Shots`) are taken from the tool's own window, never from the screen.

## 3. Unit tests (parallel)

| ID | Test | Pass when |
|---|---|---|
| U1 | `Suite.Tests.ps1`, `Toolkit.Tests.ps1`, `Beta.Tests.ps1` at the same time | all pass |

## 4. Window sizes (parallel, all 9 GUI scripts)

| ID | Test | Pass when |
|---|---|---|
| R1 | every size from the minimum to maximized on the 4K monitor, 100 % | no issues |
| R2 | the same with simulated 150 % | no issues |
| R3 | primary resolution changed live: 4K, 1280x720, back | the window fits 720p; scrolling switches off again at 4K |

## 5. Two monitors (one tool at a time, all 9 GUI scripts)

| ID | Test | Pass when |
|---|---|---|
| M1 | move to the 2K monitor (to the right; and arranged above, with negative coordinates); sizes there | on monitor 2, inside its work area, no issues |
| M2 | maximize on the 2K monitor | maximized there, no issues |
| M3 | across the edge of the two monitors | it stays across the edge (when both screens show all of it), no issues |
| M4 | 2K monitor scaled to 150 % while the tool is on it; sizes, maximize, across the edge | fits; no issues |
| M5 | 2K monitor removed while the tool is on it, then back | the window moves to the 4K monitor and fits; no issues |
| M6 | M1-M5 with simulated 150 % | as above |

## 6. Features on the new hardware

| ID | Test | Pass when |
|---|---|---|
| F1 | all 9 GUI scripts started at the same time, unmodified apart from skipping the admin prompt; with a normal and with a minimized start style (`WinSuperTool.bat` uses minimized) | all still open after 15 s, main windows visible and not minimized |
| F4 | each popup (report, task summary, Automation task summary) with the main window on monitor 2 | it opens on monitor 2 |
| F2 | System Info > Video on a PC with two monitors | both monitors listed with resolution and scaling |
| F3 | HTML Automation report (10 tasks, long output) rendered by Edge at 3840, 2560, 1280 and 390 px wide | readable; no sideways scrolling |

## 7. By you, at the VM

| ID | Step | Pass when |
|---|---|---|
| P1 | Settings > Display: main (4K) monitor to 150 %, **sign out and in**, then run R1 and section 5 again | no issues |
| P2 | the same at 200 % | no issues |
| P3 | drag WinSuperTool slowly with the mouse from the 4K monitor to the 2K monitor and back, and drop it across the edge | it follows the mouse smoothly and is not pulled away while you drag |
| P4 | WinSuperTool on the 2K monitor at 150 % (main monitor 100 %) | text readable (Windows stretches it slightly - expected for this kind of app) |
| P5 | Automation tab, as administrator: queue restore point + SFC scan only + DISM check health + Defender quick scan, run, save the HTML report | every task gets a result, popups appear on the monitor of the main window |

Results: [TEST-RESULTS-multimonitor.md](TEST-RESULTS-multimonitor.md).
