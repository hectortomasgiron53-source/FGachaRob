--!strict
--[[
	CasesPanel: apertura de cajas estilo CS:GO. Las cajas se compran en la Tienda (pestanas Destacado y Cajas), que
	llama a CasesPanel.openCase(id, cantidad).
	- Se pueden abrir hasta Economy.MaxCasesAtOnce cajas a la vez: una tira de tarjetas por caja (mas pequenas cuantas
	  mas haya). Las tiras frenan poco a poco y se paran en el premio, una detras de otra.
	- El premio lo decide el servidor ANTES de girar; la tira solo lo ensena.
	- Saltar la animacion: Game Pass de pago unico (Economy.SkipSpinGamePassId). Con el pase, "Saltar" para todas las
	  ruletas de ahora en adelante; sin el, el boton ofrece comprarlo (y si lo compras a mitad, salta en ese momento).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)

local CasesPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make

local STRIP_COUNT = 44
local WIN_INDEX = 38 -- la tarjeta del premio
local VIEW_W = 860

local overlay: Frame
local spinning = false
local toast: (string, string) -> () = function() end
local changedCallbacks: { () -> () } = {}

-- Pase "Saltar animacion" (pago unico). Se comprueba una vez y se recuerda; al comprarlo se activa al momento.
local localPlayer = Players.LocalPlayer
local skipPassId: number = tonumber(Economy.SkipSpinGamePassId) or 0
local ownsSkip = false
local skipChecked = false
local currentSkip: (() -> ())? = nil -- salta las ruletas que estan girando

local function checkSkipPass()
	if skipChecked or skipPassId == 0 then
		return
	end
	skipChecked = true
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(localPlayer.UserId, skipPassId)
	end)
	ownsSkip = ok and owns == true
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, passId: number, purchased: boolean)
	if who == localPlayer and passId == skipPassId and purchased then
		ownsSkip = true
		local skipNow = currentSkip
		if skipNow then
			task.spawn(skipNow)
		end
	end
end)

local function playSound(name: string, volume: number?, pitch: number?)
	local entry = (Balance.Sounds :: any)[name]
	if type(entry) ~= "table" then
		return
	end
	local id = if entry.Id and entry.Id ~= "" then "rbxassetid://" .. tostring(entry.Id) else entry.Fallback
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = (entry.Volume or 0.5) * (volume or 1)
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Relleno de la tira: brainrots al azar con las probabilidades de la caja (para que se vea "justo")
local function randomRecord(case: any): any
	local rarity = EconomyMath.rollRarity(case, math.random())
	local entry = EconomyMath.pickOfRarity(rarity, math.random())
	return { Id = entry.Id, Variant = "Normal" }
end

local function isSpecial(result: any): boolean
	return (Brainrots.RarityIndex[result.Rarity] or 1) >= 4 or result.Variant ~= "Normal"
end

-- Avisa a la tienda (para activar o desactivar sus botones)
function CasesPanel.onChanged(callback: () -> ())
	table.insert(changedCallbacks, callback)
end
local function changed()
	for _, callback in changedCallbacks do
		task.spawn(callback)
	end
end

-- La capa de la ruleta / resultados esta abierta
function CasesPanel.isShowing(): boolean
	return overlay ~= nil and overlay.Visible
end

function CasesPanel.isSpinning(): boolean
	return spinning
end

