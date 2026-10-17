--!strict
--[[
	Ball: el balon de un partido (clase). Fisica de Roblox con el servidor como dueno
	(SetNetworkOwner(nil)), para que nadie con mal ping pueda desincronizarlo ni hacer trampas.
	Estados: Free (suelto), Controlled (un jugador lo conduce), Stopped (anclado: antes del saque o tras un gol).

	Si el golpeo se siente mal en la Fase 1, el plan B es un balon simulado a mano (ver la hoja de ruta).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local BallControlEvent = Remotes.get("BallControl")

export type BallState = "Free" | "Controlled" | "Stopped"

type Fields = {
	Part: Part,
	Origin: CFrame,
	State: BallState,
	Controller: Types.Actor?,
	LastTouch: Types.Actor?,
}

local Ball = {}
Ball.__index = Ball

export type Ball = typeof(setmetatable({} :: Fields, Ball))

local rng = Random.new()

local function claimNetworkOwnership(part: Part)
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

local function announceControl(actor: Types.Actor)
	local head = actor.Model:FindFirstChild("Head")
	if actor.Player and head and head:IsA("BasePart") then
		BallControlEvent:FireAllClients(head, actor.Name .. " es un putoniga")
	end
	print(actor.Name .. " es un putoniga")
end

-- IMPORTANTE: "parent" ya debe estar dentro de Workspace (si no, SetNetworkOwner falla).
function Ball.new(parent: Instance, origin: CFrame): Ball
	local B = Balance.Ball
	local part = Instance.new("Part")
	part.Name = "Ball"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(B.Diameter, B.Diameter, B.Diameter)
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.SmoothPlastic
	part.CustomPhysicalProperties = PhysicalProperties.new(B.Density, B.Friction, B.Elasticity, 1, 1)
	part.CFrame = origin * CFrame.new(0, B.Diameter / 2, 0)
	part.Anchored = false
	part.Parent = parent
	claimNetworkOwnership(part)

	local fields: Fields = {
		Part = part,
		Origin = origin,
		State = "Free",
		Controller = nil,
		LastTouch = nil,
	}
	local self = setmetatable(fields, Ball)
	self:placeAtCenter()
	return self
end

function Ball.getLocalPosition(self: Ball): Vector3
	return self.Origin:PointToObjectSpace(self.Part.Position)
end

-- Anclado en el centro (antes del saque).
function Ball.placeAtCenter(self: Ball)
	local part = self.Part
	self.Controller = nil
	self.State = "Stopped"
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Anchored = true
	part.CFrame = self.Origin * CFrame.new(0, Balance.Ball.Diameter / 2, 0)
end

-- Anclado donde esta (celebracion de un gol, final).
function Ball.freeze(self: Ball)
	local part = self.Part
	self.Controller = nil
	self.State = "Stopped"
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Anchored = true
end

-- Devuelve la fisica al balon (al empezar el partido).
function Ball.release(self: Ball)
	if self.State ~= "Stopped" then
		return
	end
	self.Part.Anchored = false
	claimNetworkOwnership(self.Part)
	self.State = "Free"
end

function Ball._updateControl(
	self: Ball,
	vel: Vector3,
	actors: { Types.Actor },
	now: number,
	localPos: Vector3
): Vector3
	local C = Balance.Control
	local part = self.Part

	-- 1) Soltar el balon si el controlador se aleja, esta aturdido o el balon sube demasiado
	local controller = self.Controller
	if controller then
		local valid = controller.Root.Parent ~= nil
			and now >= controller.StunnedUntil
			and MathUtil.flat(part.Position - controller.Root.Position).Magnitude <= C.DribbleReleaseRange
			and localPos.Y <= C.MaxControlHeight
		if not valid then
			self.Controller = nil
			self.State = "Free"
			controller = nil
		end
	end

	-- 2) Si nadie lo controla, el jugador mas cercano que lo tenga delante lo recoge
	if not controller and vel.Magnitude <= C.MaxCatchSpeed and localPos.Y <= C.MaxControlHeight then
		local best: Types.Actor? = nil
		local bestDist = math.huge
		for _, actor in actors do
			if actor.Controllable and now >= actor.ReleaseAt and now >= actor.StunnedUntil then
				local toBall = MathUtil.flat(part.Position - actor.Root.Position)
				local dist = toBall.Magnitude
				if dist <= C.DribbleRange and dist < bestDist then
					local look = MathUtil.flat(actor.Root.CFrame.LookVector)
					local facing = dist < 0.05 or look.Unit:Dot(toBall.Unit) >= C.DribbleFrontDot
					if facing then
						best = actor
						bestDist = dist
					end
				end
			end
		end
		if best then
			self.Controller = best
			self.LastTouch = best
			self.State = "Controlled"
			announceControl(best)
			controller = best
		end
	end

	-- 3) Regate: pequenos toques que mantienen el balon delante (en vez de pegarlo al personaje)
	if controller then
		local root = controller.Root
		local look = MathUtil.flat(root.CFrame.LookVector)
		if look.Magnitude > 0.01 then
			local target = root.Position + look.Unit * C.DribbleDistance
			local rootVel = MathUtil.flat(root.AssemblyLinearVelocity)
			local desired = MathUtil.flat(target - part.Position) * C.DribbleStrength + rootVel
			local a = C.DribbleResponse
			vel = Vector3.new(MathUtil.lerp(vel.X, desired.X, a), vel.Y, MathUtil.lerp(vel.Z, desired.Z, a))
		end
	end

	return vel
