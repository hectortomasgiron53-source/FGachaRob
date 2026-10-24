--!strict
--!native
--[[
	Tactics: el "cerebro" tactico de los bots de campo. Es codigo puro (no usa nada de Roblox salvo Vector3), asi
	se puede probar fuera de Roblox con un simulador. BotBrain le pasa una "foto" del partido en coordenadas del campo
	(X = largo, Z = ancho) y Tactics decide, para cada bot, a donde ir, hacia donde mirar y que accion hacer.

	Ideas que usa:
	  - Valor de cada zona (xT): cuanto peligro hay con el balon en ese punto (cerca de la porteria y con angulo = mas).
	  - Riesgo de cada pase: para varios puntos del recorrido compara cuando llega el balon y cuando llegaria cada
	    rival (con su velocidad y tiempo de reaccion). Asi sabe si un pase es seguro, arriesgado o imposible.
	  - El que lleva el balon compara el valor esperado de tirar (xG), pasar (al pie o al hueco) y conducir
	    (en varias direcciones) y elige lo mejor, con un poco de azar para no ser predecible.
	  - Ataque sin balon: cada bot prueba muchos puntos alrededor de su puesto (pivot arriba, apoyo atras/al lado) y
	    se va al mejor: donde le pueden pasar seguro, donde hay espacio (llega antes que los rivales), donde hay
	    peligro, sin pisarse con los companeros y a una distancia de pase comoda.
	  - Defensa: el que antes llega presiona (por el lado de su porteria, sin pasarse de largo); los otros reparten
	    marcaje al atacante mas peligroso (por el lado de la porteria y un poco hacia el balon, para cortar el pase)
	    y cobertura del centro. Si el que lleva el balon puede tirar, el de cobertura se pone en la linea de tiro.
	  - Balones sueltos: calcula quien llega antes de cada equipo; si llega antes su equipo, el resto ya se abre
	    para atacar; si llega antes el rival, se colocan para defender. Tras un pase, va a por el balon el receptor.
	  - Transiciones: al perder el balon presionan enseguida; al recuperarlo se abren rapido.
]]
local Tactics = {}

-- ---------------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rand(): number
	return math.random()
end

local function noise(scale: number): number
	return (rand() + rand() + rand() - 1.5) * scale
end

local function sigmoid(x: number): number
	return 1 / (1 + math.exp(-x))
end

local function attackDir(team: number): number
	return if team == 1 then 1 else -1 -- el equipo 1 ataca hacia +X
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (p - a).Magnitude, 0
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return (p - (a + ab * t)).Magnitude, t
end

local function clampField(world: any, p: Vector3, margin: number): Vector3
	local F = world.Field
	return Vector3.new(
		math.clamp(p.X, -F.Length / 2 + margin, F.Length / 2 - margin),
		0,
		math.clamp(p.Z, -F.Width / 2 + margin, F.Width / 2 - margin)
	)
end

local function goalOf(world: any, team: number): Vector3
	-- Porteria que ATACA ese equipo
	return Vector3.new(attackDir(team) * world.Field.Length / 2, 0, 0)
end

local function ownGoalOf(world: any, team: number): Vector3
	return Vector3.new(-attackDir(team) * world.Field.Length / 2, 0, 0)
end

-- Angulo (grados) con el que se ve la porteria rival desde p
local function goalAngle(world: any, team: number, p: Vector3): number
	local g = goalOf(world, team)
	local half = world.Field.GoalWidth / 2
	if (g.X - p.X) * attackDir(team) < 0.5 then
		return 0
	end
	local a = Vector3.new(g.X, 0, half) - p
	local b = Vector3.new(g.X, 0, -half) - p
	if a.Magnitude < 0.1 or b.Magnitude < 0.1 then
		return 180
	end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- Valor de tener el balon en p para "team" (0..1): crece cerca de la porteria rival y con buen angulo
local function threat(world: any, team: number, p: Vector3): number
	local g = goalOf(world, team)
	local d = (g - p).Magnitude
	local angle = math.min(goalAngle(world, team, p) / 60, 1)
	local progress = (p.X * attackDir(team)) / world.Field.Length + 0.5 -- 0 en su porteria, 1 en la rival
	-- La caida con la distancia es proporcional al largo del campo (asi vale igual con campos de otro tamano)
	local reach = world.Field.Length * 0.16
	return 0.01 + 0.08 * progress + 0.45 * math.exp(-d / reach) * (0.35 + 0.65 * angle)
end

-- Peligro de perder el balon en p (lo que vale ese punto para el rival)
local function danger(world: any, team: number, p: Vector3): number
	return threat(world, 3 - team, p)
end

-- ---------------------------------------------------------------------------
-- Movimiento del balon y de los jugadores (modelos sencillos)
-- ---------------------------------------------------------------------------

local function damping(cfg: any): number
	return math.max(cfg.Ball.RollDamping, 0.05)
end

-- Velocidad de salida de un pase raso de "d" studs (llega con algo de fuerza para controlarlo)
function Tactics.passSpeed(cfg: any, d: number): number
	local B = cfg.Bots
	local v = d * damping(cfg) + B.PassArrive + d * B.PassArrivePerStud
	return math.clamp(v, 16, cfg.Kick.PassSpeedMax * 1.2)
end

-- Tiempo que tarda un balon (salida v0) en recorrer s studs
local function ballTime(cfg: any, v0: number, s: number): number
	local k = damping(cfg)
	local x = 1 - s * k / v0
	if x <= 0.02 then
		return math.huge
	end
	return -math.log(x) / k
end

local function sprintSpeed(cfg: any, p: any): number
	return p.RunSpeed * cfg.Speed.SprintMultiplier
end

-- Tiempo que tarda un jugador en llegar a un punto (con reaccion y alcance de pierna)
local function reachTime(cfg: any, p: any, point: Vector3, reaction: number): number
	local d = math.max(0, (point - p.Pos).Magnitude - 1.8)
	local t = reaction + d / sprintSpeed(cfg, p)
	if p.Stunned then
		t += 0.5
	end
	return t
end

-- Muestras del recorrido de un pase (tablas reutilizadas: passSafety se llama cientos de veces por segundo y crear
-- tablas nuevas en cada llamada cargaba mucho al recolector de basura)
local SAMPLES = 11
local sampleX: { number } = table.create(SAMPLES, 0)
local sampleZ: { number } = table.create(SAMPLES, 0)
local sampleTime: { number } = table.create(SAMPLES, 0)
local sampleSlow: { boolean } = table.create(SAMPLES, false)
local sampleFast: { boolean } = table.create(SAMPLES, false)
local sampleRecv: { number } = table.create(SAMPLES, 0)

