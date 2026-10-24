# Dibuja los iconos de moneda y diamante (PNG 512x512 con fondo transparente) en la carpeta "imagenes".
# Dibujos propios (sin derechos de terceros). Uso: powershell -File herramientas\dibujar_iconos.ps1
param([string]$Salida = (Join-Path $PSScriptRoot "..\imagenes"))
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $Salida | Out-Null

function New-Canvas { param([int]$Size = 512)
	$bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
	$g.Clear([System.Drawing.Color]::Transparent)
	return $bmp, $g
}
function C([int]$r, [int]$gg, [int]$b, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $gg, $b) }
function LinearBrush($x, $y, $w, $h, $c1, $c2, [float]$angle = 90) {
	New-Object System.Drawing.Drawing2D.LinearGradientBrush ((New-Object System.Drawing.RectangleF $x, $y, $w, $h), $c1, $c2, $angle)
}

# ---------------------------------------------------------------- Moneda
$bmp, $g = New-Canvas
# Canto (grosor de la moneda, abajo)
$g.FillEllipse((LinearBrush 56 70 400 400 (C 214 110 10) (C 170 70 5)), 56, 78, 400, 400)
# Cara
$g.FillEllipse((LinearBrush 56 40 400 400 (C 255 214 40) (C 250 160 20)), 56, 40, 400, 400)
$g.DrawEllipse((New-Object System.Drawing.Pen (C 230 130 10), 10), 61, 45, 390, 390)
# Anillo interior en relieve
$g.FillEllipse((LinearBrush 116 100 280 280 (C 250 165 30) (C 255 220 70)), 116, 100, 280, 280)
$g.FillEllipse((LinearBrush 128 112 256 256 (C 255 222 75) (C 252 175 35)), 128, 112, 256, 256)
# Simbolo $
$font = New-Object System.Drawing.Font("Arial Black", 150, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$rect = New-Object System.Drawing.RectangleF 128, 116, 256, 256
$shadowRect = New-Object System.Drawing.RectangleF 132, 122, 256, 256
$g.DrawString('$', $font, (New-Object System.Drawing.SolidBrush (C 255 240 170 200)), $shadowRect, $fmt)
$g.DrawString('$', $font, (LinearBrush 128 140 256 220 (C 245 120 15) (C 225 85 10)), $rect, $fmt)
# Brillos
$g.FillEllipse((New-Object System.Drawing.SolidBrush (C 255 255 255 230)), 246, 50, 20, 9)
$g.FillEllipse((New-Object System.Drawing.SolidBrush (C 255 255 255 200)), 246, 404, 20, 9)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(86, 70, 340, 340, 200, 70)
$g.DrawPath((New-Object System.Drawing.Pen (C 255 250 210 170), 12), $path)
$bmp.Save((Join-Path $Salida "moneda.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# ---------------------------------------------------------------- Diamante
$bmp, $g = New-Canvas
function P([float[]]$xy) {
	$pts = New-Object 'System.Drawing.PointF[]' ($xy.Count / 2)
	for ($i = 0; $i -lt $pts.Length; $i++) { $pts[$i] = New-Object System.Drawing.PointF $xy[2 * $i], $xy[2 * $i + 1] }
	return , $pts
}
function Facet([float[]]$xy, $color) { $g.FillPolygon((New-Object System.Drawing.SolidBrush $color), (P $xy)) }
# Corona (parte de arriba): 5 facetas
Facet @(150,110, 362,110, 470,200, 42,200) (C 150 215 250)
Facet @(150,110, 210,200, 42,200) (C 175 228 252)
Facet @(150,110, 256,110, 210,200) (C 120 200 245)
Facet @(256,110, 362,110, 302,200) (C 160 222 252)
Facet @(362,110, 470,200, 302,200) (C 110 185 240)
Facet @(210,200, 256,110, 302,200) (C 195 238 255)
# Pabellon (parte de abajo): facetas hacia la punta
Facet @(42,200, 210,200, 256,440) (C 95 175 240)
Facet @(210,200, 302,200, 256,440) (C 130 205 248)
Facet @(302,200, 470,200, 256,440) (C 55 135 230)
Facet @(42,200, 120,200, 256,440) (C 120 195 245)
Facet @(392,200, 470,200, 256,440) (C 40 110 215)
# Lineas blancas entre facetas
$pen = New-Object System.Drawing.Pen (C 255 255 255 235), 6
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
foreach ($line in @(@(42,200,470,200), @(150,110,210,200), @(256,110,210,200), @(256,110,302,200), @(362,110,302,200),
		@(210,200,256,440), @(302,200,256,440), @(120,200,256,440), @(392,200,256,440))) {
	$g.DrawLine($pen, $line[0], $line[1], $line[2], $line[3])
}
# Contorno
$outline = New-Object System.Drawing.Pen (C 30 80 170), 7
$outline.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawPolygon($outline, (P @(150,110, 362,110, 470,200, 256,440, 42,200)))
# Destello
$g.FillPolygon((New-Object System.Drawing.SolidBrush (C 255 255 255 200)), (P @(170,128, 196,128, 168,180, 150,180)))
$bmp.Save((Join-Path $Salida "diamante.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"Iconos guardados en $Salida"
