#requires -Version 5.1
# Version 1.8.2 (2026-11-20). What changed: docs/changes/V1.8.2.md
# Windows Repair Toolkit - https://github.com/TheTechSupportGuru/windows-repair-toolkit
# Copyright (C) 2026 TheTechSupportGuru
# SPDX-License-Identifier: GPL-3.0-or-later
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file or https://www.gnu.org/licenses/.
# Claude Log & Screenshot Analyzer - Windows 11, no extra libraries.
# Works with Claude (Anthropic) or Gemini (Google, has a free tier) - pick in the dropdown.
# Login: the PC shows a QR code, you scan it with your phone, type/paste your API key on the phone.
# The key is encrypted on the phone (one-time pad from the QR) and only ever held in memory for 1 hour.

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class Dpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][Dpi]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------------------------
#  Window helpers - the same block in every Windows Repair Toolkit tool (since 1.8.1):
#  display scaling, splash screen, fit to screen, scrolling instead of squeezing.
# ---------------------------------------------------------------------------------------------
# Sharp, unclipped text on 125 % / 150 % / 200 % displays: this process scales its own windows
# (AutoScaleMode Dpi on every form) instead of Windows stretching a blurry bitmap of them.
try { Add-Type -Namespace WrtUi -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop; [void][WrtUi.Dpi]::SetProcessDPIAware() } catch {}
# The scaling is switched on when the form LOADS: WinForms only scales what exists at that moment, so this way the
# finished window and every control in it scale together (setting it at creation scaled nothing inside the window).
function Set-WrtScaling($f) {
    $f.Add_Load({
        $this.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96); $this.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
        $k = Get-WrtScale $this
        if ($k -gt 1.01) { Resize-WrtColumns $this $k }
        Move-WrtIntoView $this
    })
}
# WinForms centres a window using its size BEFORE scaling, so a scaled window grew past the right and bottom edge
# of the screen: centre it again with its final size and keep it inside the screen's working area.
function Move-WrtIntoView($f) {
    try {
        $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea
        if ($f.Width -gt $wa.Width) { $f.Width = $wa.Width }
        if ($f.Height -gt $wa.Height) { $f.Height = $wa.Height }
        $sp = [string]$f.StartPosition; $r = $null
        if ($sp -eq 'CenterParent' -and $f.Owner) { $r = $f.Owner.Bounds } elseif ($sp -eq 'CenterScreen' -or $sp -eq 'CenterParent') { $r = $wa }
        $x = $f.Left; $y = $f.Top
        if ($r) { $x = $r.Left + [int](($r.Width - $f.Width) / 2); $y = $r.Top + [int](($r.Height - $f.Height) / 2) }
        $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $f.Width)); $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $f.Height))
        $f.Location = New-Object Drawing.Point($x, $y)
    } catch {}
}
# list view column widths are not scaled by WinForms
function Resize-WrtColumns($parent, [double]$k) {
    foreach ($c in $parent.Controls) {
        if ($c -is [Windows.Forms.ListView]) { foreach ($col in $c.Columns) { $col.Width = [int]($col.Width * $k) } }
        if ($c.Controls.Count) { Resize-WrtColumns $c $k }
    }
}
function Get-WrtScale($f) { try { $s = [double]$f.CurrentAutoScaleDimensions.Width / 96; if ($s -gt 0) { return $s } } catch {}; return 1.0 }
function Show-WrtSplash([string]$what) {
    try {
        $s = New-Object Windows.Forms.Form; Set-WrtScaling $s
        $s.FormBorderStyle = 'None'; $s.StartPosition = 'CenterScreen'; $s.ShowInTaskbar = $false; $s.TopMost = $true
        $s.ClientSize = New-Object Drawing.Size(480, 220); $s.BackColor = [Drawing.Color]::FromArgb(22, 50, 88); $s.Text = 'Windows Repair Toolkit'
        $rows = @(
            @('Windows Repair Toolkit', 22, 'Bold', 34, 48, 'White'),
            @('Brought to you by TheTechSupportGuru', 11, 'Regular', 96, 26, 'White'),
            @('Licensed under GNU GPL v3.0', 10, 'Regular', 124, 24, 'LightSteelBlue'),
            @("Loading $what ...", 9, 'Italic', 182, 22, 'Silver'))
        foreach ($r in $rows) {
            $l = New-Object Windows.Forms.Label
            $l.AutoSize = $false; $l.TextAlign = 'MiddleCenter'; $l.Text = $r[0]
            $l.Font = New-Object Drawing.Font('Segoe UI', [single]$r[1], [Drawing.FontStyle]$r[2])
            $l.ForeColor = [Drawing.Color]::FromName($r[5]); $l.BackColor = [Drawing.Color]::Transparent
            $l.Location = New-Object Drawing.Point(0, $r[3]); $l.Size = New-Object Drawing.Size(480, $r[4])
            $s.Controls.Add($l)
        }
        $s.Show(); $s.Refresh(); [Windows.Forms.Application]::DoEvents()
        $script:WrtSplash = $s; $script:WrtSplashAt = Get-Date
    } catch { $script:WrtSplash = $null }
}
function Close-WrtSplash {
    if (-not $script:WrtSplash) { return }
    try { $left = 1.2 - ((Get-Date) - $script:WrtSplashAt).TotalSeconds; if ($left -gt 0) { Start-Sleep -Milliseconds ([int]($left * 1000)) } } catch {}   # readable for at least ~1 s
    try { $script:WrtSplash.Close(); $script:WrtSplash.Dispose() } catch {}
    $script:WrtSplash = $null
}
# Call right before ShowDialog. Records how much room each scrollable area ($scroll: tab pages, panels) needs at its
# design size, so a small window scrolls instead of squeezing the controls together; sets the minimum size; opens
# maximized when the scaled window does not fit on the screen; then closes the splash screen.
function Initialize-WrtWindow($f, $scroll = @(), [int]$minW = 640, [int]$minH = 460) {
    $script:WrtForm = $f; $script:WrtMinWH = @($minW, $minH); $script:WrtExt = New-Object Collections.ArrayList
    foreach ($c in @($scroll)) {
        if (-not $c) { continue }
        $w = 0; $h = 0
        foreach ($k in $c.Controls) { if ($k.Dock -eq 'None') { $w = [Math]::Max($w, $k.Right); $h = [Math]::Max($h, $k.Bottom) } }
        [void]$script:WrtExt.Add(@($c, $w, $h))
    }
    $f.Add_Shown({ Complete-WrtWindow })
}
function Complete-WrtWindow {
    $f = $script:WrtForm; $k = Get-WrtScale $f
    foreach ($e in $script:WrtExt) { try { if ($e[1] -gt 0) { $e[0].AutoScroll = $true; $e[0].AutoScrollMinSize = New-Object Drawing.Size([int](($e[1] + 8) * $k), [int](($e[2] + 8) * $k)) } } catch {} }
    try { $f.MinimumSize = New-Object Drawing.Size([int]($script:WrtMinWH[0] * $k), [int]($script:WrtMinWH[1] * $k)) } catch {}
    try { $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea; if ($f.Width -gt $wa.Width -or $f.Height -gt $wa.Height) { $f.WindowState = 'Maximized' } } catch {}
    Close-WrtSplash
    try { $f.Activate() } catch {}
}
Show-WrtSplash 'Claude Log Analyzer'