end

-- Se llama cada Heartbeat desde Match.update.
function Ball.step(self: Ball, dt: number, actors: { Types.Actor }, now: number)
	if self.State == "Stopped" then
		return
	end
	local B = Balance.Ball
	local part = self.Part
	local localPos = self:getLocalPosition()
	local vel = part.AssemblyLinearVelocity

	-- Frenado al rodar por el suelo
	if localPos.Y <= B.Diameter / 2 + 0.25 then
		local f = math.max(0, 1 - B.RollDamping * dt)
		vel = Vector3.new(vel.X * f, vel.Y, vel.Z * f)
	end
	part.AssemblyAngularVelocity = part.AssemblyAngularVelocity * math.max(0, 1 - B.AngularDamping * dt)

	vel = self:_updateControl(vel, actors, now, localPos)

	if vel.Magnitude > B.MaxSpeed then
		vel = vel.Unit * B.MaxSpeed
	end
	part.AssemblyLinearVelocity = vel
end

-- Golpeo (pase o tiro). Lo valida el servidor: alcance, estado del balon y estadisticas del personaje.
function Ball.kick(self: Ball, actor: Types.Actor, kind: string, charge: number, goalPosition: Vector3): boolean
	local K = Balance.Kick
	local part = self.Part
	if self.State == "Stopped" then
		return false
	end
	if (part.Position - actor.Root.Position).Magnitude > Balance.Control.KickRange then
		return false
	end
	local look = MathUtil.flat(actor.Root.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return false
	end

	local dir = look.Unit
	local stats = actor.Stats
	local speed: number
	local lift: number
	local errorDeg: number

	if kind == "Shoot" then
		-- Ayuda de punteria: si la porteria esta dentro del cono, gira un poco hacia ella
		local toGoal = MathUtil.flat(goalPosition - actor.Root.Position)
		if toGoal.Magnitude > 1 then
			local angle = math.deg(math.acos(math.clamp(dir:Dot(toGoal.Unit), -1, 1)))
			if angle <= K.AimAssistConeDegrees then
				dir = dir:Lerp(toGoal.Unit, K.AimAssist).Unit
			end
		end
		local base = MathUtil.mapStat(stats.Shooting, K.ShotSpeedMin, K.ShotSpeedMax)
		speed = base * (K.ShotMinCharge + (1 - K.ShotMinCharge) * charge)
		lift = MathUtil.lerp(K.ShotLiftMin, K.ShotLiftMax, charge)
		errorDeg = MathUtil.mapStat(stats.Shooting, K.ErrorMaxDeg, K.ErrorMinDeg)
	else
		speed = MathUtil.mapStat(stats.Passing, K.PassSpeedMin, K.PassSpeedMax)
		lift = K.PassLift
		errorDeg = MathUtil.mapStat(stats.Passing, K.PassErrorMaxDeg, K.PassErrorMinDeg)
	end

	local angleError = math.rad((rng:NextNumber() * 2 - 1) * errorDeg)
	dir = CFrame.Angles(0, angleError, 0):VectorToWorldSpace(dir)

	part.AssemblyLinearVelocity = dir * speed + Vector3.new(0, speed * lift, 0)
	self.State = "Free"
	self.Controller = nil
	self.LastTouch = actor
	actor.ReleaseAt = os.clock() + Balance.Control.KickLockSeconds
	return true
end

-- Entrada: intenta robar el balon a un rival que lo controla. Devuelve true si lo roba.
function Ball.tackle(self: Ball, actor: Types.Actor, now: number): boolean
	local C = Balance.Control
	local victim = self.Controller
	if not victim or victim.Team == actor.Team then
		return false
	end
	local toVictim = MathUtil.flat(victim.Root.Position - actor.Root.Position)
	if toVictim.Magnitude > C.TackleRange then
		return false
	end
	if toVictim.Magnitude > 0.05 then
		local look = MathUtil.flat(actor.Root.CFrame.LookVector)
		if look.Magnitude > 0.01 and look.Unit:Dot(toVictim.Unit) < 0.2 then
			return false
		end
	end

	local chance = math.clamp(C.TackleBaseChance + (actor.Stats.Defense - victim.Stats.Dribbling) / 200, 0.15, 0.85)
	if rng:NextNumber() > chance then
		return false
	end

	victim.ReleaseAt = now + 0.8
	victim.StunnedUntil = now + C.TackledStunSeconds
	actor.ReleaseAt = 0
	self.Controller = actor
	self.LastTouch = actor
	self.State = "Controlled"
	announceControl(actor)
	return true
end

return Ball
