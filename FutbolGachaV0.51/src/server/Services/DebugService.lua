--!strict
--[[
	DebugService: comandos de prueba. SOLO funcionan dentro de Roblox Studio.
	En el juego publicado este servicio no hace nada (y el panel de pruebas del cliente no aparece).
	- En partido: gol, tiempo, terminar, balon al centro (atajos Y, U, I, O, P).
	- En cualquier sitio (panel "Pruebas" del cliente): monedas, gemas, brainrots, niveles y velocidad.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Ranked = require(ReplicatedStorage.Shared.Config.Ranked)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local BrainrotModel = require(ReplicatedStorage.Shared.Util.BrainrotModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local DebugService = {}

local NORMAL_SPEED = 16

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, "Reward", `[Pruebas] {text}`)
end

-- Velocidad fuera de partido (en partido manda Balance.Speed). Se mantiene al reaparecer.
local function applySpeed(player: Player)
	local factor = tonumber(player:GetAttribute("DebugSpeed")) or 1
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local inMatch = player:GetAttribute("MatchId") ~= nil and player:GetAttribute("MatchId") ~= 0
	if humanoid and not inMatch then
		humanoid.WalkSpeed = NORMAL_SPEED * factor
	end
end

-- ---------------------------------------------------------------------------
-- Revisar el giro de los modelos 3D propios (ReplicatedStorage > BrainrotModels)
-- Pone todos en fila delante de ti, MIRANDOTE. Los que te den la espalda o esten de lado estan mal: pulsa "Girar
-- 90°" en ellos hasta que te miren de frente. Cada vez se escribe en la Salida la tabla ModelYaw corregida.
-- ---------------------------------------------------------------------------
local reviewModel: Model? = nil
local extraYaw: { [string]: number } = {}

local function printYaws()
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local lines = {}
	for _, source in if folder then folder:GetChildren() else {} do
		local id = source.Name
		if Brainrots.ById[id] then
			local yaw = ((Brainrots.ModelYaw[id] or 0) + (extraYaw[id] or 0)) % 360
			table.insert(lines, `\t{id} = {yaw},`)
		end
	end
	table.sort(lines)
	print("[Giros] Copia esto y pasaselo a Claude (o cambialo en Brainrots.lua > ModelYaw):\nlocal ModelYaw = {\n"
		.. table.concat(lines, "\n") .. "\n}")
end

local function reviewModels(player: Player, show: boolean)
	if reviewModel then
		reviewModel:Destroy()
		reviewModel = nil
	end
	if not show then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not root or not folder then
		notify(player, "No hay modelos en ReplicatedStorage > BrainrotModels")
		return
	end
	local ids = {}
	for _, source in folder:GetChildren() do
		if Brainrots.ById[source.Name] then
			table.insert(ids, source.Name)
		end
	end
	table.sort(ids)
	local holder = Instance.new("Model")
	holder.Name = "RevisarGiros"
	holder.Parent = workspace
	reviewModel = holder
	local eye = root.Position
	local ground = eye.Y - 3
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
	for i, id in ids do
		local position = eye + flatLook * 20 + right * ((i - (#ids + 1) / 2) * 9)
		position = Vector3.new(position.X, ground, position.Z)
		local ok, model = pcall(BrainrotModel.build, id, "Normal", 5)
		if not ok then
			warn(`[Giros] No se pudo crear {id}: {model}`)
			continue
		end
		local base = model.PrimaryPart :: BasePart
		base.Anchored = true
		-- Mirando hacia ti: los que estan bien te miran de frente
		model:PivotTo(CFrame.lookAt(position, Vector3.new(eye.X, ground, eye.Z)))
		model.Parent = holder
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(220, 46)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
		tag.AlwaysOnTop = true
		tag.Adornee = base
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(20, 32, 78)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		local function refresh()
			label.Text = `{Brainrots.ById[id].Name}\ngiro {((Brainrots.ModelYaw[id] or 0) + (extraYaw[id] or 0)) % 360}`
		end
		refresh()
		label.Parent = tag
		tag.Parent = base
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Girar 90°"
		prompt.ObjectText = Brainrots.ById[id].Name
		prompt.MaxActivationDistance = 30
		prompt.RequiresLineOfSight = false
		prompt.Parent = base
		prompt.Triggered:Connect(function()
			extraYaw[id] = ((extraYaw[id] or 0) + 90) % 360
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
			refresh()
			printYaws()
		end)
	end
	notify(player, "Los que te miran de frente están bien. A los demás, pulsa E (Girar 90°) hasta que te miren")
	printYaws()
end

-- Comandos de economia (funcionan en cualquier sitio)
local function economyCommand(player: Player, command: string, value: any): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	if command == "Coins" and type(value) == "number" then
		data.Coins += math.max(0, value)
		DataService.changed(player, true)
		notify(player, `+{EconomyMath.format(value)} monedas`)
	elseif command == "Gems" and type(value) == "number" then
		data.Gems += math.max(0, value)
		DataService.changed(player, true)
		notify(player, `+{EconomyMath.format(value)} gemas`)
	elseif command == "Brainrot" and type(value) == "string" and Brainrots.ByRarity[value] then
		local pool = Brainrots.ByRarity[value]
		if #pool == 0 then
			return true
		end
		local entry = pool[math.random(1, #pool)]
		local uid = DataService.addBrainrot(data, entry.Id, 1, "Normal")
		if not uid then
			notify(player, "Inventario lleno")
			return true
		end
		DataService.placeInFarm(data, uid)
		DataService.changed(player, true)
		notify(player, `Nuevo brainrot: {entry.Name} ({entry.Rarity})`)
	elseif command == "LevelFarm" and type(value) == "number" then
		-- Sube (gratis) los brainrots de tu granja: sirve para ver las evoluciones (nivel 50 y 90)
		local count = 0
		for _, uid in data.Farm do
			local record = data.Brainrots[uid]
			if record then
				record.Level = math.clamp(record.Level + math.floor(value), 1, Economy.Brainrot.MaxLevel)
				count += 1
			end
		end
		DataService.changed(player, true)
		notify(player, `{count} brainrots de tu granja +{value} niveles`)
	elseif command == "AccountLevel" and type(value) == "number" then
		-- Sube (gratis, sin recompensas) el nivel de tu CUENTA: sirve para probar los vehiculos de cada escalon
		local target = if value >= 1000 then 100 else data.Level + math.floor(value)
		data.Level = math.clamp(target, 1, 1000)
		data.XP = 0
		DataService.changed(player, true)
		notify(player, `Nivel de cuenta {data.Level}`)
	elseif command == "Rating" and type(value) == "number" then
		-- Copas de los partidos online (para ver los rangos). 0 = volver a las de inicio
		local pvp = data.Pvp
		pvp.Rating = if value == 0 then Ranked.StartRating else math.max(0, pvp.Rating + math.floor(value))
		pvp.Best = math.max(pvp.Best, pvp.Rating)
		DataService.changed(player, true)
		notify(player, `{pvp.Rating} copas ({Ranked.label(pvp.Rating)})`)
	elseif command == "ReviewModels" then
		reviewModels(player, value ~= -1)
	elseif command == "Speed" and type(value) == "number" then
		player:SetAttribute("DebugSpeed", math.clamp(value, 0.5, 10))
		applySpeed(player)
		notify(player, `Velocidad x{value}`)
	else
		return false
	end
	return true
end

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end
	Remotes.get("Debug").OnServerEvent:Connect(function(player: Player, command: any, value: any)
		if type(command) ~= "string" then
			return
		end
		if economyCommand(player, command, value) then
			return
		end
		local match = MatchService.getMatchOf(player)
		if not match then
			return
		end
		if command == "Goal" and (value == 1 or value == 2) then
			match:debugGoal(value :: number)
		elseif command == "SetTime" and type(value) == "number" then
			match:debugSetTime(math.clamp(value :: number, 1, 600))
		elseif command == "End" then
			match:debugEnd()
		elseif command == "ResetBall" then
			match:debugResetBall()
		end
	end)

	-- La velocidad de pruebas se mantiene al reaparecer y al volver de un partido
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			applySpeed(player)
		end)
		player:GetAttributeChangedSignal("MatchId"):Connect(function()
			task.wait(0.5)
			applySpeed(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	print("[Debug] Comandos de prueba activos (solo Studio): panel 'Pruebas' abajo a la izquierda")
end

return DebugService
