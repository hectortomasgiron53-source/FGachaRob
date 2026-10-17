--!strict
--[[
	ArenaBuilder: construye el campo por codigo (no hace falta modelarlo a mano).
	Coordenadas locales: origen en el centro del campo, la cara superior del suelo en Y = 0,
	el largo en el eje X y el ancho en el eje Z. El equipo 1 ataca hacia +X.
	Las medidas salen de Balance.Field.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Balance = require(ReplicatedStorage.Shared.Config.Balance)

local ArenaBuilder = {}

local FLOOR_PHYSICS = PhysicalProperties.new(2, 0.35, 0.4, 10, 1)
local WALL_PHYSICS = PhysicalProperties.new(2, 0.05, 0.7, 1, 10)

local GRASS = Color3.fromRGB(67, 140, 70)
local WALL = Color3.fromRGB(225, 228, 235)
local GOAL = Color3.fromRGB(255, 200, 60)
local LINE = Color3.fromRGB(255, 255, 255)

local function addPart(
	model: Model,
	origin: CFrame,
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	physics: PhysicalProperties?,
	transparency: number?,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = origin * localCFrame
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = transparency or 0
	part.CanCollide = canCollide ~= false
	if physics then
		part.CustomPhysicalProperties = physics
	end
	part.Parent = model
	return part
end

function ArenaBuilder.build(origin: CFrame): Model
	local F = Balance.Field
	local halfL, halfW = F.Length / 2, F.Width / 2
	local T, H = F.WallThickness, F.WallHeight
	local GW, GH, GD = F.GoalWidth, F.GoalHeight, F.GoalDepth

	local model = Instance.new("Model")
	model.Name = "Arena"

	-- Suelo (incluye el fondo de las dos porterias) y linea central
	addPart(
		model,
		origin,
		"Floor",
		Vector3.new(F.Length + 2 * GD + 2 * T, 1, F.Width + 2 * T),
		CFrame.new(0, -0.5, 0),
		GRASS,
		FLOOR_PHYSICS
	)
	addPart(model, origin, "CenterLine", Vector3.new(0.4, 0.1, F.Width), CFrame.new(0, 0.05, 0), LINE, nil, 0, false)

	-- Muros laterales
	for _, sz in { -1, 1 } do
		addPart(
			model,
			origin,
			"SideWall",
			Vector3.new(F.Length + 2 * T, H, T),
			CFrame.new(0, H / 2, sz * (halfW + T / 2)),
			WALL,
			WALL_PHYSICS,
			0.35
		)
	end

	-- Muros de fondo (con hueco para la porteria), travesano y caja de la porteria
	local segLen = halfW - GW / 2 + T
	for _, sx in { -1, 1 } do
		local wallX = sx * (halfL + T / 2)
		for _, sz in { -1, 1 } do
			addPart(
				model,
				origin,
				"EndWall",
				Vector3.new(T, H, segLen),
				CFrame.new(wallX, H / 2, sz * (GW / 2 + segLen / 2)),
				WALL,
				WALL_PHYSICS,
				0.35
			)
		end
		addPart(
			model,
			origin,
			"Crossbar",
			Vector3.new(T, H - GH, GW),
			CFrame.new(wallX, GH + (H - GH) / 2, 0),
			WALL,
			WALL_PHYSICS,
			0.35
		)
		addPart(
			model,
			origin,
			"GoalBack",
			Vector3.new(T, GH + T, GW + 2 * T),
			CFrame.new(sx * (halfL + GD + T / 2), (GH + T) / 2, 0),
			GOAL,
			WALL_PHYSICS,
			0.3
		)
		addPart(
			model,
			origin,
			"GoalRoof",
			Vector3.new(GD, T, GW),
			CFrame.new(sx * (halfL + GD / 2), GH + T / 2, 0),
			GOAL,
			WALL_PHYSICS,
			0.3
		)
		for _, sz in { -1, 1 } do
			addPart(
				model,
				origin,
				"GoalSide",
				Vector3.new(GD, GH + T, T),
				CFrame.new(sx * (halfL + GD / 2), (GH + T) / 2, sz * (GW / 2 + T / 2)),
				GOAL,
				WALL_PHYSICS,
				0.3
			)
		end
	end

	-- Esquinas cortadas a 45 grados (el balon no se atasca en un angulo recto)
	local c = F.CornerSize
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = Vector3.new(sx * (halfL - c), 0, sz * halfW)
			local b = Vector3.new(sx * halfL, 0, sz * (halfW - c))
			local outward = Vector3.new(sx, 0, sz).Unit * (T / 2)
			local mid = (a + b) / 2 + outward + Vector3.new(0, H / 2, 0)
			addPart(
				model,
				origin,
				"Corner",
				Vector3.new(T, H, (b - a).Magnitude),
				CFrame.lookAt(mid, mid + (b - a)),
				WALL,
				WALL_PHYSICS,
				0.35
			)
		end
	end

	-- Techo invisible para que el balon nunca salga volando
	addPart(
		model,
		origin,
		"Ceiling",
		Vector3.new(F.Length + 2 * GD + 2 * T, T, F.Width + 2 * T),
		CFrame.new(0, H + T / 2, 0),
		WALL,
		WALL_PHYSICS,
		1
	)

	return model
end

return ArenaBuilder
