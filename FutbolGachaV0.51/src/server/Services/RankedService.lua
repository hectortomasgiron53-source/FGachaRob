--!strict
--[[
	RankedService: partidos ONLINE entre jugadores (configuracion en Ranked.lua).
	- Cola: "JUGAR ONLINE" (accion QueueJoin). Cada segundo se buscan las mejores parejas de equipos entre los que
	  esperan: el mayor numero de personas posible, equipos con las mismas personas (con un bot de mas si alguien lleva
	  mucho esperando) y copas parecidas (la diferencia permitida crece con la espera). Cuando ya se puede jugar, se
	  espera FillSeconds a que entre mas gente (o empieza al momento si estan los 6).
	- Grupos de amigos (PartyInvite / PartyRespond / PartyLeave): hasta 3, siempre en el mismo equipo.
	- Copas (Elo) al acabar, recompensas mejores que en practica, MVP, y abandono = derrota (el puesto lo coge un bot).
	- Clasificacion mundial con OrderedDataStore (en Studio sin acceso a la API: la del servidor).
	Al cliente: atributos del jugador (QueueSince, QueueEta, Party, Rating) y de ReplicatedStorage (RankedQueue,
	RankedPlaying); avisos por el remote Notify (PartyInvite, Info...).
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Ranked = require(ReplicatedStorage.Shared.Config.Ranked)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MatchService = require(script.Parent.MatchService)
local GlobalMatchmaking = require(script.Parent.GlobalMatchmaking)

local RankedService = {}

local NotifyEvent = Remotes.get("Notify")
local GOALKEEPER_SLOT = Balance.Match.GoalkeeperSlot

-- Solo en Studio: si llevas un rato solo en la cola, juegas "online" contra un equipo de bots (para probarlo todo
-- sin tener que abrir dos clientes). Las copas se calculan como contra alguien de tus mismas copas.
local STUDIO_SOLO_AFTER = 6

type Group = { Id: string, Members: { Player }, Since: number, SinceUnix: number }
type Party = { Leader: Player, Members: { Player } }
type OnlineMatch = {
	Lineup: { [number]: { Player } },
	Ratings: { [Player]: number }, -- copas de cada humano al empezar
	TeamAvg: { number }, -- copas medias de cada equipo al empezar
	Solo: boolean, -- prueba en Studio sin rival humano
	Left: { [Player]: boolean }, -- abandonos (ya penalizados)
}

local queue: { Group } = {}
local groupOf: { [Player]: Group } = {}
local formingSince: number? = nil
local parties: { [Player]: Party } = {} -- jugador -> su grupo
local invites: { [Player]: { [Player]: number } } = {} -- invitado -> quien invita -> caduca (os.clock)
local onlineOf: { [Player]: OnlineMatch } = {} -- humanos jugando un partido online
local playingCount = 0

local function notify(player: Player, kind: string, text: string, extra: any?)
	if player.Parent then
		NotifyEvent:FireClient(player, kind, text, extra)
	end
end

local function fail(message: string): any
	return { Ok = false, Error = message }
end

local function ratingOf(player: Player): number
	local data = DataService.get(player)
	return if data then data.Pvp.Rating else Ranked.StartRating
end

-- ---------------------------------------------------------------------------
-- Clasificacion mundial
-- ---------------------------------------------------------------------------

type TopEntry = { UserId: number, Name: string, Rating: number }
local orderedStore: OrderedDataStore? = nil
local topList: { TopEntry } = {}
local topGlobal = false -- true si la lista viene del DataStore (si no, es la de este servidor)
local names: { [number]: string } = {}

local function getOrderedStore(): OrderedDataStore?
	if orderedStore then
		return orderedStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Ranked.LeaderboardStore)
	end)
	if ok then
		orderedStore = result
		return result
	end
	return nil
end

local function pushRating(player: Player, rating: number)
	local userId = player.UserId
	task.spawn(function()
		local store = getOrderedStore()
		if store and userId > 0 then
			pcall(function()
				store:SetAsync(tostring(userId), math.floor(rating))
			end)
		end
	end)
end

local function serverTop(): { TopEntry }
	local list: { TopEntry } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			table.insert(list, { UserId = player.UserId, Name = player.DisplayName, Rating = math.floor(data.Pvp.Rating) })
		end
	end
	table.sort(list, function(a, b)
		return a.Rating > b.Rating
	end)
	while #list > Ranked.LeaderboardSize do
		table.remove(list)
	end
	return list
end

