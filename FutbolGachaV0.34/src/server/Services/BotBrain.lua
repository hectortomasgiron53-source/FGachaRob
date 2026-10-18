--!strict
--[[
	BotBrain: jugadores de campo controlados por la maquina (nivel 1).
	Cada bot, varias veces por segundo, decide a donde ir:
	  - El jugador de su equipo mas cercano al balon va a por el (si es un humano, los bots le dejan).
	  - Si un rival tiene el balon, el que va a por el le presiona e intenta la entrada.
	  - El resto se coloca en su sitio de la formacion, que se mueve con el balon: suben cuando su equipo ataca
	    y bajan cuando defiende, sin amontonarse.
	  - Con balon: conduce hacia la porteria rival, tira si esta cerca y con angulo, pasa a un companero
	    si un rival le presiona (o a veces a uno mejor colocado) y de vez en cuando intenta una croqueta.
	Los bots usan las mismas acciones y reglas que un jugador humano (Match.performAction).
	Los porteros no estan aqui: los lleva Match._updateKeepers.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Types = require(ReplicatedStorage.Shared.Types)

local BotBrain = {}

local rng = Random.new()

-- Animaciones de serie de Roblox (R15) para que los bots no "patinen"
local RUN_ANIM = "rbxassetid://507767714"
local IDLE_ANIM = "rbxassetid://507766666"

type Memory = {
	Target: Vector3, -- objetivo en coordenadas del campo
	Chasing: boolean,
	HadBall: boolean, -- tenia el balon el fotograma anterior
	NextThinkAt: number,
	NextDecisionAt: number,
	NextTackleAt: number,
	Run: AnimationTrack?,
	Idle: AnimationTrack?,
	AnimFailed: boolean,
}

local memories: { [Types.Actor]: Memory } = setmetatable({}, { __mode = "k" }) :: any

local function memoryOf(actor: Types.Actor): Memory
	local m = memories[actor]
	if not m then
		local created: Memory = {
			Target = Vector3.zero,
			Chasing = false,
			HadBall = false,
			NextThinkAt = 0,
			NextDecisionAt = 0,
			NextTackleAt = 0,
			Run = nil,
			Idle = nil,
			AnimFailed = false,
		}
		memories[actor] = created
		m = created
	end
	return m :: Memory
end

local function isBot(actor: Types.Actor): boolean
	return actor.Player == nil and actor.Controllable and not actor.IsGoalkeeper
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- ---------------------------------------------------------------------------
-- Animaciones (correr / parado)
-- ---------------------------------------------------------------------------

local function updateAnimation(actor: Types.Actor, m: Memory, speed: number)
	if m.AnimFailed then
		return
	end
	if not m.Run then
		local ok = pcall(function()
			local found = actor.Humanoid:FindFirstChildOfClass("Animator")
			local animator: Animator
			if found then
				animator = found
			else
				animator = Instance.new("Animator")
				animator.Parent = actor.Humanoid
			end
			local run = Instance.new("Animation")
			run.AnimationId = RUN_ANIM
			local idle = Instance.new("Animation")
			idle.AnimationId = IDLE_ANIM
			m.Run = animator:LoadAnimation(run)
			m.Idle = animator:LoadAnimation(idle)
		end)
		if not ok or not m.Run then
			m.AnimFailed = true
			return
		end
	end
	local run = m.Run :: AnimationTrack
	local idle = m.Idle :: AnimationTrack
	if speed > 1.5 then
		if not run.IsPlaying then
			idle:Stop(0.2)
			run:Play(0.2)
		end
		run:AdjustSpeed(math.clamp(speed / 16, 0.6, 1.8))
	elseif not idle.IsPlaying then
		run:Stop(0.2)
		idle:Play(0.2)
	end
end

-- ---------------------------------------------------------------------------
-- Utilidades del campo (todo en coordenadas locales: X = largo, Z = ancho)
-- ---------------------------------------------------------------------------

local function ownSide(team: number): number
	return if team == 1 then -1 else 1 -- el equipo 1 defiende la porteria de -X
end

local function clampToField(p: Vector3, margin: number): Vector3
	local F = Balance.Field
	return Vector3.new(
		math.clamp(p.X, -F.Length / 2 + margin, F.Length / 2 - margin),
		0,
		math.clamp(p.Z, -F.Width / 2 + margin, F.Width / 2 - margin)
	)
end

local function localPos(match: any, actor: Types.Actor): Vector3
	return flat(match.Origin:PointToObjectSpace(actor.Root.Position))
end

-- Distancia de un punto a un segmento (para saber si un rival corta la linea de pase)
local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function faceTowards(match: any, actor: Types.Actor, localTarget: Vector3)
	local root = actor.Root
	local from = root.Position
	local to = match.Origin:PointToWorldSpace(Vector3.new(localTarget.X, 0, localTarget.Z))
	local look = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if look.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(from, from + look)
	end
end

-- ---------------------------------------------------------------------------
-- Decisiones con balon
-- ---------------------------------------------------------------------------

-- Mejor companero para pasar: adelantado, libre de rivales en la linea de pase y no demasiado lejos.
local function bestPassTarget(match: any, actor: Types.Actor, myPos: Vector3, attack: number, requireBetter: boolean): Types.Actor?
	local best: Types.Actor? = nil
	local bestScore = -math.huge
	for _, mate in match.Actors do
		if mate == actor or mate.Team ~= actor.Team or not mate.Root.Parent then
			continue
		end
		local matePos = localPos(match, mate)
		local distance = (matePos - myPos).Magnitude
		if distance < 6 or distance > 70 then
			continue
		end
		local open = math.huge
		for _, rival in match.Actors do
			if rival.Team ~= actor.Team and rival.Root.Parent then
				open = math.min(open, distanceToSegment(localPos(match, rival), myPos, matePos))
			end
		end
		if open < 3.5 then
			continue -- un rival corta el pase
		end
		local advance = (matePos.X - myPos.X) * attack
		if requireBetter and advance < 10 then
			continue
		end
		local score = advance * 0.6 + math.min(open, 15) * 1.5 - distance * 0.15
		if mate.IsGoalkeeper then
			score -= 25 -- al portero solo si no hay otra cosa
		end
		if score > bestScore then
			bestScore = score
			best = mate
		end
	end
	return best
end

local function onBall(match: any, actor: Types.Actor, m: Memory, now: number, myPos: Vector3)
	local B = Balance.Bots
	local F = Balance.Field
	local attack = -ownSide(actor.Team)
	local goal = Vector3.new(attack * F.Length / 2, 0, 0)
	local toGoal = goal - myPos

	-- Rival mas cercano (presion)
	local nearestRival: Vector3? = nil
	local pressure = math.huge
	for _, rival in match.Actors do
		if rival.Team ~= actor.Team and rival.Root.Parent then
			local d = (localPos(match, rival) - myPos).Magnitude
			if d < pressure then
				pressure = d
				nearestRival = localPos(match, rival)
			end
		end
	end

	if now >= m.NextDecisionAt then
		m.NextDecisionAt = now + B.DecisionInterval * (0.8 + rng:NextNumber() * 0.4)
		-- Angulo de porteria visto desde el bot (entre los dos palos)
		local postA = Vector3.new(goal.X, 0, F.GoalWidth / 2) - myPos
		local postB = Vector3.new(goal.X, 0, -F.GoalWidth / 2) - myPos
		local angle = 0
		if postA.Magnitude > 0.1 and postB.Magnitude > 0.1 then
			angle = math.deg(math.acos(math.clamp(postA.Unit:Dot(postB.Unit), -1, 1)))
		end
		if toGoal.Magnitude <= B.ShootRange and angle >= B.ShootMinAngle then
			-- Tiro: apunta a un punto entre los palos (no siempre al centro)
			local aimZ = (rng:NextNumber() * 2 - 1) * F.GoalWidth * 0.35
			faceTowards(match, actor, Vector3.new(goal.X, 0, aimZ))
			local charge = math.clamp(0.35 + toGoal.Magnitude / B.ShootRange * 0.5 + rng:NextNumber() * 0.15, 0, 1)
			match:performAction(actor, if rng:NextNumber() < 0.2 then "ShootHigh" else "Shoot", charge)
			return
		end
		if pressure < B.PressureRange then
			if rng:NextNumber() < B.PassChance then
				local mate = bestPassTarget(match, actor, myPos, attack, false)
				if mate then
					faceTowards(match, actor, localPos(match, mate))
					match:performAction(actor, "Pass", nil)
					return
				end
			end
			if rng:NextNumber() < B.JukeChance then
				match:performAction(actor, "Juke", if rng:NextNumber() < 0.5 then -1 else 1)
			end
		elseif rng:NextNumber() < B.LongPassChance then
			local mate = bestPassTarget(match, actor, myPos, attack, true)
			if mate then
				faceTowards(match, actor, localPos(match, mate))
				match:performAction(actor, "Pass", nil)
				return
			end
		end
	end

	-- Conducir hacia la porteria, esquivando al rival que tenga delante
	local dir = if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.new(attack, 0, 0)
	if nearestRival and pressure < 10 then
		local toRival = (nearestRival :: Vector3) - myPos
		if toRival.Magnitude > 0.1 and toRival.Unit:Dot(dir) > 0.3 then
			local side = Vector3.new(-dir.Z, 0, dir.X)
			if side:Dot(toRival) > 0 then
				side = -side
			end
			dir = (dir + side * 0.9).Unit
		end
	end
	m.Target = clampToField(myPos + dir * 10, 4)
	m.Chasing = false
	actor.SprintWanted = pressure > 9
end

-- ---------------------------------------------------------------------------
-- Sin balon: a por el balon o a su sitio
-- ---------------------------------------------------------------------------

local function supportTarget(match: any, actor: Types.Actor, ballPos: Vector3, possession: number?): Vector3
	local B = Balance.Bots
	local side = ownSide(actor.Team)
	local attack = -side
	local formation = Balance.Formation[actor.Slot] or { X = 0, Z = 0 }
	local baseX = side * formation.X * 0.6
	local baseZ = if actor.Team == 1 then formation.Z else -formation.Z
	local x = baseX + ballPos.X * B.FollowBall
	if possession == actor.Team then
		x += attack * B.AttackPush
		if actor.Slot == 1 then
			x += attack * 8 -- el delantero se queda arriba
		end
	elseif possession ~= nil then
		x -= attack * B.DefendDrop
	end
	local z = baseZ + (ballPos.Z - baseZ) * B.FollowBallSide
	return clampToField(Vector3.new(x, 0, z), 6)
end

local function think(match: any, actor: Types.Actor, m: Memory, now: number, myPos: Vector3, chaser: Types.Actor?)
	local B = Balance.Bots
	local ball = match.Ball
	local ballPos = flat(ball:getLocalPosition())
	local ballVel = flat(match.Origin:VectorToObjectSpace(ball.Part.AssemblyLinearVelocity))
	local controller: Types.Actor? = ball.Controller
	local possession: number? = if controller then controller.Team else nil

	if chaser == actor then
		m.Chasing = true
		if controller and controller.Team ~= actor.Team then
			m.Target = localPos(match, controller) -- presionar al que lleva el balon
		else
			m.Target = clampToField(ballPos + ballVel * B.ChaseLead, 1)
		end
	else
		m.Chasing = false
		m.Target = supportTarget(match, actor, ballPos, possession)
		-- Separarse de los companeros que esten demasiado cerca
		for _, mate in match.Actors do
			if mate ~= actor and mate.Team == actor.Team and not mate.IsGoalkeeper and mate.Root.Parent then
				local away = m.Target - localPos(match, mate)
				if away.Magnitude < B.MinSpacing then
					local push = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
					m.Target = clampToField(m.Target + push * (B.MinSpacing - away.Magnitude), 6)
				end
			end
		end
	end

	-- Saque de centro: los rivales esperan fuera del circulo central
	local kickoff = match.Kickoff
	if kickoff and actor.Team ~= match.KickoffTeam then
		local radius = Balance.Field.CenterCircleRadius + Balance.Kickoff.KeepOutMargin + 1
		if m.Target.Magnitude < radius then
			local dir = if m.Target.Magnitude > 0.1 then m.Target.Unit else Vector3.new(ownSide(actor.Team), 0, 0)
			m.Target = dir * radius
		end
	end
end

-- Quien de cada equipo va a por el balon: el mas cercano (humano incluido). Nadie si ya lo tiene su equipo.
local function chaserOf(match: any, team: number, now: number): Types.Actor?
	local ball = match.Ball
	local controller: Types.Actor? = ball.Controller
	if controller and controller.Team == team then
		return nil
	end
	if ball.ProtectedBy and now < ball.ProtectedUntil then
		local protected = ball.ProtectedBy :: Types.Actor
		return if protected.Team == team then protected else nil
	end
	local ballPos = flat(ball:getLocalPosition())
	local best: Types.Actor? = nil
	local bestDistance = math.huge
	for _, actor in match.Actors do
		if actor.Team == team and actor.Controllable and not actor.IsGoalkeeper and actor.Root.Parent then
			local d = (localPos(match, actor) - ballPos).Magnitude
			if now < actor.StunnedUntil then
				d += 15 -- aturdido: mejor que vaya otro
			end
			if d < bestDistance then
				bestDistance = d
				best = actor
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
-- Bucle (lo llama Match.update cada Heartbeat)
-- ---------------------------------------------------------------------------

function BotBrain.update(match: any, _dt: number, now: number)
	local live = match:_isLive()
	local kickoff = match.Kickoff
	local waitingKickoff = kickoff ~= nil and not kickoff.Passed
	local chasers: { [number]: Types.Actor? } = {}
	if live and not waitingKickoff then
		chasers[1] = chaserOf(match, 1, now)
		chasers[2] = chaserOf(match, 2, now)
	end

	for _, actor in match.Actors do
		if not isBot(actor) or not actor.Root.Parent then
			continue
		end
		local m = memoryOf(actor)
		local humanoid = actor.Humanoid
		local speed = flat(actor.Root.AssemblyLinearVelocity).Magnitude
		updateAnimation(actor, m, speed)

		-- Segada o croqueta en curso: se mueve en la direccion impuesta (a los humanos lo hace su cliente)
		if live and os.clock() < actor.ForcedMoveUntil then
			humanoid:Move(actor.ForcedMoveDir)
			continue
		end
		if not live or now < actor.StunnedUntil then
			humanoid:Move(Vector3.zero)
			actor.SprintWanted = false
			continue
		end
		local myPos = localPos(match, actor)

		if match.Ball.Controller == actor then
			if not m.HadBall then
				m.HadBall = true
				m.NextDecisionAt = now + 0.35 -- recien controlado: un momento antes de decidir (sin pases "de primeras")
			end
			onBall(match, actor, m, now, myPos)
		elseif now >= m.NextThinkAt then
			m.HadBall = false
			m.NextThinkAt = now + 0.15 + rng:NextNumber() * Balance.Bots.Reaction
			if waitingKickoff then
				m.Chasing = false
				m.Target = myPos -- esperan quietos al pase de saque
			else
				think(match, actor, m, now, myPos, chasers[actor.Team])
			end
		end

		-- Presion: entrada (o segada) cuando tiene a tiro al rival con balon
		local controller: Types.Actor? = match.Ball.Controller
		if m.Chasing and controller and controller.Team ~= actor.Team and now >= m.NextTackleAt then
			local rivalPos = localPos(match, controller)
			local distance = (rivalPos - myPos).Magnitude
			if distance <= Balance.Control.TackleRange - 0.5 then
				m.NextTackleAt = now + Balance.Bots.TackleInterval
				faceTowards(match, actor, rivalPos)
				if rng:NextNumber() < Balance.Bots.SlideChance then
					match:performAction(actor, "Slide", nil)
				elseif rng:NextNumber() < Balance.Bots.TackleChance then
					match:performAction(actor, "Tackle", nil)
				end
			end
		end

		-- Moverse hacia el objetivo
		local toTarget = m.Target - myPos
		local distance = toTarget.Magnitude
		if distance <= Balance.Bots.ArriveDistance and not m.Chasing then
			humanoid:Move(Vector3.zero)
			actor.SprintWanted = false
			-- Parado: mira hacia el balon
			faceTowards(match, actor, flat(match.Ball:getLocalPosition()))
		else
			local worldDir = match.Origin:VectorToWorldSpace(toTarget.Unit)
			humanoid:Move(worldDir)
			if match.Ball.Controller ~= actor then
				actor.SprintWanted = distance > Balance.Bots.SprintDistance or m.Chasing
			end
		end
	end
end

return BotBrain
