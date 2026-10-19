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
local BotBrain = require(script.Parent.BotBrain)

local MatchEvent = Remotes.get("MatchEvent")
local FxEvent = Remotes.get("Fx")

local TEAM_COLORS = { Color3.fromRGB(52, 120, 246), Color3.fromRGB(235, 64, 52) }
local KEEPER_COLORS = { Color3.fromRGB(245, 205, 48), Color3.fromRGB(60, 190, 90) } -- el portero viste distinto

local rng = Random.new()

export type Phase = "Preparing" | "CoinToss" | "Countdown" | "Playing" | "GoldenGoal" | "Goal" | "Final" | "Closed"

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
	GoalPending: { Team: number, Since: number }?, -- balon ya dentro de la porteria, gol pendiente de confirmar
	StartedAt: number,
	Connections: { RBXScriptConnection },
	NextBounceSoundAt: number, -- evita que los rebotes suenen 20 veces seguidas
	ActorConns: { [Types.Actor]: { RBXScriptConnection } },
	KeeperHolding: Types.Actor?, -- portero con el balon en las manos
	KeeperReleaseAt: number,
	KeeperCooldownUntil: number, -- tras sacar, el portero no puede volver a atrapar hasta este instante
	KeeperStates: { [Types.Actor]: KeeperState }, -- estado de cada portero (colocarse, estirada, en el suelo...)
	GoalSince: number?, -- patio: instante en que el balon entro entero en una porteria
	Coin: CoinState?, -- sorteo de saque (solo antes del primer saque)
	Kickoff: KickoffState?, -- saque de centro en curso (el delantero pasa atras y los rivales esperan fuera del circulo)
	Published: { [string]: any },
	Result: Types.MatchResult?,
	OnClosed: ((Types.MatchResult?) -> ())?,
}

-- Sorteo de moneda antes del partido.
-- Step: "Choose" (el capitan elige cara/cruz), "Flip" (la moneda vuela), "Decide" (el ganador elige saque),
-- "Result" (se muestra quien saca) y "Done".
type CoinState = {
	Step: string,
	Timer: number,
	Chooser: Player?, -- jugador que elige cara o cruz (capitan del equipo 1)
	Call: string?, -- "Cara" o "Cruz"
	Result: string?,
	Winner: number, -- equipo que gana el sorteo
	Decision: string?, -- "Kick" (sacar) o "Receive" (ceder el saque)
}

-- Saque de centro: el delantero que saca (Kicker) pasa a un companero al azar (Receiver) en PassAt.
-- Hasta KeepOutUntil los rivales no pueden entrar en el circulo central.
type KickoffState = {
	Kicker: Types.Actor?,
	Receiver: Types.Actor?,
	PassAt: number,
	Passed: boolean,
	KeepOutUntil: number,
}

-- Estado de un portero. Mode: "Position" (colocandose), "Set" (paso lateral), "Jump" (salto), "Dive" (estirada),
-- "Down" (en el suelo tras la estirada), "GetUp" (levantandose).
type KeeperState = {
	Mode: string,
	StandY: number, -- altura del centro del cuerpo de pie (local)
	Start: number,
	Duration: number,
	From: Vector3, -- posicion local al empezar la accion
	To: Vector3, -- posicion local al acabarla
	Peak: number, -- altura extra del salto
	Roll: number, -- giro del cuerpo en la estirada (radianes, + = hacia su derecha)
	Facing: Vector3, -- hacia donde mira (local, plano)
	PlanAt: number, -- instante en que reacciona al tiro (0 = sin tiro detectado)
	ShotSeenAt: number, -- instante en que vio venir el tiro (0 = no lo vio: tiro a bocajarro)
	Touched: boolean, -- ya toco el balon en esta accion
	DownUntil: number,
	NextLungeAt: number, -- no vuelve a tirarse a los pies de un rival hasta este instante
}

local Match = {}
Match.__index = Match

export type Match = typeof(setmetatable({} :: Fields, Match))

-- ---------------------------------------------------------------------------
-- Creacion
-- ---------------------------------------------------------------------------

local function createDummy(team: number, name: string, isKeeper: boolean): Model
	local description = Instance.new("HumanoidDescription")
	local color = if isKeeper then KEEPER_COLORS[team] else TEAM_COLORS[team]
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

	local arena = ArenaBuilder.build(origin, { Stands = true }) -- con gradas y tunel de vestuarios
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
		GoalPending = nil,
		StartedAt = os.clock(),
		Connections = {},
		NextBounceSoundAt = 0,
		ActorConns = {},
		KeeperHolding = nil,
		KeeperReleaseAt = 0,
		KeeperCooldownUntil = 0,
		KeeperStates = {},
		GoalSince = nil,
		Coin = nil,
		Kickoff = nil,
		Published = {},
		Result = nil,
		OnClosed = nil,
	}
	local self = setmetatable(fields, Match)
	table.insert(self.Connections, ball.Part.Touched:Connect(function(hit: BasePart)
		self:_onBallTouched(hit)
	end))

	folder:SetAttribute("Phase", "Preparing")
	folder:SetAttribute("OriginYaw", (select(2, origin:ToOrientation()))) -- la camara se orienta segun el campo
	folder:SetAttribute("Origin", origin.Position) -- centro del campo (lo usa el cliente para la mesa del sorteo)
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
	if Balance.CoinToss.Enabled then
		self:_enterCoinToss() -- sorteo de saque con moneda; al acabar empieza la cuenta atras
	else
		self:_enterCountdown()
	end
	return self
end

-- ---------------------------------------------------------------------------
-- Patio de juegos (campo de exhibicion del lobby): siempre activo, sin marcador, tiempo ni goles.
-- Quien entra al campo juega con el balon; si el balon se queda dentro de una porteria, vuelve al centro.
-- ---------------------------------------------------------------------------