$Model       = 'claude-sonnet-5-5'
$GeminiModel = 'gemini-flash-latest'   # if Google retires it, try 'gemini-2.5-flash' or another current Flash model
$SessionMin  = 60      # session length in minutes
$PairingMin  = 5       # how long each QR code stays valid
$ImageTypes  = @{ '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.gif'='image/gif'; '.webp'='image/webp' }
$MaxLogChars = 150000    # newest part of each log that is sent
$MaxTotalChars = 450000  # all logs together (keeps requests fast and inside model limits)
$MaxImageBytes = 3.5MB   # per image (raw); bigger ones are scaled down instead of refused
$MaxTotalImageB64 = 15MB # all images together, as base64
$ImageMaxEdge  = 2000    # bigger screenshots are scaled down before upload
$ConvertTypes  = @('.bmp', '.tif', '.tiff')
$SystemPrompt  = 'You are a Windows troubleshooting expert. Give a concise analysis: 1) Summary, 2) Key errors/findings, 3) Likely cause, 4) Step-by-step fixes. Use plain text, no markdown.'
$script:AiJob = $null; $script:TickErr = $false
$files       = New-Object System.Collections.ArrayList

$script:ApiKey = $null; $script:SessionEnd = [datetime]::MinValue
$script:Listener = $null; $script:Token = ''; $script:Pad = $null
$script:PairExpires = [datetime]::MinValue; $script:Attempts = 0
$script:QM = $null; $script:QF = $null

# =====================================================================
#  QR CODE ENCODER (byte mode, error correction L, versions 1-9)
# =====================================================================
$script:GfExp = New-Object 'int[]' 512
$script:GfLog = New-Object 'int[]' 256
$gx = 1
for ($i = 0; $i -lt 255; $i++) {
    $script:GfExp[$i] = $gx; $script:GfLog[$gx] = $i
    $gx = $gx -shl 1
    if ($gx -band 0x100) { $gx = $gx -bxor 0x11D }
}
for ($i = 255; $i -lt 512; $i++) { $script:GfExp[$i] = $script:GfExp[$i - 255] }

function GfMul($a, $b) {
    if ($a -eq 0 -or $b -eq 0) { return 0 }
    return $script:GfExp[$script:GfLog[$a] + $script:GfLog[$b]]
}

function Get-RsEc([int[]]$data, [int]$n) {
    $gen = @(1)
    for ($i = 0; $i -lt $n; $i++) {
        $new = New-Object 'int[]' ($gen.Length + 1)
        for ($j = 0; $j -lt $gen.Length; $j++) {
            $new[$j]     = $new[$j] -bxor $gen[$j]
            $new[$j + 1] = $new[$j + 1] -bxor (GfMul $gen[$j] $script:GfExp[$i])
        }
        $gen = $new
    }
    $rem = New-Object 'int[]' $n
    foreach ($b in $data) {
        $f = $b -bxor $rem[0]
        for ($k = 0; $k -lt $n - 1; $k++) { $rem[$k] = $rem[$k + 1] }
        $rem[$n - 1] = 0
        if ($f -ne 0) {
            for ($k = 0; $k -lt $n; $k++) { $rem[$k] = $rem[$k] -bxor (GfMul $gen[$k + 1] $f) }
        }
    }
    return ,$rem
}

function Set-QrModule($x, $y, $v) {
    if ($v) { $script:QM[$y, $x] = 1 } else { $script:QM[$y, $x] = 0 }
    $script:QF[$y, $x] = $true
}

function Add-Bits($list, [int]$val, [int]$cnt) {
    for ($i = $cnt - 1; $i -ge 0; $i--) { $list.Add(($val -shr $i) -band 1) }
}

function Set-QrFormat([int]$m, [int]$size) {
    $data = (1 -shl 3) -bor $m
    $rem = $data
    for ($k = 0; $k -lt 10; $k++) { $rem = ($rem -shl 1) -bxor (($rem -shr 9) * 0x537) }
    $fb = (($data -shl 10) -bor $rem) -bxor 0x5412
    for ($i = 0; $i -lt 6; $i++)  { Set-QrModule 8 $i ((($fb -shr $i) -band 1) -eq 1) }
    Set-QrModule 8 7 ((($fb -shr 6) -band 1) -eq 1)
    Set-QrModule 8 8 ((($fb -shr 7) -band 1) -eq 1)
    Set-QrModule 7 8 ((($fb -shr 8) -band 1) -eq 1)
    for ($i = 9; $i -lt 15; $i++) { Set-QrModule (14 - $i) 8 ((($fb -shr $i) -band 1) -eq 1) }
    for ($i = 0; $i -lt 8; $i++)  { Set-QrModule ($size - 1 - $i) 8 ((($fb -shr $i) -band 1) -eq 1) }
    for ($i = 8; $i -lt 15; $i++) { Set-QrModule 8 ($size - 15 + $i) ((($fb -shr $i) -band 1) -eq 1) }
    Set-QrModule 8 ($size - 8) $true
}