local function refreshTop()
	local store = getOrderedStore()
	local ok, entries = false, nil
	if store then
		ok, entries = pcall(function()
			local pages = store:GetSortedAsync(false, Ranked.LeaderboardSize)
			return pages:GetCurrentPage()
		end)
	end
	if not ok or type(entries) ~= "table" or #entries == 0 then
		topList = serverTop()
		topGlobal = false
		return
	end
	local list: { TopEntry } = {}
	for _, entry in entries do
		local userId = tonumber(entry.key) or 0
		local name = names[userId]
		if not name then
			local online = Players:GetPlayerByUserId(userId)
			if online then
				name = online.DisplayName
			else
				local okName, fetched = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				name = if okName then fetched else `#{userId}`
			end
			names[userId] = name :: string
		end
		table.insert(list, { UserId = userId, Name = name :: string, Rating = tonumber(entry.value) or 0 })
	end
	topList = list
	topGlobal = true
end

-- ---------------------------------------------------------------------------
-- Estado publicado (atributos)
-- ---------------------------------------------------------------------------

local function publishCounts()
	local searching = 0
	for _, group in queue do
		searching += #group.Members
	end
	if GlobalMatchmaking.isEnabled() then
		searching = math.max(searching, GlobalMatchmaking.queueCount())
	end
	ReplicatedStorage:SetAttribute("RankedQueue", searching)
	ReplicatedStorage:SetAttribute("RankedPlaying", playingCount)
end

local function publishParty(party: Party?, players: { Player })
	for _, p in players do
		if p.Parent then
			p:SetAttribute("Party", if party then party.Leader.UserId else nil)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Cola
-- ---------------------------------------------------------------------------

-- "matched": se va porque ya tiene partido (no hace falta quitarlo de la cola global: ya no esta)
local function removeGroup(group: Group, matched: boolean?)
	if not matched then
		GlobalMatchmaking.forget(group.Id)
	end
	local index = table.find(queue, group)
	if index then
		table.remove(queue, index)
	end
	for _, p in group.Members do
		if groupOf[p] == group then
			groupOf[p] = nil
		end
		if p.Parent then
			p:SetAttribute("QueueSince", nil)
			p:SetAttribute("QueueEta", nil)
		end
	end
	if #queue == 0 then
		formingSince = nil
	end
	publishCounts()
end

-- Saca de la cola a "player" y a su grupo. "reason": aviso a los demas del grupo.
function RankedService.leaveQueue(player: Player, reason: string?)
	local group = groupOf[player]
	if not group then
		return
	end
	removeGroup(group)
	if reason then
		for _, p in group.Members do
			if p ~= player then
				notify(p, "Info", reason)
			end
		end
	end
end

local function membersOf(player: Player): { Player }
	local party = parties[player]
	return if party then table.clone(party.Members) else { player }
end

local function joinQueue(player: Player): any
	if not Ranked.Enabled then
		return fail("Los partidos online estan desactivados")
	end
	if groupOf[player] then
		return { Ok = true }
	end
	if ReplicatedStorage:GetAttribute("MatchServer") then
		return fail("Estás en el servidor de un partido: al acabar vuelves a tu servidor")
	end
	local party = parties[player]
	if party and party.Leader ~= player then
		return fail(`Solo {party.Leader.DisplayName} (el líder del grupo) puede buscar partido`)
	end
	local members = membersOf(player)
	for _, p in members do
		if not DataService.get(p) then
			return fail(`Los datos de {p.DisplayName} aún se están cargando`)
		end
		if onlineOf[p] or not MatchService.canPlay(p) then
			return fail(if p == player then "Ahora no puedes jugar (¿estás en un partido o llevas un brainrot robado?)"
				else `{p.DisplayName} no puede jugar ahora`)
		end
	end
	local group: Group = { Id = HttpService:GenerateGUID(false), Members = members, Since = os.clock(), SinceUnix = os.time() }
	table.insert(queue, group)
	local since = workspace:GetServerTimeNow()
	for _, p in members do
		groupOf[p] = group
		p:SetAttribute("QueueSince", since)
		p:SetAttribute("QueueEta", 0)
		if p ~= player then
			notify(p, "Info", `{player.DisplayName} busca partido online para vuestro grupo`)
		end
	end
	publishCounts()
	return { Ok = true }
end

-- ---------------------------------------------------------------------------
-- Grupos de amigos
-- ---------------------------------------------------------------------------

