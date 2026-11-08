param(
    [string]$StaysCsv='Z:\Projects\OMSI\Trolley Poles\_analysis\o3d_stays_world.csv',
    [string]$MapDir='Z:\Projects\OMSI\Trolley Poles\_analysis\map_sli_replaced\Lublin\maps\Projekt_Lublin_2017',
    [int]$FirstId=3000000
)
$ErrorActionPreference='Stop'
$inv=[System.Globalization.CultureInfo]::InvariantCulture
function F9([double]$v){ return $v.ToString('F9',$inv) }
function GetMapEncoding([string]$path){
    $b=[System.IO.File]::ReadAllBytes($path)
    if($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF){ return New-Object System.Text.UTF8Encoding($true) }
    if($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE){ return [System.Text.Encoding]::Unicode }
    if($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF){ return [System.Text.Encoding]::BigEndianUnicode }
    return [System.Text.Encoding]::Default
}
$stays=Import-Csv -LiteralPath $StaysCsv | Where-Object { $_.DuplicateKabel -ne 'True' }
Write-Host ('stays to add: '+$stays.Count)
$byTile=@{}
foreach($s in $stays){
    $key=('{0}_{1}' -f $s.TileX,$s.TileY)
    if(-not $byTile.ContainsKey($key)){$byTile[$key]=New-Object System.Collections.Generic.List[object]}
    $byTile[$key].Add($s)
}
$id=$FirstId;$total=0;$miss=0
foreach($key in ($byTile.Keys | Sort-Object)){
    $file=Join-Path $MapDir ('tile_'+$key+'.map')
    if(-not (Test-Path -LiteralPath $file)){ Write-Host ('MISSING '+$file); $miss+=$byTile[$key].Count; continue }
    $enc=GetMapEncoding $file
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($l in [System.IO.File]::ReadAllLines($file,$enc)){ $lines.Add($l) }
    foreach($s in $byTile[$key]){
        $Ax=[double]$s.Ax;$Ay=[double]$s.Ay;$Az=[double]$s.Az;$Bx=[double]$s.Bx;$By=[double]$s.By;$Bz=[double]$s.Bz
        $dx=$Bx-$Ax;$dy=$By-$Ay;$len=[math]::Sqrt($dx*$dx+$dy*$dy)
        if($len -lt 0.05){continue}
        $h=[math]::Atan2($dx,$dy)*180.0/[math]::PI;if($h -lt 0){$h+=360}
        $grad=(($Bz-$Az)/$len)*100.0
        $lx=$Ax-[int]$s.TileX*300.0;$ly=$Ay-[int]$s.TileY*300.0;$zbase=$Az-5.135
        if($lines.Count -gt 0 -and $lines[$lines.Count-1].Trim() -ne ''){ $lines.Add('') }
        $lines.Add('[spline]');$lines.Add('0');$lines.Add('Splines\Lublin\kabel.sli');$lines.Add([string]$id);$lines.Add('0');$lines.Add('0')
        $lines.Add((F9 $lx));$lines.Add((F9 $zbase));$lines.Add((F9 $ly));$lines.Add((F9 $h));$lines.Add((F9 $len))
        $lines.Add('0');$lines.Add((F9 $grad));$lines.Add((F9 $grad));$lines.Add('0');$lines.Add('0');$lines.Add('0');$lines.Add('0');$lines.Add('0')
        $id++;$total++
    }
    [System.IO.File]::WriteAllLines($file,$lines,$enc)
}
Write-Host ('added stay splines: '+$total+'  missing='+$miss)