function New-QrMatrix([string]$text) {
    $dataCw = 0,19,34,55,80,108,136,156,194,232
    $ecPer  = 0,7,10,15,20,26,18,20,24,30
    $blocks = 0,1,1,1,1,1,2,2,2,2
    $align  = @($null, $null, @(6,18), @(6,22), @(6,26), @(6,30), @(6,34), @(6,22,38), @(6,24,42), @(6,26,46))

    $payload = [Text.Encoding]::UTF8.GetBytes($text)
    $n = $payload.Length
    $ver = 0
    for ($v = 1; $v -le 9; $v++) { if ((12 + 8 * $n) -le ($dataCw[$v] * 8)) { $ver = $v; break } }
    if ($ver -eq 0) { throw 'QR payload too long' }

    # data bits
    $bits = New-Object 'System.Collections.Generic.List[int]'
    Add-Bits $bits 4 4
    Add-Bits $bits $n 8
    foreach ($b in $payload) { Add-Bits $bits $b 8 }
    $cap = $dataCw[$ver] * 8
    Add-Bits $bits 0 ([Math]::Min(4, $cap - $bits.Count))
    while (($bits.Count % 8) -ne 0) { $bits.Add(0) }
    $cw = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $val = 0
        for ($j = 0; $j -lt 8; $j++) { $val = ($val -shl 1) -bor $bits[$i + $j] }
        $cw.Add($val)
    }
    $k = 0
    while ($cw.Count -lt $dataCw[$ver]) { if (($k % 2) -eq 0) { $cw.Add(0xEC) } else { $cw.Add(0x11) }; $k++ }

    # blocks + error correction + interleave
    $nb = $blocks[$ver]; $per = [int]($dataCw[$ver] / $nb); $ec = $ecPer[$ver]
    $db = @(); $eb = @()
    for ($b = 0; $b -lt $nb; $b++) {
        $blk = [int[]]($cw.GetRange($b * $per, $per).ToArray())
        $db += ,$blk
        $eb += ,(Get-RsEc $blk $ec)
    }
    $final = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $per; $i++) { for ($b = 0; $b -lt $nb; $b++) { $final.Add($db[$b][$i]) } }
    for ($i = 0; $i -lt $ec;  $i++) { for ($b = 0; $b -lt $nb; $b++) { $final.Add($eb[$b][$i]) } }

    # matrix and fixed patterns
    $size = 17 + 4 * $ver
    $script:QM = New-Object 'int[,]'  $size, $size
    $script:QF = New-Object 'bool[,]' $size, $size
    for ($i = 0; $i -lt $size; $i++) {
        Set-QrModule 6 $i (($i % 2) -eq 0)
        Set-QrModule $i 6 (($i % 2) -eq 0)
    }
    foreach ($c in @(@(3,3), @(($size - 4),3), @(3,($size - 4)))) {
        for ($dy = -4; $dy -le 4; $dy++) {
            for ($dx = -4; $dx -le 4; $dx++) {
                $xx = $c[0] + $dx; $yy = $c[1] + $dy
                if ($xx -ge 0 -and $xx -lt $size -and $yy -ge 0 -and $yy -lt $size) {
                    $d = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
                    Set-QrModule $xx $yy (($d -ne 2) -and ($d -ne 4))
                }
            }
        }
    }
    $pos = $align[$ver]
    if ($pos) {
        $last = $pos[$pos.Length - 1]
        foreach ($a in $pos) {
            foreach ($b in $pos) {
                if (($a -eq 6 -and $b -eq 6) -or ($a -eq 6 -and $b -eq $last) -or ($a -eq $last -and $b -eq 6)) { continue }
                for ($dy = -2; $dy -le 2; $dy++) {
                    for ($dx = -2; $dx -le 2; $dx++) {
                        $d = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
                        Set-QrModule ($a + $dx) ($b + $dy) ($d -ne 1)
                    }
                }
            }
        }
    }
    Set-QrFormat 0 $size
    if ($ver -ge 7) {
        $rem = $ver
        for ($k = 0; $k -lt 12; $k++) { $rem = ($rem -shl 1) -bxor (($rem -shr 11) * 0x1F25) }
        $vb = ($ver -shl 12) -bor $rem
        for ($i = 0; $i -lt 18; $i++) {
            $bit = ((($vb -shr $i) -band 1) -eq 1)
            $a = $size - 11 + ($i % 3); $b = [int][Math]::Floor($i / 3)
            Set-QrModule $a $b $bit
            Set-QrModule $b $a $bit
        }
    }

    # place data bits in the zigzag pattern
    $idx = 0; $total = $final.Count * 8; $right = $size - 1
    while ($right -ge 1) {
        if ($right -eq 6) { $right = 5 }
        $upward = ((($right + 1) -band 2) -eq 0)
        for ($vert = 0; $vert -lt $size; $vert++) {
            if ($upward) { $y = $size - 1 - $vert } else { $y = $vert }
            for ($j = 0; $j -lt 2; $j++) {
                $x = $right - $j
                if ((-not $script:QF[$y, $x]) -and ($idx -lt $total)) {
                    $script:QM[$y, $x] = (($final[($idx -shr 3)] -shr (7 - ($idx -band 7))) -band 1)
                    $idx++
                }
            }
        }
        $right -= 2
    }
    # mask 0, then final format bits
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            if ((-not $script:QF[$y, $x]) -and ((($x + $y) % 2) -eq 0)) { $script:QM[$y, $x] = $script:QM[$y, $x] -bxor 1 }
        }
    }
    Set-QrFormat 0 $size
    return @{ Size = $size; Mod = $script:QM }
}

function New-QrBitmap([string]$text, [int]$scale = 6) {
    $q = New-QrMatrix $text
    $n = $q.Size; $quiet = 4; $dim = ($n + 2 * $quiet) * $scale
    $bmp = New-Object System.Drawing.Bitmap $dim, $dim
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    for ($y = 0; $y -lt $n; $y++) {
        for ($x = 0; $x -lt $n; $x++) {
            if ($q.Mod[$y, $x] -eq 1) {
                $g.FillRectangle([System.Drawing.Brushes]::Black, ($x + $quiet) * $scale, ($y + $quiet) * $scale, $scale, $scale)
            }
        }
    }
    $g.Dispose()
    return $bmp
}

