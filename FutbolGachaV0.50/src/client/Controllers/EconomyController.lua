--!strict
--[[
	EconomyController: interfaz de la economia.
	- Arriba a la derecha: monedas, gemas, nivel (con barra de XP) y monedas por segundo de tu granja.
	- A la izquierda: menu (Brainrots, Cajas, Tienda, Diario, Mi granja).
	- Avisos (recompensas, robos, subir de nivel) y resumen de recompensas al acabar un partido.
	Durante un partido se esconde todo menos los avisos.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local MatchController = require(script.Parent.MatchController)
local InventoryPanel = require(script.Parent.InventoryPanel)
local CasesPanel = require(script.Parent.CasesPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local DailyPanel = require(script.Parent.DailyPanel)

local EconomyController = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local gui: ScreenGui
local toastHolder: Frame
local windows: { Frame } = {}

-- ---------------------------------------------------------------------------
-- Avisos
-- ---------------------------------------------------------------------------

local TOAST_COLORS: { [string]: Color3 } = {
	Info = Colors.Blue,
	Reward = Colors.Green,
	Warning = Colors.Red,
	LevelUp = Colors.Coins,
}

local function toast(kind: string, text: string)
	if not toastHolder then
		return
	end
	local color = TOAST_COLORS[kind] or Colors.Blue
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Colors.Back,
		BackgroundTransparency = 0.08,
		LayoutOrder = -math.floor(os.clock() * 100),
	}, toastHolder)
	UiKit.corner(frame, 10)
	UiKit.stroke(frame, color, 2)
	make("Frame", {
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, frame)
	UiKit.label(frame, text, {
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -24, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.zindex(frame, 60)
	frame.ZIndex = 60
	UiKit.pop(frame)
	local life = if kind == "Warning" then 5 else 4
	task.delay(life, function()
		if frame.Parent then
			local info = TweenInfo.new(0.3)
			for _, d in frame:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, info, { TextTransparency = 1 }):Play()
				elseif d:IsA("Frame") then
					TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, info, { Transparency = 1 }):Play()
				end
			end
			TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
			task.wait(0.32)
			frame:Destroy()
		end
	end)
	-- Como mucho 5 a la vez
	local list = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(list, child)
		end
	end
	if #list > 5 then
		table.sort(list, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		list[1]:Destroy()
	end
end
EconomyController.toast = toast

-- Resumen al acabar un partido
local function showMatchReward(extra: any)
	local titles = { Win = "¡VICTORIA!", Draw = "EMPATE", Loss = "DERROTA" }
	local colors = { Win = Colors.Green, Draw = Colors.Blue, Loss = Colors.Red }
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(380, 250),
		BackgroundColor3 = Colors.Back,
		ZIndex = 50,
	}, gui)
	UiKit.corner(panel, 16)
	UiKit.stroke(panel, colors[extra.Outcome] or Colors.Blue, 3)
	UiKit.label(panel, titles[extra.Outcome] or "FIN", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Enum.Font.GothamBlack,
		TextColor3 = colors[extra.Outcome] or Colors.Text,
	})
	UiKit.label(panel, `Goles tuyos: {extra.Goals}`, {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Colors.Muted,
	})
	local rows: { { any } } = {
		{ `+{EconomyMath.format(extra.Coins)} monedas`, Colors.Coins },
		{ `+{extra.Gems} gemas`, Colors.Gems },
		{ `+{extra.XP} XP`, Colors.Purple },
	}
	for i, row in rows do
		UiKit.label(panel, row[1], {
			Position = UDim2.fromOffset(0, 84 + (i - 1) * 32),
			Size = UDim2.new(1, 0, 0, 28),
			TextColor3 = row[2],
			Font = Enum.Font.GothamBlack,
		})
	end
	local ok = UiKit.button(panel, "¡Genial!", Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(200, 40),
	})
	UiKit.zindex(panel, 50)
	UiKit.pop(panel)
	ok.Activated:Connect(function()
		panel:Destroy()
	end)
	task.delay(12, function()
		if panel.Parent then
			panel:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------

local function closeAll(except: Frame?)
	for _, window in windows do
		if window ~= except then
			window.Visible = false
		end
	end
end

function EconomyController.openInventory(uid: string?)
	closeAll()
	InventoryPanel.open(uid)
end

function EconomyController.start()
	ClientData.start()

	gui = make("ScreenGui", {
		Name = "EconomiaUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))
	-- Escala para pantallas pequenas (movil)
	local scale = make("UIScale", {}, gui)
	local function rescale()
		local camera = Workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			scale.Scale = math.clamp(math.min(size.X / 1100, size.Y / 720), 0.55, 1)
		end
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- HUD
	-- (arriba a la derecha, junto al engranaje: arriba a la izquierda esta el chat de Roblox)
	local hud = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -66, 0, 12),
		Size = UDim2.fromOffset(230, 128),
		BackgroundColor3 = Colors.Back,
		BackgroundTransparency = 0.15,
	}, gui)
	UiKit.corner(hud, 12)
	UiKit.stroke(hud, Colors.Line, 1.5)
	local coinsLabel = UiKit.label(hud, "0", {
		Position = UDim2.fromOffset(44, 8),
		Size = UDim2.new(1, -52, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Coins,
		Font = Enum.Font.GothamBlack,
	})
	local coinIcon = make("Frame", {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Colors.Coins,
	}, hud)
	UiKit.corner(coinIcon, 12)
	UiKit.stroke(coinIcon, Color3.fromRGB(170, 120, 20), 2)
	local gemsLabel = UiKit.label(hud, "0", {
		Position = UDim2.fromOffset(44, 40),
		Size = UDim2.new(1, -52, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Gems,
		Font = Enum.Font.GothamBlack,
	})
	local gemIcon = make("Frame", {
		Position = UDim2.fromOffset(15, 43),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Colors.Gems,
		Rotation = 45,
	}, hud)
	UiKit.corner(gemIcon, 4)
	local incomeLabel = UiKit.label(hud, "", {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 0, 15),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
	})
	local levelLabel = UiKit.label(hud, "Nivel 1", {
		Position = UDim2.fromOffset(12, 88),
		Size = UDim2.new(1, -24, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Purple,
	})
	local xpBack = make("Frame", {
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.new(1, -24, 0, 10),
		BackgroundColor3 = Colors.Panel2,
	}, hud)
	UiKit.corner(xpBack, 5)
	local xpFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Purple,
	}, xpBack)
	UiKit.corner(xpFill, 5)
	local tempLabel = UiKit.label(gui, "Datos temporales: no se guardan (activa el acceso a la API en Studio)", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -66, 0, 144),
		Size = UDim2.fromOffset(330, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Colors.Red,
		Visible = false,
	})

	-- Menu
	local menu = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 20),
		Size = UDim2.fromOffset(130, 5 * 52),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, menu)
	local function menuButton(text: string, color: Color3, order: number): TextButton
		local b = UiKit.button(menu, text, color, {
			Size = UDim2.fromOffset(130, 44),
			LayoutOrder = order,
		})
		UiKit.stroke(b, Color3.new(1, 1, 1), 1.5, 0.6)
		return b
	end
	local inventoryButton = menuButton("Brainrots", Colors.Blue, 1)
	local casesButton = menuButton("Cajas", Colors.Purple, 2)
	local shopButton = menuButton("Tienda", Colors.Green, 3)
	local dailyButton = menuButton("Diario", Color3.fromRGB(230, 140, 40), 4)
	local homeButton = menuButton("Mi granja", Color3.fromRGB(60, 140, 120), 5)
	local dailyDot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Colors.Red,
		Visible = false,
		ZIndex = 3,
	}, dailyButton)
	UiKit.corner(dailyDot, 8)

	-- Avisos (arriba en el centro, debajo del marcador)
	toastHolder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(440, 300),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, gui)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)

	-- Ventanas
	local inventoryWindow = InventoryPanel.build(gui, toast)
	local casesWindow = CasesPanel.build(gui, toast)
	local shopWindow = ShopPanel.build(gui, toast)
	local dailyWindow = DailyPanel.build(gui, toast)
	windows = { inventoryWindow, casesWindow, shopWindow, dailyWindow }

	local function toggle(window: Frame, open: () -> ())
		if window.Visible then
			window.Visible = false
		else
			closeAll()
			open()
		end
	end
	inventoryButton.Activated:Connect(function()
		toggle(inventoryWindow, function()
			InventoryPanel.open()
		end)
	end)
	casesButton.Activated:Connect(function()
		toggle(casesWindow, CasesPanel.open)
	end)
	shopButton.Activated:Connect(function()
		toggle(shopWindow, ShopPanel.open)
	end)
	dailyButton.Activated:Connect(function()
		toggle(dailyWindow, DailyPanel.open)
	end)
	homeButton.Activated:Connect(function()
		closeAll()
		Remotes.get("Notify"):FireServer("GoHome")
	end)

	-- Avisos del servidor
	Remotes.get("Notify").OnClientEvent:Connect(function(kind: string, text: string, extra: any)
		if kind == "MatchReward" and type(extra) == "table" then
			showMatchReward(extra)
		elseif kind == "LevelUp" and type(extra) == "table" then
			toast("LevelUp", `¡Nivel {extra.Level}! +{EconomyMath.format(extra.Coins)} monedas y +{extra.Gems} gemas`)
		elseif type(text) == "string" then
			toast(kind, text)
		end
	end)

	-- Valores del HUD
	local shownCoins = 0
	local function refreshHud()
		local data = ClientData.get()
		gemsLabel.Text = EconomyMath.format(ClientData.gems())
		local level = tonumber(player:GetAttribute("Level")) or 1
		local xp = tonumber(player:GetAttribute("XP")) or 0
		local need = tonumber(player:GetAttribute("XPNeed")) or 100
		levelLabel.Text = `Nivel {level}  ·  {xp}/{need} XP`
		xpFill.Size = UDim2.fromScale(math.clamp(xp / need, 0, 1), 1)
		local income = tonumber(player:GetAttribute("Income")) or 0
		incomeLabel.Text = `Granja: +{EconomyMath.format(income)} monedas/s`
		tempLabel.Visible = data ~= nil and data.Temporary == true
		dailyDot.Visible = DailyPanel.canClaim()
	end
	for _, name in { "Gems", "Level", "XP", "XPNeed", "Income" } do
		player:GetAttributeChangedSignal(name):Connect(refreshHud)
	end
	ClientData.onChanged(refreshHud)
	refreshHud()

	RunService.RenderStepped:Connect(function(dt: number)
		-- Las monedas suben con una pequena animacion
		local target = ClientData.coins()
		if math.abs(target - shownCoins) < 1 then
			shownCoins = target
		else
			shownCoins += (target - shownCoins) * math.min(1, dt * 8)
		end
		coinsLabel.Text = EconomyMath.format(shownCoins)
		local inMatch = MatchController.isInMatch()
		local folder = MatchController.getFolder()
		local playground = inMatch and folder ~= nil and folder:GetAttribute("Mode") == "Playground"
		local hide = inMatch and not playground
		hud.Visible = not hide
		menu.Visible = not hide
		if hide then
			closeAll()
		end
	end)
end

return EconomyController