-- Probabilidad de que un pase de "from" (donde esta el balon) a "to" no lo corte nadie del equipo contrario.
-- Igual que en el juego, el balon se lo queda quien primero lo tiene a su alcance: si el receptor ("receiverPos",
-- donde estara) llega antes, o esta mas cerca cuando el balon llega a los dos, es suyo. Asi un companero con el
-- marcador a la espalda SI es un pase seguro (el balon le llega a el primero).
-- (Todo en el plano: X y Z. Los puntos que recibe ya son planos.)
local function passSafety(world: any, cfg: any, team: number, from: Vector3, to: Vector3, receiverPos: Vector3?): (number, number)
	local fx, fz = from.X, from.Z
	local dx, dz = to.X - fx, to.Z - fz
	local d = math.sqrt(dx * dx + dz * dz)
	local v0 = Tactics.passSpeed(cfg, d)
	local k = damping(cfg)
	local safe = 1
	local C = cfg.Control
	local reaction = cfg.Bots.Reaction
	local range = C.DribbleRange * 0.9
	local maxCatch = C.MaxCatchSpeed
	local fastSpeed = C.FastBallSpeed
	local recv = receiverPos or to
	local rx, rz = recv.X, recv.Z
	local ux, uz = 0, 0
	if d > 0.01 then
		ux, uz = dx / d, dz / d
	end
	-- Muestras del recorrido y el primer punto en que el receptor ya lo tiene a su alcance
	local pickup = SAMPLES
	for i = 1, SAMPLES do
		local f = 0.02 + (i - 1) * 0.098
		local s = d * f
		local qx, qz = fx + dx * f, fz + dz * f
		local speedThere = v0 - s * k
		local ex, ez = qx - rx, qz - rz
		local recvDist = math.sqrt(ex * ex + ez * ez)
		local slow = speedThere <= maxCatch
		sampleX[i], sampleZ[i] = qx, qz
		sampleTime[i] = ballTime(cfg, v0, s)
		sampleSlow[i] = slow
		sampleFast[i] = speedThere > fastSpeed
		sampleRecv[i] = recvDist
		if slow and recvDist <= range and pickup == SAMPLES and i < SAMPLES then
			pickup = i
			break
		end
	end
	local closeRange = C.FastBallCloseRange
	local areaRadius = world.Field.AreaRadius
	local center, scale = cfg.Bots.SafetyCenter, cfg.Bots.SafetyScale
	for _, opp in world.Players do
		if opp.Team == team then
			continue
		end
		local ox, oz = opp.Pos.X, opp.Pos.Z
		local keeper = opp.Keeper
		local goalX = -attackDir(opp.Team) * world.Field.Length / 2 -- su propia porteria (Z = 0)
		local run = sprintSpeed(cfg, opp)
		local stunned = opp.Stunned
		local worst = math.huge
		for i = 1, pickup do
			if not sampleSlow[i] then
				continue -- demasiado rapido para controlarlo
			end
			local qx, qz = sampleX[i], sampleZ[i]
			if keeper then
				local gx, gz = qx - goalX, qz
				if gx * gx + gz * gz > areaRadius * areaRadius then
					continue -- el portero solo corta dentro de su area
				end
			end
			local px, pz = ox - qx, oz - qz
			local dist = math.sqrt(px * px + pz * pz)
			if i == pickup and dist >= sampleRecv[i] then
				continue -- cuando llega el balon, el receptor esta mas cerca: es suyo
			end
			if sampleFast[i] and px * ux + pz * uz < -1 and dist > closeRange then
				continue -- ese rival queda por detras del balon: un balon rapido que se le aleja no lo puede controlar
			end
			-- Tiempo que tarda en poder CONTROLARLO: en el juego, cualquiera que tenga el balon a menos de DribbleRange
			-- (y lento) se lo queda al instante, asi que basta con acercarse a esa distancia
			local cut: number
			if dist <= range then
				cut = if stunned then 0.4 else 0
			else
				cut = reaction + (dist - range) / run + (if stunned then 0.5 else 0)
			end
			local margin = cut - sampleTime[i]
			if margin < worst then
				worst = margin
			end
		end
		if worst < math.huge then
			safe *= sigmoid((worst - center) / scale)
		end
	end
	return safe, ballTime(cfg, v0, d)
end

-- Cuanto tarda el rival mas rapido en llegar a un punto
local function rivalTime(world: any, cfg: any, team: number, point: Vector3, reaction: number): number
	local best = math.huge
	for _, opp in world.Players do
		if opp.Team ~= team and not opp.Keeper then
			best = math.min(best, reachTime(cfg, opp, point, reaction))
		end
	end
	return best
end

-- Probabilidad de gol de un tiro desde p (y a donde apuntar)
local function shotValue(world: any, cfg: any, team: number, p: Vector3): (number, Vector3, boolean)
	local g = goalOf(world, team)
	local d = (g - p).Magnitude
	if d > cfg.Bots.ShootRange then
		return 0, g, false
	end
	local angle = goalAngle(world, team, p)
	local xg = 0.85 * math.exp(-d / 15) * math.min(1, angle / 45)
	local half = world.Field.GoalWidth / 2
	-- Portero: al palo con mas hueco
	local keeper: any = nil
	for _, opp in world.Players do
		if opp.Team ~= team and opp.Keeper then
			keeper = opp
		end
	end
	local aimZ = (if rand() < 0.5 then 1 else -1) * half * 0.62
	local chip = false
	if keeper then
		local kz = keeper.Pos.Z
		aimZ = (if (half - kz) > (kz + half) then 1 else -1) * half * (0.55 + rand() * 0.15)
		local offLine, along = distanceToSegment(keeper.Pos, p, Vector3.new(g.X, 0, aimZ))
		if offLine < 2 and along > 0.2 then
			xg *= 0.7 -- el portero tapa ese palo
		end
		local out = math.abs(g.X - keeper.Pos.X)
		if out > 9 and d > 14 then
			xg *= 1.3
			chip = true -- portero adelantado: vaselina
		end
	end
	local aim = Vector3.new(g.X, 0, aimZ)
	for _, opp in world.Players do
		if opp.Team ~= team and not opp.Keeper then
			local off, along = distanceToSegment(opp.Pos, p, aim)
			if off < 2.2 and along > 0.05 then
				xg *= cfg.Bots.BlockedShotFactor -- un rival tapa el tiro (aun asi puede colarse o rebotar)
			end
		end
	end
	return math.min(xg, 0.9), aim, chip
end

-- ---------------------------------------------------------------------------
-- Posiciones (delantero, medio, defensa) y su zona de actividad
-- ---------------------------------------------------------------------------

-- Posicion de un jugador segun su slot: "Delantero", "Medio" o "Defensa"
local function positionOf(cfg: any, p: any): string
	return cfg.Bots.Positions[p.Slot] or "Medio"
end

-- Zona de actividad (profundidad: -L/2 = su porteria, +L/2 = la rival)
local function zoneOf(world: any, cfg: any, p: any): (number, number)
	local zone = cfg.Bots.Zones[positionOf(cfg, p)] or { Min = -1, Max = 1 }
	local half = world.Field.Length / 2
	return zone.Min * half, zone.Max * half
end

-- Cuanto se sale de su zona un punto (0 = dentro)
local function outsideZone(world: any, cfg: any, p: any, point: Vector3): number
	local zMin, zMax = zoneOf(world, cfg, p)
	local depth = point.X * attackDir(p.Team)
	return math.max(0, zMin - depth, depth - zMax)
end

-- ---------------------------------------------------------------------------
-- Estado (memoria de cada bot y de cada equipo)
-- ---------------------------------------------------------------------------

function Tactics.newState(): any
	return {
		Mem = {},
		Teams = {
			[1] = { NextPlanAt = 0, Pass = nil, LostAt = -100, HadBall = false, Stall = 0 },
			[2] = { NextPlanAt = 0.1, Pass = nil, LostAt = -100, HadBall = false, Stall = 0 },
		},
	}
end

local function memOf(state: any, p: any): any
	local m = state.Mem[p.Id]
	if not m then
		m = {
			Role = "Wait",
			Target = p.Pos,
			Urgent = false,
			Face = nil,
			NextDecisionAt = 0,
			NextTackleAt = 0,
			NextJukeAt = 0,
			BallSince = 0,
			HadBall = false,
			Pending = nil,
			MoveDir = Vector3.zero,
		}
		state.Mem[p.Id] = m
	end
	return m
end

-- Tras un pase de un bot: el receptor (y solo el) va a por el balon
function Tactics.notePass(state: any, world: any, cfg: any, passer: any, mate: any, aim: Vector3)
	local d = (aim - passer.Pos).Magnitude
	local t = ballTime(cfg, Tactics.passSpeed(cfg, d), d)
	if t == math.huge then
		t = 2
	end
	state.Teams[passer.Team].Pass = { Receiver = mate.Id, Point = aim, Until = world.Now + t + 0.8 }
end

-- Momento en que un jugador alcanza un balon suelto (y donde)
local function intercept(world: any, cfg: any, p: any): (number, Vector3)
	local ball = world.Ball
	local pos = flat(ball.Pos)
	local vel = flat(ball.Vel)
	local k = damping(cfg)
	if vel.Magnitude < 3 then
		return reachTime(cfg, p, pos, 0.1), pos
	end
	local t = 0
	while t <= 3 do
		local travel = (1 - math.exp(-k * t)) / k
		local q = clampField(world, pos + vel * travel, 1)
		local speedThere = vel.Magnitude * math.exp(-k * t)
		if speedThere <= cfg.Control.MaxCatchSpeed and reachTime(cfg, p, q, 0.1) <= t then
			return t, q
		end
		t += 0.1
	end
	local travel = (1 - math.exp(-k * 3)) / k
	local q = clampField(world, pos + vel * travel, 1)
	return 3 + reachTime(cfg, p, q, 0), q