-- El campo ya existe (lo construye SpawnService); aqui solo se crean el balon y la logica.
function Match.newPlayground(id: number, parent: Instance, origin: CFrame): Match
	local folder = Instance.new("Folder")
	folder.Name = `Match_{id}`
	folder.Parent = parent
	folder:SetAttribute("Mode", "Playground")
	folder:SetAttribute("OriginYaw", (select(2, origin:ToOrientation())))
	folder:SetAttribute("Phase", "Playing")
	local ball = Ball.new(folder, origin)

	local fields: Fields = {
		Id = id,
		Slot = -1,
		Mode = "Playground",
		Folder = folder,
		Origin = origin,
		Ball = ball,
		Actors = {},
		ByPlayer = {},
		Phase = "Playing",
		PhaseTimer = 0,
		TimeLeft = 0,
		Score = { 0, 0 },
		Scorers = {},
		KickoffTeam = 1,
		EndAfterGoal = false,
		GoalPending = nil,
		StartedAt = os.clock(),
		Connections = {},
		NextBounceSoundAt = 0,
		ActorConns = {},
		KeeperHolding = nil,
		KeeperReleaseAt = 0,
		KeeperCooldownUntil = 0,
		KeeperStates = {},
		GoalSince = nil,
		Coin = nil,
		Kickoff = nil,
		Published = {},
		Result = nil,
		OnClosed = nil,
	}
	local self = setmetatable(fields, Match)
	table.insert(self.Connections, ball.Part.Touched:Connect(function(hit: BasePart)
		self:_onBallTouched(hit)
	end))
	self:_publish("Score1", 0)
	self:_publish("Score2", 0)
	self:_publish("TimeLeft", 0)
	self:_publish("Countdown", 0)
	ball:release()
	return self
end

-- Punto del jugador en coordenadas del campo (X = largo, Z = ancho).
function Match.localPosition(self: Match, worldPosition: Vector3): Vector3
	return self.Origin:PointToObjectSpace(worldPosition)
end

-- true si "worldPosition" esta dentro del campo, con un margen (positivo = hacia dentro, negativo = hacia fuera)
function Match.isInsideField(self: Match, worldPosition: Vector3, margin: number): boolean
	local F = Balance.Field
	local p = self:localPosition(worldPosition)
	return math.abs(p.X) < F.Length / 2 - margin and math.abs(p.Z) < F.Width / 2 - margin and p.Y > -5 and p.Y < 40
end

function Match.addPlaygroundPlayer(self: Match, player: Player)
	if self.ByPlayer[player] then
		return
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	local actor = self:_createActor(1, 1, player, true) -- se queda donde esta, no se recoloca
	table.insert(self.Actors, actor)
	self.ByPlayer[player] = actor
end

function Match._updatePlayground(self: Match, dt: number, now: number)
	-- Si el balon acaba fuera del campo (o se cae), vuelve al centro
	do
		local F = Balance.Field
		local p = self.Ball:getLocalPosition()
		local out = math.abs(p.X) > F.Length / 2 + F.GoalDepth + 4
			or math.abs(p.Z) > F.Width / 2 + 4
			or p.Y < -10
			or p.Y > F.WallHeight + 10
		if out then
			self.GoalSince = nil
			self.Ball:placeAtCenter()
			self.Ball:release()
		end
	end
	if #self.Actors == 0 then
		return -- sin nadie dentro no se simula nada
	end
	self.Ball:step(dt, self.Actors, now)
	self:_updateActors(dt, now)

	-- Sin goles: si el balon se queda dentro de una porteria, vuelve al centro
	local F = Balance.Field
	local p = self.Ball:getLocalPosition()
	local radius = Balance.Ball.Diameter / 2
	local inGoal = math.abs(p.X) - radius > F.Length / 2
		and math.abs(p.Z) + radius <= F.GoalWidth / 2
		and p.Y + radius <= F.GoalHeight
	if inGoal then
		local since = self.GoalSince
		if not since then
			self.GoalSince = now
		elseif now - since >= Balance.Playground.GoalResetSeconds then
			self.GoalSince = nil
			self.Ball:placeAtCenter()
			self.Ball:release()
		end
	else
		self.GoalSince = nil
	end
end

-- ---------------------------------------------------------------------------
-- Porteros: solo se mueven por su linea de gol, siguen el balon a lo ancho y atrapan los tiros que les llegan.
-- (Los porteros humanos no existen: el slot del portero siempre es un muneco.)
-- ---------------------------------------------------------------------------

-- Distancia de un punto al segmento a-b (para tratar el cuerpo del portero como una capsula).
local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function Match._keeperState(self: Match, actor: Types.Actor): KeeperState
	local state = self.KeeperStates[actor]
	if not state then
		local rootLocal = self.Origin:PointToObjectSpace(actor.Root.Position)
		local intoField = if actor.Team == 1 then 1 else -1
		state = {
			Mode = "Position",
			StandY = rootLocal.Y,
			Start = 0,
			Duration = 0,
			From = rootLocal,
			To = rootLocal,
			Peak = 0,
			Roll = 0,
			Facing = Vector3.new(intoField, 0, 0),
			PlanAt = 0,
			ShotSeenAt = 0,
			Touched = false,
			DownUntil = 0,
			NextLungeAt = 0,
		}
		self.KeeperStates[actor] = state
	end
	return state :: KeeperState
end

-- Prediccion: donde (Z) y a que altura (Y) pasara el balon por el plano X = planeX, y cuanto tarda. nil si no llega.
local function predictCrossing(ballLocal: Vector3, ballVel: Vector3, planeX: number, maxTime: number): (number?, number, number)
	if math.abs(ballVel.X) < 1 then
		return nil, 0, 0
	end
	local t = (planeX - ballLocal.X) / ballVel.X
	if t <= 0 or t > maxTime then
		return nil, 0, 0
	end
	local radius = Balance.Ball.Diameter / 2
	local y = ballLocal.Y + ballVel.Y * t - 0.5 * workspace.Gravity * t * t
	return t, ballLocal.Z + ballVel.Z * t, math.max(radius, y)
end