# =====================================================================
#  PAIRING SERVER (tiny HTTP listener on the local network, no admin rights needed)
# =====================================================================
$script:PageHtml = @'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>Connect PC</title>
<style>body{font-family:system-ui,sans-serif;margin:0;padding:24px;background:#f5f5f7;color:#111}
input,button{width:100%;box-sizing:border-box;font-size:17px;padding:14px;margin-top:12px;border-radius:10px;border:1px solid #bbb}
button{background:#d97757;color:#fff;border:0;font-weight:600}#m{color:#b00020;min-height:1.5em}</style></head><body>
<h2>Connect this PC</h2>
<p>Enter your Claude or Gemini API key. It is encrypted on this phone before it is sent. The PC forgets it after 1 hour.</p>
<input id="k" type="password" placeholder="Paste your API key" autocomplete="current-password" autocapitalize="off" autocorrect="off" spellcheck="false">
<button id="b">Send to PC</button><p id="m"></p>
<script>
(function(){
var m=document.getElementById('m');
function b64(s){s=s.replace(/-/g,'+').replace(/_/g,'/');while(s.length%4)s+='=';var r=atob(s),o=new Uint8Array(r.length);for(var i=0;i<r.length;i++)o[i]=r.charCodeAt(i);return o;}
document.getElementById('b').onclick=function(){
 var pad;try{pad=b64(location.hash.slice(1));}catch(e){pad=[];}
 if(!pad.length){m.textContent='Please scan the QR code again.';return;}
 var key=new TextEncoder().encode(document.getElementById('k').value.trim());
 if(!key.length||key.length>pad.length){m.textContent='That does not look like a valid key.';return;}
 var hex='';for(var i=0;i<key.length;i++){var v=key[i]^pad[i];hex+=(v<16?'0':'')+v.toString(16);}
 fetch(location.pathname.replace(/\/$/,'')+'/key',{method:'POST',body:hex}).then(function(r){
  if(r.ok){document.getElementById('k').value='';history.replaceState(null,'',location.pathname);
   document.body.innerHTML='<h2>Connected</h2><p>You can close this page. Click Log out on the PC when you are done.</p>';}
  else{m.textContent='The PC rejected the key. Check it and try again.';}
 }).catch(function(){m.textContent='Could not reach the PC. Are both on the same Wi-Fi?';});
};})();
</script></body></html>
'@

function Get-LanIp {
    try {
        $s = New-Object Net.Sockets.Socket ([Net.Sockets.AddressFamily]::InterNetwork), ([Net.Sockets.SocketType]::Dgram), ([Net.Sockets.ProtocolType]::Udp)
        $s.Connect('8.8.8.8', 53)
        $ip = $s.LocalEndPoint.Address.ToString(); $s.Close()
        if ($ip -ne '0.0.0.0') { return $ip }
    } catch {}
    foreach ($a in [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName())) {
        if ($a.AddressFamily -eq 'InterNetwork' -and -not $a.ToString().StartsWith('169.254')) { return $a.ToString() }
    }
    return '127.0.0.1'
}

function Stop-Pairing {
    if ($script:Listener) { try { $script:Listener.Stop() } catch {}; $script:Listener = $null }
    $script:Pad = $null; $script:Token = ''
}

function Start-Pairing {
    Stop-Pairing
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $pad = New-Object byte[] 128; $rng.GetBytes($pad)
    $tk  = New-Object byte[] 8;   $rng.GetBytes($tk)
    $rng.Dispose()
    $script:Pad = $pad
    $script:Token = ([BitConverter]::ToString($tk) -replace '-', '').ToLower()
    $script:Listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Any), 0
    $script:Listener.Start()
    $port = $script:Listener.LocalEndpoint.Port
    $b64 = [Convert]::ToBase64String($pad).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $script:PairExpires = (Get-Date).AddMinutes($PairingMin)
    $script:Attempts = 0; $script:PairConns = 0
    return ('http://{0}:{1}/{2}#{3}' -f (Get-LanIp), $port, $script:Token, $b64)
}

function Send-Resp($stream, [int]$code, [string]$ctype, [string]$body) {
    # correct reason phrase (it used to send "400 OK" and "404 OK")
    $reasonText = switch ($code) { 200 { 'OK' } 400 { 'Bad Request' } default { 'Not Found' } }
    $b = [Text.Encoding]::UTF8.GetBytes($body)
    $h = "HTTP/1.1 $code $reasonText`r`nContent-Type: $ctype; charset=utf-8`r`nContent-Length: $($b.Length)`r`nCache-Control: no-store`r`nReferrer-Policy: no-referrer`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($h)
    $stream.Write($hb, 0, $hb.Length); $stream.Write($b, 0, $b.Length); $stream.Flush()
}

function Handle-Client($client) {
    $client.ReceiveTimeout = 700; $client.SendTimeout = 700   # runs on the GUI thread: keep each client short
    $script:PairConns++                     # every connection counts toward the junk limit (see the timer)
    $stream = $client.GetStream()
    $buf = New-Object byte[] 8192; $total = 0; $hEnd = -1; $txt = ''
    # overall deadline: the 700 ms timeout is per Read, so a client sending one byte at a time could hold the GUI thread
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1500)
    while ($total -lt $buf.Length) {
        if ([DateTime]::UtcNow -gt $deadline) { return }
        $r = $stream.Read($buf, $total, $buf.Length - $total)
        if ($r -le 0) { break }
        $total += $r
        $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $total)
        $hEnd = $txt.IndexOf("`r`n`r`n")
        if ($hEnd -ge 0) {
            $len = 0
            if ($txt.Substring(0, $hEnd) -match '(?im)^content-length:\s*(\d+)') { $len = [int]$Matches[1] }
            if ($total -ge ($hEnd + 4 + $len)) { break }
        }
    }
    if ($hEnd -lt 0) { return }
    $head   = $txt.Substring(0, $hEnd) -split "`r`n"
    $parts  = $head[0] -split ' '
    if ($parts.Count -lt 2) { return }
    $method = $parts[0]
    $path   = ($parts[1] -split '\?')[0]
    $body   = $txt.Substring($hEnd + 4)
    $tok    = '/' + $script:Token

    if ($method -eq 'GET' -and $path -eq $tok) {
        Send-Resp $stream 200 'text/html' $script:PageHtml
    }
    elseif ($method -eq 'POST' -and $path -eq "$tok/key") {
        $ok = $false
        try {
            $hex = $body.Trim()
            if ($hex -match '^[0-9a-fA-F]+$' -and ($hex.Length % 2) -eq 0 -and ($hex.Length / 2) -le $script:Pad.Length) {
                $n = [int]($hex.Length / 2)
                $chars = New-Object char[] $n
                for ($i = 0; $i -lt $n; $i++) {
                    $chars[$i] = [char]([Convert]::ToInt32($hex.Substring(2 * $i, 2), 16) -bxor $script:Pad[$i])
                }
                $k = -join $chars
                if ($k -match '^(sk-ant-[A-Za-z0-9_\-]{10,}|AIza[A-Za-z0-9_\-]{30,})$') { $script:ApiKey = $k; $ok = $true }
            }
        } catch {}
        if ($ok) { Send-Resp $stream 200 'text/plain' 'OK' }
        # one rejected key ends this QR code: a second attempt with the same one-time pad would leak key XOR key
        else { $script:Attempts = 5; Send-Resp $stream 400 'text/plain' 'Invalid' }
    }
    else { Send-Resp $stream 404 'text/plain' 'Not found' }
}

