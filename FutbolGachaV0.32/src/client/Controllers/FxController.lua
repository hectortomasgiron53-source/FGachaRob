--!strict
--[[
	FxController: sonidos y animaciones sencillas del partido.
	El servidor avisa por el remote "Fx":
	  ("Sound", nombre, posicion?, volumen, tono, repeticiones)  -> posicion nil = sonido global (publico, silbato)
	  ("Anim", modelo, tipo, duracion, lado)                     -> animacion por codigo sobre las articulaciones R15
	Las animaciones no usan assets: giran un momento las articulaciones (Motor6D.C0) y las devuelven a su sitio.
	Funcionan sobre las animaciones normales de Roblox (correr, etc.), que siguen funcionando debajo.
]]
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MatchController = require(script.Parent.MatchController)
local AudioSettings = require(script.Parent.AudioSettings)

local FxController = {}

-- ---------------------------------------------------------------------------
-- Sonidos
-- ---------------------------------------------------------------------------

local function soundIdOf(entry: any): string?
	local id = entry.Id
	if id ~= nil and tostring(id) ~= "" then
		local text = tostring(id)
		if string.find(text, "://", 1, true) then
			return text
		end
		return "rbxassetid://" .. text
	end
	return entry.Fallback
end

local function makeSound(name: string, parent: Instance, volume: number, pitch: number): Sound?
	local entry = (Balance.Sounds :: any)[name]
	if type(entry) ~= "table" then
		return nil
	end
	local id = soundIdOf(entry)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	-- Grupo de volumen: lo controla el jugador en Configuracion (Publico o Efectos)
	sound.SoundGroup = AudioSettings.group(if string.sub(name, 1, 5) == "Crowd" then "Crowd" else "Effects")
	sound.Volume = (entry.Volume or 1) * volume * (Balance.Sounds.MasterVolume or 1)
	sound.PlaybackSpeed = (entry.Pitch or 1) * pitch * (1 + (math.random() - 0.5) * 0.08) -- pequena variacion natural
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = Balance.Sounds.MaxDistance
	sound.Parent = parent
	return sound
end

local function playSound(name: string, position: Vector3?, volume: number, pitch: number)
	local holder: Attachment? = nil
	local parent: Instance = SoundService
	if position then
		local attachment = Instance.new("Attachment")
		attachment.Parent = workspace.Terrain
		attachment.Position = position -- el Terrain esta en el origen: posicion local = posicion en el mundo
		holder = attachment
		parent = attachment
	end
	local sound = makeSound(name, parent, volume, pitch)
	if not sound then
		if holder then
			holder:Destroy()
		end
		return
	end
	sound:Play()
	sound.Ended:Once(function()
		if holder then
			holder:Destroy()
		else
			sound:Destroy()
		end
	end)
	Debris:AddItem(holder or sound, 15) -- por si nunca llega a cargar
end

-- Para otros controladores (el sorteo de la moneda reproduce sus sonidos aqui, con el volumen de Efectos).
FxController.playSound = playSound

-- Ambiente de publico en bucle mientras estas en un partido (no en el patio de juegos)
local crowdLoop: Sound? = nil
local function setCrowd(on: boolean)
	if on and not crowdLoop then
		local sound = makeSound("CrowdLoop", SoundService, 1, 1)
		if sound then
			sound.Looped = true
			sound:Play()
			crowdLoop = sound
		end
	elseif not on and crowdLoop then
		crowdLoop:Destroy()
		crowdLoop = nil
	end
end

-- ---------------------------------------------------------------------------
-- Animaciones por codigo (R15)
-- ---------------------------------------------------------------------------
-- Convenio de angulos (grados, giro sobre el eje X de la articulacion):
--   caderas y hombros: + = pierna/brazo hacia delante y arriba
--   rodillas: - = doblar (talon hacia atras); codos: + = doblar
--   Waist (cintura) y Root (todo el cuerpo): + = inclinarse hacia atras, - = hacia delante
--   eje Z: + = inclinarse hacia la izquierda

