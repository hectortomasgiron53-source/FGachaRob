--!strict
--[[
	InventoryPanel: tus brainrots y tu equipo.
	- Arriba: los 4 puestos del equipo (1 Delantero = tu, 2 Medio, 3 Defensa, 4 Portero).
	- Izquierda: todos tus brainrots (ordenados por calidad, nivel o los mas nuevos).
	- Derecha: el seleccionado: estadisticas, monedas por segundo, subir de nivel, granja, equipo y vender.
]]
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
local sortMode = "Calidad"
local sellArmed: string? = nil
local toast: (string, string) -> () = function() end

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
		local uid = data.Team[i]
		local record = if uid ~= "" then data.Brainrots[uid] else nil
		if record then
			local entry = EconomyMath.entryOf(record.Id)
			local rarity = EconomyMath.rarityOf(record.Id)
			UiKit.viewport(slotFrame, record.Id, record.Variant, {
				Position = UDim2.fromOffset(4, 18),
				Size = UDim2.fromOffset(46, 46),
			})
			UiKit.label(slotFrame, entry.Name, {
				Position = UDim2.fromOffset(54, 22),
				Size = UDim2.new(1, -58, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBlack,
			})
			UiKit.label(slotFrame, `{rarity.Name} · Nv {record.Level} · {EconomyMath.overall(record)} MED`, {
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

local function renderGrid(data: any)
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = sortedUids(data)
	local count = 0
	for order, uid in list do
		count += 1
		local record = data.Brainrots[uid]
		local card = UiKit.card(grid, record, Vector2.new(112, 140))
		card.LayoutOrder = order
		if uid == selected then
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Color3.new(1, 1, 1)
				stroke.Thickness = 3
			end
		end
		local tags = {}
		if farmSlotOf(data, uid) then
			table.insert(tags, "Granja")
		end
		local t = teamSlotOf(data, uid)
		if t then
			table.insert(tags, `Equipo {t}`)
		end
		if #tags > 0 then
			local tag = UiKit.label(card, table.concat(tags, " · "), {
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
			renderGrid(data)
			renderDetail()
		end)
	end
	countLabel.Text = `Mis brainrots ({count}/{Economy.Brainrot.MaxInventory})`
	UiKit.zindex(grid, 11)
end

function renderDetail()
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
	})
	UiKit.label(detail, entry.Name, {
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
	-- Estadisticas
	local stats = EconomyMath.stats(record)
	for i, name in EconomyMath.StatNames do
		local y = 184 + (i - 1) * 15
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

	-- Botones
	local y = 296
	local cost = EconomyMath.levelCost(record)
	local levelButton = UiKit.button(detail, if cost then `Subir nivel · {EconomyMath.format(cost)} monedas` else "Nivel máximo", Colors.Green, {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 30),
	})
	UiKit.setEnabled(levelButton, cost ~= nil and ClientData.coins() >= (cost :: number))
	levelButton.Activated:Connect(function()
		if levelButton.Active then
			act("LevelUp", uid)
		end
	end)

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
	for i, short in { "DEL", "MED", "DEF", "POR" } do
		local b = UiKit.button(detail, short, if inTeam == i then Colors.Coins else Colors.Panel2, {
			Position = UDim2.new((i - 1) * 0.25, 2, 0, y + 88),
			Size = UDim2.new(0.25, -4, 0, 28),
		})
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
	window, content = UiKit.window(parent, "BRAINROTS Y EQUIPO", Vector2.new(900, 620))

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
		Size = UDim2.new(0.4, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local sortButton = UiKit.button(content, "Orden: Calidad", Colors.Panel2, {
		Position = UDim2.new(0.42, 0, 0, 76),
		Size = UDim2.fromOffset(160, 24),
	})
	sortButton.Activated:Connect(function()
		sortMode = if sortMode == "Calidad" then "Nivel" elseif sortMode == "Nivel" then "Nuevos" else "Calidad"
		sortButton.Text = `Orden: {sortMode}`
		local data = ClientData.get()
		if data then
			renderGrid(data)
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
