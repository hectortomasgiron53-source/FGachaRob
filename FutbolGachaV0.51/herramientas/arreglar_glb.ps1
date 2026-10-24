# ARREGLAR GLB: convierte los materiales "KHR_materials_pbrSpecularGlossiness" (formato antiguo de Sketchfab que el
# importador de Roblox NO entiende: los modelos salen grises) al formato normal de glTF (metalico / rugosidad),
# conservando colores y texturas. Tambien puede girar el modelo (para que mire hacia delante en Roblox).
#
# Uso (PowerShell):  .\arreglar_glb.ps1 -Entrada "carpeta con .glb" -Salida "carpeta nueva"
# Los .glb que no lo necesitan se copian tal cual. Los originales no se tocan.
param(
	[Parameter(Mandatory = $true)][string]$Entrada,
	[Parameter(Mandatory = $true)][string]$Salida,
	# Giro (grados, sobre el eje vertical) por archivo: @{ "nombre.glb" = 180 }
	[hashtable]$Giros = @{},
	# Archivos en los que los colores muy oscuros se aclaran un poco (el negro puro en Roblox se ve plano, sin forma)
	[string[]]$Aclarar = @()
)

New-Item -ItemType Directory -Force -Path $Salida | Out-Null

function Remove-Ext($list, [string]$name) {
	if ($null -eq $list) { return $null }
	$kept = @($list | Where-Object { $_ -ne $name })
	if ($kept.Count -eq 0) { return $null }
	return , $kept
}