local function leaveParty(player: Player, silent: boolean?)
	local party = parties[player]
	if not party then
		return
	end
	RankedService.leaveQueue(player, if silent then nil else "La búsqueda se ha cancelado: el grupo ha cambiado")
	parties[player] = nil
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	publishParty(nil, { player })
	if #party.Members <= 1 then
		-- Grupo de uno: se deshace
		for _, p in party.Members do
			parties[p] = nil
			if not silent then
				notify(p, "Info", `{player.DisplayName} ha dejado el grupo`)
			end
		end
		publishParty(nil, party.Members)
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	publishParty(party, party.Members)
	for _, p in party.Members do
		notify(p, "Info", `{player.DisplayName} ha dejado el grupo. Líder: {party.Leader.DisplayName}`)
	end
end

local function invite(from: Player, userId: any): any
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not target or target == from then
		return fail("Ese jugador ya no está en el servidor")
	end
	local party = parties[from]
	if party and party.Leader ~= from then
		return fail(`Solo {party.Leader.DisplayName} (el líder) puede invitar`)
	end
	if party and table.find(party.Members, target) then
		return fail(`{target.DisplayName} ya está en tu grupo`)
	end
	if party and #party.Members >= Ranked.PartyMax then
		return fail(`El grupo está lleno (máximo {Ranked.PartyMax})`)
	end
	local targetParty = parties[target]
	if targetParty and #targetParty.Members > 1 then
		return fail(`{target.DisplayName} ya está en otro grupo`)
	end
	local pending = invites[target]
	if not pending then
		pending = {}
		invites[target] = pending
	end
	local list = pending :: { [Player]: number }
	if (list[from] or 0) > os.clock() then
		return fail(`Ya has invitado a {target.DisplayName}: espera su respuesta`)
	end
	list[from] = os.clock() + Ranked.InviteSeconds
	notify(target, "PartyInvite", `{from.DisplayName} te invita a su grupo`, {
		From = from.UserId,
		Name = from.DisplayName,
		Rating = math.floor(ratingOf(from)),
		Seconds = Ranked.InviteSeconds,
	})
	return { Ok = true, Name = target.DisplayName }
end

local function respond(player: Player, fromUserId: any, accept: any): any
	local from = if type(fromUserId) == "number" then Players:GetPlayerByUserId(fromUserId) else nil
	local pending = invites[player]
	local expires = if pending and from then pending[from] else nil
	if pending and from then
		pending[from] = nil
	end
	if not from or not expires or expires < os.clock() then
		return fail("La invitación ha caducado")
	end
	if accept ~= true then
		notify(from, "Info", `{player.DisplayName} ha rechazado tu invitación`)
		return { Ok = true }
	end
	if onlineOf[player] or onlineOf[from] then
		return fail("Espera a que acabe el partido")
	end
	local party = parties[from]
	if party and party.Leader ~= from then
		return fail("Esa invitación ya no vale")
	end
	if party and #party.Members >= Ranked.PartyMax then
		return fail("El grupo ya está lleno")
	end
	-- Deja su grupo anterior (y su cola) y entra en el nuevo
	leaveParty(player, true)
	RankedService.leaveQueue(player)
	if not party then
		local newParty: Party = { Leader = from, Members = { from } }
		parties[from] = newParty
		party = newParty
	end
	local p = party :: Party
	RankedService.leaveQueue(from, "La búsqueda se ha cancelado: el grupo ha cambiado")
	table.insert(p.Members, player)
	parties[player] = p
	publishParty(p, p.Members)
	for _, member in p.Members do
		notify(member, "Reward", if member == player then `Te has unido al grupo de {from.DisplayName}`
			else `{player.DisplayName} se ha unido al grupo`)
	end
	return { Ok = true }
end

-- ---------------------------------------------------------------------------
-- Equipos de brainrots (con las estadisticas acercadas a la media: Ranked.StatEqualize)
-- ---------------------------------------------------------------------------

local function cloneMember(member: any): any
	local copy = table.clone(member)
	copy.Stats = table.clone(member.Stats)
	return copy
end

local function equalize(members: { any })
	if #members == 0 or Ranked.StatEqualize <= 0 then
		return
	end
	local sums: { [string]: number } = {}
	for _, member in members do
		for stat, value in member.Stats do
			if type(value) == "number" then
				sums[stat] = (sums[stat] or 0) + value
			end
		end
	end
	for _, member in members do
		for stat, value in member.Stats do
			if type(value) == "number" and sums[stat] then
				local mean = sums[stat] / #members
				member.Stats[stat] = value + (mean - value) * Ranked.StatEqualize
			end
		end
	end
end

