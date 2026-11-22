# Test Center 1.0 beta 2 (2026-11-22)

One fix, for the release layout of toolkit 1.9.1.

- **Online mode lists the betas again.** Since 1.9.1 betas have no release entry of their own: their zips and notes are inside the main release. "Get version list" now also reads the repository's git tags and adds every beta tag (WinFixKit beta-automation, the WinSuperTool 1.9 betas, Test Center betas) as "(beta)", between the releases and `main`. If the tag lookup fails, the releases are still listed.
- The included tools are now 1.9.1 (the 1.9 tools plus Backup Script Builder).

Tested: `tests/Run-TestCenterGui.ps1` passes, with "Get version list" finding 21 versions (13 releases, 7 beta tags, `main`); a beta tag's source zip downloads.

Everything else is as in [beta 1](TestCenter-1.0-beta.1.md).
