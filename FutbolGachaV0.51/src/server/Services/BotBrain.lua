--!strict
--[[
	BotBrain: une el partido de Roblox con el cerebro tactico (Tactics.lua).
	Cada fotograma:
	  1. Hace una "foto" del partido en coordenadas del campo (posiciones, velocidades, balon, saque...).
	  2. Tactics decide, para cada bot de campo, a donde ir, hacia donde mirar y que accion hacer.
	  3. Aqui se aplica: Humanoid:Move, ritmo (WalkSpeed), sprint, giro del cuerpo y acciones
	     (con Match.performAction: mismas reglas que un jugador humano).
	Los porteros no estan aqui: los lleva Match._updateKeepers.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Types = require(ReplicatedStorage.Shared.Types)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Tactics = require(script.Parent.Tactics)

local BotBrain = {}

-- Animaciones de serie de Roblox (R15) para que los bots no "patinen"
local RUN_ANIM = "rbxassetid://507767714"
local IDLE_ANIM = "rbxassetid://507766666"

type Anim = { Run: AnimationTrack?, Idle: AnimationTrack?, Failed: boolean, Speed: number }

local states: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local infos: { [Types.Actor]: any } = setmetatable({}, { __mode = "k" }) :: any
local anims: { [Types.Actor]: Anim } = setmetatable({}, { __mode = "k" }) :: any

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function isBot(actor: Types.Actor): boolean
	return actor.Player == nil and actor.Controllable and not actor.IsGoalkeeper
end

local function updateAnimation(actor: Types.Actor, speed: number)
	local a = anims[actor]
	if not a then
		a = { Run = nil, Idle = nil, Failed = false, Speed = 0 }
		anims[actor] = a
	end
	local anim = a :: Anim
	if anim.Failed then
		return
	end
	if not anim.Run then
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
			anim.Run = animator:LoadAnimation(run)
			anim.Idle = animator:LoadAnimation(idle)
		end)
		if not ok or not anim.Run then
			anim.Failed = true
			return
		end
	end
	local run = anim.Run :: AnimationTrack
	local idle = anim.Idle :: AnimationTrack
	if speed > 1.5 then
		if not run.IsPlaying then
			idle:Stop(0.25)
			run:Play(0.25)
			anim.Speed = 1 -- Play vuelve a la velocidad normal
		end
		-- Solo si cambia de verdad (cada ajuste se manda a los clientes)
		local rate = math.clamp(speed / 16, 0.5, 1.7)
		if math.abs(rate - anim.Speed) > 0.06 then
			anim.Speed = rate
			run:AdjustSpeed(rate)
		end
	elseif not idle.IsPlaying then
		run:Stop(0.3)
		idle:Play(0.3)
	end
end

-- Gira el cuerpo hacia "worldDir" como mucho "rate" rad/s (solo sobre el eje vertical)
local function turnTowards(root: BasePart, worldDir: Vector3, rate: number, dt: number)
	local look = flat(root.CFrame.LookVector)
	local want = flat(worldDir)
	if want.Magnitude < 0.01 or look.Magnitude < 0.01 then
		return
	end
	local current = math.atan2(-look.X, -look.Z)
	local target = math.atan2(-want.X, -want.Z)
	local diff = (target - current + math.pi) % (2 * math.pi) - math.pi
	local step = math.clamp(diff, -rate * dt, rate * dt)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, current + step, 0)
end

