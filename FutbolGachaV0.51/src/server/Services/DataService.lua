--!strict
--[[
	DataService: los datos guardados de cada jugador (DataStore).
	- Carga al entrar (con bloqueo de sesion para que no se duplique nada entre dos servidores), guarda cada
	  Economy.Data.AutosaveSeconds, al salir y al cerrar el servidor.
	- Si el DataStore no esta disponible (Studio sin "Enable Studio Access to API Services"), juega con datos
	  temporales y lo avisa en la Salida.
	- Aqui viven tambien las operaciones basicas sobre los datos (anadir / quitar brainrots, colocarlos en la granja,
	  el equipo). La logica de juego (cajas, precios, robos...) esta en EconomyService y FarmService.
	- Publica al cliente: Attributes del jugador (Coins, Gems, Level, XP) para lo que cambia a menudo, y el remote
	  "Data" con una foto completa cuando cambian los brainrots, la granja o el equipo.
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ranked = require(ReplicatedStorage.Shared.Config.Ranked)

local DataService = {}

export type BrainrotRecord = { Id: string, Level: number, Variant: string, Got: number }
export type PvpStats = { Rating: number, Best: number, Wins: number, Losses: number, Draws: number, Streak: number, Mvps: number, Played: number }
export type Data = {
	Version: number,
	Coins: number,
	Gems: number,
	Level: number,
	XP: number,
	NextUid: number,
	Brainrots: { [string]: BrainrotRecord },
	Farm: { [string]: string }, -- "1".."10" -> uid
	Team: { string }, -- 4 uids ("" = vacio). 1 Delantero (tu), 2 Medio, 3 Defensa, 4 Portero
	Daily: { LastDay: number, Streak: number },
	LastSeen: number,
	Stats: { [string]: number },
	Purchases: { string },
	Codes: { [string]: number }, -- codigos promocionales ya canjeados (codigo -> cuando)
	Vehicles: { [string]: boolean }, -- vehiculos comprados (Vehicles.lua)
	Vehicle: string, -- vehiculo elegido ("" = ninguno)
	Pvp: PvpStats, -- partidos online (Ranked.lua): copas, victorias, racha...
	Offers: { [string]: number }, -- ofertas de Robux de pago unico ya compradas (Economy.Offers: nombre -> cuando)
	Joined: number, -- primera vez que entro (os.time): el pack de bienvenida dura unos dias desde aqui
	Tutorial: number, -- paso del tutorial (0 = sin empezar, 100 = terminado)
	Session: any,
}

type Profile = {
	Data: Data,
	Dirty: boolean,
	Saving: boolean,
	Temporary: boolean, -- datos sin guardar (DataStore no disponible)
	CoinFraction: number, -- decimales de las monedas por segundo (no se guardan)
	PushQueued: boolean,
}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, Data, boolean, number) -> () } = {}
local changedCallbacks: { (Player, Data) -> () } = {}
local releasedCallbacks: { (Player) -> () } = {}
local store: DataStore? = nil
local storeWarned = false
local DataEvent = Remotes.get("Data")

local SESSION_TIMEOUT = 300 -- un bloqueo de sesion de hace mas de 5 minutos se considera abandonado

local function defaultPvp(): PvpStats
	return { Rating = Ranked.StartRating, Best = Ranked.StartRating, Wins = 0, Losses = 0, Draws = 0, Streak = 0, Mvps = 0, Played = 0 }
end

local function defaultData(): Data
	return {
		Version = Economy.Data.Version,
		Coins = Economy.Start.Coins,
		Gems = Economy.Start.Gems,
		Level = 1,
		XP = 0,
		NextUid = 1,
		Brainrots = {},
		Farm = {},
		Team = { "", "", "", "" },
		Daily = { LastDay = -1, Streak = 0 },
		LastSeen = 0,
		Stats = {},
		Purchases = {},
		Codes = {},
		Vehicles = {},
		Vehicle = "",
		Pvp = defaultPvp(),
		Offers = {},
		Joined = os.time(),
		Tutorial = 0,
		Session = nil,
	}
end

