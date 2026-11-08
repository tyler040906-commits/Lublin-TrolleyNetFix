param(
    [string]$Txt = 'Z:\Projects\OMSI\Trolley Poles\Addons\Lublin-TrolleyNet\maps\Projekt_Lublin_2017\trolley.parkmesh.current.txt',
    [string]$SourceMap = 'Z:\Projects\OMSI\Trolley Poles\_analysis\_lublin_extract\Lublin\maps\Projekt_Lublin_2017',
    [string]$OutMap = 'Z:\Projects\OMSI\Trolley Poles\_analysis\map_sli_replaced\Lublin\maps\Projekt_Lublin_2017',
    [string]$SplinePath = 'Splines\Lublin\trolejbus.sli',
    [double]$ProfileHeight = 5.047,
    [int]$FirstId = 2000000,
    [double]$MergeTol = 0.02,
    [double]$SwitchRadius = 15.0
)
$ErrorActionPreference='Stop'
$inv=[System.Globalization.CultureInfo]::InvariantCulture
function F9([double]$v){ return $v.ToString('F9',$inv) }
function F3([double]$v){ return $v.ToString('F3',$inv) }
function GetMapEncoding([string]$path){
    $b=[System.IO.File]::ReadAllBytes($path)
    if($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF){ return New-Object System.Text.UTF8Encoding($true) }
    if($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE){ return [System.Text.Encoding]::Unicode }
    if($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF){ return [System.Text.Encoding]::BigEndianUnicode }
    return [System.Text.Encoding]::Default
}
function ReadMapLines([string]$path){ return [System.IO.File]::ReadAllLines($path,(GetMapEncoding $path)) }
function WriteMapLines([string]$path,[object]$lines){ [System.IO.File]::WriteAllLines($path,$lines,(GetMapEncoding $path)) }

# O3D local -> world reference (used if stays are extracted later):
# local x=right, y=up, z=forward.
# f2 = z*cos(p) - y*sin(p); u2 = z*sin(p) + y*cos(p)
# wx = ox + x*cos(h) + f2*sin(h)
# wy = oy - x*sin(h) + f2*cos(h)
# wz = oz + u2
# The 0x79 matrix is a pivot, not a transform.

Write-Host 'copying map tiles...'
if(Test-Path -LiteralPath $OutMap){ Remove-Item -LiteralPath $OutMap -Recurse -Force }
New-Item -ItemType Directory -Path $OutMap -Force | Out-Null
Get-ChildItem -LiteralPath $SourceMap -File | Copy-Item -Destination $OutMap -Force
Write-Host ('copied files: '+(Get-ChildItem -LiteralPath $OutMap -File).Count)

# --- parse txt spans ---
$lines=[System.IO.File]::ReadAllLines($Txt)
$spans=New-Object System.Collections.Generic.List[object]
$cur=$null
foreach($line in $lines){
    $t=$line.Trim()
    if($t -eq '[trolley_span]'){ if($null -ne $cur){$spans.Add($cur)}; $cur=[pscustomobject]@{Points=(New-Object System.Collections.Generic.List[object])}; continue }
    if($t -eq '[trolley_switch]'){ if($null -ne $cur){$spans.Add($cur);$cur=$null}; continue }
    if($null -ne $cur -and $t -match '^p\s+'){ $a=$t.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries); if($a.Count -ge 4){$cur.Points.Add([pscustomobject]@{X=[double]::Parse($a[1],$inv);Y=[double]::Parse($a[2],$inv);Z=[double]::Parse($a[3],$inv)})} }
}
if($null -ne $cur){$spans.Add($cur)}
Write-Host ('txt spans: '+$spans.Count)

# switch positions, for the 15 m collinear-merge window
$switchPositions=New-Object System.Collections.Generic.List[object]
for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i].Trim() -ne '[trolley_switch]'){ continue }
    for($j=$i+1;$j -lt [math]::Min($i+8,$lines.Count);$j++){
        $t=$lines[$j].Trim()
        if($t -match '^pos\s+'){
            $a=$t.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)
            if($a.Count -ge 4){ $switchPositions.Add([pscustomobject]@{X=[double]::Parse($a[1],$inv);Y=[double]::Parse($a[2],$inv)}) }
            break
        }
    }
}
Write-Host ('switches: '+$switchPositions.Count)