local JOINT_PART: { [string]: string } = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
}

type Pose = { [string]: { number } } -- articulacion -> { x, y, z } en grados
type Key = { Time: number, Pose: Pose }

local function key(time: number, pose: Pose): Key
	return { Time = time, Pose = pose }
end

-- Cada animacion: funcion (duracion, lado) -> lista de fotogramas clave. El ultimo vuelve a la postura normal.
local ANIMS: { [string]: (number, number) -> { Key } } = {
	Pass = function()
		return {
			key(0.09, { RightHip = { -25, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftShoulder = { 15, 0, 0 }, RightShoulder = { -15, 0, 0 } }),
			key(0.18, { RightHip = { 45, 0, 0 }, RightKnee = { -5, 0, 0 }, LeftShoulder = { 25, 0, 0 }, Waist = { -5, 0, 0 } }),
			key(0.38, {}),
		}
	end,
	Shoot = function()
		return {
			key(0.13, { RightHip = { -45, 0, 0 }, RightKnee = { -75, 0, 0 }, Waist = { 8, 0, 0 }, LeftShoulder = { 35, 0, 0 }, RightShoulder = { -30, 0, 0 } }),
			key(0.23, { RightHip = { 85, 0, 0 }, RightKnee = { -5, 0, 0 }, Waist = { -12, 0, 0 }, LeftShoulder = { 45, 0, 0 }, RightShoulder = { 20, 0, 0 } }),
			key(0.5, {}),
		}
	end,
	ShootHigh = function()
		return {
			key(0.13, { RightHip = { -40, 0, 0 }, RightKnee = { -70, 0, 0 }, Waist = { 12, 0, 0 }, LeftShoulder = { 35, 0, 0 }, RightShoulder = { -30, 0, 0 } }),
			key(0.24, { RightHip = { 100, 0, 0 }, RightKnee = { -5, 0, 0 }, Waist = { 22, 0, 0 }, LeftShoulder = { 60, 0, 0 }, RightShoulder = { 35, 0, 0 } }),
			key(0.55, {}),
		}
	end,
	Flick = function()
		return {
			key(0.1, { RightKnee = { -110, 0, 0 }, RightHip = { 15, 0, 0 } }),
			key(0.22, { RightHip = { -25, 0, 0 }, RightKnee = { -70, 0, 0 }, Waist = { -8, 0, 0 } }),
			key(0.4, {}),
		}
	end,
	Juke = function(_d: number, side: number)
		local lean = -side * 14
		return {
			key(0.08, { Root = { 0, 0, lean }, Waist = { 0, 0, lean * 0.6 }, RightShoulder = { 0, 0, side > 0 and -25 or 0 }, LeftShoulder = { 0, 0, side < 0 and 25 or 0 } }),
			key(0.3, {}),
		}
	end,
	Tackle = function()
		local pose: Pose = { RightHip = { 75, 0, 0 }, RightKnee = { -10, 0, 0 }, Waist = { -18, 0, 0 }, RightShoulder = { -35, 0, 0 }, LeftShoulder = { -35, 0, 0 } }
		return { key(0.12, pose), key(0.3, pose), key(0.45, {}) }
	end,
	Slide = function(d: number)
		local pose: Pose = {
			Root = { 45, 0, 0 },
			Waist = { -15, 0, 0 },
			RightHip = { 80, 0, 0 },
			RightKnee = { -5, 0, 0 },
			LeftHip = { 45, 0, 0 },
			LeftKnee = { -80, 0, 0 },
			LeftShoulder = { -50, 0, 0 },
			RightShoulder = { 30, 0, 0 },
		}
		local duration = if d > 0 then d else 1
		return { key(0.1, pose), key(math.max(0.12, duration - 0.3), pose), key(duration, {}) }
	end,
	KeeperDive = function(d: number)
		local pose: Pose = {
			RightShoulder = { 175, 0, 0 },
			LeftShoulder = { 175, 0, 0 },
			RightHip = { 10, 0, 0 },
			LeftHip = { -15, 0, 0 },
			LeftKnee = { -25, 0, 0 },
		}
		local duration = if d > 0 then d else 1.1
		return { key(0.12, pose), key(math.max(0.14, duration - 0.35), pose), key(duration, {}) }
	end,
	KeeperJump = function(d: number)
		local pose: Pose = { RightShoulder = { 170, 0, 0 }, LeftShoulder = { 170, 0, 0 }, RightKnee = { -35, 0, 0 }, LeftKnee = { -35, 0, 0 } }
		local duration = if d > 0 then d else 0.7
		return { key(0.15, pose), key(duration * 0.65, pose), key(duration, {}) }
	end,
	KeeperCatch = function(d: number)
		local pose: Pose = {
			RightShoulder = { 75, 0, 10 },
			LeftShoulder = { 75, 0, -10 },
			RightElbow = { 70, 0, 0 },
			LeftElbow = { 70, 0, 0 },
			Waist = { -10, 0, 0 },
		}
		local duration = if d > 0 then d else 1.2
		return { key(0.1, pose), key(math.max(0.12, duration - 0.2), pose), key(duration, {}) }
	end,
	KeeperParry = function()
		return {
			key(0.08, { RightShoulder = { 170, 0, 0 }, LeftShoulder = { 150, 0, 0 } }),
			key(0.5, {}),
		}
	end,
	Celebrate = function(d: number)
		local duration = if d > 0 then d else 2.5
		local keys: { Key } = {}
		local t = 0.2
		local up = true
		while t < duration - 0.3 do
			table.insert(keys, key(t, {
				RightShoulder = { if up then 165 else 140, 0, -15 },
				LeftShoulder = { if up then 140 else 165, 0, 15 },
				Waist = { 10, 0, 0 },
				RightKnee = { if up then -20 else 0, 0, 0 },
				LeftKnee = { if up then 0 else -20, 0, 0 },
			}))
			up = not up
			t += 0.3
		end
		table.insert(keys, key(duration, {}))
		return keys
	end,
}

-- Una articulacion puede ser un Motor6D (clasico) o un AnimationConstraint (articulaciones nuevas de Roblox).
-- En los dos casos se gira el "punto de union" del lado del padre: Motor6D.C0 o AnimationConstraint.Attachment0.CFrame.
type Joint = { Get: () -> CFrame, Set: (CFrame) -> (), Key: Instance }

local function findJoint(part: Instance, name: string): Joint?
	for _, child in part:GetChildren() do
		if child.Name == name then
			if child:IsA("Motor6D") then
				local motor = child
				return {
					Get = function()
						return motor.C0
					end,
					Set = function(value: CFrame)
						motor.C0 = value
					end,
					Key = motor :: Instance,
				}
			elseif child:IsA("AnimationConstraint") then
				local attachment = child.Attachment0
				if attachment then
					return {
						Get = function()
							return attachment.CFrame
						end,
						Set = function(value: CFrame)
							attachment.CFrame = value
						end,
						Key = attachment :: Instance,
					}
				end
			end
		end
	end
	return nil
end

type Active = { Start: number, Keys: { Key }, Motors: { [string]: Joint } }
local active: { [Model]: Active } = {}
local originals: { [Instance]: CFrame? } = setmetatable({}, { __mode = "k" }) :: any
local warnedModels: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function poseCFrame(pose: Pose, joint: string): CFrame
	local angles = pose[joint]
	if not angles then
		return CFrame.identity
	end
	return CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
end

local function restore(state: Active)
	for _, joint in state.Motors do
		local original = originals[joint.Key]
		if original and joint.Key.Parent then
			joint.Set(original)
		end
	end
end

local function playAnim(model: Model, kind: string, duration: number, side: number)
	local builder = ANIMS[kind]
	if not builder or not model.Parent then
		return
	end
	local previous = active[model]
	if previous then
		restore(previous)
	end
	local motors: { [string]: Joint } = {}
	for jointName, partName in JOINT_PART do
		local part = model:FindFirstChild(partName)
		local joint = if part then findJoint(part, jointName) else nil
		if joint then
			motors[jointName] = joint
			if originals[joint.Key] == nil then
				originals[joint.Key] = joint.Get()
			end
		end
	end
	if next(motors) == nil then
		if not warnedModels[model] then
			warnedModels[model] = true
			-- Diagnostico: que tipo de articulaciones tiene este personaje
			local found = {}
			for _, d in model:GetDescendants() do
				if d:IsA("JointInstance") or d:IsA("Constraint") then
					found[d.ClassName] = (found[d.ClassName] or 0) + 1
				end
			end
			local parts = {}
			for className, count in found do
				table.insert(parts, `{className} x{count}`)
			end
			warn(`[Fx] {model.Name}: no encuentro articulaciones R15 para animar. Tiene: {table.concat(parts, ", ")}`)
		end
		return
	end
	active[model] = { Start = os.clock(), Keys = builder(duration, side), Motors = motors }
end

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

local function stepAnims()
	local now = os.clock()
	for model, state in active do
		if not model.Parent then
			active[model] = nil
			continue
		end
		local elapsed = now - state.Start
		local keys = state.Keys
		local previousPose: Pose = {}
		local previousTime = 0
		local nextKey: Key? = nil
		for _, k in keys do
			if k.Time >= elapsed then
				nextKey = k
				break
			end
			previousPose = k.Pose
			previousTime = k.Time
		end
		if not nextKey then
			restore(state)
			active[model] = nil
			continue
		end
		local target = nextKey :: Key
		local alpha = smooth(math.clamp((elapsed - previousTime) / math.max(target.Time - previousTime, 1e-3), 0, 1))
		for jointName, joint in state.Motors do
			local original = originals[joint.Key]
			if original then
				local from = poseCFrame(previousPose, jointName)
				local to = poseCFrame(target.Pose, jointName)
				joint.Set(original * from:Lerp(to, alpha))
			end
		end
	end
end

-- ---------------------------------------------------------------------------

function FxController.start()
	Remotes.get("Fx").OnClientEvent:Connect(function(kind: string, ...: any)
		local args = { ... }
		if kind == "Sound" then
			local name, position, volume, pitch, count = args[1], args[2], args[3], args[4], args[5]
			if type(name) ~= "string" then
				return
			end
			local times = math.clamp(tonumber(count) or 1, 1, 5)
			for i = 1, times do
				task.delay((i - 1) * 0.7, playSound, name, if typeof(position) == "Vector3" then position else nil, tonumber(volume) or 1, tonumber(pitch) or 1)
			end
		elseif kind == "Anim" then
			local model, animKind, duration, side = args[1], args[2], args[3], args[4]
			if typeof(model) == "Instance" and model:IsA("Model") and type(animKind) == "string" then
				if RunService:IsStudio() then
					print(`[Fx] animacion {animKind} -> {model.Name}`) -- solo en Studio, para comprobar que llegan
				end
				playAnim(model, animKind, tonumber(duration) or 0, tonumber(side) or 1)
			end
		end
	end)

	RunService.RenderStepped:Connect(stepAnims)
	print("[Fx] FxController listo (sonidos y animaciones)")

	-- Ambiente de publico: solo en partido (no en el patio de juegos del lobby)
	MatchController.onChanged(function(inMatch: boolean)
		if not inMatch then
			setCrowd(false)
			return
		end
		task.wait(0.5) -- da tiempo a que llegue la carpeta del partido
		local folder = MatchController.getFolder()
		local playground = folder ~= nil and folder:GetAttribute("Mode") == "Playground"
		setCrowd(MatchController.isInMatch() and not playground)
	end)
end

return FxController
