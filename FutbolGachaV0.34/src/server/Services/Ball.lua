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
local CollisionSetup = require(script.Parent.CollisionSetup)

local BallControlEvent = Remotes.get("BallControl")

export type BallState = "Free" | "Controlled" | "Stopped"

type Fields = {
	Part: Part,
	Origin: CFrame,
	State: BallState,
	Controller: Types.Actor?,
	LastTouch: Types.Actor?,
	ProtectedBy: Types.Actor?, -- tras un sombrero, solo este actor puede recoger el balon...
	ProtectedUntil: number, -- ...hasta este instante
	Dead: boolean, -- balon dentro de la porteria: sin control, sin golpeos y casi sin rebote
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

-- Cada jugador tiene su propio enfriamiento para que el mensaje no salga una y otra vez
-- al perder y recuperar el balon (claves debiles: se limpia solo cuando el actor desaparece).
local lastAnnounce: { [Types.Actor]: number } = setmetatable({}, { __mode = "k" }) :: any

local function announceControl(actor: Types.Actor)
	local now = os.clock()
	local last = lastAnnounce[actor]
	if last and now - last < Balance.Control.AnnounceCooldown then
		return
	end
	lastAnnounce[actor] = now

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
	CollisionSetup.setup()
	part.CollisionGroup = CollisionSetup.BALL
	part.Parent = parent
	claimNetworkOwnership(part)

	local fields: Fields = {
		Part = part,
		Origin = origin,
		State = "Free",
		Controller = nil,
		LastTouch = nil,
		ProtectedBy = nil,
		ProtectedUntil = 0,
		Dead = false,
	}
	local self = setmetatable(fields, Ball)
	self:placeAtCenter()
	return self
end

-- Publica quien controla el balon (para que el cliente sepa si tiene balon y dibuje su balon sin retraso).
-- ControllerUserId: UserId del humano que lo controla; 0 = nadie o un bot.
function Ball._sync(self: Ball)
	local controller = self.Controller
	local userId = 0
	if controller and controller.Player then
		userId = controller.Player.UserId
	end
	if self.Part:GetAttribute("ControllerUserId") ~= userId then
		self.Part:SetAttribute("ControllerUserId", userId)
	end
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
	self.ProtectedBy = nil
	self.Dead = false
	self:_sync()
end

-- Anclado donde esta (celebracion de un gol, final).
function Ball.freeze(self: Ball)
	local part = self.Part
	self.Controller = nil
	self.State = "Stopped"
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Anchored = true
	self:_sync()
end

-- Devuelve la fisica al balon (al empezar el partido).
function Ball.release(self: Ball)
	if self.State ~= "Stopped" then
		return
	end
	self.Part.Anchored = false
	claimNetworkOwnership(self.Part)
	self.Dead = false
	self.State = "Free"
end

function Ball._updateControl(
	self: Ball,
	vel: Vector3,
	actors: { Types.Actor },
	now: number,
	localPos: Vector3,
	dt: number
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
		local protectedBy = if now < self.ProtectedUntil then self.ProtectedBy else nil
		for _, actor in actors do
			local allowed = protectedBy == nil or protectedBy == actor
			if allowed and actor.Controllable and now >= actor.ReleaseAt and now >= actor.StunnedUntil then
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
			local rootVel = MathUtil.flat(root.AssemblyLinearVelocity)
			-- El objetivo se adelanta segun la velocidad: compensa el retraso con el que el servidor ve al jugador
			local target = root.Position + look.Unit * C.DribbleDistance + rootVel * C.DribbleLead
			-- El balon se recoloca directamente hacia el objetivo (no por fuerzas): al girar, cambia de direccion
			-- casi al instante en vez de describir una curva larga.
			local current = part.Position
			local alpha = 1 - math.exp(-C.DribbleSnapRate * dt)
			local nextX = current.X + (target.X - current.X) * alpha
			local nextZ = current.Z + (target.Z - current.Z) * alpha
			part.CFrame = CFrame.new(nextX, current.Y, nextZ) * part.CFrame.Rotation
			vel = Vector3.new(rootVel.X, vel.Y, rootVel.Z)
		end
	end

	return vel
end

-- El balon ha entrado entero en la porteria: nadie puede controlarlo ni golpearlo y se frena en seco.
function Ball.kill(self: Ball)
	self.Dead = true
	self.Controller = nil
	self.ProtectedBy = nil
	if self.State ~= "Stopped" then
		self.State = "Free"
	end
	self:_sync()
end

-- El portero atrapa el balon: queda anclado en sus manos ("position", en el mundo) hasta que saca con keeperRelease.
function Ball.keeperCatch(self: Ball, keeper: Types.Actor, position: Vector3)
	local part = self.Part
	self.Controller = nil
	self.ProtectedBy = nil
	self.State = "Stopped"
	self.LastTouch = keeper
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Anchored = true
	part.CFrame = CFrame.new(position)
	self:_sync()
end

-- Mientras el portero lo tiene, el balon va pegado a sus manos.
function Ball.keeperCarry(self: Ball, position: Vector3)
	if self.State == "Stopped" and self.Part.Anchored then
		self.Part.CFrame = CFrame.new(position)
	end
end

-- Despeje / rechace del portero: el balon sale rebotado con la velocidad indicada.
function Ball.keeperParry(self: Ball, keeper: Types.Actor, velocity: Vector3)
	self.Controller = nil
	self.ProtectedBy = nil
	self.LastTouch = keeper
	self.Part.AssemblyLinearVelocity = velocity
	self:_sync()
end

-- Saque del portero: el balon vuelve a ser fisico con la velocidad indicada.
function Ball.keeperRelease(self: Ball, keeper: Types.Actor, velocity: Vector3)
	local part = self.Part
	part.Anchored = false
	claimNetworkOwnership(part)
	self.Dead = false
	self.State = "Free"
	self.LastTouch = keeper
	part.AssemblyLinearVelocity = velocity
	self:_sync()
end

-- Se llama cada Heartbeat desde Match.update.
function Ball.step(self: Ball, dt: number, actors: { Types.Actor }, now: number)
	if self.State == "Stopped" then
		return
	end
	if self.Dead then
		local f = math.max(0, 1 - 12 * dt)
		self.Part.AssemblyLinearVelocity = self.Part.AssemblyLinearVelocity * f
		self.Part.AssemblyAngularVelocity = self.Part.AssemblyAngularVelocity * f
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

	vel = self:_updateControl(vel, actors, now, localPos, dt)

	if vel.Magnitude > B.MaxSpeed then
		vel = vel.Unit * B.MaxSpeed
	end
	part.AssemblyLinearVelocity = vel
	self:_sync()
end

-- Golpeo (pase o tiro). Lo valida el servidor: alcance, estado del balon y estadisticas del personaje.
function Ball.kick(self: Ball, actor: Types.Actor, kind: string, charge: number, goalPosition: Vector3): boolean
	local K = Balance.Kick
	local part = self.Part
	if self.State == "Stopped" or self.Dead then
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

	if kind == "Shoot" or kind == "ShootHigh" then
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
		if kind == "ShootHigh" then
			-- Tiro alto: mucho mas elevado y algo mas lento (vaselina / tiro a la escuadra)
			speed *= K.HighSpeedFactor
			-- La carga decide sobre todo la fuerza hacia arriba: poca = vaselina, media = escuadra, mucha = fuera
			lift = MathUtil.lerp(K.HighUpMin, K.HighUpMax, charge) / math.max(speed, 1)
		else
			lift = MathUtil.lerp(K.ShotLiftMin, K.ShotLiftMax, charge)
		end
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
	self.ProtectedBy = nil
	self:_sync()
	return true
end

-- Saque de centro: el balon (parado en el centro) sale raso hacia el companero elegido, con la fuerza justa para
-- llegar a el. Mientras viaja, solo ese companero puede controlarlo.
function Ball.kickoffPass(self: Ball, kicker: Types.Actor, receiver: Types.Actor)
	local K = Balance.Kickoff
	local part = self.Part
	local toReceiver = MathUtil.flat(receiver.Root.Position - part.Position)
	local distance = toReceiver.Magnitude
	local dir = if distance > 0.1 then toReceiver.Unit else MathUtil.flat(-kicker.Root.CFrame.LookVector).Unit
	local arrive = K.ArriveSpeed
	if receiver.IsGoalkeeper then
		-- Al portero se la deja algo antes y mas suave, para que la bloque sin peligro de que se cuele
		distance = math.max(0, distance - 6)
		arrive *= 0.5
	end
	-- El cesped frena el balon de forma exponencial (Ball.RollDamping): v0 = distancia * frenado + velocidad de llegada
	local speed = math.min(distance * Balance.Ball.RollDamping + arrive, Balance.Ball.MaxSpeed)
	part.Anchored = false
	claimNetworkOwnership(part)
	self.Dead = false
	self.State = "Free"
	self.Controller = nil
	self.LastTouch = kicker
	part.AssemblyAngularVelocity = Vector3.zero
	part.AssemblyLinearVelocity = dir * speed
	kicker.ReleaseAt = os.clock() + Balance.Control.KickLockSeconds
	self.ProtectedBy = receiver
	self.ProtectedUntil = os.clock() + K.ProtectSeconds
	self:_sync()
end

-- Entrada: intenta robar el balon a un rival que lo controla.
-- Devuelve: "NoTarget" (no habia rival con balon a tu alcance), "Won" (lo robas) o "Failed" (el rival aguanta).
function Ball.tackle(self: Ball, actor: Types.Actor, now: number): string
	local C = Balance.Control
	local victim = self.Controller
	if not victim or victim.Team == actor.Team then
		return "NoTarget"
	end
	local toVictim = MathUtil.flat(victim.Root.Position - actor.Root.Position)
	if toVictim.Magnitude > C.TackleRange then
		return "NoTarget"
	end
	if toVictim.Magnitude > 0.05 then
		local look = MathUtil.flat(actor.Root.CFrame.LookVector)
		if look.Magnitude > 0.01 and look.Unit:Dot(toVictim.Unit) < 0.2 then
			return "NoTarget"
		end
	end
	if now < victim.ImmuneUntil then
		return "Failed" -- el rival esta regateando
	end

	local chance = math.clamp(C.TackleBaseChance + (actor.Stats.Defense - victim.Stats.Dribbling) / 200, 0.15, 0.85)
	if rng:NextNumber() > chance then
		return "Failed"
	end

	victim.ReleaseAt = now + 0.8
	victim.StunnedUntil = now + C.TackledStunSeconds
	actor.ReleaseAt = 0
	self.Controller = actor
	self.LastTouch = actor
	self.State = "Controlled"
	self:_sync()
	announceControl(actor)
	return "Won"
end

-- Segada: se llama cada fotograma mientras dura la ventana de la segada de "actor".
-- Solo hay un contacto por segada: roba el balon a un rival, o empuja un balon suelto.
-- Devuelve "Won" (roba), "Poke" (empuja un balon suelto), "Failed" o nil (sin contacto todavia).
function Ball.slideContact(self: Ball, actor: Types.Actor, now: number): string?
	local C = Balance.Control
	if actor.SlideResolved or self.State == "Stopped" then
		return nil
	end
	local part = self.Part
	local toBall = MathUtil.flat(part.Position - actor.Root.Position)
	if toBall.Magnitude > C.SlideHitRange then
		return nil
	end
	if toBall.Magnitude > 0.05 and actor.SlideDir:Dot(toBall.Unit) < C.SlideHitDot then
		return nil
	end

	local victim = self.Controller
	if victim and victim.Team ~= actor.Team then
		actor.SlideResolved = true
		local chance = math.clamp(C.SlideBaseChance + (actor.Stats.Defense - victim.Stats.Dribbling) / 200, 0.25, 0.9)
		if now < victim.ImmuneUntil or rng:NextNumber() > chance then
			actor.StunnedUntil += 0.3 -- falla: tarda mas en levantarse
			return "Failed"
		end
		victim.StunnedUntil = now + C.SlideStunSeconds
		victim.ReleaseAt = now + C.SlideStunSeconds
		self.Controller = nil
		self.State = "Free"
		self.LastTouch = actor
		part.AssemblyLinearVelocity = actor.SlideDir * C.SlidePokeSpeed + Vector3.new(0, 4, 0)
		self:_sync()
		return "Won"
	elseif not victim then
		actor.SlideResolved = true
		self.LastTouch = actor
		part.AssemblyLinearVelocity = actor.SlideDir * C.SlidePokeSpeed + Vector3.new(0, 4, 0)
		return "Poke"
	end
	return nil
end

-- Sombrero: el jugador que controla el balon lo levanta por encima del rival. Solo el puede recogerlo al caer.
function Ball.flick(self: Ball, actor: Types.Actor, now: number): boolean
	local C = Balance.Control
	if self.Controller ~= actor then
		return false
	end
	local look = MathUtil.flat(actor.Root.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return false
	end
	self.Part.AssemblyLinearVelocity = look.Unit * C.FlickForward + Vector3.new(0, C.FlickUp, 0)
	self.Controller = nil
	self.State = "Free"
	self.LastTouch = actor
	self.ProtectedBy = actor
	self.ProtectedUntil = now + C.FlickProtectSeconds
	actor.ReleaseAt = now + C.FlickLockSeconds
	actor.ImmuneUntil = now + C.FlickImmuneSeconds
	self:_sync()
	return true
end

return Ball