local function buildTeams(lineup: { [number]: { Player } }): { [number]: { any } }
	local teams: { [number]: { any } } = {}
	local field, keepers = {}, {}
	for team = 1, 2 do
		local humans = lineup[team]
		local captain = humans[1]
		local base = if captain then EconomyService.getMatchTeam(captain) else EconomyService.rivalTeam(EconomyService.getMatchTeam(lineup[1][1]))
		local members = {}
		for slot = 1, 4 do
			local human = if slot ~= GOALKEEPER_SLOT then humans[slot] else nil
			-- Cada persona juega con SU delantero (puesto 1 de su equipo); los bots, con los del capitan
			local member = if human then EconomyService.getMatchTeam(human)[1] else base[slot]
			members[slot] = cloneMember(member)
			table.insert(if slot == GOALKEEPER_SLOT then keepers else field, members[slot])
		end
		teams[team] = members
	end
	equalize(field)
	equalize(keepers)
	return teams
end

-- ---------------------------------------------------------------------------
-- Copas y recompensas
-- ---------------------------------------------------------------------------

local function expected(mine: number, theirs: number): number
	return 1 / (1 + 10 ^ ((theirs - mine) / 400))
end

-- Aplica el resultado ("score": 1 victoria, 0.5 empate, 0 derrota) a las copas. Devuelve (antes, despues).
local function applyRating(player: Player, score: number, mine: number, theirs: number, leaving: boolean, scale: number): (number, number)
	local data = DataService.get(player)
	if not data then
		return 0, 0
	end
	local pvp = data.Pvp
	local before = pvp.Rating
	local k = if pvp.Played < Ranked.PlacementMatches then Ranked.PlacementK else Ranked.KFactor
	local delta = k * (score - expected(mine, theirs))
	if score >= 1 then
		pvp.Wins += 1
		pvp.Streak = math.max(0, pvp.Streak) + 1
		delta = math.max(Ranked.MinGain, delta) + math.min(Ranked.StreakBonusMax, Ranked.StreakBonus * (pvp.Streak - 1))
	elseif score <= 0 then
		pvp.Losses += 1
		pvp.Streak = 0
		delta = math.min(-Ranked.MinLoss, delta)
		if leaving then
			delta -= Ranked.LeavePenaltyExtra
		end
	else
		pvp.Draws += 1
		pvp.Streak = 0
	end
	pvp.Played += 1
	pvp.Rating = math.max(0, math.floor(before + delta * scale + 0.5))
	pvp.Best = math.max(pvp.Best, pvp.Rating)
	DataService.changed(player, true)
	pushRating(player, pvp.Rating)
	return before, pvp.Rating
end

-- Abandono: derrota (y un poco mas). Solo una vez por partido.
local function penalizeLeaver(player: Player)
	local info = onlineOf[player]
	if not info or info.Left[player] then
		return
	end
	info.Left[player] = true
	onlineOf[player] = nil
	playingCount = math.max(0, playingCount - 1)
	publishCounts()
	local team = if table.find(info.Lineup[1], player) then 1 else 2
	local other = if team == 1 then 2 else 1
	local theirs = if info.Solo then info.TeamAvg[team] else info.TeamAvg[other]
	local before, after = applyRating(player, 0, info.TeamAvg[team], theirs, true, 1)
	if player.Parent then
		notify(player, "Warning", `Has abandonado el partido online: {after - before} copas`)
	end
end