-- Foto del partido en coordenadas del campo
local function snapshot(match: any, now: number): any
	local origin: CFrame = match.Origin
	local players = {}
	for _, actor: Types.Actor in match.Actors do
		local root = actor.Root
		if not root.Parent then
			continue
		end
		local info = infos[actor]
		if not info then
			info = { Id = actor }
			infos[actor] = info
		end
		local look = flat(origin:VectorToObjectSpace(root.CFrame.LookVector))
		info.Team = actor.Team
		info.Slot = actor.Slot
		info.Keeper = actor.IsGoalkeeper
		info.Human = actor.Player ~= nil
		info.Bot = isBot(actor)
		info.Pos = flat(origin:PointToObjectSpace(root.Position))
		info.Vel = flat(origin:VectorToObjectSpace(root.AssemblyLinearVelocity))
		info.Look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(1, 0, 0)
		info.RunSpeed = MathUtil.mapStat(actor.Stats.Speed, Balance.Speed.Min, Balance.Speed.Max)
		info.Stats = actor.Stats
		info.Stunned = now < actor.StunnedUntil
		if match.Ball.Controller == actor then
			actor.RequestBallUntil = 0 -- ya la tiene: deja de pedirla
		end
		info.Requesting = actor.Player ~= nil and now < actor.RequestBallUntil -- pide el balon (E)
		info.CanControl = actor.Controllable and not actor.IsGoalkeeper
		info.Actor = actor
		table.insert(players, info)
	end
	local ball = match.Ball
	local controller: Types.Actor? = ball.Controller
	if not controller and match.KeeperHolding then
		controller = match.KeeperHolding -- portero con el balon en las manos: su equipo tiene la posesion
	end
	local kickoff = match.Kickoff
	local F = Balance.Field
	return {
		Now = now,
		Field = { Length = F.Length, Width = F.Width, GoalWidth = F.GoalWidth, CenterRadius = F.CenterCircleRadius, AreaRadius = F.AreaRadius },
		Ball = {
			Pos = origin:PointToObjectSpace(ball.Part.Position),
			Vel = origin:VectorToObjectSpace(ball.Part.AssemblyLinearVelocity),
			Controller = if controller then infos[controller] else nil,
			LastTouch = if ball.LastTouch then infos[ball.LastTouch] else nil,
		},
		Players = players,
		Kickoff = if kickoff then { Team = match.KickoffTeam, Waiting = not kickoff.Passed } else nil,
		Live = match:_isLive(),
		-- Portero con el balon en las manos: sus rivales tienen que quedarse fuera de su primer tercio
		KeeperClear = if match.KeeperHolding
			then { Team = match.KeeperHolding.Team, Depth = F.Length * Balance.Goalkeeper.ClearZoneFraction + Balance.Goalkeeper.ClearZoneMargin + 2 }
			else nil,
	}
end

-- ---------------------------------------------------------------------------
-- Bucle (lo llama Match.update cada Heartbeat)
-- ---------------------------------------------------------------------------

local function stateOf(match: any): any
	local state = states[match]
	if not state then
		state = Tactics.newState()
		states[match] = state
		print(`[Bots] Cerebro tactico {Balance.Version}: desmarques, pases seguros, presion, cobertura, marcaje y juego con el humano`)
	end
	return state
end

-- Un humano acaba de pasar a un bot (pase con "mini-iman"): ese bot va a por el balon y los demas no se lo quitan
local function noteHumanPass(state: any, world: any, match: any)
	local ball = match.Ball
	local kicker: Types.Actor? = ball.PassKicker
	local target: Types.Actor? = ball.PassTarget
	if not kicker or not target or not kicker.Player or state.NotedPassUntil == ball.PassUntil then
		return
	end
	state.NotedPassUntil = ball.PassUntil
	local passer, mate = infos[kicker], infos[target]
	if passer and mate and mate.Bot then
		Tactics.notePass(state, world, Balance, passer, mate, mate.Pos + mate.Vel * 0.35)
	end
end

-- Saque del portero (lo pide Match cuando el portero va a sacar con la mano). Devuelve el punto (en el mundo) al
-- que pasar, la velocidad del pase y el companero; o nil si no hay ningun pase con al menos "minSafe" de seguridad.
function BotBrain.keeperPass(match: any, keeper: Types.Actor, minSafe: number): (Vector3?, number, Types.Actor?)
	local now = os.clock()
	local state = stateOf(match)
	local world = snapshot(match, now)
	local info = infos[keeper]
	if not info then
		return nil, 0, nil
	end
	local choice = Tactics.keeperPass(world, Balance, info, minSafe)
	if not choice then
		return nil, 0, nil
	end
	Tactics.notePass(state, world, Balance, info, choice.Mate, choice.Aim) -- el receptor va a por el
	local origin: CFrame = match.Origin
	return origin:PointToWorldSpace(choice.Aim), Tactics.passSpeed(Balance, choice.Distance), choice.Mate.Actor
