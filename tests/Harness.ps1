# Harness.ps1 - pulls individual functions / variables / button scriptblocks out of the suite scripts
# WITHOUT running the scripts (no GUI, no elevation, no system changes). Uses the PowerShell parser only.
$global:SuiteDir = Split-Path $PSScriptRoot -Parent
$global:AstCache = @{}

# Which copy is tested: the newest "Edited scripts\V<x.y>" folder that contains the file, else the original.
# Set  $env:SUITE_TEST_VERSION = 'original'  (or e.g. 'V1.2') to test a specific version.
$global:EditedVersions = @(Get-ChildItem -LiteralPath (Join-Path $global:SuiteDir 'Edited scripts') -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^V(\d+)\.(\d+)$' } | Sort-Object { [version]($_.Name.Substring(1)) } -Descending)
function global:Resolve-SuitePath([string]$Rel) {
    # repo layout: the current scripts are in tools\
    $r = Join-Path $global:SuiteDir ('tools\' + (Split-Path $Rel -Leaf)); if (Test-Path -LiteralPath $r) { return $r }
    $want = $env:SUITE_TEST_VERSION
    if ($want -ne 'original') {
        foreach ($v in $global:EditedVersions) {
            if ($want -and $v.Name -ne $want) { continue }
            $p = Join-Path $v.FullName (Split-Path $Rel -Leaf)
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    Join-Path $global:SuiteDir $Rel
}

function global:Get-SuiteAst([string]$Rel) {
    if (-not $global:AstCache.ContainsKey($Rel)) {
        $t = $null; $e = $null
        $global:AstCache[$Rel] = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-SuitePath $Rel), [ref]$t, [ref]$e)
    }
    $global:AstCache[$Rel]
}

# Text of one or more function definitions -> dot-source the result to define them in the caller's scope
function global:Get-FnText([string]$Rel, [string[]]$Names) {
    $ast = Get-SuiteAst $Rel
    $out = foreach ($n in $Names) {
        $f = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $f) { throw "Function $n not found in $Rel" }
        $f.Extent.Text
    }
    $out -join "`r`n"
}

# Text of the first assignment to $Var (e.g. 'DpAllow', 'script:KillCritical')
function global:Get-AssignText([string]$Rel, [string]$Var) {
    $ast = Get-SuiteAst $Rel
    $a = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $x.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $x.Left.VariablePath.UserPath -eq $Var }, $true)
    if (-not $a) { throw "Assignment to `$$Var not found in $Rel" }
    $a.Extent.Text
}

# The Run = { ... } scriptblock of a WinFixKit action, found by its Label
function global:Get-ActionRun([string]$Rel, [string]$Label) {
    $ast = Get-SuiteAst $Rel
    $h = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.HashtableAst] -and
            @($x.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'Label' -and $_.Item2.Extent.Text -eq "'$Label'" }).Count -gt 0 }, $true)
    if (-not $h) { throw "Action '$Label' not found in $Rel" }
    $run = $h.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'Run' } | Select-Object -First 1
    $txt = $run.Item2.Extent.Text.Trim()
    [scriptblock]::Create($txt.Substring(1, $txt.Length - 2))   # strip the outer { }
}
