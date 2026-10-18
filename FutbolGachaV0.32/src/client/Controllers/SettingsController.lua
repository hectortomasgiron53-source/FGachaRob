--!strict
--[[
	SettingsController: boton de Configuracion (arriba a la derecha) y su panel.
	- Volumenes: General, Efectos y Publico. Solo afectan a este jugador.
	Funciona en el lobby y en los partidos.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local AudioSettings = require(script.Parent.AudioSettings)

local player = Players.LocalPlayer

local SettingsController = {}

local COLORS = {
	Panel = Color3.fromRGB(14, 20, 34),
	Card = Color3.fromRGB(24, 32, 52),
	Text = Color3.fromRGB(235, 240, 250),
	Muted = Color3.fromRGB(150, 162, 186),
	Accent = Color3.fromRGB(250, 200, 50),
	Track = Color3.fromRGB(48, 58, 84),
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

-- Deslizador 0-100 %. "name" es la clave de AudioSettings.
local function slider(parent: Instance, order: number, label: string, name: string)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
	}, parent)
	make("TextLabel", {
		Size = UDim2.new(0.7, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = label,
	}, row)
	local valueLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.3, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = COLORS.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	}, row)
	local bar = make("TextButton", {
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = COLORS.Track,
		AutoButtonColor = false,
		Text = "",
	}, row)
	corner(bar, 5)
	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = COLORS.Accent,
		BorderSizePixel = 0,
	}, bar)
	corner(fill, 5)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundColor3 = COLORS.Text,
		ZIndex = 2,
	}, bar)
	corner(knob, 9)

	local function render(value: number)
		fill.Size = UDim2.new(value, 0, 1, 0)
		knob.Position = UDim2.new(value, 0, 0.5, 0)
		valueLabel.Text = `{math.floor(value * 100 + 0.5)} %`
	end

	local dragging = false
	local function setFromX(x: number)
		local relative = (x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1)
		AudioSettings.set(name, math.clamp(relative, 0, 1))
	end
	bar.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	render(AudioSettings.get(name))
	AudioSettings.onChanged(function(changed: string, value: number)
		if changed == name then
			render(value)
		end
	end)
end

local function button(parent: Instance, text: string, size: UDim2): TextButton
	local b = make("TextButton", {
		Size = size,
		BackgroundColor3 = COLORS.Track,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = COLORS.Text,
		Text = text,
	}, parent)
	corner(b, 8)
	return b
end

local function sectionTitle(parent: Instance, order: number, text: string)
	make("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
	}, parent)
end

function SettingsController.start()
	local gui = make("ScreenGui", {
		Name = "FutbolGachaSettings",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- Boton de engranaje (siempre visible, arriba a la derecha)
	local openButton = make("TextButton", {
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 44, 0, 44),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextColor3 = COLORS.Text,
		Text = "⚙",
	}, gui)
	corner(openButton, 10)

	-- Panel
	local panel = make("Frame", {
		Name = "SettingsPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 380, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Panel,
		Visible = false,
	}, gui)
	corner(panel, 14)
	make("UIStroke", { Color = COLORS.Track, Thickness = 1.5 }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

	-- Cabecera
	local header = make("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, panel)
	make("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Configuración",
	}, header)
	local closeButton = button(header, "✕", UDim2.new(0, 30, 0, 30))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)

	-- Sonido
	sectionTitle(panel, 2, "SONIDO")
	slider(panel, 3, "Volumen general", "Master")
	slider(panel, 4, "Efectos (balón, silbato...)", "Effects")
	slider(panel, 5, "Público", "Crowd")

	local function setOpen(open: boolean)
		panel.Visible = open
	end
	openButton.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
end

return SettingsController
