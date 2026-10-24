--!strict
--[[
	ShopPanel: la tienda (estilo tienda de simulador).
	- Izquierda: categorias con icono grande: Destacado, Cajas, Gemas (Robux), Canje (monedas -> gemas) y Vehiculos
	  (abre el Garaje).
	- Centro: lo de la categoria. Destacado: banner grande de la mejor caja (fondo arcoiris, sus mejores premios y
	  botones x1 / x5) y debajo las otras cajas. Las cajas se abren con CasesPanel (hasta 5 a la vez).
	- Derecha: "Ultimos premios" del servidor (brainrots Epicos o mejores, u Oro / Diamante, que acaba de sacar alguien).
	Los packs de Robux usan Economy.RobuxProducts (con ProductId = 0 salen desactivados). El canje cuesta lo que gana
	tu granja en un rato (Economy.Exchange): nunca sale barato.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local CasesPanel = require(script.Parent.CasesPanel)
local GaragePanel = require(script.Parent.GaragePanel)
local Offers = require(script.Parent.Offers)
local TutorialTargets = require(script.Parent.TutorialTargets)

local ShopPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local TABS = {
	{ Id = "Featured", Emoji = "⭐", Name = "Destacado", Color = Colors.Red },
	{ Id = "Cases", Emoji = "🎁", Name = "Cajas", Color = Colors.Purple },
	{ Id = "Gems", Emoji = "💎", Name = "Gemas", Color = Colors.Blue },
	{ Id = "Exchange", Emoji = "💰", Name = "Canje", Color = Colors.Teal },
	{ Id = "Vehicles", Emoji = "🛹", Name = "Vehículos", Color = Colors.Orange },
}

local window: Frame
local center: Frame
local feedList: Frame
local tabButtons: { [string]: TextButton } = {}
local tab = "Featured"
local caseButtons: { { Button: TextButton, Price: number } } = {}
local exchangeButtons: { { Button: TextButton, Offer: any } } = {}
local robuxPrices: { [number]: number } = {}
local recent: { any } = {} -- ultimos premios del servidor (el primero es el mas nuevo)
local caseBanners: { [string]: Frame } = {} -- (pestana Cajas) para poder llevar la vista a una caja
local casesList: ScrollingFrame? = nil
local toast: (string, string) -> () = function() end

local function refreshButtons()
	local gems = ClientData.gems()
	local busy = CasesPanel.isSpinning()
	for _, entry in caseButtons do
		if entry.Button.Parent then
			UiKit.setEnabled(entry.Button, not busy and gems >= entry.Price)
		end
	end
	local level = tonumber(player:GetAttribute("Level")) or 1
	for _, entry in exchangeButtons do
		if entry.Button.Parent then
			local cost = EconomyMath.exchangeCost(entry.Offer, level)
			entry.Button.Text = `Canjear · {EconomyMath.format(cost)}`
			UiKit.setEnabled(entry.Button, ClientData.coins() >= cost)
		end
	end
end

local function clearCenter()
	for _, child in center:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(caseButtons)
	table.clear(exchangeButtons)
end

-- ---------------------------------------------------------------------------
-- Banners de cajas
-- ---------------------------------------------------------------------------

-- Los mejores brainrots que pueden salir en una caja (para ensenarlos en el banner)
local function topRewards(case: any, count: number): { any }
	local list = {}
	for index = #Brainrots.Rarities, 1, -1 do
		local rarity = Brainrots.Rarities[index]
		if (case.Odds[rarity.Id] or 0) > 0 then
			for _, entry in Brainrots.ByRarity[rarity.Id] do
				if #list < count then
					table.insert(list, entry)
				end
			end
		end
	end
	return list
end

-- La "caja": un cubo de su color con una cinta y un regalo
local function caseBox(parent: Instance, case: any, size: number, position: UDim2)
	local box = make("Frame", {
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = case.Color,
		Rotation = -6,
	}, parent)
	UiKit.corner(box, 14)
	UiKit.stroke(box, Colors.Ink, 3.5)
	UiKit.gradient(box, 0.6)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.18, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, box)
	UiKit.emoji(box, "🎁", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
	})
end

