--!strict
--[[
	UiKit: piezas de interfaz comunes (colores, botones, paneles, tarjetas de brainrot con su modelo en 3D).
	No es un controlador: lo usan EconomyController y sus paneles.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BrainrotModel = require(ReplicatedStorage.Shared.Util.BrainrotModel)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)

local UiKit = {}

UiKit.Colors = {
	Back = Color3.fromRGB(11, 18, 34),
	Panel = Color3.fromRGB(20, 32, 56),
	Panel2 = Color3.fromRGB(28, 44, 74),
	Line = Color3.fromRGB(58, 84, 130),
	Text = Color3.fromRGB(235, 242, 255),
	Muted = Color3.fromRGB(150, 165, 195),
	Coins = Color3.fromRGB(255, 200, 60),
	Gems = Color3.fromRGB(90, 220, 255),
	Green = Color3.fromRGB(70, 190, 100),
	Red = Color3.fromRGB(220, 70, 70),
	Blue = Color3.fromRGB(60, 120, 230),
	Purple = Color3.fromRGB(150, 90, 240),
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
	make("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

function UiKit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	make("UIStroke", {
		Color = color or Colors.Line,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
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

function UiKit.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
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

-- Boton con un pequeno efecto al pasar el raton
function UiKit.button(parent: Instance, text: string, color: Color3, props: { [string]: any }?): TextButton
	local button = make("TextButton", {
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = text,
	}, parent)
	UiKit.corner(button, 8)
	make("UITextSizeConstraint", { MaxTextSize = 22 }, button)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, button)
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	local base = color
	button.MouseEnter:Connect(function()
		if button.Active then
			button.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.15)
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = base
	end)
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		-- si alguien cambia el color desde fuera, ese es el nuevo color base
		local c = button.BackgroundColor3
		if c ~= base:Lerp(Color3.new(1, 1, 1), 0.15) then
			base = c
		end
	end)
	return button
end

function UiKit.setEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundTransparency = if enabled then 0 else 0.55
	button.TextTransparency = if enabled then 0 else 0.4
end

-- Ventana centrada con titulo y boton de cerrar. Devuelve (ventana, contenido, boton cerrar)
function UiKit.window(parent: Instance, title: string, size: Vector2): (Frame, Frame, TextButton)
	local window = make("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Colors.Back,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 10,
	}, parent)
	UiKit.corner(window, 16)
	UiKit.stroke(window, Colors.Line, 2)
	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Colors.Panel,
		ZIndex = 10,
	}, window)
	UiKit.corner(header, 16)
	make("Frame", { -- tapa las esquinas redondeadas de abajo del titulo
		Position = UDim2.new(0, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, header)
	UiKit.label(header, title, {
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -90, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBlack,
		ZIndex = 11,
	})
	local close = UiKit.button(header, "X", Colors.Red, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		ZIndex = 11,
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

-- Pone ZIndex a todo lo de dentro (las ventanas van por encima del HUD)
function UiKit.zindex(root: Instance, z: number)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, z)
		end
	end
end

-- Modelo 3D de un brainrot dentro de la interfaz
function UiKit.viewport(parent: Instance, id: string, variant: string?, props: { [string]: any }?): ViewportFrame
	local viewport = make("ViewportFrame", {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
	}, parent)
	if props then
		for key, value in props do
			(viewport :: any)[key] = value
		end
	end
	local ok, model = pcall(BrainrotModel.build, id, variant, 4)
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

-- Tarjeta de brainrot (para listas y para la ruleta de las cajas)
function UiKit.card(parent: Instance, record: { Id: string, Level: number?, Variant: string? }, size: Vector2): Frame
	local entry = EconomyMath.entryOf(record.Id)
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)
	local card = make("Frame", {
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Colors.Panel,
	}, parent)
	UiKit.corner(card, 10)
	UiKit.stroke(card, rarity.Color, 2)
	make("UIGradient", {
		Color = ColorSequence.new(Colors.Panel, rarity.Color:Lerp(Colors.Panel, 0.55)),
		Rotation = 90,
	}, card)
	UiKit.viewport(card, record.Id, record.Variant, {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -44),
	})
	UiKit.label(card, entry.Name, {
		Name = "NameLabel",
		Position = UDim2.new(0, 6, 1, -40),
		Size = UDim2.new(1, -12, 0, 20),
		Font = Enum.Font.GothamBlack,
	})
	local sub = rarity.Name
	if record.Variant and record.Variant ~= "Normal" then
		sub = `{variant.Name} · {sub}`
	end
	if record.Level then
		sub = `{sub} · Nv {record.Level}`
	end
	UiKit.label(card, sub, {
		Name = "SubLabel",
		Position = UDim2.new(0, 6, 1, -19),
		Size = UDim2.new(1, -12, 0, 15),
		TextColor3 = if record.Variant and record.Variant ~= "Normal" then variant.Color else rarity.Color,
	})
	-- Franja de color de la calidad
	make("Frame", {
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = rarity.Color,
		BorderSizePixel = 0,
	}, card)
	return card
end

function UiKit.pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale") or make("UIScale", {}, gui)
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

return UiKit