-- Porteros con comportamiento "fisico": se colocan entre el balon y la porteria, ven venir el tiro, reaccionan con un
-- pequeno retraso (segun su estadistica) y hacen un paso lateral, un salto o una estirada hacia donde va a pasar el
-- balon. Solo paran si su cuerpo (una capsula de pies a manos) llega a tocar el balon: entonces lo atrapan o lo despejan.
function Match._updateKeepers(self: Match, dt: number, now: number)
	local G = Balance.Goalkeeper
	local F = Balance.Field
	local ball = self.Ball
	local ballLocal = ball:getLocalPosition()
	local ballVel = self.Origin:VectorToObjectSpace(ball.Part.AssemblyLinearVelocity)
	local ballSpeed = ballVel.Magnitude
	local ballRadius = Balance.Ball.Diameter / 2
	local ballLoose = ball.Controller == nil and ball.State ~= "Stopped" and not ball.Dead

	for _, actor in self.Actors do
		if not actor.IsGoalkeeper or actor.Player then
			continue
		end
		local state = self:_keeperState(actor)
		local ownSide = if actor.Team == 1 then -1 else 1 -- el equipo 1 defiende la porteria de -X
		local intoField = -ownSide
		local goalX = ownSide * F.Length / 2
		local rootLocal = self.Origin:PointToObjectSpace(actor.Root.Position)
		local holding = self.KeeperHolding == actor

		local position = rootLocal
		local roll = 0
		local facing = state.Facing

		-- 1) Accion en curso (paso, salto, estirada, en el suelo, levantarse)
		local mode = state.Mode
		local p = if state.Duration > 0 then math.clamp((now - state.Start) / state.Duration, 0, 1) else 1
		local ease = 1 - (1 - p) * (1 - p)
		if mode == "Set" then
			position = state.From:Lerp(state.To, ease)
			if p >= 1 then
				state.Mode = "Position"
			end
		elseif mode == "Jump" then
			local flat = state.From:Lerp(state.To, ease)
			position = Vector3.new(flat.X, state.StandY + state.Peak * math.sin(math.pi * p), flat.Z)
			if p >= 1 then
				state.Mode = "Position"
			end
		elseif mode == "Dive" then
			position = state.From:Lerp(state.To, ease) + Vector3.new(0, math.sin(math.pi * p) * 0.8, 0)
			roll = state.Roll * math.min(1, p * 1.6)
			if p >= 1 then
				state.Mode = "Down"
				state.DownUntil = now + G.DownTime
			end
		elseif mode == "Down" then
			position = state.To
			roll = state.Roll
			if now >= state.DownUntil then
				state.Mode = "GetUp"
				state.Start = now
				state.Duration = G.GetUpTime
				state.From = state.To
			end
		elseif mode == "GetUp" then
			position = Vector3.new(state.From.X, state.From.Y + (state.StandY - state.From.Y) * ease, state.From.Z)
			roll = state.Roll * (1 - ease)
			if p >= 1 then
				state.Mode = "Position"
				state.Roll = 0
			end
		end

		-- 2) Colocacion (solo de pie y sin accion): entre el balon y el centro de la porteria, dentro de su area (circular)
		if state.Mode == "Position" and mode == "Position" then
			local toBall = Vector3.new(ballLocal.X - goalX, 0, ballLocal.Z)
			local dirToBall = if toBall.Magnitude > 0.1 then toBall.Unit else Vector3.new(intoField, 0, 0)
			if dirToBall.X * intoField < 0.2 then
				dirToBall = Vector3.new(intoField * 0.2, 0, dirToBall.Z).Unit
			end
			local areaR = F.AreaRadius - 1
			local ballDist = toBall.Magnitude
			local inArea = ballDist <= areaR and (ballLocal.X - goalX) * intoField > 0
			local opponentWithBall = ball.Controller ~= nil and ball.Controller.Team ~= actor.Team
			local speed = G.MoveSpeed
			local target: Vector3
			if opponentWithBall and ballDist < G.OneOnOneDistance then
				-- 1v1: sale a achicar, quedandose a unos pasos del balon (cierra el angulo)
				local advance = math.clamp(ballDist - G.CloseDownGap, G.LineOffset, areaR)
				target = Vector3.new(goalX, 0, 0) + dirToBall * advance
				speed = G.RushSpeed
			elseif ballLoose and ballSpeed < G.RushMaxSpeed and inArea then
				-- Balon suelto y lento dentro de su area: sale a por el
				target = Vector3.new(ballLocal.X, 0, ballLocal.Z)
				speed = G.RushSpeed
			else
				-- Sin peligro inmediato: cerca de la porteria, algo adelantado segun donde este el balon
				local advance = math.clamp(ballDist * G.AdvanceFactor, G.LineOffset, G.NormalMaxAdvance)
				target = Vector3.new(goalX, 0, 0) + dirToBall * advance
			end
			-- Nunca detras de la linea de gol ni fuera de su area
			local depth = math.max((target.X - goalX) * intoField, G.LineOffset)
			target = Vector3.new(goalX + intoField * depth, 0, target.Z)
			local fromGoal = Vector3.new(target.X - goalX, 0, target.Z)
			if fromGoal.Magnitude > areaR then
				target = Vector3.new(goalX, 0, 0) + fromGoal.Unit * areaR
			end
			local delta = Vector3.new(target.X - rootLocal.X, 0, target.Z - rootLocal.Z)
			local maxStep = speed * dt
			if delta.Magnitude > maxStep then
				delta = delta.Unit * maxStep
			end
			position = Vector3.new(rootLocal.X + delta.X, state.StandY, rootLocal.Z + delta.Z)
			local look = Vector3.new(ballLocal.X - position.X, 0, ballLocal.Z - position.Z)
			if look.Magnitude > 0.5 then
				facing = look.Unit
				state.Facing = facing
			end

			-- 1v1 muy cerca: se tira a los pies del rival
			local toBallFlat = Vector3.new(ballLocal.X - position.X, 0, ballLocal.Z - position.Z)
			if opponentWithBall and toBallFlat.Magnitude <= G.LungeDistance and now >= state.NextLungeAt then
				state.NextLungeAt = now + G.LungeCooldown
				local right = facing:Cross(Vector3.yAxis)
				local sideSign = if toBallFlat:Dot(right) >= 0 then 1 else -1
				state.Mode = "Dive"
				state.Start = now
				state.Duration = G.LungeTime
				state.From = position
				state.To = Vector3.new(ballLocal.X, G.DiveMinHeight, ballLocal.Z)
				state.Roll = -sideSign * math.rad(80)
				self:_anim(actor, "KeeperDive", G.LungeTime + G.DownTime + 0.2)
				state.Touched = false
				state.ShotSeenAt = 0 -- a bocajarro
				state.PlanAt = 0
			end

			-- 3) Ve venir un tiro: reaccionara tras un pequeno retraso (mejor portero = antes)
			local comingSpeed = ballVel.X * ownSide
			if state.Mode == "Position" and not holding and ballLoose and comingSpeed > G.ShotMinSpeed and now >= self.KeeperCooldownUntil then
				local tGoal, zGoal = predictCrossing(ballLocal, ballVel, goalX, G.MaxPredictTime)
				local onTarget = tGoal ~= nil and math.abs(zGoal) <= F.GoalWidth / 2 + 2
				if onTarget and state.ShotSeenAt == 0 then
					state.ShotSeenAt = now
				end
				if onTarget and state.PlanAt == 0 and state.Mode == "Position" then
					local skill = math.clamp(actor.Stats.Goalkeeping / 100, 0, 1)
					state.PlanAt = now + G.ReactionMax + (G.ReactionMin - G.ReactionMax) * skill + rng:NextNumber() * 0.05
				elseif not onTarget then
					state.PlanAt = 0
					state.ShotSeenAt = 0
				end
			else
				state.PlanAt = 0
				if not ballLoose or comingSpeed <= 0 then
					state.ShotSeenAt = 0
				end
			end

			-- 4) Llega el momento de reaccionar: paso lateral, salto o estirada hacia donde pasara el balon
			if state.PlanAt > 0 and now >= state.PlanAt then
				state.PlanAt = 0
				local t, predZ, predY = predictCrossing(ballLocal, ballVel, position.X, G.MaxPredictTime)
				if t ~= nil then
					local dz = predZ - position.Z
					local right = facing:Cross(Vector3.yAxis) -- su derecha
					local sideSign = if (Vector3.new(0, 0, dz)):Dot(right) >= 0 then 1 else -1
					state.Start = now
					state.From = position
					state.Touched = false
					if math.abs(dz) <= G.SetReach and predY <= state.StandY + 3 then
						state.Mode = "Set"
						state.Duration = 0.2
						state.To = Vector3.new(position.X, state.StandY, predZ)
					elseif math.abs(dz) <= G.JumpReachZ then
						state.Mode = "Jump"
						state.Duration = G.JumpTime
						state.Peak = math.clamp(predY - (state.StandY + G.HandsOffset) + 1, 0.6, G.JumpHeight)
						state.To = Vector3.new(position.X, state.StandY, predZ)
						self:_anim(actor, "KeeperJump", G.JumpTime)
					else
						state.Mode = "Dive"
						state.Duration = G.DiveTime
						local reachZ = position.Z + math.clamp(dz, -G.DiveReach, G.DiveReach)
						local bodyY = math.clamp(predY, G.DiveMinHeight, state.StandY + G.DiveMaxRise)
						state.To = Vector3.new(position.X + intoField * 0.8, bodyY, reachZ)
						state.Roll = -sideSign * math.rad(80) -- cabeza hacia el lado de la estirada
						self:_anim(actor, "KeeperDive", G.DiveTime + G.DownTime + 0.2)
					end
				end
			end
		end

		-- 5) Pose final del muneco
		local bodyCf = CFrame.lookAt(position, position + facing) * CFrame.Angles(0, 0, roll)
		actor.Model:PivotTo(self.Origin * bodyCf)
		local hands = (bodyCf * CFrame.new(0, G.HandsOffset, 0)).Position
		local feet = (bodyCf * CFrame.new(0, -G.FeetOffset, 0)).Position

		-- 6) Con el balon: lo lleva en las manos y saca cuando esta de pie
		if holding then
			local carry = if state.Mode == "Position" then (bodyCf * CFrame.new(0, 0.6, -1.6)).Position else hands
			ball:keeperCarry(self.Origin:PointToWorldSpace(carry))
			if state.Mode == "Position" and now >= self.KeeperReleaseAt then
				self.KeeperHolding = nil
				local dir = self.Origin:VectorToWorldSpace(Vector3.new(intoField, 0, (rng:NextNumber() - 0.5) * 0.8)).Unit
				ball:keeperRelease(actor, dir * G.ClearSpeed + Vector3.new(0, G.ClearSpeed * G.ClearLift, 0))
				actor.ReleaseAt = now + 0.5
				self.KeeperCooldownUntil = now + G.ReleaseCooldown -- si no, lo volveria a coger al instante
			end
			continue
		end

		-- 7) Contacto: el balon toca su cuerpo (capsula pies-manos)
		-- (tambien le quita el balon a un rival que se lo lleve pegado hasta sus manos)
		local playable = ball.State ~= "Stopped" and not ball.Dead and (ball.Controller == nil or ball.Controller.Team ~= actor.Team)
		if self.KeeperHolding == nil and playable and now >= self.KeeperCooldownUntil and not state.Touched then
			local distance = distanceToSegment(ballLocal, feet, hands)
			if distance <= G.BodyRadius + ballRadius then
				state.Touched = true

				-- Dificultad de la parada (0 = facil, 1 = imposible):
				--  * fuerza del balon al llegarle
				--  * colocacion: cerca del palo, cerca del larguero y sobre todo a la escuadra
				--  * cercania: poco tiempo desde que vio venir el tiro (a bocajarro casi no hay tiempo)
				local D = G.Difficulty
				local speedTerm = math.clamp((ballSpeed - D.SpeedFrom) / D.SpeedRange, 0, 1)
				local _, zGoal, yGoal = predictCrossing(ballLocal, ballVel, goalX, 2)
				local placeZ = math.clamp(math.abs(zGoal) / (F.GoalWidth / 2), 0, 1)
				local placeY = math.clamp(yGoal / F.GoalHeight, 0, 1)
				local placement = math.clamp(0.5 * placeZ * placeZ + 0.3 * placeY * placeY + 0.8 * placeZ * placeY, 0, 1)
				local window = if state.ShotSeenAt > 0 then now - state.ShotSeenAt else 0
				local closeness = math.clamp(1 - (window - D.CloseFull) / D.CloseRange, 0, 1)
				local skill = (actor.Stats.Goalkeeping - 50) / 200
				local difficulty = math.clamp(
					D.SpeedWeight * speedTerm + D.PlaceWeight * placement + D.CloseWeight * closeness - skill,
					0,
					1
				)
				state.ShotSeenAt = 0

				if ballSpeed <= G.ClaimMaxSpeed then
					-- Balon muerto: lo bloca siempre
					ball:keeperCatch(actor, self.Origin:PointToWorldSpace(hands:Lerp(position, 0.4)))
					self:_sound("KeeperCatch", ball.Part.Position)
					self:_anim(actor, "KeeperCatch", G.HoldSeconds + 0.4)
					self.KeeperHolding = actor
					self.KeeperReleaseAt = now + G.HoldSeconds
				elseif rng:NextNumber() > math.clamp(1 - difficulty, D.MinSave, D.MaxSave) then
					-- Lo toca pero no lo para: el balon sigue, algo frenado y desviado ("se le cuela")
					local leak = Vector3.new(ballVel.X * D.LeakKeep, ballVel.Y * D.LeakKeep + 3, ballVel.Z * D.LeakKeep + (rng:NextNumber() - 0.5) * 8)
					ball:keeperParry(actor, self.Origin:VectorToWorldSpace(leak))
					self.KeeperCooldownUntil = now + G.ParryCooldown
				else
					local canCatch = difficulty <= D.CatchMaxDifficulty
					local catchChance = math.clamp(
						G.CatchBase + (actor.Stats.Goalkeeping - 50) / 100 - math.max(0, ballSpeed - G.CatchSpeedFrom) / G.CatchSpeedRange,
						0.1,
						0.95
					)
					if canCatch and rng:NextNumber() <= catchChance then
						-- Blocaje (solo en paradas faciles: tiro flojo, centrado y con tiempo)
						ball:keeperCatch(actor, self.Origin:PointToWorldSpace(hands:Lerp(position, 0.4)))
						self:_sound("KeeperCatch", ball.Part.Position)
						self:_anim(actor, "KeeperCatch", G.HoldSeconds + 0.4)
						self.KeeperHolding = actor
						self.KeeperReleaseAt = now + G.HoldSeconds
					else
						-- Parada dificil: no la puede blocar, sale rebotada hacia el campo y hacia el lado
						local sideOut = if ballLocal.Z >= position.Z then 1 else -1
						local bounce = Vector3.new(
							intoField * ballSpeed * G.ParryFactor,
							G.ParryLift,
							sideOut * ballSpeed * G.ParrySide * (0.6 + rng:NextNumber() * 0.8)
						)
						ball:keeperParry(actor, self.Origin:VectorToWorldSpace(bounce))
						self:_sound("KickShot", ball.Part.Position, 0.7, 0.85)
						self:_sound("CrowdOoh")
						self:_anim(actor, "KeeperParry")
						self.KeeperCooldownUntil = now + G.ParryCooldown
					end
				end
			end
		end
		-- Una vez de pie y sin accion, puede volver a tocar el balon
		if state.Mode == "Position" and mode == "Position" and state.Touched and (ballLocal - position).Magnitude > 6 then
			state.Touched = false
		end
	end
