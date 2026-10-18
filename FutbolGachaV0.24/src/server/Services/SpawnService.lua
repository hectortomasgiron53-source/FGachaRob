--!strict
-- Lobby de FutbolGacha: entrada de estadio moderna, construida por codigo.
-- El lobby vive en el origen; los partidos se generan a 500 studs de altura.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- Muros invisibles en el borde de la plataforma (lobby + paseo hacia el campo de exhibicion).
local function addBoundaries(model: Model)
	local specs = {
		{ Vector3.new(2, 60, 124), Vector3.new(-107, 28, 0) },
		{ Vector3.new(2, 60, 124), Vector3.new(76, 28, 0) },
		{ Vector3.new(187, 60, 2), Vector3.new(-15.5, 28, -61) },
		{ Vector3.new(187, 60, 2), Vector3.new(-15.5, 28, 61) },
	}
	for _, spec in specs do
		local wall = part(model, "Boundary", spec[1], CFrame.new(BASE + spec[2]), C.Navy, Enum.Material.SmoothPlastic, 1)
		wall.CanQuery = false
	end
	-- Paseo de cemento que une el lobby con el campo de exhibicion (misma altura que la plataforma)
	part(model, "Promenade", Vector3.new(33, 2, 120), CFrame.new(BASE + Vector3.new(-91.5, -1.5, 0)), C.Navy, Enum.Material.Concrete)
	-- Borde luminoso (suave) de la plataforma
	for _, z in { -58, 58 } do
		neon(model, "EdgeGlow", Vector3.new(180, 0.2, 0.3), CFrame.new(BASE + Vector3.new(-16, -0.45, z)), C.Blue)
	end
	for _, x in { -105, 73 } do
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

-- Maniquies en las gradas del lobby
local function addMannequins(model: Model)
	local folder = Instance.new("Folder")
	folder.Name = "Mannequins"
	folder.Parent = model
	local rng = Random.new(2026)
	for _, side in { -1, 1 } do
		for row = 1, 4 do
			local seatY = 1 + row * 2.1 + 0.9 -- parte alta del escalon
			local z = side * (31 + row * 3.1)
			for x = -29, 29, 2.4 do
				if shouldSeat(rng, 0.3) then
					addMannequin(folder, BASE + Vector3.new(x, seatY, z), Vector3.new(0, 0, -side), 2.1, rng)
				end
			end
		end
	end
end

