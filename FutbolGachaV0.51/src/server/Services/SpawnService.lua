--!strict
-- Lobby de FutbolGacha: entrada de estadio moderna, construida por codigo.
-- El lobby vive en el origen; los partidos se generan a 500 studs de altura.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

local SpawnService = {}

local ROOT_NAME = "FutbolGachaLobby"
local BASE = Vector3.new(0, 0, 0)

local C = {
	Navy = Color3.fromRGB(9, 18, 38),
	Panel = Color3.fromRGB(17, 34, 62),
	Blue = Color3.fromRGB(58, 104, 156), -- azul apagado (antes un neon muy intenso)
	Cyan = Color3.fromRGB(104, 168, 196),
	White = Color3.fromRGB(235, 245, 255),
	Grass = Color3.fromRGB(38, 105, 65),
	DarkGrass = Color3.fromRGB(28, 78, 51),
	Gold = Color3.fromRGB(255, 194, 74),
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function neon(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = part(parent, name, size, cf, color, Enum.Material.Neon)
	p.CanCollide = false
	return p
end

local function makeSign(parent: Instance, adornee: BasePart, title: string, subtitle: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LobbySign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = adornee

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = C.Navy
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0.018, 0, 1, 0)
	stripe.BackgroundColor3 = C.Cyan
	stripe.BorderSizePixel = 0
	stripe.Parent = frame

	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromScale(0.06, 0.12)
	heading.Size = UDim2.fromScale(0.9, 0.48)
	heading.Font = Enum.Font.GothamBlack
	heading.Text = title
	heading.TextColor3 = C.White
	heading.TextScaled = true
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0.065, 0.62)
	sub.Size = UDim2.fromScale(0.88, 0.22)
	sub.Font = Enum.Font.GothamMedium
	sub.Text = subtitle
	sub.TextColor3 = C.Cyan
	sub.TextScaled = true
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Parent = frame
end

-- ---------------------------------------------------------------------------
-- Ambiente: iluminacion, limites, grada con publico, portal de partido y animaciones
-- ---------------------------------------------------------------------------

local function setupLighting()
	local lighting = game:GetService("Lighting")
	lighting.ClockTime = 14 -- siempre de dia
	lighting.GeographicLatitude = 30
	lighting.Brightness = 3
	lighting.Ambient = Color3.fromRGB(120, 124, 134)
	lighting.OutdoorAmbient = Color3.fromRGB(150, 155, 165)
	lighting.ColorShift_Top = Color3.new(0, 0, 0)
	lighting.EnvironmentDiffuseScale = 0.6
	lighting.EnvironmentSpecularScale = 0.5
	lighting.GlobalShadows = true

	for _, name in { "FG_Atmosphere", "FG_Bloom", "FG_Color", "FG_Rays" } do
		local old = lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "FG_Atmosphere"
	atmosphere.Density = 0.2
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(199, 212, 230)
	atmosphere.Decay = Color3.fromRGB(150, 170, 200)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.6
	atmosphere.Parent = lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "FG_Bloom"
	bloom.Intensity = 0.2
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "FG_Color"
	color.Contrast = 0.05
	color.Saturation = 0.1
	color.Parent = lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "FG_Rays"
	rays.Intensity = 0.04
	rays.Spread = 0.5
	rays.Parent = lighting
end

-- V0.70: el lobby ya no esta cerrado. Es el centro del mapa: de el salen los caminos a las granjas, repartidas
-- alrededor (FarmService). Las barreras invisibles estan en el borde del mapa.
local function addBoundaries(model: Model)
	-- Camino del lobby a la puerta del campo de exhibicion (V1.08: antes un paseo ancho de cemento), como los de las
	-- granjas: losas, bordes de piedra, una linea de luz en medio y farolas a los lados
	local gap = Balance.Playground.ExhibitionGap
	local pathLength = gap + 4 -- (entra un poco bajo el borde del lobby y hasta el muro del campo)
	local pathCenter = BASE + Vector3.new(-75 - gap / 2, -0.55, 0)
	part(model, "ExhibitionPath", Vector3.new(pathLength, 0.1, 14), CFrame.new(pathCenter), C.Panel, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		part(model, "ExhibitionPathEdge", Vector3.new(pathLength, 0.3, 0.8), CFrame.new(pathCenter + Vector3.new(0, 0.1, side * 7.2)), C.Navy, Enum.Material.Cobblestone)
		for x = -75 - 12, -75 - gap + 8, -16 do
			local base = BASE + Vector3.new(x, -0.5, side * 10)
			part(model, "PathLampPole", Vector3.new(0.5, 9, 0.5), CFrame.new(base + Vector3.new(0, 4.5, 0)), C.Panel, Enum.Material.Metal)
			local bulb = neon(model, "PathLampBulb", Vector3.new(1.4, 1.4, 1.4), CFrame.new(base + Vector3.new(0, 9.3, 0)), C.White)
			bulb.Shape = Enum.PartType.Ball
		end
	end
	neon(model, "ExhibitionPathGlow", Vector3.new(pathLength - 2, 0.06, 0.4), CFrame.new(pathCenter + Vector3.new(0, 0.08, 0)), C.Cyan)
	-- Borde luminoso (suave) de la plataforma
	for _, z in { -58, 58 } do
		neon(model, "EdgeGlow", Vector3.new(146, 0.2, 0.3), CFrame.new(BASE + Vector3.new(0, -0.45, z)), C.Blue)
	end
	for _, x in { -73, 73 } do
		neon(model, "EdgeGlow", Vector3.new(0.3, 0.2, 116), CFrame.new(BASE + Vector3.new(x, -0.45, 0)), C.Blue)
	end
end

-- Maniquies sentados (decoracion). "position" = punto del asiento (parte alta del escalon), "facing" = hacia donde miran,
-- "rise" = desnivel hasta la fila de delante (alarga las espinillas hasta apoyar los pies).
local MANNEQUIN_SKIN = Color3.fromRGB(206, 198, 184)
local MANNEQUIN_SHIRTS = {
	Color3.fromRGB(206, 198, 184),
	Color3.fromRGB(206, 198, 184),
	Color3.fromRGB(235, 235, 235),
	Color3.fromRGB(58, 104, 156),
	Color3.fromRGB(176, 66, 58),
	Color3.fromRGB(214, 176, 80),
}

local function addMannequin(folder: Instance, position: Vector3, facing: Vector3, rise: number, rng: Random)
	local cf = CFrame.lookAt(position, position + facing)
	local model = Instance.new("Model")
	model.Name = "Mannequin"
	local shirt = MANNEQUIN_SHIRTS[rng:NextInteger(1, #MANNEQUIN_SHIRTS)]

	local function piece(size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf * CFrame.new(offset)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		if shape then
			p.Shape = shape
		end
		p.Parent = model
	end

	piece(Vector3.new(1.0, 0.4, 1.4), Vector3.new(0, 0.2, -0.5), shirt) -- muslos
	piece(Vector3.new(0.9, rise, 0.4), Vector3.new(0, 0.4 - rise / 2, -1.1), MANNEQUIN_SKIN) -- espinillas
	piece(Vector3.new(1.2, 1.5, 0.6), Vector3.new(0, 1.15, 0.2), shirt) -- torso
	piece(Vector3.new(0.35, 1.3, 0.35), Vector3.new(-0.78, 1.1, 0.1), MANNEQUIN_SKIN) -- brazos
	piece(Vector3.new(0.35, 1.3, 0.35), Vector3.new(0.78, 1.1, 0.1), MANNEQUIN_SKIN)
	piece(Vector3.new(0.95, 0.95, 0.95), Vector3.new(0, 2.35, 0.2), MANNEQUIN_SKIN, Enum.PartType.Ball) -- cabeza
	model.Parent = folder
end

-- Ocupa "casi al azar" unos cuantos asientos: algunos huecos, otros con grupos.
local function shouldSeat(rng: Random, density: number): boolean
	return rng:NextNumber() < density
end

-- ---------------------------------------------------------------------------
-- Asientos de estadio (cubeta + respaldo). "rowTop" = punto en la parte alta del escalon, centro del asiento.
-- Devuelve el punto donde se sienta alguien (encima de la cubeta).
-- ---------------------------------------------------------------------------
local SEAT_HEIGHT = 0.95 -- altura de la cubeta sobre el escalon (los pies del que se sienta llegan al suelo)
local function addSeat(folder: Instance, rowTop: Vector3, facing: Vector3, color: Color3): Vector3
	local cf = CFrame.lookAt(rowTop, rowTop + facing) -- -Z local = hacia el campo
	local function seatPart(name: string, size: Vector3, offset: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
	end
	seatPart("SeatPost", Vector3.new(0.3, SEAT_HEIGHT, 0.3), CFrame.new(0, SEAT_HEIGHT / 2, 0.1))
	seatPart("SeatPan", Vector3.new(1.7, 0.25, 1.3), CFrame.new(0, SEAT_HEIGHT + 0.125, -0.05))
	seatPart("SeatBack", Vector3.new(1.7, 1.3, 0.22), CFrame.new(0, SEAT_HEIGHT + 0.25 + 0.65, 0.62) * CFrame.Angles(math.rad(-8), 0, 0))
	return (cf * CFrame.new(0, SEAT_HEIGHT + 0.25, -0.05)).Position
end

-- ---------------------------------------------------------------------------
-- Publico del lobby: personajes R15 normales de Roblox, cada uno con su estilo (piel, ropa, complexion,
-- gorra, bufanda, postura). Sentados en su asiento y anclados (no consumen fisica).
-- ---------------------------------------------------------------------------
local SKIN_TONES = {
	Color3.fromRGB(255, 224, 189),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(92, 58, 34),
}
local SHIRT_COLORS = {
	Color3.fromRGB(52, 120, 246), -- azul (local)
	Color3.fromRGB(52, 120, 246),
	Color3.fromRGB(235, 64, 52), -- rojo (visitante)
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(30, 30, 36),
	Color3.fromRGB(245, 205, 48),
	Color3.fromRGB(40, 150, 80),
	Color3.fromRGB(240, 130, 40),
	Color3.fromRGB(120, 70, 170),
}
local PANTS_COLORS = {
	Color3.fromRGB(38, 52, 84), -- vaquero oscuro
	Color3.fromRGB(70, 100, 150), -- vaquero claro
	Color3.fromRGB(25, 25, 28),
	Color3.fromRGB(110, 110, 116),
	Color3.fromRGB(96, 72, 52),
	Color3.fromRGB(190, 180, 150),
}

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function attachTo(parent: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = p
	weld.Parent = p
	p.Parent = parent.Parent
end

local function bendJoint(model: Model, partName: string, motorName: string, angle: CFrame)
	local part = model:FindFirstChild(partName)
	if not part then
		return
	end
	for _, joint in part:GetChildren() do
		if joint.Name == motorName then
			if joint:IsA("Motor6D") then
				joint.C0 = joint.C0 * angle
				return
			elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
				-- articulaciones nuevas de Roblox: se gira el punto de union del lado del padre
				joint.Attachment0.CFrame = joint.Attachment0.CFrame * angle
				return
			end
		end
	end
end

local function addSpectator(folder: Instance, sitPoint: Vector3, facing: Vector3, rng: Random)
	local skin = pick(rng, SKIN_TONES)
	local shirt = pick(rng, SHIRT_COLORS)
	local pants = pick(rng, PANTS_COLORS)
	local longSleeves = rng:NextNumber() < 0.5

	local description = Instance.new("HumanoidDescription")
	description.HeadColor = skin
	description.TorsoColor = shirt
	description.LeftArmColor = if longSleeves then shirt else skin
	description.RightArmColor = if longSleeves then shirt else skin
	description.LeftLegColor = pants
	description.RightLegColor = pants
	description.HeightScale = rng:NextNumber(0.9, 1.05)
	description.WidthScale = rng:NextNumber(0.85, 1.1)
	description.DepthScale = description.WidthScale
	description.HeadScale = rng:NextNumber(0.95, 1.08)
	description.BodyTypeScale = rng:NextNumber(0, 0.3)
	description.ProportionScale = rng:NextNumber(0, 0.5)

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		return
	end
	local model = result :: Model
	model.Name = "Spectator"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lowerTorso = model:FindFirstChild("LowerTorso") :: BasePart?
	local upperLeg = model:FindFirstChild("RightUpperLeg") :: BasePart?
	if not humanoid or not root or not lowerTorso or not upperLeg then
		model:Destroy()
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	pcall(function()
		humanoid.EvaluateStateMachine = false -- no piensa: es decoracion
	end)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	root.Anchored = true

	-- Altura de la cadera respecto al centro del personaje (medida de pie, antes de sentarlo)
	local hip = upperLeg:FindFirstChild("RightHip")
	local hipLocal = if hip and hip:IsA("Motor6D")
		then root.CFrame:PointToObjectSpace((lowerTorso.CFrame * hip.C0).Position)
		else Vector3.new(0, -1, 0)
	local thighThickness = upperLeg.Size.Z

	-- Postura sentada: muslos hacia delante, espinillas hacia abajo
	local forward = CFrame.Angles(math.rad(90), 0, 0)
	local down = CFrame.Angles(math.rad(-90), 0, 0)
	bendJoint(model, "RightUpperLeg", "RightHip", forward)
	bendJoint(model, "LeftUpperLeg", "LeftHip", forward)
	bendJoint(model, "RightLowerLeg", "RightKnee", down)
	bendJoint(model, "LeftLowerLeg", "LeftKnee", down)

	-- Brazos: unos animan con los brazos arriba, otros los apoyan en las piernas, otros los dejan caer
	local armStyle = rng:NextNumber()
	if armStyle < 0.2 then
		local up = CFrame.Angles(math.rad(165), 0, 0)
		bendJoint(model, "RightUpperArm", "RightShoulder", up)
		bendJoint(model, "LeftUpperArm", "LeftShoulder", up)
	elseif armStyle < 0.55 then
		local lap = CFrame.Angles(math.rad(45), 0, 0)
		bendJoint(model, "RightUpperArm", "RightShoulder", lap)
		bendJoint(model, "LeftUpperArm", "LeftShoulder", lap)
	elseif armStyle < 0.7 then
		bendJoint(model, "RightUpperArm", "RightShoulder", CFrame.Angles(math.rad(165), 0, 0)) -- saluda con una mano
	end

	-- Colocacion: la cadera sobre la cubeta, un poco hacia el respaldo
	-- (en el espacio del personaje +Z es hacia atras, por eso hipLocal.Z se suma en la direccion de "facing")
	local rootPos = sitPoint + Vector3.new(0, thighThickness / 2 - hipLocal.Y, 0) - facing.Unit * (0.35 - hipLocal.Z)
	model:PivotTo(CFrame.lookAt(rootPos, rootPos + facing))

	-- Complementos (cada aficionado distinto)
	local head = model:FindFirstChild("Head") :: BasePart?
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	local teamColor = if rng:NextNumber() < 0.6 then Color3.fromRGB(52, 120, 246) else Color3.fromRGB(235, 64, 52)
	if head and rng:NextNumber() < 0.3 then
		local hs = head.Size
		attachTo(head, "Cap", Vector3.new(hs.X * 1.05, hs.Y * 0.32, hs.Z * 1.05), head.CFrame * CFrame.new(0, hs.Y * 0.38, 0), teamColor)
		attachTo(head, "CapBrim", Vector3.new(hs.X * 0.85, 0.12, hs.Z * 0.6), head.CFrame * CFrame.new(0, hs.Y * 0.26, -hs.Z * 0.65), teamColor)
	elseif head and rng:NextNumber() < 0.15 then
		local hs = head.Size
		attachTo(head, "Beanie", Vector3.new(hs.X * 1.08, hs.Y * 0.45, hs.Z * 1.08), head.CFrame * CFrame.new(0, hs.Y * 0.33, 0), pick(rng, SHIRT_COLORS))
	end
	if torso and rng:NextNumber() < 0.35 then
		local ts = torso.Size
		attachTo(torso, "Scarf", Vector3.new(ts.X * 0.7, 0.35, ts.Z * 1.2), torso.CFrame * CFrame.new(0, ts.Y / 2 - 0.12, 0), teamColor)
		attachTo(torso, "ScarfEnd", Vector3.new(0.4, ts.Y * 0.7, 0.12), torso.CFrame * CFrame.new(ts.X * 0.18, ts.Y * 0.1, -ts.Z / 2 - 0.08), teamColor)
	end

	model.Parent = folder
end

-- Asientos y publico de las gradas del lobby. Los personajes se crean en segundo plano (cada uno tarda un poco).
local function addLobbyCrowd(model: Model)
	local folder = Instance.new("Folder")
	folder.Name = "Crowd"
	folder.Parent = model
	local seatsFolder = Instance.new("Folder")
	seatsFolder.Name = "Seats"
	seatsFolder.Parent = folder
	local rng = Random.new(2026)
	local seatColor = Color3.fromRGB(58, 104, 156)
	local spots: { { Vector3 } } = {}
	for _, side in { -1, 1 } do
		for row = 1, 4 do
			local rowTopY = 1 + row * 2.1 + 0.9 -- parte alta del escalon
			local z = side * (31 + row * 3.1)
			local facing = Vector3.new(0, 0, -side)
			for x = -29, 29, 2.4 do
				local sitPoint = addSeat(seatsFolder, BASE + Vector3.new(x, rowTopY, z), facing, seatColor)
				if shouldSeat(rng, 0.3) then
					table.insert(spots, { sitPoint, facing })
				end
			end
		end
	end
	task.spawn(function()
		for _, spot in spots do
			addSpectator(folder, spot[1], spot[2], rng)
		end
	end)
end

-- Campo de exhibicion: un campo igual que el de partido (siempre generado), al lado del lobby, con una sola
-- grada de dos pisos en el lado lejano y maniquies repartidos por ella. Se entra por la puerta y se juega libre
-- con el balon (patio de juegos; la logica esta en MatchService / Match.newPlayground).
local function addExhibitionField(model: Model)
	local F = Balance.Field
	local T = F.WallThickness
	local P = Balance.Playground
	local origin = CFrame.new(BASE + P.Position) * CFrame.Angles(0, P.RotationY, 0)
	-- Coordenadas locales del campo: X = largo, Z = ancho. El lado +Z mira al lobby; la grada va en -Z.

	local field = ArenaBuilder.build(origin, { Gate = true }) -- con puerta: el campo es un patio de juegos (ver MatchService)
	field.Name = "ExhibitionField"
	field.Parent = model

	-- Gradas en U alrededor del campo (V1.08): el lado del fondo y los dos fondos de porteria, unidos por esquinas
	-- curvas; el lado que mira al lobby queda abierto (por ahi llega el camino). Dos pisos con un pasillo en medio.
	-- Cada fila sigue el contorno del campo a una distancia "r" de su muro: rectas a los lados y, en las esquinas del
	-- fondo, un cuarto de circulo de radio r centrado en la esquina del campo.
	local standFolder = Instance.new("Folder")
	standFolder.Name = "ExhibitionStand"
	standFolder.Parent = model
	local hx = F.Length / 2 + T -- medio largo del campo con su muro (eje X local)
	local hz = F.Width / 2 + T -- medio ancho (eje Z local; +Z = lado del lobby)
	local rowDepth, rowRise = 3, 1.6
	local rowsPerTier = 6
	local landing = 6
	local gap = 1 -- entre el muro del campo y la primera fila
	local endCut = 18 -- los fondos se paran antes del lado del lobby (boca de entrada; lejos de los caminos de las granjas)

	-- Trozos de un anillo de la U a la distancia r (centro de la franja = r + depth / 2): { centro, tangente, hacia el campo, largo }
	type Piece = { Center: Vector3, Tangent: Vector3, Inward: Vector3, Length: number }
	local function ring(r: number, depth: number): { Piece }
		local mid = r + depth / 2
		local pieces: { Piece } = {
			{ Center = Vector3.new(0, 0, -(hz + mid)), Tangent = Vector3.xAxis, Inward = Vector3.zAxis, Length = 2 * hx },
		}
		for _, s in { -1, 1 } do
			local zFrom, zTo = -hz, hz - endCut
			table.insert(pieces, {
				Center = Vector3.new(s * (hx + mid), 0, (zFrom + zTo) / 2),
				Tangent = Vector3.zAxis,
				Inward = Vector3.new(-s, 0, 0),
				Length = zTo - zFrom,
			})
			-- Esquina curva: de la direccion -Z (fondo) a la direccion s*X (fondo de porteria)
			local corner = Vector3.new(s * hx, 0, -hz)
			local steps = math.max(3, math.ceil(mid * math.pi / 2 / 5))
			local delta = (math.pi / 2) / steps
			for i = 1, steps do
				local phi = (i - 0.5) * delta
				local dir = Vector3.new(s * math.sin(phi), 0, -math.cos(phi))
				table.insert(pieces, {
					Center = corner + dir * mid,
					Tangent = Vector3.new(-dir.Z, 0, dir.X),
					Inward = -dir,
					Length = 2 * (r + depth) * math.sin(delta / 2) + 0.4, -- (cubre el borde de fuera sin huecos)
				})
			end
		end
		return pieces
	end

	local function block(name: string, piece: Piece, sizeY: number, depth: number, yBottom: number, color: Color3, material: Enum.Material)
		local position = origin:PointToWorldSpace(piece.Center + Vector3.new(0, yBottom + sizeY / 2, 0))
		local cf = CFrame.fromMatrix(position, origin:VectorToWorldSpace(piece.Tangent), Vector3.yAxis)
		local p = part(standFolder, name, Vector3.new(piece.Length, sizeY, depth), cf, color, material)
		p.CastShadow = false
		return p
	end

	-- Filas (cada una un escalon macizo desde el suelo) y el pasillo entre pisos
	local rows: { { R: number, Height: number, Upper: boolean } } = {}
	local r = gap
	local height = 0
	for tier = 1, 2 do
		for row = 1, rowsPerTier do
			height += rowRise
			for _, piece in ring(r, rowDepth) do
				block("StandRow", piece, height, rowDepth, 0, if (tier + row) % 2 == 0 then C.Blue else C.Panel, Enum.Material.Metal)
			end
			table.insert(rows, { R = r, Height = height, Upper = tier == 2 })
			r += rowDepth
		end
		if tier == 1 then
			height += rowRise
			for _, piece in ring(r, landing) do
				block("StandLanding", piece, height, landing, 0, C.Navy, Enum.Material.Concrete)
			end
			r += landing
		end
	end
	-- Muro trasero (sin cubierta) con una franja de luz
	for _, piece in ring(r, 1) do
		block("StandBack", piece, 8, 1, height, C.Navy, Enum.Material.Metal)
	end
	for _, piece in ring(r - 0.1, 0.2) do
		local glow = block("StandBackGlow", piece, 0.3, 0.2, height + 7.2, C.Cyan, Enum.Material.Neon)
		glow.CanCollide = false
	end

	-- Asientos (azules abajo, rojos arriba) y maniquies sencillos en algunos
	local seatsFolder = Instance.new("Folder")
	seatsFolder.Name = "Seats"
	seatsFolder.Parent = standFolder
	local mannequins = Instance.new("Folder")
	mannequins.Name = "Mannequins"
	mannequins.Parent = standFolder
	local rng = Random.new(77)
	for _, row in rows do
		local color = if row.Upper then Color3.fromRGB(176, 66, 58) else Color3.fromRGB(58, 104, 156)
		for _, piece in ring(row.R, rowDepth) do
			local usable = piece.Length - 1.2
			local count = math.max(1, math.floor(usable / 2.4))
			local facing = origin:VectorToWorldSpace(piece.Inward)
			for k = 1, count do
				local along = -usable / 2 + (k - 0.5) * usable / count
				local localPoint = piece.Center + piece.Tangent * along + Vector3.new(0, row.Height, 0)
				local sitPoint = addSeat(seatsFolder, origin:PointToWorldSpace(localPoint), facing, color)
				if shouldSeat(rng, 0.18) then
					addMannequin(mannequins, sitPoint, facing, SEAT_HEIGHT + 0.65, rng) -- espinillas hasta el escalon
				end
			end
		end
	end
end

-- Portal de partido: acercate y mantén la tecla del aviso para jugar (equivale al boton verde).
local function addMatchPortal(model: Model): (BasePart, BasePart)
	local center = BASE + Vector3.new(0, 0.85, 20)
	local base = part(model, "PortalBase", Vector3.new(0.4, 16, 16), CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Navy, Enum.Material.Metal)
	base.Shape = Enum.PartType.Cylinder
	local ring = part(model, "PortalRing", Vector3.new(0.5, 14, 14), CFrame.new(center + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Cyan, Enum.Material.Neon, 0.15)
	ring.Shape = Enum.PartType.Cylinder
	ring.CanCollide = false
	local inner = part(model, "PortalInner", Vector3.new(0.3, 11.2, 11.2), CFrame.new(center + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Navy, Enum.Material.SmoothPlastic)
	inner.Shape = Enum.PartType.Cylinder
	local beam = part(model, "PortalBeam", Vector3.new(18, 10, 10), CFrame.new(center + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Cyan, Enum.Material.Neon, 0.8)
	beam.Shape = Enum.PartType.Cylinder
	beam.CanCollide = false
	beam.CastShadow = false

	local light = Instance.new("PointLight")
	light.Color = C.Cyan
	light.Brightness = 2.5
	light.Range = 30
	light.Parent = beam

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(C.Cyan, C.White)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(1.5, 2.5)
	sparks.Rate = 26
	sparks.Speed = NumberRange.new(3, 6)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Parent = inner

	-- Cartel flotante
	local anchor = part(model, "PortalLabel", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 15, 0)), C.Navy, Enum.Material.SmoothPlastic, 1)
	anchor.CanCollide = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(300, 64)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 140
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "JUGAR PARTIDO"
	label.TextColor3 = C.White
	label.TextStrokeColor3 = C.Blue
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Jugar partido de práctica"
	prompt.ObjectText = "Portal de partido"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = inner
	prompt.Triggered:Connect(function(player: Player)
		-- require perezoso: MatchService se carga despues que este servicio
		local services = script.Parent
		local ok, MatchService = pcall(function()
			return require(services:WaitForChild("MatchService")) :: any
		end)
		if ok then
			MatchService.startPractice(player)
		end
	end)
	return ring, beam
end

-- Las animaciones del lobby (balon que flota, anillos del portal) las hace cada cliente (LobbyController): antes las
-- movia el servidor en cada fotograma y mandaba esas 4 piezas a todos los jugadores 60 veces por segundo.
local function animate(ball: BasePart, ballRing: BasePart, portalRing: BasePart, portalBeam: BasePart)
	for part, kind in { [ball] = "BallBob", [ballRing] = "BallRing", [portalRing] = "PortalRing", [portalBeam] = "PortalBeam" } do
		part:SetAttribute("LobbyAnim", kind)
		CollectionService:AddTag(part, "LobbyAnim")
	end
end

-- Red de seguridad: si algo hace caer a un jugador al vacio, vuelve al spawn del lobby.
local function addVoidRescue()
	task.spawn(function()
		local Players = game:GetService("Players")
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local rootInstance = if character then character:FindFirstChild("HumanoidRootPart") else nil
				if character and rootInstance and rootInstance:IsA("BasePart") then
					local y = rootInstance.Position.Y
					if y < -30 and y > -400 then
						character:PivotTo(CFrame.new(BASE + Vector3.new(0, 4, -7)))
						rootInstance.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
		end
	end)
end

local function decorate(model: Model, ball: BasePart, ballRing: BasePart)
	addVoidRescue()
	setupLighting()
	addBoundaries(model)
	addLobbyCrowd(model)
	addExhibitionField(model)
	local ring, beam = addMatchPortal(model)
	animate(ball, ballRing, ring, beam)
end

local function buildLobby()
	-- Roblox suele crear una Baseplate por defecto. Su cara superior estaba
	-- exactamente a la misma altura que la Foundation, causando z-fighting
	-- (parpadeo de superficies). Quitamos solo la Baseplate predeterminada.
	local defaultBaseplate = workspace:FindFirstChild("Baseplate")
	if defaultBaseplate and defaultBaseplate:IsA("BasePart") then
		defaultBaseplate:Destroy()
	end

	local existing = workspace:FindFirstChild(ROOT_NAME)
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = ROOT_NAME
	model.Parent = workspace

	-- Plataforma principal oscura con una zona de césped central.
	part(model, "Foundation", Vector3.new(150, 2, 120), CFrame.new(BASE + Vector3.new(0, -1.5, 0)), C.Navy, Enum.Material.Concrete)
	part(model, "LobbyFloor", Vector3.new(112, 0.5, 82), CFrame.new(BASE + Vector3.new(0, 0.25, 0)), C.Panel, Enum.Material.Slate)
	part(model, "CentralTurf", Vector3.new(62, 0.25, 42), CFrame.new(BASE + Vector3.new(0, 0.625, 0)), C.Grass, Enum.Material.Grass)

	-- Franjas decorativas del césped.
	for i = -4, 4 do
		if i % 2 == 0 then
			part(model, "TurfStripe", Vector3.new(6, 0.08, 41.5), CFrame.new(BASE + Vector3.new(i * 6.5, 0.79, 0)), C.DarkGrass, Enum.Material.Grass) -- 8 centesimas sobre el cesped: sin parpadeo de lejos
		end
	end

	-- Líneas de campo estilizadas, solo decorativas.
	neon(model, "CenterLine", Vector3.new(0.18, 0.05, 41), CFrame.new(BASE + Vector3.new(0, 0.88, 0)), C.White)

	-- Acceso monumental al fondo del lobby (lado Z positivo).
	for _, x in { -25, 25 } do
		part(model, "GatePillar", Vector3.new(5, 24, 5), CFrame.new(BASE + Vector3.new(x, 12, 43)), C.Panel, Enum.Material.Metal)
		neon(model, "PillarLight", Vector3.new(0.35, 21, 0.25), CFrame.new(BASE + Vector3.new(x - 2.58, 12, 40.4)), C.Cyan)
	end

	part(model, "GateHeader", Vector3.new(55, 4, 7), CFrame.new(BASE + Vector3.new(0, 23, 43)), C.Navy, Enum.Material.Metal)
	neon(model, "GateHeaderLight", Vector3.new(48, 0.35, 0.25), CFrame.new(BASE + Vector3.new(0, 20.8, 39.35)), C.Blue)

	local sign = part(model, "MainSign", Vector3.new(38, 10, 0.8), CFrame.new(BASE + Vector3.new(0, 22, 39)), C.Navy, Enum.Material.Metal)
	sign.CanCollide = false
	makeSign(model, sign, "STRIKER BRAINROT", "ENTRA AL CAMPO  •  JUEGA  •  CONVIÉRTETE EN LEYENDA")

	-- Laterales arquitectónicos con iluminación azul.
	--for _, z in { -28, 28 } do 
		-- part(model, "SideWall", Vector3.new(112, 12, 2), CFrame.new(BASE + Vector3.new(0, 6, z)), C.Navy, Enum.Material.Metal)
		-- neon(model, "SideLight", Vector3.new(105, 0.3, 0.25), CFrame.new(BASE + Vector3.new(0, 11.8, z - (z > 0 and 1.15 or -1.15))), C.Blue)
	--end

	-- Gradas compactas a ambos lados para crear profundidad sin cerrar el lobby.
	for _, side in { -1, 1 } do
		for row = 1, 4 do
			local y = 1 + row * 2.1
			local z = side * (31 + row * 3.1)
			part(model, "StandRow", Vector3.new(62, 1.8, 3.2), CFrame.new(BASE + Vector3.new(0, y, z)), row % 2 == 0 and C.Blue or C.Panel, Enum.Material.Metal)
		end
	end

	-- Focos altos apuntando hacia el centro.
	for _, x in { -48, 48 } do
		for _, z in { -35, 35 } do
			part(model, "FloodlightPole", Vector3.new(1.2, 27, 1.2), CFrame.new(BASE + Vector3.new(x, 13.5, z)), C.Panel, Enum.Material.Metal)
			local lamp = part(model, "Floodlight", Vector3.new(8, 1.2, 3), CFrame.new(BASE + Vector3.new(x, 27.5, z)), C.White, Enum.Material.Neon)
			lamp.CanCollide = false
			local light = Instance.new("PointLight")
			light.Color = C.White
			light.Brightness = 0.3
			light.Range = 38
			light.Shadows = false
			light.Parent = lamp
		end
	end

	-- Cubierta superior: vigas y perfiles para que la entrada tenga más volumen.
	for _, x in { -38, -19, 0, 19, 38 } do
		part(model, "RoofBeam", Vector3.new(1.1, 1.1, 70), CFrame.new(BASE + Vector3.new(x, 29, 5)), C.Panel, Enum.Material.Metal)
	end
	part(model, "RoofCrossbeam", Vector3.new(82, 1.4, 2), CFrame.new(BASE + Vector3.new(0, 29, 5)), C.Navy, Enum.Material.Metal)
	neon(model, "RoofAccent", Vector3.new(76, 0.18, 0.25), CFrame.new(BASE + Vector3.new(0, 28.2, 5)), C.Cyan)

	-- (V0.93: quitados los paneles laterales de bienvenida "PLAY" y "RANK UP": tapaban la vista)

	-- Elimina el SpawnLocation de la plantilla para que no haya
	-- dos puntos de aparición compitiendo entre sí.
	for _, item in workspace:GetDescendants() do
		if item:IsA("SpawnLocation") then
			item:Destroy()
		end
	end

	-- Spawn visible: plataforma con anillo de neon, mirando hacia la entrada (Z positivo).
	local spawnPos = BASE + Vector3.new(0, 1.05, -7)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(9, 0.5, 9)
	spawn.CFrame = CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, 1))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C.Navy
	spawn.Material = Enum.Material.Metal
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.CanCollide = true
	spawn.Parent = model
	for _, d in { -4.35, 4.35 } do
		neon(model, "SpawnEdgeX", Vector3.new(0.3, 0.1, 9), CFrame.new(spawnPos + Vector3.new(d, 0.3, 0)), C.Cyan)
		neon(model, "SpawnEdgeZ", Vector3.new(9, 0.1, 0.3), CFrame.new(spawnPos + Vector3.new(0, 0.3, d)), C.Cyan)
	end
	-- Balon decorativo sobre un pedestal al lado de la entrada (gira y flota, ver animaciones).
	local pedestalPos = BASE + Vector3.new(36, 1.1, 35)
	local pedestal = part(model, "BallPedestal", Vector3.new(1.2, 5, 5), CFrame.new(pedestalPos) * CFrame.Angles(0, 0, math.rad(90)), C.Panel, Enum.Material.Metal)
	pedestal.Shape = Enum.PartType.Cylinder
	local ball = part(model, "LobbyBall", Vector3.new(3.2, 3.2, 3.2), CFrame.new(BASE + Vector3.new(36, 3.6, 35)), C.White, Enum.Material.SmoothPlastic)
	ball.Shape = Enum.PartType.Ball
	ball.CanCollide = false
	local ballRing = part(model, "BallAccent", Vector3.new(0.12, 3.5, 3.5), CFrame.new(BASE + Vector3.new(36, 3.6, 35)) * CFrame.Angles(0, 0, math.rad(90)), C.Blue, Enum.Material.Neon, 0.2)
	ballRing.Shape = Enum.PartType.Cylinder
	ballRing.CanCollide = false

	decorate(model, ball, ballRing)

	model:SetAttribute("LobbySpawnReady", true)
end

function SpawnService.start()
	buildLobby()
	print("[SpawnService] Lobby de estadio FutbolGacha creado")
end

return SpawnService
