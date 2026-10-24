--!strict
--[[
	UiKit: piezas de interfaz comunes (colores, botones, ventanas, iconos, losetas de menu, tarjetas de brainrot con su
	modelo en 3D). No es un controlador: lo usan EconomyController, sus paneles y el resto de pantallas.

	Estilo (V0.73, "simulador"): colores vivos con degradado, bordes gruesos azul oscuro, esquinas redondeadas, letra
	redondeada (FredokaOne) blanca con contorno, iconos grandes y botones que se hunden al pulsarlos.
	UiKit.theme(PlayerGui) aplica la letra y el contorno a TODO texto de nuestras pantallas (tambien a las que no usan
	UiKit), asi todo el juego se ve igual.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BrainrotModel = require(ReplicatedStorage.Shared.Util.BrainrotModel)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)

local UiKit = {}

UiKit.Font = Enum.Font.FredokaOne

UiKit.Colors = {
	Ink = Color3.fromRGB(20, 32, 78), -- contorno de todo (bordes y letras)
	Back = Color3.fromRGB(42, 96, 205), -- fondos de avisos, paneles y barras
	Panel = Color3.fromRGB(58, 122, 226),
	Panel2 = Color3.fromRGB(92, 152, 240),
	WindowTop = Color3.fromRGB(128, 196, 255), -- ventanas: azul claro arriba...
	WindowBottom = Color3.fromRGB(76, 146, 238), -- ...y algo mas oscuro abajo
	Line = Color3.fromRGB(20, 32, 78),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(222, 236, 255),
	Coins = Color3.fromRGB(255, 205, 45),
	Gems = Color3.fromRGB(110, 205, 255), -- azul diamante
	Green = Color3.fromRGB(70, 205, 75),
	Red = Color3.fromRGB(232, 64, 64),
	Blue = Color3.fromRGB(40, 125, 240),
	Purple = Color3.fromRGB(150, 85, 245),
	Orange = Color3.fromRGB(250, 145, 40),
	Yellow = Color3.fromRGB(255, 200, 40),
	Teal = Color3.fromRGB(40, 185, 170),
	Chip = Color3.fromRGB(28, 40, 86), -- recuadros oscuros de monedas y gemas dentro de las ventanas
}
local Colors = UiKit.Colors

function UiKit.make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end
local make = UiKit.make

function UiKit.corner(parent: Instance, radius: number?)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, parent)
end

function UiKit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	make("UIStroke", {
		Color = color or Colors.Ink,
		Thickness = thickness or 2.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

-- Degradado vertical: arriba el color tal cual y abajo algo mas oscuro (da "volumen" a botones y paneles)
function UiKit.gradient(parent: Instance, bottom: number?)
	local b = bottom or 0.78
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(b, b, b)),
		Rotation = 90,
	}, parent)
end

function UiKit.padding(parent: Instance, px: number)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	}, parent)
end

-- Contorno de las letras (texto claro sobre fondos de color: siempre se lee)
local function textStroke(label: Instance, thickness: number?)
	if label:FindFirstChildOfClass("UIStroke") then
		return
	end
	make("UIStroke", {
		Color = Colors.Ink,
		Thickness = thickness or 1.8,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end
UiKit.textStroke = textStroke

function UiKit.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiKit.Font,
		TextColor3 = Colors.Text,
		TextScaled = true,
		Text = text,
	}, parent)
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

-- Icono hecho con un emoji (grande y de colores, como los de los juegos tipo simulador)
function UiKit.emoji(parent: Instance, emoji: string, props: { [string]: any }?): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiKit.Font,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = emoji,
	}, parent)
	label:SetAttribute("NoStroke", true)
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

-- Al pulsar, el boton se hunde un poco y rebota (se nota que lo has pulsado)
local function pressEffect(button: GuiButton)
	local scale = make("UIScale", { Name = "Press" }, button)
	local down = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local up = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			TweenService:Create(scale, down, { Scale = 0.92 }):Play()
		end
	end)
	local function release()
		TweenService:Create(scale, up, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

-- Boton: color vivo con degradado, borde grueso oscuro, letra blanca con contorno y efecto al pulsar
function UiKit.button(parent: Instance, text: string, color: Color3, props: { [string]: any }?): TextButton
	local button = make("TextButton", {
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = UiKit.Font,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = Colors.Ink,
		TextStrokeTransparency = 0,
		TextScaled = true,
		Text = text,
	}, parent)
	UiKit.corner(button, 10)
	UiKit.stroke(button, Colors.Ink, 3)
	UiKit.gradient(button)
	make("UITextSizeConstraint", { MaxTextSize = 24 }, button)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, button)
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	local base = button.BackgroundColor3
	local hover = false
	button.MouseEnter:Connect(function()
		if button.Active then
			hover = true
			button.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.18)
		end
	end)
	button.MouseLeave:Connect(function()
		hover = false
		button.BackgroundColor3 = base
	end)
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		-- si alguien cambia el color desde fuera, ese es el nuevo color base
		if not hover then
			base = button.BackgroundColor3
		end
	end)
	pressEffect(button)
	return button