# =====================================================================
#  UI
# =====================================================================
function New-Ctl($parent, $type, $x, $y, $w, $h, $text) {
    $c = New-Object "System.Windows.Forms.$type"
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, $h)
    if ($text) { $c.Text = $text }
    $parent.Controls.Add($c)
    return $c
}

$form = New-Object System.Windows.Forms.Form; Set-WrtScaling $form
$form.Text = 'Claude Log & Screenshot Analyzer'
$form.Size = New-Object System.Drawing.Size(900, 780)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

# ---- Login panel ----
$pnlLogin = New-Object System.Windows.Forms.Panel; $pnlLogin.Dock = 'Fill'; $form.Controls.Add($pnlLogin)
$lblTitle = New-Ctl $pnlLogin Label 0 15 880 40 'Scan to log in'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18); $lblTitle.TextAlign = 'MiddleCenter'
$lblHow = New-Ctl $pnlLogin Label 90 58 700 50 'Open your phone camera, scan this code, then enter your API key on the phone. Your phone and this PC must be on the same Wi-Fi.'
$lblHow.TextAlign = 'MiddleCenter'
$picQr = New-Ctl $pnlLogin PictureBox 245 115 400 400 ''
$picQr.SizeMode = 'Normal'
$lblCount  = New-Ctl $pnlLogin Label 0 600 880 28 ''
$lblCount.TextAlign = 'MiddleCenter'
$btnNewQr  = New-Ctl $pnlLogin Button 345 635 200 38 'New QR code'
$lblNotice = New-Ctl $pnlLogin Label 90 685 700 50 ''
$lblNotice.TextAlign = 'MiddleCenter'; $lblNotice.ForeColor = [System.Drawing.Color]::DarkRed

# ---- Main panel ----
$pnlMain = New-Object System.Windows.Forms.Panel; $pnlMain.Dock = 'Fill'; $pnlMain.Visible = $false; $form.Controls.Add($pnlMain)
$lblSession = New-Ctl $pnlMain Label 15 18 350 26 ''
$btnLogout  = New-Ctl $pnlMain Button 745 12 125 34 'Log out'
$btnLogout.Anchor = 'Top,Right'
[void](New-Ctl $pnlMain Label 375 17 95 26 'Analyze with:')
$cmbAi = New-Ctl $pnlMain ComboBox 475 12 250 30 ''
$cmbAi.DropDownStyle = 'DropDownList'
[void]$cmbAi.Items.AddRange(@('Claude (Anthropic)', 'Gemini (Google)'))
$cmbAi.SelectedIndex = 0
$cmbAi.Add_SelectedIndexChanged({
    if ($cmbAi.SelectedIndex -eq 1) { $status.Text = 'Gemini free tier: Google may use content to improve its products. Avoid sensitive logs.' }
    else { $status.Text = 'Ready.' }
})

$btnBrowse = New-Ctl $pnlMain Button 15 58 150 34 'Browse...'
$btnRemove = New-Ctl $pnlMain Button 175 58 150 34 'Remove selected'
$btnClear  = New-Ctl $pnlMain Button 335 58 100 34 'Clear'

$lst = New-Ctl $pnlMain ListBox 15 100 855 130 ''
$lst.SelectionMode = 'MultiExtended'; $lst.HorizontalScrollbar = $true; $lst.AllowDrop = $true
$lst.Anchor = 'Top,Left,Right'

[void](New-Ctl $pnlMain Label 15 240 400 24 'Prompt (optional):')
$txtPrompt = New-Ctl $pnlMain TextBox 15 265 855 80 'Analyze these files. Identify errors, likely root causes, and recommended fixes.'
$txtPrompt.Multiline = $true; $txtPrompt.ScrollBars = 'Vertical'; $txtPrompt.Anchor = 'Top,Left,Right'

$btnGo = New-Ctl $pnlMain Button 15 355 700 42 'Upload && Analyze'
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11); $btnGo.Anchor = 'Top,Left,Right'
$btnCancel = New-Ctl $pnlMain Button 725 355 145 42 'Cancel'
$btnCancel.Anchor = 'Top,Right'; $btnCancel.Enabled = $false

[void](New-Ctl $pnlMain Label 15 407 400 24 'Analysis:')
$txtOut = New-Ctl $pnlMain TextBox 15 433 855 250 ''
$txtOut.Multiline = $true; $txtOut.ReadOnly = $true; $txtOut.ScrollBars = 'Vertical'
$txtOut.BackColor = [System.Drawing.Color]::White; $txtOut.Anchor = 'Top,Bottom,Left,Right'

$status = New-Ctl $pnlMain Label 15 695 855 24 'Ready.'
$status.Anchor = 'Bottom,Left,Right'

