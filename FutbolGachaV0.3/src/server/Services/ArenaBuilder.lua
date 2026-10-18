--!strict
--[[
	ArenaBuilder: construye el campo por codigo (no hace falta modelarlo a mano).
	Coordenadas locales: origen en el centro del campo, la cara superior del suelo en Y = 0,
	el largo en el eje X y el ancho en el eje Z. El equipo 1 ataca hacia +X.
	Las medidas salen de Balance.Field.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local CollisionSetup = require(script.Parent.CollisionSetup)

local ArenaBuilder = {}

local FLOOR_PHYSICS = PhysicalProperties.new(2, 0.35, 0.4, 10, 1)
local WALL_PHYSICS = PhysicalProperties.new(2, 0.05, 0.7, 1, 10)

local GRASS = Color3.fromRGB(67, 140, 70)
local WALL = Color3.fromRGB(225, 228, 235)
local GOAL = Color3.fromRGB(255, 200, 60)
local LINE = Color3.fromRGB(255, 255, 255)
local NET_COLOR = Color3.fromRGB(236, 240, 244)
local BOARD = Color3.fromRGB(70, 82, 104)
-- Las redes del cerramiento rebotan como los muros. Solo la red de DENTRO de la porteria no rebota.
local NET_PHYSICS = PhysicalProperties.new(2, 0.05, 0.6, 1, 10)
local GOAL_NET_PHYSICS = PhysicalProperties.new(1, 0.9, 0, 10, 100)

local function addPart(
	model: Model,
	origin: CFrame,
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	physics: PhysicalProperties?,
	transparency: number?,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = origin * localCFrame
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = transparency or 0
	part.CanCollide = canCollide ~= false
	if physics then
		part.CustomPhysicalProperties = physics
	end
	part.Parent = model
	return part
end


-- Linea pintada sobre el suelo (no choca, no la ve ni el raycast). from/to en coordenadas locales (X, Z).

-- Cuadricula de hilos (la "red"): hilos finos verticales y horizontales sobre el plano de "cf"
-- (X local = ancho, Y local = alto). No chocan: la colision la pone el panel transparente de detras.
local function addNetLines(model: Model, origin: CFrame, cf: CFrame, width: number, height: number, spacing: number)
	local cols = math.max(1, math.round(width / spacing))
	local rows = math.max(1, math.round(height / spacing))
	for i = 0, cols do
		local x = -width / 2 + width * i / cols
		local strand = addPart(model, origin, "NetStrand", Vector3.new(0.12, height, 0.12), cf * CFrame.new(x, 0, 0), NET_COLOR, nil, 0.25, false)
		strand.CanQuery = false
		strand.CanTouch = false
		strand.CastShadow = false
	end
	for j = 0, rows do
		local y = -height / 2 + height * j / rows
		local strand = addPart(model, origin, "NetStrand", Vector3.new(width, 0.12, 0.12), cf * CFrame.new(0, y, 0), NET_COLOR, nil, 0.25, false)
		strand.CanQuery = false
		strand.CanTouch = false
		strand.CastShadow = false
	end
end

-- Cerramiento: muro bajo solido (boardH) + red hasta netTop. a y b: extremos de la base (X, Z locales, Y = 0).
-- Para un tramo sin muro bajo (travesano sobre la porteria) boardH = 0 y netBottom = altura donde empieza la red.
local function addBarrier(model: Model, origin: CFrame, name: string, a: Vector3, b: Vector3, boardH: number, netBottom: number, netTop: number)
	local T = Balance.Field.WallThickness
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.01 then
		return
	end
	local dir = delta.Unit
	local mid = (a + b) / 2
	local function basis(y: number): CFrame
		return CFrame.fromMatrix(mid + Vector3.new(0, y, 0), dir, Vector3.yAxis)
	end
	if boardH > 0 then
		addPart(model, origin, name .. "Board", Vector3.new(length, boardH, T), basis(boardH / 2), BOARD, WALL_PHYSICS)
	end
	local netH = netTop - netBottom
	if netH > 0 then
		local cf = basis(netBottom + netH / 2)
		addPart(model, origin, name .. "Net", Vector3.new(length, netH, T), cf, NET_COLOR, NET_PHYSICS, 0.9, true)
		addNetLines(model, origin, cf, length, netH, 4)
	end
end

local addMarkings: (Model, CFrame) -> ()

local function addLine(model: Model, origin: CFrame, name: string, a: Vector2, b: Vector2, width: number, color: Color3?, lift: number?)
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.01 then
		return
	end
	local mid = (a + b) / 2
	local part = addPart(
		model,
		origin,
		name,
		Vector3.new(width, 0.1, length),
		CFrame.lookAt(Vector3.new(mid.X, 0.05 + (lift or 0), mid.Y), Vector3.new(b.X, 0.05 + (lift or 0), b.Y)),
		color or LINE,
		nil,
		0,
		false
	)
	part.CanQuery = false
	part.CanTouch = false
end

-- Marcas del campo. Las lineas de banda y de gol van DENTRO del campo, pegadas al muro: su borde exterior es
-- exactamente X = +-Length/2 y Z = +-Width/2. Es gol cuando el balon entero ha pasado ese borde (ver Match._checkGoal).
addMarkings = function(model: Model, origin: CFrame)
	local F = Balance.Field
	local halfL, halfW = F.Length / 2, F.Width / 2
	local lw = F.LineWidth
	local inL, inW = halfL - lw / 2, halfW - lw / 2 -- centro de las lineas del borde

	-- Bandas (a lo largo de X) y lineas de fondo/gol (a lo largo de Z), con las esquinas cortadas
	local c = F.CornerSize
	for _, sz in { -1, 1 } do
		addLine(model, origin, "Touchline", Vector2.new(-(halfL - c), sz * inW), Vector2.new(halfL - c, sz * inW), lw)
	end
	for _, sx in { -1, 1 } do
		addLine(model, origin, "GoalLine", Vector2.new(sx * inL, -(halfW - c)), Vector2.new(sx * inL, halfW - c), lw)
		for _, sz in { -1, 1 } do
			-- esquina cortada a 45 grados
			addLine(
				model,
				origin,
				"CornerLine",
				Vector2.new(sx * (halfL - c), sz * inW),
				Vector2.new(sx * inL, sz * (halfW - c)),
				lw
			)
		end
		-- Boca de la porteria: marca mas gruesa y dorada sobre la linea de gol, solo entre los palos
		addLine(
			model,
			origin,
			"GoalMouth",
			Vector2.new(sx * (halfL - lw * 0.8), -F.GoalWidth / 2), -- su borde exterior tambien acaba en X = +-Length/2
			Vector2.new(sx * (halfL - lw * 0.8), F.GoalWidth / 2),
			lw * 1.6,
			GOAL,
			0.03 -- por encima de la linea de gol blanca (si estan al mismo nivel, parpadean)
		)

		-- Area grande: semicirculo con centro en el centro de la porteria
		local areaRadius = F.AreaRadius
		local arcSegments = 28
		for k = 1, arcSegments do
			local a0 = -math.pi / 2 + (k - 1) / arcSegments * math.pi
			local a1 = -math.pi / 2 + k / arcSegments * math.pi
			addLine(
				model,
				origin,
				"AreaArc",
				Vector2.new(sx * (halfL - areaRadius * math.cos(a0)), areaRadius * math.sin(a0)),
				Vector2.new(sx * (halfL - areaRadius * math.cos(a1)), areaRadius * math.sin(a1)),
				lw * 1.05,
				nil,
				if k % 2 == 0 then 0.01 else 0
			)
		end

		-- Area pequena: rectangulo abierto hacia la linea de gol
		local boxX = sx * (halfL - F.SmallAreaDepth)
		local boxZ = F.SmallAreaWidth / 2
		addLine(model, origin, "SmallAreaFront", Vector2.new(boxX, -boxZ), Vector2.new(boxX, boxZ), lw)
		for _, sz in { -1, 1 } do
			addLine(model, origin, "SmallAreaSide", Vector2.new(boxX, sz * boxZ), Vector2.new(sx * inL, sz * boxZ), lw)
		end
	end

	-- Linea central, circulo central y punto de saque
	addLine(model, origin, "CenterLine", Vector2.new(0, -inW), Vector2.new(0, inW), lw)
	local radius = F.CenterCircleRadius
	local segments = 36
	for i = 1, segments do
		local a0 = (i - 1) / segments * math.pi * 2
		local a1 = i / segments * math.pi * 2
		addLine(
			model,
			origin,
			"CenterCircle",
			Vector2.new(math.cos(a0) * radius, math.sin(a0) * radius),
			Vector2.new(math.cos(a1) * radius, math.sin(a1) * radius),
			lw * 1.05, -- un pelin mas ancho para que los tramos no dejen huecos en las uniones
			nil,
			if i % 2 == 0 then 0.01 else 0 -- tramos alternos a distinta altura: donde se solapan no parpadean
		)
	end
	local spot = addPart(model, origin, "CenterSpot", Vector3.new(1.4, 0.1, 1.4), CFrame.new(0, 0.08, 0), LINE, nil, 0, false)
	spot.CanQuery = false
end

-- options.Gate = true abre una puerta (ancho Field.GateWidth) en el muro lateral +Z, por donde se puede entrar al campo.
-- ---------------------------------------------------------------------------
-- Gradas alrededor del campo (partido de practica): dos pisos, negras, con curvas en las esquinas.
-- Una esquina no tiene primer piso: alli esta el tunel de vestuarios, con el segundo piso por encima.
-- ---------------------------------------------------------------------------
local FAN_COLORS = {
	Color3.fromRGB(52, 120, 246),
	Color3.fromRGB(235, 64, 52),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(245, 205, 48),
	Color3.fromRGB(40, 150, 80),
	Color3.fromRGB(240, 130, 40),
}
local SKIN_COLORS = {
	Color3.fromRGB(255, 224, 189),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(141, 85, 36),
}
local TUNNEL_GREEN = Color3.fromRGB(22, 112, 66)
local TUNNEL_GREEN_DARK = Color3.fromRGB(14, 74, 44)
local TRIM_WHITE = Color3.fromRGB(236, 240, 236)

local function decor(part: Part)
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Perfil de la grada (de delante hacia atras): filas del primer piso, pasillo, filas del segundo piso, muro trasero.
-- Cada tramo: Offset (distancia desde el borde delantero), Depth, Top (altura de su cara de arriba), Tier y si lleva asientos.
type Segment = { Offset: number, Depth: number, Top: number, Tier: number, Seats: boolean }

local function standProfile(): ({ Segment }, number, number)
	local S = Balance.Stands
	local segments: { Segment } = {}
	local offset, top = 0, 0
	for _ = 1, S.Tier1Rows do
		top += S.RowRise
		table.insert(segments, { Offset = offset, Depth = S.RowDepth, Top = top, Tier = 1, Seats = true })
		offset += S.RowDepth
	end
	top += S.RowRise
	local landingTop = top
	table.insert(segments, { Offset = offset, Depth = S.LandingDepth, Top = top, Tier = 2, Seats = false }) -- pasillo / base del 2o piso
	offset += S.LandingDepth
	for _ = 1, S.Tier2Rows do
		top += S.RowRise
		table.insert(segments, { Offset = offset, Depth = S.RowDepth, Top = top, Tier = 2, Seats = true })
		offset += S.RowDepth
	end
	table.insert(segments, { Offset = offset, Depth = 1, Top = top + 4, Tier = 2, Seats = false }) -- muro trasero
	return segments, landingTop, offset + 1
end

-- Un bloque de grada: centro en planta "center" (local, Y = 0), "along" a lo largo, "out" hacia fuera.
-- "bottom" > 0 lo convierte en una losa elevada (segundo piso sin primer piso debajo).
local function standBlock(model: Model, origin: CFrame, center: Vector3, along: Vector3, length: number, segment: Segment, bottom: number, rng: Random)
	local S = Balance.Stands
	local function basis(position: Vector3): CFrame
		return CFrame.fromMatrix(position, along, Vector3.yAxis)
	end
	local height = segment.Top - bottom
	decor(addPart(model, origin, "Stand", Vector3.new(length, height, segment.Depth), basis(center + Vector3.new(0, bottom + height / 2, 0)), S.Color))
	if not segment.Seats then
		return
	end
	decor(addPart(model, origin, "StandSeats", Vector3.new(length, 0.6, 1.1), basis(center + Vector3.new(0, segment.Top + 0.3, 0)), S.SeatColor, nil, 0, false))
	-- Aficionados sencillos (cuerpo + cabeza) en algunos asientos
	for t = -length / 2 + 1.2, length / 2 - 1.2, 2.4 do
		if rng:NextNumber() < S.FanDensity then
			local base = center + along * t
			decor(addPart(model, origin, "Fan", Vector3.new(1.1, 1.4, 0.8), basis(base + Vector3.new(0, segment.Top + 1.3, 0)), FAN_COLORS[rng:NextInteger(1, #FAN_COLORS)], nil, 0, false))
			local head = addPart(model, origin, "FanHead", Vector3.new(0.9, 0.9, 0.9), basis(base + Vector3.new(0, segment.Top + 2.45, 0)), SKIN_COLORS[rng:NextInteger(1, #SKIN_COLORS)], nil, 0, false)
			head.Shape = Enum.PartType.Ball
			decor(head)
		end
	end
end

-- Grada recta entre "a" y "b" (puntos del borde delantero, locales) con "out" hacia fuera.
-- tier1Range permite acortar el primer piso por un extremo (junto al tunel).
local function addStraightStand(model: Model, origin: CFrame, a: Vector3, b: Vector3, out: Vector3, rng: Random, tier1Trim: { Start: number, Finish: number }?)
	local segments = standProfile()
	local along = (b - a).Unit
	local fullLength = (b - a).Magnitude
	for _, segment in segments do
		local startT, endT = 0, fullLength
		if tier1Trim and segment.Tier == 1 then
			startT += tier1Trim.Start
			endT -= tier1Trim.Finish
		end
		local length = endT - startT
		if length > 0.5 then
			local mid = a + along * ((startT + endT) / 2) + out * (segment.Offset + segment.Depth / 2)
			standBlock(model, origin, mid, along, length, segment, 0, rng)
		end
	end
end

-- Grada curva (cuarto de circulo) alrededor de "pivot", entre las direcciones dirA y dirB (hacia fuera).
-- onlyTier2: solo el segundo piso, elevado (esquina del tunel).
local function addCurvedStand(model: Model, origin: CFrame, pivot: Vector3, dirA: Vector3, dirB: Vector3, rng: Random, onlyTier2: boolean, skip: ((Vector3) -> boolean)?)
	local S = Balance.Stands
	local segments, landingTop = standProfile()
	local count = S.CornerSegments
	local step = (math.pi / 2) / count
	for k = 1, count do
		local theta = (k - 0.5) * step
		local dir = (dirA * math.cos(theta) + dirB * math.sin(theta)).Unit
		local tangent = Vector3.yAxis:Cross(dir).Unit
		if skip == nil or not skip(dir) then
			for _, segment in segments do
				if not onlyTier2 or segment.Tier == 2 then
					local outer = segment.Offset + segment.Depth
					local length = 2 * outer * math.tan(step / 2) + 0.3 -- tapa el hueco del borde exterior
					local center = pivot + dir * (segment.Offset + segment.Depth / 2)
					local bottom = if onlyTier2 then landingTop - S.RowRise else 0
					standBlock(model, origin, center, tangent, length, segment, bottom, rng)
				end
			end
		end
	end
end

local function addSign(part: Part, face: Enum.NormalId, text: string, font: Enum.Font?, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color or TRIM_WHITE
	label.TextScaled = true
	label.Parent = gui
end

-- Tunel de vestuarios (inspirado en un tunel de estadio real): pasillo de cesped entre dos muros verdes con textos,
-- portico verde con escudo y letrero, y dentro un tunel oscuro con escaleras. El segundo piso de grada va por encima.
local function addTunnel(model: Model, origin: CFrame, pivot: Vector3, facadeRadius: number, landingTop: number)
	local F = Balance.Field
	local S = Balance.Stands
	local halfL, halfW, c, T = F.Length / 2, F.Width / 2, F.CornerSize, F.WallThickness
	local cornerMid = Vector3.new(halfL - c / 2, 0, halfW - c / 2)
	local dir = Vector3.new(pivot.X - cornerMid.X, 0, pivot.Z - cornerMid.Z).Unit
	local side = Vector3.yAxis:Cross(dir).Unit
	local w, h = S.TunnelWidth, S.TunnelHeight
	local mouth = cornerMid + dir * (T + 1)
	local portal = pivot + dir * facadeRadius
	local corridor = (portal - mouth).Magnitude
	local function basis(position: Vector3): CFrame
		-- X local = a lo ancho (side), Z local = a lo largo (hacia atras = -dir)
		return CFrame.fromMatrix(position, side, Vector3.yAxis)
	end

	-- Pasillo de cesped al aire libre
	local floor = addPart(model, origin, "TunnelGrass", Vector3.new(w, 0.2, corridor), basis(mouth + dir * (corridor / 2) + Vector3.new(0, 0.1, 0)), Color3.fromRGB(70, 140, 70))
	floor.Material = Enum.Material.Grass
	decor(floor)

	-- Muros laterales verdes con remate blanco y textos
	local wallH = S.WingWallHeight
	local wallTexts = { "FUTBOL GACHA  ·  SIEMPRE CONTIGO", "VESTUARIOS  ·  ¡VAMOS EQUIPO!" }
	for index, sgn in { -1, 1 } do
		local center = mouth + dir * (corridor / 2) + side * sgn * (w / 2 + 0.75)
		local wall = addPart(model, origin, "TunnelWingWall", Vector3.new(1.5, wallH, corridor), basis(center + Vector3.new(0, wallH / 2, 0)), TUNNEL_GREEN)
		decor(wall)
		decor(addPart(model, origin, "TunnelWingTrim", Vector3.new(1.9, 0.4, corridor), basis(center + Vector3.new(0, wallH + 0.2, 0)), TRIM_WHITE))
		addSign(wall, if sgn < 0 then Enum.NormalId.Right else Enum.NormalId.Left, wallTexts[index])
	end

	-- Portico: dos pilares con letrero y dintel verde con escudo, hasta la base del segundo piso
	local pillarW = 3
	for _, sgn in { -1, 1 } do
		local pillar = addPart(model, origin, "TunnelPillar", Vector3.new(pillarW, h, 1.5), basis(portal + side * sgn * (w / 2 + pillarW / 2) + Vector3.new(0, h / 2, 0)), TUNNEL_GREEN)
		decor(pillar)
		addSign(pillar, Enum.NormalId.Front, "TUNNEL\nCLUB", Enum.Font.GothamBold) -- Front = cara que mira al campo
	end
	local headerH = landingTop - h
	local header = addPart(model, origin, "TunnelHeader", Vector3.new(w + 2 * pillarW, headerH, 1.5), basis(portal + Vector3.new(0, h + headerH / 2, 0)), TUNNEL_GREEN)
	decor(header)
	addSign(header, Enum.NormalId.Front, "FG")
	decor(addPart(model, origin, "TunnelHeaderTrim", Vector3.new(w + 2 * pillarW + 0.4, 0.4, 1.9), basis(portal + Vector3.new(0, h + 0.2, 0)), TRIM_WHITE))

	-- Interior: tunel oscuro con escaleras al fondo y luz
	local inner = S.TunnelInnerLength
	local innerCenter = portal + dir * (inner / 2 + 0.75)
	for _, sgn in { -1, 1 } do
		decor(addPart(model, origin, "TunnelInnerWall", Vector3.new(1, h, inner), basis(innerCenter + side * sgn * (w / 2 + 0.5) + Vector3.new(0, h / 2, 0)), TUNNEL_GREEN_DARK))
	end
	decor(addPart(model, origin, "TunnelRoof", Vector3.new(w + 2, 1, inner), basis(innerCenter + Vector3.new(0, h + 0.5, 0)), TUNNEL_GREEN_DARK))
	decor(addPart(model, origin, "TunnelFloor", Vector3.new(w, 0.2, inner), basis(innerCenter + Vector3.new(0, 0.1, 0)), Color3.fromRGB(24, 26, 30)))
	local steps = 6
	for k = 1, steps do
		local stepPos = portal + dir * (inner - 6 + k * 1) + Vector3.new(0, k * 0.5 / 2, 0)
		decor(addPart(model, origin, "TunnelStep", Vector3.new(w, k * 0.5, 1), basis(stepPos), Color3.fromRGB(36, 38, 44)))
	end
	decor(addPart(model, origin, "TunnelBack", Vector3.new(w, h, 1), basis(portal + dir * (inner + 1) + Vector3.new(0, h / 2, 0)), Color3.fromRGB(10, 10, 12)))
	local lamp = addPart(model, origin, "TunnelLamp", Vector3.new(w - 2, 0.2, 1), basis(innerCenter + Vector3.new(0, h - 0.2, 0)), Color3.fromRGB(255, 236, 200), nil, 0, false)
	lamp.Material = Enum.Material.Neon
	decor(lamp)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 226, 180)
	light.Range = 16
	light.Brightness = 1.2
	light.Parent = lamp

	return dir, w / 2 + pillarW -- eje del tunel y medio ancho del portico (para la fachada)
end

local function addStandsAround(model: Model, origin: CFrame)
	local F = Balance.Field
	local S = Balance.Stands
	local halfL, halfW, T, GD = F.Length / 2, F.Width / 2, F.WallThickness, F.GoalDepth
	local rng = Random.new()
	local sideFront = halfW + T + 1 -- borde delantero de las laterales (Z)
	local endFront = halfL + GD + T + 2 -- borde delantero de los fondos (X)
	local _, landingTop = standProfile()
	local facadeRadius = S.Tier1Rows * S.RowDepth -- donde empieza el segundo piso visto desde la esquina
	local tunnelClear = S.TunnelWidth / 2 + 6 -- el primer piso se recorta junto al tunel

	-- Rectas: laterales (a lo largo de X) y fondos (a lo largo de Z). La esquina del tunel es (+X, +Z).
	addStraightStand(model, origin, Vector3.new(-endFront, 0, -sideFront), Vector3.new(endFront, 0, -sideFront), Vector3.new(0, 0, -1), rng)
	addStraightStand(model, origin, Vector3.new(-endFront, 0, sideFront), Vector3.new(endFront, 0, sideFront), Vector3.new(0, 0, 1), rng, { Start = 0, Finish = tunnelClear })
	addStraightStand(model, origin, Vector3.new(-endFront, 0, -sideFront), Vector3.new(-endFront, 0, sideFront), Vector3.new(-1, 0, 0), rng)
	addStraightStand(model, origin, Vector3.new(endFront, 0, -sideFront), Vector3.new(endFront, 0, sideFront), Vector3.new(1, 0, 0), rng, { Start = 0, Finish = tunnelClear })

	-- Curvas en las esquinas
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 } } do
		local sx, sz = corner[1], corner[2]
		addCurvedStand(model, origin, Vector3.new(sx * endFront, 0, sz * sideFront), Vector3.new(sx, 0, 0), Vector3.new(0, 0, sz), rng, false, nil)
	end

	-- Esquina del tunel: solo segundo piso (curvo, elevado) + tunel debajo + fachada negra
	local pivot = Vector3.new(endFront, 0, sideFront)
	local tunnelDir, portalHalf = addTunnel(model, origin, pivot, facadeRadius, landingTop)
	addCurvedStand(model, origin, pivot, Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), rng, true, nil)
	-- Fachada: arco negro a la altura del pasillo, del suelo a la base del 2o piso, salvo donde esta el portico
	local count = S.CornerSegments * 2
	local step = (math.pi / 2) / count
	local facadeH = landingTop - S.RowRise
	for k = 1, count do
		local theta = (k - 0.5) * step
		local dir = Vector3.new(math.cos(theta), 0, math.sin(theta))
		local lateral = math.abs(dir:Cross(tunnelDir).Y) * facadeRadius -- distancia al eje del tunel a lo ancho
		if lateral > portalHalf or dir:Dot(tunnelDir) < 0 then
			local tangent = Vector3.yAxis:Cross(dir).Unit
			local length = 2 * (facadeRadius + 1) * math.tan(step / 2) + 0.3
			local center = pivot + dir * (facadeRadius + 0.5)
			decor(addPart(model, origin, "StandFacade", Vector3.new(length, facadeH, 1), CFrame.fromMatrix(center + Vector3.new(0, facadeH / 2, 0), tangent, Vector3.yAxis), S.Color))
		end
	end
end

-- options.Stands = true rodea el campo de gradas (partido de practica), con el tunel de vestuarios en una esquina.
function ArenaBuilder.build(origin: CFrame, options: { Gate: boolean?, Stands: boolean? }?): Model
	local F = Balance.Field
	local halfL, halfW = F.Length / 2, F.Width / 2
	local T, H = F.WallThickness, F.WallHeight
	local GW, GH, GD = F.GoalWidth, F.GoalHeight, F.GoalDepth

	local model = Instance.new("Model")
	model.Name = "Arena"

	-- Suelo en 3 piezas (el campo no tiene esquinas rectas: van cortadas en diagonal)
	local c = F.CornerSize
	local floorHalfL = halfL + GD + T
	addPart(model, origin, "Floor", Vector3.new(2 * floorHalfL, 1, 2 * (halfW - c)), CFrame.new(0, -0.5, 0), GRASS, FLOOR_PHYSICS)
	-- Las bandas laterales NO se solapan con la central (dos caras al mismo nivel parpadean: z-fighting)
	for _, sz in { -1, 1 } do
		local inner, outer = halfW - c, halfW + T
		addPart(
			model,
			origin,
			"Floor",
			Vector3.new(2 * (halfL - c), 1, outer - inner),
			CFrame.new(0, -0.5, sz * (inner + outer) / 2),
			GRASS,
			FLOOR_PHYSICS
		)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- Rectangulo apoyado en la diagonal que rellena el triangulo de la esquina cortada
			local a = Vector3.new(sx * (halfL - c), 0, sz * halfW)
			local b = Vector3.new(sx * halfL, 0, sz * (halfW - c))
			local inward = -Vector3.new(sx, 0, sz).Unit
			local depth = c / math.sqrt(2)
			local center = (a + b) / 2 + inward * ((depth - T) / 2) + Vector3.new(0, -0.53, 0) -- 3 centesimas por debajo: sin parpadeo donde se solapa
			addPart(
				model,
				origin,
				"Floor",
				Vector3.new(depth + T, 1, (b - a).Magnitude),
				CFrame.lookAt(center, center + (b - a)),
				GRASS,
				FLOOR_PHYSICS
			)
		end
	end
	addMarkings(model, origin)

	local BH = F.BoardHeight

	-- Muros laterales (llegan solo hasta donde empieza la esquina diagonal): muro bajo (rebota) + red hasta arriba
	local sideReach = halfL - c + T
	local gate = options ~= nil and options.Gate == true
	for _, sz in { -1, 1 } do
		local z = sz * (halfW + T / 2)
		if gate and sz == 1 then
			local half = F.GateWidth / 2
			addBarrier(model, origin, "SideWall", Vector3.new(-sideReach, 0, z), Vector3.new(-half, 0, z), BH, BH, H)
			addBarrier(model, origin, "SideWall", Vector3.new(half, 0, z), Vector3.new(sideReach, 0, z), BH, BH, H)
			-- Las 3 filas de cuadros de arriba cruzan la puerta: la red es continua por encima de la entrada
			local rowH = (H - BH) / math.max(1, math.round((H - BH) / 4))
			addBarrier(model, origin, "GateTopNet", Vector3.new(-half, 0, z), Vector3.new(half, 0, z), 0, H - 3 * rowH, H)
			-- Barrera invisible solo para el balon: los jugadores pasan por la puerta, el balon no
			local barrier = addPart(
				model,
				origin,
				"GateBallBarrier",
				Vector3.new(F.GateWidth, H - 3 * rowH, T),
				CFrame.new(0, (H - 3 * rowH) / 2, z),
				NET_COLOR,
				NET_PHYSICS,
				1
			)
			barrier.CanQuery = false
			CollisionSetup.setup()
			barrier.CollisionGroup = CollisionSetup.BALL_ONLY
		else
			addBarrier(model, origin, "SideWall", Vector3.new(-sideReach, 0, z), Vector3.new(sideReach, 0, z), BH, BH, H)
		end
	end

	for _, sx in { -1, 1 } do
		-- Muros de fondo a los lados de la porteria y red sobre ella (en lugar del travesano macizo)
		local wallX = sx * (halfL + T / 2)
		for _, sz in { -1, 1 } do
			addBarrier(model, origin, "EndWall", Vector3.new(wallX, 0, sz * GW / 2), Vector3.new(wallX, 0, sz * (halfW - c + T / 2)), BH, BH, H)
		end
		addBarrier(model, origin, "Crossbar", Vector3.new(wallX, 0, -GW / 2), Vector3.new(wallX, 0, GW / 2), 0, GH, H)

		-- Porteria de red: fondo, laterales y techo. Colision invisible + hilos. No rebotan.
		addPart(model, origin, "GoalBackNet", Vector3.new(T, GH + T, GW + 2 * T), CFrame.new(sx * (halfL + GD + T / 2), (GH + T) / 2, 0), NET_COLOR, GOAL_NET_PHYSICS, 0.9)
		addNetLines(model, origin, CFrame.new(sx * (halfL + GD), GH / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), GW, GH, 1.5)
		addPart(model, origin, "GoalRoofNet", Vector3.new(GD, T, GW), CFrame.new(sx * (halfL + GD / 2), GH + T / 2, 0), NET_COLOR, GOAL_NET_PHYSICS, 0.9)
		addNetLines(model, origin, CFrame.new(sx * (halfL + GD / 2), GH, 0) * CFrame.Angles(math.pi / 2, 0, 0), GD, GW, 1.5)
		for _, sz in { -1, 1 } do
			addPart(model, origin, "GoalSideNet", Vector3.new(GD, GH + T, T), CFrame.new(sx * (halfL + GD / 2), (GH + T) / 2, sz * (GW / 2 + T / 2)), NET_COLOR, GOAL_NET_PHYSICS, 0.9)
			addNetLines(model, origin, CFrame.new(sx * (halfL + GD / 2), GH / 2, sz * GW / 2), GD, GH, 1.5)

			-- Palo (solo visual)
			local post = addPart(model, origin, "Post", Vector3.new(0.6, GH, 0.6), CFrame.new(sx * halfL, GH / 2, sz * GW / 2), LINE, nil, 0, false)
			post.CanQuery = false
		end
		local bar = addPart(model, origin, "CrossbarRod", Vector3.new(0.6, 0.6, GW + 0.6), CFrame.new(sx * halfL, GH, 0), LINE, nil, 0, false)
		bar.CanQuery = false
	end

	-- Esquinas cortadas a 45 grados (el balon no se atasca en un angulo recto)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = Vector3.new(sx * (halfL - c), 0, sz * halfW)
			local b = Vector3.new(sx * halfL, 0, sz * (halfW - c))
			local outward = Vector3.new(sx, 0, sz).Unit * (T / 2)
			addBarrier(model, origin, "Corner", a + outward, b + outward, BH, BH, H)
		end
	end

	if options ~= nil and options.Stands == true then
		addStandsAround(model, origin)
	end

	-- Techo invisible para que el balon nunca salga volando
	addPart(
		model,
		origin,
		"Ceiling",
		Vector3.new(F.Length + 2 * GD + 2 * T, T, F.Width + 2 * T),
		CFrame.new(0, H + T / 2, 0),
		WALL,
		WALL_PHYSICS,
		1
	)

	return model
end

return ArenaBuilder