end

function Match._createActor(self: Match, team: number, slot: number, player: Player?, keepPosition: boolean?): Types.Actor
	local characterId = Characters.DefaultTeam[slot]
	local data = Characters.List[characterId]
	assert(data, "Falta el personaje " .. tostring(characterId))

	local model: Model
	if player and player.Character then
		model = player.Character
	else
		model = createDummy(team, data.Name, slot == Balance.Match.GoalkeeperSlot)
		model.Parent = self.Folder
	end

	local actorConns: { RBXScriptConnection } = {}
	local collisionConn = CollisionSetup.applyToActor(model) -- el balon no choca con los jugadores
	table.insert(self.Connections, collisionConn)
	table.insert(actorConns, collisionConn)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.WalkSpeed = 0

	local highlight = Instance.new("Highlight")
	highlight.FillColor = TEAM_COLORS[team]
	highlight.OutlineColor = TEAM_COLORS[team]
	highlight.FillTransparency = 0.6
	highlight.Name = "MatchHighlight"
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
		Controllable = player ~= nil or (Balance.Bots.Enabled and slot ~= Balance.Match.GoalkeeperSlot),
		IsGoalkeeper = slot == Balance.Match.GoalkeeperSlot,
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
		local diedConn = humanoid.Died:Connect(function()
			self:_removeActor(actor)
		end)
		table.insert(self.Connections, diedConn)
		table.insert(actorConns, diedConn)
	end
	self.ActorConns[actor] = actorConns

	if not keepPosition then
		self:_placeActor(actor)
	end
	if not player then
		if actor.Controllable then
			-- Bot de campo: lo mueve BotBrain desde el servidor
			root.Anchored = false
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			-- Que no se caiga al chocar con otros jugadores (si se tumba, ya no puede moverse)
			for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Physics, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated } do
				humanoid:SetStateEnabled(state, false)
			end
			-- Ademas, lo mantiene siempre de pie (solo puede girar sobre si mismo)
			local upright = Instance.new("AlignOrientation")
			upright.Name = "BotUpright"
			upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
			upright.AlignType = Enum.AlignType.PrimaryAxisParallel
			upright.PrimaryAxis = Vector3.yAxis
			upright.RigidityEnabled = false
			upright.MaxTorque = 1e6
			upright.Responsiveness = 60
			local attachment = Instance.new("Attachment")
			attachment.Name = "BotUprightAttachment"
			attachment.CFrame = CFrame.Angles(0, 0, math.pi / 2) -- su eje principal (X) = el "arriba" del cuerpo
			attachment.Parent = root
			upright.Attachment0 = attachment
			upright.Parent = root
		else
			root.Anchored = true -- portero bot: lo mueve _updateKeepers
		end
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

