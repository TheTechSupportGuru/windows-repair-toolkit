# Time sheet as of 1.9 (backup)

The hidden time sheet from the bottom of the README as it was for **1.9 and Test Center 1.0 beta 1** (2026-11-21), kept word for word when it was updated for 1.9.1. The current one is at the bottom of the [README](../../README.md) (look for the tiny pi).

<!-- Easter egg: update the numbers at every major release (see the "Hours" lines). -->
<br><br>
<details>
<summary><sub><sup>&pi;</sup></sub></summary>

### You found the time sheet

How long this project has taken, as of **1.9 and Test Center 1.0 beta 1** (November 2026). For 1.1 onwards, the AI hours are measured from the session logs and the human hours are an honest guess. The original scripts are estimated by the Claude project that wrote them, which had no stopwatch either.

| | Human | AI |
|---|---:|---:|
| Writing the original scripts in claude.ai, Nov 12-19 (the earlier Claude project's own estimate: Windows repair tool, WinFixKit, log collector and monitor, log analyzer) | ~8 h | ~6 h |
| 1.1 to 1.9 and Test Center: fixing, testing, more testing, releasing | ~14 h | ~11 h of actual thinking and typing, over ~20 h of wall clock |
| VMs grinding through test runs while everyone else made coffee | ~0 h | ~10 h of machine time, unsupervised |
| **Total** | **~22 h** | **~17 h** (plus a lot of patient VMs) |

**By the numbers**
- 174 messages from the human, 3,867 replies from the AI. The AI talks too much, and it knows.
- About 9,600 lines of tool code, 5,100 lines of tests, 1,800 lines of docs.
- 363 unit tests, 16 releases, 36 commits. More than 100 bugs fixed. One of them was a splash screen that closed the whole app.
- 3 operating systems, 2 monitors, 1 VM that got its display scaling changed more times than any VM should.
- Number of times the AI mixed up which side the second monitor is on: 1. The human remembers.
- Number of times a short PowerShell alias (`H`, `R`) secretly turned into `Get-History`: 2. It doesn't forget either.

*Updated at every major release. If the human column ever drops below the AI column, someone owes someone a coffee.*

<details>
<summary></summary>

**How long it takes the human to re-read it all**

| What | Words | Just reading (~230 words a minute) | Hunting for mistakes (~100 words a minute) | Marvelling at it |
|---|---:|---:|---:|---:|
| This page | ~3,600 | ~16 min | ~36 min | open-ended |
| Every doc in the repo (change notes, test plans, results) | ~42,500 | ~3 h | ~7 h | open-ended |
| Every release note | ~5,400 | ~25 min | ~55 min | open-ended |
| The ~9,600 lines of tool code | - | ~5 h if you skim | ~2 working days | **the rest of your life** |
| **Everything** | **~51,500** | **~9 h** | **~4 working days** | **forever** |

Marvelling takes so long because, as far as we can tell, nothing else does all of this at once: boot repair, Safe Mode, deployment, log collection, a live monitor, AI log analysis, an automation queue that also repairs a Windows that won't start from Hiren's PE, and a test tool to check all of it. If you find one, please open an issue so we can be a little less smug.

The "hunting for mistakes" column is not theoretical. One proofreading pass found five naming styles on the releases tab, a beta that never existed in the bug form, and a link to a folder that never left the PC.

</details>

</details>
