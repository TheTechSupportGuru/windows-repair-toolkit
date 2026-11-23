# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build-ReleaseZips.ps1 - builds the release zips of one version from its git tag (the exact committed bytes).
# Since 1.9.2 the separate tools are ONE zip, IndividualTools-v<x>.zip, started with its shared Run-PS-As-Admin.bat.
#   powershell -ExecutionPolicy Bypass -File .\build\Build-ReleaseZips.ps1 -Tag v1.9.2 -OutDir C:\temp\zips
param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$OutDir)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$ver = $Tag.TrimStart('v')
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force $OutDir | Out-Null
function Get-TagBytes([string]$p) {
    $tmp = [IO.Path]::GetTempFileName()
    cmd /c "git -C `"$repo`" show `"${Tag}:$p`" > `"$tmp`""; if ($LASTEXITCODE) { throw "git show $Tag $p failed" }
    $b = [IO.File]::ReadAllBytes($tmp); Remove-Item $tmp; , $b
}
$common = @"
Licensed under the GNU General Public License, version 3 or (at your option) any later version (see LICENSE.txt).
Copyright (C) 2026 TheTechSupportGuru. This program comes with ABSOLUTELY NO WARRANTY.

WARNING: these scripts were written with AI. They have been tested on Windows 11, Windows 10 64-bit (MBR disk) and
Hiren's BootCD PE 10 / 11, but not on many real PCs. Use at your own risk, and try them on a test machine first.

Files downloaded from the internet are marked as blocked by Windows. Before extracting, right-click the .zip >
Properties > tick "Unblock", or run in PowerShell:  Get-ChildItem <folder> | Unblock-File

Full documentation: https://github.com/TheTechSupportGuru/windows-repair-toolkit
"@
$zips = [ordered]@{
    "WinSuperTool-v$ver"      = @{ Files = 'tools/WinSuperTool.ps1', 'tools/WinSuperTool.bat'; Start = 'Start WinSuperTool.bat.' }
    "WinSuperTool-NoAI-v$ver" = @{ Files = 'tools/WinSuperTool-NoAI.ps1', 'tools/WinSuperTool-NoAI.bat'; Start = 'Start WinSuperTool-NoAI.bat (WinSuperTool without the AI Analyze tab).' }
    "WinFixKit-v$ver"         = @{ Files = 'tools/WinFixKit.ps1', 'tools/Launch-WinFixKit.bat'; Start = 'Start Launch-WinFixKit.bat.' }
    "IndividualTools-v$ver"   = @{ Files = 'tools/WinRepairTool-startup.ps1', 'tools/Collect-Logs.ps1', 'tools/Monitor-Logs.ps1', 'tools/ClaudeLogAnalyzer.ps1', 'tools/Run-PS-As-Admin.bat'
                                   Start = "The separate tools, each also part of WinSuperTool: WinRepairTool, Collect-Logs, Monitor-Logs, ClaudeLogAnalyzer.`r`nStart any of them with Run-PS-As-Admin.bat: drag the .ps1 onto it." }
}
$bsb = Get-TagBytes 'tools/BackupScriptBuilder.ps1'
if ([Text.Encoding]::ASCII.GetString($bsb) -match '# Version ([\d.]+)') { $zips["BackupScriptBuilder-v$($Matches[1])"] = @{ Files = 'tools/BackupScriptBuilder.ps1', 'tools/BackupScriptBuilder.bat'; Start = 'Start BackupScriptBuilder.bat. Needs FreeFileSync: https://freefilesync.org/' } }
foreach ($name in $zips.Keys) {
    $z = $zips[$name]; $path = Join-Path $OutDir "$name.zip"; if (Test-Path $path) { Remove-Item $path }
    $folder = $name -replace '-v[\d.]+$', ''
    $zip = [IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($f in $z.Files) { $e = $zip.CreateEntry("$folder/$(Split-Path $f -Leaf)"); $s = $e.Open(); $b = Get-TagBytes $f; $s.Write($b, 0, $b.Length); $s.Dispose() }
        $e = $zip.CreateEntry("$folder/LICENSE.txt"); $s = $e.Open(); $b = Get-TagBytes 'LICENSE'; $s.Write($b, 0, $b.Length); $s.Dispose()
        $e = $zip.CreateEntry("$folder/READ ME FIRST.txt"); $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.ASCIIEncoding))
        $w.Write((("$name`r`n`r`n" + $z.Start + "`r`n`r`n" + $common) -replace "(?<!\r)\n", "`r`n")); $w.Dispose()
    } finally { $zip.Dispose() }
    '{0,-34} {1,8:N0} bytes  {2}' -f "$name.zip", (Get-Item $path).Length, (($z.Files | Split-Path -Leaf) -join ', ')
}