# --- merge collinear points, only within SwitchRadius of a switch ---
function Merge-Collinear($pts,$tol,$switches,$radius){
    if($pts.Count -lt 3){ return $pts }
    $out=New-Object System.Collections.Generic.List[object]
    $out.Add($pts[0])
    $a=$pts[0]
    for($i=1;$i -lt $pts.Count-1;$i++){
        $b=$pts[$i];$c=$pts[$i+1]
        $near=$false
        foreach($sw in $switches){
            $sx=$b.X-$sw.X;$sy=$b.Y-$sw.Y
            if(($sx*$sx+$sy*$sy) -le ($radius*$radius)){ $near=$true; break }
        }
        if(-not $near){ $out.Add($b); $a=$b; continue }
        $vx=$c.X-$a.X;$vy=$c.Y-$a.Y
        $l=[math]::Sqrt($vx*$vx+$vy*$vy)
        if($l -lt 1e-9){ continue }
        $dist=[math]::Abs($vx*($b.Y-$a.Y)-$vy*($b.X-$a.X))/$l
        if($dist -gt $tol){ $out.Add($b); $a=$b }
    }
    $out.Add($pts[$pts.Count-1])
    return $out
}

# --- build segments per tile ---
$segments=New-Object System.Collections.Generic.List[object]
$skipped=New-Object System.Collections.Generic.List[object]
$id=$FirstId
for($si=0;$si -lt $spans.Count;$si++){
    $sp=$spans[$si]
    if($sp.Points.Count -lt 2){ continue }
    $merged=Merge-Collinear $sp.Points $MergeTol $switchPositions $SwitchRadius
    for($k=0;$k+1 -lt $merged.Count;$k++){
        $p0=$merged[$k];$p1=$merged[$k+1]
        $dx=$p1.X-$p0.X;$dy=$p1.Y-$p0.Y
        $len=[math]::Sqrt($dx*$dx+$dy*$dy)
        if($len -lt 0.02){ $skipped.Add([pscustomobject]@{Span=$si;Seg=$k;Len=$len;X=$p0.X;Y=$p0.Y}); continue }
        $tx=[int][math]::Floor($p0.X/300.0)
        $ty=[int][math]::Floor($p0.Y/300.0)
        $segments.Add([pscustomobject]@{
            Span=$si; Seg=$k; ID=$id; TileX=$tx; TileY=$ty;
            X0=$p0.X; Y0=$p0.Y; Z0=$p0.Z; X1=$p1.X; Y1=$p1.Y; Z1=$p1.Z;
            Len=$len; Heading=0.0; Grad=0.0; Prev=0; Next=0
        })
        $id++
    }
}
Write-Host ('segments: '+$segments.Count+' skipped short: '+$skipped.Count)

# per-segment heading and gradient
foreach($s in $segments){
    $dx=$s.X1-$s.X0;$dy=$s.Y1-$s.Y0
    $h=[math]::Atan2($dx,$dy)*180.0/[math]::PI
    if($h -lt 0){$h+=360.0}
    $s.Heading=$h
    $s.Grad=(($s.Z1-$s.Z0)/$s.Len)*100.0
    $s | Add-Member -NotePropertyName DirX -NotePropertyValue ($dx/$s.Len) -Force
    $s | Add-Member -NotePropertyName DirY -NotePropertyValue ($dy/$s.Len) -Force
}

