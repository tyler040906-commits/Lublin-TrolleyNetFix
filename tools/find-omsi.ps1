param()
$ErrorActionPreference = 'SilentlyContinue'
$mapRel = 'maps\Projekt_Lublin_2017'
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$withState = New-Object System.Collections.Generic.List[string]
$plain = New-Object System.Collections.Generic.List[string]

function Add-Candidate([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return }
    $p = $p.Trim().Trim('"').TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $p $mapRel))) { return }
    if (-not $seen.Add($p)) { return }
    if (Test-Path -LiteralPath (Join-Path $p 'Addons\Lublin-TrolleyNetFix\_install_state')) { $withState.Add($p) }
    else { $plain.Add($p) }
}

# 1. the package may sit inside <OMSI>\Addons\Lublin-TrolleyNetFix
$d = $PSScriptRoot
for ($i = 0; $i -lt 5 -and $d; $i++) {
    Add-Candidate $d
    $d = Split-Path -Parent $d
}

# 2. explicit environment variable
Add-Candidate $env:OMSI2_ROOT
Add-Candidate $env:OMSI_ROOT

# 3. Steam install path and library folders
$steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath).SteamPath
if (-not $steam) { $steam = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath).InstallPath }
if ($steam) {
    Add-Candidate (Join-Path $steam 'steamapps\common\OMSI 2')
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($line in [System.IO.File]::ReadAllLines($vdf)) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $lib = $matches[1] -replace '\\\\', '\'
                Add-Candidate (Join-Path $lib 'steamapps\common\OMSI 2')
            }
        }
    }
}

# 4. uninstall entries (Steam App 252530, Aerosoft, etc.)
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($root in $uninstallRoots) {
    foreach ($k in Get-ChildItem $root) {
        $it = Get-ItemProperty $k.PSPath
        if ($it.DisplayName -match 'OMSI\s*2') {
            Add-Candidate $it.InstallLocation
            if ($k.PSChildName -eq 'Steam App 252530') { Add-Candidate $it.InstallLocation }
        }
    }
}

# 5. common layouts on every fixed drive
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' } | Select-Object -ExpandProperty Root
$patterns = @(
    'SteamLibrary\steamapps\common\OMSI 2',
    'Steam\steamapps\common\OMSI 2',
    'Program Files (x86)\Steam\steamapps\common\OMSI 2',
    'Program Files\Steam\steamapps\common\OMSI 2',
    'Games\OMSI 2',
    'OMSI 2',
    'Program Files (x86)\Aerosoft\OMSI 2',
    'Program Files\Aerosoft\OMSI 2'
)
foreach ($dr in $drives) {
    foreach ($pat in $patterns) { Add-Candidate (Join-Path $dr $pat) }
}
foreach ($p in $withState) { Write-Output $p; exit 0 }
foreach ($p in $plain) { Write-Output $p; exit 0 }
exit 1

