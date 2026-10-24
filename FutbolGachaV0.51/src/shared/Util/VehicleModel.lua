--!strict
--[[
	VehicleModel: crea el modelo de un vehiculo (Vehicles.lua) por codigo.
	El modelo devuelto tiene PrimaryPart = "Root" (invisible) en el CENTRO DE LA SUPERFICIE donde van los pies del
	jugador, mirando hacia -Z (como Roblox). El suelo queda a "Lift" studs por debajo de Root.
	Todas las piezas: sin colisiones, sin masa, sin tocar, soldadas a Root. Root no esta anclada: el que lo usa decide.
	Si existe ReplicatedStorage > VehicleModels > <Id> (un Model propio) se usa ese, colocado igual (su parte de
	arriba a la altura de los pies).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)

local VehicleModel = {}

local DARK = Color3.fromRGB(35, 35, 42)
local METAL = Color3.fromRGB(170, 175, 185)

local function setup(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
end

local function piece(model: Model, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	setup(p)
	p.Parent = model
	return p
end

local function block(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	return piece(model, name, Enum.PartType.Block, size, cf, color, material)
end

-- Rueda: cilindro con el eje a lo ancho (X), girando en el plano Y-Z
local function wheel(model: Model, position: Vector3, diameter: number, width: number, color: Color3?)
	piece(model, "Wheel", Enum.PartType.Cylinder, Vector3.new(width, diameter, diameter), CFrame.new(position), color or DARK)
	piece(model, "Hub", Enum.PartType.Cylinder, Vector3.new(width + 0.04, diameter * 0.45, diameter * 0.45), CFrame.new(position), METAL, Enum.Material.Metal)
end

local function glow(parent: BasePart, color: Color3, rate: number, direction: Enum.NormalId)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.EmissionDirection = direction
	emitter.Parent = parent
end

local function flame(parent: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 20))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.2, 0.35)
	emitter.Rate = 60
	emitter.Speed = NumberRange.new(8, 12)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Parent = parent
end

-- Formas. "lift" = altura de los pies sobre el suelo (el suelo esta en y = -lift).
local BUILDERS: { [string]: (Model, any) -> () } = {}

BUILDERS.Skate = function(model, v)
	local lift = v.Lift
	block(model, "Deck", Vector3.new(2.2, 0.25, 5.2), CFrame.new(0, -0.125, 0), v.Color, Enum.Material.Wood)
	block(model, "Grip", Vector3.new(2.1, 0.05, 5), CFrame.new(0, 0.02, 0), v.Accent, Enum.Material.Sand)
	for _, z in { -1.8, 1.8 } do
		block(model, "Truck", Vector3.new(1.6, 0.2, 0.4), CFrame.new(0, -0.35, z), METAL, Enum.Material.Metal)
		for _, x in { -0.8, 0.8 } do
			wheel(model, Vector3.new(x, -lift + 0.3, z), 0.6, 0.35, Color3.fromRGB(240, 240, 240))
		end
	end
end

BUILDERS.Scooter = function(model, v)
	local lift = v.Lift
	block(model, "Deck", Vector3.new(1.8, 0.25, 4.4), CFrame.new(0, -0.125, 0.3), v.Color, Enum.Material.Metal)
	wheel(model, Vector3.new(0, -lift + 0.45, -2.1), 0.9, 0.4)
	wheel(model, Vector3.new(0, -lift + 0.45, 2.4), 0.9, 0.4)
	block(model, "Stem", Vector3.new(0.3, 3.6, 0.3), CFrame.new(0, 1.55, -2.0) * CFrame.Angles(math.rad(-8), 0, 0), METAL, Enum.Material.Metal)
	block(model, "Handlebar", Vector3.new(2.2, 0.25, 0.25), CFrame.new(0, 3.3, -2.25), v.Accent)
	block(model, "Light", Vector3.new(0.6, 0.3, 0.1), CFrame.new(0, 2.6, -2.25), Color3.fromRGB(255, 250, 200), Enum.Material.Neon)
end

BUILDERS.Bike = function(model, v)
	local lift = v.Lift
	local r = 1.1
	local wheelY = -lift + r
	wheel(model, Vector3.new(0, wheelY, -2.1), r * 2, 0.25)
	wheel(model, Vector3.new(0, wheelY, 2.1), r * 2, 0.25)
	-- Plataforma de los pedales (donde va de pie), cuadro y manillar
	block(model, "Pedals", Vector3.new(1.8, 0.2, 1.4), CFrame.new(0, -0.1, 0), DARK)
	block(model, "Frame", Vector3.new(0.3, 0.3, 4.2), CFrame.new(0, wheelY + 0.4, 0), v.Color, Enum.Material.Metal)
	block(model, "Fork", Vector3.new(0.25, 3, 0.25), CFrame.new(0, wheelY + 1.3, -2.1), v.Color, Enum.Material.Metal)
	block(model, "Handlebar", Vector3.new(2.4, 0.25, 0.25), CFrame.new(0, wheelY + 2.8, -2.1), v.Accent)
	block(model, "Seat", Vector3.new(0.8, 0.3, 1.2), CFrame.new(0, 0.9, 1.9), DARK)
	if v.Trail then
		block(model, "NeonStrip", Vector3.new(0.35, 0.12, 4.2), CFrame.new(0, wheelY + 0.62, 0), v.Accent, Enum.Material.Neon)
	end
end

BUILDERS.Hover = function(model, v)
	block(model, "Board", Vector3.new(2.6, 0.35, 5.6), CFrame.new(0, -0.175, 0), v.Color, Enum.Material.Metal)
	block(model, "Stripe", Vector3.new(0.5, 0.05, 5.4), CFrame.new(0, 0.02, 0), v.Accent, Enum.Material.Neon)
	block(model, "Underglow", Vector3.new(2.2, 0.1, 5), CFrame.new(0, -0.4, 0), v.Accent, Enum.Material.Neon)
	for _, z in { -1.9, 1.9 } do
		local thruster = piece(model, "Thruster", Enum.PartType.Ball, Vector3.new(0.9, 0.5, 0.9), CFrame.new(0, -0.5, z), v.Accent, Enum.Material.Neon)
		glow(thruster, v.Accent, 25, Enum.NormalId.Bottom)
	end
end

BUILDERS.Moto = function(model, v)
	local lift = v.Lift
	block(model, "Body", Vector3.new(1.3, 1.1, 4.4), CFrame.new(0, -0.6, 0.2), v.Color, Enum.Material.Metal)
	block(model, "Footrest", Vector3.new(2, 0.2, 1.2), CFrame.new(0, -0.1, 0.3), DARK)
	block(model, "Tank", Vector3.new(1.1, 0.7, 1.6), CFrame.new(0, 0.3, -1.1), v.Accent, Enum.Material.Metal)
	block(model, "Handlebar", Vector3.new(2.6, 0.25, 0.25), CFrame.new(0, 1.9, -1.9), DARK)
	block(model, "Stem", Vector3.new(0.3, 2.2, 0.3), CFrame.new(0, 0.8, -1.9), METAL, Enum.Material.Metal)
	block(model, "Light", Vector3.new(0.8, 0.5, 0.1), CFrame.new(0, 0.6, -2.15), Color3.fromRGB(255, 250, 210), Enum.Material.Neon)
	if v.Trail then
		-- Moto voladora: anillos de luz en lugar de ruedas
		for _, z in { -1.9, 2.1 } do
			local ring = piece(model, "HoverRing", Enum.PartType.Cylinder, Vector3.new(0.25, 1.8, 1.8), CFrame.new(0, -1.5, z) * CFrame.Angles(0, 0, math.rad(90)), v.Accent, Enum.Material.Neon)
			glow(ring, v.Accent, 20, Enum.NormalId.Left)
		end
	else
		local r = 1
		wheel(model, Vector3.new(0, -lift + r, -1.9), r * 2, 0.6)
		wheel(model, Vector3.new(0, -lift + r, 2.1), r * 2, 0.6)
	end
end

BUILDERS.Carpet = function(model, v)
	block(model, "Carpet", Vector3.new(3.2, 0.15, 5.8), CFrame.new(0, -0.075, 0), v.Color, Enum.Material.Fabric)
	for _, x in { -1.45, 1.45 } do
		block(model, "Border", Vector3.new(0.25, 0.17, 5.8), CFrame.new(x, -0.07, 0), v.Accent, Enum.Material.Fabric)
	end
	block(model, "Pattern", Vector3.new(1.4, 0.17, 1.4), CFrame.new(0, -0.07, 0) * CFrame.Angles(0, math.rad(45), 0), v.Accent, Enum.Material.Fabric)
	for _, x in { -1.5, 1.5 } do
		for _, z in { -2.9, 2.9 } do
			piece(model, "Tassel", Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(x, -0.15, z), v.Accent)
		end
	end
	local sparkle = block(model, "Magic", Vector3.new(2.8, 0.05, 5.4), CFrame.new(0, -0.2, 0), v.Accent, Enum.Material.Neon)
	sparkle.Transparency = 0.6
	glow(sparkle, v.Accent, 12, Enum.NormalId.Bottom)
end

BUILDERS.Rocket = function(model, v)
	block(model, "Board", Vector3.new(2.4, 0.3, 5.6), CFrame.new(0, -0.15, 0), v.Color, Enum.Material.Metal)
	block(model, "Stripe", Vector3.new(0.4, 0.05, 5.4), CFrame.new(0, 0.02, 0), v.Accent, Enum.Material.Neon)
	-- Cohete debajo (a lo largo de la tabla) con fuego detras
	piece(model, "Rocket", Enum.PartType.Cylinder, Vector3.new(4.6, 1.1, 1.1), CFrame.new(0, -0.85, 0.3) * CFrame.Angles(0, math.rad(90), 0), METAL, Enum.Material.Metal)
	piece(model, "Nose", Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, -0.85, -2.0), v.Accent)
	local nozzle = block(model, "Nozzle", Vector3.new(0.9, 0.9, 0.3), CFrame.new(0, -0.85, 2.7), v.Accent, Enum.Material.Neon)
	flame(nozzle)
end

-- Estela de luz (vehiculos de gemas): entre dos puntos de la parte de atras
local function addTrail(model: Model, root: BasePart, v: any, size: Vector3)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-size.X * 0.35, -0.3, size.Z * 0.45)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(size.X * 0.35, -0.3, size.Z * 0.45)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(v.Accent, v.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.45
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = root
	model:SetAttribute("Trail", true)
end

-- Copia de un modelo propio (ReplicatedStorage > VehicleModels > <Id>), limpia de scripts
local function customModel(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VehicleModels")
	local source = if folder then folder:FindFirstChild(id) else nil
	if not source or not source:IsA("Model") then
		return nil
	end
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("Sound") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	-- Su parte de arriba a la altura de los pies (y = 0), centrado
	local cf, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-cf.Position.X, -(cf.Position.Y + size.Y / 2), -cf.Position.Z) * model:GetPivot())
	return model
end

function VehicleModel.build(id: string): Model?
	local v = Vehicles.ById[id]
	if not v then
		return nil
	end
	local model = customModel(id)
	if not model then
		local generic = Instance.new("Model")
		local builder = BUILDERS[v.Kind] or BUILDERS.Skate
		builder(generic, v)
		model = generic
	end
	local m = model :: Model
	m.Name = v.Name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 0, 0)
	setup(root)
	root.Parent = m
	m.PrimaryPart = root
	local _, size = m:GetBoundingBox()
	-- Weld con offset fijo (C0): un WeldConstraint creado fuera del Workspace no arrastra las piezas al mover Root,
	-- y el vehiculo aparecia lejos (en el origen del mapa) en vez de bajo los pies
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			setup(d)
			local weld = Instance.new("Weld")
			weld.Part0 = root
			weld.Part1 = d
			weld.C0 = root.CFrame:ToObjectSpace(d.CFrame)
			weld.Parent = root
		end
	end
	if v.Trail then
		addTrail(m, root, v, size)
	end
	m:SetAttribute("VehicleId", id)
	return m
end

return VehicleModel
