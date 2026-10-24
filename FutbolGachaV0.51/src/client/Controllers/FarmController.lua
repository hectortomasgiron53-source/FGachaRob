--!strict
--[[
	FarmController: lo que se ve en tu ordenador de las granjas y de los brainrots.
	- Avisos de los pedestales: "Robar" solo en granjas ajenas (y sin proteccion); en la tuya, "Ver" (abre tu
	  inventario con ese brainrot) y "Colocar" en los pedestales vacios (pone ahi tu mejor brainrot sin colocar).
	- Sobre tus brainrots salen de vez en cuando las monedas que te estan dando ("+12").
	- Si alguien te roba: aviso "¡LADRON!" sobre su cabeza (y el servidor le hace brillar en rojo).
	- Si robas tu: cuenta atras arriba en el centro y una linea verde hasta tu granja.
	- Los brainrots de las granjas flotan y giran un poco (solo los que tienes cerca); los de los partidos dan
	  saltitos al correr.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local EconomyController = require(script.Parent.EconomyController)

local FarmController = {}

local player = Players.LocalPlayer
local Colors = UiKit.Colors

local ANIMATE_DISTANCE = 160 -- los brainrots de granja mas lejos que esto no se animan (no se aprecia)
local POPUP_INTERVAL = 3 -- cada cuanto salen las monedas sobre tus brainrots
local POPUP_DISTANCE = 90 -- solo si estas cerca de tu granja

local hooked: { [ProximityPrompt]: boolean } = {}

local function myPlot(): Instance?
	local farms = Workspace:FindFirstChild("Granjas")
	if not farms then
		return nil
	end
	for _, plot in farms:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

-- Pedestales de cada granja con sus avisos (se buscan una vez: los pedestales no cambian)
type PedestalEntry = { Pedestal: BasePart, Steal: ProximityPrompt?, Manage: ProximityPrompt?, Place: ProximityPrompt? }
local pedestalCache: { [Instance]: { PedestalEntry } } = setmetatable({}, { __mode = "k" }) :: any

local function pedestalsOf(plot: Instance): { PedestalEntry }
	local list = pedestalCache[plot]
	if list and #list > 0 then
		return list
	end
	local found: { PedestalEntry } = {}
	for _, pedestal in plot:GetChildren() do
		if not pedestal:IsA("BasePart") or pedestal:GetAttribute("Slot") == nil then
			continue
		end
		local manage = pedestal:FindFirstChild("ManagePrompt") :: ProximityPrompt?
		if manage and not hooked[manage] then
			hooked[manage] = true
			manage.Triggered:Connect(function()
				local uid = pedestal:GetAttribute("Uid")
				if type(uid) == "string" then
					EconomyController.openInventory(uid)
				end
			end)
		end
		table.insert(found, {
			Pedestal = pedestal,
			Steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt?,
			Manage = manage,
			Place = pedestal:FindFirstChild("PlacePrompt") :: ProximityPrompt?,
		})
	end
	pedestalCache[plot] = found
	return found
end

local function setEnabled(prompt: ProximityPrompt?, enabled: boolean)
	if prompt and prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

local promptRounds = 0
local function updatePrompts()
	local farms = Workspace:FindFirstChild("Granjas")
	if not farms then
		return
	end
	-- Cada ~3 s se vuelve a buscar (por si una granja llega por partes desde el servidor)
	promptRounds += 1
	if promptRounds % 10 == 0 then
		table.clear(pedestalCache)
	end
	for _, plot in farms:GetChildren() do
		if not plot:IsA("Model") or plot:GetAttribute("PlotIndex") == nil then
			continue
		end
		local owner = plot:GetAttribute("OwnerUserId")
		local mine = owner == player.UserId
		local protected = plot:GetAttribute("Protected") == true
		for _, entry in pedestalsOf(plot) do
			local pedestal = entry.Pedestal
			local hasBrainrot = pedestal:GetAttribute("Uid") ~= nil
			setEnabled(entry.Steal, hasBrainrot and owner ~= nil and not mine and not protected)
			setEnabled(entry.Place, mine and not hasBrainrot and pedestal:GetAttribute("BeingStolen") ~= true)
			setEnabled(entry.Manage, hasBrainrot and mine)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Animaciones
-- ---------------------------------------------------------------------------

-- Todo lo animado se guarda en listas propias al aparecer (etiquetas de CollectionService): asi no hay que pedir
-- GetTagged, ni leer atributos, ni buscar piezas en cada fotograma.
local function watchTag(tag: string, added: (Instance) -> (), removed: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
	for _, instance in CollectionService:GetTagged(tag) do
		added(instance)
	end
end

-- Brainrots de las granjas (solo en tu pantalla): flotan y giran un poco. Todos los cercanos se mueven de una vez
-- (BulkMoveTo), que es mucho mas barato que moverlos uno a uno.
type FarmEntry = { Model: Model, Base: CFrame?, Phase: number }
local farmEntries: { [Instance]: FarmEntry } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function addFarmBrainrot(instance: Instance)
	if not instance:IsA("Model") or farmEntries[instance] then
		return
	end
	local model = instance :: Model
	local entry: FarmEntry = { Model = model, Base = nil, Phase = math.random() * 6.28 }
	local function readBase()
		local base = model:GetAttribute("BaseCFrame")
		entry.Base = if typeof(base) == "CFrame" then base else nil
	end
	readBase()
	model:GetAttributeChangedSignal("BaseCFrame"):Connect(readBase)
	farmEntries[model] = entry
end

local function animateFarm(t: number, cameraPos: Vector3)
	local count = 0
	local limit = ANIMATE_DISTANCE * ANIMATE_DISTANCE
	for _, entry in farmEntries do
		local base = entry.Base
		if not base then
			continue
		end
		local offset = base.Position - cameraPos
		if offset:Dot(offset) > limit then
			continue
		end
		local root = entry.Model.PrimaryPart
		if not root then
			continue
		end
		local phase = entry.Phase
		count += 1
		moveParts[count] = root
		moveCFrames[count] = base * CFrame.new(0, math.sin(t * 2 + phase) * 0.2 + 0.2, 0) * CFrame.Angles(0, math.sin(t * 0.6 + phase) * 0.35, 0)
	end
	for i = #moveParts, count + 1, -1 do
		moveParts[i] = nil
		moveCFrames[i] = nil
	end
	if count > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Cintas de los caminos (las crea FarmService con su velocidad): aqui se ponen flechas de neon que avanzan a la
-- misma velocidad que la cinta. Solo se mueven las flechas que tienes cerca (un BulkMoveTo por fotograma); las
-- lejanas se quedan quietas (a esa distancia no se nota).
local CONVEYOR_DISTANCE = 150
local CHEVRON_GAP = 7
type Conveyor = { Lane: BasePart, CFrame: CFrame, Top: number, Arms: { BasePart }, Speed: number, Half: number }
local conveyors: { Conveyor } = {}
local chevronParts: { BasePart } = {}
local chevronCFrames: { CFrame } = {}

-- Las dos piezas de una flecha ">" (punta hacia delante = -Z de la cinta), en el espacio de la punta
local ARM_CFRAMES = {
	CFrame.lookAt(Vector3.new(-0.65, 0, 0.55), Vector3.new(0, 0, 0)),
	CFrame.lookAt(Vector3.new(0.65, 0, 0.55), Vector3.new(0, 0, 0)),
}

local function addConveyor(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local lane = instance :: BasePart
	for _, conveyor in conveyors do
		if conveyor.Lane == lane then
			return
		end
	end
	local length = lane.Size.Z
	local folder = Instance.new("Folder")
	folder.Name = "Flechas"
	folder.Parent = lane
	local color = if lane:GetAttribute("Outbound") then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(80, 220, 255)
	local arms = {}
	local n = math.max(1, math.floor((length - 3) / CHEVRON_GAP))
	for i = 1, n * 2 do
		local arm = Instance.new("Part")
		arm.Name = "Flecha"
		arm.Size = Vector3.new(0.35, 0.05, 1.7)
		arm.Anchored = true
		arm.CanCollide = false
		arm.CanQuery = false
		arm.CanTouch = false
		arm.CastShadow = false
		arm.Material = Enum.Material.Neon
		arm.Color = color
		-- Posicion inicial (por si nunca te acercas a esta cinta)
		local z = length / 2 - 1.5 - ((i + 1) // 2 - 1) * CHEVRON_GAP
		arm.CFrame = lane.CFrame * CFrame.new(0, lane.Size.Y / 2 + 0.03, z) * ARM_CFRAMES[(i - 1) % 2 + 1]
		arm.Parent = folder
		table.insert(arms, arm)
	end
	table.insert(conveyors, {
		Lane = lane,
		CFrame = lane.CFrame, -- las cintas estan ancladas: no se mueven
		Top = lane.Size.Y / 2 + 0.03,
		Arms = arms,
		Speed = tonumber(lane:GetAttribute("ConveyorSpeed")) or 20,
		Half = length / 2,
	})
end

local function animateConveyors(t: number, cameraPos: Vector3)
	local count = 0
	for _, conveyor in conveyors do
		if not conveyor.Lane.Parent then
			continue
		end
		local half = conveyor.Half
		-- Tramo de la cinta a menos de CONVEYOR_DISTANCE de la camara (en el eje de la cinta)
		local cframe = conveyor.CFrame
		local localPos = cframe:PointToObjectSpace(cameraPos)
		local side2 = localPos.X * localPos.X + localPos.Y * localPos.Y
		local reach2 = CONVEYOR_DISTANCE * CONVEYOR_DISTANCE - side2
		if reach2 <= 0 then
			continue
		end
		local reach = math.sqrt(reach2)
		local zMin, zMax = localPos.Z - reach, localPos.Z + reach
		if zMax < -half or zMin > half then
			continue
		end
		local top = conveyor.Top
		local shift = (t * conveyor.Speed) % CHEVRON_GAP
		local arms = conveyor.Arms
		local n = #arms // 2
		local span = n * CHEVRON_GAP
		for i = 1, n do
			-- z local: va de +half (inicio) a -half (final), la flecha avanza hacia -Z y vuelve a salir por el inicio
			local z = half - 1.5 - ((i - 1) * CHEVRON_GAP + shift) % span
			if z < zMin or z > zMax then
				continue
			end
			local tip = cframe * CFrame.new(0, top, z)
			local a = (i - 1) * 2
			chevronParts[count + 1] = arms[a + 1]
			chevronCFrames[count + 1] = tip * ARM_CFRAMES[1]
			chevronParts[count + 2] = arms[a + 2]
			chevronCFrames[count + 2] = tip * ARM_CFRAMES[2]
			count += 2
		end
	end
	for i = #chevronParts, count + 1, -1 do
		chevronParts[i] = nil
		chevronCFrames[i] = nil
	end
	if count > 0 then
		Workspace:BulkMoveTo(chevronParts, chevronCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Jaula de laser de las granjas bloqueadas (la crea FarmService; aqui solo se ve): se enciende y se apaga con un
-- fundido, las barras palpitan, el campo de fuerza "respira" y un escaner sube y baja por cada pared.
-- Se agrupa por granja: una jaula apagada o lejana no cuesta nada (solo se escribe cuando cambia algo).
local LASER_DISTANCE = 320
type Laser = { Part: BasePart, Kind: string, Home: CFrame, Phase: number, Shown: number }
type Cage = { Plot: Instance, Center: Vector3, Lasers: { Laser }, On: boolean, Fade: number, Far: boolean? }
local cages: { [Instance]: Cage } = {}
local laserCage: { [Instance]: Cage } = {}

local function laserTarget(laser: Laser, t: number): number
	local kind = laser.Kind
	if kind == "Bar" then
		return 0.1 + 0.25 * (math.sin(t * 4 + laser.Phase) * 0.5 + 0.5)
	elseif kind == "Field" then
		return 0.45 + 0.12 * math.sin(t * 2)
	elseif kind == "Scan" then
		return 0
	end
	return 0.05
end

local function addLaser(instance: Instance)
	if not instance:IsA("BasePart") or laserCage[instance] then
		return
	end
	local p = instance :: BasePart
	local folder = p.Parent
	local plot = if folder then folder.Parent else nil
	if not plot then
		return
	end
	local cage = cages[plot]
	if not cage then
		local pivot = if plot:IsA("Model") then (plot :: Model):GetPivot().Position else p.Position
		local newCage: Cage = { Plot = plot, Center = pivot, Lasers = {}, On = plot:GetAttribute("Locked") == true, Fade = 0 }
		plot:GetAttributeChangedSignal("Locked"):Connect(function()
			newCage.On = plot:GetAttribute("Locked") == true
			newCage.Far = nil -- vuelve a pintarse
		end)
		cages[plot] = newCage
		cage = newCage
	end
	local c = cage :: Cage
	local height = (tonumber(p:GetAttribute("CageHeight")) or 16) - 2
	table.insert(c.Lasers, {
		Part = p,
		Kind = tostring(p:GetAttribute("LaserKind") or "Post"),
		Home = p.CFrame,
		Phase = if p:GetAttribute("LaserKind") == "Scan" then height else p.Position.Y * 0.8,
		Shown = p.Transparency,
	})
	laserCage[p] = c
end

local function removeLaser(instance: Instance)
	local cage = laserCage[instance]
	if not cage then
		return
	end
	laserCage[instance] = nil
	for i, laser in cage.Lasers do
		if laser.Part == instance then
			table.remove(cage.Lasers, i)
			break
		end
	end
	if #cage.Lasers == 0 then
		cages[cage.Plot] = nil
	end
end

local function setShown(laser: Laser, value: number)
	if math.abs(laser.Shown - value) > 0.004 then
		laser.Shown = value
		laser.Part.Transparency = value
	end
end

local function animateLasers(t: number, dt: number, cameraPos: Vector3)
	local blend = math.min(1, dt * 5)
	local scanLift = math.sin(t * 1.6) * 0.5 + 0.5
	for _, cage in cages do
		local target = if cage.On then 1 else 0
		if cage.Fade == target and not cage.On then
			continue -- apagada del todo: nada que hacer
		end
		if (cage.Center - cameraPos).Magnitude > LASER_DISTANCE then
			-- Lejos: se pinta una vez en su estado final y no se anima
			if not cage.Far then
				cage.Far = true
				cage.Fade = target
				for _, laser in cage.Lasers do
					setShown(laser, if cage.On then 0.3 else 1)
					if laser.Kind == "Scan" then
						laser.Part.CFrame = laser.Home
					end
				end
			end
			continue
		end
		cage.Far = false
		local fade = cage.Fade + (target - cage.Fade) * blend
		if math.abs(target - fade) < 0.01 then
			fade = target
		end
		cage.Fade = fade
		for _, laser in cage.Lasers do
			setShown(laser, 1 - fade * (1 - laserTarget(laser, t)))
			if laser.Kind == "Scan" and fade > 0 then
				laser.Part.CFrame = laser.Home * CFrame.new(0, scanLift * laser.Phase, 0)
			end
		end
	end
end

-- Saltitos al correr de los brainrots de los partidos (la soldadura se busca una vez, no en cada fotograma)
type MatchEntry = { Weld: Weld?, Base: CFrame?, Phase: number, Tries: number }
local matchEntries: { [Instance]: MatchEntry } = {}

local function animateMatch(dt: number)
	for model, entry in matchEntries do
		local weld = entry.Weld
		if not weld or not weld.Parent then
			-- Aun no ha llegado (o se ha cambiado): se busca de vez en cuando
			entry.Tries += 1
			if entry.Tries % 15 ~= 1 then
				continue
			end
			local root = model:FindFirstChild("Root")
			local found = if root then root:FindFirstChild("BrainrotWeld") else nil
			if not found or not found:IsA("Weld") then
				continue
			end
			local base = found:GetAttribute("BaseC0")
			if typeof(base) ~= "CFrame" then
				continue
			end
			entry.Weld = found
			entry.Base = base
			weld = found
		end
		local w = weld :: Weld
		local body = w.Part0
		if not body then
			continue
		end
		local velocity = body.AssemblyLinearVelocity
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		local k = math.clamp(speed / 16, 0, 1)
		if k < 0.01 and entry.Phase == 0 then
			continue -- quieto y ya en reposo
		end
		local phase = if k < 0.01 then 0 else entry.Phase + dt * (6 + speed * 0.45)
		entry.Phase = phase
		local hop = math.abs(math.sin(phase)) * 0.45 * k
		local roll = math.sin(phase) * 0.12 * k
		w.C0 = (entry.Base :: CFrame) * CFrame.new(0, hop, 0) * CFrame.Angles(-0.12 * k, 0, roll)
	end
end

local function startAnimations()
	watchTag("FarmBrainrot", addFarmBrainrot, function(instance)
		farmEntries[instance] = nil
	end)
	watchTag("FarmLaser", addLaser, removeLaser)
	watchTag("FarmConveyor", addConveyor, function(instance)
		for i, conveyor in conveyors do
			if conveyor.Lane == instance then
				local folder = instance:FindFirstChild("Flechas")
				if folder then
					folder:Destroy()
				end
				table.remove(conveyors, i)
				break
			end
		end
	end)
	watchTag("MatchBrainrot", function(instance)
		if not matchEntries[instance] then
			matchEntries[instance] = { Weld = nil, Base = nil, Phase = 0, Tries = 0 }
		end
	end, function(instance)
		matchEntries[instance] = nil
	end)
end

-- ---------------------------------------------------------------------------
-- Monedas sobre tus brainrots
-- ---------------------------------------------------------------------------

local function popup(pedestal: BasePart, text: string, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FG_CoinPopup"
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 3.4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = POPUP_DISTANCE
	gui.Adornee = pedestal
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Colors.Coins
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.Parent = gui
	gui.Parent = player:FindFirstChildOfClass("PlayerGui")
	local info = TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, height + 5.6, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.4, function()
		gui:Destroy()
	end)
end

local function coinPopups()
	local plot = myPlot()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not plot or not root or player:GetAttribute("MatchId") ~= nil then
		return
	end
	for _, pedestal in plot:GetChildren() do
		if not pedestal:IsA("BasePart") or pedestal:GetAttribute("Slot") == nil then
			continue
		end
		local income = pedestal:GetAttribute("Income")
		if type(income) ~= "number" or income <= 0 then
			continue
		end
		if (pedestal.Position - root.Position).Magnitude > POPUP_DISTANCE then
			continue
		end
		local height = tonumber(pedestal:GetAttribute("Height")) or 4
		-- Pequeno desfase entre pedestales para que no salgan todos a la vez
		task.delay(math.random() * 0.8, popup, pedestal, `+{EconomyMath.format(income * POPUP_INTERVAL)}`, height)
	end
end

-- ---------------------------------------------------------------------------
-- Robos: "¡LADRON!" sobre quien te roba y linea guia del ladron a su granja
-- ---------------------------------------------------------------------------

local thiefTags: { [Player]: BillboardGui } = {}

local function updateThiefTags()
	for _, other in Players:GetPlayers() do
		local robbingMe = other ~= player and other:GetAttribute("CarryOwner") == player.UserId
		local character = other.Character
		local head = if character then character:FindFirstChild("Head") :: BasePart? else nil
		local tag = thiefTags[other]
		if robbingMe and head then
			if not tag or not tag.Parent or tag.Adornee ~= head then
				if tag then
					tag:Destroy()
				end
				local gui = Instance.new("BillboardGui")
				gui.Name = "FG_ThiefTag"
				gui.Size = UDim2.fromOffset(150, 40)
				gui.StudsOffset = Vector3.new(0, 6.5, 0)
				gui.AlwaysOnTop = true
				gui.MaxDistance = 1000
				gui.Adornee = head
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundColor3 = Colors.Red
				label.BackgroundTransparency = 0.1
				label.Font = Enum.Font.GothamBlack
				label.TextScaled = true
				label.TextColor3 = Color3.new(1, 1, 1)
				label.Text = "¡LADRÓN!"
				label.Parent = gui
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.3, 0)
				corner.Parent = label
				gui.Parent = player:FindFirstChildOfClass("PlayerGui")
				thiefTags[other] = gui
			end
		elseif tag then
			tag:Destroy()
			thiefTags[other] = nil
		end
	end
	for other, tag in thiefTags do
		if not other.Parent then
			tag:Destroy()
			thiefTags[other] = nil
		end
	end
end

local guide: { Beam: Beam, From: Attachment, To: Attachment }? = nil

local function clearGuide()
	if guide then
		guide.Beam:Destroy()
		guide.From:Destroy()
		guide.To:Destroy()
		guide = nil
	end
end

local function updateGuide(carrying: boolean)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local plot = if carrying then myPlot() else nil
	local home = if plot then plot:GetAttribute("Home") else nil
	if not carrying or not root or typeof(home) ~= "Vector3" then
		clearGuide()
		return
	end
	if guide and guide.From.Parent == root then
		guide.To.WorldPosition = home
		return
	end
	clearGuide()
	local from = Instance.new("Attachment")
	from.Name = "FG_GuideFrom"
	from.Position = Vector3.new(0, -2, 0)
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "FG_GuideTo"
	to.Parent = Workspace.Terrain
	to.WorldPosition = home
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(Colors.Green)
	beam.Transparency = NumberSequence.new(0.25)
	beam.LightEmission = 0.8
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = Workspace.Terrain
	guide = { Beam = beam, From = from, To = to }
end

function FarmController.start()
	-- Cuenta atras del robo
	local gui = UiKit.make("ScreenGui", {
		Name = "RoboUI",
		ResetOnSpawn = false,
		DisplayOrder = 6,
	}, player:WaitForChild("PlayerGui"))
	local carry = UiKit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(380, 54),
		BackgroundColor3 = Colors.Back,
		BackgroundTransparency = 0.1,
		Visible = false,
	}, gui)
	UiKit.corner(carry, 12)
	UiKit.stroke(carry, Colors.Red, 2)
	local carryLabel = UiKit.label(carry, "", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 24),
		Font = Enum.Font.GothamBlack,
	})
	UiKit.label(carry, "¡Llévalo a tu granja siguiendo la línea verde! Si su dueño te alcanza, lo recupera", {
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 14),
		TextColor3 = Colors.Muted,
	})

	-- Diagnostico (solo Studio): comprueba que tu personaje se ve como su brainrot en el partido
	local reportedMatch: any = nil
	local function checkOwnLook()
		local matchId = player:GetAttribute("MatchId")
		if not RunService:IsStudio() or matchId == nil or matchId == 0 or reportedMatch == matchId
			or Balance.Match.PlayerLook ~= "Brainrot" then
			return
		end
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not character or not root then
			return
		end
		reportedMatch = matchId
		local visual = character:FindFirstChild("BrainrotVisual")
		if not visual or not visual:IsA("Model") or not visual.PrimaryPart then
			warn("[Brainrot] Tu personaje no tiene modelo de brainrot en este partido")
			return
		end
		local offset = (visual.PrimaryPart :: BasePart).Position - root.Position
		local transparentParts = 0
		for _, d in visual:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Root" and (d.Transparency >= 1 or d.LocalTransparencyModifier >= 1) then
				transparentParts += 1
			end
		end
		print(`[Brainrot] Tu brainrot: {visual.Name}, desplazado {math.floor(offset.Y * 10) / 10} en altura y {math.floor(Vector3.new(offset.X, 0, offset.Z).Magnitude * 10) / 10} en horizontal, {transparentParts} piezas invisibles`)
	end

	startAnimations()

	local promptTimer = 0
	local lookTimer = 0
	local popupTimer = 0
	local start = os.clock()
	local carryText = ""
	-- Robo en curso (atributo del jugador): se lee solo cuando cambia
	local carryUntil: number? = nil
	local function readCarry()
		local value = player:GetAttribute("CarryUntil")
		carryUntil = if type(value) == "number" then value else nil
	end
	readCarry()
	player:GetAttributeChangedSignal("CarryUntil"):Connect(readCarry)
	RunService.RenderStepped:Connect(function(dt)
		promptTimer += dt
		lookTimer += dt
		popupTimer += dt
		if lookTimer > 3 then
			lookTimer = 0
			checkOwnLook()
		end
		local carrying = carryUntil ~= nil
		if promptTimer > 0.3 then
			promptTimer = 0
			updatePrompts()
			updateThiefTags()
			updateGuide(carrying)
		end
		if popupTimer > POPUP_INTERVAL then
			popupTimer = 0
			coinPopups()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			local t = os.clock() - start
			local cameraPos = camera.CFrame.Position
			animateFarm(t, cameraPos)
			animateLasers(t, dt, cameraPos)
			animateConveyors(t, cameraPos)
		end
		if next(matchEntries) ~= nil then
			animateMatch(dt)
		end
		if carrying then
			local left = math.max(0, (carryUntil :: number) - Workspace:GetServerTimeNow())
			local text = `{player:GetAttribute("CarryName") or "Brainrot"} · {math.ceil(left)} s`
			if text ~= carryText then
				carryText = text
				carryLabel.Text = text
			end
		end
		if carry.Visible ~= carrying then
			carry.Visible = carrying
		end
	end)
end

return FarmController