end

function UiKit.setEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundTransparency = if enabled then 0 else 0.5
	button.TextTransparency = if enabled then 0 else 0.35
	button.TextStrokeTransparency = if enabled then 0 else 0.6
end

-- Puntito rojo de aviso (por ejemplo, "tienes la recompensa diaria sin cobrar")
function UiKit.dot(parent: GuiObject): Frame
	local dot = make("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Colors.Red,
		Visible = false,
		ZIndex = (parent.ZIndex or 1) + 5,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	UiKit.stroke(dot, Color3.new(1, 1, 1), 2.5)
	return dot
end

-- Icono de monedas o gemas ("Coins" | "Gems"). Usa la imagen de Economy.Icons si tiene ID; si no:
--   monedas: una moneda de oro clasica (borde dorado oscuro, cara en relieve con un anillo interior y un brillo)
--   gemas: un diamante 💎
function UiKit.icon(parent: Instance, kind: string, props: { [string]: any }?): GuiObject
	local id = (Economy.Icons :: any)[kind]
	local icon: GuiObject
	if type(id) == "string" and id ~= "" then
		icon = make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = if string.find(id, "://", 1, true) then id else "rbxassetid://" .. id,
			ScaleType = Enum.ScaleType.Fit,
		}, parent)
	elseif kind == "Gems" then
		icon = UiKit.emoji(parent, "💎", {})
	else
		icon = make("Frame", { BackgroundColor3 = Color3.fromRGB(240, 170, 30) }, parent)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, icon)
		UiKit.stroke(icon, Color3.fromRGB(120, 70, 10), 2)
		make("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 225, 110), Color3.fromRGB(200, 120, 15)),
			Rotation = 90,
		}, icon)
		-- Cara de la moneda (en relieve)
		local face = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			BackgroundColor3 = Color3.fromRGB(255, 205, 60),
		}, icon)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, face)
		make("UIStroke", { Color = Color3.fromRGB(190, 120, 20), Thickness = 1.5 }, face)
		make("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(235, 160, 30)),
			Rotation = -60,
		}, face)
		-- Brillo
		local shine = make("Frame", {
			Position = UDim2.fromScale(0.2, 0.14),
			Size = UDim2.fromScale(0.26, 0.14),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.25,
			Rotation = -30,
		}, icon)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	end
	if props then
		for key, value in props do
			(icon :: any)[key] = value
		end
	end
	return icon
end

-- Recuadro oscuro con el icono y la cantidad de monedas o gemas (se actualiza solo). Para las ventanas.
function UiKit.currencyChip(parent: Instance, kind: string, props: { [string]: any }?): Frame
	local chip = make("Frame", {
		Size = UDim2.fromOffset(150, 36),
		BackgroundColor3 = Colors.Chip,
		BackgroundTransparency = 0.05,
	}, parent)
	UiKit.corner(chip, 8)
	UiKit.stroke(chip, Colors.Ink, 2)
	UiKit.icon(chip, kind, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
	})
	local amount = UiKit.label(chip, "0", {
		Position = UDim2.fromOffset(38, 5),
		Size = UDim2.new(1, -44, 1, -10),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local player = Players.LocalPlayer
	local function refresh()
		amount.Text = EconomyMath.format(tonumber(player:GetAttribute(kind)) or 0)
	end
	refresh()
	player:GetAttributeChangedSignal(kind):Connect(refresh)
	if props then
		for key, value in props do
			(chip :: any)[key] = value
		end
	end
	return chip
end

-- Ventana centrada (estilo "taquilla"): azul claro con degradado, borde grueso oscuro, titulo blanco con contorno
-- arriba a la izquierda, monedas y gemas arriba y boton rojo de cerrar en la esquina. "title" puede empezar por un emoji.
-- Devuelve (ventana, contenido, boton cerrar)
function UiKit.window(parent: Instance, title: string, size: Vector2): (Frame, Frame, TextButton)
	local window = make("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 10,
	}, parent)
	UiKit.corner(window, 20)
	UiKit.stroke(window, Colors.Ink, 6)
	make("UIGradient", {
		Color = ColorSequence.new(Colors.WindowTop, Colors.WindowBottom),
		Rotation = 90,
	}, window)
	-- Marco interior blanco (como el de las ventanas de los simuladores)
	local frame = make("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, window)
	UiKit.corner(frame, 16)
	UiKit.stroke(frame, Color3.new(1, 1, 1), 2.5, 0.35)
	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, window)
	local titleLabel = UiKit.label(header, title, {
		Position = UDim2.fromOffset(22, 10),
		Size = UDim2.new(1, -400, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	})
	textStroke(titleLabel, 3)
	-- Monedas y gemas (arriba a la derecha, como en la tienda de los simuladores)
	UiKit.currencyChip(header, "Gems", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -46, 0, 12),
		ZIndex = 11,
	})
	UiKit.currencyChip(header, "Coins", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -206, 0, 12),
		ZIndex = 11,
	})
	-- Cerrar: cuadrado rojo en la esquina, por fuera del borde
	local close = UiKit.button(window, "X", Colors.Red, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 20,
	})
	local content = make("Frame", {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -80),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, window)
	close.Activated:Connect(function()
		window.Visible = false
	end)
	return window, content, close