-- Botones x1 y x5 de una caja ("xs": centro de cada boton, en fraccion del ancho del banner)
local function buyButtons(parent: Instance, case: any, y: number, width: number, xs: { number })
	for i, count in { 1, Economy.MaxCasesAtOnce } do
		local holder = make("Frame", {
			Position = UDim2.new(xs[i], -width / 2, 0, y),
			Size = UDim2.fromOffset(width, 74),
			BackgroundTransparency = 1,
		}, parent)
		UiKit.textStroke(UiKit.label(holder, `x{count}`, {
			Size = UDim2.new(1, 0, 0, 26),
		}), 2.5)
		local price = case.Price * count
		local button = UiKit.button(holder, `💎 {EconomyMath.format(price)}`, Colors.Yellow, {
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 46),
		})
		table.insert(caseButtons, { Button = button, Price = price })
		if case.Id == "Basica" and count == Economy.MaxCasesAtOnce then
			TutorialTargets.set("BasicX5", button) -- (el tutorial te pide abrir 5 basicas)
		end
		button.Activated:Connect(function()
			if button.Active then
				window.Visible = false
				CasesPanel.openCase(case.Id, count)
			end
		end)
	end
end

-- Banner de una caja. "big" = el destacado (fondo arcoiris que gira y premios a la vista)
local function caseBanner(parent: Instance, case: any, props: { [string]: any }, big: boolean)
	local banner = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
	}, parent)
	for key, value in props do
		(banner :: any)[key] = value
	end
	UiKit.corner(banner, 14)
	make("UIStroke", { Color = case.Color, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, banner)
	if big then
		-- Fondo arcoiris girando poco a poco
		local rainbow = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.6, 3),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, banner)
		local gradient = make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 50)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(250, 235, 80)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 220, 120)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 140, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 80, 255)),
			}),
		}, rainbow)
		TweenService:Create(gradient, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
		make("Frame", { -- velo oscuro: el texto se lee bien
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
		}, banner)
	else
		banner.BackgroundColor3 = case.Color
		UiKit.gradient(banner, 0.45)
	end
	UiKit.textStroke(UiKit.label(banner, case.Name, {
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(0.7, 0, 0, if big then 46 else 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if big then case.Color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1),
	}), 3)
	-- Probabilidad de lo mejor que puede salir
	local bestText = {}
	for index = #Brainrots.Rarities, 1, -1 do
		local rarity = Brainrots.Rarities[index]
		local odds = case.Odds[rarity.Id] or 0
		if odds > 0 and #bestText < (if big then 3 else 2) then
			table.insert(bestText, `{rarity.Name} {odds}%`)
		end
	end
	UiKit.label(banner, `¡Puede salir: {table.concat(bestText, " · ")}!`, {
		Position = UDim2.fromOffset(18, if big then 58 else 44),
		Size = UDim2.new(0.9, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Yellow,
	})
	if big then
		caseBox(banner, case, 110, UDim2.fromOffset(30, 96))
		-- Sus mejores premios a la vista
		local row = make("Frame", {
			Position = UDim2.fromOffset(170, 92),
			Size = UDim2.new(1, -180, 0, 120),
			BackgroundTransparency = 1,
		}, banner)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, row)
		for _, entry in topRewards(case, 4) do
			UiKit.card(row, { Id = entry.Id, Variant = "Normal" }, Vector2.new(96, 118))
		end
		buyButtons(banner, case, 222, 190, { 0.25, 0.75 })
	else
		caseBox(banner, case, 70, UDim2.fromOffset(18, 74))
		buyButtons(banner, case, 70, 100, { 0.52, 0.82 }) -- a la derecha de la caja
	end
	return banner
end

-- ---------------------------------------------------------------------------
-- Pestanas
-- ---------------------------------------------------------------------------

-- Oferta especial (Economy.Offers) en la pestana Destacado
local function offerBanner(parent: Instance, name: string, props: { [string]: any })
	local isStarter = name == "Starter"
	local offer = (Economy.Offers :: any)[name]
	local vehicle = if isStarter then nil else Vehicles.ById[offer.Vehicle]
	local card = make("Frame", { BackgroundColor3 = if isStarter then Color3.fromRGB(60, 200, 90) else Color3.fromRGB(255, 150, 30) }, parent)
	for key, value in props do
		(card :: any)[key] = value
	end
	UiKit.corner(card, 14)
	UiKit.stroke(card, Colors.Yellow, 4)
	UiKit.gradient(card, 0.55)
	UiKit.emoji(card, if isStarter then "🎁" else vehicle.Emoji, {
		Position = UDim2.fromOffset(12, 14),
		Size = UDim2.fromOffset(84, 84),
	})
	UiKit.textStroke(UiKit.label(card, if isStarter then "PACK DE BIENVENIDA" else `{vehicle.Name}`, {
		Position = UDim2.fromOffset(104, 12),
		Size = UDim2.new(1, -114, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	}), 2.5)
	UiKit.label(card, if isStarter then `💎 {EconomyMath.format(offer.Gems)} + 🪙 {EconomyMath.format(offer.Coins)} · {offer.Value} valor`
		else `Velocidad {vehicle.Speed} · ¡como uno de nivel 50!`, {
		Position = UDim2.fromOffset(104, 46),
		Size = UDim2.new(1, -114, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.label(card, if isStarter then `⏰ Termina en {Offers.formatLeft(Offers.starterSecondsLeft())} · solo una vez`
		else "Oferta de lanzamiento · solo una vez", {
		Position = UDim2.fromOffset(104, 70),
		Size = UDim2.new(1, -114, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Yellow,
	})
	local button = UiKit.button(card, `COMPRAR · {Offers.priceRich(name, if isStarter then 19 else 49)}`, Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 48),
		RichText = true, -- (precio real tachado)
	})
	button.Activated:Connect(function()
		Offers.buy(name)
	end)
end

local function renderFeatured()
	local cases = Economy.Cases
	-- Ofertas especiales arriba (si hay alguna a la venta para ti) y debajo las dos mejores cajas
	local offers = {}
	if Offers.starterAvailable() then
		table.insert(offers, "Starter")
	end
	if Offers.launchAvailable() then
		table.insert(offers, "LaunchVehicle")
	end
	if #offers > 0 then
		for i, name in offers do
			offerBanner(center, name, {
				Position = UDim2.new((i - 1) / #offers, if i > 1 then 6 else 0, 0, 0),
				Size = UDim2.new(1 / #offers, if #offers > 1 then -6 else 0, 0, 170),
			})
		end
		for i = 1, 2 do
			caseBanner(center, cases[#cases - i + 1], {
				Position = UDim2.new((i - 1) / 2, if i > 1 then 6 else 0, 0, 182),
				Size = UDim2.new(0.5, -6, 1, -182),
			}, false)
		end
		return
	end
	local featured = cases[#cases] -- la mejor caja
	caseBanner(center, featured, { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 310) }, true)
	local others = {}
	for i = #cases - 1, 1, -1 do
		table.insert(others, cases[i])
	end
	for i, case in others do
		caseBanner(center, case, {
			Position = UDim2.new((i - 1) / #others, if i > 1 then 6 else 0, 0, 322),
			Size = UDim2.new(1 / #others, -6, 1, -322),
		}, false)
	end
end

local function renderCases()
	local list = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, center)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i = #Economy.Cases, 1, -1 do
		local case = Economy.Cases[i]
		local banner = caseBanner(list, case, { LayoutOrder = #Economy.Cases - i, Size = UDim2.new(1, -12, 0, 184) }, false)
		caseBanners[case.Id] = banner
		casesList = list
		-- Todas las probabilidades
		local odds = {}
		for _, rarity in Brainrots.Rarities do
			local value = case.Odds[rarity.Id] or 0
			if value > 0 then
				table.insert(odds, `{rarity.Name} {value}%`)
			end
		end
		UiKit.label(banner, table.concat(odds, "  ·  "), {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 18, 1, -8),
			Size = UDim2.new(1, -36, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	local variants = {}
	for i = 2, #Brainrots.Variants do
		local v = Brainrots.Variants[i]
		table.insert(variants, `{v.Name} {v.Chance * 100}% (x{v.Income} monedas)`)
	end
	UiKit.label(list, "Cada brainrot puede salir en variante: " .. table.concat(variants, " · "), {
		LayoutOrder = 99,
		Size = UDim2.new(1, -12, 0, 18),
		TextColor3 = Colors.Muted,
	})
end

local function renderGems()
	local grid = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, center)
	make("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0.5, -8),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local colors = { Colors.Blue, Colors.Purple, Colors.Orange, Colors.Yellow }
	for i, product in Economy.RobuxProducts do
		local card = make("Frame", { LayoutOrder = i, BackgroundColor3 = colors[(i - 1) % #colors + 1] }, grid)
		UiKit.corner(card, 14)
		UiKit.stroke(card, Colors.Ink, 3.5)
		UiKit.gradient(card, 0.6)
		-- Diamantes (1 a 3 segun el pack), con la imagen de Economy.Icons
		local stack = math.min(i, 3)
		for k = 1, stack do
			UiKit.icon(card, "Gems", {
				Position = UDim2.new(0, 14 + (k - 1) * 34, 0, 14 + (if k == 2 then 18 else 0)),
				Size = UDim2.fromOffset(78, 78),
				ZIndex = 2 + k,
			})
		end
		UiKit.textStroke(UiKit.label(card, `{EconomyMath.format(product.Gems)} gemas`, {
			Position = UDim2.new(0.45, 0, 0, 22),
			Size = UDim2.new(0.53, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
		}), 3)
		UiKit.label(card, product.Label, {
			Position = UDim2.new(0.45, 0, 0, 66),
			Size = UDim2.new(0.53, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Colors.Yellow,
		})
		local price = robuxPrices[product.ProductId]
		local button = UiKit.button(card, if product.ProductId == 0 then "Sin configurar" elseif price then `COMPRAR · R$ {price}` else "COMPRAR", Colors.Green, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -24, 0, 50),
		})
		UiKit.setEnabled(button, product.ProductId ~= 0)
		button.Activated:Connect(function()
			if product.ProductId ~= 0 then
				MarketplaceService:PromptProductPurchase(player, product.ProductId)
			end
		end)
	end
end

local function renderExchange()
	UiKit.label(center, "Las gemas se ganan jugando partidos, en el diario o con Robux. También puedes canjear monedas por gemas: el precio sube con tu nivel de cuenta.", {
		Size = UDim2.new(1, 0, 0, 36),
		TextWrapped = true,
	})
	local row = make("Frame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
	}, center)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, row)
	for _, offer in Economy.Exchange do
		local card = make("Frame", { Size = UDim2.new(1 / #Economy.Exchange, -10, 1, -20), BackgroundColor3 = Colors.Teal }, row)
		UiKit.corner(card, 14)
		UiKit.stroke(card, Colors.Ink, 3.5)
		UiKit.gradient(card, 0.6)
		UiKit.icon(card, "Gems", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 20),
			Size = UDim2.fromOffset(90, 90),
		})
		UiKit.textStroke(UiKit.label(card, `{EconomyMath.format(offer.Gems)} gemas`, {
			Position = UDim2.fromOffset(8, 124),
			Size = UDim2.new(1, -16, 0, 38),
		}), 3)
		local level = tonumber(player:GetAttribute("Level")) or 1
		UiKit.label(card, `Precio de tu nivel {level}`, {
			Position = UDim2.fromOffset(8, 166),
			Size = UDim2.new(1, -16, 0, 20),
			TextColor3 = Colors.Yellow,
		})
		local button = UiKit.button(card, "Canjear", Colors.Green, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -24, 0, 50),
		})
		table.insert(exchangeButtons, { Button = button, Offer = offer })
		button.Activated:Connect(function()
			if not button.Active then
				return
			end
			local result = ClientData.request("Exchange", offer.Id)
			if result.Ok then
				toast("Reward", `+{result.Gems} gemas`)
			else
				toast("Warning", result.Error or "No se pudo")
			end
		end)
	end
end

local function selectTab(id: string)
	if id == "Vehicles" then
		window.Visible = false
		GaragePanel.open()
		return
	end
	tab = id
	for key, button in tabButtons do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if key == id then Colors.Yellow else Colors.Ink
			stroke.Thickness = if key == id then 5 else 3.5
		end
	end
	clearCenter()
	if id == "Featured" then
		renderFeatured()
	elseif id == "Cases" then
		renderCases()
	elseif id == "Gems" then
		renderGems()
	elseif id == "Exchange" then
		renderExchange()
	end
	UiKit.zindex(center, 11)
	refreshButtons()
end

-- ---------------------------------------------------------------------------
-- Ultimos premios
-- ---------------------------------------------------------------------------

local function renderFeed()
	if not feedList then
		return
	end
	for _, child in feedList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if #recent == 0 then
		UiKit.label(feedList, "Aún nadie ha sacado nada especial. ¡Sé el primero!", {
			Size = UDim2.new(1, 0, 0, 40),
			TextWrapped = true,
			TextColor3 = Colors.Muted,
		})
	end
	for order, pull in recent do
		local rarity = EconomyMath.rarityOf(pull.Id)
		local row = make("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 86),
			BackgroundColor3 = Colors.Chip,
			BackgroundTransparency = 0.15,
		}, feedList)
		UiKit.corner(row, 10)
		UiKit.stroke(row, rarity.Color, 2.5)
		UiKit.card(row, { Id = pull.Id, Variant = pull.Variant }, Vector2.new(66, 80)).Position = UDim2.fromOffset(3, 3)
		UiKit.label(row, pull.Name, {
			Position = UDim2.fromOffset(76, 6),
			Size = UDim2.new(1, -82, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		UiKit.label(row, EconomyMath.entryOf(pull.Id).Name, {
			Position = UDim2.fromOffset(76, 30),
			Size = UDim2.new(1, -82, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.3),
		})
		local ago = math.floor((os.clock() - (pull.At or os.clock())) / 60)
		UiKit.label(row, `{rarity.Name}{if pull.Variant ~= "Normal" then " · " .. pull.Variant else ""} · {if ago < 1 then "ahora" else `hace {ago} min`}`, {
			Position = UDim2.fromOffset(76, 54),
			Size = UDim2.new(1, -82, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Colors.Muted,
		})
	end
	UiKit.zindex(feedList, 11)
end

-- Llega un premio especial de alguien del servidor (lo manda EconomyController)
function ShopPanel.addUnbox(pull: any)
	if type(pull) ~= "table" or type(pull.Id) ~= "string" then
		return
	end
	pull.At = os.clock()
	table.insert(recent, 1, pull)
	while #recent > 6 do
		table.remove(recent)
	end
	if window and window.Visible then
		renderFeed()
	end
end

-- ---------------------------------------------------------------------------

function ShopPanel.build(parent: Instance, toastFn: (string, string) -> ())
	toast = toastFn
	local content
	window, content = UiKit.window(parent, "🛒 TIENDA", Vector2.new(1040, 620))

	-- Categorias (izquierda)
	local tabs = make("Frame", {
		Size = UDim2.new(0, 112, 1, 0),
		BackgroundTransparency = 1,
	}, content)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for order, spec in TABS do
		local button = UiKit.tile(tabs, spec.Emoji, spec.Name, spec.Color, {
			LayoutOrder = order,
			Size = UDim2.fromOffset(104, 98),
		})
		tabButtons[spec.Id] = button
		button.Activated:Connect(function()
			selectTab(spec.Id)
		end)
	end

	-- Centro
	local middle = UiKit.area(content, {
		Position = UDim2.fromOffset(124, 0),
		Size = UDim2.new(1, -124 - 256, 1, 0),
	})
	center = make("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -20),
		BackgroundTransparency = 1,
	}, middle)

	-- Ultimos premios (derecha)
	local right = UiKit.area(content, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 244, 1, 0),
	})
	UiKit.textStroke(UiKit.label(right, "📢 Últimos premios", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 28),
	}), 2.5)
	feedList = make("Frame", {
		Position = UDim2.fromOffset(8, 44),
		Size = UDim2.new(1, -16, 1, -52),
		BackgroundTransparency = 1,
	}, right)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, feedList)

	-- Precio real en Robux de cada pack (se pide a Roblox una vez)
	for _, product in Economy.RobuxProducts do
		if product.ProductId ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(product.ProductId, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					robuxPrices[product.ProductId] = info.PriceInRobux
					if window.Visible and tab == "Gems" then
						selectTab("Gems")
					end
				end
			end)
		end
	end

	for _, name in { "Coins", "Gems", "Income", "Level" } do
		player:GetAttributeChangedSignal(name):Connect(refreshButtons)
	end
	CasesPanel.onChanged(refreshButtons)
	-- Al comprar una oferta (o llegar su precio de Roblox) se rehace Destacado
	local function refreshOffers()
		if window.Visible and tab == "Featured" then
			selectTab("Featured")
		end
	end
	Offers.onPrice(refreshOffers)
	local offersShown = ""
	ClientData.onChanged(function()
		local now = `{Offers.starterAvailable()}{Offers.launchAvailable()}`
		if now ~= offersShown then
			offersShown = now
			refreshOffers()
		end
	end)
	UiKit.zindex(window, 10)
	selectTab("Featured")
	renderFeed()
	return window
end

-- Lleva la lista de la pestana Cajas hasta esa caja (lo usa el tutorial)
function ShopPanel.focusCase(caseId: string)
	local list = casesList
	local banner = caseBanners[caseId]
	if list and banner and banner.Parent then
		task.defer(function()
			local y = banner.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y - 8
			list.CanvasPosition = Vector2.new(0, math.max(0, y))
		end)
	end
end

-- Abre la tienda (opcionalmente en una categoria: "Featured", "Cases", "Gems", "Exchange", "Vehicles")
function ShopPanel.open(category: string?)
	if category == "Vehicles" then
		GaragePanel.open()
		return
	end
	window.Visible = true
	UiKit.pop(window)
	selectTab(category or tab)
	renderFeed()
end

return ShopPanel
