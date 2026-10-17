--!strict
-- Lobby de FutbolGacha: entrada de estadio moderna, construida por codigo.
-- El lobby vive en el origen; los partidos se generan a 500 studs de altura.

local SpawnService = {}

local ROOT_NAME = "FutbolGachaLobby"
local BASE = Vector3.new(0, 0, 0)

local C = {
	Navy = Color3.fromRGB(9, 18, 38),
	Panel = Color3.fromRGB(17, 34, 62),
	Blue = Color3.fromRGB(35, 145, 255),
	Cyan = Color3.fromRGB(75, 225, 255),
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
	local centerCircle = part(model, "CenterCircle", Vector3.new(12, 0.06, 12), CFrame.new(BASE + Vector3.new(0, 0.86, 0)), C.Cyan, Enum.Material.Neon, 0.18)
	centerCircle.Shape = Enum.PartType.Cylinder
	centerCircle.CFrame = CFrame.new(BASE + Vector3.new(0, 0.86, 0)) * CFrame.Angles(0, 0, math.rad(90))
	centerCircle.CanCollide = false
	centerCircle.Transparency = 0.75

	-- Acceso monumental al fondo del lobby (lado Z positivo).
	for _, x in { -25, 25 } do
		part(model, "GatePillar", Vector3.new(5, 24, 5), CFrame.new(BASE + Vector3.new(x, 12, 43)), C.Panel, Enum.Material.Metal)
		neon(model, "PillarLight", Vector3.new(0.35, 21, 0.25), CFrame.new(BASE + Vector3.new(x - 2.58, 12, 40.4)), C.Cyan)
	end
	part(model, "GateHeader", Vector3.new(55, 4, 7), CFrame.new(BASE + Vector3.new(0, 23, 43)), C.Navy, Enum.Material.Metal)
	neon(model, "GateHeaderLight", Vector3.new(48, 0.35, 0.25), CFrame.new(BASE + Vector3.new(0, 20.8, 39.35)), C.Blue)

	local sign = part(model, "MainSign", Vector3.new(38, 10, 0.8), CFrame.new(BASE + Vector3.new(0, 22, 39)), C.Navy, Enum.Material.Metal)
	sign.CanCollide = false
	makeSign(model, sign, "FUTBOL GACHA", "ENTRA AL CAMPO  •  JUEGA  •  CONVIÉRTETE EN LEYENDA")

	-- Laterales arquitectónicos con iluminación azul.
	for _, z in { -28, 28 } do
		part(model, "SideWall", Vector3.new(112, 12, 2), CFrame.new(BASE + Vector3.new(0, 6, z)), C.Navy, Enum.Material.Metal)
		neon(model, "SideLight", Vector3.new(105, 0.3, 0.25), CFrame.new(BASE + Vector3.new(0, 11.8, z - (z > 0 and 1.15 or -1.15))), C.Blue)
	end

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
			light.Color = C.Cyan
			light.Brightness = 1.8
			light.Range = 38
			light.Shadows = true
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

	-- Spawn discreto centrado; el personaje aparece mirando hacia la entrada.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(8, 0.5, 8)
	spawn.CFrame = CFrame.new(BASE + Vector3.new(0, 1.05, -7))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = true
	spawn.Parent = model

	-- Balón decorativo sobre un pedestal al lado de la entrada.
	local pedestal = part(model, "BallPedestal", Vector3.new(5, 1.2, 5), CFrame.new(BASE + Vector3.new(36, 1.1, 35)), C.Panel, Enum.Material.Metal)
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.CFrame = CFrame.new(BASE + Vector3.new(36, 1.1, 35)) * CFrame.Angles(0, 0, math.rad(90))
	local ball = part(model, "LobbyBall", Vector3.new(3.2, 3.2, 3.2), CFrame.new(BASE + Vector3.new(36, 3.3, 35)), C.White, Enum.Material.SmoothPlastic)
	ball.Shape = Enum.PartType.Ball
	ball.CanCollide = false
	local ballStripe = neon(model, "BallAccent", Vector3.new(3.3, 0.16, 0.16), CFrame.new(BASE + Vector3.new(36, 3.3, 35)) * CFrame.Angles(0, 0, math.rad(35)), C.Blue)
	ballStripe.Shape = Enum.PartType.Cylinder
	ballStripe.CFrame = CFrame.new(BASE + Vector3.new(36, 3.3, 35)) * CFrame.Angles(math.rad(90), 0, math.rad(35))
	ballStripe.CanCollide = false

	model:SetAttribute("LobbySpawnReady", true)
end

function SpawnService.start()
	buildLobby()
	print("[SpawnService] Lobby de estadio FutbolGacha creado")
end

return SpawnService
