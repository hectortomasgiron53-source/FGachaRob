--!strict
--[[
	FarmService: las granjas de brainrots (repartidas en un anillo alrededor del spawn, lejos unas de otras) y los robos.
	- Hay Economy.Farm.Plots granjas por servidor. Al entrar se te asigna una libre; al salir queda libre.
	- Cada granja tiene Economy.Farm.Slots pedestales. Los brainrots colocados te dan monedas cada segundo.
	- En tu granja: "Ver" en un pedestal con brainrot (abre tu inventario con el) y "Colocar" en un pedestal vacio
	  (pone ahi tu mejor brainrot sin colocar). El anillo de cada pedestal tiene el color de la calidad del brainrot.
	- Robar: en la granja de otro, mantén el aviso "Robar" junto a un pedestal. Te lo llevas sobre la cabeza (vas mas
	  lento y brillas en rojo para que su dueno te encuentre) y tienes Economy.Farm.StealSeconds para llegar a TU granja.
	  Si el dueno te toca, se le devuelve.
	- Defensa: el boton rojo de tu granja la bloquea un rato (laser en la entrada: echa a los intrusos). Al entrar al
	  servidor tu granja esta protegida un rato. Al entrar a un partido se bloquea sola; si ya estaba bloqueada, ese
	  bloqueo se congela mientras juegas y al volver te queda la mitad de lo que te quedaba (Economy.Farm).
	- El spawn es el centro del mapa: de el salen caminos de piedra (con farolas) hasta cada granja. Tablero
	  "TOP GRANJAS" en el lobby; cartel de cada granja con la cara de su dueno y un letrero que se ve de lejos.
]]
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local BrainrotModel = require(ReplicatedStorage.Shared.Util.BrainrotModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local CollisionSetup = require(script.Parent.CollisionSetup)

local FarmService = {}

local NotifyEvent = Remotes.get("Notify")
local F = Economy.Farm

-- Disposicion: avenida a lo largo de +X desde el borde este del lobby (x = 77); granjas a ambos lados.
local PLOT_W = 64 -- ancho
local PLOT_D = 52 -- fondo
local PEDESTAL_GAP = 11.5 -- separacion entre pedestales (los brainrots evolucionados son grandes)
local ROW_Z = { -2, 14 } -- filas de pedestales (local, hacia el fondo)
local WORLD_HALF = 380 -- el suelo del mapa va de -380 a 380 (barreras invisibles en el borde)
local SPREAD_DEGREES = 270 -- las granjas ocupan este arco alrededor del spawn (el hueco, al oeste: campo de exhibicion)
local WALL_H = 5
local STONE_H = 2 -- parte baja de piedra del muro (encima va la valla de madera)
local GATE_W = 14
local LEADERBOARD_ROWS = 8

local C = {
	Navy = Color3.fromRGB(9, 18, 38),
	Panel = Color3.fromRGB(17, 34, 62),
	Ground = Color3.fromRGB(52, 58, 72),
	Path = Color3.fromRGB(40, 48, 66),
	Cyan = Color3.fromRGB(104, 168, 196),
	White = Color3.fromRGB(235, 245, 255),
	Red = Color3.fromRGB(235, 60, 60),
	Green = Color3.fromRGB(80, 200, 110),
	Gold = Color3.fromRGB(255, 194, 74),
	Grey = Color3.fromRGB(120, 128, 140),
	Grass = Color3.fromRGB(78, 142, 74),
	GrassDark = Color3.fromRGB(58, 116, 60),
	Leaves = Color3.fromRGB(64, 150, 70),
	LeavesDark = Color3.fromRGB(46, 120, 58),
	Stone = Color3.fromRGB(150, 152, 160),
	StoneDark = Color3.fromRGB(96, 100, 110),
	Marble = Color3.fromRGB(228, 230, 236),
	Wood = Color3.fromRGB(132, 92, 60),
	WoodDark = Color3.fromRGB(96, 66, 44),
	Water = Color3.fromRGB(70, 160, 225),
	Lamp = Color3.fromRGB(255, 226, 170),
	EmptyRing = Color3.fromRGB(70, 78, 92),
}
-- Color propio de cada granja (banderines, arco de la puerta, cartel)
local PLOT_COLORS = {
	Color3.fromRGB(70, 160, 90),
	Color3.fromRGB(70, 120, 210),
	Color3.fromRGB(210, 120, 60),
	Color3.fromRGB(150, 90, 200),
	Color3.fromRGB(50, 170, 170),
	Color3.fromRGB(220, 180, 50),
	Color3.fromRGB(200, 70, 90),
	Color3.fromRGB(130, 140, 160),
}

type Shown = { Uid: string, Id: string, Level: number, Variant: string, Model: Model }
type Plot = {
	Index: number,
	CFrame: CFrame, -- centro del suelo; -Z local = entrada (mira a la avenida)
	Model: Model,
	Pedestals: { Part },
	Rings: { Part },
	Doors: { BasePart }, -- paredes de la jaula de laser que chocan (con la granja bloqueada)
	CageOn: boolean,
	Sign: TextLabel,
	Status: TextLabel,
	IncomeLabel: TextLabel,
	Avatar: ImageLabel,
	ArchLabel: TextLabel,
	Pad: Part,
	PadLabel: TextLabel,
	Owner: Player?,
	Shown: { [number]: Shown },
	LockedUntil: number,
	LockReadyAt: number,
	ShieldUntil: number,
	MatchLocked: boolean, -- bloqueada porque su dueno esta jugando un partido
	PausedLock: number, -- segundos de bloqueo que le quedaban al entrar al partido (congelados)
	Tag: TextLabel, -- letrero sobre la granja que se ve desde lejos
}
type Carry = {
	Thief: Player,
	Owner: Player,
	Slot: number,
	Uid: string,
	Id: string,
	Level: number,
	Variant: string,
	Started: number,
	Model: Model,
	WalkSpeed: number,
	Highlight: Highlight,
}

local plots: { Plot } = {}

local plotOf: { [Player]: Plot } = {}
local carries: { [Player]: Carry } = {} -- por ladron
local folder: Model
local leaderRows: { { Name: TextLabel, Income: TextLabel } } = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Pieza decorativa: no choca ni la ven los rayos ni los toques (mas barata para la fisica)
local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Cilindro vertical (los cilindros de Roblox van a lo largo de X: se tumban 90 grados)
local function cylinder(parent: Instance, name: string, height: number, diameter: number, position: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), position * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, diameter: number, position: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), position, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function notify(player: Player, kind: string, text: string)
	NotifyEvent:FireClient(player, kind, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function inMatch(player: Player): boolean
	local id = player:GetAttribute("MatchId")
	return id ~= nil and id ~= 0 -- el 0 es el patio de juegos del lobby
end

local function inside(plot: Plot, position: Vector3, margin: number): boolean
	local p = plot.CFrame:PointToObjectSpace(position)
	return math.abs(p.X) < PLOT_W / 2 + margin and math.abs(p.Z) < PLOT_D / 2 + margin and p.Y > -6 and p.Y < 25
end

local function pedestalTop(plot: Plot, slot: number): CFrame
	local pedestal = plot.Pedestals[slot]
	local top = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2, 0) -- cilindro tumbado: su "alto" es Size.X
	return CFrame.new(top) * plot.CFrame.Rotation
end