-- Sonido para los jugadores del partido. "position" nil = sonido global (publico, silbato).
function Match._sound(self: Match, name: string, position: Vector3?, volume: number?, pitch: number?, count: number?)
	for player in self.ByPlayer do
		FxEvent:FireClient(player, "Sound", name, position, volume or 1, pitch or 1, count or 1)
	end
end

-- Animacion sencilla (por codigo, sin assets) de un personaje, vista por los jugadores del partido.
function Match._anim(self: Match, actor: Types.Actor, kind: string, duration: number?, side: number?)
	for player in self.ByPlayer do
		FxEvent:FireClient(player, "Anim", actor.Model, kind, duration or 0, side or 1)
	end
end

-- Rebotes del balon: muros, redes, suelo (solo si cae con fuerza)
function Match._onBallTouched(self: Match, hit: BasePart)
	local now = os.clock()
	if now < self.NextBounceSoundAt or self.Ball.State == "Stopped" then
		return
	end
	if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then
		return -- personajes: no (el balon no choca con ellos)
	end
	local velocity = self.Ball.Part.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	local name = hit.Name
	if string.find(name, "Goal") and string.find(name, "Net") then
		self:_sound("Net", self.Ball.Part.Position, math.clamp(speed / 50, 0.35, 1))
	elseif name == "Floor" then
		if math.abs(velocity.Y) < 18 then
			return
		end
		self:_sound("Bounce", self.Ball.Part.Position, math.clamp(math.abs(velocity.Y) / 70, 0.15, 0.6), 1.15)
	elseif hit.Anchored and speed > 12 then
		self:_sound("Bounce", self.Ball.Part.Position, math.clamp(speed / 80, 0.25, 1))
	else
		return
	end
	self.NextBounceSoundAt = now + 0.12
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
	local formation = Balance.Formation[actor.Slot] or { X = 0, Z = 0 }
	local distance = formation.X
	if actor.IsGoalkeeper then
		distance = Balance.Field.Length / 2 - Balance.Goalkeeper.LineOffset -- en su linea de gol
	elseif actor.Slot == 1 then
		distance = if actor.Team == self.KickoffTeam then Balance.Kickoff.Near else Balance.Kickoff.Far
	end
	local side = if actor.Team == 1 then -1 else 1 -- el equipo 1 empieza en -X y ataca hacia +X
	local z = if actor.Team == 1 then formation.Z else -formation.Z
	local position = Vector3.new(side * distance, 3.2, z)
	local facing = Vector3.new(-side, 0, 0)
	if actor.Slot == 1 and not actor.IsGoalkeeper and actor.Team == self.KickoffTeam then
		-- El que saca se pone por detras del balon (en el campo rival) mirando a su propio campo: pasa hacia atras
		position = Vector3.new(-side * distance, 3.2, z)
		facing = Vector3.new(side, 0, 0)
	end

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