end

-- ---------------------------------------------------------------------------
-- Juego con los humanos y saque del portero
-- ---------------------------------------------------------------------------

-- El bot que mejor recibiria un pase del humano que lleva el balon (para que lo pida). nil si ninguno lo merece:
-- tiene que estar libre (pase muy seguro) y mejor colocado que el humano, o el humano tiene que estar presionado.
function Tactics.bestCaller(world: any, cfg: any, team: number, carrier: any, ballPos: Vector3): any
	local B = cfg.Bots
	local pressed = rivalTime(world, cfg, team, carrier.Pos, 0) < B.CallPressure
	local here = threat(world, team, ballPos)
	local best, bestValue = nil, -math.huge
	for _, q in world.Players do
		if q.Team ~= team or not q.Bot or q.Keeper or q.Id == carrier.Id then
			continue
		end
		local target = clampField(world, q.Pos + q.Vel * 0.35, 3)
		local d = (target - ballPos).Magnitude
		if d < 8 or d > B.MaxPassDistance then
			continue
		end
		local safe = passSafety(world, cfg, team, ballPos, target, target)
		local gain = threat(world, team, target) - here
		if safe >= B.CallMinSafe and (gain >= B.CallMinGain or pressed) then
			local value = safe + gain * 4
			if value > bestValue then
				best, bestValue = q, value
			end
		end
	end
	return best
end

-- Saque del portero (con el balon en las manos): el mejor companero al que pasarsela. Devuelve
-- { Mate, Aim, Distance, Safe } o nil si no hay ningun pase con al menos "minSafe" de seguridad (entonces espera a que
-- alguien se desmarque o, si ya ha esperado mucho, despeja lejos).
function Tactics.keeperPass(world: any, cfg: any, keeper: any, minSafe: number?): any
	local B = cfg.Bots
	local team = keeper.Team
	local a = attackDir(team)
	local from = flat(keeper.Pos)
	local best, bestValue = nil, -math.huge
	for _, q in world.Players do
		if q.Team ~= team or q.Keeper or not q.CanControl then
			continue
		end
		local targets: { Vector3 } = { q.Pos + q.Vel * 0.35 }
		-- Tambien un poco por delante (hacia la porteria rival), para que reciba de cara
		table.insert(targets, q.Pos + Vector3.new(a * 6, 0, 0))
		for _, target in targets do
			target = clampField(world, target, 3)
			local d = (target - from).Magnitude
			if d < 10 or d > B.KeeperPassMax then
				continue
			end
			local safe = passSafety(world, cfg, team, from, target, q.Pos + q.Vel * 0.35)
			local progress = math.max(0, (target.X - from.X) * a) / world.Field.Length
			local value = safe * (threat(world, team, target) + progress * B.ProgressBonus)
				- (1 - safe) * (B.PossessionValue + danger(world, team, target) * B.LossWeight)
			if q.Requesting and safe >= B.RequestMinSafe then
				value += B.RequestBonus -- el humano pide el balon (E)
			end
			if safe >= (minSafe or B.KeeperPassMinSafe) and value > bestValue then
				best, bestValue = { Mate = q, Aim = target, Distance = d, Safe = safe }, value
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
-- Ataque sin balon: buscar el mejor sitio para recibir
-- ---------------------------------------------------------------------------

local function bestSpot(world: any, cfg: any, state: any, p: any, role: string, ballPos: Vector3, taken: { Vector3 }): Vector3
	local B = cfg.Bots
	local a = attackDir(p.Team)
	local m = memOf(state, p)
	local half = world.Field.Width / 2
	-- Puesto de referencia
	local anchor: Vector3
	local L = world.Field.Length
	local ballDepth = ballPos.X * a -- profundidad del balon: -L/2 en nuestra porteria, +L/2 en la rival
	if role == "Pivot" then
		-- Arriba y centrado: por delante del balon (como poco a PivotMinDepth); cerca del area rival, en el centro,
		-- esperando el pase atras o el centro desde la banda
		local depth = math.clamp(ballDepth + B.PivotAhead, B.PivotMinDepth, L / 2 - B.PivotGoalGap)
		anchor = Vector3.new(depth * a, 0, ballPos.Z * 0.15)
	else
		-- Ala: a la altura del balon (o un poco por delante) y abierto hacia la banda contraria (o la suya si el balon
		-- va por el centro): da un pase lateral o en diagonal
		local side = if math.abs(ballPos.Z) > 8 then -math.sign(ballPos.Z) else (if p.Pos.Z >= 0 then 1 else -1)
		-- Cuanto mas atras esta el balon, mas sube el ala (salida por fuera de la presion) y mas se abre
		local back = math.clamp((L / 2 - ballDepth) / L, 0, 1) -- 1 = balon en nuestra porteria, 0 = en la rival
		local ahead = B.SupportAhead + back * B.SupportAheadDeep
		local depth = math.clamp(ballDepth + ahead, -L / 2 + 16, L / 2 - 14)
		local wide = B.SupportWide + back * B.SupportWideDeep
		local z = side * math.clamp(math.abs(ballPos.Z) * 0.3 + wide, 12, half - 6)
		anchor = Vector3.new(depth * a, 0, z)
	end
	anchor = clampField(world, anchor, 5)

	if role == "Cierre" then
		-- Cierre (el defensa en ataque): por detras del balon, centrado, como pase de seguridad y cubriendo la espalda
		local depth = math.clamp(ballDepth - B.CierreBehind, -L / 2 + 14, L / 2 - 30)
		anchor = Vector3.new(depth * a, 0, ballPos.Z * 0.3)
	end
	-- Cada uno en su zona de actividad
	local zMin, zMax = zoneOf(world, cfg, p)
	anchor = Vector3.new(math.clamp(anchor.X * a, zMin, zMax) * a, 0, anchor.Z)
	anchor = clampField(world, anchor, 5)

	-- Cada punto se puntua con: WeightSafe * seguro + WeightThreat * seguro * peligro + WeightSpace * espacio + resto.
	-- "seguro" (passSafety) es lo caro de calcular y vale como mucho 1: primero se calcula todo lo demas, se ordenan los
	-- puntos por su mejor puntuacion posible (seguro = 1) y solo se calcula "seguro" mientras alguno pueda ganar al mejor.
	-- El resultado es el mismo que probandolos todos, pero con muchas menos cuentas.
	local step = B.GridStep
	local radius = if role == "Pivot" then B.PivotRadius elseif role == "Cierre" then B.CierreRadius else B.SupportRadius
	local anchorWeight = if role == "Support" then B.AnchorWeight else B.AnchorWeight * 2
	local threatWeight = B.WeightThreat * (if role == "Pivot" then 1.4 else 0.8)
	local r = math.floor(radius / step)
	local spots: { Vector3 } = {}
	local gains: { number } = {} -- lo que multiplica a "seguro"
	local rests: { number } = {} -- lo que no depende de "seguro"
	local order: { number } = {}
	local count = 0
	for ix = -r, r do
		for iz = -r, r do
			local ox, oz = ix * step, iz * step
			if ox * ox + oz * oz > radius * radius then
				continue
			end
			local spot = clampField(world, anchor + Vector3.new(ox, 0, oz), 4)
			local toBall = (spot - ballPos).Magnitude
			local value = threat(world, p.Team, spot)
			local myTime = reachTime(cfg, p, spot, 0)
			local space = math.clamp(rivalTime(world, cfg, p.Team, spot, 0.2) - myTime, -1, 1.5)
			local rest = B.WeightSpace * space
			-- Distancia de pase comoda
			if toBall < B.IdealPassMin then
				rest -= (B.IdealPassMin - toBall) * 0.06
			elseif toBall > B.IdealPassMax then
				rest -= (toBall - B.IdealPassMax) * 0.03
			end
			-- No pisarse con los companeros (ni ponerse en su misma linea de pase)
			for _, other in taken do
				local dd = (spot - other).Magnitude
				if dd < B.MinSpacing then
					rest -= (B.MinSpacing - dd) * 0.05
				end
				if math.abs(spot.Z - other.Z) < 5 and math.abs(spot.X - other.X) < 16 then
					rest -= 0.08
				end
			end
			-- El ala no debe quedarse muy por detras del balon (no ayuda a avanzar)
			if role == "Support" and (spot.X - ballPos.X) * a < -B.SupportMaxBehind then
				rest -= 0.1
			end
			-- Lejos de las bandas no tan pegado (salvo que haya mucho espacio)
			if math.abs(spot.Z) > half - 5 then
				rest -= 0.03
			end
			rest -= (spot - p.Pos).Magnitude * 0.003
			rest -= (spot - anchor).Magnitude * anchorWeight -- sin alejarse mucho de su puesto
			rest -= outsideZone(world, cfg, p, spot) * B.ZonePenalty / 10 -- ni de su zona
			if (spot - m.Target).Magnitude < 3 then
				rest += B.KeepBonus
			end
			count += 1
			spots[count] = spot
			gains[count] = B.WeightSafe + threatWeight * value
			rests[count] = rest
			order[count] = count
		end
	end
	-- Mejor puntuacion posible de cada punto (con "seguro" = 1), de mayor a menor
	table.sort(order, function(x: number, y: number): boolean
		return gains[x] + rests[x] > gains[y] + rests[y]
	end)
	local best = anchor
	local bestScore = -math.huge
	for _, index in order do
		if gains[index] + rests[index] <= bestScore then
			break -- ni con un pase 100 % seguro supera al mejor: los demas tampoco
		end
		local spot = spots[index]
		local safe = passSafety(world, cfg, p.Team, ballPos, spot, spot)
		local score = gains[index] * safe + rests[index]
		if score > bestScore then
			bestScore = score
			best = spot
		end
	end
	return best