local function finishOnline(info: OnlineMatch, result: any)
	for team = 1, 2 do
		for _, player in info.Lineup[team] do
			if onlineOf[player] == info then
				onlineOf[player] = nil
				playingCount = math.max(0, playingCount - 1)
			end
		end
	end
	publishCounts()
	if not result then
		return -- se cerro sin acabar (todos se fueron)
	end
	-- MVP: el humano (que no abandono) con mas goles; a igualdad, del equipo ganador
	local mvp: Player? = nil
	local mvpGoals = 0
	for team = 1, 2 do
		for _, player in info.Lineup[team] do
			if info.Left[player] or not player.Parent then
				continue
			end
			local goals = result.PlayerGoals[player.UserId] or 0
			if goals > mvpGoals or (goals == mvpGoals and goals > 0 and team == result.Winner) then
				mvp, mvpGoals = player, goals
			end
		end
	end
	local fullBonus = not result.Forfeit or result.Duration >= Ranked.MinDurationForBonus
	for team = 1, 2 do
		local other = if team == 1 then 2 else 1
		for _, player in info.Lineup[team] do
			if info.Left[player] or not player.Parent then
				continue
			end
			local score = if result.Winner == 0 then 0.5 elseif result.Winner == team then 1 else 0
			local theirs = if info.Solo then info.TeamAvg[team] else info.TeamAvg[other]
			-- Victoria por abandono muy pronto: la mitad de copas (que no se pueda inflar con amigos que se van)
			local before, after = applyRating(player, score, info.TeamAvg[team], theirs, false, if fullBonus then 1 else 0.5)
			local isMvp = player == mvp
			local data = DataService.get(player)
			if data and isMvp then
				data.Pvp.Mvps += 1
			end
			local _, _, _, oldLabel = Ranked.tierOf(before)
			local newTier, _, _, newLabel = Ranked.tierOf(after)
			local oldTier = Ranked.tierOf(before)
			local promoted = if newTier.Min > oldTier.Min then newTier.Name else nil
			local demoted = if newTier.Min < oldTier.Min then newTier.Name else nil
			local goals = result.PlayerGoals[player.UserId] or 0
			local ok, err = pcall(EconomyService.matchFinished, player, result.Winner, team, goals, {
				Factor = if fullBonus then Ranked.RewardFactor else 1,
				GemFactor = if fullBonus then Ranked.GemFactor else 1,
				BonusGems = if isMvp then Ranked.MvpGems else 0,
				Info = {
					Online = true,
					Rating = after,
					RatingDelta = after - before,
					RankLabel = newLabel,
					OldRankLabel = oldLabel,
					Promoted = promoted,
					Demoted = demoted,
					Mvp = isMvp,
					MvpName = if mvp then mvp.DisplayName else nil,
					MvpGems = if isMvp then Ranked.MvpGems else 0,
					Forfeit = result.Forfeit == true and result.Winner == team,
					Streak = if data then data.Pvp.Streak else 0,
				},
			})
			if not ok then
				warn(`[Online] Error al dar las recompensas a {player.Name}: {err}`)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Emparejamiento
-- ---------------------------------------------------------------------------

