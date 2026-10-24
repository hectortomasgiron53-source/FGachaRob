--!strict
--[[
	VehicleService: los vehiculos (Vehicles.lua). Comprar, elegir y montar / bajar.
	- Acciones del remote "Economy": BuyVehicle (id), EquipVehicle (id o "" para ninguno), Ride (true / false / nil =
	  cambiar).
	- Comprar: hace falta el nivel de CUENTA del escalon (cada 25 niveles uno nuevo) y las monedas o gemas.
	- Montar: el modelo se suelda bajo tus pies, te eleva (Lift) y te da su velocidad y su salto. Solo fuera de los
	  partidos. Te bajas solo al empezar un partido o al reaparecer. Para robar un brainrot hay que bajarse.
	- El atributo "Riding" del jugador dice que vehiculo lleva (el cliente lo usa para el boton de montar).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local VehicleModel = require(ReplicatedStorage.Shared.Util.VehicleModel)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local VehicleService = {}

type Ride = {
	Id: string,
	Model: Model,
	Character: Model,
	HipHeight: number,
	WalkSpeed: number,
	UseJumpPower: boolean,
	JumpPower: number,
	JumpHeight: number,
}

local rides: { [Player]: Ride } = {}

local function fail(message: string): any
	return { Ok = false, Error = message }
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function inMatch(player: Player): boolean
	return player:GetAttribute("MatchId") ~= nil -- (tambien el patio de juegos del lobby: alli se juega a pie)
end

-- Bajarse. "restore": devolver la velocidad y el salto de antes (no al entrar a un partido: alli manda el partido)
function VehicleService.dismount(player: Player, restore: boolean)
	local ride = rides[player]
	if not ride then
		return
	end
	rides[player] = nil
	if ride.Model.Parent then
		ride.Model:Destroy()
	end
	player:SetAttribute("Riding", nil)
	local humanoid = humanoidOf(player)
	if humanoid and player.Character == ride.Character then
		humanoid.HipHeight = ride.HipHeight
		if restore then
			humanoid.WalkSpeed = ride.WalkSpeed
			humanoid.UseJumpPower = ride.UseJumpPower
			humanoid.JumpPower = ride.JumpPower
			humanoid.JumpHeight = ride.JumpHeight
		end
	end
end

-- Montar en el vehiculo elegido. Devuelve un error (texto) o nil.
function VehicleService.mount(player: Player): string?
	local data = DataService.get(player)
	if not data then
		return "Tus datos aun se estan cargando"
	end
	local vehicle = Vehicles.ById[data.Vehicle]
	if not vehicle or not data.Vehicles[vehicle.Id] then
		return "Elige un vehículo en el Garaje"
	end
	if inMatch(player) then
		return "No puedes montar durante un partido"
	end
	if player:GetAttribute("CarryUntil") ~= nil then
		return "No puedes montar mientras llevas un brainrot robado"
	end
	local character = player.Character
	local humanoid = humanoidOf(player)
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return "No puedes montar ahora"
	end
	VehicleService.dismount(player, true)
	local model = VehicleModel.build(vehicle.Id)
	if not model or not model.PrimaryPart then
		return "No se pudo crear el vehículo"
	end
	local ride: Ride = {
		Id = vehicle.Id,
		Model = model,
		Character = character,
		HipHeight = humanoid.HipHeight,
		WalkSpeed = humanoid.WalkSpeed,
		UseJumpPower = humanoid.UseJumpPower,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
	}
	-- Te eleva "Lift" studs (HipHeight) y el vehiculo va pegado a la planta de tus pies. La distancia del centro del
	-- cuerpo a los pies NO cambia al elevarte (las piernas miden lo mismo): se mide con las piernas reales y, si no
	-- se encuentran, con la formula (R15 = mitad del tronco + HipHeight de antes; R6 = mitad del tronco + 2).
	local feet = 0
	for _, name in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local bottom = part.CFrame:PointToWorldSpace(Vector3.new(0, -part.Size.Y / 2, 0))
			feet = math.max(feet, root.CFrame:PointToObjectSpace(bottom).Y * -1)
		end
	end
	if feet <= 0 then
		local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
		feet = root.Size.Y / 2 + legs
	end
	humanoid.HipHeight += vehicle.Lift
	local modelRoot = model.PrimaryPart :: BasePart
	model:PivotTo(root.CFrame * CFrame.new(0, -feet, 0)) -- mueve TODAS las piezas, no solo Root
	local weld = Instance.new("Weld")
	weld.Name = "VehicleWeld"
	weld.Part0 = root
	weld.Part1 = modelRoot
	weld.C0 = CFrame.new(0, -feet, 0)
	weld.Parent = modelRoot
	model.Name = "FG_Vehicle"
	model.Parent = character
	humanoid.WalkSpeed = vehicle.Speed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = vehicle.Jump
	rides[player] = ride
	player:SetAttribute("Riding", vehicle.Id)
	return nil
end

function VehicleService.isRiding(player: Player): boolean
	return rides[player] ~= nil
end

function VehicleService.start()
	EconomyService.registerAction("BuyVehicle", function(player, data, id)
		local vehicle = if type(id) == "string" then Vehicles.ById[id] else nil
		if not vehicle then
			return fail("Vehículo no válido")
		end
		if data.Vehicles[vehicle.Id] then
			return fail("Ya lo tienes")
		end
		if vehicle.Currency == "Robux" then
			return fail("Este vehículo se compra con Robux (oferta de lanzamiento)")
		end
		if data.Level < vehicle.Level then
			return fail(`Necesitas nivel {vehicle.Level} de cuenta`)
		end
		if vehicle.Currency == "Gems" then
			if data.Gems < vehicle.Price then
				return fail("No tienes gemas suficientes")
			end
			data.Gems -= vehicle.Price
		else
			if data.Coins < vehicle.Price then
				return fail("No tienes monedas suficientes")
			end
			data.Coins -= vehicle.Price
		end
		data.Vehicles[vehicle.Id] = true
		data.Vehicle = vehicle.Id -- recien comprado: elegido
		DataService.changed(player, true)
		print(`[Vehiculos] {player.Name} compra {vehicle.Name} ({EconomyMath.format(vehicle.Price)} {vehicle.Currency})`)
		if rides[player] then
			VehicleService.mount(player) -- si ya iba montado, cambia al nuevo
		end
		return { Ok = true, Id = vehicle.Id }
	end)

	EconomyService.registerAction("EquipVehicle", function(player, data, id)
		if id == "" then
			data.Vehicle = ""
			VehicleService.dismount(player, true)
			DataService.changed(player, true)
			return { Ok = true }
		end
		if type(id) ~= "string" or not Vehicles.ById[id] or not data.Vehicles[id] then
			return fail("No tienes ese vehículo")
		end
		data.Vehicle = id
		DataService.changed(player, true)
		if rides[player] then
			local err = VehicleService.mount(player)
			if err then
				return fail(err)
			end
		end
		return { Ok = true }
	end)

	EconomyService.registerAction("Ride", function(player, _data, wanted)
		local riding = rides[player] ~= nil
		local on = if type(wanted) == "boolean" then wanted else not riding
		if not on then
			VehicleService.dismount(player, true)
			return { Ok = true, Riding = false }
		end
		local err = VehicleService.mount(player)
		if err then
			return fail(err)
		end
		return { Ok = true, Riding = true }
	end)

	local function watch(player: Player)
		-- Al empezar un partido (o entrar al patio de juegos) te bajas; alli manda el partido
		player:GetAttributeChangedSignal("MatchId"):Connect(function()
			if inMatch(player) then
				VehicleService.dismount(player, false)
			end
		end)
		-- Al reaparecer, el vehiculo se fue con el personaje anterior
		player.CharacterRemoving:Connect(function()
			if rides[player] then
				rides[player] = nil
				player:SetAttribute("Riding", nil)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rides[player] = nil
	end)
	print(`[Vehiculos] {#Vehicles.List} vehiculos en {#Vehicles.Tiers} escalones (niveles {table.concat(Vehicles.Tiers, ", ")})`)
end

return VehicleService
