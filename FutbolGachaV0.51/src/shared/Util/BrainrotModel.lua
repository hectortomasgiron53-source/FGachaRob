--!strict
--[[
	BrainrotModel: crea el modelo de un brainrot (granja, partidos, cajas).
	- Si existe ReplicatedStorage > BrainrotModels > <Id> (un Model que hayas metido tu, por ejemplo de la Toolbox),
	  se usa una copia: se le quitan los scripts, se escala a la altura pedida y se suelda a una pieza "Root".
	- Si no, se construye un muneco generico de colores (cuerpo, ojos, patas y un adorno). No representa al personaje:
	  es solo un marcador de sitio hasta que pongas su modelo.
	Evoluciones (nivel 50 y 90): el mismo brainrot, mas grande y con adornos nuevos (pinchos, hombreras, emblema y aura;
	despues alas, halo y destellos). Con un modelo propio "<Id>_Evo1" / "<Id>_Evo2" se usa ese en su lugar.
	El modelo devuelto tiene PrimaryPart = "Root" (invisible, en la base del modelo, mirando hacia -Z como Roblox).
	Todas las piezas: sin colisiones, sin masa, sin tocar. "Root" no esta anclada: el que lo usa decide.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)

local BrainrotModel = {}

local PALETTE = {
	Color3.fromRGB(240, 120, 90),
	Color3.fromRGB(110, 190, 120),
	Color3.fromRGB(90, 150, 230),
	Color3.fromRGB(240, 200, 80),
	Color3.fromRGB(200, 120, 220),
	Color3.fromRGB(90, 200, 200),
	Color3.fromRGB(230, 150, 60),
	Color3.fromRGB(170, 120, 90),
	Color3.fromRGB(150, 160, 175),
	Color3.fromRGB(240, 140, 170),
}

local function setupPart(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
end

local function newPart(model: Model, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	setupPart(p)
	p.Parent = model
	return p
end

-- Suelda todas las piezas del modelo a "root" con su sitio fijo (Weld con C0). Con WeldConstraint, si se movia solo
-- Root antes de meter el modelo en el mundo (partidos, brainrot robado sobre la cabeza), las demas piezas se quedaban
-- atras, en el centro del mapa, y el brainrot no se veia.
local function weldAll(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			setupPart(d)
			local weld = Instance.new("Weld")
			weld.Part0 = root
			weld.Part1 = d
			weld.C0 = root.CFrame:ToObjectSpace(d.CFrame)
			weld.Parent = root
		end
	end
end

local function shade(color: Color3, f: number): Color3
	return Color3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
end

-- Muneco generico (unos 4 studs de alto antes de escalar). Forma, color y adorno salen del Id.
local function buildGeneric(id: string, rarityId: string, variantId: string): Model
	local model = Instance.new("Model")
	local h = function(salt: string): number
		return EconomyMath.hash01(id .. salt)
	end
	local main = PALETTE[math.floor(h("color") * #PALETTE) + 1]
	local material = Enum.Material.SmoothPlastic
	if variantId == "Oro" then
		main = Color3.fromRGB(255, 196, 60)
		material = Enum.Material.Foil
	elseif variantId == "Diamante" then
		main = Color3.fromRGB(120, 225, 255)
		material = Enum.Material.Glass
	end
	local belly = shade(main, 1.25)
	local dark = shade(main, 0.6)
	local shapeKind = math.floor(h("shape") * 3) -- 0 bola, 1 bloque, 2 cilindro
	local accessory = math.floor(h("acc") * 4) -- 0 nada, 1 antena, 2 cuernos, 3 hoja

	-- Cuerpo
	local bodyCF = CFrame.new(0, 2.1, 0)
	local body: Part
	if shapeKind == 0 then
		body = newPart(model, "Body", Enum.PartType.Ball, Vector3.new(3.2, 3.2, 3.2), bodyCF, main, material)
	elseif shapeKind == 1 then
		body = newPart(model, "Body", Enum.PartType.Block, Vector3.new(2.8, 3, 2.4), bodyCF, main, material)
	else
		body = newPart(model, "Body", Enum.PartType.Cylinder, Vector3.new(3, 2.8, 2.8), bodyCF * CFrame.Angles(0, 0, math.rad(90)), main, material)
	end
	local front = if shapeKind == 1 then 1.2 elseif shapeKind == 2 then 1.4 else 1.45
	-- Barriga
	newPart(model, "Belly", Enum.PartType.Ball, Vector3.new(1.8, 1.8, 0.5), CFrame.new(0, 1.7, -front + 0.15), belly, material)
	-- Ojos (mirando hacia -Z)
	for _, side in { -1, 1 } do
		local eye = newPart(model, "Eye", Enum.PartType.Ball, Vector3.new(0.85, 0.85, 0.85), CFrame.new(side * 0.6, 2.75, -front + 0.05), Color3.new(1, 1, 1))
		eye.Material = Enum.Material.SmoothPlastic
		newPart(model, "Pupil", Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), CFrame.new(side * 0.6, 2.72, -front - 0.3), Color3.fromRGB(20, 20, 25))
	end
	-- Boca
	newPart(model, "Mouth", Enum.PartType.Block, Vector3.new(0.9, 0.18, 0.2), CFrame.new(0, 2.15, -front - 0.02), Color3.fromRGB(60, 25, 30))
	-- Patas y brazos
	for _, side in { -1, 1 } do
		newPart(model, "Foot", Enum.PartType.Ball, Vector3.new(1, 0.7, 1.3), CFrame.new(side * 0.8, 0.35, -0.2), dark, material)
		newPart(model, "Arm", Enum.PartType.Ball, Vector3.new(0.6, 0.6, 1.2), CFrame.new(side * 1.55, 1.9, -0.2) * CFrame.Angles(0, 0, side * 0.5), dark, material)
	end
	-- Adorno
	local top = if shapeKind == 0 then 3.7 else 3.6
	if accessory == 1 then
		newPart(model, "Antenna", Enum.PartType.Cylinder, Vector3.new(1, 0.15, 0.15), CFrame.new(0, top + 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), dark)
		newPart(model, "AntennaTip", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, top + 0.95, 0), belly, Enum.Material.Neon)
	elseif accessory == 2 then
		for _, side in { -1, 1 } do
			local horn = newPart(model, "Horn", Enum.PartType.Block, Vector3.new(0.35, 0.9, 0.35), CFrame.new(side * 0.8, top + 0.2, 0) * CFrame.Angles(0, 0, -side * 0.4), Color3.fromRGB(245, 235, 210))
			horn.Shape = Enum.PartType.Block
		end
	elseif accessory == 3 then
		newPart(model, "Leaf", Enum.PartType.Block, Vector3.new(0.2, 0.9, 1.4), CFrame.new(0, top + 0.35, 0.1) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(80, 170, 80), Enum.Material.Grass)
	end
	-- Calidad alta: corona (Secreto) o aro de luz (Legendario / Mitico)
	local rarity = Brainrots.RarityById[rarityId]
	local rarityIndex = Brainrots.RarityIndex[rarityId] or 1
	if rarityId == "Secreto" then
		newPart(model, "Crown", Enum.PartType.Cylinder, Vector3.new(0.6, 1.4, 1.4), CFrame.new(0, top + 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 200, 40), Enum.Material.Foil)
	end
	if rarityIndex >= 4 and rarity then
		local ring = newPart(model, "Aura", Enum.PartType.Cylinder, Vector3.new(0.1, 4.2, 4.2), CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), rarity.Color, Enum.Material.Neon)
		ring.Transparency = 0.35
		ring.CastShadow = false
	end
	-- Variante diamante: brillos
	if variantId == "Diamante" then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(180, 240, 255)
		sparkle.Parent = body
	end
	return model
end

-- Adornos de las evoluciones. Se colocan respecto a la caja que envuelve el modelo (sirven igual para el muneco
-- generico que para un modelo propio): el brainrot sigue siendo el mismo, pero se ve mas poderoso.
--   Evolucion 1: pinchos dorados en la cabeza, hombreras, emblema brillante en el pecho y aura en el suelo.
--   Evolucion 2: ademas, alas de luz a la espalda, halo dorado y destellos.
local GOLD = Color3.fromRGB(255, 200, 60)
local function addEvolution(model: Model, stage: number, color: Color3, cf: CFrame, size: Vector3)
	if stage <= 0 then
		return
	end
	local w, h, d = size.X, size.Y, size.Z
	local s = math.min(w, d)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- Evolucion 1
	for i = -1, 1 do
		local spike = newPart(model, "EvoSpike", Enum.PartType.Block, Vector3.new(s * 0.12, h * 0.2, s * 0.12),
			at(i * w * 0.22, h / 2 + h * 0.06, 0) * CFrame.Angles(0, math.rad(45), -i * 0.35), GOLD, Enum.Material.Foil)
		spike.CastShadow = false
	end
	for _, side in { -1, 1 } do
		newPart(model, "EvoShoulder", Enum.PartType.Ball, Vector3.new(s * 0.3, s * 0.22, s * 0.3), at(side * w * 0.47, h * 0.1, 0),
			shade(color, 0.8), Enum.Material.Metal)
	end
	newPart(model, "EvoEmblem", Enum.PartType.Ball, Vector3.new(s * 0.2, s * 0.2, s * 0.08), at(0, -h * 0.05, -d / 2 - 0.02),
		color, Enum.Material.Neon)
	local aura = newPart(model, "EvoAura", Enum.PartType.Cylinder, Vector3.new(0.08, math.max(w, d) * 0.7, math.max(w, d) * 0.7), -- (V1.16: un circulo pequeno bajo los pies; antes 1,45)
		at(0, -h / 2 + 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon)
	aura.Transparency = 0.45
	aura.CastShadow = false
	if stage < 2 then
		return
	end
	-- Evolucion 2
	for _, side in { -1, 1 } do
		local wing = newPart(model, "EvoWing", Enum.PartType.Block, Vector3.new(w * 0.6, h * 0.5, s * 0.05), -- (V1.15: antes 0,8 x 0,55)
			at(side * w * 0.5, h * 0.18, d * 0.45) * CFrame.Angles(0, side * math.rad(-28), side * math.rad(-18)), color, Enum.Material.Neon)
		wing.Transparency = 0.25
		wing.CastShadow = false
	end
	local halo = newPart(model, "EvoHalo", Enum.PartType.Cylinder, Vector3.new(0.12, w * 0.65, w * 0.65),
		at(0, h / 2 + h * 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Neon)
	halo.Transparency = 0.15
	halo.CastShadow = false
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(GOLD, color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Rate = 6
	sparkles.Speed = NumberRange.new(1, 2.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = halo
end

-- Copia de un modelo propio (ReplicatedStorage > BrainrotModels > <Id>), limpia de scripts.
-- Si hay uno especifico para la evolucion ("<Id>_Evo2", "<Id>_Evo1") se usa ese. Devuelve tambien si es especifico.
local function customModel(id: string, stage: number): (Model?, boolean)
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not folder or Brainrots.BannedModels[id] then
		return nil, false -- (prohibido: se usa el modelo generico)
	end
	local source: Instance? = nil
	local specific = false
	for s = stage, 1, -1 do
		local found = folder:FindFirstChild(`{id}_Evo{s}`)
		if found then
			source = found
			specific = true
			break
		end
	end
	if not source then
		source = folder:FindFirstChild(id)
	end
	if not source then
		return nil, false
	end
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		source:Clone().Parent = model
	else
		return nil, false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("Sound") or d:IsA("ClickDetector") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy() -- se vuelve a soldar todo a Root
		end
	end
	return model, specific
end

-- Caja (alineada con los ejes) de las piezas que SE VEN. El importador a veces anade una "RootPart" invisible mucho
-- mas grande que el modelo (p. ej. Gatto Melonino, que viene diminuto): con GetBoundingBox se mediria esa pieza y el
-- modelo se quedaria microscopico. Si no hay ninguna pieza visible, se deja la caja de siempre.
local function visibleBounds(model: Model, fallbackCf: CFrame, fallbackSize: Vector3): (CFrame, Vector3)
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	local found = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			found = true
			local half = d.Size / 2
			for _, corner in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
				Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) } do
				local p = d.CFrame:PointToWorldSpace(half * corner)
				minV = minV:Min(p)
				maxV = maxV:Max(p)
			end
		end
	end
	if not found then
		return fallbackCf, fallbackSize
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end

-- Crea el modelo listo para usar. "height" = altura final en studs.
-- "evolution": 0 (o nil) = normal, 1 = evolucion de nivel 50, 2 = de nivel 90 (ver Brainrots.Evolutions).
-- "growth": cuanto se aplica el aumento de tamano de la evolucion (1 = todo; 0 = mismo tamano, p. ej. en la interfaz).
function BrainrotModel.build(id: string, variantId: string?, height: number?, evolution: number?, growth: number?): Model
	local entry = EconomyMath.entryOf(id)
	local variant = variantId or "Normal"
	local stage = math.clamp(math.floor(evolution or 0), 0, #Brainrots.Evolutions)
	local custom, specific = customModel(id, stage)
	local model = custom or buildGeneric(id, entry.Rarity, variant)
	local sourceName = model.Name -- (el de la evolucion, p. ej. "ketupat_kepat_Evo2", puede tener su propio giro)
	model.Name = entry.Name
	if custom then
		-- Modelo propio: se gira para que mire hacia delante (Brainrots.ModelYaw; los de Sketchfab suelen mirar al
		-- reves) y su pivote queda recto, para que "alto" sea siempre el eje Y del mundo
		local yaw = Brainrots.ModelYaw[sourceName] or Brainrots.ModelYaw[id] or 0
		local pivot = model:GetPivot()
		model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, math.rad(yaw), 0) * pivot.Rotation)
		model.WorldPivot = CFrame.new(model:GetPivot().Position)
	end

	-- Raiz en la base del modelo, centrada (medida antes de los adornos de la evolucion: el cuerpo manda)
	local cf, size = model:GetBoundingBox()
	if custom then
		cf, size = visibleBounds(model, cf, size)
	end
	if stage > 0 and not specific then
		local rarity = Brainrots.RarityById[entry.Rarity] or Brainrots.Rarities[1]
		local color = if variant == "Oro" then GOLD elseif variant == "Diamante" then Color3.fromRGB(120, 225, 255) else rarity.Color
		addEvolution(model, stage, color, cf, size)
	end
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
	setupPart(root)
	root.Parent = model
	model.PrimaryPart = root

	-- Primero se escala (con las piezas sueltas) y despues se suelda todo a Root
	local wanted = height or (EconomyMath.rarityOf(id).Height :: number)
	if stage > 0 then
		wanted *= 1 + (Brainrots.Evolutions[stage].Scale - 1) * (growth or 1) -- evolucionado: mas grande
	end
	if size.Y > 0.01 then
		model:ScaleTo(model:GetScale() * wanted / size.Y)
	end
	weldAll(model, root)
	model:SetAttribute("BrainrotId", id)
	model:SetAttribute("Variant", variant)
	model:SetAttribute("Evolution", stage)
	return model
end

return BrainrotModel