local function groupRating(group: Group): number
	local sum = 0
	for _, p in group.Members do
		sum += ratingOf(p)
	end
	return sum / math.max(1, #group.Members)
end

-- Mejor reparto de unos grupos (los mas antiguos primero; su tamano y sus copas medias) en dos equipos, o nil.
-- Devuelve el equipo (0 fuera, 1, 2) de cada grupo. Lo usa tambien la cola global (GlobalMatchmaking).
local function bestSplitOf(sizes: { number }, ratings: { number }, oldestWait: number): { number }?
	local n = #sizes
	local allowedDiff = if oldestWait >= Ranked.VeryUnevenAfter then 2 elseif oldestWait >= Ranked.UnevenAfter then 1 else 0
	local allowedGap = Ranked.RatingGapBase + Ranked.RatingGapPerSecond * oldestWait
	local best: { number }? = nil
	local bestScore = -math.huge
	local assign = table.create(n, 0)
	for code = 1, 3 ^ n - 1 do
		local c = code
		local s1, s2, r1, r2 = 0, 0, 0, 0
		for i = 1, n do
			local t = c % 3
			c //= 3
			assign[i] = t
			if t == 1 then
				s1 += sizes[i]
				r1 += ratings[i] * sizes[i]
			elseif t == 2 then
				s2 += sizes[i]
				r2 += ratings[i] * sizes[i]
			end
		end
		-- El que mas lleva esperando entra siempre; ambos equipos con alguien y sin pasarse
		if assign[1] == 0 or s1 == 0 or s2 == 0 or s1 > Ranked.MaxPerTeam or s2 > Ranked.MaxPerTeam then
			continue
		end
		local diff = math.abs(s1 - s2)
		if diff > allowedDiff then
			continue
		end
		local gap = math.abs(r1 / s1 - r2 / s2)
		if gap > allowedGap then
			continue
		end
		local score = (s1 + s2) * 1000 - diff * 300 - gap
		if score > bestScore then
			bestScore = score
			best = table.clone(assign)
		end
	end
	return best
end

local function bestSplit(groups: { Group }, oldestWait: number): { number }?
	local sizes, ratings = {}, {}
	for i, group in groups do
		sizes[i] = #group.Members
		ratings[i] = groupRating(group)
	end
	return bestSplitOf(sizes, ratings, oldestWait)
end

-- Crea el partido online con estos humanos. "afterClose": se llama al acabar (servidor de partido: volver a casa).
-- Devuelve false si no se pudo crear (campo ocupado o alguien ya no puede jugar).
local function launch(lineup: { [number]: { Player } }, solo: boolean, afterClose: (() -> ())?): boolean
	local ok, teams = pcall(buildTeams, lineup)
	if not ok then
		warn(`[Online] No se pudieron preparar los equipos: {teams}`)
		return false
	end
	local info: OnlineMatch = { Lineup = lineup, Ratings = {}, TeamAvg = { 0, 0 }, Solo = solo, Left = {} }
	for team = 1, 2 do
		local sum = 0
		for _, p in lineup[team] do
			local rating = ratingOf(p)
			info.Ratings[p] = rating
			sum += rating
		end
		info.TeamAvg[team] = if #lineup[team] > 0 then sum / #lineup[team] else 0
	end
	-- Antes de crear el partido (que les pone MatchId): asi no se confunde con "ha empezado otro partido"
	for team = 1, 2 do
		for _, p in lineup[team] do
			onlineOf[p] = info
		end
	end
	local started = MatchService.startOnline(lineup, teams :: any, function(match, result)
		finishOnline(info, if match then result else nil)
		if not match then
			for team = 1, 2 do
				for _, p in lineup[team] do
					notify(p, "Warning", "No se pudo crear el partido online. Vuelve a intentarlo")
				end
			end
		end
		if afterClose then
			afterClose()
		end
	end, function(player: Player)
		penalizeLeaver(player)
	end)
	if not started then
		for team = 1, 2 do
			for _, p in lineup[team] do
				onlineOf[p] = nil
			end
		end
		return false
	end
	for team = 1, 2 do
		for _, p in lineup[team] do
			if onlineOf[p] ~= info then
				continue -- (el partido fallo al crearse y ya se limpio)
			end
			playingCount += 1
			notify(p, "Reward", if solo then "¡Partido online de prueba (Studio) contra bots!" else "¡Partido encontrado! Que empiece el espectáculo")
		end
	end
	publishCounts()
	print(`[Online] Partido {#lineup[1]} vs {#lineup[2]} (copas {math.floor(info.TeamAvg[1])} vs {math.floor(info.TeamAvg[2])})`)
	return true
end

local function startMatch(groups: { Group }, split: { number }, solo: boolean)
	local lineup: { [number]: { Player } } = { {}, {} }
	for i, group in groups do
		local team = split[i]
		if team ~= 0 then
			for _, p in group.Members do
				table.insert(lineup[team], p)
			end
		end
	end
	-- Quien ya no puede jugar (se fue, empezo una practica, robo un brainrot...) saca a su grupo de la cola
	local dropped = false
	for i, group in groups do
		if split[i] == 0 then
			continue
		end
		for _, p in group.Members do
			if not MatchService.canPlay(p) or onlineOf[p] then
				removeGroup(group)
				for _, member in group.Members do
					notify(member, "Warning", `Búsqueda cancelada: {p.DisplayName} no puede jugar ahora`)
				end
				dropped = true
				break
			end
		end
	end
	if dropped then
		return
	end
	if not launch(lineup, solo, nil) then
		return -- (campo ocupado justo ahora) siguen en la cola
	end
	for i, group in groups do
		if split[i] ~= 0 then
			removeGroup(group, true)
		end
	end
	formingSince = nil
end

-- ---------------------------------------------------------------------------
-- Cola global (todos los servidores): ver GlobalMatchmaking
-- ---------------------------------------------------------------------------

local function findGroup(id: string): Group?
	for _, group in queue do
		if group.Id == id then
			return group
		end
	end
	return nil
end

-- Viaje al servidor reservado del partido
local function teleportGroup(group: Group, accessCode: string)
	removeGroup(group, true)
	local travelers = {}
	for _, p in group.Members do
		if p.Parent and MatchService.canPlay(p) then
			table.insert(travelers, p)
			p:SetAttribute("Traveling", true)
			notify(p, "Reward", "¡Partido encontrado con jugadores de otro servidor! Viajando al estadio...")
		end
	end
	if #travelers == 0 then
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({ FG = "Online" })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, travelers, options)
	end)
	if not ok then
		warn(`[Online] No se pudo viajar al partido: {err}`)
		for _, p in travelers do
			p:SetAttribute("Traveling", nil)
			notify(p, "Warning", "No se pudo viajar al partido. Vuelve a buscar")
		end
	end
end

local globalHooks: GlobalMatchmaking.Hooks = {
	bestSplit = bestSplitOf,
	startLocal = function(groupIds: { string }, teams: { number })
		local groups: { Group } = {}
		for i, id in groupIds do
			local group = findGroup(id)
			if not group then
				return -- alguno se fue mientras tanto: los demas siguen en la cola
			end
			groups[i] = group
		end
		startMatch(groups, teams, false)
	end,
	teleport = function(groupId: string, accessCode: string)
		local group = findGroup(groupId)
		if group then
			teleportGroup(group, accessCode)
		end
	end,
}

