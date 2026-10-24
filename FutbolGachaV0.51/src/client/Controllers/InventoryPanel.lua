--!strict
--[[
	InventoryPanel: tus brainrots y tu equipo.
	- Arriba: los 4 puestos del equipo (1 Delantero = tu, 2 Medio, 3 Defensa; el 4, Portero, es fijo y no se elige).
	- Izquierda: todos tus brainrots (ordenados por calidad, nivel o los mas nuevos).
	- Derecha: el seleccionado: estadisticas, monedas por segundo, subir de nivel, granja, equipo y vender.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)

local InventoryPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make

local POSITIONS = { "Delantero (tú)", "Medio", "Defensa", "Portero" }
local STAT_LABELS = {
	Speed = "Velocidad",
	Shooting = "Tiro",
	Passing = "Pase",
	Dribbling = "Regate",
	Defense = "Defensa",
	Stamina = "Resistencia",
	Goalkeeping = "Portería",
}

local window: Frame
local grid: ScrollingFrame
local countLabel: TextLabel
local detail: Frame
local teamSlots: { Frame } = {}
local selected: string? = nil
local tutorialMode = false -- (tutorial) solo se ven los botones de los puestos que quedan libres
local teamButtons: { [number]: TextButton } = {}
local sortMode = "Calidad"
local sellArmed: string? = nil
local toast: (string, string) -> () = function() end
-- Botones de subir de nivel del brainrot elegido: se activan solos cuando llegas a las monedas (las monedas suben solas)
local levelRefs: { { Button: TextButton, Cost: number? } } = {}

local function sortedUids(data: any): { string }
	local list = {}
	for uid in data.Brainrots do
		table.insert(list, uid)
	end
	table.sort(list, function(a, b)
		local ra, rb = data.Brainrots[a], data.Brainrots[b]
		if sortMode == "Nuevos" then
			if ra.Got ~= rb.Got then
				return ra.Got > rb.Got
			end
		elseif sortMode == "Nivel" then
			if ra.Level ~= rb.Level then
				return ra.Level > rb.Level
			end
		end
		local ia = Brainrots.RarityIndex[EconomyMath.entryOf(ra.Id).Rarity] or 0
		local ib = Brainrots.RarityIndex[EconomyMath.entryOf(rb.Id).Rarity] or 0
		if ia ~= ib then
			return ia > ib
		end
		local va = EconomyMath.income(ra)
		local vb = EconomyMath.income(rb)
		if va ~= vb then
			return va > vb
		end
		return a < b
	end)
	return list
end

local function farmSlotOf(data: any, uid: string): number?
	for slot, other in data.Farm do
		if other == uid then
			return tonumber(slot)
		end
	end
	return nil
end

local function teamSlotOf(data: any, uid: string): number?
	for i = 1, 4 do
		if data.Team[i] == uid then
			return i
		end
	end
	return nil
end

local function act(action: string, a: any?, b: any?)
	local result = ClientData.request(action, a, b)
	if not result.Ok then
		toast("Warning", result.Error or "No se pudo")
	end
	return result
end

local renderDetail: () -> ()

local function renderTeam(data: any)
	for i, slotFrame in teamSlots do
		for _, child in slotFrame:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "Title" then
				child:Destroy()
			end
		end
		if i == 4 then
			-- Portero: siempre el mismo para todos, no se elige
			UiKit.label(slotFrame, "🧤 Portero fijo", {
				Position = UDim2.fromOffset(8, 22),
				Size = UDim2.new(1, -16, 0, 20),
			})
			UiKit.label(slotFrame, "igual para todos los equipos", {
				Position = UDim2.fromOffset(8, 44),
				Size = UDim2.new(1, -16, 0, 14),
				TextColor3 = Colors.Muted,
			})
			UiKit.zindex(slotFrame, 11)
			continue
		end
		local uid = data.Team[i]
		local record = if uid ~= "" then data.Brainrots[uid] else nil
		if record then
			local entry = EconomyMath.entryOf(record.Id)
			local rarity = EconomyMath.rarityOf(record.Id)
			UiKit.viewport(slotFrame, record.Id, record.Variant, {
				Position = UDim2.fromOffset(4, 18),
				Size = UDim2.fromOffset(46, 46),
			}, EconomyMath.evolutionOf(record.Level))
			UiKit.label(slotFrame, entry.Name, {
				Position = UDim2.fromOffset(54, 22),
				Size = UDim2.new(1, -58, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBlack,
			})
			UiKit.label(slotFrame, `{rarity.Name} · Nv {record.Level}{EconomyMath.evolutionTag(record.Level)} · {EconomyMath.overall(record)} MED`, {
				Position = UDim2.fromOffset(54, 42),
				Size = UDim2.new(1, -58, 0, 14),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = rarity.Color,
			})
		else
			UiKit.label(slotFrame, "Vacío (juega un suplente)", {
				Position = UDim2.fromOffset(8, 28),
				Size = UDim2.new(1, -16, 0, 18),
				TextColor3 = Colors.Muted,
			})
		end
		local click = make("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 15,
		}, slotFrame)
		click.Activated:Connect(function()
			if record then
				selected = uid
				renderDetail()
			end
		end)
		UiKit.zindex(slotFrame, 11)
		click.ZIndex = 15
	end
end

-- Tarjetas ya creadas (por uid). Cada tarjeta lleva un modelo 3D: rehacerlas todas en cada clic era muy caro con
-- muchos brainrots, asi que solo se rehace la que cambia (nivel, variante, granja o equipo).
type CardEntry = { Frame: Frame, Key: string, Stroke: UIStroke?, BaseColor: Color3, BaseThickness: number }
local cards: { [string]: CardEntry } = {}

local function tagsOf(data: any, uid: string): string
	local tags = {}
	if farmSlotOf(data, uid) then
		table.insert(tags, "Granja")
	end
	local t = teamSlotOf(data, uid)
	if t then
		table.insert(tags, `Equipo {t}`)
	end
	return table.concat(tags, " · ")
end

-- Marca la tarjeta elegida (borde blanco) sin rehacer nada
local function styleSelection()
	for uid, entry in cards do
		local stroke = entry.Stroke
		if stroke then
			local isSelected = uid == selected
			stroke.Color = if isSelected then Color3.new(1, 1, 1) else entry.BaseColor
			stroke.Thickness = if isSelected then 3 else entry.BaseThickness
		end
	end
end

local function renderGrid(data: any)
	local list = sortedUids(data)
	local alive: { [string]: boolean } = {}
	for order, uid in list do
		alive[uid] = true
		local record = data.Brainrots[uid]
		local tags = tagsOf(data, uid)
		local key = `{record.Id}|{record.Level}|{record.Variant}|{tags}`
		local entry = cards[uid]
		if entry and entry.Key ~= key then
			entry.Frame:Destroy()
			entry = nil
		end
		if not entry then
			local card = UiKit.card(grid, record, Vector2.new(112, 140))
			if tags ~= "" then
				local tag = UiKit.label(card, tags, {
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.new(1, -8, 0, 14),
					BackgroundTransparency = 0.25,
					BackgroundColor3 = Colors.Back,
					TextColor3 = Colors.Coins,
				})
				UiKit.corner(tag, 4)
			end
			local click = make("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
			}, card)
			click.Activated:Connect(function()
				selected = uid
				sellArmed = nil
				styleSelection()
				renderDetail()
			end)
			UiKit.zindex(card, 11)
			card.ZIndex = math.max(card.ZIndex, 11)
			local stroke = card:FindFirstChildOfClass("UIStroke")
			entry = {
				Frame = card,
				Key = key,
				Stroke = stroke,
				BaseColor = if stroke then stroke.Color else Colors.Line,
				BaseThickness = if stroke then stroke.Thickness else 2,
			}
			cards[uid] = entry
		end
		(entry :: CardEntry).Frame.LayoutOrder = order
	end
	for uid, entry in cards do
		if not alive[uid] then
			entry.Frame:Destroy()
			cards[uid] = nil
		end
	end
	countLabel.Text = `Mis brainrots ({#list}/{Economy.Brainrot.MaxInventory})`
	styleSelection()