-- ---------------------------------------------------------------------------
-- Sorteo de saque (moneda). El servidor decide el resultado; los clientes solo lo animan.
-- Se publica en atributos de la carpeta del partido: CoinStep, CoinChooser, CoinCall, CoinResult, CoinWinner,
-- CoinDecision, CoinFlipAt (hora del servidor en que se lanza) y CoinDeadline (fin del paso actual, para el reloj).
-- ---------------------------------------------------------------------------

function Match._setCoinStep(self: Match, step: string, seconds: number)
	local coin = self.Coin :: CoinState
	coin.Step = step
	coin.Timer = seconds
	self.Folder:SetAttribute("CoinStep", step)
	self.Folder:SetAttribute("CoinDeadline", workspace:GetServerTimeNow() + seconds)
end

function Match._teamHasHuman(self: Match, team: number): boolean
	for _, actor in self.Actors do
		if actor.Player and actor.Team == team then
			return true
		end
	end
	return false
end

function Match._enterCoinToss(self: Match)
	-- Elige el capitan del equipo 1 (en el modo de un jugador, el propio jugador)
	local chooser: Player? = nil
	for _, actor in self.Actors do
		if actor.Player and actor.Team == 1 then
			chooser = actor.Player
			break
		end
	end
	self.Coin = { Step = "Choose", Timer = 0, Chooser = chooser, Call = nil, Result = nil, Winner = 0, Decision = nil }
	local folder = self.Folder
	folder:SetAttribute("CoinChooser", if chooser then chooser.UserId else 0)
	folder:SetAttribute("CoinCall", "")
	folder:SetAttribute("CoinResult", "")
	folder:SetAttribute("CoinWinner", 0)
	folder:SetAttribute("CoinDecision", "")
	folder:SetAttribute("CoinFlipAt", 0)
	self:_setCoinStep("Choose", Balance.CoinToss.ChooseSeconds)
	self:_setPhase("CoinToss", 0)
	if not chooser then
		self:_coinCall(if rng:NextNumber() < 0.5 then "Cara" else "Cruz")
	end
end

-- El equipo 1 pide cara o cruz: se lanza la moneda (el resultado se decide ya, pero el cliente lo revela al caer).
function Match._coinCall(self: Match, call: string)
	local coin = self.Coin :: CoinState
	if coin.Step ~= "Choose" then
		return
	end
	coin.Call = call
	coin.Result = if rng:NextNumber() < 0.5 then "Cara" else "Cruz"
	coin.Winner = if coin.Call == coin.Result then 1 else 2
	local folder = self.Folder
	folder:SetAttribute("CoinCall", call)
	folder:SetAttribute("CoinResult", coin.Result)
	folder:SetAttribute("CoinWinner", coin.Winner)
	folder:SetAttribute("CoinFlipAt", workspace:GetServerTimeNow() + 0.2) -- pequeno margen: todos lo ven a la vez
	self:_setCoinStep("Flip", Balance.CoinToss.FlipSeconds + 0.2)
end

-- El ganador del sorteo elige: "Kick" (sacar) o "Receive" (ceder el saque al rival).
function Match._coinDecide(self: Match, decision: string)
	local coin = self.Coin :: CoinState
	if coin.Step ~= "Decide" and coin.Step ~= "Flip" then
		return
	end
	coin.Decision = decision
	local other = if coin.Winner == 1 then 2 else 1
	self.KickoffTeam = if decision == "Kick" then coin.Winner else other
	self.Folder:SetAttribute("CoinDecision", decision)
	self:_setCoinStep("Result", Balance.CoinToss.ResultSeconds)
end

function Match._updateCoinToss(self: Match, dt: number)
	local coin = self.Coin
	if not coin then
		self:_enterCountdown()
		return
	end
	coin.Timer -= dt
	if coin.Timer > 0 then
		return
	end
	local T = Balance.CoinToss
	if coin.Step == "Choose" then
		-- No eligio a tiempo: se elige al azar
		self:_coinCall(if rng:NextNumber() < 0.5 then "Cara" else "Cruz")
	elseif coin.Step == "Flip" then
		if self:_teamHasHuman(coin.Winner) then
			self:_setCoinStep("Decide", T.DecideSeconds)
		else
			-- Gana la maquina: decide sola
			self:_coinDecide(if rng:NextNumber() < T.AIKickChance then "Kick" else "Receive")
		end
	elseif coin.Step == "Decide" then
		self:_coinDecide("Kick") -- no decidio a tiempo: saca
	elseif coin.Step == "Result" then
		coin.Step = "Done"
		self.Folder:SetAttribute("CoinStep", "Done")
		self:_enterCountdown()
	end
end

function Match._handleCoinAction(self: Match, player: Player, action: string, value: any)
	local coin = self.Coin
	if self.Phase ~= "CoinToss" or not coin then
		return
	end
	if action == "CoinCall" then
		if coin.Step == "Choose" and player == coin.Chooser and (value == "Cara" or value == "Cruz") then
			self:_coinCall(value :: string)
		end
	elseif action == "CoinDecide" then
		local actor = self.ByPlayer[player]
		if coin.Step == "Decide" and actor and actor.Team == coin.Winner and (value == "Kick" or value == "Receive") then
			self:_coinDecide(value :: string)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Saque de centro (reglas como en el futbol): el delantero del equipo que saca la pasa hacia atras, a un