local function surfaceGui(adornee: BasePart, face: Enum.NormalId, pixels: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = 0
	gui.MaxDistance = 220 -- de lejos no se dibuja (ahorra en ordenadores y moviles modestos)
	gui.Parent = adornee
	return gui
end

local function textLabel(parent: Instance, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = text or ""
	l.Parent = parent
	return l
end

-- ---------------------------------------------------------------------------
-- Construccion
-- ---------------------------------------------------------------------------

-- Cartel del fondo de la granja: cara del dueno a la izquierda; nombre, estado e ingresos a la derecha
local function makeSign(adornee: BasePart, accent: Color3): (TextLabel, TextLabel, TextLabel, ImageLabel)
	local gui = surfaceGui(adornee, Enum.NormalId.Front, 25)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = C.Navy
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(1, 0, 0.06, 0)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	stripe.Parent = frame
	local avatar = Instance.new("ImageLabel")
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.fromScale(0.025, 0.55)
	avatar.Size = UDim2.fromScale(0.75, 0.75)
	avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
	avatar.BackgroundColor3 = C.Panel
	avatar.Image = ""
	avatar.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = avatar
	local title = textLabel(frame, UDim2.fromScale(0.27, 0.1), UDim2.fromScale(0.7, 0.38), Enum.Font.GothamBlack, C.White)
	local status = textLabel(frame, UDim2.fromScale(0.27, 0.52), UDim2.fromScale(0.7, 0.2), Enum.Font.GothamBold, C.Cyan)
	local income = textLabel(frame, UDim2.fromScale(0.27, 0.74), UDim2.fromScale(0.7, 0.2), Enum.Font.GothamMedium, C.Gold)
	return title, status, income, avatar
end

-- Arbol sencillo (tronco + dos copas). Las copas no chocan.
local function tree(parent: Instance, base: Vector3, scale: number)
	cylinder(parent, "TreeTrunk", 7 * scale, 1.3 * scale, CFrame.new(base + Vector3.new(0, 3.5 * scale, 0)), C.WoodDark, Enum.Material.Wood)
	decor(ball(parent, "TreeLeaves", 6.5 * scale, CFrame.new(base + Vector3.new(0, 8 * scale, 0)), C.Leaves, Enum.Material.Grass))
	decor(ball(parent, "TreeLeaves", 4.5 * scale, CFrame.new(base + Vector3.new(0.9 * scale, 10.3 * scale, 0.6 * scale)), C.LeavesDark, Enum.Material.Grass))
end

-- Tramo de muro: base de piedra + valla de madera encima
local function wall(parent: Instance, length: number, cf: CFrame)
	part(parent, "WallStone", Vector3.new(length, STONE_H, 1.6), cf * CFrame.new(0, STONE_H / 2, 0), C.Stone, Enum.Material.Cobblestone)
	part(parent, "WallFence", Vector3.new(length, WALL_H - STONE_H, 0.5), cf * CFrame.new(0, STONE_H + (WALL_H - STONE_H) / 2, 0), C.Wood, Enum.Material.WoodPlanks)
	decor(part(parent, "WallRail", Vector3.new(length, 0.35, 0.8), cf * CFrame.new(0, WALL_H + 0.1, 0), C.WoodDark, Enum.Material.Wood))
end

-- Angulo (alrededor del spawn) de cada granja: repartidas en SPREAD_DEGREES dejando libre el oeste (campo de
-- exhibicion). Con 8 granjas quedan a unos 170 studs unas de otras.
local function plotAngle(index: number): number
	local count = math.max(F.Plots, 2)
	return math.rad(-SPREAD_DEGREES / 2 + (index - 1) * SPREAD_DEGREES / (count - 1))
end

-- ---------------------------------------------------------------------------
-- Jaula de laser: con la granja bloqueada la rodean paredes de laser (los 4 lados y el techo). Choca con todos menos
-- con su dueno (grupos de colision FarmCage<n> / FarmOwner<n>), asi nadie puede entrar ni saltando el muro.
-- Lo que se ve (barras, postes, campo de fuerza, borde del techo y un "escaner" que sube y baja) lo anima cada
-- cliente (FarmController) segun el atributo "Locked" de la granja: el servidor no manda nada por la red cada frame.
-- ---------------------------------------------------------------------------
local CAGE_H = 16

local function cageGroup(index: number): string
	return `FarmCage{index}`
end
local function ownerGroup(index: number): string
	return `FarmOwner{index}`
end

-- Devuelve las paredes que chocan (empiezan sin chocar: la granja no esta bloqueada)
local function buildCage(model: Model, cf: CFrame, index: number): { BasePart }
	local cage = Instance.new("Folder")
	cage.Name = "Cage"
	cage.Parent = model
	local colliders: { BasePart } = {}
	local hw, hd = PLOT_W / 2 + 1, PLOT_D / 2 + 1 -- justo por fuera de los muros
	local pink = Color3.fromRGB(255, 90, 160)
	local hot = Color3.fromRGB(255, 225, 230)
	local function laser(name: string, size: Vector3, offset: CFrame, kind: string, color: Color3, material: Enum.Material?): BasePart
		local p = decor(part(cage, name, size, cf * offset, color, material or Enum.Material.Neon))
		p.Transparency = 1
		p.CastShadow = false
		p:SetAttribute("LaserKind", kind)
		p:SetAttribute("CageHeight", CAGE_H)
		CollectionService:AddTag(p, "FarmLaser")
		return p
	end
	local function collider(size: Vector3, offset: CFrame)
		local wall = part(cage, "CageWall", size, cf * offset, C.Red)
		wall.Transparency = 1
		wall.CanCollide = false
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.CollisionGroup = cageGroup(index)
		table.insert(colliders, wall)
	end
	local sides = {
		{ CFrame.new(0, 0, -hd), hw * 2 }, -- frente (con la puerta)
		{ CFrame.new(0, 0, hd), hw * 2 }, -- fondo
		{ CFrame.new(-hw, 0, 0) * CFrame.Angles(0, math.rad(90), 0), hd * 2 },
		{ CFrame.new(hw, 0, 0) * CFrame.Angles(0, math.rad(90), 0), hd * 2 },
	}
	for _, side in sides do
		local base: CFrame, length: number = side[1], side[2]
		collider(Vector3.new(length, CAGE_H, 1), base * CFrame.new(0, CAGE_H / 2, 0))
		laser("CageField", Vector3.new(length, CAGE_H, 0.15), base * CFrame.new(0, CAGE_H / 2, 0), "Field", C.Red, Enum.Material.ForceField)
		local n = 0
		for y = 1.2, CAGE_H - 0.6, 1.8 do
			n += 1
			laser("CageBar", Vector3.new(length, 0.18, 0.18), base * CFrame.new(0, y, 0), "Bar", if n % 2 == 0 then pink else C.Red)
		end
		laser("CageScan", Vector3.new(length, 0.35, 0.35), base * CFrame.new(0, 1, 0), "Scan", hot)
	end
	for _, sx in { -hw, hw } do
		for _, sz in { -hd, hd } do
			laser("CagePost", Vector3.new(0.7, CAGE_H, 0.7), CFrame.new(sx, CAGE_H / 2, sz), "Post", hot)
		end
	end
	-- Techo: pared que choca, campo de fuerza, borde y dos diagonales
	collider(Vector3.new(hw * 2, 1, hd * 2), CFrame.new(0, CAGE_H + 0.5, 0))
	laser("CageRoof", Vector3.new(hw * 2, 0.15, hd * 2), CFrame.new(0, CAGE_H, 0), "Field", C.Red, Enum.Material.ForceField)
	for _, sz in { -hd, hd } do
		laser("CageEdge", Vector3.new(hw * 2, 0.35, 0.35), CFrame.new(0, CAGE_H, sz), "Post", pink)
	end
	for _, sx in { -hw, hw } do
		laser("CageEdge", Vector3.new(0.35, 0.35, hd * 2), CFrame.new(sx, CAGE_H, 0), "Post", pink)
	end
	local diagonal = math.sqrt((hw * 2) ^ 2 + (hd * 2) ^ 2)
	for _, sign in { -1, 1 } do
		laser("CageBar", Vector3.new(diagonal, 0.18, 0.18), CFrame.new(0, CAGE_H, 0) * CFrame.Angles(0, sign * math.atan2(hd * 2, hw * 2), 0), "Bar", C.Red)
	end
	return colliders
end

-- Enciende / apaga la jaula (solo cuando cambia: asi no se manda nada por la red sin motivo)
local function setCage(plot: any, on: boolean)
	if plot.CageOn == on then
		return
	end
	plot.CageOn = on
	for _, wall in plot.Doors do
		wall.CanCollide = on
	end
	plot.Model:SetAttribute("Locked", on)
end

-- Grupos de colision: la jaula de cada granja no choca con su dueno (ni el dueno con la barrera del balon del campo de
-- exhibicion, que solo debe frenar el balon)
local function setupCageGroups()
	CollisionSetup.setup()
	for index = 1, F.Plots do
		for _, name in { cageGroup(index), ownerGroup(index) } do
			pcall(function()
				PhysicsService:RegisterCollisionGroup(name)
			end)
		end
		PhysicsService:CollisionGroupSetCollidable(cageGroup(index), ownerGroup(index), false)
		PhysicsService:CollisionGroupSetCollidable(cageGroup(index), CollisionSetup.BALL, false)
		PhysicsService:CollisionGroupSetCollidable(ownerGroup(index), CollisionSetup.BALL_ONLY, false)
	end
end

-- El personaje del dueno va en el grupo FarmOwner<n> (solo las piezas "normales": en un partido manda el partido)
local ownerConnections: { [Player]: { RBXScriptConnection } } = {}
local function paintOwner(player: Player, index: number)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.CollisionGroup == "Default" then
			d.CollisionGroup = ownerGroup(index)
		end
	end
end
local function trackOwner(player: Player, index: number)
	local connections: { RBXScriptConnection } = {}
	local function hook(character: Model)
		paintOwner(player, index)
		table.insert(connections, character.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and d.CollisionGroup == "Default" then
				d.CollisionGroup = ownerGroup(index)
			end
		end))
	end
	if player.Character then
		hook(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(hook))
	-- Al volver de un partido o del patio de juegos el personaje vuelve al grupo normal: se vuelve a pintar
	table.insert(connections, player:GetAttributeChangedSignal("MatchId"):Connect(function()
		if player:GetAttribute("MatchId") == nil then
			task.delay(0.3, paintOwner, player, index)
		end
	end))
	ownerConnections[player] = connections
end
local function untrackOwner(player: Player)
	local connections = ownerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		ownerConnections[player] = nil
	end
end

local function buildPlot(index: number): Plot
	local angle = plotAngle(index)
	local center = Vector3.new(math.cos(angle) * F.RingRadius, 0, math.sin(angle) * F.RingRadius)
	local cf = CFrame.lookAt(center, Vector3.new(0, 0, 0)) -- la entrada (-Z local) mira al spawn
	local accent = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]

	local model = Instance.new("Model")
	model.Name = `Granja_{index}`
	model:SetAttribute("PlotIndex", index)
	-- Punto justo dentro de la puerta: el ladron ve una guia hasta aqui (FarmController)
	model:SetAttribute("Home", (cf * CFrame.new(0, 2, -PLOT_D / 2 + 4)).Position)
	model.Parent = folder

	-- Suelo de cesped, camino de piedra desde la puerta y plaza de los pedestales
	part(model, "Floor", Vector3.new(PLOT_W, 1, PLOT_D), cf * CFrame.new(0, -0.5, 0), C.Grass, Enum.Material.Grass)
	local plazaFront, plazaBack = ROW_Z[1] - 4.5, ROW_Z[2] + 4.5
	local pathLength = plazaFront + PLOT_D / 2
	decor(part(model, "FloorPath", Vector3.new(6, 0.1, pathLength), cf * CFrame.new(0, 0.05, -PLOT_D / 2 + pathLength / 2), C.StoneDark, Enum.Material.Slate))
	decor(part(model, "FloorPlaza", Vector3.new(PLOT_W - 4, 0.1, plazaBack - plazaFront), cf * CFrame.new(0, 0.05, (plazaFront + plazaBack) / 2), C.Stone, Enum.Material.Concrete))

	-- Muros: fondo, lados y frente con puerta (piedra + valla), con pilares en las esquinas
	wall(model, PLOT_W, cf * CFrame.new(0, 0, PLOT_D / 2))
	for _, side in { -1, 1 } do
		wall(model, PLOT_D, cf * CFrame.new(side * PLOT_W / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
		local segment = (PLOT_W - GATE_W) / 2
		wall(model, segment, cf * CFrame.new(side * (GATE_W / 2 + segment / 2), 0, -PLOT_D / 2))
		for _, zSide in { -1, 1 } do
			part(model, "CornerPost", Vector3.new(2, WALL_H + 0.8, 2), cf * CFrame.new(side * PLOT_W / 2, (WALL_H + 0.8) / 2, zSide * PLOT_D / 2), C.StoneDark, Enum.Material.Cobblestone)
		end
		-- Postes de la puerta con farolillo del color de la granja
		part(model, "GatePost", Vector3.new(2, 7.4, 2), cf * CFrame.new(side * GATE_W / 2, 3.7, -PLOT_D / 2), C.StoneDark, Enum.Material.Cobblestone)
		decor(part(model, "GateLantern", Vector3.new(1.1, 1.1, 1.1), cf * CFrame.new(side * (GATE_W / 2 + 0.4), 9.85, -PLOT_D / 2), accent, Enum.Material.Neon))
	end
	-- Arco de la puerta con el nombre del dueno (mira a la avenida)
	local arch = part(model, "GateArch", Vector3.new(GATE_W + 2, 1.8, 1.2), cf * CFrame.new(0, 8.4, -PLOT_D / 2), accent, Enum.Material.SmoothPlastic)
	decor(arch)
	local archGui = surfaceGui(arch, Enum.NormalId.Front, 30)
	local archLabel = textLabel(archGui, UDim2.fromScale(0.02, 0.08), UDim2.fromScale(0.96, 0.84), Enum.Font.GothamBlack, C.White, "GRANJA LIBRE")
	archLabel.TextStrokeTransparency = 0.4

	-- Jaula de laser (solo se ve y solo choca con la granja bloqueada; el dueno la atraviesa)
	local doors = buildCage(model, cf, index)

	-- Cartel del fondo (con la cara del dueno)
	local signPart = part(model, "Sign", Vector3.new(26, 7, 0.6), cf * CFrame.new(0, WALL_H + 5.5, PLOT_D / 2 - 0.2), C.Navy, Enum.Material.Metal)
	decor(signPart)
	local title, status, income, avatar = makeSign(signPart, accent)
	-- Letrero flotante que se ve desde lejos (asi desde el spawn sabes cual es cada granja)
	local tagGui = Instance.new("BillboardGui")
	tagGui.Name = "FarmTag"
	tagGui.Size = UDim2.fromOffset(280, 46)
	tagGui.StudsOffset = Vector3.new(0, 10, 0)
	tagGui.MaxDistance = 700
	tagGui.LightInfluence = 0
	tagGui.Adornee = signPart
	tagGui.Parent = signPart
	local tag = textLabel(tagGui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.Font.GothamBlack, accent, "GRANJA LIBRE")
	tag.TextStrokeTransparency = 0.2
	tag.TextStrokeColor3 = C.Navy
	for _, side in { -1, 1 } do
		part(model, "SignPole", Vector3.new(0.6, WALL_H + 5, 0.6), cf * CFrame.new(side * 11, (WALL_H + 5) / 2, PLOT_D / 2 + 0.2), C.Panel, Enum.Material.Metal)
	end

	-- Arboles en las esquinas del fondo
	for _, side in { -1, 1 } do
		tree(model, (cf * CFrame.new(side * (PLOT_W / 2 - 4.5), 0, PLOT_D / 2 - 4.5)).Position, 0.9)
	end

	-- Pedestales: 2 filas de 5 (base de piedra, pedestal de marmol y anillo de luz del color de la calidad)
	local pedestals: { Part } = {}
	local rings: { Part } = {}
	local cols = math.ceil(F.Slots / 2)
	for slot = 1, F.Slots do
		local row = if slot <= cols then 0 else 1
		local col = (slot - 1) % cols
		local px = (col - (cols - 1) / 2) * PEDESTAL_GAP
		local pz = ROW_Z[row + 1]
		decor(cylinder(model, "PedestalBase", 0.5, 7.2, cf * CFrame.new(px, 0.25, pz), C.StoneDark, Enum.Material.Slate))
		local pedestal = cylinder(model, `Pedestal_{slot}`, 1.4, 6, cf * CFrame.new(px, 0.7, pz), C.Marble, Enum.Material.Marble)
		pedestal:SetAttribute("Slot", slot)
		pedestal:SetAttribute("PlotIndex", index)
		local ring = decor(cylinder(model, "PedestalRing", 0.2, 6.3, cf * CFrame.new(px, 1.35, pz), C.EmptyRing, Enum.Material.SmoothPlastic)) :: Part
		-- Avisos: "Robar" (para los demas), "Ver" y "Colocar" (para el dueno). El cliente ensena solo el que toca.
		local steal = Instance.new("ProximityPrompt")
		steal.Name = "StealPrompt"
		steal.ActionText = "Robar"
		steal.ObjectText = ""
		steal.HoldDuration = F.StealHoldSeconds
		steal.MaxActivationDistance = 9
		steal.RequiresLineOfSight = false
		steal.Parent = pedestal
		local manage = Instance.new("ProximityPrompt")
		manage.Name = "ManagePrompt"
		manage.ActionText = "Ver"
		manage.ObjectText = ""
		manage.HoldDuration = 0
		manage.MaxActivationDistance = 9
		manage.RequiresLineOfSight = false
		manage.Parent = pedestal
		local place = Instance.new("ProximityPrompt")
		place.Name = "PlacePrompt"
		place.ActionText = "Colocar"
		place.ObjectText = "Pedestal vacío"
		place.HoldDuration = 0
		place.MaxActivationDistance = 9
		place.RequiresLineOfSight = false
		place.Enabled = false
		place.Parent = pedestal
		pedestals[slot] = pedestal
		rings[slot] = ring
	end

	-- Boton de bloqueo (dentro, junto a la entrada)
	local pad = part(model, "LockPad", Vector3.new(6, 0.4, 6), cf * CFrame.new(-PLOT_W / 2 + 6, 0.2, -PLOT_D / 2 + 6), C.Red, Enum.Material.Neon)
	pad.CanCollide = false
	local padGui = surfaceGui(pad, Enum.NormalId.Top, 30)
	local padText = textLabel(padGui, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.9), Enum.Font.GothamBlack, C.White, "BLOQUEAR")

	local plot: Plot = {
		Index = index,
		CFrame = cf,
		Model = model,
		Pedestals = pedestals,
		Rings = rings,
		Doors = doors,
		CageOn = false,
		Sign = title,
		Status = status,
		IncomeLabel = income,
		Avatar = avatar,
		ArchLabel = archLabel,
		Pad = pad,
		PadLabel = padText,
		Owner = nil,
		Shown = {},
		LockedUntil = 0,
		LockReadyAt = 0,
		ShieldUntil = 0,
		MatchLocked = false,
		PausedLock = 0,
		Tag = tag,
	}
	title.Text = "GRANJA LIBRE"
	status.Text = "Entra al servidor para tener la tuya"

	local lastPadMessage = 0
	pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if not player or player ~= plot.Owner then
			return
		end
		if plot.MatchLocked then
			return
		end
		local now = os.clock()
		if now < plot.LockedUntil then
			return
		end
		if now < plot.LockReadyAt then
			if now - lastPadMessage > 3 then
				lastPadMessage = now
				notify(player, "Info", `Podras bloquear otra vez en {math.ceil(plot.LockReadyAt - now)} s`)
			end
			return
		end
		plot.LockedUntil = now + F.LockSeconds
		plot.LockReadyAt = plot.LockedUntil + F.LockCooldown
		notify(player, "Info", `Granja bloqueada {F.LockSeconds} s`)
	end)
	return plot
