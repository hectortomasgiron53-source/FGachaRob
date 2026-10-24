--!strict
--[[
	GlobalMatchmaking: la cola online compartida por TODOS los servidores del juego (la usa RankedService).
	- Cada servidor publica sus grupos en la cola global (MemoryStore "FG_Queue", caducan si el servidor deja de
	  refrescarlos).
	- Un solo servidor a la vez hace de "emparejador" (cerrojo en MemoryStore que se renueva cada paso): lee la cola,
	  busca el mejor reparto (el mismo de siempre: mas gente, equipos iguales, copas parecidas) y lo asigna:
	    * si todos los grupos estan en el mismo servidor, ese servidor juega el partido alli mismo (sin viajar);
	    * si no, reserva un servidor nuevo para el partido (TeleportService:ReserveServer), guarda quien juega en
	      que equipo ("FG_Spec", con la clave del servidor reservado) y los manda a todos alli.
	- Cada servidor mira cada paso si sus grupos tienen asignacion ("FG_Assign") y actua.
	- El servidor del partido lee "FG_Spec" al arrancar (RankedService.runMatchServer).
	En Studio (o si MemoryStore falla) no se usa: la cola es la del servidor, como antes.
]]
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Ranked = require(game:GetService("ReplicatedStorage").Shared.Config.Ranked)

local GlobalMatchmaking = {}

export type Hooks = {
	-- Mejor reparto: tamanos y copas medias de los grupos (los mas antiguos primero) -> equipo de cada grupo (0, 1, 2)
	bestSplit: (sizes: { number }, ratings: { number }, oldestWait: number) -> { number }?,
	-- Partido en este mismo servidor con estos grupos locales (y su equipo)
	startLocal: (groupIds: { string }, teams: { number }) -> (),
	-- Viajar a un servidor reservado con este codigo
	teleport: (groupId: string, accessCode: string) -> (),
}

export type LocalGroup = { Id: string, UserIds: { number }, Rating: number, Since: number }

local JOB = if game.JobId ~= "" then game.JobId else "studio"
local QUEUE_TTL = 30 -- segundos que vive una entrada de la cola si su servidor deja de refrescarla
local REFRESH_EVERY = 6
local LOST_AFTER = 15 -- si mi grupo desaparece de la cola y no llega asignacion en este tiempo, se vuelve a publicar
local LOCK_TTL = 8

local queueMap: MemoryStoreSortedMap? = nil
local assignMap: MemoryStoreSortedMap? = nil
local specMap: MemoryStoreSortedMap? = nil
local infoMap: MemoryStoreSortedMap? = nil

local healthy = true
local failures = 0
local warned = false
local globalQueue = 0 -- personas buscando en todo el juego (lo publica el emparejador)

type Published = { At: number, Missing: number? }
local published: { [string]: Published } = {}
type PendingLocal = { Count: number, Groups: { string }, Teams: { number }, Since: number }
local pendingLocal: { [string]: PendingLocal } = {}

function GlobalMatchmaking.isEnabled(): boolean
	return Ranked.Global and healthy and not RunService:IsStudio() and game.PlaceId ~= 0
end

function GlobalMatchmaking.queueCount(): number
	return globalQueue
end

local function maps(): boolean
	if queueMap then
		return true
	end
	local ok = pcall(function()
		queueMap = MemoryStoreService:GetSortedMap("FG_Queue_v1")
		assignMap = MemoryStoreService:GetSortedMap("FG_Assign_v1")
		specMap = MemoryStoreService:GetSortedMap("FG_Spec_v1")
		infoMap = MemoryStoreService:GetSortedMap("FG_Info_v1")
	end)
	return ok and queueMap ~= nil
end

-- Llamada a MemoryStore protegida. Si falla muchas veces seguidas se deja de usar un rato (cola local).
local function call<T>(fn: () -> T): (boolean, T?)
	local ok, result = pcall(fn)
	if ok then
		failures = 0
		return true, result
	end
	failures += 1
	if not warned then
		warned = true
		warn(`[Online] Cola global: {result}`)
	end
	if failures >= 6 and healthy then
		healthy = false
		warn("[Online] La cola global no responde: se usa la del servidor durante 60 s")
		task.delay(60, function()
			healthy = true
			failures = 0
		end)
	end
	return false, nil
end

