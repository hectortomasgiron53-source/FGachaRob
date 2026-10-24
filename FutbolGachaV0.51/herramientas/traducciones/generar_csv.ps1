# Genera la tabla de localizacion (CSV) para subirla en create.roblox.com > Localizacion > Gestion de tablas > Cargar CSV.
#  - ingles.tsv: texto en espanol <TAB> traduccion al ingles (revisada a mano)
#  - nombres.txt: nombres que NO se traducen (brainrots, nombre del juego): el mismo texto en todos los idiomas
# Los demas idiomas (pt, fr, it) se dejan vacios: los rellena la traduccion automatica de Roblox.
param([string]$Salida = (Join-Path $PSScriptRoot "tabla_localizacion.csv"))

function Q([string]$s) { '"' + $s.Replace('"', '""') + '"' }

$rows = New-Object System.Collections.Generic.List[string]
$rows.Add("Key,Example,Source,Context,Game Locations,en,pt,fr,it")
$seen = @{}
foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "ingles.tsv"), [System.Text.Encoding]::UTF8)) {
	if ($line.Trim() -eq "") { continue }
	$parts = $line.Split("`t")
	if ($parts.Count -ne 2) { continue }
	$source, $en = $parts[0], $parts[1]
	if ($seen.ContainsKey($source)) { continue }
	$seen[$source] = $true
	$rows.Add(",," + (Q $source) + ",,," + (Q $en) + ",,,")
}
foreach ($name in [System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "nombres.txt"), [System.Text.Encoding]::UTF8)) {
	$name = $name.Trim()
	if ($name -eq "" -or $seen.ContainsKey($name)) { continue }
	$seen[$name] = $true
	$q = Q $name
	$rows.Add(",,$q,,,$q,$q,$q,$q")
}
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllLines($Salida, $rows, $utf8Bom)
"$($rows.Count - 1) textos -> $Salida"
