--!strict
--[[
	DebugPanel: panel de pruebas, SOLO en Roblox Studio (en el juego publicado no aparece y el servidor no lo acepta).
	Boton "Pruebas" abajo a la izquierda (o tecla F4): monedas, gemas, brainrots de cada calidad, subir de nivel tu
	granja (para ver las evoluciones) y velocidad.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)

local DebugPanel = {}

local Colors = UiKit.Colors

function DebugPanel.start()
	if not RunService:IsStudio() then
		return
	end
	local remote = Remotes.get("Debug")
	local player = Players.LocalPlayer
	local gui = UiKit.make("ScreenGui", {
		Name = "PruebasUI",
		ResetOnSpawn = false,
		DisplayOrder = 20,
	}, player:WaitForChild("PlayerGui"))

	local toggle = UiKit.button(gui, "Pruebas (F4)", Color3.fromRGB(90, 90, 110), {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(130, 32),
	})
	local panel = UiKit.make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -54),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Back,
		BackgroundTransparency = 0.05,
		Visible = false,
	}, gui)
	UiKit.corner(panel, 10)
	UiKit.stroke(panel, Colors.Line, 1.5)
	UiKit.padding(panel, 8)
	UiKit.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

	local order = 0
	local function row(title: string, buttons: { { any } })
		order += 1
		UiKit.label(panel, title, {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Colors.Muted,
		})
		order += 1
		local line = UiKit.make("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, panel)
		for i, spec in buttons do
			local b = UiKit.button(line, spec[1], spec[4] or Colors.Blue, {
				Position = UDim2.new((i - 1) / #buttons, 2, 0, 0),
				Size = UDim2.new(1 / #buttons, -4, 1, 0),
			})
			b.Activated:Connect(function()
				remote:FireServer(spec[2], spec[3])
			end)
		end
	end

	row("Monedas", {
		{ "+100K", "Coins", 1e5, Colors.Coins },
		{ "+10M", "Coins", 1e7, Colors.Coins },
		{ "+1B", "Coins", 1e9, Colors.Coins },
	})
	row("Gemas", {
		{ "+10K", "Gems", 1e4, Colors.Gems },
		{ "+100K", "Gems", 1e5, Colors.Gems },
	})
	local rarities = {}
	for _, rarity in Brainrots.Rarities do
		table.insert(rarities, { rarity.Name, "Brainrot", rarity.Id, rarity.Color })
	end
	row("Brainrot al azar (va a tu granja si hay sitio)", rarities)
	row("Nivel de cuenta (desbloquea vehículos cada 25)", {
		{ "+1", "AccountLevel", 1, Colors.Purple },
		{ "+5", "AccountLevel", 5, Colors.Purple },
		{ "+25", "AccountLevel", 25, Colors.Purple },
		{ "Al 100", "AccountLevel", 1000, Colors.Purple },
	})
	row("Modelos 3D: ponlos en fila mirándote para revisar su giro", {
		{ "👀 Revisar giros", "ReviewModels", 1, Colors.Orange },
		{ "Quitar fila", "ReviewModels", -1, Colors.Red },
	})
	row("Copas online (rangos). Solo en la cola 6 s = partido online de prueba", {
		{ "+100", "Rating", 100, Colors.Orange },
		{ "+500", "Rating", 500, Colors.Orange },
		{ "-100", "Rating", -100, Colors.Red },
		{ "Reset", "Rating", 0, Colors.Panel },
	})
	row("Subir niveles a tu granja (gratis)", {
		{ "+10", "LevelFarm", 10 },
		{ "+50", "LevelFarm", 50 },
		{ "Al 100", "LevelFarm", 100 },
	})
	row("Velocidad (fuera de partido)", {
		{ "x1", "Speed", 1 },
		{ "x2", "Speed", 2 },
		{ "x3", "Speed", 3 },
		{ "x5", "Speed", 5 },
	})

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.F4 then
			panel.Visible = not panel.Visible
		end
	end)
end

return DebugPanel