local function entryOf(group: LocalGroup): any
	return { M = group.UserIds, R = math.floor(group.Rating), T = group.Since, J = JOB }
end

-- Un grupo deja la cola (cancela, se va, empieza otra cosa...)
function GlobalMatchmaking.forget(groupId: string)
	published[groupId] = nil
	if not queueMap then
		return
	end
	task.spawn(function()
		call(function()
			(queueMap :: MemoryStoreSortedMap):RemoveAsync(groupId)
			return true
		end)
	end)
end

-- Publica / refresca mis grupos y mira si tienen asignacion
local function syncGroups(groups: { LocalGroup }, hooks: Hooks)
	local now = os.clock()
	for _, group in groups do
		local state = published[group.Id]
		local qMap = queueMap :: MemoryStoreSortedMap
		local aMap = assignMap :: MemoryStoreSortedMap
		if not state then
			local ok = call(function()
				qMap:SetAsync(group.Id, entryOf(group), QUEUE_TTL)
				return true
			end)
			if ok then
				published[group.Id] = { At = now, Missing = nil }
			end
			continue
		end
		-- Asignacion?
		local okAssign, assignment = call(function()
			return aMap:GetAsync(group.Id)
		end)
		if okAssign and type(assignment) == "table" then
			call(function()
				aMap:RemoveAsync(group.Id)
				return true
			end)
			published[group.Id] = nil
			if assignment.C then
				hooks.teleport(group.Id, assignment.C)
			else
				local key = tostring(assignment.K)
				local pending = pendingLocal[key]
				if not pending then
					pending = { Count = tonumber(assignment.N) or 2, Groups = {}, Teams = {}, Since = now }
					pendingLocal[key] = pending
				end
				local p = pending :: PendingLocal
				table.insert(p.Groups, group.Id)
				table.insert(p.Teams, tonumber(assignment.Team) or 1)
				if #p.Groups >= p.Count then
					pendingLocal[key] = nil
					hooks.startLocal(p.Groups, p.Teams)
				end
			end
			continue
		end
		-- Refrescar (sin volver a crearla si el emparejador ya se la llevo)
		if now - state.At >= REFRESH_EVERY then
			state.At = now
			local okRefresh, value = call(function()
				return qMap:UpdateAsync(group.Id, function(old: any)
					if old == nil then
						return nil
					end
					return entryOf(group)
				end, QUEUE_TTL)
			end)
			if okRefresh and value == nil then
				state.Missing = state.Missing or now
			end
		end
		if state.Missing and now - (state.Missing :: number) > LOST_AFTER then
			published[group.Id] = nil -- se perdio la asignacion: se vuelve a publicar
		end
	end
	-- Partidos locales a medias (uno de los grupos se fue antes de llegar su asignacion): se olvidan
	for key, pending in pendingLocal do
		if now - pending.Since > 10 then
			pendingLocal[key] = nil
		end
	end
end