end

-- Reparte puestos de ataque entre los companeros sin balon. "ballPos": donde esta (o estara) el balon.
local function planAttack(world: any, cfg: any, state: any, team: number, ballPos: Vector3, exclude: { [any]: boolean }, out: { [any]: any })
	local _a = attackDir(team)
	local taken: { Vector3 } = { ballPos }
	local bots: { any } = {}
	for _, p in world.Players do
		if p.Team == team and not p.Keeper and not exclude[p.Id] then
			if p.Bot then
				table.insert(bots, p)
			else
				table.insert(taken, p.Pos + p.Vel * 0.5) -- los humanos van a su aire: se cuenta donde estaran
			end
		end
	end
	-- Cada uno segun su posicion: el delantero de pivot, el medio de ala y el defensa de cierre
	local roleOf = { Delantero = "Pivot", Medio = "Support", Defensa = "Cierre" }
	table.sort(bots, function(x, y)
		return x.Slot < y.Slot
	end)
	for _, p in bots do
		local role = roleOf[positionOf(cfg, p)] or "Support"
		local spot = bestSpot(world, cfg, state, p, role, ballPos, taken)
		table.insert(taken, spot)
		local far = (spot - p.Pos).Magnitude
		out[p.Id] = { Role = role, Target = spot, Urgent = far > 14 }
	end
end

-- ---------------------------------------------------------------------------
-- Defensa
-- ---------------------------------------------------------------------------

