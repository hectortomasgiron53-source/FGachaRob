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

type Anim = { Run: AnimationTrack?, Idle: AnimationTrack?, Failed: boolean }

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
		a = { Run = nil, Idle = nil, Failed = false }
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
		end
		run:AdjustSpeed(math.clamp(speed / 16, 0.5, 1.7))
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
	}
end

-- ---------------------------------------------------------------------------
-- Bucle (lo llama Match.update cada Heartbeat)
-- ---------------------------------------------------------------------------

function BotBrain.update(match: any, dt: number, now: number)
	local state = states[match]
	if not state then
		state = Tactics.newState()
		states[match] = state
		print(`[Bots] Cerebro tactico {Balance.Version}: desmarques, pases seguros, presion, cobertura y marcaje`)
	end
	local world = snapshot(match, now)
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

		-- Segada o croqueta en curso: direccion impuesta (a los humanos se la aplica su cliente)
		if world.Live and os.clock() < actor.ForcedMoveUntil then
			humanoid:Move(actor.ForcedMoveDir)
			continue
		end
		if not world.Live or info.Stunned then
			humanoid:Move(Vector3.zero)
			actor.SprintWanted = false
			continue
		end

		-- Accion
		local out = info.Out
		local exec = if out then out.Execute else nil
		if exec then
			local aim: Vector3? = exec.Aim
			if aim then
				local worldDir = origin:VectorToWorldSpace(flat(aim - info.Pos))
				if worldDir.Magnitude > 0.1 then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + flat(worldDir))
				end
			end
			if exec.Kind == "Pass" then
				match:performAction(actor, "Pass", nil, exec.PassDistance)
				if match.Ball.LastTouch == actor and match.Ball.Controller == nil and exec.Mate then
					Tactics.notePass(state, world, Balance, info, exec.Mate, exec.Aim) -- el receptor va a por el
				end
			else
				match:performAction(actor, exec.Kind, exec.Value)
			end
		end

		-- Movimiento suave
		local dir, pace, sprint, face = Tactics.steer(state, info, ballLocal, dt, Balance)
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
