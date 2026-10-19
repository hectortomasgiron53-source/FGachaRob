--!strict
--[[
	CasesPanel: las cajas de brainrots (se abren con gemas) y la apertura estilo CS:GO:
	una tira de tarjetas pasa a toda velocidad por debajo de una linea dorada, frena poco a poco y se para en el
	premio. El premio lo decide el servidor ANTES de girar; la tira solo lo ensena.
]]
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

local CARD_W = 140
local CARD_H = 170
local GAP = 8
local STEP = CARD_W + GAP
local STRIP_COUNT = 44
local WIN_INDEX = 38 -- la tarjeta del premio

local window: Frame
local overlay: Frame
local openButtons: { [string]: TextButton } = {}
local spinning = false
local toast: (string, string) -> () = function() end

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

local function refreshButtons()
	local gems = ClientData.gems()
	for id, button in openButtons do
		local case = EconomyMath.caseById(id)
		UiKit.setEnabled(button, not spinning and case ~= nil and gems >= case.Price)
	end
end

local openCase: (string) -> ()

-- Muestra el premio despues de la ruleta
local function showResult(case: any, result: any, area: Frame)
	local entry = EconomyMath.entryOf(result.Id)
	local rarity = EconomyMath.rarityOf(result.Id)
	local variant = EconomyMath.variantOf(result.Variant)
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 430),
		BackgroundColor3 = Colors.Back,
		ZIndex = 40,
	}, area)
	UiKit.corner(panel, 16)
	UiKit.stroke(panel, rarity.Color, 3)
	make("UIGradient", { Color = ColorSequence.new(Colors.Back, rarity.Color:Lerp(Colors.Back, 0.5)), Rotation = 90 }, panel)
	UiKit.label(panel, if result.Variant ~= "Normal" then `¡{string.upper(variant.Name)}!` else "¡NUEVO BRAINROT!", {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 30),
		Font = Enum.Font.GothamBlack,
		TextColor3 = if result.Variant ~= "Normal" then variant.Color else Colors.Coins,
	})
	UiKit.viewport(panel, result.Id, result.Variant, {
		Position = UDim2.fromOffset(60, 50),
		Size = UDim2.fromOffset(300, 220),
	})
	UiKit.label(panel, entry.Name, {
		Position = UDim2.fromOffset(10, 274),
		Size = UDim2.new(1, -20, 0, 32),
		Font = Enum.Font.GothamBlack,
	})
	UiKit.label(panel, `{rarity.Name}{if result.Variant ~= "Normal" then " · " .. variant.Name else ""}  ·  +{EconomyMath.format(EconomyMath.income({ Id = result.Id, Level = 1, Variant = result.Variant }))} monedas/s`, {
		Position = UDim2.fromOffset(10, 308),
		Size = UDim2.new(1, -20, 0, 20),
		TextColor3 = rarity.Color,
	})
	UiKit.label(panel, if result.Placed then "Colocado en tu granja" else "Guardado en tu inventario (no hay pedestal libre)", {
		Position = UDim2.fromOffset(10, 332),
		Size = UDim2.new(1, -20, 0, 16),
		TextColor3 = Colors.Muted,
	})
	local again = UiKit.button(panel, `Abrir otra · {case.Price} gemas`, Colors.Purple, {
		Position = UDim2.new(0, 16, 1, -62),
		Size = UDim2.new(0.5, -22, 0, 44),
	})
	local close = UiKit.button(panel, "Cerrar", Colors.Panel2, {
		Position = UDim2.new(0.5, 6, 1, -62),
		Size = UDim2.new(0.5, -22, 0, 44),
	})
	UiKit.setEnabled(again, ClientData.gems() >= case.Price)
	UiKit.zindex(panel, 40)
	UiKit.pop(panel)
	again.Activated:Connect(function()
		if again.Active then
			openCase(case.Id)
		end
	end)
	close.Activated:Connect(function()
		overlay.Visible = false
	end)
	if (Brainrots.RarityIndex[result.Rarity] or 1) >= 4 or result.Variant ~= "Normal" then
		playSound("CaseRare")
	else
		playSound("CaseReveal")
	end
end