end

-- Farola de la avenida
local function lamp(parent: Instance, base: Vector3)
	cylinder(parent, "LampPole", 9, 0.5, CFrame.new(base + Vector3.new(0, 4.5, 0)), C.Panel, Enum.Material.Metal)
	decor(cylinder(parent, "LampCap", 0.4, 1.8, CFrame.new(base + Vector3.new(0, 9.9, 0)), C.Panel, Enum.Material.Metal))
	decor(ball(parent, "LampBulb", 1.5, CFrame.new(base + Vector3.new(0, 9.3, 0)), C.Lamp, Enum.Material.Neon))
end

-- Fuente al final de la avenida
local function fountain(parent: Instance, position: Vector3)
	cylinder(parent, "FountainBasin", 1.6, 13, CFrame.new(position + Vector3.new(0, 0.3, 0)), C.Stone, Enum.Material.Cobblestone)
	local water = decor(cylinder(parent, "FountainWater", 0.2, 11.6, CFrame.new(position + Vector3.new(0, 1.05, 0)), C.Water, Enum.Material.Glass))
	water.Transparency = 0.25
	cylinder(parent, "FountainColumn", 4, 1.6, CFrame.new(position + Vector3.new(0, 2.5, 0)), C.Marble, Enum.Material.Marble)
	local bowl = cylinder(parent, "FountainBowl", 0.6, 5, CFrame.new(position + Vector3.new(0, 4.6, 0)), C.Marble, Enum.Material.Marble)
	local top = decor(cylinder(parent, "FountainTopWater", 0.15, 4.4, CFrame.new(position + Vector3.new(0, 4.95, 0)), C.Water, Enum.Material.Glass))
	top.Transparency = 0.25
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255), C.Water)
	spray.LightEmission = 0.4
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.15) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Rate = 45
	spray.Speed = NumberRange.new(9, 12)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -26, 0)
	-- El cuenco es un cilindro tumbado: su cara "Right" (+X local) es la de arriba
	spray.EmissionDirection = Enum.NormalId.Right
	spray.Parent = bowl
