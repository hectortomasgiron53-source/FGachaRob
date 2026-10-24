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

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local MatchController = require(script.Parent.MatchController)
local InventoryPanel = require(script.Parent.InventoryPanel)
local CasesPanel = require(script.Parent.CasesPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local DailyPanel = require(script.Parent.DailyPanel)
local GaragePanel = require(script.Parent.GaragePanel)
local CodesPanel = require(script.Parent.CodesPanel)
local RankedPanel = require(script.Parent.RankedPanel)
local OffersPanel = require(script.Parent.OffersPanel)
local TutorialTargets = require(script.Parent.TutorialTargets)
local Tutorial = require(script.Parent.Tutorial)

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
	LevelUp = Colors.Orange,
}
local TOAST_ICONS: { [string]: string } = {
	Info = "💬",
	Reward = "✅",
	Warning = "⚠️",
	LevelUp = "⭐",
}

local function toast(kind: string, text: string)
	if not toastHolder then
		return
	end
	local color = TOAST_COLORS[kind] or Colors.Blue
	-- Aviso de color segun el tipo (verde premio, rojo cuidado, naranja nivel, azul info), con su icono
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = color,
		LayoutOrder = -math.floor(os.clock() * 100),
	}, toastHolder)
	UiKit.corner(frame, 12)
	UiKit.stroke(frame, Colors.Ink, 3)
	UiKit.gradient(frame, 0.72)
	UiKit.emoji(frame, TOAST_ICONS[kind] or "💬", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
	})
	UiKit.label(frame, text, {
		Position = UDim2.fromOffset(48, 7),
		Size = UDim2.new(1, -58, 1, -14),
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
	-- Online: ademas, copas ganadas o perdidas, rango (sube / baja) y MVP
	local online = extra.Online == true
	local extraHeight = if online then 128 else 0
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(if online then 420 else 380, 250 + extraHeight),
		BackgroundColor3 = Colors.Back,
		ZIndex = 50,
	}, gui)
	UiKit.corner(panel, 16)
	UiKit.stroke(panel, colors[extra.Outcome] or Colors.Blue, 3)
	UiKit.label(panel, (if online then "⚔️ " else "") .. (titles[extra.Outcome] or "FIN"), {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Enum.Font.GothamBlack,
		TextColor3 = colors[extra.Outcome] or Colors.Text,
	})
	UiKit.label(panel, if extra.Forfeit then `Goles tuyos: {extra.Goals} · el rival abandonó` else `Goles tuyos: {extra.Goals}`, {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Colors.Muted,
	})
	if online then
		local delta = tonumber(extra.RatingDelta) or 0
		local sign = if delta >= 0 then "+" else ""
		local ratingRow = UiKit.label(panel, `🏆 {sign}{delta} copas`, {
			Position = UDim2.fromOffset(0, 84),
			Size = UDim2.new(1, 0, 0, 34),
			TextColor3 = if delta >= 0 then Colors.Green else Colors.Red,
		})
		UiKit.textStroke(ratingRow, 2.5)
		local rankText = `{extra.RankLabel or ""} · {EconomyMath.format(tonumber(extra.Rating) or 0)} copas`
		if extra.Promoted then
			rankText = `⬆️ ¡Has subido a {extra.Promoted}!  {extra.RankLabel or ""}`
		elseif extra.Demoted then
			rankText = `⬇️ Has bajado a {extra.Demoted}  {extra.RankLabel or ""}`
		elseif (tonumber(extra.Streak) or 0) >= 2 and delta > 0 then
			rankText ..= `  ·  🔥 racha de {extra.Streak}`
		end
		UiKit.label(panel, rankText, {
			Position = UDim2.fromOffset(10, 120),
			Size = UDim2.new(1, -20, 0, 22),
			TextColor3 = if extra.Promoted then Colors.Yellow else Colors.Text,
		})
		local mvpText = if extra.Mvp then `⭐ ¡ERES EL MVP! +{extra.MvpGems or 0} gemas`
			elseif extra.MvpName then `⭐ MVP: {extra.MvpName}`
			else "⭐ Sin MVP (nadie marcó)"
		UiKit.label(panel, mvpText, {
			Position = UDim2.fromOffset(10, 148),
			Size = UDim2.new(1, -20, 0, 24),
			TextColor3 = if extra.Mvp then Colors.Yellow else Colors.Muted,
		})
		make("Frame", {
			Position = UDim2.new(0, 30, 0, 182),
			Size = UDim2.new(1, -60, 0, 3),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.4,
		}, panel)
	end
	local rows: { { any } } = {
		{ `+{EconomyMath.format(extra.Coins)} monedas`, Colors.Coins },
		{ `+{extra.Gems} gemas`, Colors.Gems },
		{ `+{extra.XP} XP`, Colors.Purple },
	}
	for i, row in rows do
		UiKit.label(panel, row[1], {
			Position = UDim2.fromOffset(0, 84 + extraHeight - (if online then 18 else 0) + (i - 1) * 32),
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

-- Cierra todas las ventanas (lo usa el tutorial)
function EconomyController.closeAll()
	closeAll()
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

	-- Toda nuestra interfaz con la misma letra y contorno (tambien la de los demas controladores)
	UiKit.theme(player:WaitForChild("PlayerGui"))

	-- HUD (a la izquierda, como en los simuladores): monedas y gemas en "pildoras" con un "+" verde, nivel y menu
	local side = make("Frame", {
		Name = "SideHud",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 6, 0, 4), -- pegado a la esquina de arriba a la izquierda
		Size = UDim2.fromOffset(240, 570),
		BackgroundTransparency = 1,
	}, gui)

	-- Pildora de monedas o gemas: icono grande a la izquierda, cantidad y un "+" verde que abre la tienda
	local function pill(kind: string, y: number, color: Color3): (TextLabel, TextButton, Frame)
		local frame = make("Frame", {
			Position = UDim2.fromOffset(18, y),
			Size = UDim2.fromOffset(212, 50),
			BackgroundColor3 = color,
		}, side)
		UiKit.corner(frame, 14)
		UiKit.stroke(frame, Colors.Ink, 3.5)
		UiKit.gradient(frame, 0.7)
		UiKit.icon(side, kind, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(0, y + 25),
			Size = UDim2.fromOffset(54, 54),
			ZIndex = 3,
		})
		local amount = UiKit.label(frame, "0", {
			Position = UDim2.fromOffset(42, 5),
			Size = UDim2.new(1, -96, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		UiKit.textStroke(amount, 2.5)
		local plus = UiKit.button(frame, "+", Colors.Green, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
		})
		return amount, plus, frame
	end
	local coinsLabel, coinsPlus, coinsPill = pill("Coins", 0, Colors.Blue)
	local gemsLabel, gemsPlus, gemsPill = pill("Gems", 64, Colors.Blue)
	-- Monedas por segundo de tu granja, debajo de la cantidad
	local incomeLabel = UiKit.label(coinsPill, "", {
		Position = UDim2.fromOffset(42, 33),
		Size = UDim2.new(1, -96, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(170, 255, 150),
	})

	-- Nivel de la cuenta con su barra de experiencia
	local levelPill = make("Frame", {
		Position = UDim2.fromOffset(18, 128),
		Size = UDim2.fromOffset(212, 36),
		BackgroundColor3 = Colors.Purple,
	}, side)
	UiKit.corner(levelPill, 12)
	UiKit.stroke(levelPill, Colors.Ink, 3)
	UiKit.gradient(levelPill, 0.7)
	UiKit.emoji(side, "⭐", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(2, 146),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 3,
	})
	local levelLabel = UiKit.label(levelPill, "Nivel 1", {
		Position = UDim2.fromOffset(30, 2),
		Size = UDim2.new(1, -38, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local xpBack = make("Frame", {
		Position = UDim2.fromOffset(30, 22),
		Size = UDim2.new(1, -40, 0, 9),
		BackgroundColor3 = Colors.Ink,
	}, levelPill)
	UiKit.corner(xpBack, 5)
	local xpFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Yellow,
	}, xpBack)
	UiKit.corner(xpFill, 5)

	-- Menus repartidos a los dos lados:
	--   izquierda, bajo el nivel: Brainrots y, debajo, Mi granja (losetas cuadradas, una columna)
	--   derecha, en fila junto al engranaje de ajustes: diario, cajas, tienda y codigos (losetas anchas y bajas)
	local leftMenu = make("Frame", {
		Position = UDim2.fromOffset(4, 208), -- separado del nivel
		Size = UDim2.fromOffset(112, 350),
		BackgroundTransparency = 1,
	}, side)
	make("UIListLayout", { Padding = UDim.new(0, 30), SortOrder = Enum.SortOrder.LayoutOrder }, leftMenu) -- y separados entre si
	-- La fila de la derecha va arriba del todo, a la altura de los botones de Roblox (esa esquina esta libre): en una
	-- pantalla aparte que ignora la franja de arriba, igual que el engranaje de ajustes
	local topGui = make("ScreenGui", {
		Name = "MenuArriba",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))
	local rightMenu = make("Frame", {
		Name = "RightHud",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -80, 0, 6), -- a la izquierda del engranaje de ajustes (64 de ancho, pegado a la esquina)
		Size = UDim2.fromOffset(4 * 132 + 3 * 8, 64),
		BackgroundTransparency = 1,
	}, topGui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rightMenu)
	local inventoryButton = UiKit.tile(leftMenu, "🧠", "Brainrots", Colors.Blue, { LayoutOrder = 1, Size = UDim2.fromOffset(108, 92) })
	local homeButton = UiKit.tile(leftMenu, "🏡", "Mi granja", Colors.Teal, { LayoutOrder = 2, Size = UDim2.fromOffset(108, 92) })
	local garageButton = UiKit.tile(leftMenu, "🛹", "Garaje", Colors.Orange, { LayoutOrder = 3, Size = UDim2.fromOffset(108, 92) })
	local dailyButton, dailyDot = UiKit.wideTile(rightMenu, "📅", "Diario", Colors.Orange, { LayoutOrder = 1 })
	local casesButton, casesDot = UiKit.wideTile(rightMenu, "🎁", "Cajas", Colors.Purple, { LayoutOrder = 2 })
	local shopButton = UiKit.wideTile(rightMenu, "🛒", "Tienda", Colors.Green, { LayoutOrder = 3 })
	local codesButton = UiKit.wideTile(rightMenu, "🎟️", "Códigos", Colors.Red, { LayoutOrder = 4 })

	local tempLabel = UiKit.label(side, "Datos temporales: no se guardan (activa el acceso a la API en Studio)", {
		Position = UDim2.fromOffset(0, 556),
		Size = UDim2.fromOffset(330, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Red,
		Visible = false,
	})

	-- Avisos (arriba en el centro, debajo del marcador)
	toastHolder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(460, 300),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)

	-- Ventanas
	local inventoryWindow = InventoryPanel.build(gui, toast)
	CasesPanel.build(gui, toast) -- (la ruleta de las cajas; las cajas se compran en la tienda)
	local garageWindow = GaragePanel.build(gui, toast)
	local shopWindow = ShopPanel.build(gui, toast)
	local dailyWindow = DailyPanel.build(gui, toast)
	local codesWindow = CodesPanel.build(gui, toast)
	local rankedWindow = RankedPanel.build(gui, toast) -- partidos online (botones de jugar, cola, grupo, copas)
	OffersPanel.build(gui) -- ofertas especiales: tarjetas a la derecha y pantalla al entrar
	windows = { inventoryWindow, shopWindow, dailyWindow, codesWindow, garageWindow, rankedWindow }
	-- Lo que senala el tutorial
	TutorialTargets.set("CoinsPill", coinsPill)
	TutorialTargets.set("GemsPill", gemsPill)
	TutorialTargets.set("CasesTile", casesButton)
	TutorialTargets.set("HomeTile", homeButton)
	TutorialTargets.set("InventoryTile", inventoryButton)
	TutorialTargets.set("InventoryWindow", inventoryWindow)
	TutorialTargets.set("ShopWindow", shopWindow)
	Tutorial.start(closeAll) -- (solo la primera vez que juegas)

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
	-- Cajas: la tienda en su pestana de cajas. Tienda: la pestana destacada.
	casesButton.Activated:Connect(function()
		toggle(shopWindow, function()
			ShopPanel.open("Cases")
		end)
	end)
	shopButton.Activated:Connect(function()
		toggle(shopWindow, function()
			ShopPanel.open("Featured")
		end)
	end)
	garageButton.Activated:Connect(function()
		toggle(garageWindow, GaragePanel.open)
	end)
	-- Los "+" de monedas y gemas llevan a la tienda (gemas con Robux y canje de monedas)
	for _, plus in { coinsPlus, gemsPlus } do
		plus.Activated:Connect(function()
			closeAll()
			ShopPanel.open()
		end)
	end
	dailyButton.Activated:Connect(function()
		toggle(dailyWindow, DailyPanel.open)
	end)
	codesButton.Activated:Connect(function()
		toggle(codesWindow, CodesPanel.open)
	end)
	homeButton.Activated:Connect(function()
		closeAll()
		Remotes.get("Notify"):FireServer("GoHome")
	end)

	-- Avisos del servidor
	Remotes.get("Notify").OnClientEvent:Connect(function(kind: string, text: string, extra: any)
		if kind == "PartyInvite" then
			return -- (la tarjeta de invitacion la pone RankedPanel)
		end
		if kind == "Unbox" and type(extra) == "table" then
			-- Premio especial de alguien del servidor: a "Ultimos premios" de la tienda; los Miticos y Secretos, a todos
			ShopPanel.addUnbox(extra)
			local rarity = EconomyMath.rarityOf(tostring(extra.Id))
			if (rarity.Income or 0) >= 1500 then
				toast("LevelUp", `📢 ¡{extra.Name} ha sacado {EconomyMath.entryOf(tostring(extra.Id)).Name} ({rarity.Name})!`)
			end
			return
		end
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
		incomeLabel.Text = `+{EconomyMath.format(income)}/s`
		tempLabel.Visible = data ~= nil and data.Temporary == true
		dailyDot.Visible = DailyPanel.canClaim()
		-- Puntito en Cajas si te llega para abrir la mas barata
		local cheapest = math.huge
		for _, case in Economy.Cases do
			cheapest = math.min(cheapest, case.Price)
		end
		casesDot.Visible = ClientData.gems() >= cheapest
	end
	for _, name in { "Gems", "Level", "XP", "XPNeed", "Income" } do
		player:GetAttributeChangedSignal(name):Connect(refreshHud)
	end
	ClientData.onChanged(refreshHud)
	refreshHud()

	local shownText = ""
	local hidden: boolean? = nil
	RunService.RenderStepped:Connect(function(dt: number)
		-- Las monedas suben con una pequena animacion (solo se formatea el numero mientras cambia)
		local target = ClientData.coins()
		if shownCoins ~= target then
			if math.abs(target - shownCoins) < 1 then
				shownCoins = target
			else
				shownCoins += (target - shownCoins) * math.min(1, dt * 8)
			end
			local text = EconomyMath.format(shownCoins)
			if shownText ~= text then
				shownText = text
				coinsLabel.Text = text
			end
		end
		local inMatch = MatchController.isInMatch()
		local folder = if inMatch then MatchController.getFolder() else nil
		local playground = folder ~= nil and folder:GetAttribute("Mode") == "Playground"
		local hide = inMatch and not playground
		if hide ~= hidden then
			hidden = hide
			side.Visible = not hide
			rightMenu.Visible = not hide
			GaragePanel.setHudVisible(not hide)
			RankedPanel.setHudVisible(not hide)
			OffersPanel.setHudVisible(not hide)
		end
		if hide then
			closeAll()
		end
	end)
end

return EconomyController
