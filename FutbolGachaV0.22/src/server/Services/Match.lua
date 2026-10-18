--!strict
--[[
	Match: un partido completo (clase). Hay un objeto Match por cada partido en curso.
	Fases: Preparing -> Countdown -> Playing -> Goal -> Countdown ... -> [GoldenGoal] -> Final -> Closed
	El servidor es la unica autoridad: marcador, tiempo y fase solo se modifican aqui.
	El estado se publica al cliente como Attributes de la carpeta del partido (Phase, Score1, Score2, TimeLeft, Countdown).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Characters = require(ReplicatedStorage.Shared.Config.Characters)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local Ball = require(script.Parent.Ball)
local CollisionSetup = require(script.Parent.CollisionSetup)

local MatchEvent = Remotes.get("MatchEvent")

local TEAM_COLORS = { Color3.fromRGB(52, 120, 246), Color3.fromRGB(235, 64, 52) }

export type Phase = "Preparing" | "Countdown" | "Playing" | "GoldenGoal" | "Goal" | "Final" | "Closed"

type Fields = {
	Id: number,
	Slot: number,
	Mode: string,
	Folder: Folder,
	Origin: CFrame,
	Ball: Ball.Ball,
	Actors: { Types.Actor },
	ByPlayer: { [Player]: Types.Actor },
	Phase: Phase,
	PhaseTimer: number,
	TimeLeft: number,
	Score: { number },
	Scorers: { Types.Scorer },
	KickoffTeam: number,
	EndAfterGoal: boolean,
	StartedAt: number,
	Connections: { RBXScriptConnection },
	Published: { [string]: any },
	Result: Types.MatchResult?,
	OnClosed: ((Types.MatchResult?) -> ())?,
}

local Match = {}
Match.__index = Match

export type Match = typeof(setmetatable({} :: Fields, Match))

-- ---------------------------------------------------------------------------
-- Creacion
-- ---------------------------------------------------------------------------

local function createDummy(team: number, name: string): Model
	local description = Instance.new("HumanoidDescription")
	local color = TEAM_COLORS[team]
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = color
	description.RightLegColor = color
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = name
	return model
end

-- ATENCION: puede ceder el hilo (crea munecos). Llamar dentro de task.spawn.
-- "players" deben tener su personaje cargado. En el modo de practica todos van al equipo 1.
function Match.new(id: number, slot: number, parent: Instance, players: { Player }, mode: string): Match
	local origin = CFrame.new(Balance.Match.ArenaBasePosition + Vector3.new(0, 0, slot * Balance.Match.ArenaSpacing))

	local folder = Instance.new("Folder")
	folder.Name = `Match_{id}`
	folder.Parent = parent -- primero dentro de Workspace; el balon lo necesita para SetNetworkOwner

	local arena = ArenaBuilder.build(origin)
	arena.Parent = folder
	local ball = Ball.new(folder, origin)

	local fields: Fields = {
		Id = id,
		Slot = slot,
		Mode = mode,
		Folder = folder,
		Origin = origin,
		Ball = ball,
		Actors = {},
		ByPlayer = {},
		Phase = "Preparing",
		PhaseTimer = 0,
		TimeLeft = Balance.Match.Duration,
		Score = { 0, 0 },
		Scorers = {},
		KickoffTeam = 1,
		EndAfterGoal = false,
		StartedAt = os.clock(),
		Connections = {},
		Published = {},
		Result = nil,
		OnClosed = nil,
	}
	local self = setmetatable(fields, Match)

	folder:SetAttribute("Phase", "Preparing")
	self:_publish("Score1", 0)
	self:_publish("Score2", 0)
	self:_publish("TimeLeft", Balance.Match.Duration)
	self:_publish("Countdown", 0)

	local humanIndex = 0
	for team = 1, 2 do
		for actorSlot = 1, Balance.Match.TeamSize do
			local player: Player? = nil
			if team == 1 then
				humanIndex += 1
				player = players[humanIndex]
			end
			local actor = self:_createActor(team, actorSlot, player)
			table.insert(self.Actors, actor)
			if actor.Player then
				self.ByPlayer[actor.Player] = actor
			end
		end
	end

	self.StartedAt = os.clock()
	self:_enterCountdown()
	return self
end

function Match._createActor(self: Match, team: number, slot: number, player: Player?): Types.Actor
	local characterId = Characters.DefaultTeam[slot]
	local data = Characters.List[characterId]
	assert(data, "Falta el personaje " .. tostring(characterId))

	local model: Model
	if player and player.Character then
		model = player.Character
	else
		model = createDummy(team, data.Name)
		model.Parent = self.Folder
	end

	table.insert(self.Connections, CollisionSetup.applyToActor(model)) -- el balon no choca con los jugadores
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.WalkSpeed = 0

	local highlight = Instance.new("Highlight")
	highlight.FillColor = TEAM_COLORS[team]
	highlight.OutlineColor = TEAM_COLORS[team]
	highlight.FillTransparency = 0.6
	highlight.Adornee = model
	highlight.Parent = model

	local actor: Types.Actor = {
		Name = if player then player.DisplayName else data.Name,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Team = team,
		Slot = slot,
		Player = player,
		Controllable = player ~= nil,
		Stats = data.Stats,
		Stamina = Balance.Stamina.Max,
		Exhausted = false,
		SprintWanted = false,
		LastSprintAt = 0,
		StunnedUntil = 0,
		ReleaseAt = 0,
		ImmuneUntil = 0,
		ForcedMoveUntil = 0,
		ForcedMoveDir = Vector3.zero,
		ForcedMoveSpeed = 0,
		SlideUntil = 0,
		SlideDir = Vector3.zero,
		SlideResolved = true,
		NextActionAt = {},
	}

	if player then
		player:SetAttribute("MatchId", self.Id)
		player:SetAttribute("Team", team)
		player:SetAttribute("Stamina", Balance.Stamina.Max)
		table.insert(
			self.Connections,
			humanoid.Died:Connect(function()
				self:_removeActor(actor)
			end)
		)
	end

	self:_placeActor(actor)
	if not player then
		root.Anchored = true -- munecos quietos hasta la Fase 3 (bots)
	end
	return actor
end

-- ---------------------------------------------------------------------------
-- Utilidades internas
-- ---------------------------------------------------------------------------

function Match._publish(self: Match, name: string, value: any)
	if self.Published[name] ~= value then
		self.Published[name] = value
		self.Folder:SetAttribute(name, value)
	end
end

function Match._broadcast(self: Match, ...: any)
	for player in self.ByPlayer do
		MatchEvent:FireClient(player, ...)
	end
end

function Match._setPhase(self: Match, phase: Phase, timer: number)
	self.Phase = phase
	self.PhaseTimer = timer
	self.Folder:SetAttribute("Phase", phase)
	print(`[Match {self.Id}] fase -> {phase}`) -- registro de cada transicion de estado
end

function Match._goalPosition(self: Match, attackingTeam: number): Vector3
	local sign = if attackingTeam == 1 then 1 else -1
	return self.Origin:PointToWorldSpace(Vector3.new(sign * Balance.Field.Length / 2, 0, 0))
end

function Match._isLive(self: Match): boolean
	return self.Phase == "Playing" or self.Phase == "GoldenGoal"
end

-- Coloca a un actor en su posicion de saque, mirando al rival.
function Match._placeActor(self: Match, actor: Types.Actor)
	local formation = Balance.Formation[actor.Slot]
	local distance = formation.X
	if actor.Slot == 1 then
		distance = if actor.Team == self.KickoffTeam then Balance.Kickoff.Near else Balance.Kickoff.Far
	end
	local side = if actor.Team == 1 then -1 else 1 -- el equipo 1 empieza en -X y ataca hacia +X
	local z = if actor.Team == 1 then formation.Z else -formation.Z
	local position = Vector3.new(side * distance, 3.2, z)
	local facing = Vector3.new(-side, 0, 0)

	actor.Model:PivotTo(self.Origin * CFrame.lookAt(position, position + facing))
	actor.Root.AssemblyLinearVelocity = Vector3.zero
	actor.Root.AssemblyAngularVelocity = Vector3.zero
end

-- El movimiento impuesto (segada, regate lateral) lo ejecuta el cliente dueno del personaje:
-- el servidor publica hasta cuando y en que direccion (hora del servidor) y el cliente llama a Humanoid:Move.
function Match._publishForcedMove(self: Match, actor: Types.Actor)
	local player = actor.Player
	if not player then
		return
	end
	if actor.ForcedMoveUntil > os.clock() then
		player:SetAttribute("ForceDir", actor.ForcedMoveDir)
		player:SetAttribute("ForceUntil", workspace:GetServerTimeNow() + (actor.ForcedMoveUntil - os.clock()))
	else
		player:SetAttribute("ForceUntil", 0)
	end
end

function Match._enterCountdown(self: Match)
	for _, actor in self.Actors do
		self:_placeActor(actor)
		actor.StunnedUntil = 0
		actor.ReleaseAt = 0
		actor.ImmuneUntil = 0
		actor.ForcedMoveUntil = 0
		actor.SlideUntil = 0
		actor.SprintWanted = false
		self:_publishForcedMove(actor)
	end
	self.Ball:placeAtCenter()
	self:_setPhase("Countdown", Balance.Match.CountdownSeconds)
	self:_publish("Countdown", Balance.Match.CountdownSeconds)
end

-- ---------------------------------------------------------------------------
-- Bucle principal (lo llama MatchService cada Heartbeat)
-- ---------------------------------------------------------------------------

function Match._updateActors(self: Match, dt: number, now: number)
	local S = Balance.Speed
	local ST = Balance.Stamina
	local live = self:_isLive()

	for _, actor in self.Actors do
		if not actor.Controllable then
			actor.Humanoid.WalkSpeed = 0
			continue
		end
		local stunned = now < actor.StunnedUntil
		local moving = MathUtil.flat(actor.Root.AssemblyLinearVelocity).Magnitude > 1
		local sprinting = actor.SprintWanted and live and not stunned and not actor.Exhausted and moving

		if sprinting then
			local duration = MathUtil.mapStat(actor.Stats.Stamina, ST.DurationMin, ST.DurationMax)
			actor.Stamina = math.max(0, actor.Stamina - (ST.Max / duration) * dt)
			actor.LastSprintAt = now
			if actor.Stamina <= 0 then
				actor.Exhausted = true
			end
		elseif now - actor.LastSprintAt >= ST.RegenDelay then
			actor.Stamina = math.min(ST.Max, actor.Stamina + (ST.Max / ST.RegenSeconds) * dt)
			if actor.Exhausted and actor.Stamina >= ST.ResumeAt then
				actor.Exhausted = false
			end
		end

		local speed = MathUtil.mapStat(actor.Stats.Speed, S.Min, S.Max)
		if sprinting then
			speed *= S.SprintMultiplier
		end
		actor.Humanoid.WalkSpeed = if live and not stunned then speed else 0
		if live and now < actor.ForcedMoveUntil then
			actor.Humanoid.WalkSpeed = actor.ForcedMoveSpeed -- segada o regate: velocidad impuesta
		end

		if actor.Player then
			actor.Player:SetAttribute("Stamina", math.floor(actor.Stamina))
		end
	end
end

function Match.update(self: Match, dt: number)
	local phase = self.Phase
	if phase == "Preparing" or phase == "Closed" then
		return
	end
	local now = os.clock()
	self.Ball:step(dt, self.Actors, now)
	self:_updateActors(dt, now)
	if self:_isLive() then
		for _, actor in self.Actors do
			if now < actor.SlideUntil and not actor.SlideResolved then
				self.Ball:slideContact(actor, now)
			end
		end
	end

	if phase == "Countdown" then
		self.PhaseTimer -= dt
		self:_publish("Countdown", math.ceil(math.max(self.PhaseTimer, 0)))
		if self.PhaseTimer <= 0 then
			self.Ball:release()
			self:_setPhase("Playing", 0)
		end
	elseif phase == "Playing" then
		self.TimeLeft = math.max(0, self.TimeLeft - dt)
		self:_publish("TimeLeft", math.ceil(self.TimeLeft))
		if not self:_checkGoal() and self.TimeLeft <= 0 then
			if self.Score[1] == self.Score[2] then
				self:_setPhase("GoldenGoal", Balance.Match.GoldenGoalSeconds)
			else
				self:_finish()
			end
		end
	elseif phase == "GoldenGoal" then
		self.PhaseTimer -= dt
		self:_publish("TimeLeft", math.ceil(math.max(self.PhaseTimer, 0)))
		if not self:_checkGoal() and self.PhaseTimer <= 0 then
			self:_finish() -- sigue empatado: empate
		end
	elseif phase == "Goal" then
		self.PhaseTimer -= dt
		if self.PhaseTimer <= 0 then
			if self.EndAfterGoal then
				self:_finish()
			else
				self:_enterCountdown() -- reposicion y nueva cuenta atras
			end
		end
	elseif phase == "Final" then
		self.PhaseTimer -= dt
		if self.PhaseTimer <= 0 then
			self:close()
		end
	end
end

-- El gol se detecta por plano (posicion del balon respecto a la linea), no con Touched.
-- Es gol SOLO si el balon entero ha cruzado la linea de gol: el centro tiene que estar a mas de un radio
-- del borde exterior de la linea (la linea de gol acaba justo en X = Length / 2, ver ArenaBuilder), y el balon
-- entero tiene que estar entre los palos y bajo el travesano.
function Match._checkGoal(self: Match): boolean
	local F = Balance.Field
	local p = self.Ball:getLocalPosition()
	local radius = Balance.Ball.Diameter / 2
	local crossedLine = math.abs(p.X) - radius > F.Length / 2
	local betweenPosts = math.abs(p.Z) + radius <= F.GoalWidth / 2
	local underBar = p.Y + radius <= F.GoalHeight
	if crossedLine and betweenPosts and underBar then
		self:_onGoal(if p.X > 0 then 1 else 2)
		return true
	end
	return false
end

function Match._onGoal(self: Match, team: number)
	self.Score[team] += 1
	local lastTouch = self.Ball.LastTouch
	local scorerName = if lastTouch then lastTouch.Name else "?"
	table.insert(self.Scorers, {
		Team = team,
		Name = scorerName,
		Time = Balance.Match.Duration - self.TimeLeft,
	})

	self.Ball:freeze()
	self.KickoffTeam = if team == 1 then 2 else 1 -- saca el equipo que encajo
	self.EndAfterGoal = self.Phase == "GoldenGoal"
	self:_publish("Score1", self.Score[1])
	self:_publish("Score2", self.Score[2])
	self:_broadcast("Goal", team, scorerName)
	self:_setPhase("Goal", Balance.Match.GoalCelebrationSeconds)
end

function Match._finish(self: Match)
	self.Ball:freeze()
	local winner = 0
	if self.Score[1] > self.Score[2] then
		winner = 1
	elseif self.Score[2] > self.Score[1] then
		winner = 2
	end
	local result: Types.MatchResult = {
		Winner = winner,
		Score = { self.Score[1], self.Score[2] },
		Scorers = self.Scorers,
		Duration = os.clock() - self.StartedAt,
		Mode = self.Mode,
	}
	self.Result = result
	-- TODO (Fase 4 en adelante): aqui se entregan monedas, experiencia y puntos de fichaje.
	self:_broadcast("Final", winner, result.Score[1], result.Score[2])
	self:_setPhase("Final", Balance.Match.FinalSeconds)
end

-- ---------------------------------------------------------------------------
-- Acciones de los jugadores (ya validadas por RemoteValidator)
-- ---------------------------------------------------------------------------

function Match.handleAction(self: Match, player: Player, action: string, value: any)
	local actor = self.ByPlayer[player]
	if not actor then
		return
	end
	if action == "Sprint" then
		actor.SprintWanted = value == true
		return
	end
	if not self:_isLive() then
		return
	end

	local now = os.clock()
	if now < actor.StunnedUntil then
		return
	end
	local readyAt = actor.NextActionAt[action]
	if readyAt and now < readyAt then
		return
	end
	local C = Balance.Control
	local cooldown = C.Cooldowns[action] or 0.5

	-- Dos "visiones": con balon (regates) y sin balon (entrada y segada). Lo decide el servidor.
	local hasBall = self.Ball.Controller == actor

	if action == "Pass" or action == "Shoot" then
		-- Tambien sirven sin tener el balon controlado (golpear un balon suelto a tu alcance); kick() lo valida.
		local charge = 0
		if action == "Shoot" and typeof(value) == "number" then
			charge = math.clamp(value :: number, 0, 1)
		end
		if self.Ball:kick(actor, action, charge, self:_goalPosition(actor.Team)) then
			actor.NextActionAt[action] = now + cooldown
		end
	elseif action == "Tackle" then
		if hasBall then
			return
		end
		local result = self.Ball:tackle(actor, now)
		if result == "NoTarget" then
			actor.NextActionAt[action] = now + C.TackleWhiffCooldown -- sin rival: ni aturdimiento ni castigo
		else
			actor.NextActionAt[action] = now + cooldown
			if result == "Failed" then
				actor.StunnedUntil = now + C.TackleStunSeconds
			end
		end
	elseif action == "Slide" then
		if hasBall then
			return
		end
		local look = MathUtil.flat(actor.Root.CFrame.LookVector)
		if look.Magnitude < 0.01 then
			return
		end
		actor.NextActionAt[action] = now + cooldown
		actor.SlideDir = look.Unit
		actor.SlideUntil = now + C.SlideSeconds
		actor.SlideResolved = false
		actor.ForcedMoveDir = look.Unit
		actor.ForcedMoveSpeed = C.SlideSpeed
		actor.ForcedMoveUntil = now + C.SlideSeconds
		actor.StunnedUntil = now + C.SlideSeconds + C.SlideRecoverySeconds -- no puede actuar hasta levantarse
		self:_publishForcedMove(actor)
	elseif action == "Juke" then
		if not hasBall then
			return
		end
		local side = if typeof(value) == "number" and (value :: number) < 0 then -1 else 1
		local look = MathUtil.flat(actor.Root.CFrame.LookVector)
		if look.Magnitude < 0.01 then
			return
		end
		local right = MathUtil.flat(actor.Root.CFrame.RightVector)
		actor.NextActionAt[action] = now + cooldown
		actor.ForcedMoveDir = (look.Unit * C.JukeForwardBias + right.Unit * side).Unit
		actor.ForcedMoveSpeed = MathUtil.mapStat(actor.Stats.Speed, Balance.Speed.Min, Balance.Speed.Max)
			* C.JukeSpeedMultiplier
		actor.ForcedMoveUntil = now + C.JukeSeconds
		actor.ImmuneUntil = now + C.JukeImmuneSeconds
		self:_publishForcedMove(actor)
	elseif action == "Flick" then
		if not hasBall then
			return
		end
		if self.Ball:flick(actor, now) then
			actor.NextActionAt[action] = now + cooldown
		end
	end
end

-- ---------------------------------------------------------------------------
-- Salida y limpieza
-- ---------------------------------------------------------------------------

function Match._removeActor(self: Match, actor: Types.Actor)
	local index = table.find(self.Actors, actor)
	if index then
		table.remove(self.Actors, index)
	end
	if self.Ball.Controller == actor then
		self.Ball.Controller = nil
		if self.Ball.State == "Controlled" then
			self.Ball.State = "Free"
		end
	end
	local player = actor.Player
	if player then
		self.ByPlayer[player] = nil
		player:SetAttribute("MatchId", nil)
		player:SetAttribute("Team", nil)
		player:SetAttribute("Stamina", nil)
		player:SetAttribute("ForceUntil", nil)
		player:SetAttribute("ForceDir", nil)
		CollisionSetup.resetActor(actor.Model)
	end
	if next(self.ByPlayer) == nil then
		self:close() -- ya no queda ningun humano
	end
end

function Match.removePlayer(self: Match, player: Player)
	local actor = self.ByPlayer[player]
	if actor then
		self:_removeActor(actor)
	end
end

function Match.close(self: Match)
	if self.Phase == "Closed" then
		return
	end
	self.Phase = "Closed"
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	for player in self.ByPlayer do
		player:SetAttribute("MatchId", nil)
		player:SetAttribute("Team", nil)
		player:SetAttribute("Stamina", nil)
		player:SetAttribute("ForceUntil", nil)
		player:SetAttribute("ForceDir", nil)
		if player.Parent then
			task.spawn(function()
				player:LoadCharacter() -- vuelve al lobby (punto de aparicion)
			end)
		end
	end
	table.clear(self.ByPlayer)

	self.Folder:Destroy() -- campo, balon y munecos
	print(`[Match {self.Id}] cerrado`)
	if self.OnClosed then
		self.OnClosed(self.Result)
	end
end

-- ---------------------------------------------------------------------------
-- Depuracion (solo se usa desde DebugService, que ya comprueba que sea Studio)
-- ---------------------------------------------------------------------------

function Match.debugGoal(self: Match, team: number)
	if self:_isLive() then
		self:_onGoal(team)
	end
end

function Match.debugSetTime(self: Match, seconds: number)
	if self.Phase == "Playing" then
		self.TimeLeft = seconds
	end
end

function Match.debugEnd(self: Match)
	if self:_isLive() then
		self:_finish()
	end
end

function Match.debugResetBall(self: Match)
	if self:_isLive() then
		self.Ball:placeAtCenter()
		self.Ball:release()
	end
end

return Match
