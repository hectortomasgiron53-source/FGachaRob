--!strict
--[[
	BrainrotModel: crea el modelo de un brainrot (granja, partidos, cajas).
	- Si existe ReplicatedStorage > BrainrotModels > <Id> (un Model que hayas metido tu, por ejemplo de la Toolbox),
	  se usa una copia: se le quitan los scripts, se escala a la altura pedida y se suelda a una pieza "Root".
	- Si no, se construye un muneco generico de colores (cuerpo, ojos, patas y un adorno). No representa al personaje:
	  es solo un marcador de sitio hasta que pongas su modelo.
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

-- Suelda todas las piezas del modelo a "root"
local function weldAll(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			setupPart(d)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
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

-- Copia de un modelo propio (ReplicatedStorage > BrainrotModels > <Id>), limpia de scripts
local function customModel(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local source = if folder then folder:FindFirstChild(id) else nil
	if not source then
		return nil
	end
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		source:Clone().Parent = model
	else
		return nil
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
	return model
end

-- Crea el modelo listo para usar. "height" = altura final en studs.
function BrainrotModel.build(id: string, variantId: string?, height: number?): Model
	local entry = EconomyMath.entryOf(id)
	local variant = variantId or "Normal"
	local model = customModel(id) or buildGeneric(id, entry.Rarity, variant)
	model.Name = entry.Name

	-- Raiz en la base del modelo, centrada
	local cf, size = model:GetBoundingBox()
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
	if size.Y > 0.01 then
		model:ScaleTo(model:GetScale() * wanted / size.Y)
	end
	weldAll(model, root)
	model:SetAttribute("BrainrotId", id)
	model:SetAttribute("Variant", variant)
	return model
end

return BrainrotModel