# link prev/next across span joints: at each node, pair an incoming segment end
# with the straightest outgoing segment start.
$starts=@{};$ends=@{}
foreach($s in $segments){
    $k0=('{0:F2},{1:F2}' -f $s.X0,$s.Y0); if(-not $starts.ContainsKey($k0)){$starts[$k0]=New-Object System.Collections.Generic.List[object]}; $starts[$k0].Add($s)
    $k1=('{0:F2},{1:F2}' -f $s.X1,$s.Y1); if(-not $ends.ContainsKey($k1)){$ends[$k1]=New-Object System.Collections.Generic.List[object]}; $ends[$k1].Add($s)
}
$nodeKeys=@{}
foreach($k in $starts.Keys){$nodeKeys[$k]=$true}
foreach($k in $ends.Keys){$nodeKeys[$k]=$true}
$linked=0
foreach($k in $nodeKeys.Keys){
    if(-not $starts.ContainsKey($k) -or -not $ends.ContainsKey($k)){continue}
    $cand=New-Object System.Collections.Generic.List[object]
    foreach($s in $starts[$k]){
        foreach($t in $ends[$k]){
            if($s.ID -eq $t.ID){continue}
            $dot=$s.DirX*$t.DirX+$s.DirY*$t.DirY
            $cand.Add([pscustomobject]@{S=$s;T=$t;Dot=$dot})
        }
    }
    $usedS=@{};$usedT=@{}
    foreach($c in ($cand | Sort-Object Dot -Descending)){
        if($usedS.ContainsKey($c.S.ID) -or $usedT.ContainsKey($c.T.ID)){continue}
        $c.S.Prev=$c.T.ID
        $c.T.Next=$c.S.ID
        $usedS[$c.S.ID]=$true;$usedT[$c.T.ID]=$true
        $linked++
    }
}
Write-Host ('prev/next links across joints: '+$linked)

# --- tile keys present ---
$tiles=@{}
foreach($f in (Get-ChildItem -LiteralPath $OutMap -File -Filter 'tile_*.map')){
    if($f.Name -match '^tile_(-?\d+)_(-?\d+)\.map$'){ $tiles[('{0}_{1}' -f [int]$Matches[1],[int]$Matches[2])]=$f.FullName }
}
$missing=@{}
foreach($s in $segments){
    $key=('{0}_{1}' -f $s.TileX,$s.TileY)
    if(-not $tiles.ContainsKey($key)){ $missing[$key]=1+$(if($missing.ContainsKey($key)){$missing[$key]}else{0}) }
}
Write-Host ('tiles present: '+$tiles.Count+'  segments in missing tiles: '+(($missing.Values|Measure-Object -Sum).Sum))