-- Resumen al acabar: una tarjeta por premio, con "Abrir otra vez" y "Cerrar"
local function showResults(case: any, results: { any }, area: Frame)
	local count = #results
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.max(440, count * 156 + 40), 400),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 40,
	}, area)
	UiKit.corner(panel, 18)
	UiKit.stroke(panel, Colors.Ink, 5)
	make("UIGradient", { Color = ColorSequence.new(Colors.WindowTop, Colors.WindowBottom), Rotation = 90 }, panel)
	local best = results[1]
	for _, result in results do
		if (Brainrots.RarityIndex[result.Rarity] or 1) > (Brainrots.RarityIndex[best.Rarity] or 1) then
			best = result
		end
	end
	UiKit.textStroke(UiKit.label(panel, if count == 1 then "¡NUEVO BRAINROT!" else `¡{count} BRAINROTS NUEVOS!`, {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 36),
		TextColor3 = Colors.Yellow,
	}), 3)
	local row = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(count * 156, 230),
		BackgroundTransparency = 1,
	}, panel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
	}, row)
	for _, result in results do
		local card = UiKit.card(row, { Id = result.Id, Variant = result.Variant, Level = 1 }, Vector2.new(144, 186))
		UiKit.label(card, if result.Placed then "🏡 En tu granja" else "🎒 Al inventario", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 6),
			Size = UDim2.new(1, 0, 0, 16),
			TextColor3 = Colors.Muted,
		})
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if isSpecial(result) and stroke then
			stroke.Color = Colors.Yellow -- premio especial: borde dorado
			stroke.Thickness = 4
		end
	end
	local again = UiKit.button(panel, `Abrir otra vez x{count}  ·  💎 {EconomyMath.format(case.Price * count)}`, Colors.Purple, {
		Position = UDim2.new(0, 20, 1, -70),
		Size = UDim2.new(0.6, -26, 0, 52),
	})
	local close = UiKit.button(panel, "Cerrar", Colors.Red, {
		Position = UDim2.new(0.6, 6, 1, -70),
		Size = UDim2.new(0.4, -26, 0, 52),
	})
	UiKit.setEnabled(again, ClientData.gems() >= case.Price * count)
	UiKit.zindex(panel, 40)
	UiKit.pop(panel)
	again.Activated:Connect(function()
		if again.Active then
			CasesPanel.openCase(case.Id, count)
		end
	end)
	close.Activated:Connect(function()
		overlay.Visible = false
	end)
	playSound(if isSpecial(best) then "CaseRare" else "CaseReveal")
end

