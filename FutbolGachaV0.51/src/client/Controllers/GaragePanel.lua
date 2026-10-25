--!strict
--[[
	GaragePanel: el Garaje (vehiculos) y el boton de montar.
	- Ventana: una fila por escalon (nivel de cuenta 1, 25, 50, 75, 100) con sus dos vehiculos: el de monedas y el de
	  gemas (mejor: mas rapido, salta mas, deja estela). Bloqueados hasta tener el nivel. Comprar / Elegir.
	- Boton "Montar (V)" abajo (si tienes un vehiculo elegido) y la tecla V: montar / bajar. En los partidos no sale.
	El servidor (VehicleService) decide todo.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local Offers = require(script.Parent.Offers)

local GaragePanel = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local MAX_SPEED = 42
local MAX_JUMP = 72

local window: Frame
local list: ScrollingFrame
local rideButton: TextButton
local hudAllowed = true
local toast: (string, string) -> () = function() end

local function act(action: string, a: any?): any
	local result = ClientData.request(action, a)
	if not result.Ok then
		toast("Warning", result.Error or "No se pudo")
	end
	return result
end

local function statBar(parent: Instance, y: number, text: string, value: number, max: number, color: Color3)
	UiKit.label(parent, text, {
		Position = UDim2.fromOffset(84, y),
		Size = UDim2.fromOffset(70, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local back = make("Frame", {
		Position = UDim2.fromOffset(156, y + 2),
		Size = UDim2.new(1, -166, 0, 10),
		BackgroundColor3 = Colors.Ink,
	}, parent)
	UiKit.corner(back, 5)
	local fill = make("Frame", {
		Size = UDim2.fromScale(math.clamp(value / max, 0.05, 1), 1),
		BackgroundColor3 = color,
	}, back)
	UiKit.corner(fill, 5)
end

local render: () -> ()

local function vehicleCard(parent: Instance, vehicle: Vehicles.Vehicle, data: any, level: number, order: number)
	local owned = data.Vehicles and data.Vehicles[vehicle.Id] == true
	local equipped = data.Vehicle == vehicle.Id
	local locked = level < vehicle.Level
	local card = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundColor3 = vehicle.Color:Lerp(Colors.Panel, 0.35),
	}, parent)
	UiKit.corner(card, 12)
	UiKit.stroke(card, if equipped then Colors.Yellow else Colors.Ink, if equipped then 4 else 3)
	UiKit.gradient(card, 0.65)
	UiKit.emoji(card, vehicle.Emoji, {
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.fromOffset(68, 68),
	})
	UiKit.textStroke(UiKit.label(card, vehicle.Name, {
		Position = UDim2.fromOffset(84, 8),
		Size = UDim2.new(1, -94, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	}), 2.2)
	statBar(card, 38, "Velocidad", vehicle.Speed, MAX_SPEED, Colors.Green)
	statBar(card, 56, "Salto", vehicle.Jump, MAX_JUMP, Colors.Blue)
	UiKit.label(card, vehicle.Description, {
		Position = UDim2.fromOffset(84, 74),
		Size = UDim2.new(1, -94, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
	})
	if vehicle.Currency == "Gems" then
		local best = make("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, -10),
			Size = UDim2.fromOffset(92, 22),
			BackgroundColor3 = Colors.Yellow,
			Rotation = 6,
		}, card)
		UiKit.corner(best, 6)
		UiKit.stroke(best, Colors.Ink, 2)
		UiKit.label(best, "⭐ MEJOR", { Size = UDim2.fromScale(1, 1) })
	end
	-- Boton de abajo: precio, elegir, elegido o bloqueado
	local text: string
	local color: Color3
	if locked then
		text, color = `🔒 Nivel {vehicle.Level}`, Colors.Chip
	elseif equipped then
		text, color = "✅ Elegido", Colors.Teal
	elseif owned then
		text, color = "Elegir", Colors.Blue
	elseif vehicle.Currency == "Robux" then
		text, color = `{UiKit.tr("Comprar")} · {Offers.priceRich("LaunchVehicle", vehicle.Price)}`, Colors.Green
	elseif vehicle.Currency == "Gems" then
		text, color = `Comprar · 💎 {EconomyMath.format(vehicle.Price)}`, Colors.Purple
	else
		text, color = `Comprar · {EconomyMath.format(vehicle.Price)} monedas`, Colors.Green
	end
	local button = UiKit.button(card, text, color, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 34),
		RichText = true, -- (precio real tachado en la oferta de lanzamiento)
	})
	if not locked and not equipped and not owned and vehicle.Currency == "Robux" then
		button.AutoLocalize = false -- (precio tachado: la traduccion automatica lo rompe; "Comprar" va con UiKit.tr)
	end
	local affordable = if vehicle.Currency == "Robux" then true elseif vehicle.Currency == "Gems" then ClientData.gems() >= vehicle.Price else ClientData.coins() >= vehicle.Price
	UiKit.setEnabled(button, not locked and not equipped and (owned or affordable))
	button.Activated:Connect(function()
		if not button.Active then
			return
		end
		if owned then
			act("EquipVehicle", vehicle.Id)
		elseif vehicle.Currency == "Robux" then
			Offers.buy("LaunchVehicle")
		else
			local result = act("BuyVehicle", vehicle.Id)
			if result.Ok then
				toast("Reward", `¡{vehicle.Emoji} {vehicle.Name} es tuyo! Pulsa V para montar`)
			end
		end
	end)
end

function render()
	if not window or not window.Visible then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local data = ClientData.get() or {}
	local level = tonumber(player:GetAttribute("Level")) or 1
	-- Oferta de lanzamiento (Robux): arriba del todo, si sigue a la venta o ya lo tienes
	for _, vehicle in Vehicles.List do
		local owned = data.Vehicles and data.Vehicles[vehicle.Id] == true
		if vehicle.Currency ~= "Robux" or (not owned and not Offers.launchAvailable()) then
			continue
		end
		local row = make("Frame", { LayoutOrder = 0, Size = UDim2.new(1, -12, 0, 172), BackgroundTransparency = 1 }, list)
		local badge = make("Frame", {
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.fromOffset(96, 120),
			BackgroundColor3 = Colors.Orange,
		}, row)
		UiKit.corner(badge, 12)
		UiKit.stroke(badge, Colors.Ink, 3)
		UiKit.gradient(badge, 0.7)
		UiKit.label(badge, "⚡", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 34) }):SetAttribute("NoStroke", true)
		UiKit.textStroke(UiKit.label(badge, "OFERTA", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 24) }), 2.5)
		UiKit.label(badge, "lanzamiento", { Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 18) })
		local pair = make("Frame", {
			Position = UDim2.fromOffset(108, 16),
			Size = UDim2.new(1, -108, 0, 152),
			BackgroundTransparency = 1,
		}, row)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }, pair)
		vehicleCard(pair, vehicle, data, level, 1)
	end
	for order, tier in Vehicles.Tiers do
		local row = make("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, -12, 0, 172),
			BackgroundTransparency = 1,
		}, list)
		local unlocked = level >= tier
		local badge = make("Frame", {
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.fromOffset(96, 120),
			BackgroundColor3 = if unlocked then Colors.Purple else Colors.Chip,
		}, row)
		UiKit.corner(badge, 12)
		UiKit.stroke(badge, Colors.Ink, 3)
		UiKit.gradient(badge, 0.7)
		UiKit.label(badge, if unlocked then "⭐" else "🔒", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 34),
		}):SetAttribute("NoStroke", true)
		UiKit.label(badge, "NIVEL", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 18) })
		UiKit.textStroke(UiKit.label(badge, tostring(tier), { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 32) }), 2.5)
		local pair = make("Frame", {
			Position = UDim2.fromOffset(108, 16),
			Size = UDim2.new(1, -108, 0, 152),
			BackgroundTransparency = 1,
		}, row)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, pair)
		for _, vehicle in Vehicles.List do
			if vehicle.Level == tier and vehicle.Currency ~= "Robux" then
				vehicleCard(pair, vehicle, data, level, if vehicle.Currency == "Coins" then 1 else 2)
			end
		end
	end
	UiKit.zindex(list, 11)