-- Si este servidor es el emparejador: forma partidos con la cola de todos
local function matchmake(hooks: Hooks)
	local mMap = infoMap :: MemoryStoreSortedMap
	local okLock, lock = call(function()
		return mMap:UpdateAsync("lock", function(old: any)
			if old == nil or old.J == JOB or (tonumber(old.U) or 0) < os.time() then
				return { J = JOB, U = os.time() + LOCK_TTL - 2 }
			end
			return nil
		end, LOCK_TTL)
	end)
	if not okLock or lock == nil then
		-- Otro servidor empareja: solo se lee cuanta gente busca
		local okInfo, info = call(function()
			return mMap:GetAsync("stats")
		end)
		if okInfo and type(info) == "table" then
			globalQueue = tonumber(info.Q) or globalQueue
		end
		return
	end
	local qMap = queueMap :: MemoryStoreSortedMap
	local okRange, entries = call(function()
		return qMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)
	if not okRange or type(entries) ~= "table" then
		return
	end
	local list = {}
	local humans = 0
	for _, entry in entries :: { any } do
		local value = entry.value
		if type(value) == "table" and type(value.M) == "table" then
			table.insert(list, { Key = entry.key, Value = value })
			humans += #value.M
		end
	end
	globalQueue = humans
	call(function()
		mMap:SetAsync("stats", { Q = humans }, 30)
		return true
	end)
	if #list == 0 then
		return
	end
	table.sort(list, function(a, b)
		return (tonumber(a.Value.T) or 0) < (tonumber(b.Value.T) or 0)
	end)
	local considered = {}
	local sizes, ratings = {}, {}
	for i = 1, math.min(#list, Ranked.MaxGroupsConsidered) do
		considered[i] = list[i]
		sizes[i] = #list[i].Value.M
		ratings[i] = tonumber(list[i].Value.R) or Ranked.StartRating
	end
	local oldestWait = os.time() - (tonumber(considered[1].Value.T) or os.time())
	local split = hooks.bestSplit(sizes, ratings, oldestWait)
	if not split then
		return
	end
	local inMatch = 0
	for i, team in split do
		if team ~= 0 then
			inMatch += sizes[i]
		end
	end
	if inMatch < Ranked.MaxPerTeam * 2 and oldestWait < Ranked.FillSeconds then
		return -- aun se espera a que entre mas gente
	end

	-- Se quitan de la cola (si alguno ya no esta, se cancela y se reintenta en el siguiente paso)
	local chosen = {}
	for i, team in split do
		if team ~= 0 then
			table.insert(chosen, { Key = considered[i].Key, Value = considered[i].Value, Team = team })
		end
	end
	local removed = {}
	for _, c in chosen do
		local ok = call(function()
			qMap:RemoveAsync(c.Key)
			return true
		end)
		if not ok then
			for _, r in removed do
				call(function()
					qMap:SetAsync(r.Key, r.Value, QUEUE_TTL)
					return true
				end)
			end
			return
		end
		table.insert(removed, c)
	end

	local matchKey = HttpService:GenerateGUID(false)
	local sameServer = true
	for _, c in chosen do
		if c.Value.J ~= chosen[1].Value.J then
			sameServer = false
		end
	end
	local aMap = assignMap :: MemoryStoreSortedMap
	if sameServer then
		for _, c in chosen do
			call(function()
				aMap:SetAsync(c.Key, { K = matchKey, N = #chosen, Team = c.Team }, 120)
				return true
			end)
		end
		print(`[Online] Partido global en un mismo servidor ({inMatch} personas)`)
		return
	end

	-- Servidor nuevo para el partido
	local okReserve, code, privateId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not okReserve or type(code) ~= "string" then
		warn(`[Online] No se pudo reservar un servidor: {code}`)
		for _, c in chosen do
			call(function()
				qMap:SetAsync(c.Key, c.Value, QUEUE_TTL)
				return true
			end)
		end
		return
	end
	local teams: { { number } } = { {}, {} }
	local origins: { [string]: string } = {}
	for _, c in chosen do
		for _, userId in c.Value.M do
			table.insert(teams[c.Team], userId)
			origins[tostring(userId)] = c.Value.J
		end
	end
	call(function()
		(specMap :: MemoryStoreSortedMap):SetAsync(tostring(privateId), { Teams = teams, Origins = origins }, 1800)
		return true
	end)
	for _, c in chosen do
		call(function()
			aMap:SetAsync(c.Key, { K = matchKey, C = code }, 120)
			return true
		end)
	end
	print(`[Online] Partido global entre servidores: {#teams[1]} vs {#teams[2]}`)
end

-- Un paso (lo llama RankedService cada segundo; aqui se hace el trabajo cada GlobalTick)
local lastStep = 0
function GlobalMatchmaking.step(groups: { LocalGroup }, hooks: Hooks)
	if os.clock() - lastStep < Ranked.GlobalTick then
		return
	end
	lastStep = os.clock()
	if not maps() then
		return
	end
	syncGroups(groups, hooks)
	matchmake(hooks)
end

-- ---------------------------------------------------------------------------
-- Servidor del partido
-- ---------------------------------------------------------------------------

-- true si este servidor es uno reservado para un partido online
function GlobalMatchmaking.isMatchServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- Quien juega y en que equipo (o nil si no se encuentra)
function GlobalMatchmaking.loadSpec(): { Teams: { { number } }, Origins: { [string]: string } }?
	if not maps() then
		return nil
	end
	for _ = 1, 8 do
		local ok, spec = call(function()
			return (specMap :: MemoryStoreSortedMap):GetAsync(game.PrivateServerId)
		end)
		if ok and type(spec) == "table" and type(spec.Teams) == "table" then
			return spec
		end
		task.wait(1.5)
	end
	return nil
end

return GlobalMatchmaking