end

-- Tablero "TOP GRANJAS" (junto al paso desde el lobby, mirando al lobby)
local function leaderboard(parent: Instance, position: Vector3)
	local cf = CFrame.lookAt(position, position + Vector3.new(-1, 0, 0)) -- su cara delantera mira al lobby (-X)
	for _, side in { -1, 1 } do
		part(parent, "BoardPost", Vector3.new(0.8, 12, 0.8), cf * CFrame.new(side * 7.2, -0.5, 0.6), C.Panel, Enum.Material.Metal)
	end
	local board = part(parent, "Leaderboard", Vector3.new(15, 11, 0.6), cf, C.Navy, Enum.Material.Metal)
	decor(board)
	local gui = surfaceGui(board, Enum.NormalId.Front, 30)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = C.Navy
	frame.BorderSizePixel = 0
	frame.Parent = gui
	textLabel(frame, UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.92, 0.13), Enum.Font.GothamBlack, C.Gold, "TOP GRANJAS")
	textLabel(frame, UDim2.fromScale(0.04, 0.15), UDim2.fromScale(0.92, 0.06), Enum.Font.GothamMedium, C.Cyan, "monedas por segundo en este servidor")
	local rowH = 0.76 / LEADERBOARD_ROWS
	for i = 1, LEADERBOARD_ROWS do
		local y = 0.22 + (i - 1) * rowH
		local color = if i == 1 then C.Gold elseif i == 2 then Color3.fromRGB(210, 215, 225) elseif i == 3 then Color3.fromRGB(215, 150, 90) else C.White
		local name = textLabel(frame, UDim2.fromScale(0.05, y + rowH * 0.1), UDim2.fromScale(0.6, rowH * 0.8), Enum.Font.GothamBold, color, "")
		name.TextXAlignment = Enum.TextXAlignment.Left
		local income = textLabel(frame, UDim2.fromScale(0.62, y + rowH * 0.1), UDim2.fromScale(0.33, rowH * 0.8), Enum.Font.GothamBold, C.Gold, "")
		income.TextXAlignment = Enum.TextXAlignment.Right
		leaderRows[i] = { Name = name, Income = income }
	end