-- companero al azar (portero incluido), y los rivales esperan fuera del circulo central.
-- ---------------------------------------------------------------------------

function Match._startKickoff(self: Match, now: number)
	local K = Balance.Kickoff
	local team = self.KickoffTeam
	-- Quien saca: el delantero (slot 1); si no esta, cualquier jugador de campo del equipo
	local kicker: Types.Actor? = nil
	for _, actor in self.Actors do
		if actor.Team == team and actor.Slot == 1 then
			kicker = actor
		end
	end
	if not kicker then
		for _, actor in self.Actors do
			if actor.Team == team and not actor.IsGoalkeeper then
				kicker = actor
				break
			end
		end
	end
	-- A quien: un companero al azar (los otros de campo o el portero)
	local mates: { Types.Actor } = {}
	for _, actor in self.Actors do
		if actor.Team == team and actor ~= kicker then
			table.insert(mates, actor)
		end
	end
	local receiver = if #mates > 0 then mates[rng:NextInteger(1, #mates)] else nil
	if not kicker or not receiver then
		self.Ball:release() -- no hay con quien sacar: balon libre como antes
		self.Kickoff = nil
		return
	end
	self.Kickoff = {
		Kicker = kicker,
		Receiver = receiver,
		PassAt = now + K.PassDelay,
		Passed = false,
		KeepOutUntil = math.huge,
	}
	-- El que saca se gira hacia el companero
	local kickerActor = kicker :: Types.Actor
	local from = kickerActor.Root.Position
	local to = (receiver :: Types.Actor).Root.Position
	local look = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if look.Magnitude > 0.1 then
		kickerActor.Model:PivotTo(CFrame.lookAt(from, from + look))
	end
end

function Match._updateKickoff(self: Match, now: number)
	local kickoff = self.Kickoff
	if not kickoff then
		return
	end
	local K = Balance.Kickoff
	if not kickoff.Passed and now >= kickoff.PassAt then
		local kicker = kickoff.Kicker
		local receiver = kickoff.Receiver
		kickoff.Passed = true
		kickoff.KeepOutUntil = now + K.KeepOutSeconds
		local valid = kicker ~= nil and receiver ~= nil and table.find(self.Actors, kicker) ~= nil
			and table.find(self.Actors, receiver) ~= nil
		if valid then
			self.Ball:kickoffPass(kicker :: Types.Actor, receiver :: Types.Actor)
			self:_sound("KickPass", self.Ball.Part.Position)
			self:_anim(kicker :: Types.Actor, "Pass")
		else
			self.Ball:release()
		end
	end
	if now >= kickoff.KeepOutUntil then
		self.Kickoff = nil
		return
	end
	-- Rivales fuera del circulo central (los humanos; los munecos ya estan colocados fuera)
	local radius = Balance.Field.CenterCircleRadius + K.KeepOutMargin
	for _, actor in self.Actors do
		if actor.Team ~= self.KickoffTeam and actor.Controllable and actor.Root.Parent then
			local localPos = self.Origin:PointToObjectSpace(actor.Root.Position)
			local flat = Vector3.new(localPos.X, 0, localPos.Z)
			if flat.Magnitude < radius then
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(if actor.Team == 1 then -1 else 1, 0, 0)
				local edge = dir * radius
				local target = self.Origin:PointToWorldSpace(Vector3.new(edge.X, localPos.Y, edge.Z))
				local root = actor.Root
				actor.Model:PivotTo(CFrame.new(target) * root.CFrame.Rotation)
				local vel = root.AssemblyLinearVelocity
				local worldDir = self.Origin:VectorToWorldSpace(dir)
				local inward = vel:Dot(-worldDir)
				if inward > 0 then
					root.AssemblyLinearVelocity = vel + worldDir * inward -- quita la parte que va hacia dentro
				end
			end
		end
	end
end

function Match._enterCountdown(self: Match)
	self.Kickoff = nil
	self.GoalPending = nil
	self.KeeperHolding = nil
	table.clear(self.KeeperStates) -- el portero vuelve a su sitio y de pie
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
		if self.Ball.Controller == actor then
			actor.Humanoid.WalkSpeed *= Balance.Control.DribbleSpeedFactor -- con balon se corre algo menos
		end
		if live and now < actor.ForcedMoveUntil then
			actor.Humanoid.WalkSpeed = actor.ForcedMoveSpeed -- segada o regate: velocidad impuesta
		end
		local kickoff = self.Kickoff
		if kickoff and not kickoff.Passed and kickoff.Kicker == actor then
			actor.Humanoid.WalkSpeed = 0 -- el que saca espera quieto a hacer el pase
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
	if self.Mode == "Playground" then
		self:_updatePlayground(dt, now)
		return
	end
	self.Ball:step(dt, self.Actors, now)
	self:_updateActors(dt, now)
	if self:_isLive() then
		for _, actor in self.Actors do
			if now < actor.SlideUntil and not actor.SlideResolved then
				local slideResult = self.Ball:slideContact(actor, now)
				if slideResult == "Won" then
					self:_sound("Tackle", actor.Root.Position)
				elseif slideResult == "Poke" then
					self:_sound("KickPass", self.Ball.Part.Position, 0.7)
				end
			end
		end
		self:_updateKeepers(dt, now)
	end
	if Balance.Bots.Enabled then
		BotBrain.update(self, dt, now)
	end

	if phase == "CoinToss" then
		self:_updateCoinToss(dt)
	elseif phase == "Countdown" then
		self.PhaseTimer -= dt
		self:_publish("Countdown", math.ceil(math.max(self.PhaseTimer, 0)))
		if self.PhaseTimer <= 0 then
			self:_setPhase("Playing", 0)
			self:_sound("Whistle")
			self:_startKickoff(now)
		end
	elseif phase == "Playing" then
		self:_updateKickoff(now)
		self.TimeLeft = math.max(0, self.TimeLeft - dt)
		self:_publish("TimeLeft", math.ceil(self.TimeLeft))
		if not self:_checkGoal() and self.TimeLeft <= 0 then
			if self.Score[1] == self.Score[2] then
				self:_setPhase("GoldenGoal", Balance.Match.GoldenGoalSeconds)
				self:_sound("Whistle", nil, 1, 1, 2)
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
	local pending = self.GoalPending
	if not pending then
		local F = Balance.Field
		local p = self.Ball:getLocalPosition()
		local radius = Balance.Ball.Diameter / 2
		local crossedLine = math.abs(p.X) - radius > F.Length / 2
		local betweenPosts = math.abs(p.Z) + radius <= F.GoalWidth / 2
		local underBar = p.Y + radius <= F.GoalHeight
		if not (crossedLine and betweenPosts and underBar) then
			return false
		end
		-- Entro entero: el gol ya no se puede deshacer. El balon se "mata" (sin rebote, sin control) y el gol
		-- se confirma tras GoalConfirmSeconds, para que el cliente (que ve el balon con retraso) lo vea entrar.
		pending = { Team = if p.X > 0 then 1 else 2, Since = os.clock() }
		self.GoalPending = pending
		self.Ball:kill()
	end

	-- Devuelve true mientras esta pendiente para que el tiempo no pueda acabar el partido a mitad del gol.
	local goal = pending :: { Team: number, Since: number }
	if os.clock() - goal.Since >= Balance.Match.GoalConfirmSeconds then
		self.GoalPending = nil
		self:_onGoal(goal.Team)
	end
	return true
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
	self:_sound("CrowdGoal")
	self:_sound("Whistle")
	if lastTouch and lastTouch.Team == team and not lastTouch.IsGoalkeeper then
		self:_anim(lastTouch, "Celebrate", Balance.Match.GoalCelebrationSeconds - 0.5)
	end
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
	self:_sound("Whistle", nil, 1, 1, 3) -- final: tres pitidos
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
	if action == "CoinCall" or action == "CoinDecide" then
		self:_handleCoinAction(player, action, value)
		return
	end
	self:performAction(actor, action, value)
