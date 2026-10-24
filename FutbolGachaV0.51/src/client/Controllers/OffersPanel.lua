--!strict
--[[
	OffersPanel: las ofertas especiales a la vista (Economy.Offers; la logica en Offers.lua).
	- A la derecha de la pantalla: una tarjeta grande y animada por oferta disponible (pack de bienvenida con su
	  cuenta atras y vehiculo de lanzamiento). Al pulsarla se abre la pantalla de ofertas.
	- Pantalla de ofertas: sale SOLA al entrar al juego (una vez por sesion, si hay alguna oferta) con las dos
	  ofertas y su boton de comprar.
	Durante los partidos no se ve nada de esto.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local MatchController = require(script.Parent.MatchController)
local Offers = require(script.Parent.Offers)

local OffersPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make

local STARTER_COLOR = Color3.fromRGB(60, 200, 90)
local LAUNCH_COLOR = Color3.fromRGB(255, 150, 30)

local side: Frame
local promo: Frame
local promoBody: Frame
local hudAllowed = true
local starterTimers: { TextLabel } = {} -- (los de la pantalla de ofertas: se rehacen al abrirla)
local sideTimer: TextLabel? = nil
local priceButtons: { { Button: TextButton, Name: string, Fallback: number } } = {}

local starter = (Economy.Offers :: any).Starter
local launch = (Economy.Offers :: any).LaunchVehicle
local launchVehicle = Vehicles.ById[launch.Vehicle]

local function priceText(name: string, fallback: number): string
	return `COMPRAR · {Offers.priceRich(name, fallback)}` -- (con el precio real tachado)
end

-- Etiqueta inclinada ("x6 VALOR", "LANZAMIENTO")
local function ribbon(parent: Instance, text: string, color: Color3, props: { [string]: any })
	local tag = make("Frame", { BackgroundColor3 = color, Rotation = 8 }, parent)
	for key, value in props do
		(tag :: any)[key] = value
	end
	UiKit.corner(tag, 8)
	UiKit.stroke(tag, Colors.Ink, 2.5)
	UiKit.label(tag, text, { Size = UDim2.fromScale(1, 1) })
end

-- Latido suave (llama la atencion sin molestar)
local function pulse(gui: GuiObject, amount: number)
	local scale = make("UIScale", {}, gui)
	TweenService:Create(scale, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1 + amount }):Play()
end

-- Brillo que cruza la tarjeta de vez en cuando
local function shine(card: GuiObject)
	local glare = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
	}, card)
	UiKit.corner(glare, 14)
	local gradient = make("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	}, glare)
	task.spawn(function()
		while card.Parent do
			gradient.Offset = Vector2.new(-1, 0)
			local tween = TweenService:Create(gradient, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Offset = Vector2.new(1, 0) })
			tween:Play()
			tween.Completed:Wait()
			task.wait(2.5)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Pantalla de ofertas
-- ---------------------------------------------------------------------------

local function offerColumn(parent: Instance, name: string, x: number, width: number)
	local isStarter = name == "Starter"
	local color = if isStarter then STARTER_COLOR else LAUNCH_COLOR
	local column = make("Frame", {
		Position = UDim2.new(x, if x > 0 then 8 else 0, 0, 0),
		Size = UDim2.new(width, if x > 0 or width < 1 then -8 else 0, 1, 0),
		BackgroundColor3 = color,
	}, parent)
	UiKit.corner(column, 16)
	UiKit.stroke(column, Colors.Ink, 4)
	UiKit.gradient(column, 0.55)
	shine(column)
	UiKit.emoji(column, if isStarter then "🎁" else launchVehicle.Emoji, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(92, 92),
	})
	UiKit.textStroke(UiKit.label(column, if isStarter then "PACK DE BIENVENIDA" else launchVehicle.Name:upper(), {
		Position = UDim2.fromOffset(10, 106),
		Size = UDim2.new(1, -20, 0, 32),
	}), 3)
	local lines = if isStarter
		then { `💎 {EconomyMath.format(starter.Gems)} gemas`, `🪙 {EconomyMath.format(starter.Coins)} monedas`, "¡Solo para jugadores nuevos!" }
		else { `Velocidad {launchVehicle.Speed} · Salto {launchVehicle.Jump}`, "¡Como un hoverboard de nivel 50!", "Desde el nivel 1 · con estela de luz" }
	for i, line in lines do
		UiKit.label(column, line, {
			Position = UDim2.fromOffset(10, 140 + (i - 1) * 26),
			Size = UDim2.new(1, -20, 0, 22),
			TextColor3 = if i == 3 then Colors.Yellow else Colors.Text,
		})
	end
	if isStarter then
		local timer = UiKit.label(column, "", {
			Position = UDim2.fromOffset(10, 222),
			Size = UDim2.new(1, -20, 0, 20),
			TextColor3 = Colors.Yellow,
		})
		table.insert(starterTimers, timer)
	end
	local off = Offers.discount(name, if isStarter then 19 else 49)
	local tag = if isStarter then `{starter.Value} VALOR` else "LANZAMIENTO"
	ribbon(column, if off > 0 then `-{off}% · {tag}` else tag, if isStarter then Colors.Red else Colors.Purple, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -10),
		Size = UDim2.fromOffset(if off > 0 then 190 else 140, 32),
	})
	local button = UiKit.button(column, priceText(name, if isStarter then 19 else 49), Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -30, 0, 54),
	})
	button.RichText = true
	pulse(button, 0.05)
	table.insert(priceButtons, { Button = button, Name = name, Fallback = if isStarter then 19 else 49 })
	button.Activated:Connect(function()
		Offers.buy(name)
	end)