-- Ruleta
local function spin(case: any, result: any)
	for _, child in overlay:GetChildren() do
		child:Destroy()
	end
	overlay.Visible = true
	local area = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 520),
		BackgroundTransparency = 1,
		ZIndex = 30,
	}, overlay)
	UiKit.label(area, `Abriendo {case.Name}...`, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Enum.Font.GothamBlack,
		TextColor3 = case.Color,
		ZIndex = 31,
	})
	local view = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, CARD_H + 30),
		BackgroundColor3 = Colors.Back,
		ClipsDescendants = true,
		ZIndex = 31,
	}, area)
	UiKit.corner(view, 12)
	UiKit.stroke(view, case.Color, 2)
	local strip = make("Frame", {
		Position = UDim2.fromOffset(0, 15),
		Size = UDim2.fromOffset(STRIP_COUNT * STEP, CARD_H),
		BackgroundTransparency = 1,
		ZIndex = 32,
	}, view)
	for i = 1, STRIP_COUNT do
		local record = if i == WIN_INDEX then { Id = result.Id, Variant = result.Variant } else randomRecord(case)
		local card = UiKit.card(strip, record, Vector2.new(CARD_W, CARD_H))
		card.Position = UDim2.fromOffset((i - 1) * STEP, 0)
	end
	UiKit.zindex(strip, 32)
	-- Linea central y sombras de los lados
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Colors.Coins,
		BorderSizePixel = 0,
		ZIndex = 35,
	}, view)
	for _, side in { 0, 1 } do
		local shadow = make("Frame", {
			AnchorPoint = Vector2.new(side, 0),
			Position = UDim2.fromScale(side, 0),
			Size = UDim2.new(0, 160, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 34,
		}, view)
		make("UIGradient", {
			Transparency = NumberSequence.new(if side == 0 then 0.1 else 1, if side == 0 then 1 else 0.1),
		}, shadow)
	end
	local skip = UiKit.button(area, "Saltar", Colors.Panel2, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(160, 40),
		ZIndex = 36,
	})

	-- Donde tiene que acabar: el centro de la tarjeta ganadora (con un poco de azar) bajo la linea
	local viewWidth = 860
	local jitter = (math.random() - 0.5) * (CARD_W - 24)
	local finalX = -((WIN_INDEX - 1) * STEP + CARD_W / 2 + jitter) + viewWidth / 2
	local startX = 0
	local value = Instance.new("NumberValue")
	value.Value = startX
	local duration = Economy.CaseSpinSeconds
	local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Value = finalX })
	local lastIndex = -1
	local conn = RunService.RenderStepped:Connect(function()
		strip.Position = UDim2.fromOffset(value.Value, 15)
		-- "clic" cada vez que una tarjeta pasa por la linea
		local index = math.floor((viewWidth / 2 - value.Value) / STEP)
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
		tween:Cancel()
		conn:Disconnect()
		strip.Position = UDim2.fromOffset(finalX, 15)
		value:Destroy()
		skip:Destroy()
		task.wait(0.35)
		spinning = false
		refreshButtons()
		showResult(case, result, area)
	end
	skip.Activated:Connect(function()
		task.spawn(finish)
	end)
	tween.Completed:Connect(function()
		task.spawn(finish)
	end)
	tween:Play()
end

function openCase(caseId: string)
	if spinning then
		return
	end
	local case = EconomyMath.caseById(caseId)
	if not case then
		return
	end
	spinning = true
	refreshButtons()
	local result = ClientData.request("OpenCase", caseId)
	if not result.Ok then
		spinning = false
		refreshButtons()
		toast("Warning", result.Error or "No se pudo abrir")
		return
	end
	spin(case, result)
end

function CasesPanel.build(parent: Instance, toastFn: (string, string) -> ())
	toast = toastFn
	local content
	window, content = UiKit.window(parent, "CAJAS DE BRAINROTS", Vector2.new(900, 560))
	local count = #Economy.Cases
	for i, case in Economy.Cases do
		local card = make("Frame", {
			Position = UDim2.new((i - 1) / count, 6, 0, 0),
			Size = UDim2.new(1 / count, -12, 1, -34),
			BackgroundColor3 = Colors.Panel,
		}, content)
		UiKit.corner(card, 12)
		UiKit.stroke(card, case.Color, 2)
		make("UIGradient", { Color = ColorSequence.new(case.Color:Lerp(Colors.Panel, 0.55), Colors.Panel), Rotation = 90 }, card)
		-- La "caja"
		local box = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 16),
			Size = UDim2.fromOffset(110, 90),
			BackgroundColor3 = case.Color,
			Rotation = -4,
		}, card)
		UiKit.corner(box, 10)
		UiKit.stroke(box, Color3.new(1, 1, 1), 2, 0.4)
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.new(0, 18, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, box)
		UiKit.label(box, "?", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextTransparency = 0.1 })
		UiKit.label(card, case.Name, {
			Position = UDim2.fromOffset(8, 116),
			Size = UDim2.new(1, -16, 0, 28),
			Font = Enum.Font.GothamBlack,
		})
		UiKit.label(card, `{case.Price} gemas`, {
			Position = UDim2.fromOffset(8, 146),
			Size = UDim2.new(1, -16, 0, 20),
			TextColor3 = Colors.Gems,
		})
		-- Probabilidades
		local y = 178
		for _, rarity in Brainrots.Rarities do
			local odds = case.Odds[rarity.Id] or 0
			if odds > 0 then
				UiKit.label(card, rarity.Name, {
					Position = UDim2.fromOffset(18, y),
					Size = UDim2.new(0.6, -18, 0, 16),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = rarity.Color,
				})
				UiKit.label(card, `{odds}%`, {
					Position = UDim2.new(0.6, 0, 0, y),
					Size = UDim2.new(0.4, -18, 0, 16),
					TextXAlignment = Enum.TextXAlignment.Right,
				})
				y += 20
			end
		end
		local button = UiKit.button(card, "ABRIR", Colors.Purple, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, 46),
		})
		openButtons[case.Id] = button
		button.Activated:Connect(function()
			if button.Active then
				openCase(case.Id)
			end
		end)
	end
	local variants = {}
	for i = 2, #Brainrots.Variants do
		local v = Brainrots.Variants[i]
		table.insert(variants, `{v.Name} {v.Chance * 100}% (x{v.Income} monedas)`)
	end
	UiKit.label(content, "Cada brainrot puede salir en variante: " .. table.concat(variants, " · "), {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Colors.Muted,
	})
	UiKit.zindex(window, 10)

	-- Capa de la ruleta (por encima de todo)
	overlay = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.25,
		Visible = false,
		Active = true,
		ZIndex = 30,
	}, parent)

	ClientData.onChanged(refreshButtons)
	local player = game:GetService("Players").LocalPlayer
	player:GetAttributeChangedSignal("Gems"):Connect(refreshButtons)
	refreshButtons()
	return window
end

function CasesPanel.open()
	window.Visible = true
	UiKit.pop(window)
	refreshButtons()
end

return CasesPanel