local function planDefense(world: any, cfg: any, state: any, team: number, carrierPos: Vector3, carrierId: any, exclude: { [any]: boolean }, out: { [any]: any })
	local B = cfg.Bots
	local ownGoal = ownGoalOf(world, team)
	local defenders: { any } = {}
	for _, p in world.Players do
		if p.Team == team and p.Bot and not p.Keeper and not exclude[p.Id] then
			table.insert(defenders, p)
		end
	end
	if #defenders == 0 then
		return
	end
	-- Trabajos posibles: cobertura del centro y marcaje de los atacantes peligrosos
	local jobs: { any } = {}
	local toGoal = ownGoal - carrierPos
	local coverDist = math.clamp(toGoal.Magnitude * B.CoverFactor, B.CoverMin, B.CoverMax)
	local cover = carrierPos + (if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.zero) * coverDist
	local xg = shotValue(world, cfg, 3 - team, carrierPos)
	if xg > 0.06 then
		-- Puede tirar: cobertura en la linea de tiro, cerca del que tira
		cover = carrierPos + (if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.zero) * math.min(5, toGoal.Magnitude * 0.5)
	end
	table.insert(jobs, { Role = "Cover", Target = cover, Weight = 0.12 })
	-- En campo rival (lejos de nuestra porteria) solo se marca al mas peligroso; el resto guarda la zona
	local ballFromGoal = (carrierPos - ownGoal).Magnitude
	local maxMarks = if ballFromGoal < world.Field.Length * 0.5 then 2 else 1
	local marks: { any } = {}
	for _, opp in world.Players do
		if opp.Team ~= team and not opp.Keeper and opp.Id ~= carrierId then
			local dangerHere = threat(world, opp.Team, opp.Pos) * passSafety(world, cfg, opp.Team, carrierPos, opp.Pos)
			-- Atacantes muy por detras del balon no son peligro (no se les sigue arriba)
			local behind = (opp.Pos - carrierPos):Dot((carrierPos - ownGoal).Unit)
			if behind > 10 then
				dangerHere *= 0.3
			end
			if dangerHere > B.MarkDangerMin then
				local g = ownGoal - opp.Pos
				local mark = opp.Pos + (if g.Magnitude > 0.1 then g.Unit else Vector3.zero) * B.MarkDistance
				-- Un poco hacia el balon: asi puede cortar el pase
				mark = mark:Lerp(carrierPos, B.MarkBallSide)
				table.insert(marks, { Role = "Mark", Target = mark, Weight = dangerHere })
			end
		end
	end
	table.sort(marks, function(x, y)
		return x.Weight > y.Weight
	end)
	for i = 1, math.min(maxMarks, #marks) do
		table.insert(jobs, marks[i])
	end
	-- El medio corta el pase al atacante mas peligroso: entre el balon y el, un poco mas hacia el balon
	if #marks > 0 then
		marks[1].Target = marks[1].Target:Lerp(carrierPos, B.LaneBallSide)
	end
	-- Zona: un poco mas atras, cerrando el centro (para el que no marca ni cubre)
	local zone = carrierPos + (if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.zero) * math.min(toGoal.Magnitude * 0.6, B.CoverMax + 12)
	table.insert(jobs, { Role = "Zone", Target = Vector3.new(zone.X, 0, zone.Z * 0.5), Weight = 0.05 })
	-- Trabajos por posicion: el defensa cubre la espalda (el mas retrasado, o marca al que se le cuela), el medio
	-- corta el pase al atacante mas peligroso y el delantero (si no presiona) tapa la salida sin hundirse.
	local half = world.Field.Length / 2
	local a = attackDir(team)
	local dirToGoal = if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.new(-a, 0, 0)
	local backDist = math.clamp(toGoal.Magnitude * B.BackFactor, B.BackMin, B.BackMax)
	local back = carrierPos + dirToGoal * backDist
	-- Atacante colado por detras del que cubre: el defensa se encarga de el
	local deepest: Vector3? = nil
	for _, opp in world.Players do
		if opp.Team ~= team and not opp.Keeper and opp.Id ~= carrierId then
			local oppGoalDist = (opp.Pos - ownGoal).Magnitude
			if oppGoalDist < (back - ownGoal).Magnitude + 4 and (not deepest or oppGoalDist < ((deepest :: Vector3) - ownGoal).Magnitude) then
				deepest = opp.Pos
			end
		end
	end
	if deepest then
		local g = ownGoal - (deepest :: Vector3)
		back = (deepest :: Vector3) + (if g.Magnitude > 0.1 then g.Unit else Vector3.zero) * B.MarkDistance
	end
	local lane = if #marks > 0 then marks[1].Target else cover
	local screen = carrierPos + dirToGoal * B.ScreenDistance
	local screenDepth = math.max(screen.X * a, B.ScreenMinDepth * half)
	screen = Vector3.new(screenDepth * a, 0, screen.Z)
	local wanted = {
		Defensa = { Role = "Back", Target = back },
		Medio = { Role = "Lane", Target = lane },
		Delantero = { Role = "Screen", Target = screen },
	}
	-- Si falta alguno (presiona o es humano), su trabajo lo hereda otro: primero la espalda, luego el pase
	local order = { "Defensa", "Medio", "Delantero" }
	local free: { [string]: boolean } = { Defensa = true, Medio = true, Delantero = true }
	local assigned: { [any]: any } = {}
	for _, p in defenders do
		local pos = positionOf(cfg, p)
		if free[pos] then
			free[pos] = false
			assigned[p.Id] = wanted[pos]
		end
	end
	for _, p in defenders do
		if not assigned[p.Id] then
			for _, pos in order do
				if free[pos] then
					free[pos] = false
					assigned[p.Id] = wanted[pos]
					break
				end
			end
		end
	end
	-- Si el defensa no esta (humano o presionando) y queda libre "la espalda", el medio la cubre en lugar del pase
	if free.Defensa then
		for _, p in defenders do
			if assigned[p.Id] and assigned[p.Id].Role == "Lane" then
				assigned[p.Id] = wanted.Defensa
				break
			end
		end
	end
	for _, p in defenders do
		local job = assigned[p.Id] or { Role = "Zone", Target = zone }
		local target = clampField(world, job.Target, 2)
		-- Su zona de actividad (el defensa no sube a presionar arriba, el delantero no se hunde)
		local zMin, zMax = zoneOf(world, cfg, p)
		target = Vector3.new(math.clamp(target.X * a, zMin, zMax) * a, 0, target.Z)
		local wrongSide = (p.Pos - carrierPos):Dot((carrierPos - ownGoal).Unit) > 0
		out[p.Id] = { Role = job.Role, Target = target, Urgent = wrongSide or (target - p.Pos).Magnitude > 10 }
	end
end

-- ---------------------------------------------------------------------------
-- Plan de un equipo
-- ---------------------------------------------------------------------------

-- Profundidad del delantero del equipo (la mas adelantada entre donde esta y a donde va), o nil si no hay
local function delanteroDepth(world: any, cfg: any, state: any, team: number): number?
	local a = attackDir(team)
	for _, p in world.Players do
		if p.Team == team and not p.Keeper and positionOf(cfg, p) == "Delantero" then
			local depth = p.Pos.X * a
			local m = state.Mem[p.Id]
			if p.Bot and m and m.Target then
				depth = math.min(depth, m.Target.X * a)
			end
			return depth
		end
	end
	return nil
end

local planTeamRaw: (any, any, any, number) -> { [any]: any }

-- El medio (sin balon y sin ir a por el) se queda por detras del delantero
local function planTeam(world: any, cfg: any, state: any, team: number): { [any]: any }
	local out = planTeamRaw(world, cfg, state, team)
	local B = cfg.Bots
	-- El portero rival tiene el balon en las manos: nadie se coloca dentro de su primer tercio (Match les obliga a salir)
	local clear = world.KeeperClear
	if clear and clear.Team ~= team then
		local inward = attackDir(clear.Team) -- desde su porteria hacia el campo
		local goalX = -inward * world.Field.Length / 2
		for _, order in out do
			if (order.Target.X - goalX) * inward < clear.Depth then
				order.Target = Vector3.new(goalX + inward * clear.Depth, 0, order.Target.Z)
			end
		end
	end
	local delDepth = delanteroDepth(world, cfg, state, team)
	if not delDepth then
		return out
	end
	local a = attackDir(team)
	for _, p in world.Players do
		local order = out[p.Id]
		if order and p.Team == team and p.Bot and positionOf(cfg, p) == "Medio" then
			if order.Role ~= "Carrier" and order.Role ~= "Chase" and order.Role ~= "Press" and order.Role ~= "Wait" then
				local zMin = zoneOf(world, cfg, p)
				local cap = math.max((delDepth :: number) - B.MedioBehind, zMin)
				local depth = order.Target.X * a
				if depth > cap then
					order.Target = Vector3.new(cap * a, 0, order.Target.Z)
				end
			end
		end
	end
	return out
end

function planTeamRaw(world: any, cfg: any, state: any, team: number): { [any]: any }
	local B = cfg.Bots
	local ball = world.Ball
	local ballPos = flat(ball.Pos)
	local now = world.Now
	local T = state.Teams[team]
	local out: { [any]: any } = {}
	local exclude: { [any]: boolean } = {}

	-- Saque de centro: quietos hasta el pase
	local kickoff = world.Kickoff
	if kickoff and kickoff.Waiting then
		for _, p in world.Players do
			if p.Team == team and p.Bot and not p.Keeper then
				out[p.Id] = { Role = "Wait", Target = p.Pos, Urgent = false }
			end
		end
		return out
	end

	local controller = ball.Controller
	local hasBall = controller ~= nil and controller.Team == team
	if T.HadBall and not hasBall and controller ~= nil then
		T.LostAt = now -- acabamos de perderlo: presion inmediata
	end
	T.HadBall = hasBall
	-- Urgencia: tiempo con el balon sin llegar al ultimo tercio (cuanto mas, mas arriesgan)
	if hasBall and ballPos.X * attackDir(team) < world.Field.Length / 6 then
		T.Stall += B.PlanInterval
	elseif hasBall or controller ~= nil then
		T.Stall = 0
	end

	if hasBall then
		exclude[controller.Id] = true
		if controller.Bot then
			out[controller.Id] = { Role = "Carrier", Target = controller.Pos, Urgent = false }
		end
		planAttack(world, cfg, state, team, ballPos, exclude, out)
		-- Companero humano con el balon: el bot mejor desmarcado se lo pide ("¡Pasala!")
		if controller.Human then
			if T.HumanCarrier ~= controller.Id then
				T.HumanCarrier = controller.Id
				T.HumanSince = now
			end
			if now - T.HumanSince >= B.CallAfter then
				local caller = Tactics.bestCaller(world, cfg, team, controller, ballPos)
				if caller and out[caller.Id] then
					out[caller.Id].Call = true
				end
			end
		else
			T.HumanCarrier = nil
		end
		return out
	end
	T.HumanCarrier = nil

	if controller then
		-- DEFENSA: uno presiona al que lleva el balon (al portero con el balon en las manos no se le presiona)
		local best, bestTime = nil, math.huge
		local fallback, fallbackTime = nil, math.huge
		local deep = (controller.Pos.X * attackDir(team)) < -world.Field.Length / 6 -- el rival esta en nuestro tercio
		for _, p in world.Players do
			if p.Team == team and not p.Keeper and not controller.Keeper then
				local t = reachTime(cfg, p, controller.Pos, 0)
				if p.Human and t > B.HumanEngagedTime then
					continue -- un humano solo cuenta si ya esta encima (no sabemos si ira)
				end
				-- Presiona sobre todo el delantero; el medio y el defensa solo si el rival ya esta en nuestro tercio
				-- (o si ya estan encima del balon)
				local position = positionOf(cfg, p)
				local bias = (if deep then B.PressBiasDeep else B.PressBias)[position] or 0
				local allowed = deep or position == "Delantero" or t < B.PressCloseTime or p.Human
				if allowed and t + bias < bestTime then
					best, bestTime = p, t + bias
				end
				if t + bias < fallbackTime then
					fallback, fallbackTime = p, t + bias
				end
			end
		end
		if not best then
			best = fallback -- no hay delantero disponible: el que le toque por cercania
		end
		if best then
			exclude[best.Id] = true
			if best.Bot then
				local g = ownGoalOf(world, team) - controller.Pos
				local jockey = controller.Pos + (if g.Magnitude > 0.1 then g.Unit else Vector3.zero) * B.JockeyDistance
				out[best.Id] = { Role = "Press", Target = jockey, Urgent = true }
			end
		end
		planDefense(world, cfg, state, team, ballPos, controller.Id, exclude, out)
		return out
	end

	-- BALON SUELTO (o pase en camino)
	local pass = T.Pass
	local receiver: any = nil
	if pass and now < pass.Until then
		for _, p in world.Players do
			if p.Id == pass.Receiver then
				receiver = p
			end
		end
	else
		T.Pass = nil
	end

	local ourBest, ourTime, ourPoint = nil, math.huge, ballPos
	local ourBiased, ourBiasedTime, ourBiasedRaw, ourBiasedPoint = nil, math.huge, math.huge, ballPos
	local theirTime, theirPoint, theirBest = math.huge, ballPos, nil
	for _, p in world.Players do
		if p.Keeper or not p.CanControl then
			continue
		end
		local t, q = intercept(world, cfg, p)
		if ball.LastTouch and ball.LastTouch.Id == p.Id and flat(ball.Vel).Magnitude > 15 then
			t += 3 -- quien acaba de golpear no persigue su propio pase o tiro
		end
		if p.Human and p.Team == team and t > B.HumanEngagedTime and not (receiver and receiver.Id == p.Id) then
			continue -- un companero humano solo cuenta si esta encima del balon (o si el pase es para el)
		end
		if p.Team == team then
			if receiver and p.Id == receiver.Id then
				t -= 0.6 -- el receptor del pase tiene preferencia
			end
			if t < ourTime then
				ourBest, ourTime, ourPoint = p, t, q
			end
			local deepBall = (q.X * attackDir(team)) < -world.Field.Length / 6
			local biased = t + ((if deepBall then B.PressBiasDeep else B.PressBias)[positionOf(cfg, p)] or 0)
			if biased < ourBiasedTime then
				ourBiased, ourBiasedTime, ourBiasedRaw, ourBiasedPoint = p, biased, t, q
			end
		elseif t < theirTime then
			theirBest, theirTime, theirPoint = p, t, q
		end
	end

	-- Va a por el balon el que le toca por posicion, salvo que asi lo perdamos y el mas rapido si lo gane
	if ourBiased and ourBest and ourBiased ~= ourBest and not (receiver and ourBest.Id == receiver.Id) then
		local biasedWins = ourBiasedRaw <= theirTime + 0.15
		local fastestWins = ourTime <= theirTime + 0.15
		if biasedWins or not fastestWins then
			ourBest, ourTime, ourPoint = ourBiased, ourBiasedRaw, ourBiasedPoint
		end
	end
	if ourBest and (ourTime <= theirTime + 0.15 or (receiver and ourBest.Id == receiver.Id)) then
		-- Lo cogemos nosotros: uno va a por el y el resto ya se abre para atacar
		exclude[ourBest.Id] = true
		if ourBest.Bot then
			out[ourBest.Id] = { Role = "Chase", Target = ourPoint, Urgent = true }
		end
		planAttack(world, cfg, state, team, ourPoint, exclude, out)
	else
		-- Lo coge el rival: el nuestro mas rapido lo disputa si llega a tiempo; el resto defiende
		-- (el que le toca por posicion si llega; el medio solo si de verdad llega antes)
		local disputer, disputePoint = ourBest, ourPoint
		if ourBiased and ourBiased ~= ourBest and ourBiasedRaw < theirTime + 0.7 then
			disputer, disputePoint = ourBiased, ourBiasedPoint
		elseif ourBest and positionOf(cfg, ourBest) == "Medio" and ourBest.Bot and ourTime > theirTime - 0.1
			and (ourPoint.X * attackDir(team)) > -world.Field.Length / 6 then
			disputer = nil
		end
		if disputer and (ourTime < theirTime + 0.7 or now - T.LostAt < B.CounterPressSeconds) then
			exclude[disputer.Id] = true
			if disputer.Bot then
				out[disputer.Id] = { Role = "Chase", Target = disputePoint, Urgent = true }
			end
		end
		planDefense(world, cfg, state, team, theirPoint, if theirBest then theirBest.Id else nil, exclude, out)
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Con balon: decidir
-- ---------------------------------------------------------------------------

local function decideCarrier(world: any, cfg: any, state: any, p: any): any
	local B = cfg.Bots
	local team = p.Team
	local a = attackDir(team)
	local pos = p.Pos
	local m = memOf(state, p)
	local held = world.Now - m.BallSince
	local origin = flat(world.Ball.Pos) -- el balon sale desde aqui (delante del pie)
	local L = world.Field.Length
	-- Urgencia (0..1): lleva rato sin avanzar -> arriesga mas, premia mas avanzar y tira antes
	local urgency = math.clamp(state.Teams[team].Stall / B.StallSeconds, 0, 1)
	local lossWeight = B.LossWeight * (1 - 0.6 * urgency)
	local progressBonus = B.ProgressBonus * (1 + 2 * urgency)
	local function progress(target: Vector3): number
		return math.max(0, (target.X - origin.X) * a) / (L / 2)
	end

	-- Presion actual: cuanto tarda el rival mas cercano en llegarme
	local pressure = rivalTime(world, cfg, team, pos, 0)
	local keepNow = sigmoid((pressure - 0.45) / 0.15)

	local options: { any } = {}

	-- 1) Tiro
	local xg, aim, chip = shotValue(world, cfg, team, pos)
	if xg >= B.MinShotXG * (1 - 0.4 * urgency) then
		-- Tras un tiro casi siempre se pierde la posesion: se cuenta ese coste
		local value = xg * B.ShootBias * (1 + 0.5 * urgency) - (1 - xg) * B.PossessionValue * 0.5
		table.insert(options, { Kind = if chip then "ShootHigh" else "Shoot", Aim = aim, Value = value })
	end

	-- 2) Pases (al pie y al hueco)
	for _, q in world.Players do
		if q.Team ~= team or q.Id == p.Id or not q.CanControl then
			continue
		end
		local targets: { Vector3 } = { q.Pos + q.Vel * 0.35 }
		if not q.Keeper then
			local run = if q.Vel.Magnitude > 4 then q.Vel.Unit else Vector3.new(a, 0, 0)
			table.insert(targets, q.Pos + run * 8)
			table.insert(targets, q.Pos + Vector3.new(a * 9, 0, 0))
		end
		for _, target in targets do
			target = clampField(world, target, 3)
			local d = (target - pos).Magnitude
			if d < 6 or d > B.MaxPassDistance then
				continue
			end
			local safe, tBall = passSafety(world, cfg, team, origin, target, q.Pos + q.Vel * 0.35)
			local tRecv = reachTime(cfg, q, target, 0.1)
			if tRecv > tBall + 0.5 then
				safe *= 0.35 -- el balon llega mucho antes que el companero
			end
			-- (el valor de la zona ya es el valor de tener el balon alli: la posesion solo cuenta como coste al perderla)
			local gain = threat(world, team, target) + progress(target) * progressBonus
			local lossCost = B.PossessionValue + danger(world, team, (origin + target) / 2) * lossWeight
			local value = safe * gain * B.PassBias - (1 - safe) * lossCost
			if q.Keeper then
				value -= 0.04
			end
			if q.Requesting and safe >= B.RequestMinSafe then
				value += B.RequestBonus -- el humano pide el balon (E): se le da preferencia
			end
			table.insert(options, { Kind = "Pass", Aim = target, Mate = q, Value = value, Distance = d, Safe = safe })
		end
	end

	-- 3) Conducir (varias direcciones) o aguantar
	local medioCap: number? = nil
	if positionOf(cfg, p) == "Medio" then
		local delDepth = delanteroDepth(world, cfg, state, team)
		if delDepth then
			medioCap = math.max(delDepth - B.MedioBehind, pos.X * a)
		end
	end
	local goal = goalOf(world, team)
	local toGoal = (goal - pos)
	local baseDir = if toGoal.Magnitude > 0.1 then toGoal.Unit else Vector3.new(a, 0, 0)
	local carryLength = p.RunSpeed * cfg.Control.DribbleSpeedFactor * 0.6
	for _, deg in { -150, -110, -75, -45, -20, 0, 20, 45, 75, 110, 150, 180 } do
		local r = math.rad(deg)
		local dir = Vector3.new(baseDir.X * math.cos(r) - baseDir.Z * math.sin(r), 0, baseDir.X * math.sin(r) + baseDir.Z * math.cos(r))
		local dest = clampField(world, pos + dir * carryLength, 3)
		local arrive = (dest - pos).Magnitude / math.max(p.RunSpeed * cfg.Control.DribbleSpeedFactor, 1)
		local reached = 1 - sigmoid((rivalTime(world, cfg, team, dest, 0) - arrive - 0.15) / 0.18) -- le alcanzan antes de llegar
		local keep = (1 - reached * B.DuelLossChance) * (0.55 + 0.45 * keepNow)
		local value = keep * (threat(world, team, dest) + progress(dest) * progressBonus)
			- (1 - keep) * (B.PossessionValue + danger(world, team, pos) * lossWeight)
			- math.max(0, danger(world, team, dest) - danger(world, team, pos)) * B.OwnGoalAvoid -- no ir hacia su porteria
		-- Contra la pared o en una esquina se queda sin salida
		local F = world.Field
		local wallZ = F.Width / 2 - math.abs(dest.Z)
		local wallX = F.Length / 2 - math.abs(dest.X)
		if wallZ < B.WallMargin then
			value -= (B.WallMargin - wallZ) * 0.012
		end
		if wallX < B.WallMargin and math.abs(dest.Z) > F.GoalWidth / 2 then
			value -= (B.WallMargin - wallX) * 0.02
		end
		local hold = B.HoldSeconds * ((B.HoldFactor[positionOf(cfg, p)] or 1))
		if held > hold then
			value *= B.HoldPenalty -- lleva mucho: mejor mover el balon
		end
		-- No irse conduciendo fuera de su zona (el defensa no se va al ataque con el balon)
		value -= outsideZone(world, cfg, p, dest) * B.ZonePenalty / 10
		if medioCap and dest.X * a > medioCap then
			value -= (dest.X * a - medioCap) * B.ZonePenalty / 10 -- el medio no se va por delante del delantero
		end
		table.insert(options, { Kind = "Dribble", Target = dest, Value = value })
	end

	-- 4) Croqueta: con un rival encima, un instante de inmunidad y un salto lateral para salir de la presion
	if pressure < B.JukePressure and world.Now >= m.NextJukeAt then
		local escape = B.JukeKeep * threat(world, team, pos)
			- (1 - B.JukeKeep) * (B.PossessionValue + danger(world, team, pos) * lossWeight)
		table.insert(options, { Kind = "Juke", Value = escape })
	end

	-- 5) Sombrero: con un rival justo delante y cerca, levanta el balon por encima de el (solo el puede recogerlo)
	if world.Now >= (m.NextFlickAt or 0) then
		local blocked = false
		for _, opp in world.Players do
			if opp.Team ~= team and not opp.Keeper then
				local to = opp.Pos - pos
				local d = to.Magnitude
				if d > 1 and d < B.FlickRange and p.Look:Dot(to / d) > 0.75 then
					blocked = true
				end
			end
		end
		if blocked then
			local landing = clampField(world, pos + p.Look * B.FlickLanding, 3)
			local escape = B.FlickKeep * (threat(world, team, landing) + progress(landing) * progressBonus)
				- (1 - B.FlickKeep) * (B.PossessionValue + danger(world, team, pos) * lossWeight)
			table.insert(options, { Kind = "Flick", Value = escape })
		end
	end

	local best = nil
	local bestValue = -math.huge
	local bestDribble = -math.huge
	for _, option in options do
		local v = option.Value + noise(B.DecisionNoise)
		if v > bestValue then
			best, bestValue = option, v
		end
		if option.Kind == "Dribble" then
			bestDribble = math.max(bestDribble, option.Value)
		end
	end
	m.Debug = { Keep = keepNow, Dribble = bestDribble, Pressure = pressure, Options = options, Urgency = urgency }
	-- Croqueta (elegida como mejor opcion)
	if best and best.Kind == "Juke" then
		m.NextJukeAt = world.Now + cfg.Bots.JukeCooldown
		local nearest, nd = nil, math.huge
		for _, opp in world.Players do
			if opp.Team ~= team and not opp.Keeper then
				local d = (opp.Pos - pos).Magnitude
				if d < nd then
					nearest, nd = opp, d
				end
			end
		end
		local side = 1
		if nearest then
			local right = Vector3.new(-p.Look.Z, 0, p.Look.X)
			side = if (nearest.Pos - pos):Dot(right) > 0 then -1 else 1
		end
		return { Kind = "Juke", Value = side }
	end
	if best and best.Kind == "Flick" then
		m.NextFlickAt = world.Now + cfg.Bots.FlickCooldown
	end
	return best