end

local function hidePromo()
	if promo then
		promo.Visible = false
	end
end

function OffersPanel.openPromo()
	local list = {}
	if Offers.starterAvailable() then
		table.insert(list, "Starter")
	end
	if Offers.launchAvailable() then
		table.insert(list, "LaunchVehicle")
	end
	if #list == 0 then
		return
	end
	for _, child in promoBody:GetChildren() do
		child:Destroy()
	end
	table.clear(starterTimers)
	table.clear(priceButtons)
	for i, name in list do
		offerColumn(promoBody, name, (i - 1) / #list, 1 / #list)
	end
	promo.Size = UDim2.fromOffset(if #list == 2 then 700 else 400, 470)
	UiKit.zindex(promo, 55)
	promo.Visible = true
	UiKit.pop(promo)
end

local function buildPromo(parent: Instance)
	promo = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4), -- (algo por encima del centro)
		Size = UDim2.fromOffset(700, 470),
		BackgroundColor3 = Colors.Back,
		Visible = false,
		ZIndex = 55,
	}, parent)
	UiKit.corner(promo, 20)
	UiKit.stroke(promo, Colors.Yellow, 5)
	UiKit.gradient(promo, 0.6)
	UiKit.textStroke(UiKit.label(promo, "🎉 ¡OFERTAS DE LANZAMIENTO!", {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -40, 0, 42),
		TextColor3 = Colors.Yellow,
	}), 3)
	UiKit.label(promo, "Solo se pueden comprar una vez. ¡No te las pierdas!", {
		Position = UDim2.fromOffset(20, 54),
		Size = UDim2.new(1, -40, 0, 20),
		TextColor3 = Colors.Muted,
	})
	promoBody = make("Frame", {
		Position = UDim2.fromOffset(20, 86),
		Size = UDim2.new(1, -40, 1, -150),
		BackgroundTransparency = 1,
	}, promo)
	local later = UiKit.button(promo, "Ahora no", Colors.Red, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(180, 42),
	})
	later.Activated:Connect(hidePromo)
end

-- ---------------------------------------------------------------------------
-- Tarjetas de la derecha
-- ---------------------------------------------------------------------------