end

function renderDetail()
	levelRefs = {}
	for _, child in detail:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local data = ClientData.get()
	local record = if data and selected then data.Brainrots[selected] else nil
	if not record or not selected then
		UiKit.label(detail, "Elige un brainrot", {
			Position = UDim2.fromScale(0, 0.4),
			Size = UDim2.new(1, 0, 0, 24),
			TextColor3 = Colors.Muted,
		})
		UiKit.zindex(detail, 11)
		return
	end
	local uid = selected :: string
	local entry = EconomyMath.entryOf(record.Id)
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)

	UiKit.viewport(detail, record.Id, record.Variant, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 120),
	}, EconomyMath.evolutionOf(record.Level))
	local evolution = EconomyMath.evolution(record.Level)
	UiKit.label(detail, if evolution then `{entry.Name} {evolution.Tag}` else entry.Name, {
		Position = UDim2.fromOffset(0, 122),
		Size = UDim2.new(1, 0, 0, 24),
		Font = Enum.Font.GothamBlack,
	})
	UiKit.label(detail, `{rarity.Name}{if record.Variant ~= "Normal" then " · " .. variant.Name else ""} · Fama {entry.Fame} · Puesto ideal: {entry.Role}`, {
		Position = UDim2.fromOffset(0, 147),
		Size = UDim2.new(1, 0, 0, 15),
		TextColor3 = if record.Variant ~= "Normal" then variant.Color else rarity.Color,
	})
	UiKit.label(detail, `Nivel {record.Level}/{Economy.Brainrot.MaxLevel}  ·  +{EconomyMath.format(EconomyMath.income(record))} monedas/s  ·  {EconomyMath.overall(record)} MED`, {
		Position = UDim2.fromOffset(0, 164),
		Size = UDim2.new(1, 0, 0, 15),
		TextColor3 = Colors.Coins,
	})
	-- Evolucion: la que tiene y la siguiente
	local nextEvolution = EconomyMath.nextEvolution(record.Level)
	local evolutionText = if nextEvolution
		then `{if evolution then evolution.Name .. " · " else ""}Evoluciona a nivel {nextEvolution.Level}: más grande y x{nextEvolution.Income} monedas`
		else `{if evolution then evolution.Name else ""} · Evolución final`
	UiKit.label(detail, evolutionText, {
		Position = UDim2.fromOffset(0, 180),
		Size = UDim2.new(1, 0, 0, 13),
		TextColor3 = Colors.Purple,
	})
	-- Estadisticas (el nivel las cambia poco: sobre todo da monedas)
	local stats = EconomyMath.stats(record)
	for i, name in EconomyMath.StatNames do
		local y = 197 + (i - 1) * 14
		UiKit.label(detail, STAT_LABELS[name], {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(0.38, 0, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Colors.Muted,
			Font = Enum.Font.GothamMedium,
		})
		local back = make("Frame", {
			Position = UDim2.new(0.4, 0, 0, y + 2),
			Size = UDim2.new(0.5, 0, 0, 9),
			BackgroundColor3 = Colors.Panel2,
		}, detail)
		UiKit.corner(back, 4)
		local fill = make("Frame", {
			Size = UDim2.new(stats[name] / 100, 0, 1, 0),
			BackgroundColor3 = rarity.Color,
		}, back)
		UiKit.corner(fill, 4)
		UiKit.label(detail, tostring(stats[name]), {
			Position = UDim2.new(0.92, 0, 0, y),
			Size = UDim2.new(0.08, 0, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end

	-- Botones: subir 1 nivel o varios de golpe (+10)
	local y = 298
	levelRefs = {}
	local manyCount = Economy.Brainrot.MaxLevelsPerClick
	for index, count in { 1, manyCount } do
		local cost, levels = EconomyMath.levelCostMany(record, count)
		local text = if levels == 0
			then "Nivel máximo"
			else `{if count == 1 then "Subir nivel" else `+{levels} niveles`} · {EconomyMath.format(cost)}`
		local button = UiKit.button(detail, text, if index == 1 then Colors.Green else Color3.fromRGB(40, 150, 80), {
			Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 3, 0, y),
			Size = UDim2.new(0.5, -3, 0, 30),
		})
		local need: number? = if levels > 0 then cost else nil
		UiKit.setEnabled(button, need ~= nil and ClientData.coins() >= (need :: number))
		table.insert(levelRefs, { Button = button, Cost = need })
		button.Activated:Connect(function()
			if not button.Active then
				return
			end
			local result = act("LevelUp", uid, count)
			if result.Ok and result.Evolved then
				local reached = EconomyMath.evolution(tonumber(result.Level) or 1)
				toast("LevelUp", `¡{entry.Name} ha evolucionado! {if reached then reached.Tag .. " " .. reached.Name else ""}`)
			end
		end)
	end

	local inFarm = farmSlotOf(data, uid)
	local farmButton = UiKit.button(detail, if inFarm then `Quitar de la granja (pedestal {inFarm})` else "Colocar en la granja", Colors.Blue, {
		Position = UDim2.fromOffset(0, y + 36),
		Size = UDim2.new(1, 0, 0, 30),
	})
	farmButton.Activated:Connect(function()
		act(if inFarm then "Unplace" else "Place", uid)
	end)

	UiKit.label(detail, "Poner en el equipo:", {
		Position = UDim2.fromOffset(0, y + 72),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
	})
	local inTeam = teamSlotOf(data, uid)
	for i, short in { "DEL", "MED", "DEF" } do -- (el portero es fijo: no se elige)
		local b = UiKit.button(detail, short, if inTeam == i then Colors.Coins else Colors.Panel2, {
			Position = UDim2.new((i - 1) / 3, 2, 0, y + 88),
			Size = UDim2.new(1 / 3, -4, 0, 28),
		})
		teamButtons[i] = b
		if tutorialMode and (inTeam ~= nil or (data.Team[i] ~= nil and data.Team[i] ~= "")) then
			b.Visible = false -- (tutorial) ese puesto ya esta ocupado, o este brainrot ya juega
		end
		b.Activated:Connect(function()
			if inTeam == i then
				act("SetTeam", i, "")
			else
				act("SetTeam", i, uid)
			end
		end)
	end

	local value = EconomyMath.sellValue(record)
	local sellButton = UiKit.button(detail, if sellArmed == uid then `¿Seguro? Pulsa otra vez (+{EconomyMath.format(value)})` else `Vender · +{EconomyMath.format(value)} monedas`, Colors.Red, {
		Position = UDim2.fromOffset(0, y + 124),
		Size = UDim2.new(1, 0, 0, 28),
	})
	sellButton.Activated:Connect(function()
		if sellArmed == uid then
			sellArmed = nil
			local result = act("Sell", uid)
			if result.Ok then
				selected = nil
				toast("Reward", `Vendido por {EconomyMath.format(result.Coins)} monedas`)
			end
		else
			sellArmed = uid
			renderDetail()
		end
	end)
	UiKit.zindex(detail, 11)
end

function InventoryPanel.build(parent: Instance, toastFn: (string, string) -> ())
	toast = toastFn
	local content
	window, content = UiKit.window(parent, "🧠 BRAINROTS Y EQUIPO", Vector2.new(900, 620))

	-- Equipo
	local teamBar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
	}, content)
	for i = 1, 4 do
		local slotFrame = make("Frame", {
			Position = UDim2.new((i - 1) * 0.25, 3, 0, 0),
			Size = UDim2.new(0.25, -6, 1, 0),
			BackgroundColor3 = Colors.Panel,
		}, teamBar)
		UiKit.corner(slotFrame, 8)
		UiKit.stroke(slotFrame, Colors.Line, 1)
		UiKit.label(slotFrame, `{i} · {POSITIONS[i]}`, {
			Name = "Title",
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -16, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Colors.Coins,
		})
		teamSlots[i] = slotFrame
	end

	-- Lista
	countLabel = UiKit.label(content, "Mis brainrots", {
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(0.25, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local sortButton = UiKit.button(content, "Orden: Calidad", Colors.Panel2, {
		Position = UDim2.new(0.26, 0, 0, 74),
		Size = UDim2.fromOffset(140, 28),
	})
	sortButton.Activated:Connect(function()
		sortMode = if sortMode == "Calidad" then "Nivel" elseif sortMode == "Nivel" then "Nuevos" else "Calidad"
		sortButton.Text = `Orden: {sortMode}`
		local data = ClientData.get()
		if data then
			renderGrid(data)
		end
	end)
	-- Llena la granja con los brainrots que mas monedas dan (y quita los peores)
	-- (junto al boton de ordenar)
	local bestButton = UiKit.button(content, "🏡 Colocar los mejores", Colors.Green, {
		Position = UDim2.new(0.26, 148, 0, 74),
		Size = UDim2.fromOffset(200, 28),
	})
	bestButton.Activated:Connect(function()
		local result = act("AutoFarm")
		if result.Ok then
			if (tonumber(result.Moved) or 0) > 0 then
				toast("Reward", `Granja organizada: +{EconomyMath.format(tonumber(result.Income) or 0)} monedas/s`)
			else
				toast("Info", "Tu granja ya tiene a tus mejores brainrots")
			end
		end
	end)
	-- Las monedas suben solas: el boton de subir nivel se activa en cuanto llegas
	Players.LocalPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
		if not window.Visible then
			return
		end
		for _, ref in levelRefs do
			if ref.Button.Parent then
				UiKit.setEnabled(ref.Button, ref.Cost ~= nil and ClientData.coins() >= (ref.Cost :: number))
			end
		end
	end)
	grid = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, -310, 1, -106),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.4,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		BorderSizePixel = 0,
	}, content)
	UiKit.corner(grid, 8)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(112, 140),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	UiKit.padding(grid, 8)

	-- Detalle
	detail = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 78),
		Size = UDim2.new(0, 296, 1, -78),
		BackgroundTransparency = 1,
	}, content)

	ClientData.onChanged(function(data)
		if selected and not data.Brainrots[selected] then
			selected = nil
		end
		if window.Visible then
			renderTeam(data)
			renderGrid(data)
			renderDetail()
		end
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		local data = ClientData.get()
		if window.Visible and data then
			renderTeam(data)
			renderGrid(data)
			renderDetail()
		end
	end)
	UiKit.zindex(window, 10)
	return window