# --- rewrite tiles: remove old trolejbus spline blocks, append new ---
function IsTrolejbusBlock([string[]]$blockLines){
    foreach($l in $blockLines){ if($l.Trim() -match 'trolejbus\.sli$'){ return $true } }
    return $false
}
$report=New-Object System.Collections.Generic.List[object]
$totalRemoved=0;$totalAdded=0
foreach($key in ($tiles.Keys | Sort-Object)){
    $path=$tiles[$key]
    $tileSegs=@($segments | Where-Object { ('{0}_{1}' -f $_.TileX,$_.TileY) -eq $key } | Sort-Object ID)
    $old=ReadMapLines $path
    $out=New-Object System.Collections.Generic.List[string]
    $removed=0
    $oldSplines=New-Object System.Collections.Generic.List[object]
    $splineOrd=0
    $i=0
    while($i -lt $old.Count){
        $t=$old[$i].Trim()
        if($t -eq '[spline]' -or $t -eq '[spline_h]'){
            $block=New-Object System.Collections.Generic.List[string]
            $j=$i
            while($j -lt $old.Count){
                $v=$old[$j].Trim()
                if($j -gt $i -and ($v -eq '' -or $v -match '^\[')){ break }
                $block.Add($old[$j]); $j++
            }
            $oldSplines.Add([pscustomobject]@{
                Index=$splineOrd; Id=$block[3].Trim(); Path=$block[2].Trim();
                X=[double]::Parse($block[6].Trim(),$inv); Y=[double]::Parse($block[8].Trim(),$inv)
            })
            $splineOrd++
            if(IsTrolejbusBlock $block.ToArray()){
                $removed++
                # keep one blank separator if the block was followed by blanks
                while($j -lt $old.Count -and $old[$j].Trim() -eq ''){ $j++ }
                $i=$j
                continue
            }
            for($k=$i;$k -lt $j;$k++){ $out.Add($old[$k]) }
            $i=$j
            continue
        }
        $out.Add($old[$i]); $i++
    }
    foreach($s in $tileSegs){
        $lx=$s.X0-$s.TileX*300.0
        $ly=$s.Y0-$s.TileY*300.0
        $zbase=$s.Z0-$ProfileHeight
        if($out.Count -gt 0 -and $out[$out.Count-1].Trim() -ne ''){ $out.Add('') }
        $out.Add('[spline]')
        $out.Add('0')
        $out.Add($SplinePath)
        $out.Add([string]$s.ID)
        $out.Add([string]$s.Prev)
        $out.Add([string]$s.Next)
        $out.Add((F9 $lx))
        $out.Add((F9 $zbase))
        $out.Add((F9 $ly))
        $out.Add((F9 $s.Heading))
        $out.Add((F9 $s.Len))
        $out.Add('0')
        $out.Add((F9 $s.Grad))
        $out.Add((F9 $s.Grad))
        $out.Add('0')
        $out.Add('0')
        $out.Add('0')
        $out.Add('0')
        $out.Add('0')
    }

    # [splineAttachement] names its spline by its index in the tile's spline list, not by
    # ID. Removing the old trolejbus splines shifts every index after them, so remap every
    # attachment by the ID of the spline it used to point at.
    $newSplines=New-Object System.Collections.Generic.List[object]
    $newIndexById=@{}
    for($i=0;$i -lt $out.Count;$i++){
        $t=$out[$i].Trim()
        if($t -eq '[spline]' -or $t -eq '[spline_h]'){
            $nid=$out[$i+3].Trim()
            $newIndexById[$nid]=$newSplines.Count
            $newSplines.Add([pscustomobject]@{
                Index=$newSplines.Count; Id=$nid; Path=$out[$i+2].Trim();
                X=[double]::Parse($out[$i+6].Trim(),$inv); Y=[double]::Parse($out[$i+8].Trim(),$inv)
            })
        }
    }
    $remapped=0;$remappedNew=0
    for($i=0;$i -lt $out.Count;$i++){
        $t=$out[$i].Trim()
        $idxPos=-1
        if($t -eq '[splineAttachement]'){ $idxPos=$i+4 }
        elseif($t -eq '[splineAttachement_repeater]'){ $idxPos=$i+6 }
        if($idxPos -lt 0){ continue }
        $oldIdx=0
        if(-not [int]::TryParse($out[$idxPos].Trim(),[ref]$oldIdx)){ continue }
        if($oldIdx -lt 0 -or $oldIdx -ge $oldSplines.Count){ continue }
        $oldSp=$oldSplines[$oldIdx]
        if($newIndexById.ContainsKey($oldSp.Id)){
            $newIdx=[int]$newIndexById[$oldSp.Id]
        } else {
            # The referenced spline was a removed trolley wire: use the nearest replacement
            # contact segment in this tile so the attachment stays at the same place.
            # oldSp.X/Y are tile-local; tile segments are world coordinates.
            $kp=$key -split '_'
            $oldWX=$oldSp.X+([int]$kp[0])*300.0
            $oldWY=$oldSp.Y+([int]$kp[1])*300.0
            $best=$null;$bestD=[double]::MaxValue
            foreach($s in $tileSegs){
                $dx=$s.X0-$oldWX;$dy=$s.Y0-$oldWY
                $d=$dx*$dx+$dy*$dy
                if($d -lt $bestD){$bestD=$d;$best=$s}
            }
            if($null -eq $best){ continue }
            $newIdx=[int]$newIndexById[[string]$best.ID]
            $remappedNew++
        }
        $out[$idxPos]=[string]$newIdx
        $remapped++
    }
    WriteMapLines $path $out
    $totalRemoved+=$removed;$totalAdded+=$tileSegs.Count
    if($removed -gt 0 -or $tileSegs.Count -gt 0){
        $report.Add([pscustomobject]@{Tile=$key;RemovedOld=$removed;AddedNew=$tileSegs.Count;RemappedAttach=$remapped;RemappedToNew=$remappedNew})
    }
}
$report | Export-Csv -LiteralPath (Join-Path $OutMap 'spline_rewrite_report.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('removed old trolejbus blocks: '+$totalRemoved)
Write-Host ('added new spline blocks: '+$totalAdded)
Write-Host ('report: '+(Join-Path $OutMap 'spline_rewrite_report.csv'))


