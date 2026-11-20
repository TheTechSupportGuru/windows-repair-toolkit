# Toolkit.Tests.ps1 - checks that hold for EVERY tool since 1.8.1: GPL v3 headers, the shared window helpers
# (display scaling, splash, fit to screen), the generated no-AI edition, and the beta's HTML Automation report.
# Reads the scripts with the PowerShell parser only (no GUI, no admin, no system changes).
#   Invoke-Pester .\tests\Toolkit.Tests.ps1
$Root = Split-Path $PSScriptRoot -Parent
$Ps1 = @(Get-ChildItem (Join-Path $Root 'tools'), (Join-Path $Root 'beta') -Filter *.ps1)
$Bat = @(Get-ChildItem (Join-Path $Root 'tools'), (Join-Path $Root 'beta') -Filter *.bat)
$GuiTools = @($Ps1 | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'Windows\.Forms\.Form' })
function Get-HelperBlock([string]$text) {
    $m = [regex]::Match($text, '(?s)#  Window helpers - the same block in every Windows Repair Toolkit tool.*?\nfunction Complete-WrtWindow \{.*?\n\}')
    if ($m.Success) { $m.Value -replace "`r", '' } else { '' }
}

Describe 'T1 license (GNU GPL v3.0)' {
    It 'LICENSE is the GPL v3 text' {
        $l = [IO.File]::ReadAllText((Join-Path $Root 'LICENSE'))
        $l | Should Match 'GNU GENERAL PUBLIC LICENSE\s+Version 3, 29 June 2007'
        $l.Length | Should BeGreaterThan 30000
    }
    It 'every script and launcher carries the SPDX line and copyright' {
        foreach ($f in $Ps1 + $Bat) {
            $t = [IO.File]::ReadAllText($f.FullName)
            if ($t -notmatch 'SPDX-License-Identifier: GPL-3\.0-only') { throw "$($f.Name): no SPDX line" }
            if ($t -notmatch 'Copyright \(C\) 2026 TheTechSupportGuru') { throw "$($f.Name): no copyright line" }
        }
        ($Ps1 + $Bat).Count | Should BeGreaterThan 10
    }
    It 'scripts are pure ASCII and parse' {
        foreach ($f in $Ps1) {
            @([IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 }).Count | Should Be 0
            $tk = $null; $pe = $null; [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tk, [ref]$pe)
            if ($pe.Count) { throw "$($f.Name): $($pe[0].Message)" }
        }
    }
}