end

function BotBrain.update(match: any, dt: number, now: number)
	local state = stateOf(match)
	local world = snapshot(match, now)
	noteHumanPass(state, world, match)
	Tactics.update(state, world, Balance)

	local origin: CFrame = match.Origin
	local ballLocal = flat(world.Ball.Pos)
	for _, info in world.Players do
		if not info.Bot then
			continue
		end
		local actor: Types.Actor = info.Actor
		local humanoid = actor.Humanoid
		local root = actor.Root
		if humanoid.AutoRotate then
			humanoid.AutoRotate = false -- el cuerpo lo gira el cerebro (puede mirar al balon mientras se recoloca)
		end
		updateAnimation(actor, flat(root.AssemblyLinearVelocity).Magnitude)

		-- Segada, croqueta o retirada de la zona del portero: direccion impuesta (a los humanos se la aplica su cliente)
		if world.Live and os.clock() < actor.ForcedMoveUntil then
			humanoid:Move(actor.ForcedMoveDir)
			local keeper = match.KeeperHolding
			if keeper and keeper.Team ~= actor.Team then
				turnTowards(root, actor.ForcedMoveDir, Balance.Bots.TurnRate, dt) -- se da la vuelta y corre hacia atras
			end
			continue
		end
		if not world.Live or info.Stunned then
			humanoid:Move(Vector3.zero)
			actor.SprintWanted = false
			continue
		end

		-- Accion
		local out = info.Out
		if out and out.Call then
			match:botCall(actor) -- "¡Pasala!": pide el balon al companero humano
		end
		local exec = if out then out.Execute else nil
		if exec then
			local aim: Vector3? = exec.Aim
			if aim then
				local worldDir = origin:VectorToWorldSpace(flat(aim - info.Pos))
				if worldDir.Magnitude > 0.1 then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + flat(worldDir))
				end
			end
			-- Punto al que golpear, en el mundo (el golpeo sale desde el balon hacia alli)
			local aimWorld: Vector3? = if aim then origin:PointToWorldSpace(Vector3.new(aim.X, 0, aim.Z)) else nil
			if exec.Kind == "Pass" then
				-- Siempre con "mini-iman" hacia el companero: el pase se curva hacia el (o hacia donde corre) y frena al llegar
				local mateInfo = exec.Mate
				local mateActor: Types.Actor? = if mateInfo then mateInfo.Actor else nil
				match:performAction(actor, "Pass", nil, exec.PassDistance, mateActor, aimWorld)
				if match.Ball.LastTouch == actor and match.Ball.Controller == nil and exec.Mate then
					Tactics.notePass(state, world, Balance, info, exec.Mate, exec.Aim) -- el receptor va a por el
				end
			elseif exec.Kind == "Shoot" or exec.Kind == "ShootHigh" then
				match:performAction(actor, exec.Kind, exec.Value, nil, nil, aimWorld) -- al palo que eligio
			else
				match:performAction(actor, exec.Kind, exec.Value)
				if exec.Kind == "Flick" and match.Ball.Controller == nil and match.Ball.LastTouch == actor then
					-- Sombrero: el balon cae unos metros por delante; va a por el (solo el puede cogerlo)
					Tactics.notePass(state, world, Balance, info, info, info.Pos + info.Look * Balance.Bots.FlickLanding)
				end
			end
		end

		-- Movimiento suave
		local dir, pace, sprint, face = Tactics.steer(state, info, ballLocal, dt, Balance, world.Players)
		if dir.Magnitude > 0.01 then
			local worldDir: Vector3 = origin:VectorToWorldSpace(dir)
			humanoid:Move(worldDir)
			humanoid.WalkSpeed *= pace
		else
			humanoid:Move(Vector3.zero)
		end
		actor.SprintWanted = sprint
		if not exec and face.Magnitude > 0.01 then
			turnTowards(root, origin:VectorToWorldSpace(face), Balance.Bots.FaceTurnRate, dt)
		end
	end
end

return BotBrain