-- Rellena lo que falte (datos de versiones anteriores) y limpia lo que ya no existe
local function reconcile(raw: any): Data
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	for key, value in raw do
		if (data :: any)[key] ~= nil and type(value) == type((data :: any)[key]) then
			(data :: any)[key] = value
		end
	end
	data.Session = raw.Session
	-- Datos de la economia antigua (V0.6x y anteriores): monedas y gemas x10 para que valgan lo mismo con los precios nuevos
	if data.Version < 2 then
		data.Coins = math.floor(data.Coins * Economy.Data.MigrateV1Factor)
		data.Gems = math.floor(data.Gems * Economy.Data.MigrateV1Factor)
	end
	data.Version = Economy.Data.Version
	-- Brainrots que ya no estan en el catalogo: fuera
	for uid, record in data.Brainrots do
		if type(record) ~= "table" or not Brainrots.ById[record.Id] then
			data.Brainrots[uid] = nil
		else
			record.Level = math.clamp(math.floor(tonumber(record.Level) or 1), 1, Economy.Brainrot.MaxLevel)
			record.Variant = if Brainrots.VariantById[record.Variant] then record.Variant else "Normal"
			record.Got = tonumber(record.Got) or 0
		end
	end
	for slot, uid in data.Farm do
		local n = tonumber(slot)
		if not data.Brainrots[uid] or not n or n < 1 or n > Economy.Farm.Slots then
			data.Farm[slot] = nil
		end
	end
	for i = 1, 4 do
		local uid = data.Team[i]
		if type(uid) ~= "string" or (uid ~= "" and not data.Brainrots[uid]) then
			data.Team[i] = ""
		end
	end
	data.Team[4] = "" -- el portero ya no se elige (es siempre el mismo)
	-- Jugadores de antes del tutorial: ya saben jugar
	if raw.Tutorial == nil then
		data.Tutorial = 100
	end
	if type(data.Daily.LastDay) ~= "number" then
		data.Daily = { LastDay = -1, Streak = 0 }
	end
	-- Partidos online: lo que falte, por defecto
	local pvp = defaultPvp()
	for key, value in pvp do
		local saved = (data.Pvp :: any)[key]
		local pvpAny: any = pvp
		pvpAny[key] = if type(saved) == "number" and saved == saved then saved else value
	end
	data.Pvp = pvp
	return data
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Economy.Data.StoreName)
	end)
	if ok then
		store = result
		return result
	end
	return nil
end

local function keyOf(player: Player): string
	return `u_{player.UserId}`
end

local function warnStore(reason: any)
	if not storeWarned then
		storeWarned = true
		warn(`[Datos] No se puede usar el DataStore ({reason}). Se juega con datos TEMPORALES (no se guardan).`
			.. " En Studio: Game Settings > Security > Enable Studio Access to API Services.")
	end
end

-- ---------------------------------------------------------------------------
-- Publicar al cliente
-- ---------------------------------------------------------------------------

local function setLeaderstat(player: Player, name: string, value: number)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "leaderstats"
		f.Parent = player
		folder = f
	end
	local stat = (folder :: Instance):FindFirstChild(name)
	if not stat then
		local v = Instance.new("StringValue")
		v.Name = name
		v.Parent = folder
		stat = v
	end
	(stat :: StringValue).Value = if name == "Monedas" then EconomyMath.format(value) else tostring(math.floor(value))
end

local function publishAttributes(player: Player, data: Data)
	player:SetAttribute("Coins", math.floor(data.Coins))
	player:SetAttribute("Gems", math.floor(data.Gems))
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPNeed", EconomyMath.xpForLevel(data.Level))
	setLeaderstat(player, "Nivel", data.Level)
	setLeaderstat(player, "Monedas", data.Coins)
	player:SetAttribute("Rating", math.floor(data.Pvp.Rating))
	setLeaderstat(player, "Copas", data.Pvp.Rating)
end

-- Ingresos por segundo de la granja (lo calcula EconomyService; aqui solo se publica)
local incomeOf: (Player, Data) -> number = function()
	return 0
end
function DataService.setIncomeFunction(fn: (Player, Data) -> number)
	incomeOf = fn
end

function DataService.snapshot(player: Player): any
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local data = profile.Data
	local today = EconomyMath.dayIndex(os.time())
	local brainrots = {}
	for uid, record in data.Brainrots do
		brainrots[uid] = { Id = record.Id, Level = record.Level, Variant = record.Variant, Got = record.Got }
	end
	local farm = {}
	for slot, uid in data.Farm do
		farm[slot] = uid
	end
	return {
		Coins = math.floor(data.Coins),
		Gems = math.floor(data.Gems),
		Level = data.Level,
		XP = data.XP,
		XPNeed = EconomyMath.xpForLevel(data.Level),
		Brainrots = brainrots,
		Farm = farm,
		Team = table.clone(data.Team),
		Daily = {
			Streak = data.Daily.Streak,
			CanClaim = data.Daily.LastDay ~= today,
			NextDay = DataService.nextDailyDay(data),
			SecondsLeft = (today + 1) * 86400 + Economy.DailyResetHourUTC * 3600 - os.time(),
		},
		Income = incomeOf(player, data),
		Vehicles = table.clone(data.Vehicles),
		Vehicle = data.Vehicle,
		Pvp = table.clone(data.Pvp),
		Offers = table.clone(data.Offers),
		StarterUntil = data.Joined + Economy.Offers.Starter.Days * 86400,
		Tutorial = data.Tutorial,
		Temporary = profile.Temporary,
	}