Describe 'T2 window helpers: display scaling, splash, resizing (all GUI tools)' {
    It 'every GUI tool has the identical helper block' {
        $first = Get-HelperBlock ([IO.File]::ReadAllText($GuiTools[0].FullName))
        $first.Length | Should BeGreaterThan 1000
        foreach ($f in $GuiTools) { if ((Get-HelperBlock ([IO.File]::ReadAllText($f.FullName))) -ne $first) { throw "$($f.Name): helper block differs" } }
        $GuiTools.Count | Should BeGreaterThan 7
    }
    It 'the process is made DPI-aware before any window, and every form scales with the display' {
        foreach ($f in $GuiTools) {
            $t = [IO.File]::ReadAllText($f.FullName)
            $t | Should Match 'SetProcessDPIAware'
            $unscaled = [regex]::Matches($t, '(?m)^\s*\$\w+ = New-Object (System\.)?Windows\.Forms\.Form\s*$').Count
            if ($unscaled) { throw "$($f.Name): $unscaled form(s) without Set-WrtScaling" }
            if ($t -match 'New-Ctl Form' -and $t -notmatch 'Set-WrtScaling \$script:Form') { throw "$($f.Name): main form not scaled" }
        }
    }
    It 'every GUI tool shows the splash and calls Initialize-WrtWindow right before its main ShowDialog' {
        foreach ($f in $GuiTools) {
            $t = [IO.File]::ReadAllText($f.FullName)
            if ($t -notmatch '(?m)^Show-WrtSplash ') { throw "$($f.Name): no splash" }
            if ($t -notmatch '(?m)^Initialize-WrtWindow [^\r\n]+\r?\n\[void\]\$(script:)?[Ff]orm\.ShowDialog\(\)') { throw "$($f.Name): Initialize-WrtWindow not right before ShowDialog" }
        }
    }
    It 'the splash says exactly what it should' {
        $t = [IO.File]::ReadAllText($GuiTools[0].FullName)
        $t | Should Match "@\('Windows Repair Toolkit', 22"
        $t | Should Match "@\('Brought to you by TheTechSupportGuru'"
        $t | Should Match "@\('Licensed under GNU GPL v3\.0'"
    }
    It 'Get-WrtScale reads the display scale (1.0 at 96 DPI)' {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $tk = $null; $pe = $null; $ast = [Management.Automation.Language.Parser]::ParseFile($GuiTools[0].FullName, [ref]$tk, [ref]$pe)
        foreach ($n in 'Set-WrtScaling', 'Get-WrtScale', 'Resize-WrtColumns') { . ([scriptblock]::Create($ast.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true).Extent.Text)) }
        $f = New-Object Windows.Forms.Form; Set-WrtScaling $f
        $f.AutoScaleMode | Should Not Be 'Dpi'          # not yet: it is switched on when the finished window loads
        $f.Add_Shown({ $script:modeAtShown = $f.AutoScaleMode; $f.Close() })
        [void]$f.ShowDialog()
        $script:modeAtShown | Should Be 'Dpi'
        $g = $f.CreateGraphics(); $dpi = $g.DpiX; $g.Dispose()
        (Get-WrtScale $f) | Should Be ($dpi / 96)
        $f.Dispose()
    }
    It 'scaling switched on at load scales the controls inside the window too (simulated 150 %)' {
        $f = New-Object Windows.Forms.Form
        $f.ClientSize = New-Object Drawing.Size(400, 300)
        $t = New-Object Windows.Forms.TabControl; $t.Size = New-Object Drawing.Size(300, 200); $p = New-Object Windows.Forms.TabPage; $t.TabPages.Add($p)
        $b = New-Object Windows.Forms.Button; $b.Size = New-Object Drawing.Size(80, 20); $p.Controls.Add($b); $f.Controls.Add($t)
        $f.Add_Load({ $this.AutoScaleDimensions = New-Object Drawing.SizeF(64, 64); $this.AutoScaleMode = 'Dpi' })   # 96 / 64 = 1.5
        $f.Add_Shown({ $script:sz = @($f.ClientSize.Width, $b.Width); $f.Close() })
        [void]$f.ShowDialog(); $f.Dispose()
        $script:sz[0] | Should Be 600; $script:sz[1] | Should Be 120
    }
}