end

-- ---------------------------------------------------------------------------
-- Actualizacion (cada fotograma)
-- ---------------------------------------------------------------------------

-- Rellena p.Out para cada bot: { Role, Target, Urgent, Face, Execute }
function Tactics.update(state: any, world: any, cfg: any)
	local B = cfg.Bots
	local now = world.Now

	-- Planes de equipo (varias veces por segundo: tambien hace de tiempo de reaccion)
	for team = 1, 2 do
		local T = state.Teams[team]
		if world.Live and now >= T.NextPlanAt then
			T.NextPlanAt = now + B.PlanInterval
			local plan = planTeam(world, cfg, state, team)
			for id, order in plan do
				local m = state.Mem[id]
				if m then
					m.Role = order.Role
					m.Target = order.Target
					m.Urgent = order.Urgent
					m.Call = order.Call == true
				end
			end
		end
	end

	local ball = world.Ball
	for _, p in world.Players do
		if not p.Bot or p.Keeper then
			continue
		end
		local m = memOf(state, p)
		local out: any = { Role = m.Role, Target = m.Target, Urgent = m.Urgent, Face = nil, Execute = nil, Call = false }
		p.Out = out
		if not world.Live or p.Stunned then
			m.Pending = nil
			out.Target = p.Pos
			out.Role = "Wait"
			continue
		end
		-- Pide el balon al companero humano (como mucho un bot cada CallCooldown segundos por equipo)
		if m.Call then
			m.Call = false
			local T = state.Teams[p.Team]
			if now >= (T.NextCallAt or 0) then
				T.NextCallAt = now + B.CallCooldown
				out.Call = true
			end
		end
		local hasBall = ball.Controller ~= nil and ball.Controller.Id == p.Id

		if hasBall then
			if not m.HadBall then
				m.HadBall = true
				m.BallSince = now
				m.NextDecisionAt = now + B.FirstTouchDelay
				m.Pending = nil
				m.Carry = nil
			end
			out.Role = "Carrier"
			if not m.Pending and m.NextDecisionAt > now + 0.05 and now - m.BallSince > 0.15 then
				for _, q in world.Players do
					if q.Team == p.Team and q.Requesting then
						m.NextDecisionAt = now -- un companero pide el balon: se decide ya
					end
				end
			end
			if not m.Pending and now >= m.NextDecisionAt then
				m.NextDecisionAt = now + B.DecisionInterval
				local choice = decideCarrier(world, cfg, state, p)
				if choice then
					if choice.Kind == "Dribble" then
						m.Carry = choice.Target
					elseif choice.Kind == "Juke" then
						out.Execute = { Kind = "Juke", Value = choice.Value }
					elseif choice.Kind == "Flick" then
						out.Execute = { Kind = "Flick" }
					else
						local charge = 0
						if choice.Kind == "Shoot" then
							local d = (choice.Aim - p.Pos).Magnitude
							charge = math.clamp(0.55 + d / 70, 0.6, 1)
						elseif choice.Kind == "ShootHigh" then
							charge = math.clamp(0.15 + (choice.Aim - p.Pos).Magnitude / 140, 0.15, 0.45)
						end
						-- Con un rival encima se golpea casi de primeras (sin tiempo para perfilarse)
						local aimTime = B.AimTime * math.clamp((m.Debug and m.Debug.Pressure or 1) / 0.6, 0.25, 1)
						m.Pending = { Kind = choice.Kind, Aim = choice.Aim, Mate = choice.Mate, Value = charge, At = now + aimTime, Safe = choice.Safe }
					end
				end
			end
			out.Target = m.Carry or (p.Pos + p.Look * 6)
			out.Urgent = rivalTime(world, cfg, p.Team, p.Pos, 0) > 0.8
		else
			m.HadBall = false
			m.Carry = nil
			if m.Pending then
				m.Pending = nil -- perdio el balon antes de golpear
			end
		end

		-- Accion preparada: perfilarse y golpear
		local pending = m.Pending
		if pending then
			local aim = pending.Aim
			if pending.Mate then
				-- Pase: recalcula con la posicion actual del companero (al hueco si va corriendo)
				local q = pending.Mate
				for _, other in world.Players do
					if other.Id == q.Id then
						q = other
					end
				end
				local lead = clampField(world, q.Pos + q.Vel * 0.35, 3)
				if (lead - pending.Aim).Magnitude < 10 then
					aim = pending.Aim:Lerp(lead, 0.5)
				end
			end
			local toAim = flat(aim - p.Pos)
			out.Face = if toAim.Magnitude > 0.1 then toAim.Unit else p.Look
			out.Target = p.Pos + p.Look * 1.5
			out.Urgent = false
			local facing = p.Look:Dot(out.Face) > math.cos(math.rad(8))
			if now >= pending.At or facing then
				m.Pending = nil
				m.NextDecisionAt = now + B.DecisionInterval
				out.Execute = {
					Kind = pending.Kind,
					Value = pending.Value,
					Aim = aim,
					Mate = pending.Mate,
					PassDistance = if pending.Kind == "Pass" then toAim.Magnitude else nil,
					Safe = pending.Safe,
				}
			end
			continue
		end

		-- Presion: entrada cuando lo tiene a tiro
		local controller = ball.Controller
		if (m.Role == "Press" or m.Role == "Chase") and controller and controller.Team ~= p.Team then
			local reach = math.min((controller.Pos - p.Pos).Magnitude, (flat(ball.Pos) - p.Pos).Magnitude)
			if reach < 9 then
				-- Cerca: al balon directamente
				out.Target = flat(ball.Pos)
				out.Face = (flat(ball.Pos) - p.Pos).Unit
			end
			-- Cerca de nuestra porteria se defiende con mas intensidad
			local dangerZone = threat(world, controller.Team, controller.Pos) > B.DangerZoneThreat
			local interval = if dangerZone then B.TackleInterval * 0.65 else B.TackleInterval
			local chance = if dangerZone then math.min(1, B.TackleChance * 1.5) else B.TackleChance
			if reach <= cfg.Control.TackleRange - 0.8 and now >= m.NextTackleAt then
				m.NextTackleAt = now + interval * (0.8 + rand() * 0.5)
				if rand() < chance then
					out.Execute = { Kind = if rand() < B.SlideChance then "Slide" else "Tackle", Aim = flat(ball.Pos) }
				end
			end
		elseif m.Role == "Chase" and not controller then
			-- Balon lento: directo a el (si va rapido, al punto de corte que calculo el plan)
			if flat(ball.Vel).Magnitude < 10 or (flat(ball.Pos) - p.Pos).Magnitude < 6 then
				out.Target = flat(ball.Pos) + flat(ball.Vel) * 0.12
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Movimiento suave (compartido por el juego y el simulador)
-- ---------------------------------------------------------------------------

