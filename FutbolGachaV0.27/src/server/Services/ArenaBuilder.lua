--!strict
--[[
	ArenaBuilder: construye el campo por codigo (no hace falta modelarlo a mano).
	Coordenadas locales: origen en el centro del campo, la cara superior del suelo en Y = 0,
	el largo en el eje X y el ancho en el eje Z. El equipo 1 ataca hacia +X.
	Las medidas salen de Balance.Field.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local CollisionSetup = require(script.Parent.CollisionSetup)

local ArenaBuilder = {}

local FLOOR_PHYSICS = PhysicalProperties.new(2, 0.35, 0.4, 10, 1)
local WALL_PHYSICS = PhysicalProperties.new(2, 0.05, 0.7, 1, 10)

local GRASS = Color3.fromRGB(67, 140, 70)
local WALL = Color3.fromRGB(225, 228, 235)
local GOAL = Color3.fromRGB(255, 200, 60)
local LINE = Color3.fromRGB(255, 255, 255)
local NET_COLOR = Color3.fromRGB(236, 240, 244)
local BOARD = Color3.fromRGB(70, 82, 104)
-- La red no rebota: el balon que la toca cae casi sin rebote
local NET_PHYSICS = PhysicalProperties.new(1, 0.9, 0, 10, 100)

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


-- Linea pintada sobre el suelo (no choca, no la ve ni el raycast). from/to en coordenadas locales (X, Z).

-- Cuadricula de hilos (la "red"): hilos finos verticales y horizontales sobre el plano de "cf"
-- (X local = ancho, Y local = alto). No chocan: la colision la pone el panel transparente de detras.
local function addNetLines(model: Model, origin: CFrame, cf: CFrame, width: number, height: number, spacing: number)
	local cols = math.max(1, math.round(width / spacing))
	local rows = math.max(1, math.round(height / spacing))
	for i = 0, cols do
		local x = -width / 2 + width * i / cols
		local strand = addPart(model, origin, "NetStrand", Vector3.new(0.12, height, 0.12), cf * CFrame.new(x, 0, 0), NET_COLOR, nil, 0.25, false)
		strand.CanQuery = false
		strand.CanTouch = false
		strand.CastShadow = false
	end
	for j = 0, rows do
		local y = -height / 2 + height * j / rows
		local strand = addPart(model, origin, "NetStrand", Vector3.new(width, 0.12, 0.12), cf * CFrame.new(0, y, 0), NET_COLOR, nil, 0.25, false)
		strand.CanQuery = false
		strand.CanTouch = false
		strand.CastShadow = false
	end
end

-- Cerramiento: muro bajo solido (boardH) + red hasta netTop. a y b: extremos de la base (X, Z locales, Y = 0).
-- Para un tramo sin muro bajo (travesano sobre la porteria) boardH = 0 y netBottom = altura donde empieza la red.
local function addBarrier(model: Model, origin: CFrame, name: string, a: Vector3, b: Vector3, boardH: number, netBottom: number, netTop: number)
	local T = Balance.Field.WallThickness
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.01 then
		return
	end
	local dir = delta.Unit
	local mid = (a + b) / 2
	local function basis(y: number): CFrame
		return CFrame.fromMatrix(mid + Vector3.new(0, y, 0), dir, Vector3.yAxis)
	end
	if boardH > 0 then
		addPart(model, origin, name .. "Board", Vector3.new(length, boardH, T), basis(boardH / 2), BOARD, WALL_PHYSICS)
	end
	local netH = netTop - netBottom
	if netH > 0 then
		local cf = basis(netBottom + netH / 2)
		addPart(model, origin, name .. "Net", Vector3.new(length, netH, T), cf, NET_COLOR, NET_PHYSICS, 0.9, true)
		addNetLines(model, origin, cf, length, netH, 4)
	end
end

local addMarkings: (Model, CFrame) -> ()

local function addLine(model: Model, origin: CFrame, name: string, a: Vector2, b: Vector2, width: number, color: Color3?, lift: number?)
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.01 then
		return
	end
	local mid = (a + b) / 2
	local part = addPart(
		model,
		origin,
		name,
		Vector3.new(width, 0.1, length),
		CFrame.lookAt(Vector3.new(mid.X, 0.05 + (lift or 0), mid.Y), Vector3.new(b.X, 0.05 + (lift or 0), b.Y)),
		color or LINE,
		nil,
		0,
		false
	)
	part.CanQuery = false
	part.CanTouch = false
end

-- Marcas del campo. Las lineas de banda y de gol van DENTRO del campo, pegadas al muro: su borde exterior es
-- exactamente X = +-Length/2 y Z = +-Width/2. Es gol cuando el balon entero ha pasado ese borde (ver Match._checkGoal).
addMarkings = function(model: Model, origin: CFrame)
	local F = Balance.Field
	local halfL, halfW = F.Length / 2, F.Width / 2
	local lw = F.LineWidth
	local inL, inW = halfL - lw / 2, halfW - lw / 2 -- centro de las lineas del borde

	-- Bandas (a lo largo de X) y lineas de fondo/gol (a lo largo de Z), con las esquinas cortadas
	local c = F.CornerSize
	for _, sz in { -1, 1 } do
		addLine(model, origin, "Touchline", Vector2.new(-(halfL - c), sz * inW), Vector2.new(halfL - c, sz * inW), lw)
	end
	for _, sx in { -1, 1 } do
		addLine(model, origin, "GoalLine", Vector2.new(sx * inL, -(halfW - c)), Vector2.new(sx * inL, halfW - c), lw)
		for _, sz in { -1, 1 } do
			-- esquina cortada a 45 grados
			addLine(
				model,
				origin,
				"CornerLine",
				Vector2.new(sx * (halfL - c), sz * inW),
				Vector2.new(sx * inL, sz * (halfW - c)),
				lw
			)
		end
		-- Boca de la porteria: marca mas gruesa y dorada sobre la linea de gol, solo entre los palos
		addLine(
			model,
			origin,
			"GoalMouth",
			Vector2.new(sx * (halfL - lw * 0.8), -F.GoalWidth / 2), -- su borde exterior tambien acaba en X = +-Length/2
			Vector2.new(sx * (halfL - lw * 0.8), F.GoalWidth / 2),
			lw * 1.6,
			GOAL,
			0.03 -- por encima de la linea de gol blanca (si estan al mismo nivel, parpadean)
		)

		-- Area grande y area pequena (rectangulos abiertos hacia la linea de gol)
		for _, box in {
			{ F.PenaltyDepth, F.PenaltyWidth / 2 },
			{ F.SixYardDepth, F.SixYardWidth / 2 },
		} do
			local x = sx * (halfL - box[1])
			local z = box[2]
			addLine(model, origin, "AreaFront", Vector2.new(x, -z), Vector2.new(x, z), lw)
			for _, sz in { -1, 1 } do
				addLine(model, origin, "AreaSide", Vector2.new(x, sz * z), Vector2.new(sx * inL, sz * z), lw)
			end
		end
	end

	-- Linea central, circulo central y punto de saque
	addLine(model, origin, "CenterLine", Vector2.new(0, -inW), Vector2.new(0, inW), lw)
	local radius = F.CenterCircleRadius
	local segments = 36
	for i = 1, segments do
		local a0 = (i - 1) / segments * math.pi * 2
		local a1 = i / segments * math.pi * 2
		addLine(
			model,
			origin,
			"CenterCircle",
			Vector2.new(math.cos(a0) * radius, math.sin(a0) * radius),
			Vector2.new(math.cos(a1) * radius, math.sin(a1) * radius),
			lw * 1.05, -- un pelin mas ancho para que los tramos no dejen huecos en las uniones
			nil,
			if i % 2 == 0 then 0.01 else 0 -- tramos alternos a distinta altura: donde se solapan no parpadean
		)
	end
	local spot = addPart(model, origin, "CenterSpot", Vector3.new(1.4, 0.1, 1.4), CFrame.new(0, 0.08, 0), LINE, nil, 0, false)
	spot.CanQuery = false
end

-- options.Gate = true abre una puerta (ancho Field.GateWidth) en el muro lateral +Z, por donde se puede entrar al campo.
function ArenaBuilder.build(origin: CFrame, options: { Gate: boolean? }?): Model
	local F = Balance.Field
	local halfL, halfW = F.Length / 2, F.Width / 2
	local T, H = F.WallThickness, F.WallHeight
	local GW, GH, GD = F.GoalWidth, F.GoalHeight, F.GoalDepth

	local model = Instance.new("Model")
	model.Name = "Arena"

	-- Suelo en 3 piezas (el campo no tiene esquinas rectas: van cortadas en diagonal)
	local c = F.CornerSize
	local floorHalfL = halfL + GD + T
	addPart(model, origin, "Floor", Vector3.new(2 * floorHalfL, 1, 2 * (halfW - c)), CFrame.new(0, -0.5, 0), GRASS, FLOOR_PHYSICS)
	-- Las bandas laterales NO se solapan con la central (dos caras al mismo nivel parpadean: z-fighting)
	for _, sz in { -1, 1 } do
		local inner, outer = halfW - c, halfW + T
		addPart(
			model,
			origin,
			"Floor",
			Vector3.new(2 * (halfL - c), 1, outer - inner),
			CFrame.new(0, -0.5, sz * (inner + outer) / 2),
			GRASS,
			FLOOR_PHYSICS
		)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- Rectangulo apoyado en la diagonal que rellena el triangulo de la esquina cortada
			local a = Vector3.new(sx * (halfL - c), 0, sz * halfW)
			local b = Vector3.new(sx * halfL, 0, sz * (halfW - c))
			local inward = -Vector3.new(sx, 0, sz).Unit
			local depth = c / math.sqrt(2)
			local center = (a + b) / 2 + inward * ((depth - T) / 2) + Vector3.new(0, -0.53, 0) -- 3 centesimas por debajo: sin parpadeo donde se solapa
			addPart(
				model,
				origin,
				"Floor",
				Vector3.new(depth + T, 1, (b - a).Magnitude),
				CFrame.lookAt(center, center + (b - a)),
				GRASS,
				FLOOR_PHYSICS
			)
		end
	end
	addMarkings(model, origin)

	local BH = F.BoardHeight

	-- Muros laterales (llegan solo hasta donde empieza la esquina diagonal): muro bajo (rebota) + red hasta arriba
	local sideReach = halfL - c + T
	local gate = options ~= nil and options.Gate == true
	for _, sz in { -1, 1 } do
		local z = sz * (halfW + T / 2)
		if gate and sz == 1 then
			local half = F.GateWidth / 2
			addBarrier(model, origin, "SideWall", Vector3.new(-sideReach, 0, z), Vector3.new(-half, 0, z), BH, BH, H)
			addBarrier(model, origin, "SideWall", Vector3.new(half, 0, z), Vector3.new(sideReach, 0, z), BH, BH, H)
			-- Las 3 filas de cuadros de arriba cruzan la puerta: la red es continua por encima de la entrada
			local rowH = (H - BH) / math.max(1, math.round((H - BH) / 4))
			addBarrier(model, origin, "GateTopNet", Vector3.new(-half, 0, z), Vector3.new(half, 0, z), 0, H - 3 * rowH, H)
			-- Barrera invisible solo para el balon: los jugadores pasan por la puerta, el balon no
			local barrier = addPart(
				model,
				origin,
				"GateBallBarrier",
				Vector3.new(F.GateWidth, H - 3 * rowH, T),
				CFrame.new(0, (H - 3 * rowH) / 2, z),
				NET_COLOR,
				NET_PHYSICS,
				1
			)
			barrier.CanQuery = false
			CollisionSetup.setup()
			barrier.CollisionGroup = CollisionSetup.BALL_ONLY
		else
			addBarrier(model, origin, "SideWall", Vector3.new(-sideReach, 0, z), Vector3.new(sideReach, 0, z), BH, BH, H)
		end
	end

	for _, sx in { -1, 1 } do
		-- Muros de fondo a los lados de la porteria y red sobre ella (en lugar del travesano macizo)
		local wallX = sx * (halfL + T / 2)
		for _, sz in { -1, 1 } do
			addBarrier(model, origin, "EndWall", Vector3.new(wallX, 0, sz * GW / 2), Vector3.new(wallX, 0, sz * (halfW - c + T / 2)), BH, BH, H)
		end
		addBarrier(model, origin, "Crossbar", Vector3.new(wallX, 0, -GW / 2), Vector3.new(wallX, 0, GW / 2), 0, GH, H)

		-- Porteria de red: fondo, laterales y techo. Colision invisible + hilos. No rebotan.
		addPart(model, origin, "GoalBackNet", Vector3.new(T, GH + T, GW + 2 * T), CFrame.new(sx * (halfL + GD + T / 2), (GH + T) / 2, 0), NET_COLOR, NET_PHYSICS, 0.9)
		addNetLines(model, origin, CFrame.new(sx * (halfL + GD), GH / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), GW, GH, 1.5)
		addPart(model, origin, "GoalRoofNet", Vector3.new(GD, T, GW), CFrame.new(sx * (halfL + GD / 2), GH + T / 2, 0), NET_COLOR, NET_PHYSICS, 0.9)
		addNetLines(model, origin, CFrame.new(sx * (halfL + GD / 2), GH, 0) * CFrame.Angles(math.pi / 2, 0, 0), GD, GW, 1.5)
		for _, sz in { -1, 1 } do
			addPart(model, origin, "GoalSideNet", Vector3.new(GD, GH + T, T), CFrame.new(sx * (halfL + GD / 2), (GH + T) / 2, sz * (GW / 2 + T / 2)), NET_COLOR, NET_PHYSICS, 0.9)
			addNetLines(model, origin, CFrame.new(sx * (halfL + GD / 2), GH / 2, sz * GW / 2), GD, GH, 1.5)

			-- Palo (solo visual)
			local post = addPart(model, origin, "Post", Vector3.new(0.6, GH, 0.6), CFrame.new(sx * halfL, GH / 2, sz * GW / 2), LINE, nil, 0, false)
			post.CanQuery = false
		end
		local bar = addPart(model, origin, "CrossbarRod", Vector3.new(0.6, 0.6, GW + 0.6), CFrame.new(sx * halfL, GH, 0), LINE, nil, 0, false)
		bar.CanQuery = false
	end

	-- Esquinas cortadas a 45 grados (el balon no se atasca en un angulo recto)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = Vector3.new(sx * (halfL - c), 0, sz * halfW)
			local b = Vector3.new(sx * halfL, 0, sz * (halfW - c))
			local outward = Vector3.new(sx, 0, sz).Unit * (T / 2)
			addBarrier(model, origin, "Corner", a + outward, b + outward, BH, BH, H)
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