-- Campo de exhibicion: un campo igual que el de partido (siempre generado), al lado del lobby, con una sola
-- grada de dos pisos en el lado lejano y maniquies repartidos por ella. Solo se mira: nadie puede entrar.
local function addExhibitionField(model: Model)
	local F = Balance.Field
	local T = F.WallThickness
	local origin = CFrame.new(BASE + Vector3.new(-150, -0.5, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	-- Coordenadas locales del campo: X = largo, Z = ancho. El lado +Z mira al lobby; la grada va en -Z.

	local field = ArenaBuilder.build(origin)
	field.Name = "ExhibitionField"
	field.Parent = model

	-- Balon de adorno en el centro del campo
	local ball = part(model, "ExhibitionBall", Vector3.new(3, 3, 3), origin * CFrame.new(0, 1.5, 0), C.White, Enum.Material.SmoothPlastic)
	ball.Shape = Enum.PartType.Ball
	ball.CanCollide = false

	-- Grada de dos pisos
	local standFolder = Instance.new("Folder")
	standFolder.Name = "ExhibitionStand"
	standFolder.Parent = model
	local length = 120
	local rowDepth, rowRise = 3, 1.6
	local rowsPerTier = 6
	local landing = 6
	local zStart = -(F.Width / 2 + T + 1) -- borde de la grada pegado al muro del campo (hacia -Z)

	local function block(name: string, sizeY: number, depth: number, zFront: number, color: Color3, material: Enum.Material)
		local p = part(
			standFolder,
			name,
			Vector3.new(length, sizeY, depth),
			origin * CFrame.new(0, sizeY / 2, zFront - depth / 2),
			color,
			material
		)
		p.CastShadow = false
		return p
	end

	local seats: { { Vector3 } } = {} -- { posicion local del asiento, ...}
	local z = zStart
	local height = 0
	for tier = 1, 2 do
		for row = 1, rowsPerTier do
			height += rowRise
			block("StandRow", height, rowDepth, z, if (tier + row) % 2 == 0 then C.Blue else C.Panel, Enum.Material.Metal)
			table.insert(seats, { Vector3.new(0, height, z - rowDepth / 2) })
			z -= rowDepth
		end
		if tier == 1 then
			-- Pasillo entre pisos (la parte alta de este descansillo es el "segundo piso")
			height += rowRise
			block("StandLanding", height, landing, z, C.Navy, Enum.Material.Concrete)
			z -= landing
		end
	end
	-- Muro trasero y cubierta
	local backDepth = 1
	local back = part(standFolder, "StandBack", Vector3.new(length, 8, backDepth), origin * CFrame.new(0, height + 4, z - backDepth / 2), C.Navy, Enum.Material.Metal)
	back.CastShadow = false
	local roofDepth = math.abs(z - zStart) + 4
	local roof = part(standFolder, "StandRoof", Vector3.new(length + 4, 1, roofDepth), origin * CFrame.new(0, height + 10, zStart - roofDepth / 2 + 2), C.Panel, Enum.Material.Metal)
	roof.CastShadow = true
	for _, x in { -length / 2, 0, length / 2 } do
		part(standFolder, "StandPost", Vector3.new(1.2, height + 10, 1.2), origin * CFrame.new(x, (height + 10) / 2, z - 0.6), C.Panel, Enum.Material.Metal)
	end

	-- Maniquies repartidos por la grada (no en todos los asientos)
	local mannequins = Instance.new("Folder")
	mannequins.Name = "Mannequins"
	mannequins.Parent = standFolder
	local rng = Random.new(77)
	local facing = origin:VectorToWorldSpace(Vector3.new(0, 0, 1))
	for _, seat in seats do
		local base = seat[1]
		for x = -length / 2 + 2, length / 2 - 2, 2.4 do
			if shouldSeat(rng, 0.22) then
				addMannequin(mannequins, origin:PointToWorldSpace(Vector3.new(x, base.Y, base.Z)), facing, rowRise, rng)
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

local function animate(ball: BasePart, ballRing: BasePart, portalRing: BasePart, portalBeam: BasePart, spawnRing: BasePart)
	local ballHome = ball.CFrame
	local ringHome = ballRing.CFrame
	local portalHome = portalRing.CFrame
	local beamHome = portalBeam.CFrame
	local spawnHome = spawnRing.CFrame
	local t = 0
	RunService.Heartbeat:Connect(function(dt: number)
		t += dt
		local bob = Vector3.new(0, math.sin(t * 1.6) * 0.35, 0)
		ball.CFrame = CFrame.new(ballHome.Position + bob) * CFrame.Angles(0, t * 0.9, 0)
		ballRing.CFrame = CFrame.new(ringHome.Position + bob) * CFrame.Angles(0, t * 0.9, 0) * CFrame.Angles(0, 0, math.rad(90))
		portalRing.CFrame = portalHome * CFrame.Angles(t * 0.8, 0, 0)
		portalBeam.CFrame = beamHome * CFrame.Angles(t * -0.5, 0, 0)
		portalBeam.Transparency = 0.78 + math.sin(t * 2.4) * 0.06
		spawnRing.Transparency = 0.3 + (math.sin(t * 2) + 1) * 0.15
		spawnRing.CFrame = spawnHome
	end)
end

local function decorate(model: Model, ball: BasePart, ballRing: BasePart)
	setupLighting()
	addBoundaries(model)
	addMannequins(model)
	addExhibitionField(model)
	local ring, beam = addMatchPortal(model)
	local spawnRing = model:FindFirstChild("SpawnRing") :: BasePart
	animate(ball, ballRing, ring, beam, spawnRing)
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
			part(model, "TurfStripe", Vector3.new(6, 0.04, 41.5), CFrame.new(BASE + Vector3.new(i * 6.5, 0.77, 0)), C.DarkGrass, Enum.Material.Grass)
		end
	end

	-- Líneas de campo estilizadas, solo decorativas.
	neon(model, "CenterLine", Vector3.new(0.18, 0.05, 41), CFrame.new(BASE + Vector3.new(0, 0.81, 0)), C.White)
	local centerCircle = part(model, "CenterCircle", Vector3.new(0.06, 12, 12), CFrame.new(BASE + Vector3.new(0, 0.86, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Cyan, Enum.Material.Neon, 0.35)
	centerCircle.Shape = Enum.PartType.Cylinder
	centerCircle.CanCollide = false

	-- Acceso monumental al fondo del lobby (lado Z positivo).
	for _, x in { -25, 25 } do
		part(model, "GatePillar", Vector3.new(5, 24, 5), CFrame.new(BASE + Vector3.new(x, 12, 43)), C.Panel, Enum.Material.Metal)
		neon(model, "PillarLight", Vector3.new(0.35, 21, 0.25), CFrame.new(BASE + Vector3.new(x - 2.58, 12, 40.4)), C.Cyan)
	end

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

	-- Paneles laterales de bienvenida para dar escala al espacio.
	for _, x in { -54, 54 } do
		local panel = part(model, "WelcomePanel", Vector3.new(0.8, 11, 19), CFrame.new(BASE + Vector3.new(x, 8, 4)), C.Navy, Enum.Material.Metal)
		panel.CanCollide = false
		makeSign(model, panel, x < 0 and "PLAY" or "RANK UP", x < 0 and "MATCHES START HERE" or "BUILD YOUR TEAM")
		neon(model, "PanelEdge", Vector3.new(0.18, 10.4, 0.18), CFrame.new(BASE + Vector3.new(x + (x < 0 and 0.48 or -0.48), 8, 4)), C.Blue)
	end

	-- Banderas verticales en la entrada.
	for _, x in { -34, -17, 17, 34 } do
		local banner = part(model, "StadiumBanner", Vector3.new(0.25, 9, 4.5), CFrame.new(BASE + Vector3.new(x, 15, 34)), x % 2 == 0 and C.Blue or C.Panel, Enum.Material.SmoothPlastic)
		banner.CanCollide = false
		neon(model, "BannerStripe", Vector3.new(0.3, 0.35, 4.6), CFrame.new(BASE + Vector3.new(x, 15, 34)), C.Cyan)
	end

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
	local spawnRing = part(model, "SpawnRing", Vector3.new(0.08, 6.5, 6.5), CFrame.new(spawnPos + Vector3.new(0, 0.32, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Blue, Enum.Material.Neon, 0.3)
	spawnRing.Shape = Enum.PartType.Cylinder
	spawnRing.CanCollide = false

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