end

local function buildArea()
	local old = workspace:FindFirstChild("Granjas")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Granjas"
	model.Parent = workspace
	folder = model
	local decorFolder = Instance.new("Model")
	decorFolder.Name = "Decoracion"
	decorFolder.Parent = model

	-- Suelo de cesped de todo el mapa (un pelin por debajo de la plataforma del lobby: sin parpadeos)
	part(model, "MapGround", Vector3.new(WORLD_HALF * 2, 2, WORLD_HALF * 2), CFrame.new(0, -1.6, 0), C.GrassDark, Enum.Material.Grass)

	-- Caminos de piedra desde el borde del lobby (el spawn es el centro) hasta la puerta de cada granja, con farolas
	local lobbyHalfX, lobbyHalfZ = 75, 60 -- media plataforma del lobby (SpawnService)
	for index = 1, F.Plots do
		local angle = plotAngle(index)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local t0 = math.min(lobbyHalfX / math.max(math.abs(dir.X), 1e-3), lobbyHalfZ / math.max(math.abs(dir.Z), 1e-3))
		local t1 = F.RingRadius - PLOT_D / 2
		local length = t1 - t0
		local mid = dir * ((t0 + t1) / 2) + Vector3.new(0, -0.6, 0)
		decor(part(model, "Path", Vector3.new(10, 0.1, length), CFrame.lookAt(mid, mid + dir), C.Path, Enum.Material.Slate))
		for _, sign in { -1, 1 } do
			decor(part(model, "PathEdge", Vector3.new(0.4, 0.14, length), CFrame.lookAt(mid + side * sign * 5.2, mid + side * sign * 5.2 + dir), C.Stone, Enum.Material.Cobblestone))
			-- Cintas transportadoras: a la derecha la de ida (hacia la granja), a la izquierda la de vuelta (al spawn).
			-- Una pieza anclada con velocidad arrastra a quien la pisa. Las flechas animadas las pone el cliente.
			local laneDir = dir * sign
			local laneMid = mid + side * sign * 2.45 + Vector3.new(0, 0.1, 0)
			local lane = part(model, "Conveyor", Vector3.new(4.3, 0.2, length - 2), CFrame.lookAt(laneMid, laneMid + laneDir), C.Path, Enum.Material.DiamondPlate)
			lane.CanTouch = false
			lane.AssemblyLinearVelocity = laneDir * F.ConveyorSpeed
			lane:SetAttribute("ConveyorSpeed", F.ConveyorSpeed)
			lane:SetAttribute("Outbound", sign == 1)
			CollectionService:AddTag(lane, "FarmConveyor")
		end
		decor(part(model, "ConveyorDivider", Vector3.new(0.5, 0.26, length - 2), CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), mid + Vector3.new(0, 0.1, 0) + dir), C.Gold, Enum.Material.Neon))
		local t = t0 + 20
		while t < t1 - 10 do
			for _, sign in { -1, 1 } do
				lamp(decorFolder, dir * t + side * sign * 7 + Vector3.new(0, -0.6, 0))
			end
			t += 45
		end
		-- Arboles entre esta granja y la siguiente (lejos de los caminos)
		if index < F.Plots then
			local between = (angle + plotAngle(index + 1)) / 2
			local out = Vector3.new(math.cos(between), 0, math.sin(between))
			for k, radius in { F.RingRadius - 40, F.RingRadius, F.RingRadius + 35 } do
				tree(decorFolder, out * radius + Vector3.new(0, -0.6, 0) + Vector3.new(-out.Z, 0, out.X) * (k - 2) * 9, 1 + (k % 2) * 0.2)
			end
		end
	end
	fountain(decorFolder, Vector3.new(30, -0.6, 100))
	leaderboard(decorFolder, Vector3.new(71, 6, 0))

	-- Barreras invisibles en el borde del mapa
	local function barrier(size: Vector3, position: Vector3)
		local wallPart = part(model, "Boundary", size, CFrame.new(position), C.Navy)
		wallPart.Transparency = 1
		wallPart.CanQuery = false
	end
	for _, sign in { -1, 1 } do
		barrier(Vector3.new(WORLD_HALF * 2 + 8, 120, 4), Vector3.new(0, 58, sign * (WORLD_HALF + 2)))
		barrier(Vector3.new(4, 120, WORLD_HALF * 2 + 8), Vector3.new(sign * (WORLD_HALF + 2), 58, 0))
	end

	for index = 1, F.Plots do
		plots[index] = buildPlot(index)
	end
end

-- ---------------------------------------------------------------------------
-- Mostrar los brainrots de una granja
-- ---------------------------------------------------------------------------

local function isStolenSlot(plot: Plot, slot: number): boolean
	for _, carry in carries do
		if plotOf[carry.Owner] == plot and carry.Slot == slot then
			return true
		end
	end
	return false
end

local function makeBillboard(model: Model, height: number, record: { Id: string, Level: number, Variant: string })
	local entry = EconomyMath.entryOf(record.Id)
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(200, 64)
	-- (por encima del halo y los pinchos de las evoluciones)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height * (if EconomyMath.evolutionOf(record.Level) > 0 then 1.3 else 1) + 1.6, 0)
	gui.MaxDistance = 70
	gui.Adornee = model.PrimaryPart :: BasePart
	gui.Parent = model
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.42, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.3
	name.Text = entry.Name
	name.Parent = gui
	local info = Instance.new("TextLabel")
	info.Position = UDim2.fromScale(0, 0.42)
	info.Size = UDim2.new(1, 0, 0.3, 0)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextColor3 = rarity.Color
	info.TextStrokeTransparency = 0.3
	info.Text = `{rarity.Name}{if record.Variant ~= "Normal" then " · " .. variant.Name else ""} · Nv {record.Level}{if EconomyMath.evolutionTag(record.Level) ~= "" then " " .. EconomyMath.evolutionTag(record.Level) else ""}`
	info.Parent = gui
	local income = Instance.new("TextLabel")
	income.Position = UDim2.fromScale(0, 0.72)
	income.Size = UDim2.new(1, 0, 0.28, 0)
	income.BackgroundTransparency = 1
	income.Font = Enum.Font.GothamBold
	income.TextScaled = true
	income.TextColor3 = C.Gold
	income.TextStrokeTransparency = 0.3
	income.Text = `+{EconomyMath.format(EconomyMath.income(record))}/s`
	income.Parent = gui