end

-- Abre el panel (opcionalmente con un brainrot elegido)
-- ---------------------------------------------------------------------------
-- Para el tutorial
-- ---------------------------------------------------------------------------

function InventoryPanel.setTutorial(on: boolean)
	tutorialMode = on
	renderDetail()
end

function InventoryPanel.selectedUid(): string?
	return selected
end

-- La primera tarjeta (en el orden de la lista) de un brainrot que aun no esta en el equipo
function InventoryPanel.tutorialCard(): (GuiObject?, string?)
	local data = ClientData.get()
	local best: CardEntry? = nil
	local bestUid: string? = nil
	for uid, entry in cards do
		if data and teamSlotOf(data, uid) == nil and entry.Frame.Parent then
			if not best or entry.Frame.LayoutOrder < best.Frame.LayoutOrder then
				best, bestUid = entry, uid
			end
		end
	end
	return if best then best.Frame else nil, bestUid
end

-- Boton DEL / MED / DEF (1, 2, 3) del brainrot elegido
function InventoryPanel.teamButton(slot: number): TextButton?
	local button = teamButtons[slot]
	return if button and button.Parent and button.Visible then button else nil
end

function InventoryPanel.open(uid: string?)
	if uid then
		selected = uid
	end
	sellArmed = nil
	window.Visible = true
	UiKit.pop(window)
	local data = ClientData.get()
	if data then
		renderTeam(data)
		renderGrid(data)
		renderDetail()
	end
end

return InventoryPanel