-- Ruletas: una tira por caja, todas a la vez; se van parando una detras de otra
local function spin(case: any, results: { any })
	for _, child in overlay:GetChildren() do
		child:Destroy()
	end
	overlay.Visible = true
	local count = #results
	local cardH = if count == 1 then 170 else math.floor(math.min(130, 520 / count - 14))
	local cardW = math.floor(cardH * 0.82)
	local step = cardW + 8
	local area = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(940, 680),
		BackgroundTransparency = 1,
		ZIndex = 30,
	}, overlay)
	UiKit.textStroke(UiKit.label(area, if count == 1 then `Abriendo {case.Name}...` else `Abriendo {count} x {case.Name}...`, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 44),
		TextColor3 = case.Color:Lerp(Color3.new(1, 1, 1), 0.3),
		ZIndex = 31,
	}), 3)
	local stack = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(VIEW_W, count * (cardH + 22)),
		BackgroundTransparency = 1,
		ZIndex = 31,
	}, area)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, stack)

	local strips: { { Strip: Frame, FinalX: number, Value: NumberValue, Tween: Tween } } = {}
	for index, result in results do
		local view = make("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(VIEW_W, cardH + 14),
			BackgroundColor3 = Colors.Chip,
			ClipsDescendants = true,
			ZIndex = 31,
		}, stack)
		UiKit.corner(view, 12)
		UiKit.stroke(view, Colors.Ink, 3)
		local strip = make("Frame", {
			Position = UDim2.fromOffset(0, 7),
			Size = UDim2.fromOffset(STRIP_COUNT * step, cardH),
			BackgroundTransparency = 1,
			ZIndex = 32,
		}, view)
		for i = 1, STRIP_COUNT do
			local record = if i == WIN_INDEX then { Id = result.Id, Variant = result.Variant } else randomRecord(case)
			local card = UiKit.card(strip, record, Vector2.new(cardW, cardH))
			card.Position = UDim2.fromOffset((i - 1) * step, 0)
		end
		UiKit.zindex(strip, 32)
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = Colors.Yellow,
			BorderSizePixel = 0,
			ZIndex = 35,
		}, view)
		for _, side in { 0, 1 } do
			local shadow = make("Frame", {
				AnchorPoint = Vector2.new(side, 0),
				Position = UDim2.fromScale(side, 0),
				Size = UDim2.new(0, 140, 1, 0),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
				ZIndex = 34,
			}, view)
			make("UIGradient", {
				Transparency = NumberSequence.new(if side == 0 then 0.1 else 1, if side == 0 then 1 else 0.1),
			}, shadow)
		end
		-- Donde tiene que acabar: el centro de la tarjeta ganadora (con un poco de azar) bajo la linea
		local jitter = (math.random() - 0.5) * (cardW - 20)
		local finalX = -((WIN_INDEX - 1) * step + cardW / 2 + jitter) + VIEW_W / 2
		local value = Instance.new("NumberValue")
		value.Value = 0
		-- Cada tira para un poco despues que la anterior (mas emocion)
		local duration = Economy.CaseSpinSeconds + (index - 1) * 0.45
		local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Value = finalX })
		table.insert(strips, { Strip = strip, FinalX = finalX, Value = value, Tween = tween })
	end

	-- Saltar: solo con el pase (si no lo tienes, el boton ofrece comprarlo). Sin pase configurado no aparece.
	local skip = UiKit.button(area, if ownsSkip then "⏩ Saltar" else "⏩ Saltar animaciones para siempre · R$", if ownsSkip then Colors.Blue else Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(if ownsSkip then 200 else 420, 50),
		ZIndex = 36,
		Visible = skipPassId ~= 0,
	})
	if not ownsSkip and skipPassId ~= 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(skipPassId, Enum.InfoType.GamePass)
			end)
			if ok and info and info.PriceInRobux and skip.Parent and not ownsSkip then
				skip.Text = `⏩ Saltar animaciones para siempre · {info.PriceInRobux} R$`
			end
		end)
	end

	-- "Clic" cada vez que una tarjeta pasa por la linea (de la primera tira)
	local lastIndex = -1
	local first = strips[1]
	local conn = RunService.RenderStepped:Connect(function()
		for _, s in strips do
			s.Strip.Position = UDim2.fromOffset(s.Value.Value, 7)
		end
		local index = math.floor((VIEW_W / 2 - first.Value.Value) / step)
		if index ~= lastIndex then
			lastIndex = index
			playSound("CaseTick", 0.6, 1 + math.random() * 0.1)
		end
	end)
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		currentSkip = nil
		conn:Disconnect()
		for _, s in strips do
			s.Tween:Cancel()
			s.Strip.Position = UDim2.fromOffset(s.FinalX, 7)
			s.Value:Destroy()
		end
		skip:Destroy()
		task.wait(0.5)
		spinning = false
		changed()
		for _, child in area:GetChildren() do
			if child ~= stack then
				child:Destroy()
			end
		end
		stack:Destroy()
		showResults(case, results, area)
	end
	skip.Activated:Connect(function()
		if ownsSkip then
			task.spawn(finish)
		else
			MarketplaceService:PromptGamePassPurchase(localPlayer, skipPassId)
		end
	end)
	-- Si compra el pase en mitad de la ruleta, se salta en ese momento
	currentSkip = function()
		if not finished then
			finish()
		end
	end
	strips[#strips].Tween.Completed:Connect(function()
		task.spawn(finish)
	end)
	for _, s in strips do
		s.Tween:Play()
	end
end

-- Ruleta de una caja que ya te han dado gratis (recompensa diaria): el servidor ya eligio los premios
function CasesPanel.showFree(caseId: string, results: { any })
	local case = EconomyMath.caseById(caseId)
	if spinning or not case or #results == 0 then
		return
	end
	spinning = true
	changed()
	spin(case, results)
end

-- Abre "count" cajas de golpe (lo pide la tienda)
function CasesPanel.openCase(caseId: string, count: number?)
	if spinning then
		return
	end
	local case = EconomyMath.caseById(caseId)
	if not case then
		return
	end
	task.spawn(checkSkipPass)
	local n = math.clamp(math.floor(count or 1), 1, Economy.MaxCasesAtOnce)
	spinning = true
	changed()
	local result = ClientData.request("OpenCase", caseId, n)
	if not result.Ok or type(result.Results) ~= "table" then
		spinning = false
		changed()
		toast("Warning", result.Error or "No se pudo abrir")
		return
	end
	spin(case, result.Results)
end

-- Crea la capa de la ruleta (por encima de todo)
function CasesPanel.build(parent: Instance, toastFn: (string, string) -> ())
	toast = toastFn
	overlay = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.25,
		Visible = false,
		Active = true,
		ZIndex = 30,
	}, parent)
	task.spawn(checkSkipPass)
end

return CasesPanel