end

local function refreshRide()
	if not rideButton then
		return
	end
	local data = ClientData.get()
	local vehicle = if data then Vehicles.ById[data.Vehicle or ""] else nil
	local riding = player:GetAttribute("Riding") ~= nil
	local inMatch = player:GetAttribute("MatchId") ~= nil
	rideButton.Visible = hudAllowed and vehicle ~= nil and not inMatch
	if vehicle then
		rideButton.Text = if riding then `⬇️ Bajar (V)` else `{vehicle.Emoji} Montar (V)`
		rideButton.BackgroundColor3 = if riding then Colors.Red else Colors.Orange
	end
end

-- Postura montado: mientras vas en vehiculo no se anda (se cortan las animaciones de andar / correr del script
-- Animate y se queda de pie quieto); saltar y caer siguen igual. Solo el jugador local: su animacion se replica.
local rideConnection: RBXScriptConnection? = nil
local rideIdle: AnimationTrack? = nil

local function isWalkTrack(track: AnimationTrack, walkIds: { [string]: boolean }): boolean
	local name = track.Animation and track.Animation.Name or track.Name
	return walkIds[track.Animation and track.Animation.AnimationId or ""] == true or name == "WalkAnim" or name == "RunAnim"
end

local function setRidePose(on: boolean)
	if rideConnection then
		rideConnection:Disconnect()
		rideConnection = nil
	end
	if rideIdle then
		rideIdle:Stop(0.2)
		rideIdle = nil
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not on or not character or not animator then
		return
	end
	local walkIds: { [string]: boolean } = {}
	local idleAnim: Animation? = nil
	local animate = character:FindFirstChild("Animate")
	if animate then
		for _, kind in { "walk", "run" } do
			local folder = animate:FindFirstChild(kind)
			for _, a in if folder then folder:GetChildren() else {} do
				if a:IsA("Animation") then
					walkIds[a.AnimationId] = true
				end
			end
		end
		local idle = animate:FindFirstChild("idle")
		local first = if idle then idle:FindFirstChildOfClass("Animation") else nil
		idleAnim = first
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if isWalkTrack(track, walkIds) then
			track:Stop(0.15)
		end
	end
	rideConnection = animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		if isWalkTrack(track, walkIds) then
			track:Stop(0.15)
		end
	end)
	if idleAnim then
		local ok, track = pcall(function()
			return animator:LoadAnimation(idleAnim :: Animation)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Core
			track.Looped = true
			track:Play(0.2)
			rideIdle = track
		end
	end
end

local function toggleRide()
	local data = ClientData.get()
	if not data or not Vehicles.ById[data.Vehicle or ""] then
		toast("Info", "Compra un vehículo en el 🛹 Garaje")
		return
	end
	act("Ride")
end

-- Para el HUD: en los partidos se esconde
function GaragePanel.setHudVisible(visible: boolean)
	if hudAllowed ~= visible then
		hudAllowed = visible
		refreshRide()
	end
end

function GaragePanel.build(parent: Instance, toastFn: (string, string) -> ()): Frame
	toast = toastFn
	local content
	window, content = UiKit.window(parent, "🛹 GARAJE", Vector2.new(900, 600))
	UiKit.label(content, "Cada 25 niveles de cuenta se desbloquean vehículos nuevos. El de 💎 gemas es mucho mejor.", {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local area = UiKit.area(content, {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
	})
	list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 1, -12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, area)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UiKit.zindex(window, 10)

	-- Boton de montar (abajo, a la derecha del de jugar)
	rideButton = UiKit.button(parent, "Montar (V)", Colors.Orange, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 176, 1, -40),
		Size = UDim2.fromOffset(210, 60),
		Visible = false,
	})
	rideButton.Activated:Connect(toggleRide)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Vehicles.RideKey and player:GetAttribute("MatchId") == nil then
			toggleRide()
		end
	end)

	ClientData.onChanged(function()
		render()
		refreshRide()
	end)
	for _, name in { "Riding", "MatchId", "Level", "Coins", "Gems" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			refreshRide()
			if name == "Level" or name == "Gems" then
				render()
			end
		end)
	end
	player:GetAttributeChangedSignal("Riding"):Connect(function()
		setRidePose(player:GetAttribute("Riding") ~= nil)
	end)
	player.CharacterAdded:Connect(function()
		setRidePose(false)
	end)
	refreshRide()
	return window
end

function GaragePanel.open()
	window.Visible = true
	UiKit.pop(window)
	render()
end

return GaragePanel
