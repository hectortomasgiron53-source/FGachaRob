--!strict
--[[
	BotBrain: jugadores de campo controlados por la maquina (nivel 2).

	Cada equipo hace un "plan" varias veces por segundo y reparte papeles:
	  CON BALON (ataque)
	    - Conductor: conduce esquivando rivales; tira si tiene angulo y la linea de tiro libre (apunta al palo
	      contrario al portero, o vaselina si el portero esta adelantado); pasa si le presionan o si un companero
	      esta claramente mejor colocado. Pases medidos y al hueco (adelantados a donde va el companero).
	    - Apoyos: buscan el mejor hueco cercano: lejos de rivales, con la linea de pase libre desde el balon,
	      separados entre si y a una distancia de pase comoda. El delantero busca huecos mas adelantados.
	  SIN BALON (defensa)
	    - Presion: el que antes llega al balon (calcula donde lo puede interceptar). Si un rival lo lleva, se
	      pone entre el y la porteria, frena al acercarse y entra cuando lo tiene a tiro.
	    - Cobertura: entre el balon y la porteria, unos metros por detras del que presiona.
	    - Marcaje: se pega (por el lado de su porteria) al rival libre mas peligroso.
	Movimiento natural: los giros son progresivos, aceleran y frenan al llegar, trotan cuando no hay prisa
	y se perfilan antes de pasar o tirar. Usan las mismas acciones y reglas que un humano (Match.performAction).
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

type Pending = { Action: string, Value: any, Aim: Vector3, At: number, Mate: Types.Actor? }

type Memory = {
	Role: string, -- "Carrier", "Press", "Cover", "Mark", "Support", "Wait"
	Target: Vector3, -- objetivo en coordenadas del campo
	Urgent: boolean, -- correr a tope (si no, trota)
	MoveDir: Vector3, -- direccion actual de la carrera (mundo, plana): gira poco a poco
	NextDecisionAt: number,
	NextTackleAt: number,
	NextJukeAt: number,
	HadBall: boolean,
	Pending: Pending?,
	Run: AnimationTrack?,
	Idle: AnimationTrack?,
	AnimFailed: boolean,
}

type Plan = { NextAt: number }

local memories: { [Types.Actor]: Memory } = setmetatable({}, { __mode = "k" }) :: any
local plans: { [any]: Plan } = setmetatable({}, { __mode = "k" }) :: any

local function memoryOf(actor: Types.Actor): Memory
	local m = memories[actor]
	if not m then
		local created: Memory = {
			Role = "Wait",
			Target = Vector3.zero,
			Urgent = false,
			MoveDir = Vector3.zero,
			NextDecisionAt = 0,
			NextTackleAt = 0,
			NextJukeAt = 0,
			HadBall = false,
			Pending = nil,
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

local function localVel(match: any, actor: Types.Actor): Vector3
	return flat(match.Origin:VectorToObjectSpace(actor.Root.AssemblyLinearVelocity))
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function alive(actor: Types.Actor): boolean
	return actor.Root.Parent ~= nil
end

-- Distancia del rival mas cercano a la linea a-b (cuanto de "libre" esta un pase o un tiro)
local function laneClearance(match: any, team: number, a: Vector3, b: Vector3): number
	local best = math.huge
	for _, rival in match.Actors do
		if rival.Team ~= team and alive(rival) then
			best = math.min(best, distanceToSegment(localPos(match, rival), a, b))
		end
	end
	return best
end

local function nearestRival(match: any, team: number, p: Vector3): (number, Vector3?)
	local best = math.huge
	local where: Vector3? = nil
	for _, rival in match.Actors do
		if rival.Team ~= team and alive(rival) then
			local rp = localPos(match, rival)
			local d = (rp - p).Magnitude
			if d < best then
				best = d
				where = rp
			end
		end
	end
	return best, where
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
			idle:Stop(0.25)
			run:Play(0.25)
		end
		run:AdjustSpeed(math.clamp(speed / 16, 0.5, 1.7))
	elseif not idle.IsPlaying then
		run:Stop(0.3)
		idle:Play(0.3)
	end
end

-- ---------------------------------------------------------------------------
-- Giro suave del cuerpo (en vez de girar de golpe)
-- ---------------------------------------------------------------------------

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

-- Gira el cuerpo hacia "worldDir" como mucho "rate" radianes por segundo. Devuelve el angulo que falta.
local function turnTowards(actor: Types.Actor, worldDir: Vector3, rate: number, dt: number): number
	local root = actor.Root
	local look = flat(root.CFrame.LookVector)
	local want = flat(worldDir)
	if want.Magnitude < 0.01 or look.Magnitude < 0.01 then
		return 0
	end
	local current = yawOf(look)
	local target = yawOf(want)
	local diff = (target - current + math.pi) % (2 * math.pi) - math.pi
	local step = math.clamp(diff, -rate * dt, rate * dt)
	local pos = root.Position
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, current + step, 0)
	return math.abs(diff - step)
end

-- ---------------------------------------------------------------------------
-- Prediccion del balon e intercepcion
-- ---------------------------------------------------------------------------

-- Posicion del balon dentro de t segundos (rodando, con el frenado del cesped)
local function ballAt(ballPos: Vector3, ballVel: Vector3, t: number): Vector3
	local k = Balance.Ball.RollDamping
	local travel = if k > 0 then (1 - math.exp(-k * t)) / k else t
	return clampToField(ballPos + ballVel * travel, 1)
end

-- Tiempo que tarda un actor en llegar al balon y donde lo coge
local function interceptOf(match: any, actor: Types.Actor, ballPos: Vector3, ballVel: Vector3): (number, Vector3)
	local myPos = localPos(match, actor)
	local speed = math.max(actor.Humanoid.WalkSpeed, Balance.Speed.Min) * Balance.Speed.SprintMultiplier
	if ballVel.Magnitude < 3 then
		return (ballPos - myPos).Magnitude / speed, ballPos
	end
	local t = 0
	while t <= 2.5 do
		local p = ballAt(ballPos, ballVel, t)
		if (p - myPos).Magnitude / speed <= t then
			return t, p
		end
		t += 0.1
	end
	local p = ballAt(ballPos, ballVel, 2.5)
	return 2.5 + (p - myPos).Magnitude / speed, p
end

-- ---------------------------------------------------------------------------
-- Ataque: elegir hueco, pase y tiro
-- ---------------------------------------------------------------------------

local function supportSpot(match: any, actor: Types.Actor, m: Memory, carrierPos: Vector3, attack: number): Vector3
	local B = Balance.Bots
	local formation = Balance.Formation[actor.Slot] or { X = 0, Z = 0 }
	local side = -attack
	local baseZ = if actor.Team == 1 then formation.Z else -formation.Z
	local forward = actor.Slot == 1
	-- Base: por delante (delantero) o a un lado/detras del balon (los otros)
	local baseX = carrierPos.X + attack * (if forward then 18 else -2) + side * formation.X * 0.15
	local base = clampToField(Vector3.new(baseX, 0, baseZ * 0.8 + carrierPos.Z * 0.2), 6)
	local myPos = localPos(match, actor)

	local best = base
	local bestScore = -math.huge
	for ring = 0, 2 do
		local radius = ring * 8
		local count = if ring == 0 then 1 else 8
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local spot = clampToField(base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), 5)
			local open = nearestRival(match, actor.Team, spot)
			local lane = laneClearance(match, actor.Team, carrierPos, spot)
			local toCarrier = (spot - carrierPos).Magnitude
			local score = math.min(open, 15) * 1.2
				+ math.min(lane, 8) * 1.5
				+ (spot.X - carrierPos.X) * attack * (if forward then 0.6 else 0.25)
				- math.abs(toCarrier - B.SupportDistance) * 0.4
				- (spot - base).Magnitude * 0.2
				- (spot - myPos).Magnitude * 0.1
			if lane < 3 then
				score -= 20
			end
			for _, mate in match.Actors do
				if mate ~= actor and mate.Team == actor.Team and not mate.IsGoalkeeper and alive(mate) then
					local mateSpot = if isBot(mate) then memoryOf(mate).Target else localPos(match, mate)
					local d = (mateSpot - spot).Magnitude
					if d < B.MinSpacing then
						score -= (B.MinSpacing - d) * 2.5
					end
				end
			end
			if (spot - m.Target).Magnitude < 3 then
				score += 4 -- no cambiar de idea por poco
			end
			if score > bestScore then
				bestScore = score
				best = spot
			end
		end
	end
	return best
end

-- Mejor companero para pasar. "requireBetter": solo si esta claramente mas adelantado y libre.
local function bestPass(match: any, actor: Types.Actor, myPos: Vector3, attack: number, requireBetter: boolean): (Types.Actor?, Vector3)
	local B = Balance.Bots
	local best: Types.Actor? = nil
	local bestAim = Vector3.zero
	local bestScore = -math.huge
	for _, mate in match.Actors do
		if mate == actor or mate.Team ~= actor.Team or not alive(mate) then
			continue
		end
		local matePos = localPos(match, mate)
		local distance = (matePos - myPos).Magnitude
		if distance < 7 or distance > B.MaxPassDistance then
			continue
		end
		-- Pase al hueco: adelantado a donde va el companero
		local aim = clampToField(matePos + localVel(match, mate) * math.clamp(distance / 45, 0.15, 0.8), 3)
		local lane = laneClearance(match, actor.Team, myPos, aim)
		if lane < B.PassLaneClearance then
			continue
		end
		local open = nearestRival(match, actor.Team, aim)
		local advance = (aim.X - myPos.X) * attack
		if requireBetter and (advance < 12 or open < 9) then
			continue
		end
		local score = advance * 0.5 + math.min(open, 15) * 1.5 + math.min(lane, 8) - distance * 0.12
		if mate.IsGoalkeeper then
			score -= 30 -- al portero solo si no hay otra cosa
		end
		if score > bestScore then
			bestScore = score
			best = mate
			bestAim = aim
		end
	end
	return best, bestAim
end

-- Donde y como tirar (o nil si no conviene)
local function shotChoice(match: any, actor: Types.Actor, myPos: Vector3, attack: number): (string?, Vector3, number)
	local B = Balance.Bots
	local F = Balance.Field
	local goalX = attack * F.Length / 2
	local distance = (Vector3.new(goalX, 0, 0) - myPos).Magnitude
	if distance > B.ShootRange or (goalX - myPos.X) * attack < 4 then
		return nil, Vector3.zero, 0
	end
	-- Angulo entre los palos
	local postA = Vector3.new(goalX, 0, F.GoalWidth / 2) - myPos
	local postB = Vector3.new(goalX, 0, -F.GoalWidth / 2) - myPos
	local angle = math.deg(math.acos(math.clamp(postA.Unit:Dot(postB.Unit), -1, 1)))
	if angle < B.ShootMinAngle and distance > 15 then
		return nil, Vector3.zero, 0
	end
	-- Portero rival: al palo contrario; si esta muy adelantado, vaselina
	local keeperZ, keeperOut = 0, 0
	for _, rival in match.Actors do
		if rival.Team ~= actor.Team and rival.IsGoalkeeper and alive(rival) then
			local kp = localPos(match, rival)
			keeperZ = kp.Z
			keeperOut = math.abs(goalX - kp.X)
		end
	end
	local aimZ = (if keeperZ > 0 then -1 else 1) * F.GoalWidth * (0.28 + rng:NextNumber() * 0.12)
	local aim = Vector3.new(goalX, 0, aimZ)
	-- Rivales de campo tapando el tiro (el portero no cuenta, para eso esta el angulo)
	local blocked = false
	for _, rival in match.Actors do
		if rival.Team ~= actor.Team and not rival.IsGoalkeeper and alive(rival) then
			if distanceToSegment(localPos(match, rival), myPos, aim) < 2.5 then
				blocked = true
			end
		end
	end
	if blocked and distance > 12 then
		return nil, Vector3.zero, 0
	end
	if keeperOut > 10 and distance > 16 and rng:NextNumber() < 0.6 then
		return "ShootHigh", Vector3.new(goalX, 0, aimZ * 0.5), math.clamp(0.15 + distance / 120, 0.15, 0.45)
	end
	local charge = math.clamp(0.45 + distance / B.ShootRange * 0.5 + rng:NextNumber() * 0.1, 0, 1)
	return "Shoot", aim, charge
end

-- ---------------------------------------------------------------------------
-- Plan del equipo: reparto de papeles
-- ---------------------------------------------------------------------------

local function planTeam(match: any, team: number, now: number)
	local B = Balance.Bots
	local ball = match.Ball
	local ballPos = flat(ball:getLocalPosition())
	local ballVel = flat(match.Origin:VectorToObjectSpace(ball.Part.AssemblyLinearVelocity))
	local controller: Types.Actor? = ball.Controller
	local side = ownSide(team)
	local attack = -side
	local ownGoal = Vector3.new(side * Balance.Field.Length / 2, 0, 0)

	-- Jugadores de campo del equipo (humanos incluidos: tambien cuentan para repartir)
	local field: { Types.Actor } = {}
	for _, actor in match.Actors do
		if actor.Team == team and actor.Controllable and not actor.IsGoalkeeper and alive(actor) then
			table.insert(field, actor)
		end
	end
	if #field == 0 then
		return
	end

	-- Tras el saque, los rivales del que saca siguen fuera del circulo central un momento
	local keepOut = match.Kickoff ~= nil and team ~= match.KickoffTeam
	local keepRadius = Balance.Field.CenterCircleRadius + Balance.Kickoff.KeepOutMargin + 1.5

	local assigned: { [Types.Actor]: boolean } = {}
	local function give(actor: Types.Actor, role: string, target: Vector3, urgent: boolean)
		assigned[actor] = true
		if isBot(actor) then
			local m = memoryOf(actor)
			local t = clampToField(target, 2)
			if keepOut and t.Magnitude < keepRadius then
				t = (if t.Magnitude > 0.1 then t.Unit else Vector3.new(side, 0, 0)) * keepRadius
			end
			m.Role = role
			m.Target = t
			m.Urgent = urgent
		end
	end

	-- Saque de centro: todos quietos hasta el pase; los rivales fuera del circulo
	local kickoff = match.Kickoff
	if kickoff and not kickoff.Passed then
		for _, actor in field do
			give(actor, "Wait", localPos(match, actor), false)
		end
		return
	end

	local protectedBy: Types.Actor? = if ball.ProtectedBy and now < ball.ProtectedUntil then ball.ProtectedBy else nil

	if controller and controller.Team == team then
		-- ATAQUE
		local carrierPos = localPos(match, controller)
		give(controller, "Carrier", carrierPos, false)
		for _, actor in field do
			if not assigned[actor] then
				give(actor, "Support", supportSpot(match, actor, memoryOf(actor), carrierPos, attack), false)
			end
		end
		return
	end

	-- SIN BALON: quien llega antes al balon presiona / intercepta
	local presser: Types.Actor? = nil
	local pressPoint = ballPos
	if protectedBy then
		if protectedBy.Team == team then
			presser = protectedBy
		end
	else
		local bestTime = math.huge
		for _, actor in field do
			local t, p = interceptOf(match, actor, ballPos, ballVel)
			if now < actor.StunnedUntil then
				t += 1
			end
			if t < bestTime then
				bestTime = t
				presser = actor
				pressPoint = p
			end
		end
	end
	if presser then
		local target = pressPoint
		if controller then
			-- Rival con balon: entre el y nuestra porteria, pegado
			local rivalPos = localPos(match, controller)
			local toGoal = ownGoal - rivalPos
			target = rivalPos + (if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.zero) * 1.8
		end
		give(presser, "Press", target, true)
	end

	-- Rivales peligrosos (sin el que lleva el balon), de mas a menos cerca de nuestra porteria
	local threats: { Types.Actor } = {}
	for _, rival in match.Actors do
		if rival.Team ~= team and not rival.IsGoalkeeper and alive(rival) and rival ~= controller then
			table.insert(threats, rival)
		end
	end
	table.sort(threats, function(a, b)
		return (localPos(match, a) - ownGoal).Magnitude < (localPos(match, b) - ownGoal).Magnitude
	end)

	local rivalHasBall = controller ~= nil and controller.Team ~= team
	local rest: { Types.Actor } = {}
	for _, actor in field do
		if not assigned[actor] then
			table.insert(rest, actor)
		end
	end

	-- Puestos: cobertura (entre balon y porteria) y marcaje del rival mas peligroso
	local jobs: { { Role: string, Target: Vector3, Urgent: boolean } } = {}
	local toGoal = ownGoal - ballPos
	local coverDir = if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.new(side, 0, 0)
	table.insert(jobs, { Role = "Cover", Target = ballPos + coverDir * B.CoverDistance, Urgent = rivalHasBall })
	for _, rival in threats do
		local rp = localPos(match, rival)
		local g = ownGoal - rp
		local mark = rp + (if g.Magnitude > 0.1 then g.Unit else Vector3.zero) * B.MarkDistance
		table.insert(jobs, { Role = "Mark", Target = mark, Urgent = rivalHasBall })
	end
	-- Si el balon esta suelto y lo vamos a coger nosotros, los demas ya se abren para atacar
	local weGetIt = presser ~= nil and not controller
	for _, actor in rest do
		local bestIndex, bestDistance = 0, math.huge
		for index, job in jobs do
			local d = (job.Target - localPos(match, actor)).Magnitude
			if d < bestDistance then
				bestIndex, bestDistance = index, d
			end
		end
		if weGetIt and actor.Slot == 1 then
			-- El delantero se adelanta para recibir
			give(actor, "Support", supportSpot(match, actor, memoryOf(actor), ballPos, attack), false)
		elseif bestIndex > 0 then
			local job = jobs[bestIndex]
			table.remove(jobs, bestIndex)
			give(actor, job.Role, job.Target, job.Urgent)
		else
			give(actor, "Cover", ballPos + coverDir * (B.CoverDistance + 8), false)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Con balon
-- ---------------------------------------------------------------------------

-- Prepara una accion: el bot se perfila (gira) un instante y luego golpea.
local function prepare(m: Memory, action: string, value: any, aim: Vector3, now: number, mate: Types.Actor?)
	m.Pending = { Action = action, Value = value, Aim = aim, At = now + Balance.Bots.AimTime, Mate = mate }
end

local function carrierThink(match: any, actor: Types.Actor, m: Memory, now: number, myPos: Vector3)
	local B = Balance.Bots
	local attack = -ownSide(actor.Team)
	local pressure, rivalPos = nearestRival(match, actor.Team, myPos)

	if m.Pending == nil and now >= m.NextDecisionAt then
		m.NextDecisionAt = now + B.DecisionInterval * (0.8 + rng:NextNumber() * 0.4)
		local shot, aim, charge = shotChoice(match, actor, myPos, attack)
		if shot then
			prepare(m, shot, charge, aim, now, nil)
		elseif pressure < B.PressureRange and rng:NextNumber() < B.PassChance then
			local mate, passAim = bestPass(match, actor, myPos, attack, false)
			if mate then
				prepare(m, "Pass", (passAim - myPos).Magnitude, passAim, now, mate)
			elseif now >= m.NextJukeAt and rng:NextNumber() < B.JukeChance then
				m.NextJukeAt = now + 1.5
				local side = if rivalPos and ((rivalPos :: Vector3).Z - myPos.Z) > 0 then -1 else 1
				match:performAction(actor, "Juke", side)
			end
		elseif rng:NextNumber() < B.ForwardPassChance then
			local mate, passAim = bestPass(match, actor, myPos, attack, true)
			if mate then
				prepare(m, "Pass", (passAim - myPos).Magnitude, passAim, now, mate)
			end
		end
	end

	-- Conduccion: hacia la porteria, esquivando a los rivales de delante y lejos de las bandas
	local goal = Vector3.new(attack * Balance.Field.Length / 2, 0, 0)
	local toGoal = goal - myPos
	local dir = if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.new(attack, 0, 0)
	local avoid = Vector3.zero
	for _, rival in match.Actors do
		if rival.Team ~= actor.Team and not rival.IsGoalkeeper and alive(rival) then
			local away = myPos - localPos(match, rival)
			local d = away.Magnitude
			if d < 12 and d > 0.1 and (-away.Unit):Dot(dir) > -0.2 then
				avoid += away.Unit * ((12 - d) / 12) * 1.6
			end
		end
	end
	local halfWidth = Balance.Field.Width / 2
	if math.abs(myPos.Z) > halfWidth - 10 then
		avoid += Vector3.new(0, 0, -math.sign(myPos.Z)) * 0.8
	end
	local steer = dir + avoid
	if steer.Magnitude < 0.1 then
		steer = dir
	end
	m.Target = clampToField(myPos + steer.Unit * 12, 4)
	m.Urgent = pressure > 10
	m.Role = "Carrier"
end

-- ---------------------------------------------------------------------------
-- Bucle (lo llama Match.update cada Heartbeat)
-- ---------------------------------------------------------------------------

function BotBrain.update(match: any, dt: number, now: number)
	local B = Balance.Bots
	local live = match:_isLive()

	-- Plan de los equipos (varias veces por segundo, con un pequeno retraso de reaccion)
	local plan = plans[match]
	if not plan then
		plan = { NextAt = 0 }
		plans[match] = plan
	end
	if live and now >= (plan :: Plan).NextAt then
		(plan :: Plan).NextAt = now + B.PlanInterval
		planTeam(match, 1, now)
		planTeam(match, 2, now)
	end

	for _, actor in match.Actors do
		if not isBot(actor) or not alive(actor) then
			continue
		end
		local m = memoryOf(actor)
		local humanoid = actor.Humanoid
		local root = actor.Root
		local speed = flat(root.AssemblyLinearVelocity).Magnitude
		updateAnimation(actor, m, speed)

		-- Segada o croqueta en curso: direccion impuesta (a los humanos se la aplica su cliente)
		if live and os.clock() < actor.ForcedMoveUntil then
			humanoid:Move(actor.ForcedMoveDir)
			m.MoveDir = actor.ForcedMoveDir
			continue
		end
		if not live or now < actor.StunnedUntil then
			humanoid:Move(Vector3.zero)
			m.MoveDir = Vector3.zero
			m.Pending = nil
			actor.SprintWanted = false
			continue
		end

		local myPos = localPos(match, actor)
		local hasBall = match.Ball.Controller == actor
		if hasBall then
			if not m.HadBall then
				m.HadBall = true
				m.NextDecisionAt = now + B.FirstTouchDelay -- recien controlado: un momento antes de decidir
			end
			carrierThink(match, actor, m, now, myPos)
		else
			m.HadBall = false
			if m.Pending and m.Pending.Action ~= "Tackle" then
				m.Pending = nil -- perdio el balon antes de golpear
			end
		end

		-- Accion preparada: perfilarse y golpear
		local pending = m.Pending
		if pending then
			local aim = pending.Aim
			if pending.Mate and alive(pending.Mate :: Types.Actor) then
				-- Recalcula el pase al hueco con la posicion actual del companero
				local mate = pending.Mate :: Types.Actor
				local mp = localPos(match, mate)
				local d = (mp - myPos).Magnitude
				aim = clampToField(mp + localVel(match, mate) * math.clamp(d / 45, 0.15, 0.8), 3)
				pending.Value = (aim - myPos).Magnitude
			end
			local toAim = aim - myPos
			if toAim.Magnitude < 0.5 then
				toAim = flat(match.Origin:VectorToObjectSpace(root.CFrame.LookVector))
			end
			local worldDir = match.Origin:VectorToWorldSpace(toAim.Unit)
			local left = turnTowards(actor, worldDir, B.AimTurnRate, dt)
			humanoid:Move(worldDir * 0.4)
			if now >= pending.At or left < math.rad(6) then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat(worldDir))
				m.Pending = nil
				m.NextDecisionAt = now + B.DecisionInterval
				match:performAction(actor, pending.Action, pending.Value)
			end
			continue
		end

		-- Presion: entrada cuando tiene a tiro al rival con balon
		local controller: Types.Actor? = match.Ball.Controller
		if m.Role == "Press" and controller and controller.Team ~= actor.Team and now >= m.NextTackleAt then
			local rivalPos = localPos(match, controller)
			local ballPos = flat(match.Ball:getLocalPosition())
			local reach = math.min((rivalPos - myPos).Magnitude, (ballPos - myPos).Magnitude)
			if reach <= Balance.Control.TackleRange - 0.8 then
				m.NextTackleAt = now + B.TackleInterval * (0.8 + rng:NextNumber() * 0.5)
				if rng:NextNumber() < B.TackleChance then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + match.Origin:VectorToWorldSpace(ballPos - myPos))
					match:performAction(actor, if rng:NextNumber() < B.SlideChance then "Slide" else "Tackle", nil)
				end
			end
			-- Persecucion directa al balon cuando esta cerca (en vez de al punto del plan)
			if reach < 8 then
				m.Target = ballPos
			end
		elseif m.Role == "Press" and not controller then
			m.Target = flat(match.Ball:getLocalPosition()) + flat(match.Origin:VectorToObjectSpace(match.Ball.Part.AssemblyLinearVelocity)) * 0.15
		end

		-- Movimiento suave: la direccion gira poco a poco y frena al llegar
		local toTarget = m.Target - myPos
		local distance = toTarget.Magnitude
		local arrive = B.ArriveDistance
		if distance <= arrive and m.Role ~= "Press" and not hasBall then
			humanoid:Move(Vector3.zero)
			m.MoveDir = Vector3.zero
			actor.SprintWanted = false
			-- Parado: se gira despacio hacia el balon
			local ballWorld = match.Ball.Part.Position - root.Position
			local look = flat(root.CFrame.LookVector)
			local want = flat(ballWorld)
			if want.Magnitude > 0.5 and look.Magnitude > 0.01 and look.Unit:Dot(want.Unit) < 0.94 then
				turnTowards(actor, want, B.IdleTurnRate, dt)
			end
			continue
		end
		local wantDir = match.Origin:VectorToWorldSpace(toTarget.Unit)
		local current = m.MoveDir
		if current.Magnitude < 0.01 then
			current = flat(root.CFrame.LookVector)
			if current.Magnitude < 0.01 then
				current = wantDir
			end
			current = current.Unit
		end
		local turnRate = if hasBall then B.TurnRateWithBall else B.TurnRate
		local angle = math.acos(math.clamp(current:Dot(wantDir), -1, 1))
		local newDir: Vector3
		if angle <= turnRate * dt or angle < 1e-3 then
			newDir = wantDir
		else
			local axis = current:Cross(wantDir)
			local sign = if axis.Y >= 0 then 1 else -1
			newDir = CFrame.Angles(0, sign * turnRate * dt, 0):VectorToWorldSpace(current)
		end
		newDir = flat(newDir).Unit
		m.MoveDir = newDir
		humanoid:Move(newDir)

		-- Ritmo: a tope si hay prisa o esta lejos; trotando si no; frena al acercarse
		local urgent = m.Urgent or distance > B.SprintDistance
		local pace = if urgent then 1 else B.JogFactor
		if distance < B.SlowDownDistance and not hasBall and m.Role ~= "Press" then
			pace *= math.clamp(distance / B.SlowDownDistance, 0.35, 1)
		end
		if m.Role == "Press" and controller and controller.Team ~= actor.Team and distance < 6 then
			pace *= 0.8 -- se acerca con cuidado para no pasarse de largo
		end
		if angle > math.rad(100) then
			pace *= 0.6 -- media vuelta: frena para girar
		end
		humanoid.WalkSpeed *= pace
		actor.SprintWanted = urgent and distance > 8
	end
end

return BotBrain
