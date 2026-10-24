--!strict
--[[
	EconomyService: monedas, gemas y brainrots. El servidor decide todo; el cliente solo pide.
	- Remote "Economy" (RemoteFunction): OpenCase, LevelUp, Sell, Place, Unplace, SetTeam, ClaimDaily, Exchange.
	- Ingresos pasivos: cada segundo, los brainrots colocados en tu granja te dan monedas (y algo mientras no estas).
	- Nivel de la cuenta (XP de los partidos) con recompensas de monedas y gemas.
	- Recompensas de partido (las pide MatchService al terminar) y equipo para los partidos.
	- Gemas con Robux (Developer Products, ver Economy.RobuxProducts).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)

local EconomyService = {}

local NotifyEvent = Remotes.get("Notify")
local rng = Random.new()
local lastCall: { [Player]: number } = {}

local function notify(player: Player, kind: string, text: string, extra: any?)
	NotifyEvent:FireClient(player, kind, text, extra)
end

-- Monedas por segundo de la granja de un jugador (sin los que le estan robando en ese momento)
function EconomyService.incomeOf(player: Player, data: DataService.Data): number
	local total = 0
	for _, uid in data.Farm do
		local record = data.Brainrots[uid]
		if record and not FarmService.isBeingStolen(player, uid) then
			total += EconomyMath.income(record)
		end
	end
	return total
end

-- Suma XP y reparte las recompensas de cada nivel nuevo
local function addXP(player: Player, data: DataService.Data, xp: number)
	local level, rest, reached = EconomyMath.addXP(data.Level, data.XP, xp)
	data.Level = level
	data.XP = rest
	for _, newLevel in reached do
		local coins, gems = EconomyMath.levelReward(newLevel)
		data.Coins += coins
		data.Gems += gems
		notify(player, "LevelUp", `¡Nivel {newLevel}!`, { Level = newLevel, Coins = coins, Gems = gems })
	end
end

-- Da recompensas (monedas, gemas, XP)
function EconomyService.grant(player: Player, coins: number, gems: number, xp: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.Coins += coins
	data.Gems += gems
	if xp > 0 then
		addXP(player, data, xp)
	end
	DataService.changed(player, true)
end

-- ---------------------------------------------------------------------------
-- Acciones del cliente
-- ---------------------------------------------------------------------------

local function fail(message: string): any
	return { Ok = false, Error = message }
end

local Actions: { [string]: (Player, DataService.Data, any, any) -> any } = {}

-- Otros servicios (vehiculos) anaden sus acciones al mismo remote "Economy"
function EconomyService.registerAction(name: string, handler: (Player, DataService.Data, any, any) -> any)
	Actions[name] = handler
end

-- Abre "count" cajas a la vez (1 por defecto, como mucho Economy.MaxCasesAtOnce). Los premios buenos (Epico o mejor,
-- u Oro / Diamante) se anuncian a todo el servidor cuando acaba la ruleta (tienda: "Ultimos premios").
local rollCases: (Player, any, any, number) -> { any }

Actions.OpenCase = function(player, data, caseId, count)
	if type(caseId) ~= "string" then
		return fail("Caja no valida")
	end
	local case = EconomyMath.caseById(caseId)
	if not case then
		return fail("Caja no valida")
	end
	local n = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, Economy.MaxCasesAtOnce) else 1
	if data.Gems < case.Price * n then
		return fail("No tienes gemas suficientes")
	end
	if DataService.countBrainrots(data) + n > Economy.Brainrot.MaxInventory then
		return fail("No te caben en el inventario (vende alguno)")
	end
	data.Gems -= case.Price * n
	return { Ok = true, Results = rollCases(player, data, case, n) }
end

-- Saca "n" brainrots de una caja (sin cobrar: eso lo hace quien llama) y avisa al servidor de los buenos
function rollCases(player: Player, data: any, case: any, n: number): { any }
	local results = {}
	local notable = {}
	for _ = 1, n do
		local rarityId = EconomyMath.rollRarity(case, rng:NextNumber())
		local entry = EconomyMath.pickOfRarity(rarityId, rng:NextNumber())
		local variant = EconomyMath.rollVariant(rng:NextNumber())
		local uid = DataService.addBrainrot(data, entry.Id, 1, variant) :: string
		local slot = DataService.placeInFarm(data, uid) -- si hay pedestal libre, directo a la granja
		table.insert(results, { Uid = uid, Id = entry.Id, Rarity = entry.Rarity, Variant = variant, Placed = slot ~= nil })
		if (Brainrots.RarityIndex[entry.Rarity] or 1) >= 3 or variant ~= "Normal" then
			table.insert(notable, { Name = player.DisplayName, Id = entry.Id, Variant = variant, Case = case.Name })
		end
		print(`[Economia] {player.Name} abre {case.Id}: {entry.Name} ({entry.Rarity}, {variant})`)
	end
	DataService.addStat(data, "Opened", n)
	DataService.changed(player, true)
	if #notable > 0 then
		task.delay(Economy.CaseSpinSeconds + 1, function()
			for _, pull in notable do
				NotifyEvent:FireAllClients("Unbox", "", pull)
			end
		end)
	end
	return results
end

-- Sube "count" niveles (1 por defecto, como mucho Brainrot.MaxLevelsPerClick). Si no llegan las monedas para todos,
-- sube los que pueda. Avisa si evoluciona (nivel 50 / 90).
Actions.LevelUp = function(player, data, uid, count)
	local record = if type(uid) == "string" then data.Brainrots[uid] else nil
	if not record then
		return fail("No tienes ese brainrot")
	end
	local wanted = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, Economy.Brainrot.MaxLevelsPerClick) else 1
	local before = EconomyMath.evolutionOf(record.Level)
	local gained = 0
	for _ = 1, wanted do
		local cost = EconomyMath.levelCost(record)
		if not cost then
			if gained == 0 then
				return fail("Ya esta al nivel maximo")
			end
			break
		end
		if data.Coins < cost then
			if gained == 0 then
				return fail("No tienes monedas suficientes")
			end
			break
		end
		data.Coins -= cost
		record.Level += 1
		gained += 1
	end
	local evolved = EconomyMath.evolutionOf(record.Level) > before
	DataService.changed(player, true)
	if evolved then
		print(`[Economia] {player.Name}: {EconomyMath.entryOf(record.Id).Name} evoluciona (nivel {record.Level})`)
	end
	return { Ok = true, Level = record.Level, Gained = gained, Evolved = evolved }