# ---- reading files for the request (same code as WinSuperTool's AI tab) ----
# reads the newest $maxChars characters of a text file, even while Windows is writing to it
# (ReadAllText failed on logs Windows holds open, and loaded whole multi-hundred-MB files into memory)
function Read-TextTail([string]$path, [int]$maxChars) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite,Delete')
    try {
        $enc = [Text.Encoding]::UTF8
        $bom = New-Object byte[] 4
        $got = $fs.Read($bom, 0, 4)
        if ($got -ge 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { $enc = [Text.Encoding]::Unicode }
        elseif ($got -ge 2 -and $bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { $enc = [Text.Encoding]::BigEndianUnicode }
        $bpc = 1; if ($enc -is [Text.UnicodeEncoding]) { $bpc = 2 }
        $start = [Math]::Max([long]0, $fs.Length - ([long]$maxChars * $bpc))
        if ($bpc -eq 2) { $start -= ($start % 2) }
        $fs.Position = $start
        $sr = New-Object IO.StreamReader($fs, $enc, ($start -eq 0))
        $text = $sr.ReadToEnd()
        return @{ Text = $text; Truncated = ($start -gt 0) }
    } finally { $fs.Dispose() }
}
function Read-LogForAi([string]$path, [int]$cap) {
    $trunc = $false
    if ([IO.Path]::GetExtension($path).ToLower() -eq '.evtx') {
        $ev = @(Get-WinEvent -FilterHashtable @{ Path = $path; Level = 1, 2, 3 } -MaxEvents 400 -ErrorAction SilentlyContinue)
        $hdr = 'Critical / Error / Warning events only, newest first:'
        if (-not $ev.Count) { $ev = @(Get-WinEvent -Path $path -MaxEvents 400 -ErrorAction SilentlyContinue); $hdr = 'Newest events (no errors or warnings found):' }
        if (-not $ev.Count) { return @{ Text = '(this event log contains no events)'; Truncated = $false; Binary = $false } }
        $lines = foreach ($e in $ev) {
            $m = $e.Message
            if (-not $m) { $m = '(no message text) ' + ((@($e.Properties) | ForEach-Object { $_.Value }) -join '; ') }
            '{0} [{1}] {2} (ID {3}): {4}' -f $e.TimeCreated, $e.LevelDisplayName, $e.ProviderName, $e.Id, ($m -replace '\s+', ' ')
        }
        $text = $hdr + "`n" + (@($lines) -join "`n")
    } else {
        # known binary formats (ETL traces, dumps, hives, archives) are never sent as text
        if ([IO.Path]::GetExtension($path).ToLower() -in '.etl', '.dmp', '.hiv', '.dat', '.zip', '.cab', '.exe', '.dll', '.sys', '.bin', '.db', '.edb', '.mdmp', '.hdmp') { return @{ Binary = $true } }
        $t = Read-TextTail $path $cap
        $text = $t.Text; $trunc = $t.Truncated
        # binary data decoded as UTF-8 mostly turns into U+FFFD replacement characters, so count those as well
        if ($text.Length -gt 200 -and ([regex]::Matches($text, '[\x00-\x08\x0E-\x1A\uFFFD]')).Count -gt ($text.Length / 20)) { return @{ Binary = $true } }
        $text = $text.Replace([string][char]0, '')
    }
    if ($text.Length -gt $cap) {
        # event logs are listed NEWEST FIRST, so keep the start; text logs grow at the end, so keep the end
        if ([IO.Path]::GetExtension($path) -ieq '.evtx') { $text = $text.Substring(0, $cap) } else { $text = $text.Substring($text.Length - $cap) }
        $trunc = $true
    }
    return @{ Text = $text; Truncated = $trunc; Binary = $false }
}
# returns @{ Mime; Data(base64); Note } - converts BMP/TIFF and shrinks oversized screenshots to JPEG
# (it used to refuse any image over 5 MB and stop the whole request)
function Get-ImagePart([string]$path) {
    $ext  = [IO.Path]::GetExtension($path).ToLower()
    $len  = (Get-Item -LiteralPath $path).Length
    $mime = $ImageTypes[$ext]
    $convert = (-not $mime) -or ($len -gt $MaxImageBytes)
    $img = $null; $bmp = $null; $g = $null; $ms = $null
    try {
        if (-not $convert -and $ext -ne '.webp' -and $ext -ne '.gif') {
            # a file that GDI+ cannot decode is not a usable picture: sending it would make the API reject the WHOLE request
            try { $img = [Drawing.Image]::FromFile($path) } catch { throw 'not a valid image file' }
            if ([Math]::Max($img.Width, $img.Height) -gt $ImageMaxEdge) { $convert = $true }
        }
        if (-not $convert) { return @{ Mime = $mime; Data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)); Note = '' } }
        if (-not $img) { $img = [Drawing.Image]::FromFile($path) }
        $scale = [Math]::Min(1.0, $ImageMaxEdge / [double][Math]::Max($img.Width, $img.Height))
        $nw = [Math]::Max(1, [int]($img.Width * $scale)); $nh = [Math]::Max(1, [int]($img.Height * $scale))
        $bmp = New-Object Drawing.Bitmap $nw, $nh
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([Drawing.Color]::White)
        $g.DrawImage($img, 0, 0, $nw, $nh)
        $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $ep = New-Object Drawing.Imaging.EncoderParameters 1
        $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality, [long]85)
        $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, $codec, $ep)
        return @{ Mime = 'image/jpeg'; Data = [Convert]::ToBase64String($ms.ToArray()); Note = " (converted to ${nw}x${nh} JPEG for upload)" }
    } catch {
        throw "Image '$([IO.Path]::GetFileName($path))' could not be prepared: $($_.Exception.Message)"
    } finally {
        foreach ($o in $g, $bmp, $ms, $img) { if ($o) { try { $o.Dispose() } catch {} } }
    }
}
function ConvertTo-JsonText([string]$s) {
    if ($null -eq $s) { return 'null' }
    $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    $s = [regex]::Replace($s, '[\x00-\x1F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    return '"' + $s + '"'
}
function New-AiRequest([bool]$gemini) {
    $parts  = New-Object 'System.Collections.Generic.List[string]'
    $notes  = New-Object 'System.Collections.Generic.List[string]'
    $budget = $MaxTotalChars
    $addText = {
        param($t)
        if ($gemini) { $parts.Add('{"text":' + (ConvertTo-JsonText $t) + '}') }
        else { $parts.Add('{"type":"text","text":' + (ConvertTo-JsonText $t) + '}') }
    }
    $imgBytes = 0
    foreach ($f in @($files)) {
        $name = [IO.Path]::GetFileName($f)
        $ext  = [IO.Path]::GetExtension($f).ToLower()
        $status.Text = "Preparing $name ..."; [Windows.Forms.Application]::DoEvents()
        if ($ImageTypes.ContainsKey($ext) -or $ConvertTypes -contains $ext) {
            # one unreadable file must not cancel the whole request: skip it and say so in the prompt
            try { $img = Get-ImagePart $f } catch { $notes.Add("not sent ($($_.Exception.Message)): $name"); continue }
            if ($imgBytes + $img.Data.Length -gt $MaxTotalImageB64) { $notes.Add("not sent (image size budget used up): $name"); continue }
            $imgBytes += $img.Data.Length
            & $addText ("Image file: $name" + $img.Note)
            if ($gemini) { $parts.Add('{"inline_data":{"mime_type":"' + $img.Mime + '","data":"' + $img.Data + '"}}') }
            else { $parts.Add('{"type":"image","source":{"type":"base64","media_type":"' + $img.Mime + '","data":"' + $img.Data + '"}}') }
        } else {
            if ($budget -lt 2000) { $notes.Add("not sent (size budget used up): $name"); continue }
            try { $r = Read-LogForAi $f ([Math]::Min($MaxLogChars, $budget)) } catch { $notes.Add("not sent (could not read: $($_.Exception.Message)): $name"); continue }
            if ($r.Binary) { $notes.Add("not sent (binary file): $name"); continue }
            $budget -= $r.Text.Length
            $label = "Log file: $name"
            if ($r.Truncated) { $label += ' (truncated - newest part only)' }
            & $addText ($label + "`n-----`n" + $r.Text + "`n-----")
        }
    }
    $userPrompt = $txtPrompt.Text.Trim()
    if (-not $userPrompt) { $userPrompt = 'Analyze these files and give a short summary of problems and fixes.' }
    if ($notes.Count) { $userPrompt += "`n`n(Note: some files were not included: " + ($notes -join '; ') + ')' }
    & $addText $userPrompt

    $joined = $parts -join ','
    if ($gemini) {
        $json = '{"system_instruction":{"parts":[{"text":' + (ConvertTo-JsonText $SystemPrompt) + '}]},"contents":[{"role":"user","parts":[' + $joined + ']}],"generationConfig":{"maxOutputTokens":8192}}'
        $uri = "https://generativelanguage.googleapis.com/v1beta/models/$($GeminiModel):generateContent"
        $headers = @{ 'x-goog-api-key' = $script:ApiKey }
    } else {
        # max_tokens 16000: on Sonnet 5.5 adaptive thinking is on by default and its tokens count toward max_tokens, so 2500
        # could leave little or no room for the answer (16000 is the recommended ceiling for a non-streaming request).
        # "fallbacks":"default" (beta) lets the API retry a refused request on a fallback model instead of returning nothing.
        $json = '{"model":' + (ConvertTo-JsonText $Model) + ',"max_tokens":16000,"fallbacks":"default","system":' + (ConvertTo-JsonText $SystemPrompt) + ',"messages":[{"role":"user","content":[' + $joined + ']}]}'
        $uri = 'https://api.anthropic.com/v1/messages'
        $headers = @{ 'x-api-key' = $script:ApiKey; 'anthropic-version' = '2023-06-01'; 'anthropic-beta' = 'server-side-fallback-2026-07-01' }
    }
    return @{ Uri = $uri; Headers = $headers; Body = [Text.Encoding]::UTF8.GetBytes($json); Notes = $notes }
}
# the web request runs in a background runspace so the window stays responsive and can be cancelled
# (it used to block the window for up to 3 minutes, with no cancel and no session-expiry check)
function Start-AiRequest($req, [bool]$gemini) {
    $ps = [PowerShell]::Create()
    $job = {
        param($u, $h, $b)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            # Invoke-WebRequest + explicit UTF-8 decode: PS 5.1 would read a charset-less JSON reply as ISO-8859-1
            $w = Invoke-WebRequest -Uri $u -Method Post -Body $b -ContentType 'application/json; charset=utf-8' -Headers $h -TimeoutSec 600 -UseBasicParsing -ErrorAction Stop
            $r = [Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
            [pscustomobject]@{ Ok = $true; Resp = $r; Err = '' }
        } catch {
            $m = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
            [pscustomobject]@{ Ok = $false; Resp = $null; Err = $m }
        }
    }
    [void]$ps.AddScript($job.ToString()).AddArgument($req.Uri).AddArgument($req.Headers).AddArgument($req.Body)
    $script:AiJob = @{ PS = $ps; Handle = $ps.BeginInvoke(); Gemini = $gemini; Started = Get-Date }
}
function Stop-AiRequest {
    if ($script:AiJob) { try { [void]$script:AiJob.PS.BeginStop($null, $null) } catch {} }
}
function Get-AnswerText($resp, [bool]$gemini) {
    if ($gemini) {
        $cand = @($resp.candidates)
        $out = ''
        if ($cand.Count -and $cand[0].content) { $out = (@($cand[0].content.parts) | ForEach-Object { $_.text }) -join "`r`n" }
        if (-not $out) {
            # a blocked prompt has no candidates at all (this used to throw "Cannot index into a null array")
            $why = ''
            if ($cand.Count) { $why = $cand[0].finishReason }
            if ($resp.promptFeedback) { $why += ' ' + $resp.promptFeedback.blockReason }
            $out = "No response text was returned (reason: $($why.Trim())). The content may have been blocked by Google."
        } elseif ($cand[0].finishReason -eq 'MAX_TOKENS') { $out += "`r`n`r`n[The answer was cut off at the length limit.]" }
    } else {
        $out = (@($resp.content) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`r`n"
        if ($resp.stop_reason -eq 'refusal') {
            $cat = ''; if ($resp.stop_details -and $resp.stop_details.category) { $cat = " (category: $($resp.stop_details.category))" }
            $out = "Claude declined to analyze this request$cat." + $(if ($out) { "`r`n`r`nPartial text:`r`n$out" } else { '' })
        } elseif ($resp.stop_reason -eq 'max_tokens') { $out += "`r`n`r`n[The answer was cut off at the length limit.]" }
        if (-not $out) { $out = "No response text was returned (stop_reason: $($resp.stop_reason))." }
    }
    return $out
}
function Complete-AiRequest {
    $job = $script:AiJob; $script:AiJob = $null
    $btnGo.Enabled = $true; $btnCancel.Enabled = $false; $form.Cursor = 'Default'
    $res = $null
    try { $res = $job.PS.EndInvoke($job.Handle) }
    catch { $status.Text = 'Cancelled.'; try { $job.PS.Dispose() } catch {}; return }
    try { $job.PS.Dispose() } catch {}
    $r = $null
    if ($res -and $res.Count) { $r = $res[0] }
    if (-not $r) { $txtOut.Text = 'Error: no result was returned.'; $status.Text = 'Failed.'; return }
    if (-not $r.Ok) { $txtOut.Text = "Error:`r`n" + $r.Err; $status.Text = 'Failed.'; return }
    $out = Get-AnswerText $r.Resp $job.Gemini
    if ($job.Notes -and $job.Notes.Count) { $out += "`n`n[Not included: " + ($job.Notes -join '; ') + ']' }
    $txtOut.Text = ($out -replace "(?<!`r)`n", "`r`n")
    $status.Text = "Done in $([int]((Get-Date) - $job.Started).TotalSeconds) s."
}

# ---- Session / pairing logic ----
function Show-NewQr {
    $form.Cursor = 'WaitCursor'
    $lblCount.Text = 'Generating QR code...'; $form.Refresh()
    try {
        $url = Start-Pairing
        $old = $picQr.Image
        $bmp = New-QrBitmap $url 6
        $picQr.Size = $bmp.Size
        $picQr.Left = [int](($pnlLogin.ClientSize.Width - $bmp.Width) / 2)
        $picQr.Image = $bmp
        if ($old) { $old.Dispose() }
    } catch {
        $lblCount.Text = "Could not start login: $($_.Exception.Message)"
    } finally { $form.Cursor = 'Default' }
}
function Clear-Qr {
    Stop-Pairing
    $old = $picQr.Image; $picQr.Image = $null; if ($old) { $old.Dispose() }
}

function Enter-Session {
    $script:SessionEnd = (Get-Date).AddMinutes($SessionMin)
    $lblNotice.Text = ''
    if ($script:ApiKey.StartsWith('AIza')) { $cmbAi.SelectedIndex = 1 } else { $cmbAi.SelectedIndex = 0 }
    Clear-Qr      # the old QR code stayed in memory and on the hidden panel
    $pnlLogin.Visible = $false; $pnlMain.Visible = $true
    $status.Text = 'Logged in via phone. Add your files.'
}

function Exit-Session([string]$msg) {
    Stop-AiRequest      # a running request is cancelled when the session ends
    $script:ApiKey = $null
    $files.Clear(); $lst.Items.Clear(); $txtOut.Clear()
    $pnlMain.Visible = $false; $pnlLogin.Visible = $true
    $lblNotice.Text = $msg
    Show-NewQr
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    try {
        $now = Get-Date
        if ($script:AiJob -and $script:AiJob.Handle.IsCompleted) { Complete-AiRequest }
        if (-not $script:ApiKey) {
            if ($script:Listener) {
                if ($now -gt $script:PairExpires -or $script:Attempts -ge 5 -or $script:PairConns -ge 40) {
                    Clear-Qr
                    $lblCount.Text = 'This QR code is no longer valid. Click "New QR code".'
                } else {
                    $lblCount.Text = 'Waiting for your phone... code valid for ' + ($script:PairExpires - $now).ToString('m\:ss')
                    # at most 3 clients per tick: this runs on the GUI thread, so a flood of connections must not freeze the window
                    $n = 0
                    while ($script:Listener -and $n -lt 3 -and $script:Listener.Pending()) {
                        $n++
                        $c = $script:Listener.AcceptTcpClient()
                        try { Handle-Client $c } catch {} finally { $c.Close() }
                        if ($script:ApiKey) { break }
                    }
                    if ($script:ApiKey) { Enter-Session }
                }
            }
        } else {
            $left = $script:SessionEnd - $now
            if ($left.TotalSeconds -le 0) { Exit-Session "Your $SessionMin-minute session ended. Scan a new QR code to continue." }
            else { $lblSession.Text = 'Session ends in ' + $left.ToString('hh\:mm\:ss') }
        }
    } catch {
        # an error here would otherwise pop up a WinForms error box 4 times a second
        if (-not $script:TickErr) { $script:TickErr = $true; $status.Text = "Timer error: $($_.Exception.Message)" }
    }
})

$btnNewQr.Add_Click({ $lblNotice.Text = ''; Show-NewQr })
$btnLogout.Add_Click({ Exit-Session 'Logged out. Key and files cleared from this PC.' })
$form.Add_Shown({ Show-NewQr; $timer.Start() })
$form.Add_FormClosing({ $timer.Stop(); Stop-AiRequest; Stop-Pairing; $script:ApiKey = $null })

# ---- File handling ----
function Add-Files($paths) {
    foreach ($p in @($paths)) {
        if (-not $p) { continue }
        # -LiteralPath: names with [ ] used to be read as wildcards and silently ignored
        if ((Test-Path -LiteralPath $p -PathType Leaf) -and -not $files.Contains($p)) {
            [void]$files.Add($p); [void]$lst.Items.Add($p)
        }
    }
    $status.Text = "$($files.Count) file(s) selected."
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Filter = 'Logs and images|*.log;*.txt;*.csv;*.evtx;*.json;*.xml;*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp|All files|*.*'
    if ($dlg.ShowDialog() -eq 'OK') { Add-Files $dlg.FileNames }
})
$btnRemove.Add_Click({
    foreach ($i in @($lst.SelectedItems)) { $files.Remove($i); $lst.Items.Remove($i) }
    $status.Text = "$($files.Count) file(s) selected."
})
$btnClear.Add_Click({ $files.Clear(); $lst.Items.Clear(); $status.Text = 'Cleared.' })
# only accept dropped FILES (dropped text used to be passed on as a list of nulls)
$lst.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } else { $_.Effect = 'None' } })
$lst.Add_DragDrop({ Add-Files $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop) })