end

-- Dia de la racha que tocaria cobrar ahora (1..7)
function DataService.nextDailyDay(data: Data): number
	local today = EconomyMath.dayIndex(os.time())
	if data.Daily.LastDay == today then
		return data.Daily.Streak
	end
	if data.Daily.LastDay == today - 1 then
		return (data.Daily.Streak % #Economy.Daily) + 1
	end
	return 1
end

local function pushSnapshot(player: Player)
	local profile = profiles[player]
	if not profile or profile.PushQueued then
		return
	end
	profile.PushQueued = true
	task.defer(function()
		profile.PushQueued = false
		if profiles[player] == profile and player.Parent then
			DataEvent:FireClient(player, DataService.snapshot(player))
		end
	end)
end

-- Avisa de un cambio. "full" = tambien cambio el inventario / granja / equipo (foto completa al cliente).
function DataService.changed(player: Player, full: boolean?)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Dirty = true
	publishAttributes(player, profile.Data)
	if full then
		pushSnapshot(player)
		for _, callback in changedCallbacks do
			task.spawn(callback, player, profile.Data)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Acceso
-- ---------------------------------------------------------------------------

function DataService.get(player: Player): Data?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Datos temporales (no se guardan): no se deben cobrar compras con Robux
function DataService.isTemporary(player: Player): boolean
	local profile = profiles[player]
	return profile == nil or profile.Temporary
end

function DataService.players(): { Player }
	local list = {}
	for player in profiles do
		table.insert(list, player)
	end
	return list
end

-- Monedas con decimales (ingresos por segundo): acumula la parte decimal sin guardarla
function DataService.addCoinsFractional(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	local total = profile.CoinFraction + amount
	local whole = math.floor(total)
	profile.CoinFraction = total - whole
	if whole > 0 then
		profile.Data.Coins += whole
		DataService.changed(player)
	end
end

function DataService.onLoaded(callback: (Player, Data, boolean, number) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data, false, 0)
	end
end

function DataService.onChanged(callback: (Player, Data) -> ())
	table.insert(changedCallbacks, callback)
end

function DataService.onReleased(callback: (Player) -> ())
	table.insert(releasedCallbacks, callback)
end

-- ---------------------------------------------------------------------------
-- Operaciones sobre los datos
-- ---------------------------------------------------------------------------

function DataService.countBrainrots(data: Data): number
	local n = 0
	for _ in data.Brainrots do
		n += 1
	end
	return n
end

-- Anade un brainrot. Devuelve su uid (nil si el inventario esta lleno).
function DataService.addBrainrot(data: Data, id: string, level: number?, variant: string?): string?
	if DataService.countBrainrots(data) >= Economy.Brainrot.MaxInventory then
		return nil
	end
	local uid = `b{data.NextUid}`
	data.NextUid += 1
	data.Brainrots[uid] = { Id = id, Level = level or 1, Variant = variant or "Normal", Got = os.time() }
	return uid
end

function DataService.farmSlotOf(data: Data, uid: string): number?
	for slot, other in data.Farm do
		if other == uid then
			return tonumber(slot)
		end
	end
	return nil
end

function DataService.freeFarmSlot(data: Data): number?
	for slot = 1, Economy.Farm.Slots do
		if not data.Farm[tostring(slot)] then
			return slot
		end
	end
	return nil
end

-- Coloca en la granja (en "slot" o en el primer pedestal libre). Devuelve el pedestal o nil.
function DataService.placeInFarm(data: Data, uid: string, slot: number?): number?
	if not data.Brainrots[uid] then
		return nil
	end
	local current = DataService.farmSlotOf(data, uid)
	if current then
		return current
	end
	local target = slot or DataService.freeFarmSlot(data)
	if not target or data.Farm[tostring(target)] then
		return nil
	end
	data.Farm[tostring(target)] = uid
	return target
end

function DataService.removeFromFarm(data: Data, uid: string)
	for slot, other in data.Farm do
		if other == uid then
			data.Farm[slot] = nil
		end
	end
end

-- Quita un brainrot del todo (venta o robo): tambien de la granja y del equipo. Devuelve su ficha.
function DataService.removeBrainrot(data: Data, uid: string): BrainrotRecord?
	local record = data.Brainrots[uid]
	if not record then
		return nil
	end
	data.Brainrots[uid] = nil
	DataService.removeFromFarm(data, uid)
	for i = 1, 4 do
		if data.Team[i] == uid then
			data.Team[i] = ""
		end
	end
	return record
end

function DataService.addStat(data: Data, name: string, amount: number)
	data.Stats[name] = (data.Stats[name] or 0) + amount
end

-- ---------------------------------------------------------------------------
-- Cargar y guardar
-- ---------------------------------------------------------------------------

local function newPlayerData(): Data
	local data = defaultData()
	for i, id in Economy.Start.Brainrots do
		local uid = DataService.addBrainrot(data, id, 1, "Normal")
		if uid then
			data.Farm[tostring(i)] = uid
			if i <= 3 then
				data.Team[i] = uid -- (el puesto 4, portero, es fijo)
			end
		end
	end
	return data
end

local function load(player: Player): (Data, boolean, boolean)
	if RunService:IsStudio() and Economy.Data.ResetInStudio then
		return newPlayerData(), true, true
	end
	local ds = getStore()
	if not ds then
		warnStore("sin DataStore")
		return newPlayerData(), true, true
	end
	local key = keyOf(player)
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	for attempt = 1, 5 do
		local result: any = nil
		local locked = false
		local created = false
		local ok, err = pcall(function()
			(ds :: DataStore):UpdateAsync(key, function(old: any)
				created = false
				locked = false
				local session = if type(old) == "table" then old.Session else nil
				if type(session) == "table" and session.Job ~= jobId and os.time() - (tonumber(session.Time) or 0) < SESSION_TIMEOUT
					and attempt < 5 then
					locked = true
					return nil -- otra sesion lo esta usando: no se toca (se reintenta)
				end
				local value = if type(old) == "table" then old else nil
				result = value
				local copy: any = if value then value else {}
				copy.Session = { Job = jobId, Time = os.time() }
				if not value then
					created = true
					local fresh: any = newPlayerData()
					fresh.Session = copy.Session
					result = fresh
					return fresh
				end
				return copy
			end)
		end)
		if ok and not locked then
			return reconcile(result), created, false
		end
		if not ok then
			-- En Studio sin acceso a la API falla siempre: datos temporales sin esperar. En el juego, se reintenta.
			if RunService:IsStudio() or attempt >= 3 then
				warnStore(err)
				return newPlayerData(), true, true
			end
		end
		task.wait(if locked then 4 else 2)
		if not player.Parent then
			break
		end
	end
	warnStore("no se pudo cargar")
	return newPlayerData(), true, true
end

function DataService.save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or profile.Temporary then
		return true
	end
	if profile.Saving and not release then
		return false
	end
	local ds = getStore()
	if not ds then
		return false
	end
	profile.Saving = true
	local data = profile.Data
	data.LastSeen = os.time()
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	local ok, err = pcall(function()
		(ds :: DataStore):UpdateAsync(keyOf(player), function(old: any)
			if type(old) == "table" and type(old.Session) == "table" and old.Session.Job ~= jobId then
				return nil -- otra sesion se quedo con los datos: no se pisan
			end
			local copy: any = HttpService:JSONDecode(HttpService:JSONEncode(data))
			copy.Session = if release then nil else { Job = jobId, Time = os.time() }
			return copy
		end)
	end)
	profile.Saving = false
	if ok then
		profile.Dirty = false
	else
		warn(`[Datos] No se pudo guardar a {player.Name}: {err}`)
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local data, isNew, temporary = load(player)
	if not player.Parent then
		return
	end
	-- Ganancias mientras no estabas (las calcula EconomyService en su onLoaded con este tiempo)
	local offline = 0
	if not isNew and data.LastSeen > 0 then
		offline = math.clamp(os.time() - data.LastSeen, 0, Economy.Offline.MaxHours * 3600)
	end
	data.LastSeen = os.time()
	profiles[player] = {
		Data = data,
		Dirty = isNew,
		Saving = false,
		Temporary = temporary,
		CoinFraction = 0,
		PushQueued = false,
	}
	publishAttributes(player, data)
	player:SetAttribute("DataLoaded", true)
	print(`[Datos] {player.Name}: datos cargados{if temporary then " (TEMPORALES)" else ""}{if isNew then ", cuenta nueva" else ""}`)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data, isNew, offline)
	end
	pushSnapshot(player)
end

local function onPlayerRemoving(player: Player)
	if not profiles[player] then
		return
	end
	for _, callback in releasedCallbacks do
		local ok, err = pcall(function()
			callback(player)
		end)
		if not ok then
			warn(`[Datos] Error al liberar a {player.Name}: {err}`)
		end
	end
	DataService.save(player, true)
	profiles[player] = nil
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- El cliente pide su foto al arrancar (por si llego antes que su controlador)
	DataEvent.OnServerEvent:Connect(function(player: Player)
		if profiles[player] then
			pushSnapshot(player)
		end
	end)

	-- Autoguardado
	task.spawn(function()
		while true do
			task.wait(Economy.Data.AutosaveSeconds)
			for player, profile in profiles do
				if profile.Dirty then
					task.spawn(DataService.save, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				for _, callback in releasedCallbacks do
					pcall(callback, player)
				end
				DataService.save(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
