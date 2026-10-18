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
	BallSince: number, -- desde cuando lleva el balon
	SpotIndex: number, -- puesto de la formacion que ocupa (1 pivot, 2 ala, 3 cierre)
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
			BallSince = 0,
			SpotIndex = 0,
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

local function supportSpot(match: any, actor: Types.Actor, m: Memory, base: Vector3, carrierPos: Vector3, attack: number): Vector3
	local myPos = localPos(match, actor)
	local best = base
	local bestScore = -math.huge
	for ring = 0, 2 do
		local radius = ring * 4
		local count = if ring == 0 then 1 else 8
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local spot = clampToField(base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), 5)
			local open = nearestRival(match, actor.Team, spot)
			local lane = laneClearance(match, actor.Team, carrierPos, spot)
			local score = math.min(open, 12) * 1.0
				+ math.min(lane, 8) * 1.5
				+ (spot.X - carrierPos.X) * attack * 0.15
				- (spot - base).Magnitude * 0.6 -- sin alejarse mucho de su puesto
				- (spot - myPos).Magnitude * 0.05
			if lane < 3 then
				score -= 15
			end
			if (spot - m.Target).Magnitude < 2.5 then
				score += 3 -- no cambiar de idea por poco
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
		if requireBetter and (advance < 5 or open < 7) then
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
-- Plan del equipo: formacion en bloque y reparto de papeles
-- ---------------------------------------------------------------------------

-- Pase en curso de cada equipo: quien debe recibirlo va a por el (y no el que lo ha dado)
local passTo: { [any]: { [number]: { Mate: Types.Actor, Until: number } } } = setmetatable({}, { __mode = "k" }) :: any

function BotBrain.notePass(match: any, team: number, mate: Types.Actor, now: number)
	local byTeam = passTo[match]
	if not byTeam then
		byTeam = {}
		passTo[match] = byTeam
	end
	(byTeam :: any)[team] = { Mate = mate, Until = now + Balance.Bots.ReceiverSeconds }
end

-- Los tres puestos de la formacion de futbol sala (pivot, ala y cierre), que se mueven en bloque con el balon.
-- "mode": "Attack" (tenemos el balon), "Loose" (suelto) o "Defend" (lo tiene el rival).
local function shapeSpots(team: number, ballPos: Vector3, mode: string): { Vector3 }
	local S = Balance.Bots.Shape
	local side = ownSide(team)
	local attack = -side
	local bx, bz = ballPos.X, ballPos.Z
	local far = if bz > 0 then -1 else 1 -- banda contraria a la del balon
	local spots: { Vector3 }
	if mode == "Attack" then
		spots = {
			Vector3.new(bx + attack * S.PivotAhead, 0, bz * 0.35), -- pivot: arriba, para recibir
			Vector3.new(bx + attack * S.WingAhead, 0, far * S.WingWidth), -- ala: abierto en la otra banda
			Vector3.new(bx - attack * S.BackBehind, 0, bz * 0.4), -- cierre: detras, pase de seguridad
		}
	elseif mode == "Loose" then
		spots = {
			Vector3.new(bx + attack * S.PivotAhead * 0.6, 0, bz * 0.3),
			Vector3.new(bx, 0, far * S.WingWidth * 0.8),
			Vector3.new(bx - attack * S.BackBehind * 1.1, 0, bz * 0.3),
		}
	else
		-- Defensa: linea por detras del balon (hacia nuestra porteria), cerrando el centro
		local lineX = bx + side * S.DefendLine
		local backX = bx + side * S.DefendDeep
		local maxX = Balance.Field.Length / 2 - 8
		lineX = math.clamp(lineX, -maxX, maxX)
		backX = math.clamp(backX, -maxX, maxX)
		spots = {
			Vector3.new(lineX, 0, bz * 0.5 + S.DefendWidth),
			Vector3.new(lineX, 0, bz * 0.5 - S.DefendWidth),
			Vector3.new(backX, 0, bz * 0.25),
		}
	end
	for i, spot in spots do
		spots[i] = clampToField(spot, 6)
	end
	return spots
