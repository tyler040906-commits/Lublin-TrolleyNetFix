param(
    [Parameter(Mandatory=$true)][string]$Tile
)
$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function F6($v) { ([double]$v).ToString('F6', $inv) }
$bytes = [System.IO.File]::ReadAllBytes($Tile)
$enc = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { New-Object System.Text.UTF8Encoding($true) }
       elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode }
       else { [System.Text.Encoding]::Default }
$lines = New-Object System.Collections.Generic.List[string]
foreach ($l in [System.IO.File]::ReadAllLines($Tile, $enc)) { $lines.Add($l) }
if ($lines -match '^3001000$' -or $lines -match '^3001001$') { throw 'stay IDs already present' }

# A-A': 0.52 m cross-piece at the bend
$cross = @(
    '[spline]','0','Splines\Lublin\kabel.sli','3001000','0','0',
    '265.129105','23.945000','214.828073','207.761309','0.520000',
    '0','0','0','0','0','0','0','0'
)
# A-S20: horizontal-ish stay from the upper wire end to the pole (zbase 23.945 -> 24.170 over 6.060 m)
$stay = @(
    '[spline]','0','Splines\Lublin\kabel.sli','3001001','0','0',
    '265.129105','23.945000','214.828073','79.359930','6.060089',
    '0','3.712817','3.712817','0','0','0','0','0'
)
$insertAt = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^Object Nr\.') { $insertAt = $i; break } }
if ($insertAt -lt 0) { $insertAt = $lines.Count }
$prefix = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $insertAt; $i++) { $prefix.Add($lines[$i]) }
$suffix = New-Object System.Collections.Generic.List[string]
for ($i = $insertAt; $i -lt $lines.Count; $i++) { $suffix.Add($lines[$i]) }
$out = New-Object System.Collections.Generic.List[string]
foreach ($l in $prefix) { $out.Add($l) }
foreach ($l in $cross) { $out.Add($l) }
$out.Add('')
foreach ($l in $stay) { $out.Add($l) }
$out.Add('')
foreach ($l in $suffix) { $out.Add($l) }
[System.IO.File]::WriteAllLines($Tile, $out, $enc)
Write-Host ('added two kabel stays to ' + $Tile)