end

-- "stolen" = el pedestal esta vacio porque se lo estan robando (el dueno no puede colocar otro alli)
local function clearSlot(plot: Plot, slot: number, stolen: boolean?)
	local shown = plot.Shown[slot]
	if shown then
		shown.Model:Destroy()
		plot.Shown[slot] = nil
	end
	local pedestal = plot.Pedestals[slot]
	pedestal:SetAttribute("Uid", nil)
	pedestal:SetAttribute("BrainrotName", nil)
	pedestal:SetAttribute("Income", nil)
	pedestal:SetAttribute("Height", nil)
	pedestal:SetAttribute("BeingStolen", if stolen then true else nil)
	local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt
	steal.ObjectText = ""
	local manage = pedestal:FindFirstChild("ManagePrompt") :: ProximityPrompt
	manage.ObjectText = ""
	local ring = plot.Rings[slot]
	ring.Color = C.EmptyRing
	ring.Material = Enum.Material.SmoothPlastic
end

local function refreshPlot(plot: Plot)
	local owner = plot.Owner
	local data = if owner then DataService.get(owner) else nil
	for slot = 1, F.Slots do
		local uid = if data then data.Farm[tostring(slot)] else nil
		local record = if data and uid then data.Brainrots[uid] else nil
		if not record or isStolenSlot(plot, slot) then
			clearSlot(plot, slot, record ~= nil)
			continue
		end
		local shown = plot.Shown[slot]
		if shown and shown.Uid == uid and shown.Level == record.Level and shown.Variant == record.Variant and shown.Id == record.Id then
			continue
		end
		clearSlot(plot, slot)
		local rarity = EconomyMath.rarityOf(record.Id)
		-- Evolucionado (nivel 50 / 90): otro aspecto y mas grande
		local height = rarity.Height * EconomyMath.evolutionScale(record.Level)
		local model = BrainrotModel.build(record.Id, record.Variant, rarity.Height, EconomyMath.evolutionOf(record.Level))
		local root = model.PrimaryPart :: BasePart
		root.Anchored = true
		local base = pedestalTop(plot, slot)
		model:PivotTo(base)
		model:SetAttribute("BaseCFrame", base)
		makeBillboard(model, height, record)
		model.Parent = plot.Model
		CollectionService:AddTag(model, "FarmBrainrot")
		plot.Shown[slot] = { Uid = uid :: string, Id = record.Id, Level = record.Level, Variant = record.Variant, Model = model }
		local entry = EconomyMath.entryOf(record.Id)
		local pedestal = plot.Pedestals[slot]
		pedestal:SetAttribute("Uid", uid)
		pedestal:SetAttribute("BrainrotName", entry.Name)
		pedestal:SetAttribute("Income", EconomyMath.income(record)) -- para los "+monedas" que ve el dueno
		pedestal:SetAttribute("Height", height)
		local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt
		steal.ObjectText = entry.Name
		local manage = pedestal:FindFirstChild("ManagePrompt") :: ProximityPrompt
		manage.ObjectText = entry.Name
		-- Anillo del color de la calidad (oro / diamante: el de la variante)
		local ring = plot.Rings[slot]
		ring.Color = if record.Variant ~= "Normal" then EconomyMath.variantOf(record.Variant).Color else rarity.Color
		ring.Material = Enum.Material.Neon
	end
end

function FarmService.refresh(player: Player)
	local plot = plotOf[player]
	if plot then
		refreshPlot(plot)
	end
end

-- ---------------------------------------------------------------------------
-- Colocar desde el pedestal
-- ---------------------------------------------------------------------------

-- "Colocar" en un pedestal vacio de tu granja: pone ahi tu brainrot sin colocar que mas monedas da
local function quickPlace(player: Player, plot: Plot, slot: number)
	if plot.Owner ~= player then
		return
	end
	local data = DataService.get(player)
	if not data or data.Farm[tostring(slot)] then
		return
	end
	local bestUid: string? = nil
	local bestIncome = -1
	for uid, record in data.Brainrots do
		if not DataService.farmSlotOf(data, uid) then
			local value = EconomyMath.income(record)
			if value > bestIncome or (value == bestIncome and bestUid ~= nil and uid < (bestUid :: string)) then
				bestUid, bestIncome = uid, value
			end
		end
	end
	if not bestUid then
		notify(player, "Info", "Todos tus brainrots ya están colocados: abre cajas para conseguir más")
		return
	end
	local uid = bestUid :: string
	if DataService.placeInFarm(data, uid, slot) then
		DataService.changed(player, true)
		local record = data.Brainrots[uid]
		notify(player, "Reward", `{EconomyMath.entryOf(record.Id).Name} colocado (+{EconomyMath.format(EconomyMath.income(record))} monedas/s)`)
	end
end

-- ---------------------------------------------------------------------------
-- Proteccion y robos
-- ---------------------------------------------------------------------------

-- Por que no se puede robar en esta granja ahora mismo (nil = se puede)
local function protectionReason(plot: Plot): string?
	local owner = plot.Owner
	if not owner then
		return "Granja libre"
	end
	local now = os.clock()
	if plot.MatchLocked then
		return "Granja bloqueada: su dueño está jugando un partido"
	end
	if now < plot.LockedUntil then
		return "Granja bloqueada"
	end
	if now < plot.ShieldUntil then
		return "Granja protegida (jugador nuevo en el servidor)"
	end
	return nil
end

function FarmService.isBeingStolen(owner: Player, uid: string): boolean
	for _, carry in carries do
		if carry.Owner == owner and carry.Uid == uid then
			return true
		end
	end
	return false
end

function FarmService.isCarrying(player: Player): boolean
	return carries[player] ~= nil
end

local function endCarry(carry: Carry)
	carries[carry.Thief] = nil
	if carry.Model.Parent then
		carry.Model:Destroy()
	end
	if carry.Highlight.Parent then
		carry.Highlight:Destroy()
	end
	carry.Thief:SetAttribute("CarryUntil", nil)
	carry.Thief:SetAttribute("CarryName", nil)
	carry.Thief:SetAttribute("CarryOwner", nil)
	local humanoid = humanoidOf(carry.Thief)
	if humanoid and not inMatch(carry.Thief) then
		humanoid.WalkSpeed = carry.WalkSpeed
	end
end

local function failCarry(carry: Carry, reason: string)
	endCarry(carry)
	local entry = EconomyMath.entryOf(carry.Id)
	if carry.Thief.Parent then
		notify(carry.Thief, "Warning", `Robo fallido: {reason}`)
	end
	if carry.Owner.Parent then
		notify(carry.Owner, "Info", `{entry.Name} ha vuelto a tu granja`)
		FarmService.refresh(carry.Owner)
		DataService.changed(carry.Owner, true)
	end
end