end

-- Ejecuta una accion de un actor (jugador humano o bot): mismas reglas para todos.
-- "passDistance" solo lo usan los bots: pase con la fuerza justa para llegar a esa distancia.
function Match.performAction(self: Match, actor: Types.Actor, action: string, value: any, passDistance: number?)
	if not self:_isLive() then
		return
	end
	local kickoff = self.Kickoff
	if kickoff and not kickoff.Passed and kickoff.Kicker == actor then
		return -- el que saca no puede hacer nada hasta que se haga el pase de saque
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

	if action == "Pass" or action == "Shoot" or action == "ShootHigh" then
		-- Tambien sirven sin tener el balon controlado (golpear un balon suelto a tu alcance); kick() lo valida.
		-- Carga (0..1): cuanto se ha mantenido la tecla. Sirve para el tiro y tambien para el pase.
		local charge = if typeof(value) == "number" then math.clamp(value :: number, 0, 1) else Balance.Kick.PassDefaultCharge
		local aimDir: Vector3? = nil
		if action == "Pass" and not passDistance then
			aimDir = self:_passAssist(actor) -- humano: pequena ayuda hacia el companero al que apunta
		end
		if self.Ball:kick(actor, action, charge, self:_goalPosition(actor.Team), passDistance, aimDir) then
			actor.NextActionAt[action] = now + cooldown
			if action == "Pass" then
				self:_sound("KickPass", self.Ball.Part.Position)
			else
				self:_sound("KickShot", self.Ball.Part.Position, 0.6 + 0.4 * charge)
			end
			self:_anim(actor, action)
		end
	elseif action == "Tackle" then
		if hasBall then
			return
		end
		local result = self.Ball:tackle(actor, now)
		self:_anim(actor, "Tackle")
		if result == "Won" then
			self:_sound("Tackle", actor.Root.Position)
		end
		if result == "NoTarget" or result == "Dodged" then
			actor.NextActionAt[action] = now + C.TackleWhiffCooldown -- sin rival (o te ha regateado): sin aturdimiento
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
		self:_anim(actor, "Slide", C.SlideSeconds + C.SlideRecoverySeconds)
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
		self:_anim(actor, "Juke", nil, side)
	elseif action == "Flick" then
		if not hasBall then
			return
		end
		if self.Ball:flick(actor, now) then
			actor.NextActionAt[action] = now + cooldown
			self:_sound("KickPass", self.Ball.Part.Position, 0.5, 1.2)
			self:_anim(actor, "Flick")
		end
	end
end

-- Ayuda de pase para humanos: si hay un companero dentro del cono hacia el que mira, el pase se orienta hacia el
-- (un poco por delante si va corriendo). Devuelve nil si no hay nadie en el cono.
function Match._passAssist(self: Match, actor: Types.Actor): Vector3?
	local K = Balance.Kick
	local look = MathUtil.flat(actor.Root.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return nil
	end
	look = look.Unit
	local best: Vector3? = nil
	local bestScore = math.huge
	for _, mate in self.Actors do
		if mate == actor or mate.Team ~= actor.Team or not mate.Root.Parent then
			continue
		end
		local lead = mate.Root.Position + MathUtil.flat(mate.Root.AssemblyLinearVelocity) * K.PassAssistLead
		local to = MathUtil.flat(lead - actor.Root.Position)
		local distance = to.Magnitude
		if distance < 4 or distance > 90 then
			continue
		end
		local angle = math.deg(math.acos(math.clamp(look:Dot(to.Unit), -1, 1)))
		if angle <= K.PassAssistCone then
			local score = angle + distance * 0.05
			if score < bestScore then
				bestScore = score
				best = to.Unit
			end
		end
	end
	if not best then
		return nil
	end
	return look:Lerp(best :: Vector3, K.PassAssist).Unit
end

-- ---------------------------------------------------------------------------
-- Salida y limpieza
-- ---------------------------------------------------------------------------

function Match._removeActor(self: Match, actor: Types.Actor)
	local index = table.find(self.Actors, actor)
	if index then
		table.remove(self.Actors, index)
	end
	local conns = self.ActorConns[actor]
	if conns then
		for _, connection in conns do
			connection:Disconnect()
		end
		self.ActorConns[actor] = nil
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
		if self.Mode == "Playground" then
			-- En el patio el personaje sigue vivo en el lobby: se le devuelven sus valores normales
			local highlight = actor.Model:FindFirstChild("MatchHighlight")
			if highlight then
				highlight:Destroy()
			end
			if actor.Humanoid.Parent then
				actor.Humanoid.WalkSpeed = 16
				actor.Humanoid.UseJumpPower = true
				actor.Humanoid.JumpPower = 50
			end
		end
	end
	if self.Mode ~= "Playground" and next(self.ByPlayer) == nil then
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
		self.KeeperHolding = nil
		table.clear(self.KeeperStates)
		self.Ball:placeAtCenter()
		self.Ball:release()
	end
end

return Match
