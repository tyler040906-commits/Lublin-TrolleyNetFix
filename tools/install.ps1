param(
    [string]$OmsiRoot,
    [string]$MapName = 'Projekt_Lublin_2017',
    [switch]$Revert,
    [switch]$KeepCaches
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OmsiRoot)) {
    $found = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'find-omsi.ps1')
    if ($found) { $OmsiRoot = @($found)[0].Trim() }
    if ([string]::IsNullOrWhiteSpace($OmsiRoot)) { $OmsiRoot = Read-Host 'OMSI 2 folder' }
}
if ([string]::IsNullOrWhiteSpace($OmsiRoot)) { throw 'No OMSI 2 folder given.' }
$pkg    = Split-Path -Parent $PSScriptRoot
$tools  = $PSScriptRoot
$map    = Join-Path $OmsiRoot "maps\$MapName"
$o3dDir = Join-Path $OmsiRoot 'Sceneryobjects\Lublin\Kostki sterujace ruchem AI\model'
$splDir = Join-Path $OmsiRoot 'Splines\Lublin'
$state  = Join-Path $OmsiRoot 'Addons\Lublin-TrolleyNetFix\_install_state'
$origTiles = Join-Path $state 'original_tiles'
$origO3d   = Join-Path $state 'original_o3d'
$origSli   = Join-Path $state 'original_sli'
$removedTxt = Join-Path $state 'trolley.txt.removed'
$work      = Join-Path $state 'work'
$legacyState = Join-Path $OmsiRoot 'Addons\Lublin-TrolleyNet\_install_state'
if (-not (Test-Path $origTiles) -and (Test-Path (Join-Path $legacyState 'original_tiles'))) {
    $state = $legacyState
    $origTiles = Join-Path $state 'original_tiles'
    $origO3d   = Join-Path $state 'original_o3d'
    $origSli   = Join-Path $state 'original_sli'
    $removedTxt = Join-Path $state 'trolley.txt.removed'
    $work      = Join-Path $state 'work'
}

$requiredO3d = @('Rondo_Krupskiego.o3d','UniiXZamojska.o3d','RondoLubelskiegoLipca3.o3d','DMMXWolska.o3d','GrygowejXPancerniakow.o3d','zamojska.o3d','zamojska2.o3d')

function Assert-Path($p, $what) { if (-not (Test-Path -LiteralPath $p)) { throw "$what not found: $p" } }
function Count-TrolejbusBlocks([string]$dir) {
    $n = 0
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter 'tile_*.map') {
        $L = [System.IO.File]::ReadAllLines($f.FullName)
        for ($i = 0; $i -lt $L.Count - 2; $i++) {
            if ($L[$i].Trim() -eq '[spline]' -and $L[$i + 2].Trim() -match 'trolejbus\.sli$') { $n++ }
        }
    }
    return $n
}
function Run-Tool([string]$script, [string[]]$argsList) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script @argsList
    if ($LASTEXITCODE -ne 0) { throw ("tool failed: " + $script) }
}

Assert-Path $OmsiRoot 'OMSI root'
Assert-Path $map 'map folder'
Assert-Path $o3dDir 'Kostki sterujace ruchem AI model folder'
if ((Get-ChildItem -LiteralPath $map -Filter 'tile_*.map').Count -ne 273) { throw 'expected 273 tile_*.map files' }
foreach ($n in $requiredO3d) { Assert-Path (Join-Path $o3dDir $n) ('O3D ' + $n) }