Get-ChildItem -Path $Entrada -Filter *.glb | ForEach-Object {
	$file = $_
	$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
	$jsonLen = [BitConverter]::ToUInt32($bytes, 12)
	$json = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $jsonLen)
	$g = $json | ConvertFrom-Json
	$changed = $false

	foreach ($m in @($g.materials)) {
		$sg = $null
		if ($m.extensions -and $m.extensions.PSObject.Properties["KHR_materials_pbrSpecularGlossiness"]) {
			$sg = $m.extensions.KHR_materials_pbrSpecularGlossiness
		}
		if ($null -eq $sg) { continue }
		$pbr = [ordered]@{}
		if ($sg.PSObject.Properties["diffuseFactor"]) { $pbr.baseColorFactor = @($sg.diffuseFactor) }
		if ($sg.PSObject.Properties["diffuseTexture"]) { $pbr.baseColorTexture = $sg.diffuseTexture }
		$gloss = 1.0
		if ($sg.PSObject.Properties["glossinessFactor"]) { $gloss = [double]$sg.glossinessFactor }
		$pbr.metallicFactor = 0
		$pbr.roughnessFactor = [math]::Min(1, [math]::Max(0.35, 1 - $gloss))
		$m | Add-Member -NotePropertyName pbrMetallicRoughness -NotePropertyValue ([pscustomobject]$pbr) -Force
		$m.extensions.PSObject.Properties.Remove("KHR_materials_pbrSpecularGlossiness")
		if (@($m.extensions.PSObject.Properties).Count -eq 0) { $m.PSObject.Properties.Remove("extensions") }
		$changed = $true
	}
	if ($changed) {
		$used = Remove-Ext $g.extensionsUsed "KHR_materials_pbrSpecularGlossiness"
		if ($null -eq $used) { $g.PSObject.Properties.Remove("extensionsUsed") } else { $g.extensionsUsed = $used }
		if ($g.PSObject.Properties["extensionsRequired"]) {
			$req = Remove-Ext $g.extensionsRequired "KHR_materials_pbrSpecularGlossiness"
			if ($null -eq $req) { $g.PSObject.Properties.Remove("extensionsRequired") } else { $g.extensionsRequired = $req }
		}
	}

	# Colores sin textura (solo "baseColorFactor"): el importador de Roblox puede ignorarlos y el modelo sale gris.
	# Se convierten en una textura pequena de ese color (las texturas siempre se importan).
	$extraImages = New-Object System.Collections.Generic.List[byte[]]
	$binLen = [BitConverter]::ToUInt32($bytes, 20 + $jsonLen)
	$binData = New-Object byte[] $binLen
	[Array]::Copy($bytes, 20 + $jsonLen + 8, $binData, 0, $binLen)
	$appended = New-Object System.Collections.Generic.List[byte]
	$appended.AddRange($binData)
	$colorCache = @{}
	Add-Type -AssemblyName System.Drawing
	foreach ($m in @($g.materials)) {
		$pbr = $m.pbrMetallicRoughness
		if ($null -eq $pbr) {
			$pbr = [pscustomobject]@{}
			$m | Add-Member -NotePropertyName pbrMetallicRoughness -NotePropertyValue $pbr -Force
		}
		if ($pbr.PSObject.Properties["baseColorTexture"]) { continue }
		$factor = @(1, 1, 1, 1)
		if ($pbr.PSObject.Properties["baseColorFactor"]) { $factor = @($pbr.baseColorFactor) }
		# glTF guarda el color en lineal; la textura va en sRGB
		$rgb = @(0, 1, 2) | ForEach-Object {
			$c = [math]::Min(1, [math]::Max(0, [double]$factor[$_]))
			$s = if ($c -le 0.0031308) { 12.92 * $c } else { 1.055 * [math]::Pow($c, 1 / 2.4) - 0.055 }
			if ($Aclarar -contains $file.Name) { $s = 0.2 + $s * 0.8 } # negro -> gris muy oscuro
			[int][math]::Round($s * 255)
		}
		$key = $rgb -join ","
		if (-not $colorCache.ContainsKey($key)) {
			$bmp = New-Object System.Drawing.Bitmap 8, 8
			$color = [System.Drawing.Color]::FromArgb(255, $rgb[0], $rgb[1], $rgb[2])
			for ($x = 0; $x -lt 8; $x++) { for ($y = 0; $y -lt 8; $y++) { $bmp.SetPixel($x, $y, $color) } }
			$ms = New-Object System.IO.MemoryStream
			$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
			$png = $ms.ToArray()
			$bmp.Dispose()
			while ($appended.Count % 4 -ne 0) { $appended.Add(0) }
			$offset = $appended.Count
			$appended.AddRange($png)
			if (-not $g.PSObject.Properties["bufferViews"]) { $g | Add-Member -NotePropertyName bufferViews -NotePropertyValue @() }
			if (-not $g.PSObject.Properties["images"]) { $g | Add-Member -NotePropertyName images -NotePropertyValue @() }
			if (-not $g.PSObject.Properties["textures"]) { $g | Add-Member -NotePropertyName textures -NotePropertyValue @() }
			$g.bufferViews = @($g.bufferViews) + [pscustomobject]@{ buffer = 0; byteOffset = $offset; byteLength = $png.Length }
			$g.images = @($g.images) + [pscustomobject]@{ bufferView = (@($g.bufferViews).Count - 1); mimeType = "image/png" }
			$g.textures = @($g.textures) + [pscustomobject]@{ source = (@($g.images).Count - 1) }
			$colorCache[$key] = @($g.textures).Count - 1
		}
		$pbr | Add-Member -NotePropertyName baseColorTexture -NotePropertyValue ([pscustomobject]@{ index = $colorCache[$key] }) -Force
		$pbr | Add-Member -NotePropertyName baseColorFactor -NotePropertyValue @(1, 1, 1, [double]$factor[3]) -Force
		$changed = $true
	}
	while ($appended.Count % 4 -ne 0) { $appended.Add(0) }
	if ($colorCache.Count -gt 0) {
		$g.buffers[0].byteLength = $appended.Count
	}

	# Giro: un nodo raiz nuevo que envuelve la escena
	$yaw = 0
	if ($Giros.ContainsKey($file.Name)) { $yaw = [double]$Giros[$file.Name] }
	if ($yaw -ne 0) {
		$half = $yaw * [math]::PI / 360
		$newNode = [pscustomobject]@{ name = "Giro"; rotation = @(0, [math]::Sin($half), 0, [math]::Cos($half)); children = @($g.scenes[0].nodes) }
		$nodes = @($g.nodes) + $newNode
		$g.nodes = $nodes
		$g.scenes[0].nodes = @($nodes.Count - 1)
		$changed = $true
	}

	$target = Join-Path $Salida $file.Name
	if (-not $changed) {
		Copy-Item $file.FullName $target -Force
		"copiado     $($file.Name)"
		return
	}
	$newJson = $g | ConvertTo-Json -Depth 100 -Compress
	$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($newJson)
	$pad = (4 - ($jsonBytes.Length % 4)) % 4
	$jsonChunkLen = $jsonBytes.Length + $pad
	$bin = $appended.ToArray()
	$total = 12 + 8 + $jsonChunkLen + 8 + $bin.Length
	$out = New-Object byte[] $total
	[BitConverter]::GetBytes([uint32]0x46546C67).CopyTo($out, 0)
	[BitConverter]::GetBytes([uint32]2).CopyTo($out, 4)
	[BitConverter]::GetBytes([uint32]$total).CopyTo($out, 8)
	[BitConverter]::GetBytes([uint32]$jsonChunkLen).CopyTo($out, 12)
	[BitConverter]::GetBytes([uint32]0x4E4F534A).CopyTo($out, 16)
	$jsonBytes.CopyTo($out, 20)
	for ($i = 0; $i -lt $pad; $i++) { $out[20 + $jsonBytes.Length + $i] = 0x20 }
	$binHeader = 20 + $jsonChunkLen
	[BitConverter]::GetBytes([uint32]$bin.Length).CopyTo($out, $binHeader)
	[BitConverter]::GetBytes([uint32]0x004E4942).CopyTo($out, $binHeader + 4)
	$bin.CopyTo($out, $binHeader + 8)
	[System.IO.File]::WriteAllBytes($target, $out)
	"ARREGLADO   $($file.Name)  (giro $yaw)"
}
