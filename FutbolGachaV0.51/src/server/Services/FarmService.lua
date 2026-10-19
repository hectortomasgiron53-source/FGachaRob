--!strict
--[[
	FarmService: las granjas de brainrots (a la izquierda del spawn) y los robos.
	- Hay Economy.Farm.Plots granjas por servidor. Al entrar se te asigna una libre; al salir queda libre.
	- Cada granja tiene Economy.Farm.Slots pedestales. Los brainrots colocados te dan monedas cada segundo.
	- Robar: en la granja de otro, mantén el aviso "Robar" junto a un pedestal. Te lo llevas sobre la cabeza (vas mas
	  lento) y tienes Economy.Farm.StealSeconds para llegar a TU granja. Si el dueno te toca, se le devuelve.
	- Defensa: el boton rojo de tu granja la bloquea un rato (laser en la entrada: echa a los intrusos). Al entrar al
	  servidor y mientras juegas un partido tu granja esta protegida.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local BrainrotModel = require(ReplicatedStorage.Shared.Util.BrainrotModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local FarmService = {}

local NotifyEvent = Remotes.get("Notify")
local F = Economy.Farm

-- Disposicion: avenida a lo largo de +X desde el borde este del lobby (x = 77); granjas a ambos lados.
local AVENUE_START = 78
local AVENUE_HALF = 9 -- media anchura de la avenida (eje Z)
local PLOT_W = 52 -- ancho (a lo largo de la avenida)
local PLOT_D = 46 -- fondo
local PLOT_GAP = 6
local WALL_H = 5
local GATE_W = 14

local C = {
	Navy = Color3.fromRGB(9, 18, 38),
	Panel = Color3.fromRGB(17, 34, 62),
	Path = Color3.fromRGB(40, 48, 66),
	Cyan = Color3.fromRGB(104, 168, 196),
	White = Color3.fromRGB(235, 245, 255),
	Red = Color3.fromRGB(235, 60, 60),
	Green = Color3.fromRGB(80, 200, 110),
	Gold = Color3.fromRGB(255, 194, 74),
}
local PLOT_COLORS = {
	Color3.fromRGB(64, 120, 78),
	Color3.fromRGB(70, 96, 150),
	Color3.fromRGB(140, 92, 60),
	Color3.fromRGB(120, 70, 130),
	Color3.fromRGB(60, 128, 130),
	Color3.fromRGB(150, 120, 50),
	Color3.fromRGB(130, 60, 70),
	Color3.fromRGB(90, 90, 100),
}

type Shown = { Uid: string, Id: string, Level: number, Variant: string, Model: Model }
type Plot = {
	Index: number,
	CFrame: CFrame, -- centro del suelo; -Z local = entrada (mira a la avenida)
	Model: Model,
	Pedestals: { Part },
	Doors: { Part },
	Sign: TextLabel,
	Status: TextLabel,
	IncomeLabel: TextLabel,
	Owner: Player?,
	Shown: { [number]: Shown },
	LockedUntil: number,
	LockReadyAt: number,
	ShieldUntil: number,
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
}

local plots: { Plot } = {}

local plotOf: { [Player]: Plot } = {}
local carries: { [Player]: Carry } = {} -- por ladron
local folder: Model

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

-- ---------------------------------------------------------------------------
-- Construccion
-- ---------------------------------------------------------------------------

local function makeSurfaceText(adornee: BasePart, face: Enum.NormalId, pixels: number): (Frame, TextLabel, TextLabel, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = 0
	gui.Parent = adornee
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = C.Navy
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local function label(y: number, h: number, font: Enum.Font, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = ""
		l.Parent = frame
		return l
	end
	local title = label(0.06, 0.42, Enum.Font.GothamBlack, C.White)
	local status = label(0.5, 0.22, Enum.Font.GothamBold, C.Cyan)
	local income = label(0.74, 0.2, Enum.Font.GothamMedium, C.Gold)
	return frame, title, status, income
end

local function buildPlot(index: number): Plot
	local k = math.ceil(index / 2)
	local north = index % 2 == 1
	local x = AVENUE_START + PLOT_GAP + (k - 0.5) * (PLOT_W + PLOT_GAP)
	local z = (AVENUE_HALF + 2 + PLOT_D / 2) * (if north then 1 else -1)
	local center = Vector3.new(x, 0, z)
	local facing = Vector3.new(0, 0, if north then -1 else 1) -- la entrada mira a la avenida
	local cf = CFrame.lookAt(center, center + facing)

	local model = Instance.new("Model")
	model.Name = `Granja_{index}`
	model:SetAttribute("PlotIndex", index)
	model.Parent = folder

	local floorColor = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	part(model, "Floor", Vector3.new(PLOT_W, 1, PLOT_D), cf * CFrame.new(0, -0.5, 0), floorColor, Enum.Material.Grass)
	-- Borde
	part(model, "Edge", Vector3.new(PLOT_W + 1, 0.4, 1), cf * CFrame.new(0, 0.2, -PLOT_D / 2), C.Panel, Enum.Material.Metal)
	-- Muros: fondo, lados y frente con puerta
	part(model, "WallBack", Vector3.new(PLOT_W, WALL_H, 1.5), cf * CFrame.new(0, WALL_H / 2, PLOT_D / 2), C.Panel, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		part(model, "WallSide", Vector3.new(1.5, WALL_H, PLOT_D), cf * CFrame.new(side * PLOT_W / 2, WALL_H / 2, 0), C.Panel, Enum.Material.Metal)
		local segment = (PLOT_W - GATE_W) / 2
		part(model, "WallFront", Vector3.new(segment, WALL_H, 1.5), cf * CFrame.new(side * (GATE_W / 2 + segment / 2), WALL_H / 2, -PLOT_D / 2), C.Panel, Enum.Material.Metal)
		-- Postes de la puerta
		part(model, "GatePost", Vector3.new(1.6, WALL_H + 3, 1.6), cf * CFrame.new(side * GATE_W / 2, (WALL_H + 3) / 2, -PLOT_D / 2), C.Navy, Enum.Material.Metal)
	end
	-- Laser de la puerta (solo se ve cuando esta bloqueada; no choca: a los intrusos los echa el servidor)
	local doors = {}
	for i = 1, 4 do
		local door = part(model, "Laser", Vector3.new(GATE_W, 0.25, 0.25), cf * CFrame.new(0, i * 1.6, -PLOT_D / 2), C.Red, Enum.Material.Neon)
		door.CanCollide = false
		door.CanQuery = false
		door.CanTouch = false
		door.Transparency = 1
		table.insert(doors, door)
	end
	-- Cartel
	local signPart = part(model, "Sign", Vector3.new(26, 7, 0.6), cf * CFrame.new(0, WALL_H + 5.5, PLOT_D / 2 - 0.2), C.Navy, Enum.Material.Metal)
	signPart.CanCollide = false
	local _, title, status, income = makeSurfaceText(signPart, Enum.NormalId.Front, 25)
	for _, side in { -1, 1 } do
		part(model, "SignPole", Vector3.new(0.6, WALL_H + 5, 0.6), cf * CFrame.new(side * 11, (WALL_H + 5) / 2, PLOT_D / 2 + 0.2), C.Panel, Enum.Material.Metal)
	end

	-- Pedestales: 2 filas de 5
	local pedestals = {}
	local cols = math.ceil(F.Slots / 2)
	for slot = 1, F.Slots do
		local row = if slot <= cols then 0 else 1
		local col = (slot - 1) % cols
		local px = (col - (cols - 1) / 2) * 9.5
		local pz = -2 + row * 13
		local pedestal = part(model, `Pedestal_{slot}`, Vector3.new(1.4, 6, 6), cf * CFrame.new(px, 0.7, pz) * CFrame.Angles(0, 0, math.rad(90)), C.Panel, Enum.Material.Metal)
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal:SetAttribute("Slot", slot)
		pedestal:SetAttribute("PlotIndex", index)
		local ring = part(model, "PedestalRing", Vector3.new(0.2, 6.3, 6.3), cf * CFrame.new(px, 1.35, pz) * CFrame.Angles(0, 0, math.rad(90)), C.Cyan, Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.CanCollide = false
		ring.CanQuery = false
		-- Avisos: "Robar" (para los demas) y "Gestionar" (para el dueno). El cliente ensena solo el que toca.
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
		pedestals[slot] = pedestal
	end

	-- Boton de bloqueo (dentro, junto a la entrada)
	local pad = part(model, "LockPad", Vector3.new(6, 0.4, 6), cf * CFrame.new(-PLOT_W / 2 + 6, 0.2, -PLOT_D / 2 + 6), C.Red, Enum.Material.Neon)
	pad.CanCollide = false
	local padGui = Instance.new("SurfaceGui")
	padGui.Face = Enum.NormalId.Top
	padGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	padGui.PixelsPerStud = 30
	padGui.LightInfluence = 0
	padGui.Parent = pad
	local padText = Instance.new("TextLabel")
	padText.Size = UDim2.fromScale(1, 1)
	padText.BackgroundTransparency = 1
	padText.Font = Enum.Font.GothamBlack
	padText.TextScaled = true
	padText.TextColor3 = C.White
	padText.Text = "BLOQUEAR"
	padText.Parent = padGui

	local plot: Plot = {
		Index = index,
		CFrame = cf,
		Model = model,
		Pedestals = pedestals,
		Doors = doors,
		Sign = title,
		Status = status,
		IncomeLabel = income,
		Owner = nil,
		Shown = {},
		LockedUntil = 0,
		LockReadyAt = 0,
		ShieldUntil = 0,
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

local function buildArea()
	local old = workspace:FindFirstChild("Granjas")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Granjas"
	model.Parent = workspace
	folder = model
	local cols = math.ceil(F.Plots / 2)
	local endX = AVENUE_START + PLOT_GAP + cols * (PLOT_W + PLOT_GAP) + 2
	local length = endX - 75
	-- Suelo (misma altura que la plataforma del lobby) y avenida
	part(model, "FarmFoundation", Vector3.new(length, 2, 120), CFrame.new(75 + length / 2, -1.5, 0), C.Navy, Enum.Material.Concrete)
	part(model, "Avenue", Vector3.new(length, 0.1, AVENUE_HALF * 2), CFrame.new(75 + length / 2, -0.45, 0), C.Path, Enum.Material.Slate)
	for _, z in { -AVENUE_HALF, AVENUE_HALF } do
		local glow = part(model, "AvenueGlow", Vector3.new(length, 0.12, 0.3), CFrame.new(75 + length / 2, -0.42, z), C.Cyan, Enum.Material.Neon)
		glow.CanCollide = false
	end
	-- Arco de entrada
	for _, z in { -AVENUE_HALF - 1, AVENUE_HALF + 1 } do
		part(model, "ArchPillar", Vector3.new(2, 16, 2), CFrame.new(84, 7.5, z), C.Panel, Enum.Material.Metal)
	end
	local arch = part(model, "Arch", Vector3.new(3, 4, AVENUE_HALF * 2 + 4), CFrame.new(84, 17, 0), C.Navy, Enum.Material.Metal)
	local archGui = Instance.new("SurfaceGui")
	archGui.Face = Enum.NormalId.Left -- mira hacia el lobby (-X)
	archGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	archGui.PixelsPerStud = 30
	archGui.LightInfluence = 0
	archGui.Parent = arch
	local archText = Instance.new("TextLabel")
	archText.Size = UDim2.fromScale(1, 1)
	archText.BackgroundTransparency = 1
	archText.Font = Enum.Font.GothamBlack
	archText.TextScaled = true
	archText.TextColor3 = C.Gold
	archText.Text = "GRANJAS DE BRAINROTS"
	archText.Parent = archGui
	-- Barreras invisibles
	local function barrier(size: Vector3, position: Vector3)
		local wall = part(model, "Boundary", size, CFrame.new(position), C.Navy)
		wall.Transparency = 1
		wall.CanQuery = false
	end
	barrier(Vector3.new(length + 4, 80, 4), Vector3.new(75 + length / 2, 38, 62))
	barrier(Vector3.new(length + 4, 80, 4), Vector3.new(75 + length / 2, 38, -62))
	barrier(Vector3.new(4, 80, 128), Vector3.new(endX + 2, 38, 0))

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
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.6, 0)
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
	info.Text = `{rarity.Name}{if record.Variant ~= "Normal" then " · " .. variant.Name else ""} · Nv {record.Level}`
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

local function clearSlot(plot: Plot, slot: number)
	local shown = plot.Shown[slot]
	if shown then
		shown.Model:Destroy()
		plot.Shown[slot] = nil
	end
	local pedestal = plot.Pedestals[slot]
	pedestal:SetAttribute("Uid", nil)
	pedestal:SetAttribute("BrainrotName", nil)
	local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt
	steal.ObjectText = ""
	local manage = pedestal:FindFirstChild("ManagePrompt") :: ProximityPrompt
	manage.ObjectText = ""
end

local function refreshPlot(plot: Plot)
	local owner = plot.Owner
	local data = if owner then DataService.get(owner) else nil
	for slot = 1, F.Slots do
		local uid = if data then data.Farm[tostring(slot)] else nil
		local record = if data and uid then data.Brainrots[uid] else nil
		if not record or isStolenSlot(plot, slot) then
			clearSlot(plot, slot)
			continue
		end
		local shown = plot.Shown[slot]
		if shown and shown.Uid == uid and shown.Level == record.Level and shown.Variant == record.Variant and shown.Id == record.Id then
			continue
		end
		clearSlot(plot, slot)
		local height = EconomyMath.rarityOf(record.Id).Height
		local model = BrainrotModel.build(record.Id, record.Variant, height)
		local root = model.PrimaryPart :: BasePart
		root.Anchored = true
		local base = pedestalTop(plot, slot)
		model:PivotTo(base)
		model:SetAttribute("BaseCFrame", base)
		makeBillboard(model, height, record)
		model.Parent = plot.Model
		CollectionService:AddTag(model, "FarmBrainrot")
		plot.Shown[slot] = { Uid = uid :: string, Id = record.Id, Level = record.Level, Variant = record.Variant, Model = model }
		local pedestal = plot.Pedestals[slot]
		pedestal:SetAttribute("Uid", uid)
		pedestal:SetAttribute("BrainrotName", EconomyMath.entryOf(record.Id).Name)
		local entry = EconomyMath.entryOf(record.Id)
		local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt
		steal.ObjectText = entry.Name
		local manage = pedestal:FindFirstChild("ManagePrompt") :: ProximityPrompt
		manage.ObjectText = entry.Name
	end
end

function FarmService.refresh(player: Player)
	local plot = plotOf[player]
	if plot then
		refreshPlot(plot)
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
	if now < plot.LockedUntil then
		return "Granja bloqueada"
	end
	if now < plot.ShieldUntil then
		return "Granja protegida (jugador nuevo en el servidor)"
	end
	if F.ProtectWhileInMatch and inMatch(owner) then
		return "Granja protegida: su dueño está jugando un partido"
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
	carry.Thief:SetAttribute("CarryUntil", nil)
	carry.Thief:SetAttribute("CarryName", nil)
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
	local model = BrainrotModel.build(shown.Id, shown.Variant, 3.2)
	local modelRoot = model.PrimaryPart :: BasePart
	modelRoot.CFrame = root.CFrame * CFrame.new(0, 3.6, 0)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = modelRoot
	weld.C0 = CFrame.new(0, 3.6, 0)
	weld.Parent = modelRoot
	model.Parent = thief.Character
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
	}
	carries[thief] = carry
	humanoid.WalkSpeed = carry.WalkSpeed * F.ThiefSpeed
	thief:SetAttribute("CarryUntil", workspace:GetServerTimeNow() + F.StealSeconds)
	thief:SetAttribute("CarryName", EconomyMath.entryOf(shown.Id).Name)
	clearSlot(plot, slot)
	DataService.changed(owner, true) -- sus ingresos bajan mientras se lo roban
	local name = EconomyMath.entryOf(shown.Id).Name
	notify(thief, "Info", `¡Llévalo a tu granja en {F.StealSeconds} s!`)
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

-- Bloqueo: echa a los intrusos y muestra el laser; carteles con el estado
local function updatePlots()
	local now = os.clock()
	for _, plot in plots do
		local locked = plot.Owner ~= nil and now < plot.LockedUntil
		for _, door in plot.Doors do
			door.Transparency = if locked then 0.25 else 1
		end
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
			plot.Sign.Text = `Granja de {owner.DisplayName}`
			local reason = protectionReason(plot)
			if locked then
				plot.Status.Text = `BLOQUEADA {math.ceil(plot.LockedUntil - now)} s`
				plot.Status.TextColor3 = C.Red
			elseif reason then
				plot.Status.Text = reason
				plot.Status.TextColor3 = C.Green
			elseif now < plot.LockReadyAt then
				plot.Status.Text = `Abierta · bloqueo listo en {math.ceil(plot.LockReadyAt - now)} s`
				plot.Status.TextColor3 = C.Cyan
			else
				plot.Status.Text = "Abierta · pisa el botón rojo para bloquear"
				plot.Status.TextColor3 = C.Cyan
			end
			local income = tonumber(owner:GetAttribute("Income")) or 0
			plot.IncomeLabel.Text = `+{EconomyMath.format(income)} monedas/s`
			plot.Model:SetAttribute("Protected", reason ~= nil)
		else
			plot.Sign.Text = "GRANJA LIBRE"
			plot.Status.Text = ""
			plot.IncomeLabel.Text = ""
			plot.Model:SetAttribute("Protected", true)
		end
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
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			plotOf[player] = plot
			player:SetAttribute("PlotIndex", plot.Index)
			refreshPlot(plot)
			return
		end
	end
	warn(`[Granjas] No quedan granjas libres para {player.Name} (sube Economy.Farm.Plots o baja el tamano del servidor)`)
end

local function release(player: Player)
	local carry = carries[player]
	if carry then
		failCarry(carry, "has salido del servidor")
	end
	for _, other in carries do
		if other.Owner == player then
			endCarry(other)
		end
	end
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	plot.Owner = nil
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

	buildArea()

	for _, plot in plots do
		for slot, pedestal in plot.Pedestals do
			local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt
			steal.Triggered:Connect(function(player: Player)
				trySteal(player, plot, slot)
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
		if accumulator < 0.1 then
			return
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
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				updatePlots()
			end)
			if not ok then
				warn(`[Granjas] Error en granjas: {err}`)
			end
		end
	end)
	print(`[Granjas] {F.Plots} granjas listas a la izquierda del spawn`)
end

return FarmService