end

Actions.Sell = function(player, data, uid)
	local record = if type(uid) == "string" then data.Brainrots[uid] else nil
	if not record then
		return fail("No tienes ese brainrot")
	end
	if FarmService.isBeingStolen(player, uid) then
		return fail("¡Te lo estan robando!")
	end
	local value = EconomyMath.sellValue(record)
	DataService.removeBrainrot(data, uid)
	data.Coins += value
	DataService.changed(player, true)
	return { Ok = true, Coins = value }
end

Actions.Place = function(player, data, uid, slot)
	if type(uid) ~= "string" or not data.Brainrots[uid] then
		return fail("No tienes ese brainrot")
	end
	local wanted: number? = nil
	if type(slot) == "number" and slot == slot then
		wanted = math.floor(slot)
		if wanted < 1 or wanted > Economy.Farm.Slots then
			return fail("Pedestal no valido")
		end
	end
	if DataService.farmSlotOf(data, uid) then
		return { Ok = true }
	end
	if not DataService.placeInFarm(data, uid, wanted) then
		return fail("No hay pedestales libres en tu granja")
	end
	DataService.changed(player, true)
	return { Ok = true }
end

Actions.Unplace = function(player, data, uid)
	if type(uid) ~= "string" or not data.Brainrots[uid] then
		return fail("No tienes ese brainrot")
	end
	if FarmService.isBeingStolen(player, uid) then
		return fail("¡Te lo estan robando!")
	end
	DataService.removeFromFarm(data, uid)
	DataService.changed(player, true)
	return { Ok = true }
end