local function succeedCarry(carry: Carry)
	endCarry(carry)
	local ownerData = DataService.get(carry.Owner)
	local thiefData = DataService.get(carry.Thief)
	local entry = EconomyMath.entryOf(carry.Id)
	if not ownerData or not thiefData then
		failCarry(carry, "datos no disponibles")
		return
	end
	local record = ownerData.Brainrots[carry.Uid]
	if not record or record.Id ~= carry.Id then
		failCarry(carry, "el brainrot ya no estaba")
		return
	end
	local newUid = DataService.addBrainrot(thiefData, record.Id, record.Level, record.Variant)
	if not newUid then
		failCarry(carry, "tu inventario esta lleno")
		return
	end
	DataService.removeBrainrot(ownerData, carry.Uid)
	local placed = DataService.placeInFarm(thiefData, newUid)
	DataService.addStat(thiefData, "Stolen", 1)
	DataService.addStat(ownerData, "LostToThieves", 1)
	DataService.changed(carry.Owner, true)
	DataService.changed(carry.Thief, true)
	task.spawn(DataService.save, carry.Owner)
	task.spawn(DataService.save, carry.Thief)
	notify(carry.Thief, "Reward", `¡Has robado a {entry.Name}!{if placed then "" else " (sin pedestal libre: esta en tu inventario)"}`)
	notify(carry.Owner, "Warning", `{carry.Thief.DisplayName} te ha robado a {entry.Name}`)
	print(`[Granjas] {carry.Thief.Name} roba {entry.Name} a {carry.Owner.Name}`)
end

local function trySteal(thief: Player, plot: Plot, slot: number)
	local owner = plot.Owner
	if not owner or owner == thief then
		return
	end
	if carries[thief] then
		notify(thief, "Warning", "Ya llevas un brainrot")
		return
	end
	if inMatch(thief) then
		return
	end
	if thief:GetAttribute("Riding") ~= nil then
		notify(thief, "Warning", "Bájate del vehículo para robar (tecla V)")
		return
	end
	if not plotOf[thief] then
		notify(thief, "Warning", "No tienes granja donde llevarlo")
		return
	end
	local reason = protectionReason(plot)
	if reason then
		notify(thief, "Warning", reason)
		return
	end
	local shown = plot.Shown[slot]
	if not shown or isStolenSlot(plot, slot) then
		return
	end
	local thiefData = DataService.get(thief)
	if not thiefData or DataService.countBrainrots(thiefData) >= Economy.Brainrot.MaxInventory then
		notify(thief, "Warning", "Tu inventario esta lleno")
		return
	end
	local root = rootOf(thief)
	local humanoid = humanoidOf(thief)
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (root.Position - plot.Pedestals[slot].Position).Magnitude > 14 then
		return
	end
	-- Se lo lleva sobre la cabeza
	local model = BrainrotModel.build(shown.Id, shown.Variant, 3.2, EconomyMath.evolutionOf(shown.Level), 0.5)
	local modelRoot = model.PrimaryPart :: BasePart
	model:PivotTo(root.CFrame * CFrame.new(0, 3.6, 0)) -- todo el modelo (no solo su base)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = modelRoot
	weld.C0 = CFrame.new(0, 3.6, 0)
	weld.Parent = modelRoot
	model.Parent = thief.Character
	-- El ladron brilla en rojo (se ve a traves de las paredes): su dueno puede perseguirle
	local highlight = Instance.new("Highlight")
	highlight.Name = "FG_Thief"
	highlight.FillColor = C.Red
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = C.Red
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = thief.Character
	highlight.Parent = thief.Character
	local carry: Carry = {
		Thief = thief,
		Owner = owner,
		Slot = slot,
		Uid = shown.Uid,
		Id = shown.Id,
		Level = shown.Level,
		Variant = shown.Variant,
		Started = os.clock(),
		Model = model,
		WalkSpeed = humanoid.WalkSpeed,
		Highlight = highlight,
	}
	carries[thief] = carry
	humanoid.WalkSpeed = carry.WalkSpeed * F.ThiefSpeed
	thief:SetAttribute("CarryUntil", workspace:GetServerTimeNow() + F.StealSeconds)
	thief:SetAttribute("CarryName", EconomyMath.entryOf(shown.Id).Name)
	thief:SetAttribute("CarryOwner", owner.UserId) -- el dueno ve un aviso sobre el ladron (FarmController)
	clearSlot(plot, slot, true)
	DataService.changed(owner, true) -- sus ingresos bajan mientras se lo roban
	local name = EconomyMath.entryOf(shown.Id).Name
	notify(thief, "Info", `¡Llévalo a tu granja en {F.StealSeconds} s! Sigue la línea verde`)
	notify(owner, "Warning", `¡{thief.DisplayName} te está robando a {name}! Alcánzale para recuperarlo`)
end

local function updateCarries()
	local now = os.clock()
	for thief, carry in carries do
		local root = rootOf(thief)
		local humanoid = humanoidOf(thief)
		if not thief.Parent or not root or not humanoid or humanoid.Health <= 0 or not carry.Model:IsDescendantOf(workspace) then
			failCarry(carry, "te has caído")
			continue
		end
		if not carry.Owner.Parent or not plotOf[carry.Owner] then
			endCarry(carry)
			notify(thief, "Info", "El dueño se ha ido del servidor: el robo se cancela")
			continue
		end
		if now - carry.Started > F.StealSeconds then
			failCarry(carry, "se acabó el tiempo")
			continue
		end
		local ownerRoot = rootOf(carry.Owner)
		if ownerRoot and (ownerRoot.Position - root.Position).Magnitude <= F.ReturnRange then
			failCarry(carry, `{carry.Owner.DisplayName} lo ha recuperado`)
			continue
		end
		local home = plotOf[thief]
		if home and inside(home, root.Position, -1) then
			succeedCarry(carry)
		end
	end
end

-- Bloqueo: echa a los intrusos y muestra el laser; carteles, arco y boton con el estado
-- Bloqueo automatico en los partidos: al entrar el dueno a un partido la granja se bloquea; si ya tenia un bloqueo,
-- lo que le quedaba se congela (no corre mientras juega) y al volver se le devuelve la mitad (MatchLockResumeFactor).
local function updateMatchLock(plot: Plot, now: number)
	local owner = plot.Owner
	if not owner or not F.LockWhileInMatch then
		return
	end
	local playing = inMatch(owner)
	if playing and not plot.MatchLocked then
		plot.MatchLocked = true
		plot.PausedLock = math.max(0, plot.LockedUntil - now)
		plot.LockedUntil = 0
	elseif not playing and plot.MatchLocked then
		plot.MatchLocked = false
		if plot.PausedLock > 0 then
			local left = plot.PausedLock * F.MatchLockResumeFactor
			plot.LockedUntil = now + left
			plot.LockReadyAt = plot.LockedUntil + F.LockCooldown
			notify(owner, "Info", `Tu granja sigue bloqueada {math.ceil(left)} s (la mitad de lo que te quedaba)`)
		end
		plot.PausedLock = 0
	end
end

-- Carteles y boton: solo se tocan cuando cambian (se recuerda lo ultimo puesto; asi no se trabaja 4 veces por
-- segundo en balde por cada granja)
local shown: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local function setProp(instance: Instance, property: string, value: any)
	local last = shown[instance]
	if not last then
		last = {}
		shown[instance] = last
	end
	if last[property] ~= value then
		last[property] = value;
		(instance :: any)[property] = value
	end
end
local function setText(label: Instance, text: string)
	setProp(label, "Text", text)
end