end

local function planTeam(match: any, team: number, now: number)
	local B = Balance.Bots
	local ball = match.Ball
	local ballPos = flat(ball:getLocalPosition())
	local ballVel = flat(match.Origin:VectorToObjectSpace(ball.Part.AssemblyLinearVelocity))
	local controller: Types.Actor? = ball.Controller
	local side = ownSide(team)
	local attack = -side
	local ownGoal = Vector3.new(side * Balance.Field.Length / 2, 0, 0)

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

	-- Saque de centro: todos quietos hasta el pase
	local kickoff = match.Kickoff
	if kickoff and not kickoff.Passed then
		for _, actor in field do
			give(actor, "Wait", localPos(match, actor), false)
		end
		return
	end

	-- 1) Quien va al balon (uno solo)
	local mode: string
	local chaser: Types.Actor? = nil
	local chasePoint = ballPos
	if controller and controller.Team == team then
		mode = "Attack"
		chaser = controller
		give(controller, "Carrier", localPos(match, controller), false)
	else
		mode = if controller then "Defend" else "Loose"
		local protectedBy: Types.Actor? = if ball.ProtectedBy and now < ball.ProtectedUntil then ball.ProtectedBy else nil
		local pass = passTo[match] and (passTo[match] :: any)[team]
		if protectedBy then
			if protectedBy.Team == team then
				chaser = protectedBy
			end
		elseif not controller and pass and now < pass.Until and alive(pass.Mate) and pass.Mate.Team == team then
			-- Pase nuestro en camino: va el receptor
			chaser = pass.Mate
			local _, p = interceptOf(match, pass.Mate, ballPos, ballVel)
			chasePoint = p
			mode = "Attack"
		else
			local bestTime = math.huge
			for _, actor in field do
				local t, p = interceptOf(match, actor, ballPos, ballVel)
				if now < actor.StunnedUntil then
					t += 1
				end
				if ball.LastTouch == actor and not controller and ballVel.Magnitude > 15 then
					t += 3 -- el que acaba de golpear no persigue su propio pase o tiro
				end
				if t < bestTime then
					bestTime = t
					chaser = actor
					chasePoint = p
				end
			end
		end
		if chaser then
			local target = chasePoint
			if controller then
				-- Rival con balon: entre el y nuestra porteria
				local rivalPos = localPos(match, controller)
				local toGoal = ownGoal - rivalPos
				target = rivalPos + (if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.zero) * 1.8
			end
			give(chaser, "Press", target, true)
		end
	end

	-- 2) El resto ocupa los puestos de la formacion (cada uno el suyo, sin repetir)
	local reference = if mode == "Attack" and controller then localPos(match, controller) else ballPos
	local spots = shapeSpots(team, reference, mode)
	local free: { number } = { 1, 2, 3 }
	-- Los humanos ocupan el puesto que tengan mas cerca (los bots se reparten los demas)
	for _, actor in field do
		if not assigned[actor] and not isBot(actor) then
			local bestIndex, bestDistance = 0, math.huge
			for i, index in free do
				local d = (spots[index] - localPos(match, actor)).Magnitude
				if d < bestDistance then
					bestIndex, bestDistance = i, d
				end
			end
			if bestIndex > 0 then
				table.remove(free, bestIndex)
			end
			assigned[actor] = true
		end
	end
	-- El que va al balon deja libre su puesto natural: se quita el puesto mas cercano a el si sobran puestos
	local unassigned = 0
	for _, actor in field do
		if not assigned[actor] then
			unassigned += 1
		end
	end
	if chaser and chaser.Team == team and #free > unassigned then
		local bestIndex, bestDistance = 0, math.huge
		for i, index in free do
			local d = (spots[index] - localPos(match, chaser :: Types.Actor)).Magnitude
			if d < bestDistance then
				bestIndex, bestDistance = i, d
			end
		end
		if bestIndex > 0 then
			table.remove(free, bestIndex)
		end
	end

	local threats: { Vector3 } = {}
	if mode == "Defend" then
		for _, rival in match.Actors do
			if rival.Team ~= team and not rival.IsGoalkeeper and alive(rival) and rival ~= controller then
				table.insert(threats, localPos(match, rival))
			end
		end
	end

	for _, actor in field do
		if assigned[actor] then
			continue
		end
		local m = memoryOf(actor)
		local myPos = localPos(match, actor)
		local bestI, bestCost = 0, math.huge
		for i, index in free do
			local cost = (spots[index] - myPos).Magnitude
			if index == m.SpotIndex then
				cost -= B.KeepSpotBonus -- mantener su puesto si puede
			end
			if cost < bestCost then
				bestI, bestCost = i, cost
			end
		end
		if bestI == 0 then
			give(actor, "Support", myPos, false)
			continue
		end
		local index = free[bestI]
		table.remove(free, bestI)
		m.SpotIndex = index
		local spot = spots[index]
		if mode == "Defend" then
			-- Si un rival esta cerca de su puesto, lo marca por el lado de nuestra porteria
			local role = "Cover"
			for _, rp in threats do
				if (rp - spot).Magnitude < B.MarkRadius then
					local g = ownGoal - rp
					spot = rp + (if g.Magnitude > 0.1 then g.Unit else Vector3.zero) * B.MarkDistance
					role = "Mark"
					break
				end
			end
			give(actor, role, spot, (spot - myPos).Magnitude > 10)
		else
			-- Ataque: busca el hueco libre alrededor de su puesto. Pequeno vaiven para no quedarse clavado.
			local wobble = Vector3.new(math.sin(now * 0.9 + index * 2.1), 0, math.cos(now * 0.7 + index)) * B.Wobble
			local refined = supportSpot(match, actor, m, spot + wobble, reference, attack)
			give(actor, "Support", refined, (refined - myPos).Magnitude > 14)
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
		else
			local held = now - m.BallSince
			local pressured = pressure < B.PressureRange
			local mate: Types.Actor?, passAim = nil, Vector3.zero
			if pressured and rng:NextNumber() < B.PassChance then
				mate, passAim = bestPass(match, actor, myPos, attack, false) -- le aprietan: a quien este libre
			elseif held > B.HoldSeconds and rng:NextNumber() < B.PassChance then
				mate, passAim = bestPass(match, actor, myPos, attack, false) -- lleva mucho: mover el balon
			elseif rng:NextNumber() < B.ForwardPassChance then
				mate, passAim = bestPass(match, actor, myPos, attack, true) -- companero mejor colocado
			end
			if mate then
				prepare(m, "Pass", (passAim - myPos).Magnitude, passAim, now, mate)
			elseif pressured and now >= m.NextJukeAt and rng:NextNumber() < B.JukeChance then
				m.NextJukeAt = now + 1.5
				local side = if rivalPos and ((rivalPos :: Vector3).Z - myPos.Z) > 0 then -1 else 1
				match:performAction(actor, "Juke", side)
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
				m.BallSince = now
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
				if pending.Action == "Pass" and pending.Mate and match.Ball.Controller == nil and match.Ball.LastTouch == actor then
					BotBrain.notePass(match, actor.Team, pending.Mate :: Types.Actor, now) -- el receptor va a por el
				end
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
			-- Balon lento: directo a el. Balon rapido (un pase): al punto donde lo intercepta (lo calcula el plan),
			-- en vez de correr hacia el que lo ha pasado.
			local ballVel = flat(match.Origin:VectorToObjectSpace(match.Ball.Part.AssemblyLinearVelocity))
			if ballVel.Magnitude < 12 then
				m.Target = flat(match.Ball:getLocalPosition()) + ballVel * 0.15
			end
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