# ---------- revert ----------
if ($Revert) {
    Assert-Path $origTiles 'original tile backup (install first)'
    Copy-Item (Join-Path $origTiles 'tile_*.map') $map -Force
    foreach ($n in $requiredO3d) { Copy-Item (Join-Path $origO3d $n) $o3dDir -Force }
    if (Test-Path (Join-Path $origSli 'trolejbus.sli')) { Copy-Item (Join-Path $origSli 'trolejbus.sli') $splDir -Force }
    if (Test-Path (Join-Path $origSli 'kabel.sli')) { Copy-Item (Join-Path $origSli 'kabel.sli') $splDir -Force }
    if (Test-Path $removedTxt) { Copy-Item $removedTxt (Join-Path $map 'trolley.txt') -Force }
    elseif (Test-Path (Join-Path $map 'trolley.txt')) { Remove-Item (Join-Path $map 'trolley.txt') -Force }
    if (-not $KeepCaches) {
        Get-ChildItem -LiteralPath $map -Filter '*.map.prt' -ErrorAction SilentlyContinue | Remove-Item -Force
        Get-ChildItem -LiteralPath $map -Filter 'tile_*.rdy' -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    Write-Host 'Reverted tiles, O3D, SLI and trolley.txt from _install_state.'
    exit 0
}

# ---------- first-run backup ----------
$upgrade = $false
if (-not (Test-Path -LiteralPath $origTiles)) {
    $existing = Count-TrolejbusBlocks $map
    if ($existing -ge 12000) {
        $upgrade = $true
        Write-Host 'detected a previous generated-contact version; upgrading in place (no clean 3.1 source needed).'
    } elseif ($existing -gt 2000 -or $existing -lt 900) {
        throw "the map is not a clean 3.1 map (contact spline blocks: $existing). Restore a clean 3.1 map first."
    }
    New-Item -ItemType Directory -Force -Path $origTiles, $origO3d, $origSli, $state | Out-Null
    Copy-Item (Join-Path $map 'tile_*.map') $origTiles -Force
    foreach ($n in $requiredO3d) { Copy-Item (Join-Path $o3dDir $n) $origO3d -Force }
    if (Test-Path (Join-Path $splDir 'trolejbus.sli')) { Copy-Item (Join-Path $splDir 'trolejbus.sli') $origSli -Force }
    if (Test-Path (Join-Path $splDir 'kabel.sli')) { Copy-Item (Join-Path $splDir 'kabel.sli') $origSli -Force }
    if (Test-Path (Join-Path $map 'trolley.txt')) { Copy-Item (Join-Path $map 'trolley.txt') $removedTxt -Force }
    Write-Host ('backup created: ' + $state)
}
if ((Get-ChildItem -LiteralPath $origTiles -Filter 'tile_*.map').Count -ne 273) { throw 'original tile backup is incomplete' }

# ---------- generate in a clean work directory ----------
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null
$workTiles = Join-Path $work 'tiles'
$workO3d = Join-Path $work 'o3d'

Write-Host '[1/4] generating contact splines with 15 m switch-neighbourhood collinear merge...'
Run-Tool (Join-Path $tools 'lib\rewrite_map_splines_merged.ps1') @(
    '-Txt', (Join-Path $pkg 'data\trolley.network.txt'),
    '-SourceMap', $origTiles,
    '-OutMap', $workTiles
)

$srcKabel = 0
foreach ($f in Get-ChildItem -LiteralPath $origTiles -Filter 'tile_*.map') {
    $L = [System.IO.File]::ReadAllLines($f.FullName)
    for ($i = 0; $i -lt $L.Count - 2; $i++) {
        if ($L[$i].Trim() -eq '[spline]' -and $L[$i + 2].Trim() -match 'kabel\.sli$') { $srcKabel++ }
    }
}
if ($srcKabel -lt 1200) {
    Write-Host '[2/4] adding stay splines...'
    Run-Tool (Join-Path $tools 'lib\add_stays.ps1') @(
        '-StaysCsv', (Join-Path $pkg 'data\o3d_stays.csv'),
        '-MapDir', $workTiles
    )
    Run-Tool (Join-Path $tools 'lib\add_custom_stays.ps1') @('-Tile', (Join-Path $workTiles 'tile_-13_1.map'))
} else {
    Write-Host ('[2/4] source already has ' + $srcKabel + ' kabel stays; skipping stay insertion.')
}
Write-Host '[3/4] processing local O3D high layers...'
Run-Tool (Join-Path $tools 'lib\remove_o3d_high.ps1') @('-Root', $origO3d, '-OutDir', $workO3d)

# ---------- verify generated output ----------
$tileCount = (Get-ChildItem -LiteralPath $workTiles -Filter 'tile_*.map').Count
$blockCount = Count-TrolejbusBlocks $workTiles
$kabelCount = 0
$minusOne = 0
foreach ($f in Get-ChildItem -LiteralPath $workTiles -Filter 'tile_*.map') {
    $L = [System.IO.File]::ReadAllLines($f.FullName)
    for ($i = 0; $i -lt $L.Count - 5; $i++) {
        if ($L[$i].Trim() -eq '[spline]' -and $L[$i + 2].Trim() -match 'kabel\.sli$') { $kabelCount++ }
        if ($L[$i].Trim() -eq '[spline]' -and $L[$i + 2].Trim() -match '(trolejbus|kabel)\.sli$' -and ($L[$i + 4].Trim() -eq '-1' -or $L[$i + 5].Trim() -eq '-1')) { $minusOne++ }
    }
}
if ($tileCount -ne 273 -or $blockCount -ne 12698 -or $kabelCount -ne 1234 -or $minusOne -ne 0) {
    throw ("generated output check failed: tiles=$tileCount trolejbus=$blockCount kabel=$kabelCount minusOne=$minusOne")
}
if ((Get-ChildItem -LiteralPath $workO3d -Filter '*.o3d').Count -ne 7) { throw 'expected 7 generated O3D files' }

# ---------- install into the game ----------
Write-Host '[4/4] installing contact SLI, stays, O3D and removing trolley.txt...'
Copy-Item (Join-Path $workTiles 'tile_*.map') $map -Force
Copy-Item (Join-Path $workO3d '*.o3d') $o3dDir -Force
Copy-Item (Join-Path $pkg 'Splines\Lublin\trolejbus.sli') $splDir -Force
Copy-Item (Join-Path $pkg 'Splines\Lublin\kabel.sli') $splDir -Force
if (Test-Path (Join-Path $map 'trolley.txt')) {
    if (-not (Test-Path $removedTxt)) { Copy-Item (Join-Path $map 'trolley.txt') $removedTxt -Force }
    Remove-Item (Join-Path $map 'trolley.txt') -Force
}
if (-not $KeepCaches) {
    Get-ChildItem -LiteralPath $map -Filter '*.map.prt' -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $map -Filter 'tile_*.rdy' -ErrorAction SilentlyContinue | Remove-Item -Force
}
Write-Host ''
Write-Host 'Installed.'
Write-Host ('  tiles: ' + $map)
Write-Host ('  O3D:   ' + $o3dDir)
Write-Host ('  state: ' + $state)
Write-Host '  contact SLI and kabel stays installed; trolley.txt removed.'
Write-Host '  openOMSI derives the wire from the map splines (frogs: trigger 9 / sense 12).'
Write-Host '  Revert: powershell -ExecutionPolicy Bypass -File tools\install.ps1 -OmsiRoot "<OMSI>" -Revert'