$btnGo.Add_Click({
    if (-not $script:ApiKey -or (Get-Date) -gt $script:SessionEnd) { Exit-Session 'Session ended. Scan a new QR code.'; return }
    if ($script:AiJob) { return }
    if ($files.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Add at least one file.'); return }
    $isGemini    = ($cmbAi.SelectedIndex -eq 1)
    $isGeminiKey = $script:ApiKey.StartsWith('AIza')
    if ($isGemini -ne $isGeminiKey) {
        $want = if ($isGeminiKey) { 'Gemini' } else { 'Claude' }
        [void][System.Windows.Forms.MessageBox]::Show("The selected AI does not match the key you logged in with. Switch the dropdown to $want, or log out and scan again with the other key.")
        return
    }
    $btnGo.Enabled = $false
    $txtOut.Text = ''
    try {
        $form.Cursor = 'WaitCursor'
        $req = New-AiRequest $isGemini
        Start-AiRequest $req $isGemini
        $script:AiJob.Notes = $req.Notes
        $btnCancel.Enabled = $true
        $mb = '{0:N1}' -f ($req.Body.Length / 1MB)
        $status.Text = "Analyzing ($mb MB sent)... the window stays usable; this can take a minute."
        if ($req.Notes.Count) { $txtOut.Text = 'Not included: ' + ($req.Notes -join '; ') }
    } catch {
        $txtOut.Text = "Error:`r`n$($_.Exception.Message)"
        $status.Text = 'Failed.'
        $btnGo.Enabled = $true
    } finally { $form.Cursor = 'Default' }
})
$btnCancel.Add_Click({ Stop-AiRequest; $btnCancel.Enabled = $false; $status.Text = 'Cancelling...' })

Initialize-WrtWindow $form @($pnlLogin, $pnlMain) 700 560
[void]$form.ShowDialog()