end

-- Zona clara semitransparente con borde blanco (para separar partes dentro de una ventana)
function UiKit.area(parent: Instance, props: { [string]: any }?): Frame
	local area = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
	}, parent)
	UiKit.corner(area, 12)
	UiKit.stroke(area, Color3.new(1, 1, 1), 2.5, 0.2)
	if props then
		for key, value in props do
			(area :: any)[key] = value
		end
	end
	return area
end

-- Loseta del menu principal: cuadrada, de color, con un icono grande (emoji) y su nombre debajo. Devuelve tambien su
-- puntito rojo de aviso (escondido).
function UiKit.tile(parent: Instance, emoji: string, text: string, color: Color3, props: { [string]: any }?): (TextButton, Frame)
	local tile = make("TextButton", {
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(104, 96),
	}, parent)
	UiKit.corner(tile, 14)
	UiKit.stroke(tile, Colors.Ink, 3.5)
	UiKit.gradient(tile, 0.72)
	UiKit.emoji(tile, emoji, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0.62, 0, 0.56, 0),
	})
	local label = UiKit.label(tile, text, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -10, 0, 22),
	})
	textStroke(label, 2.2)
	if props then
		for key, value in props do
			(tile :: any)[key] = value
		end
	end
	local base = tile.BackgroundColor3
	tile.MouseEnter:Connect(function()
		tile.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.18)
	end)
	tile.MouseLeave:Connect(function()
		tile.BackgroundColor3 = base
	end)
	pressEffect(tile)
	return tile, UiKit.dot(tile)
end

-- Loseta ancha y baja (icono a la izquierda y nombre a la derecha): para las filas de menu junto a una esquina.
-- Devuelve tambien su puntito rojo de aviso (escondido).
function UiKit.wideTile(parent: Instance, emoji: string, text: string, color: Color3, props: { [string]: any }?): (TextButton, Frame)
	local tile = make("TextButton", {
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(132, 60),
	}, parent)
	UiKit.corner(tile, 14)
	UiKit.stroke(tile, Colors.Ink, 3.5)
	UiKit.gradient(tile, 0.72)
	UiKit.emoji(tile, emoji, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(42, 42),
	})
	local label = UiKit.label(tile, text, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 50, 0.5, 0),
		Size = UDim2.new(1, -56, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	textStroke(label, 2.2)
	if props then
		for key, value in props do
			(tile :: any)[key] = value
		end
	end
	local base = tile.BackgroundColor3
	tile.MouseEnter:Connect(function()
		tile.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.18)
	end)
	tile.MouseLeave:Connect(function()
		tile.BackgroundColor3 = base
	end)
	pressEffect(tile)
	return tile, UiKit.dot(tile)
end

-- Pone ZIndex a todo lo de dentro (las ventanas van por encima del HUD). Nada queda por debajo de lo que lo
-- contiene: si no, con ZIndex global, lo de dentro de una pieza con ZIndex mas alto (p. ej. el icono y la cantidad
-- de los recuadros de monedas y gemas de las ventanas) se dibujaba DEBAJO de su fondo y se veia oscuro.
function UiKit.zindex(root: Instance, z: number)
	-- (GetDescendants va de padres a hijos: el padre ya esta ajustado cuando llega el hijo)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			local parent = d.Parent
			local floor = if parent and parent:IsA("GuiObject") then parent.ZIndex else z
			d.ZIndex = math.max(d.ZIndex, z, floor)
		end
	end
end