local function sideCard(name: string, order: number): TextButton
	local isStarter = name == "Starter"
	local card = make("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(250, 104),
		BackgroundColor3 = if isStarter then STARTER_COLOR else LAUNCH_COLOR,
		AutoButtonColor = false,
		Text = "",
	}, side)
	UiKit.corner(card, 14)
	UiKit.stroke(card, Colors.Ink, 3.5)
	UiKit.gradient(card, 0.6)
	shine(card)
	pulse(card, 0.03)
	UiKit.emoji(card, if isStarter then "🎁" else launchVehicle.Emoji, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(70, 70),
	})
	UiKit.textStroke(UiKit.label(card, if isStarter then "PACK BIENVENIDA" else "¡LANZAMIENTO!", {
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -88, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	}), 2.5)
	UiKit.label(card, if isStarter then `💎 {EconomyMath.format(starter.Gems)} + 🪙 {EconomyMath.format(starter.Coins)}` else launchVehicle.Name, {
		Position = UDim2.fromOffset(80, 36),
		Size = UDim2.new(1, -88, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local bottom = UiKit.label(card, "", {
		Position = UDim2.fromOffset(80, 60),
		Size = UDim2.new(1, -88, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Yellow,
	})
	if isStarter then
		sideTimer = bottom
	else
		bottom.Text = "¡Corre más que nadie desde el nivel 1!"
	end
	local price = UiKit.label(card, "", {
		Position = UDim2.fromOffset(80, 80),
		Size = UDim2.new(1, -88, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true, -- (precio real tachado)
	})
	local function refreshPrice()
		price.Text = `{Offers.priceRich(name, if isStarter then 19 else 49)} · ¡una vez!`
	end
	refreshPrice()
	Offers.onPrice(refreshPrice)
	ribbon(card, if isStarter then starter.Value else "NUEVO", Colors.Red, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -8),
		Size = UDim2.fromOffset(62, 26),
	})
	card.Activated:Connect(OffersPanel.openPromo)
	return card
end

local function refreshSide()
	local starterCard = side:FindFirstChild("Starter") :: GuiObject?
	local launchCard = side:FindFirstChild("LaunchVehicle") :: GuiObject?
	if starterCard then
		starterCard.Visible = Offers.starterAvailable()
	end
	if launchCard then
		launchCard.Visible = Offers.launchAvailable()
	end
	side.Visible = hudAllowed
	-- Comprada la ultima oferta de la pantalla: se cierra
	if promo.Visible and not Offers.starterAvailable() and not Offers.launchAvailable() then
		hidePromo()
	end
end

function OffersPanel.setHudVisible(visible: boolean)
	if hudAllowed ~= visible then
		hudAllowed = visible
		if not visible then
			hidePromo()
		end
		refreshSide()
	end
end

function OffersPanel.build(parent: ScreenGui)
	-- A la derecha, debajo de los menus de arriba
	side = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.fromOffset(250, 240),
		BackgroundTransparency = 1,
	}, parent)
	make("UIListLayout", { Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	sideCard("Starter", 1)
	sideCard("LaunchVehicle", 2)
	UiKit.zindex(side, 4)
	buildPromo(parent)

	ClientData.onChanged(refreshSide)
	Offers.onPrice(function()
		for _, entry in priceButtons do
			if entry.Button.Parent then
				entry.Button.Text = priceText(entry.Name, entry.Fallback)
			end
		end
	end)
	-- Cuenta atras del pack de bienvenida (y se esconde al acabar)
	task.spawn(function()
		while true do
			local left = Offers.starterSecondsLeft()
			for _, timer in starterTimers do
				if timer.Parent then
					timer.Text = `⏰ Termina en {Offers.formatLeft(left)}`
				end
			end
			if sideTimer then
				sideTimer.Text = `⏰ Termina en {Offers.formatLeft(left)}`
			end
			if left <= 0 then
				refreshSide()
			end
			task.wait(1)
		end
	end)
	-- Al entrar: la pantalla de ofertas sale sola (una vez), cuando ya han llegado tus datos y no estas jugando
	task.spawn(function()
		local waited = 0
		while not ClientData.get() and waited < 30 do
			task.wait(0.5)
			waited += 0.5
		end
		task.wait(3)
		-- (si aun no ha hecho el tutorial, la abre el tutorial al terminar)
		local data = ClientData.get()
		local tutorialPending = data ~= nil and (tonumber(data.Tutorial) or 100) < 100
		if not MatchController.isInMatch() and not tutorialPending then
			OffersPanel.openPromo()
		end
	end)
	refreshSide()
end

return OffersPanel