-- Desvio para no chocar: se aparta de los jugadores que tiene muy cerca y delante (en el juego los cuerpos chocan y
-- se empujan). El que va a por el balon solo esquiva a sus companeros; a los rivales los encara.
local function avoidance(cfg: any, p: any, want: Vector3, chasing: boolean, players: { any }?): Vector3
	if not players then
		return want
	end
	local radius = cfg.Bots.AvoidRadius
	local push = Vector3.zero
	for _, o in players do
		if o == p or o.Keeper or (chasing and o.Team ~= p.Team) then
			continue
		end
		local away = flat(p.Pos - o.Pos)
		local d = away.Magnitude
		if d < radius and d > 0.05 then
			local ahead = -away.Unit:Dot(want) -- 1 = lo tengo justo delante
			if ahead > -0.2 then
				push += away.Unit * ((radius - d) / radius) * (0.6 + 0.4 * ahead)
			end
		end
	end
	if push.Magnitude < 0.01 then
		return want
	end
	local mixed = want + push * cfg.Bots.AvoidStrength
	return if mixed.Magnitude > 0.01 then mixed.Unit else want
end

-- Devuelve la direccion de carrera (gira poco a poco), el ritmo (0..1), si esprinta y hacia donde mirar.
-- "players" (opcional): todos los jugadores, para no chocar con ellos.
function Tactics.steer(state: any, p: any, ballPos: Vector3, dt: number, cfg: any, players: { any }?): (Vector3, number, boolean, Vector3)
	local B = cfg.Bots
	local out = p.Out
	local m = memOf(state, p)
	if not out then
		return Vector3.zero, 0, false, p.Look
	end
	local toTarget = flat(out.Target - p.Pos)
	local distance = toTarget.Magnitude
	local chasing = out.Role == "Chase" or out.Role == "Press" or out.Role == "Carrier"
	local faceBall = flat(ballPos - p.Pos)
	faceBall = if faceBall.Magnitude > 0.1 then faceBall.Unit else p.Look

	if distance < B.ArriveDistance and not chasing then
		m.MoveDir = Vector3.zero
		return Vector3.zero, 0, false, out.Face or faceBall
	end
	-- Persiguiendo y ya encima del objetivo: se para (si no, pasaba de largo, volvia y se quedaba dando vueltas
	-- alrededor del balon cuando no podia cogerlo: botando, reservado para el receptor de un pase...)
	if chasing and out.Role ~= "Carrier" and distance < B.OrbitStopDistance then
		m.MoveDir = Vector3.zero
		return Vector3.zero, 0, false, faceBall
	end

	-- Direccion: gira como mucho TurnRate rad/s
	local want = if distance > 0.01 then toTarget.Unit else p.Look
	if distance > 2 then
		want = avoidance(cfg, p, want, chasing, players)
	end
	local current = m.MoveDir
	if current.Magnitude < 0.01 then
		current = if p.Vel.Magnitude > 2 then flat(p.Vel).Unit else want
	end
	local rate = if out.Role == "Carrier" then B.TurnRateWithBall else B.TurnRate
	-- Cerca del objetivo se gira mas rapido (como al encarar el balon en corto)
	if distance < B.CloseTurnDistance and out.Role ~= "Carrier" then
		rate *= B.CloseTurnBoost
	end
	local cosAngle = math.clamp(current:Dot(want), -1, 1)
	local angle = math.acos(cosAngle)
	local dir: Vector3
	if angle <= rate * dt then
		dir = want
	else
		-- Gira "rate * dt" hacia el lado que acerca a la direccion buscada
		local step = rate * dt
		local c, s = math.cos(step), math.sin(step)
		local d1 = Vector3.new(current.X * c - current.Z * s, 0, current.X * s + current.Z * c)
		local d2 = Vector3.new(current.X * c + current.Z * s, 0, -current.X * s + current.Z * c)
		dir = if d1:Dot(want) >= d2:Dot(want) then d1 else d2
	end
	dir = dir.Unit
	m.MoveDir = dir

	-- Ritmo
	local urgent = out.Urgent or distance > B.SprintDistance
	local pace = if urgent or chasing then 1 else B.JogFactor
	if not chasing and distance < B.SlowDownDistance then
		pace *= math.clamp(distance / B.SlowDownDistance, 0.3, 1)
	end
	if out.Role == "Press" and distance < 5 then
		pace *= 0.75 -- se acerca con cuidado, sin pasarse de largo
	end
	if angle > math.rad(110) then
		pace *= 0.55 -- media vuelta
	end
	-- Sin orbitar: el radio de giro es velocidad / giro. Si el objetivo esta mas cerca de lo que da para girar hacia el,
	-- frena lo justo (un jugador de verdad frena para encarar el balon; antes daba vueltas a su alrededor)
	local sprint = (urgent or chasing) and distance > 6
	if angle > math.rad(20) and distance < B.CloseTurnDistance * 2 then
		local runSpeed = (p.RunSpeed or 18) * (if sprint then 1.3 else 1)
		local maxPace = rate * math.max(distance, 0.5) * 0.5 / runSpeed
		if pace > maxPace then
			pace = math.max(maxPace, 0.25)
			sprint = false
		end
	end

	-- Mirada: si corre lejos o lleva el balon, hacia donde va; si se recoloca cerca, hacia el balon
	local face: Vector3
	if out.Face then
		face = out.Face
	elseif chasing and out.Role ~= "Carrier" and (flat(ballPos - p.Pos)).Magnitude < B.CloseTurnDistance then
		-- Cerca del balon, lo mira (aunque aun corra de lado): para recogerlo hay que tenerlo DELANTE
		-- (Ball: DribbleFrontDot). Antes miraba hacia donde corria y, con el balon a un lado, se quedaba dando vueltas.
		face = faceBall
	elseif out.Role == "Carrier" or (out.Role == "Chase") or (distance > 12 and pace > 0.6) then
		face = dir
	else
		face = faceBall
	end
	return dir, pace, sprint, face
end

return Tactics