Describe 'T3 no-AI edition of WinSuperTool' {
    foreach ($dir in 'tools', 'beta') {
        It "$dir\WinSuperTool-NoAI.ps1 is up to date with $dir\WinSuperTool.ps1 (rebuilt and compared)" {
            $tmp = Join-Path $env:TEMP ('wst-noai-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
            try {
                Copy-Item (Join-Path $Root "$dir\WinSuperTool.ps1"), (Join-Path $Root "$dir\WinSuperTool.bat") $tmp
                & (Join-Path $Root 'build\Build-NoAIEdition.ps1') -Source (Join-Path $tmp 'WinSuperTool.ps1') | Out-Null
                [IO.File]::ReadAllText((Join-Path $tmp 'WinSuperTool-NoAI.ps1')) | Should Be ([IO.File]::ReadAllText((Join-Path $Root "$dir\WinSuperTool-NoAI.ps1")))
                [IO.File]::ReadAllText((Join-Path $tmp 'WinSuperTool-NoAI.bat')) | Should Be ([IO.File]::ReadAllText((Join-Path $Root "$dir\WinSuperTool-NoAI.bat")))
            } finally { Remove-Item $tmp -Recurse -Force }
        }
        It "$dir no-AI edition has no AI tab, no AI service and no network listener" {
            $t = [IO.File]::ReadAllText((Join-Path $Root "$dir\WinSuperTool-NoAI.ps1"))
            $t | Should Not Match 'api\.anthropic\.com|generativelanguage|x-api-key|TcpListener|Invoke-RestMethod|Invoke-WebRequest|HttpClient'
            $t | Should Not Match "New-Page '\d+\. AI Analyze'"
            $t | Should Not Match "New-Ctl 'Button' [^\r\n]*'Send key logs to AI"
            $t | Should Match "\(no-AI edition\)'"
            $t | Should Match "New-Page '1\. Collect Logs'"
        }
        It "$dir no-AI launcher starts the no-AI script" {
            $b = [IO.File]::ReadAllText((Join-Path $Root "$dir\WinSuperTool-NoAI.bat"))
            $b | Should Match 'WinSuperTool-NoAI\.ps1'
            $b | Should Not Match 'WinSuperTool\.ps1'
        }
    }
    It 'the builder refuses an AI marker block that is left open' {
        $tmp = Join-Path $env:TEMP ('wst-noai-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
        try {
            $t = [IO.File]::ReadAllText((Join-Path $Root 'tools\WinSuperTool.ps1'))
            $t = ([regex]'(?m)^#endregion AI-ANALYZE\r?\n').Replace($t, '', 1)
            [IO.File]::WriteAllText((Join-Path $tmp 'WinSuperTool.ps1'), $t)
            { & (Join-Path $Root 'build\Build-NoAIEdition.ps1') -Source (Join-Path $tmp 'WinSuperTool.ps1') } | Should Throw
        } finally { Remove-Item $tmp -Recurse -Force }
    }
}

Describe 'T4 beta: HTML Automation report' {
    $tk = $null; $pe = $null; $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'beta\WinSuperTool.ps1'), [ref]$tk, [ref]$pe)
    foreach ($n in 'ConvertTo-HtmlText', 'Export-AutoHtml', 'Format-Dur', 'Read-TaskResult') { . ([scriptblock]::Create($ast.Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true).Extent.Text)) }
    function Get-RebootPending { @('Windows Update') }
    $AppName = 'Windows Super Tool TEST'
    $t0 = Get-Date '2026-11-20 10:00:00'
    $out = Join-Path $env:TEMP ('wst-html-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $out | Out-Null
    $of = Join-Path $out 'task1.txt'; [IO.File]::WriteAllText($of, "Rc=0`r`nStarted=2026-11-20T10:00:00`r`nEnded=2026-11-20T10:03:00`r`n-----`r`nThe component store is repairable. <b>not html</b>")
    function Row($name, $status, $tone, $find, $auto = $false) { [pscustomobject]@{ Name = $name; Status = $status; Tone = $tone; Find = $find; Auto = $auto; Why = 'added because DISM found repairable corruption'; Quote = @('The component store is repairable.'); Started = $t0; Ended = $t0.AddMinutes(3); Rc = 0; OutFile = $of; Line = 'dism.exe /online /cleanup-image /scanhealth'; Next = 'Run DISM restore health.' } }
    $script:AutoRun = @((Row 'DISM: scan' 'PASSED' 'Bad' 'CORRUPTION DETECTED - it can be repaired'), (Row 'DISM: restore health' 'PASSED' 'Good' 'CORRUPTION DETECTED - FIX WORKED' $true), (Row 'winget' 'FAILED' 'Bad' 'NOT RUN - winget is not available'), (Row 'Defender' 'Skipped' '' ''))
    $script:Auto = @{ Started = $t0; StopWhy = 'stopped because a task did not pass' }
    $html = [IO.File]::ReadAllText((Export-AutoHtml (Join-Path $out 'r.html')))
    Remove-Item $out -Recurse -Force
    It 'puts the overall result and the colour-coded summary table first, the details after' {
        $html | Should Match '<div class="banner bad">1 FAILED, 2 passed - see the red rows</div>'
        $html.IndexOf('<h2>Summary</h2>') | Should BeLessThan $html.IndexOf('<h2>Details</h2>')
        $html | Should Match '<tr class="warn"><td>1</td>|<tr class="bad"><td>1</td>'
        $html | Should Match '<tr class="good"><td>2</td>'
        $html | Should Match '<tr class="bad"><td>3</td>'
        $html | Should Match '<tr class="skip"><td>4</td>'
        $html | Should Match 'Restart needed: <b class="res warn">YES - Windows Update'
    }
    It 'shows quotes, next step, command, exit code, the automatic-repair note and the full output' {
        $html | Should Match '<blockquote>"The component store is repairable\."</blockquote>'
        $html | Should Match '<dt>Next step</dt><dd>Run DISM restore health\.</dd>'
        $html | Should Match '<code>dism\.exe /online /cleanup-image /scanhealth</code>'
        $html | Should Match 'added because DISM found repairable corruption'
        $html | Should Match '<details><summary>Full output</summary><pre>'
    }
    It 'escapes the output and contains no script' {
        $html | Should Match '&lt;b&gt;not html&lt;/b&gt;'
        $html | Should Not Match '<script'
        $html | Should Match '^<!DOCTYPE html>'
    }
}