-- Modelo 3D de un brainrot dentro de la interfaz
-- "evolution": 0 normal, 1 o 2 evolucionado (mismo tamano en la interfaz, pero con sus adornos)
function UiKit.viewport(parent: Instance, id: string, variant: string?, props: { [string]: any }?, evolution: number?): ViewportFrame
	local viewport = make("ViewportFrame", {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(180, 180, 190),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
	}, parent)
	if props then
		for key, value in props do
			(viewport :: any)[key] = value
		end
	end
	local ok, model = pcall(BrainrotModel.build, id, variant, 4, evolution, 0)
	if ok then
		(model.PrimaryPart :: BasePart).Anchored = true
		model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(-20), 0))
		model.Parent = viewport
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		local center = Vector3.new(0, 2.1, 0)
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 1.2, -8.5), center)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end
	return viewport
end

-- Tarjeta de brainrot (para listas y para la ruleta de las cajas): fondo del color de su calidad, modelo 3D, nombre y
-- una franja oscura abajo con la calidad, la variante y el nivel
function UiKit.card(parent: Instance, record: { Id: string, Level: number?, Variant: string? }, size: Vector2): Frame
	local entry = EconomyMath.entryOf(record.Id)
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)
	local card = make("Frame", {
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = rarity.Color,
	}, parent)
	UiKit.corner(card, 12)
	make("UIStroke", {
		Color = Colors.Ink,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 140)),
		Rotation = 90,
	}, card)
	UiKit.viewport(card, record.Id, record.Variant, {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -46),
	}, EconomyMath.evolutionOf(record.Level or 1))
	UiKit.label(card, entry.Name, {
		Name = "NameLabel",
		Position = UDim2.new(0, 6, 1, -44),
		Size = UDim2.new(1, -12, 0, 20),
	})
	local sub = rarity.Name
	if record.Variant and record.Variant ~= "Normal" then
		sub = `{variant.Name} · {sub}`
	end
	if record.Level then
		local tag = EconomyMath.evolutionTag(record.Level)
		sub = `{sub} · Nv {record.Level}{if tag ~= "" then " " .. tag else ""}`
	end
	-- Franja oscura de abajo (como el "OWNED" de las tiendas)
	local band = make("Frame", {
		Name = "Band",
		Position = UDim2.new(0, 3, 1, -22),
		Size = UDim2.new(1, -6, 0, 19),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.25,
	}, card)
	UiKit.corner(band, 6)
	UiKit.label(band, sub, {
		Name = "SubLabel",
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 1, -4),
		TextColor3 = if record.Variant and record.Variant ~= "Normal" then variant.Color else rarity.Color:Lerp(Color3.new(1, 1, 1), 0.35),
	})
	return card
end

function UiKit.pop(gui: GuiObject)
	local scale = gui:FindFirstChild("Pop") :: UIScale?
	if not scale then
		scale = make("UIScale", { Name = "Pop" }, gui)
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ---------------------------------------------------------------------------
-- Tema: la misma letra y el mismo contorno para todo el texto de nuestras pantallas
-- ---------------------------------------------------------------------------

local GOTHAM: { [Enum.Font]: boolean } = {
	[Enum.Font.Gotham] = true,
	[Enum.Font.GothamMedium] = true,
	[Enum.Font.GothamBold] = true,
	[Enum.Font.GothamBlack] = true,
	[Enum.Font.SourceSans] = true,
	[Enum.Font.SourceSansBold] = true,
}

local function isLight(color: Color3): boolean
	return color.R * 0.3 + color.G * 0.59 + color.B * 0.11 > 0.5
end

local function themeObject(object: Instance)
	if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
		return
	end
	local text = object :: any
	if GOTHAM[text.Font] then
		text.Font = UiKit.Font
	end
	-- Contorno solo en letras claras (las oscuras sobre fondo claro ya se leen) y si nadie lo ha pedido distinto
	if object:IsA("TextLabel") and object:GetAttribute("NoStroke") ~= true and isLight(text.TextColor3) then
		textStroke(object)
	elseif object:IsA("TextButton") and text.TextStrokeTransparency >= 1 and isLight(text.TextColor3) then
		text.TextStrokeColor3 = Colors.Ink
		text.TextStrokeTransparency = 0.1
	end
end

-- Aplica el tema a todo lo que hay (y a todo lo que se cree despues) dentro de "root" (normalmente el PlayerGui)
local themed: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
function UiKit.theme(root: Instance)
	if themed[root] then
		return
	end
	themed[root] = true
	for _, d in root:GetDescendants() do
		themeObject(d)
	end
	root.DescendantAdded:Connect(function(d: Instance)
		-- Se espera a que quien lo crea termine de ponerle sus propiedades (fuente, color...)
		task.defer(function()
			if d.Parent then
				themeObject(d)
			end
		end)
	end)
end

return UiKit