local function updatePlots()
	local now = os.clock()
	for _, plot in plots do
		updateMatchLock(plot, now)
		local locked = plot.Owner ~= nil and (plot.MatchLocked or now < plot.LockedUntil)
		setCage(plot, locked)
		if locked then
			for _, player in Players:GetPlayers() do
				if player ~= plot.Owner then
					local root = rootOf(player)
					if root and inside(plot, root.Position, 0.5) and not carries[player] then
						local out = plot.CFrame * CFrame.new(0, 3, -PLOT_D / 2 - 6)
						root.CFrame = CFrame.lookAt(out.Position, out.Position + plot.CFrame.LookVector)
					end
				end
			end
		end
		local owner = plot.Owner
		if owner then
			setText(plot.Sign, owner.DisplayName)
			setText(plot.ArchLabel, `Granja de {owner.DisplayName}`)
			setText(plot.Tag, `Granja de {owner.DisplayName}`)
			local reason = protectionReason(plot)
			if plot.MatchLocked then
				setText(plot.Status, if plot.PausedLock > 0
					then `BLOQUEADA · en partido (bloqueo congelado: {math.ceil(plot.PausedLock)} s)`
					else "BLOQUEADA · su dueño está en un partido")
				setProp(plot.Status, "TextColor3", C.Red)
				setText(plot.PadLabel, "EN PARTIDO")
				setProp(plot.Pad, "Color", C.Red)
			elseif locked then
				setText(plot.Status, `BLOQUEADA {math.ceil(plot.LockedUntil - now)} s`)
				setProp(plot.Status, "TextColor3", C.Red)
				setText(plot.PadLabel, `{math.ceil(plot.LockedUntil - now)} s`)
				setProp(plot.Pad, "Color", C.Red)
			elseif now < plot.LockReadyAt then
				setText(plot.PadLabel, `ESPERA {math.ceil(plot.LockReadyAt - now)} s`)
				setProp(plot.Pad, "Color", C.Grey)
			else
				setText(plot.PadLabel, "BLOQUEAR")
				setProp(plot.Pad, "Color", C.Red)
			end
			if not locked then
				if reason then
					setText(plot.Status, reason)
					setProp(plot.Status, "TextColor3", C.Green)
				elseif now < plot.LockReadyAt then
					setText(plot.Status, `Abierta · bloqueo listo en {math.ceil(plot.LockReadyAt - now)} s`)
					setProp(plot.Status, "TextColor3", C.Cyan)
				else
					setText(plot.Status, "Abierta · pisa el botón rojo para bloquear")
					setProp(plot.Status, "TextColor3", C.Cyan)
				end
			end
			local income = tonumber(owner:GetAttribute("Income")) or 0
			setText(plot.IncomeLabel, `+{EconomyMath.format(income)} monedas/s`)
			plot.Model:SetAttribute("Protected", reason ~= nil)
		else
			setText(plot.Sign, "GRANJA LIBRE")
			setText(plot.ArchLabel, "GRANJA LIBRE")
			setText(plot.Tag, "GRANJA LIBRE")
			setText(plot.Status, "")
			setText(plot.IncomeLabel, "")
			setText(plot.PadLabel, "")
			setProp(plot.Pad, "Color", C.Grey)
			plot.Model:SetAttribute("Protected", true)
		end
	end
end

-- Tablero "TOP GRANJAS": las granjas del servidor ordenadas por monedas por segundo
local function updateLeaderboard()
	local list = {}
	for player, plot in plotOf do
		if plot.Owner == player then
			table.insert(list, { Name = player.DisplayName, Income = tonumber(player:GetAttribute("Income")) or 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.Income ~= b.Income then
			return a.Income > b.Income
		end
		return a.Name < b.Name
	end)
	for i, row in leaderRows do
		local entry = list[i]
		row.Name.Text = if entry then `#{i}  {entry.Name}` else ""
		row.Income.Text = if entry then `+{EconomyMath.format(entry.Income)}/s` else ""
	end
end

-- ---------------------------------------------------------------------------
-- Asignar / liberar
-- ---------------------------------------------------------------------------

local function assign(player: Player)
	if plotOf[player] then
		return
	end
	for _, plot in plots do
		if not plot.Owner then
			plot.Owner = player
			plot.ShieldUntil = os.clock() + F.NewPlayerShieldSeconds
			plot.LockedUntil = 0
			plot.LockReadyAt = 0
			plot.MatchLocked = false
			plot.PausedLock = 0
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			plotOf[player] = plot
			player:SetAttribute("PlotIndex", plot.Index)
			trackOwner(player, plot.Index) -- puede atravesar la jaula de SU granja
			refreshPlot(plot)
			-- Cara del dueno en el cartel (la pide a Roblox: puede tardar un poco)
			task.spawn(function()
				local ok, image = pcall(function()
					return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				end)
				if ok and plot.Owner == player then
					plot.Avatar.Image = image
				end
			end)
			return
		end
	end
	warn(`[Granjas] No quedan granjas libres para {player.Name} (sube Economy.Farm.Plots o baja el tamano del servidor)`)
end

local function release(player: Player)
	untrackOwner(player)
	local carry = carries[player]
	if carry then
		failCarry(carry, "has salido del servidor")
	end
	for _, other in carries do
		if other.Owner == player then
			endCarry(other)
			if other.Thief.Parent then
				notify(other.Thief, "Info", "El dueño se ha ido del servidor: el robo se cancela")
			end
		end
	end
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	plot.Owner = nil
	plot.Avatar.Image = ""
	plot.Model:SetAttribute("OwnerUserId", nil)
	for slot = 1, F.Slots do
		clearSlot(plot, slot)
	end
end

-- Punto delante de la granja del jugador (para el boton "Ir a mi granja")
function FarmService.homeCFrame(player: Player): CFrame?
	local plot = plotOf[player]
	if not plot then
		return nil
	end
	local p = (plot.CFrame * CFrame.new(0, 3, -PLOT_D / 2 + 4)).Position
	return CFrame.lookAt(p, p + plot.CFrame.LookVector * -1)
end

function FarmService.start()
	-- Los modelos que metas en ReplicatedStorage > BrainrotModels no deben llevar scripts (los de la Toolbox a veces
	-- traen scripts maliciosos): se borran al arrancar el servidor
	local custom = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if custom then
		local removed = 0
		for _, d in custom:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
				removed += 1
			end
		end
		if removed > 0 then
			warn(`[Granjas] Se han quitado {removed} scripts de ReplicatedStorage > BrainrotModels`)
		end
	end

	setupCageGroups()
	buildArea()

	for _, plot in plots do
		for slot, pedestal in plot.Pedestals do
			local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt
			steal.Triggered:Connect(function(player: Player)
				trySteal(player, plot, slot)
			end)
			local place = pedestal:FindFirstChild("PlacePrompt") :: ProximityPrompt
			place.Triggered:Connect(function(player: Player)
				quickPlace(player, plot, slot)
			end)
		end
	end

	DataService.onLoaded(function(player)
		assign(player)
	end)
	DataService.onChanged(function(player)
		FarmService.refresh(player)
	end)
	DataService.onReleased(release)

	-- Boton "Ir a mi granja"
	local teleportRemote = Remotes.get("Notify")
	teleportRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if request ~= "GoHome" or inMatch(player) or carries[player] then
			return
		end
		local home = FarmService.homeCFrame(player)
		local root = rootOf(player)
		if home and root then
			root.CFrame = home
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 or next(carries) == nil then
			return -- sin robos en curso no hay nada que mirar
		end
		accumulator = 0
		local ok, err = pcall(function()
			updateCarries()
		end)
		if not ok then
			warn(`[Granjas] Error en robos: {err}`)
		end
	end)
	task.spawn(function()
		local sinceBoard = math.huge
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				updatePlots()
			end)
			if not ok then
				warn(`[Granjas] Error en granjas: {err}`)
			end
			sinceBoard += 0.25
			if sinceBoard >= 5 then
				sinceBoard = 0
				local ok2, err2 = pcall(updateLeaderboard)
				if not ok2 then
					warn(`[Granjas] Error en el tablero: {err2}`)
				end
			end
		end
	end)
	print(`[Granjas] {F.Plots} granjas listas a la izquierda del spawn`)
end

return FarmService
