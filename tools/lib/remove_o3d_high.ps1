param(
    [string]$Root='Z:\Projects\OMSI\Trolley Poles\_analysis\_lublin_root\Lublin\Sceneryobjects\Lublin\Kostki sterujace ruchem AI\model',
    [string]$OutDir='Z:\Projects\OMSI\Trolley Poles\_analysis\o3d_high_removed',
    [double]$HighY=4.5
)
$ErrorActionPreference='Stop'
$names=@('Rondo_Krupskiego.o3d','UniiXZamojska.o3d','RondoLubelskiegoLipca3.o3d','DMMXWolska.o3d','GrygowejXPancerniakow.o3d','zamojska.o3d','zamojska2.o3d')
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
foreach($name in $names){
    $path=Join-Path $Root $name
    if(-not (Test-Path -LiteralPath $path)){continue}
    $b=[System.IO.File]::ReadAllBytes($path)
    function U8([int]$o){[int]$b[$o]}
    function U16([int]$o){[int]$b[$o] -bor ([int]$b[$o+1] -shl 8)}
    function U32([int]$o){[uint32]$b[$o] -bor ([uint32]$b[$o+1] -shl 8) -bor ([uint32]$b[$o+2] -shl 16) -bor ([uint32]$b[$o+3] -shl 24)}
    function F32([int]$o){[BitConverter]::ToSingle($b,$o)}
    $p=2;$version=U8 $p;$p++
    $flags=0;if($version -ge 3){$flags=U8 $p;$p++}
    if($version -ge 4){$p+=4}
    $verts=New-Object System.Collections.Generic.List[object]
    $tris=New-Object System.Collections.Generic.List[object]
    while($p -lt $b.Length){
        $tag=U8 $p;$p++
        if($tag -eq 0x17){$n=if($version -ge 3){[int](U32 $p)}else{U16 $p};$p += $(if($version -ge 3){4}else{2});for($i=0;$i -lt $n;$i++){$verts.Add([double[]]@((F32 $p),(F32 ($p+4)),(F32 ($p+8))));$p+=32}}
        elseif($tag -eq 0x49){$n=if($version -ge 3){[int](U32 $p)}else{U16 $p};$p += $(if($version -ge 3){4}else{2});$isz=if(($flags -band 1)-ne 0){4}else{2};for($i=0;$i -lt $n;$i++){$off=$p;if($isz -eq 4){$a=[int](U32 $p);$bb=[int](U32 ($p+4));$c=[int](U32 ($p+8));$p+=12}else{$a=U16 $p;$bb=U16 ($p+2);$c=U16 ($p+4);$p+=6};$mat=U16 $p;$p+=2;$tris.Add([pscustomobject]@{A=$a;B=$bb;C=$c;Off=$off;ISize=$isz})};break}
        else{break}
    }
    $degen=0
    foreach($t in $tris){
        if($verts[$t.A][1] -gt $HighY -and $verts[$t.B][1] -gt $HighY -and $verts[$t.C][1] -gt $HighY){
            $idx=if($t.ISize -eq 4){[System.BitConverter]::GetBytes([uint32]$t.A)}else{[System.BitConverter]::GetBytes([uint16]$t.A)}
            for($k=0;$k -lt 3;$k++){ [System.Array]::Copy($idx,0,$b,($t.Off+$k*$t.ISize),$t.ISize) }
            $degen++
        }
    }
    $out=Join-Path $OutDir $name
    [System.IO.File]::WriteAllBytes($out,$b)
    Write-Host ('{0,-28} verts={1} tris={2} highDegenerate={3} bytes={4}' -f $name,$verts.Count,$tris.Count,$degen,$b.Length)
}
Write-Host ('wrote '+$OutDir)

