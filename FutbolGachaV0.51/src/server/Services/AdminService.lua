--!strict
--[[
	AdminService: panel de administrador del juego publicado (en el cliente: AdminPanel).
	Solo para el creador del juego (y los UserId de Economy.Admins); en Studio, para todos. TODO se comprueba aqui,
	en el servidor: aunque alguien trucara su cliente, sin permiso no puede hacer nada.
	Regala a cualquier jugador de ESTE servidor: gemas, monedas, un brainrot (variante y nivel), un vehiculo o cajas
	(se abren solas con la ruleta). Cada regalo se escribe en la Salida del servidor ([Admin] ...).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local AdminService = {}

local MAX_GEMS = 10000000 -- por regalo
local MAX_COINS = 1e12

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Economy.Admins, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function notify(player: Player, text: string, extra: any?)
	Remotes.get("Notify"):FireClient(player, "Reward", text, extra)
end

local function fail(text: string): any
	return { Ok = false, Error = text }
end

local function amountOf(value: any, max: number): number?
	local n = tonumber(value)
	if not n or n ~= n then
		return nil
	end
	n = math.floor(n)
	if n < 1 then
		return nil
	end
	return math.min(n, max)
end

-- Que hace cada regalo. Devuelve el texto para el administrador (o un error).
local function give(admin: Player, target: Player, kind: string, a: any, b: any, c: any): any
	local data = DataService.get(target)
	if not data then
		return fail("Sus datos aún no han cargado")
	end
	local what: string
	if kind == "Gems" then
		local n = amountOf(a, MAX_GEMS)
		if not n then
			return fail("Cantidad no válida")
		end
		data.Gems += n
		DataService.changed(target, true)
		notify(target, `🎁 ¡Regalo del creador! +{EconomyMath.format(n)} gemas`, { Gems = n })
		what = `{EconomyMath.format(n)} gemas`
	elseif kind == "Coins" then
		local n = amountOf(a, MAX_COINS)
		if not n then
			return fail("Cantidad no válida")
		end
		data.Coins += n
		DataService.changed(target, true)
		notify(target, `🎁 ¡Regalo del creador! +{EconomyMath.format(n)} monedas`, { Coins = n })
		what = `{EconomyMath.format(n)} monedas`
	elseif kind == "Brainrot" then
		local entry = if type(a) == "string" then Brainrots.ById[a] else nil
		if not entry then
			return fail("Ese brainrot no existe")
		end
		local variant = if type(b) == "string" and Brainrots.VariantById[b] then b else "Normal"
		local level = math.clamp(math.floor(tonumber(c) or 1), 1, Economy.Brainrot.MaxLevel)
		local uid = DataService.addBrainrot(data, entry.Id, level, variant)
		if not uid then
			return fail("Tiene el inventario lleno")
		end
		DataService.placeInFarm(data, uid)
		DataService.changed(target, true)
		local variantText = if variant ~= "Normal" then ` {variant}` else ""
		notify(target, `🎁 ¡Regalo del creador! {entry.Name}{variantText} (nivel {level})`)
		what = `{entry.Name}{variantText} nivel {level}`
	elseif kind == "Vehicle" then
		local vehicle = if type(a) == "string" then Vehicles.ById[a] else nil
		if not vehicle then
			return fail("Ese vehículo no existe")
		end
		if data.Vehicles[vehicle.Id] then
			return fail(`Ya tiene {vehicle.Name}`)
		end
		data.Vehicles[vehicle.Id] = true
		DataService.changed(target, true)
		notify(target, `🎁 ¡Regalo del creador! {vehicle.Emoji} {vehicle.Name} es tuyo (Garaje)`)
		what = vehicle.Name
	elseif kind == "Cases" then
		if type(a) ~= "string" or not EconomyMath.caseById(a) then
			return fail("Esa caja no existe")
		end
		what = EconomyService.giftCases(target, a, tonumber(b) or 1)
	else
		return fail("Acción no válida")
	end
	print(`[Admin] {admin.Name} regala a {target.Name}: {what}`)
	return { Ok = true, Text = `{target.DisplayName}: {what}` }
end

function AdminService.start()
	local function mark(player: Player)
		if isAdmin(player) then
			player:SetAttribute("IsAdmin", true) -- (el cliente ensena el boton; el permiso de verdad se mira aqui)
		end
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end

	local last: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
	Remotes.getFunction("Admin").OnServerInvoke = function(player: Player, action: any, targetId: any, kind: any, a: any, b: any, c: any): any
		if not isAdmin(player) then
			return fail("No tienes permiso")
		end
		local now = os.clock()
		if last[player] and now - last[player] < 0.2 then
			return fail("Más despacio")
		end
		last[player] = now
		if action == "Players" then
			local list = {}
			for _, other in Players:GetPlayers() do
				table.insert(list, { UserId = other.UserId, Name = other.Name, DisplayName = other.DisplayName })
			end
			return { Ok = true, Players = list }
		elseif action == "Give" and type(kind) == "string" then
			local target = if type(targetId) == "number" then Players:GetPlayerByUserId(targetId) else nil
			if not target then
				return fail("Ese jugador ya no está en el servidor")
			end
			return give(player, target, kind, a, b, c)
		end
		return fail("Acción no válida")
	end
	print("[Admin] Panel de administrador listo (solo el creador del juego)")
end

return AdminService