local function globalTick()
	local list: { GlobalMatchmaking.LocalGroup } = {}
	for _, group in queue do
		local ids = {}
		for _, p in group.Members do
			table.insert(ids, p.UserId)
		end
		table.insert(list, { Id = group.Id, UserIds = ids, Rating = groupRating(group), Since = group.SinceUnix })
	end
	GlobalMatchmaking.step(list, globalHooks)
	ReplicatedStorage:SetAttribute("RankedGlobal", true)
	local local_ = 0
	for _, group in queue do
		local_ += #group.Members
	end
	ReplicatedStorage:SetAttribute("RankedQueue", math.max(GlobalMatchmaking.queueCount(), local_))
	for _, group in queue do
		for _, p in group.Members do
			p:SetAttribute("QueueEta", 0)
		end
	end
end

local function tick()
	-- Limpieza: jugadores que se fueron
	for i = #queue, 1, -1 do
		local group = queue[i]
		for _, p in group.Members do
			if p.Parent == nil then
				removeGroup(group)
				break
			end
		end
	end
	if #queue == 0 then
		formingSince = nil
		return
	end
	table.sort(queue, function(a, b)
		return a.Since < b.Since
	end)
	-- En el juego publicado: cola de TODOS los servidores (si MemoryStore responde)
	if GlobalMatchmaking.isEnabled() then
		globalTick()
		return
	end
	local now = os.clock()
	local considered: { Group } = {}
	for i = 1, math.min(#queue, Ranked.MaxGroupsConsidered) do
		considered[i] = queue[i]
	end
	local oldestWait = now - considered[1].Since
	local split = bestSplit(considered, oldestWait)
	local solo = false
	if not split and RunService:IsStudio() and oldestWait >= STUDIO_SOLO_AFTER and #considered[1].Members <= Ranked.MaxPerTeam then
		split = table.create(#considered, 0)
		split[1] = 1
		solo = true
	end

	local eta = 0
	if split then
		local humans = 0
		for i, group in considered do
			if split[i] ~= 0 then
				humans += #group.Members
			end
		end
		if not MatchService.hasFreeSlot() then
			eta = -1 -- todos los campos ocupados
		else
			formingSince = formingSince or now
			local waitFor = if humans >= Ranked.MaxPerTeam * 2 or solo then 0 else Ranked.FillSeconds
			if now - (formingSince :: number) >= waitFor then
				startMatch(considered, split, solo)
				return
			end
			eta = workspace:GetServerTimeNow() + (waitFor - (now - (formingSince :: number)))
		end
	else
		formingSince = nil
	end
	for _, group in queue do
		for _, p in group.Members do
			p:SetAttribute("QueueEta", eta)
		end
	end
end

-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Servidor de partido (reservado por la cola global): espera a los jugadores, juega y los devuelve a su servidor
-- ---------------------------------------------------------------------------

local returning: { [Player]: boolean } = {}

local function setStatus(text: string)
	ReplicatedStorage:SetAttribute("MatchServerStatus", text)
end

-- Vuelta a su servidor de antes (si esta lleno o ya no existe, a cualquiera)
local function returnHome(players: { Player }, origins: { [string]: string }?)
	for _, p in players do
		if not p.Parent then
			continue
		end
		returning[p] = true
		p:SetAttribute("Traveling", true)
		local options = Instance.new("TeleportOptions")
		local origin = if origins then origins[tostring(p.UserId)] else nil
		if origin and origin ~= "" and origin ~= "studio" then
			options.ServerInstanceId = origin
		end
		local ok = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { p }, options)
		end)
		if not ok then
			pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { p })
			end)
		end
	end
end