-- Pone en la granja los brainrots que mas monedas dan (tantos como pedestales) y quita los peores.
-- Los que se estan robando en ese momento no se tocan.
Actions.AutoFarm = function(player, data)
	local list = {}
	for uid, record in data.Brainrots do
		if not FarmService.isBeingStolen(player, uid) then
			table.insert(list, { Uid = uid, Income = EconomyMath.income(record) })
		end
	end
	table.sort(list, function(a, b)
		if a.Income ~= b.Income then
			return a.Income > b.Income
		end
		return a.Uid < b.Uid
	end)
	local keep: { [string]: boolean } = {}
	for i = 1, math.min(Economy.Farm.Slots, #list) do
		keep[list[i].Uid] = true
	end
	local moved = 0
	for slot, uid in data.Farm do
		if not keep[uid] and not FarmService.isBeingStolen(player, uid) then
			data.Farm[slot] = nil
			moved += 1
		end
	end
	for i = 1, math.min(Economy.Farm.Slots, #list) do
		local uid = list[i].Uid
		if not DataService.farmSlotOf(data, uid) and DataService.placeInFarm(data, uid) then
			moved += 1
		end
	end
	if moved > 0 then
		DataService.changed(player, true)
	end
	return { Ok = true, Moved = moved, Income = EconomyService.incomeOf(player, data) }
end

Actions.SetTeam = function(player, data, slot, uid)
	if type(slot) ~= "number" or slot ~= slot then
		return fail("Puesto no valido")
	end
	local index = math.floor(slot)
	if index < 1 or index > 3 then
		return fail("Puesto no valido (el portero es siempre el mismo)")
	end
	if type(uid) ~= "string" or (uid ~= "" and not data.Brainrots[uid]) then
		return fail("No tienes ese brainrot")
	end
	-- Si ya estaba en otro puesto, se intercambian
	if uid ~= "" then
		for i = 1, 3 do
			if data.Team[i] == uid and i ~= index then
				data.Team[i] = data.Team[index]
			end
		end
	end
	data.Team[index] = uid
	DataService.changed(player, true)
	return { Ok = true }
end

-- Tutorial: guarda hasta que paso has llegado (solo hacia delante; 100 = terminado)
Actions.Tutorial = function(player, data, step)
	if type(step) ~= "number" or step ~= step then
		return fail("Paso no valido")
	end
	data.Tutorial = math.max(data.Tutorial, math.clamp(math.floor(step), 0, 100))
	DataService.changed(player)
	return { Ok = true }
end

-- Tutorial: garantiza las gemas para abrir 5 cajas basicas (solo antes de abrirlas en el tutorial)
Actions.TutorialGems = function(player, data)
	if data.Tutorial > 4 then
		return fail("Ya no hace falta")
	end
	local basic = EconomyMath.caseById("Basica")
	local need = (if basic then basic.Price else 1000) * Economy.MaxCasesAtOnce
	if data.Gems < need then
		data.Gems = need
		DataService.changed(player, true)
	end
	return { Ok = true }
end

Actions.ClaimDaily = function(player, data)
	local today = EconomyMath.dayIndex(os.time())
	if data.Daily.LastDay == today then
		return fail("Ya has cobrado la recompensa de hoy")
	end
	local day = DataService.nextDailyDay(data)
	local reward = Economy.Daily[day]
	data.Daily.LastDay = today
	data.Daily.Streak = day
	data.Coins += reward.Coins
	data.Gems += reward.Gems
	-- Caja gratis de ese dia (si cabe en el inventario)
	local case = if reward.Case then EconomyMath.caseById(reward.Case) else nil
	local results = nil
	if case and DataService.countBrainrots(data) < Economy.Brainrot.MaxInventory then
		results = rollCases(player, data, case, 1)
	end
	DataService.changed(player, true)
	return { Ok = true, Day = day, Coins = reward.Coins, Gems = reward.Gems, Case = if results then case.Id else nil, Results = results }
end

-- Codigo promocional (Economy.Codes): da monedas, gemas y/o un brainrot. Una vez por jugador.
Actions.RedeemCode = function(player, data, code)
	if type(code) ~= "string" or #code == 0 or #code > 40 then
		return fail("Escribe un código")
	end
	local key = string.upper((string.gsub(code, "%s", "")))
	local reward = Economy.Codes[key]
	if not reward then
		return fail("Ese código no existe")
	end
	if reward.Expires and os.time() > reward.Expires then
		return fail("Ese código ha caducado")
	end
	if data.Codes[key] then
		return fail("Ya has canjeado este código")
	end
	local brainrotName: string? = nil
	if reward.Brainrot and Brainrots.ById[reward.Brainrot] then
		local uid = DataService.addBrainrot(data, reward.Brainrot, 1, "Normal")
		if not uid then
			return fail("Tienes el inventario lleno (vende alguno y vuelve a probar)")
		end
		DataService.placeInFarm(data, uid)
		brainrotName = Brainrots.ById[reward.Brainrot].Name
	end
	data.Codes[key] = os.time()
	data.Coins += reward.Coins or 0
	data.Gems += reward.Gems or 0
	DataService.changed(player, true)
	print(`[Economia] {player.Name} canjea el codigo {key}`)
	return { Ok = true, Coins = reward.Coins or 0, Gems = reward.Gems or 0, Brainrot = brainrotName }
end

Actions.Exchange = function(player, data, exchangeId)
	local offer = nil
	for _, candidate in Economy.Exchange do
		if candidate.Id == exchangeId then
			offer = candidate
		end
	end
	if not offer then
		return fail("Oferta no valida")
	end
	-- El precio depende de lo que gana tu granja (Economy.Exchange): nunca sale barato
	local cost = EconomyMath.exchangeCost(offer, data.Level)
	if data.Coins < cost then
		return fail("No tienes monedas suficientes")
	end
	data.Coins -= cost
	data.Gems += offer.Gems
	DataService.changed(player, true)
	return { Ok = true, Gems = offer.Gems }
end

-- ---------------------------------------------------------------------------
-- Partidos
-- ---------------------------------------------------------------------------

export type MatchMember = { Name: string, Stats: { [string]: number }, BrainrotId: string, Variant: string, Level: number }

local function memberOf(record: { Id: string, Level: number, Variant: string }, nameOverride: string?): MatchMember
	local entry = EconomyMath.entryOf(record.Id)
	return {
		Name = nameOverride or entry.Name,
		Stats = EconomyMath.stats(record),
		BrainrotId = record.Id,
		Variant = record.Variant,
		Level = record.Level,
	}
end

local function substitute(slot: number): MatchMember
	-- Hueco vacio en el equipo: un suplente comun (portero si es el puesto 4)
	local statsFrom = if slot == 4 then "talpa_di_fero" else "tim_cheese"
	local member = memberOf({ Id = statsFrom, Level = 1, Variant = "Normal" }, "Suplente")
	member.BrainrotId = "suplente"
	return member
end

-- Portero: SIEMPRE el mismo para todos (no es un brainrot del jugador y no se elige). Usa las estadisticas de un portero
-- Legendario a nivel 1, asi ningun equipo tiene ventaja bajo palos. Se ve como un portero normal (sin brainrot).
local GOALKEEPER_STATS_FROM = "glorbo_fruttodrillo"
local function goalkeeper(): MatchMember
	local member = memberOf({ Id = GOALKEEPER_STATS_FROM, Level = 1, Variant = "Normal" }, "Portero")
	member.BrainrotId = ""
	return member
end

-- Equipo del jugador para un partido (4 puestos: 1 Delantero = el jugador, 2 Medio, 3 Defensa, 4 Portero)
function EconomyService.getMatchTeam(player: Player): { MatchMember }
	local data = DataService.get(player)
	local team: { MatchMember } = {}
	for slot = 1, 4 do
		if slot == 4 then
			team[slot] = goalkeeper()
			continue
		end
		local uid = if data then data.Team[slot] else ""
		local record = if data and uid ~= "" then data.Brainrots[uid] else nil
		team[slot] = if record then memberOf(record) else substitute(slot)
	end
	return team
end

-- Equipo rival de nivel parecido al del jugador
function EconomyService.rivalTeam(team: { MatchMember }): { MatchMember }
	local sumRarity, sumLevel, counted = 0, 0, 0
	for _, member in team do
		if member.BrainrotId == "" then
			continue -- (el portero fijo no cuenta)
		end
		local entry = EconomyMath.entryOf(member.BrainrotId)
		sumRarity += Brainrots.RarityIndex[entry.Rarity] or 1
		sumLevel += member.Level
		counted += 1
	end
	local avgRarity = sumRarity / math.max(1, counted)
	local avgLevel = sumLevel / math.max(1, counted)
	local rival: { MatchMember } = {}
	local used: { [string]: boolean } = {}
	for slot = 1, 4 do
		if slot == 4 then
			rival[slot] = goalkeeper()
			continue
		end
		local index = math.clamp(math.floor(avgRarity + (rng:NextNumber() - 0.5) * 1.3 + 0.5), 1, #Brainrots.Rarities)
		local rarityId = Brainrots.Rarities[index].Id
		local pool = Brainrots.ByRarity[rarityId]
		-- Preferencia: el puesto que toca (portero en el 4) y sin repetir
		local wantRole = if slot == 4 then "Portero" else ({ "Delantero", "Medio", "Defensa" })[slot]
		local candidates = {}
		for _, entry in pool do
			if not used[entry.Id] and entry.Role == wantRole then
				table.insert(candidates, entry)
			end
		end
		if #candidates == 0 then
			for _, entry in pool do
				if not used[entry.Id] then
					table.insert(candidates, entry)
				end
			end
		end
		local entry = if #candidates > 0 then candidates[rng:NextInteger(1, #candidates)] else Brainrots.List[1]
		used[entry.Id] = true
		local level = math.clamp(math.floor(avgLevel + rng:NextNumber(-2, 2) + 0.5), 1, Economy.Brainrot.MaxLevel)
		rival[slot] = memberOf({ Id = entry.Id, Level = level, Variant = "Normal" })
	end
	return rival
end

-- Al terminar un partido (llamado por MatchService / RankedService). "winner": 0 empate, 1 o 2. "team": equipo del
-- jugador. "extra" (online): multiplicadores, gemas de bonus y datos para la pantalla final (copas, MVP...).
export type RewardExtra = { Factor: number?, GemFactor: number?, BonusGems: number?, Info: { [string]: any }? }
function EconomyService.matchFinished(player: Player, winner: number, team: number, goals: number, extra: RewardExtra?)
	local data = DataService.get(player)
	if not data then
		return
	end
	local outcome = if winner == 0 then "Draw" elseif winner == team then "Win" else "Loss"
	local coins, gems, xp = EconomyMath.matchReward(outcome, goals)
	if extra then
		local factor = extra.Factor or 1
		coins = math.floor(coins * factor)
		xp = math.floor(xp * factor)
		gems = math.floor(gems * (extra.GemFactor or 1)) + (extra.BonusGems or 0)
	end
	DataService.addStat(data, "Matches", 1)
	DataService.addStat(data, "Goals", goals)
	if outcome == "Win" then
		DataService.addStat(data, "Wins", 1)
	end
	EconomyService.grant(player, coins, gems, xp)
	local summary: { [string]: any } = { Outcome = outcome, Coins = coins, Gems = gems, XP = xp, Goals = goals }
	if extra and extra.Info then
		for key, value in extra.Info do
			summary[key] = value
		end
	end
	notify(player, "MatchReward", "Recompensa del partido", summary)
end

-- ---------------------------------------------------------------------------
-- Robux
-- ---------------------------------------------------------------------------

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.get(player)
	if not data or (DataService.isTemporary(player) and not RunService:IsStudio()) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- sin datos guardables no se cobra
	end
	local purchaseId = tostring(info.PurchaseId)
	if table.find(data.Purchases, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- ya entregado
	end
	-- Que es: un pack de gemas o una oferta especial (Economy.Offers)
	local gems, coins = 0, 0
	local offerName: string? = nil
	local vehicleId: string? = nil
	local message = ""
	for _, candidate in Economy.RobuxProducts do
		if candidate.ProductId ~= 0 and candidate.ProductId == info.ProductId then
			gems = candidate.Gems
			message = `¡+{candidate.Gems} gemas! Gracias por tu compra`
		end
	end
	for name, offer in Economy.Offers :: { [string]: any } do
		if offer.ProductId ~= 0 and offer.ProductId == info.ProductId then
			offerName = name
			gems = offer.Gems or 0
			coins = offer.Coins or 0
			vehicleId = offer.Vehicle
			message = if vehicleId and Vehicles.ById[vehicleId]
				then `¡{Vehicles.ById[vehicleId].Emoji} {Vehicles.ById[vehicleId].Name} es tuyo! Pulsa V para montar`
				else `¡{offer.Label}! +{EconomyMath.format(gems)} gemas y +{EconomyMath.format(coins)} monedas`
		end
	end
	if message == "" then
		warn(`[Economia] Producto desconocido: {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local hadVehicle = if vehicleId then data.Vehicles[vehicleId] == true else false
	local oldVehicle = data.Vehicle
	data.Gems += gems
	data.Coins += coins
	if vehicleId and Vehicles.ById[vehicleId] then
		data.Vehicles[vehicleId] = true
		data.Vehicle = vehicleId -- recien comprado: elegido
	end
	if offerName then
		data.Offers[offerName] = os.time()
	end
	table.insert(data.Purchases, purchaseId)
	while #data.Purchases > 100 do
		table.remove(data.Purchases, 1)
	end
	DataService.changed(player, true)
	if not RunService:IsStudio() and not DataService.save(player) then
		-- No se pudo guardar: se deshace y Roblox lo volvera a intentar mas tarde
		data.Gems -= gems
		data.Coins -= coins
		if vehicleId then
			data.Vehicles[vehicleId] = if hadVehicle then true else nil
			data.Vehicle = oldVehicle
		end
		if offerName then
			data.Offers[offerName] = nil
		end
		local index = table.find(data.Purchases, purchaseId)
		if index then
			table.remove(data.Purchases, index)
		end
		DataService.changed(player, true)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	notify(player, "Reward", message, { Gems = gems, Coins = coins })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------------------

function EconomyService.start()
	DataService.setIncomeFunction(EconomyService.incomeOf)

	-- Ganancias mientras no estabas
	DataService.onLoaded(function(player, data, _isNew, offlineSeconds)
		if offlineSeconds > 60 then
			local coins = math.floor(EconomyService.incomeOf(player, data) * offlineSeconds * Economy.Offline.Fraction)
			if coins > 0 then
				data.Coins += coins
				DataService.changed(player, true)
				task.delay(3, notify, player, "Reward", `Mientras no estabas tu granja gano {EconomyMath.format(coins)} monedas`, { Coins = coins })
			end
		end
	end)

	-- Ingresos pasivos cada segundo
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in DataService.players() do
				local data = DataService.get(player)
				if data then
					local income = EconomyService.incomeOf(player, data)
					player:SetAttribute("Income", math.floor(income * 10 + 0.5) / 10)
					if income > 0 then
						DataService.addCoinsFractional(player, income)
					end
				end
			end
		end
	end)

	Remotes.getFunction("Economy").OnServerInvoke = function(player: Player, action: any, a: any, b: any): any
		local now = os.clock()
		if lastCall[player] and now - lastCall[player] < 0.12 then
			return fail("Mas despacio")
		end
		lastCall[player] = now
		if type(action) ~= "string" then
			return fail("Accion no valida")
		end
		local handler = Actions[action]
		if not handler then
			return fail("Accion no valida")
		end
		local data = DataService.get(player)
		if not data then
			return fail("Tus datos aun se estan cargando")
		end
		local ok, result = pcall(handler, player, data, a, b)
		if not ok then
			warn(`[Economia] Error en {action} de {player.Name}: {result}`)
			return fail("Error del servidor")
		end
		return result
	end

	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerRemoving:Connect(function(player)
		lastCall[player] = nil
	end)
end

return EconomyService