local function runMatchServer()
	ReplicatedStorage:SetAttribute("MatchServer", true)
	setStatus("Preparando el partido...")
	local spec = GlobalMatchmaking.loadSpec()
	if not spec then
		setStatus("No se ha encontrado el partido. Volviendo...")
		task.wait(3)
		returnHome(Players:GetPlayers(), nil)
		Players.PlayerAdded:Connect(function(p)
			task.wait(3)
			returnHome({ p }, nil)
		end)
		return
	end
	local s = spec :: { Teams: { { number } }, Origins: { [string]: string } }
	local total = #s.Teams[1] + #s.Teams[2]
	local function readyPlayers(): { [number]: { Player } }
		local lineup: { [number]: { Player } } = { {}, {} }
		for team = 1, 2 do
			for _, userId in s.Teams[team] do
				local p = Players:GetPlayerByUserId(userId)
				if p and DataService.get(p) and MatchService.canPlay(p) then
					table.insert(lineup[team], p)
				end
			end
		end
		return lineup
	end
	local deadline = os.clock() + Ranked.MatchServerWait
	local lineup = readyPlayers()
	while os.clock() < deadline and #lineup[1] + #lineup[2] < total do
		setStatus(`Esperando a los jugadores ({#lineup[1] + #lineup[2]}/{total})...`)
		task.wait(0.5)
		lineup = readyPlayers()
	end
	local started = false
	-- Quien llegue tarde (ya empezado) vuelve a su servidor
	Players.PlayerAdded:Connect(function(p)
		if started then
			task.wait(4)
			notify(p, "Warning", "Has llegado tarde: el partido ya había empezado")
			returnHome({ p }, s.Origins)
		end
	end)
	if #lineup[1] == 0 or #lineup[2] == 0 then
		setStatus("El rival no ha llegado: partido cancelado (no pierdes copas). Volviendo...")
		task.wait(4)
		returnHome(Players:GetPlayers(), s.Origins)
		return
	end
	setStatus("¡A jugar!")
	started = launch(lineup, false, function()
		setStatus("¡Partido terminado! Volviendo a tu servidor...")
		task.wait(7) -- tiempo para ver el resultado y las recompensas
		returnHome(Players:GetPlayers(), s.Origins)
	end)
	if not started then
		setStatus("No se pudo crear el partido. Volviendo...")
		task.wait(3)
		returnHome(Players:GetPlayers(), s.Origins)
	end
end

function RankedService.isPlayingOnline(player: Player): boolean
	return onlineOf[player] ~= nil
end

function RankedService.start()
	EconomyService.registerAction("QueueJoin", function(player)
		return joinQueue(player)
	end)
	EconomyService.registerAction("QueueLeave", function(player)
		RankedService.leaveQueue(player, "Se ha cancelado la búsqueda de partido")
		return { Ok = true }
	end)
	EconomyService.registerAction("PartyInvite", function(player, _data, userId)
		return invite(player, userId)
	end)
	EconomyService.registerAction("PartyRespond", function(player, _data, fromUserId, accept)
		return respond(player, fromUserId, accept)
	end)
	EconomyService.registerAction("PartyLeave", function(player)
		leaveParty(player)
		return { Ok = true }
	end)
	EconomyService.registerAction("RankedInfo", function(player, data)
		local top = topList
		if not topGlobal then
			top = serverTop() -- la del servidor se rehace al momento
		end
		return {
			Ok = true,
			Pvp = table.clone(data.Pvp),
			Top = top,
			Global = topGlobal,
			Queue = ReplicatedStorage:GetAttribute("RankedQueue") or 0,
			Playing = playingCount,
		}
	end)

	-- Al empezar una practica (o cualquier otro partido) se sale de la cola
	local function watch(player: Player)
		player:GetAttributeChangedSignal("MatchId"):Connect(function()
			local id = player:GetAttribute("MatchId")
			if id ~= nil and id ~= 0 and groupOf[player] and not onlineOf[player] then
				RankedService.leaveQueue(player, `{player.DisplayName} ha empezado otro partido: búsqueda cancelada`)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	-- Irse del servidor en pleno partido online = abandono (antes de que se guarden sus datos)
	DataService.onReleased(function(player)
		penalizeLeaver(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		RankedService.leaveQueue(player, `{player.DisplayName} se ha ido: búsqueda cancelada`)
		leaveParty(player)
		invites[player] = nil
		for _, list in invites do
			list[player] = nil
		end
	end)

	-- Viajes que fallan: aviso (y, si volvia a su servidor y estaba lleno, a cualquier otro)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message: string)
		player:SetAttribute("Traveling", nil)
		if returning[player] then
			returning[player] = nil
			pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { player })
			end)
			return
		end
		warn(`[Online] Viaje fallido de {player.Name}: {message}`)
		notify(player, "Warning", "No se pudo viajar al partido. Vuelve a buscar")
	end)
	Players.PlayerRemoving:Connect(function(player)
		returning[player] = nil
	end)

	-- Este servidor es uno reservado para un partido online de la cola global
	if GlobalMatchmaking.isMatchServer() then
		task.spawn(runMatchServer)
	end

	task.spawn(function()
		while true do
			task.wait(Ranked.QueueTick)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[Online] Error en la cola: {err}`)
			end
		end
	end)
	task.spawn(function()
		while true do
			pcall(refreshTop)
			task.wait(Ranked.LeaderboardRefresh)
		end
	end)
	publishCounts()
	print(`[Online] Partidos online listos: hasta {Ranked.MaxPerTeam}v{Ranked.MaxPerTeam} con bots de relleno y copas`)
end

return RankedService
