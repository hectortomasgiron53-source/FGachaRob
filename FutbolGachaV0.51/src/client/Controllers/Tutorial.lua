--!strict
--[[
	Tutorial: la primera vez que entras al juego te enseña donde estan las cosas, paso a paso. La pantalla se oscurece
	menos lo que hay que mirar o pulsar (con un marco amarillo y una mano), y un bocadillo explica que hacer.
	  1 Bienvenida                       6 Mi granja (ahi estan tus brainrots ganando monedas)
	  2 Monedas y gemas                  7 Boton Brainrots
	  3 Boton Cajas                      8 Tu equipo para los partidos (pon al menos uno)
	  4 Abrir 5 cajas basicas (obligado) 9 Buscar partida (online o practica)
	  5 Ver lo que te ha tocado
	El progreso se guarda (accion "Tutorial"): si sales a medias, sigues donde lo dejaste. 100 = terminado.
	Los jugadores nuevos empiezan con las gemas justas para las 5 cajas (Economy.Start.Gems).
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local MatchController = require(script.Parent.MatchController)
local TutorialTargets = require(script.Parent.TutorialTargets)
local ShopPanel = require(script.Parent.ShopPanel)
local CasesPanel = require(script.Parent.CasesPanel)
local OffersPanel = require(script.Parent.OffersPanel)
local InventoryPanel = require(script.Parent.InventoryPanel)

local Tutorial = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local DONE = 100
local PAD = 10

local gui: ScreenGui
local shades: { Frame } = {}
local ring: Frame
local hand: TextLabel
local bubble: Frame
local bubbleText: TextLabel
local bubbleStep: TextLabel
local nextButton: TextButton
local closeAllWindows: () -> () = function() end

-- Paso actual: lo que se señala, si oscurece el resto y cuando se pasa al siguiente
type Step = {
	Text: string,
	Targets: { string }?, -- piezas a señalar (TutorialTargets); sin nada = bocadillo en el centro
	-- Piezas y texto que cambian sobre la marcha (paso del equipo: primero una tarjeta, luego su puesto)
	Dynamic: (() -> ({ GuiObject }, string?))?,
	Dim: boolean?, -- oscurecer el resto (y no dejar pulsarlo). Por defecto: si
	Next: string?, -- texto del boton para seguir (si no hay, se sigue al cumplir Done)
	Enter: (() -> ())?,
	Done: (() -> boolean)?,
}

local function teamCount(): number
	local data = ClientData.get()
	local n = 0
	if data and data.Team then
		for i = 1, 3 do
			if data.Team[i] and data.Team[i] ~= "" then
				n += 1
			end
		end
	end
	return n
end

local function brainrotCount(): number
	local data = ClientData.get()
	local n = 0
	if data and data.Brainrots then
		for _ in data.Brainrots do
			n += 1
		end
	end
	return n
end

local function visible(name: string): boolean
	local target = TutorialTargets.get(name)
	return target ~= nil and target.Visible
end

local startBrainrots = 0
local opened = false

local STEPS: { Step } = {
	{
		Text = "¡Bienvenido a Striker Brainrot! ⚽🧠\nColecciona brainrots, haz que ganen monedas en tu granja y juega al fútbol con ellos.",
		Next = "¡Vamos!",
	},
	{
		Text = "Estas son tus 🪙 monedas y 💎 gemas.\nLas monedas las gana tu granja; las gemas sirven para abrir cajas.",
		Targets = { "CoinsPill", "GemsPill" },
		Next = "Siguiente",
	},
	{
		Text = "Pulsa 🎁 Cajas para ver las cajas de brainrots.",
		Targets = { "CasesTile" },
		Done = function()
			return visible("ShopWindow")
		end,
	},
	{
		Text = "¡Tienes gemas para 5 cajas básicas! Pulsa x5 para abrirlas a la vez.",
		Targets = { "BasicX5" },
		Enter = function()
			ClientData.request("TutorialGems") -- (por si acaso: las gemas justas para las 5 cajas)
			ShopPanel.open("Cases")
			ShopPanel.focusCase("Basica")
			startBrainrots = brainrotCount()
			opened = false
		end,
		Done = function()
			if CasesPanel.isSpinning() then
				opened = true
			end
			return opened or brainrotCount() >= startBrainrots + 5
		end,
	},
	{
		Text = "¡Mira lo que te ha tocado! Pulsa Cerrar cuando termines.",
		Dim = false,
		Done = function()
			return not CasesPanel.isSpinning() and not CasesPanel.isShowing()
		end,
	},
	{
		Text = "Tus brainrots nuevos ya están en tu 🏡 granja ganando monedas cada segundo (¡también mientras juegas!).\nCon este botón vas a tu granja.",
		Targets = { "HomeTile" },
		Enter = function()
			closeAllWindows()
		end,
		Next = "Siguiente",
	},
	{
		Text = "Ahora elige con quién juegas los partidos. Pulsa 🧠 Brainrots.",
		Targets = { "InventoryTile" },
		Done = function()
			return visible("InventoryWindow")
		end,
	},
	{
		Text = "Arriba está tu equipo: Delantero (tú), Medio y Defensa (el portero es fijo). ¡Vamos a llenarlo!",
		Enter = function()
			InventoryPanel.setTutorial(true)
		end,
		-- Primero se señala un brainrot que aun no juega; al elegirlo, el boton del primer puesto libre (los puestos
		-- ocupados ya no salen). Se repite hasta llenar los 3 puestos (o quedarse sin brainrots).
		Dynamic = function()
			local data = ClientData.get()
			local uid = InventoryPanel.selectedUid()
			local inTeam = false
			if data and uid then
				for i = 1, 3 do
					if data.Team[i] == uid then
						inTeam = true
					end
				end
			end
			if data and uid and data.Brainrots[uid] and not inTeam then
				for i, name in { "Delantero", "Medio", "Defensa" } do
					if not data.Team[i] or data.Team[i] == "" then
						local button = InventoryPanel.teamButton(i)
						if button then
							local short = ({ "DEL", "MED", "DEF" })[i]
							return { button }, `¡Buen fichaje! Ponlo de {name}: pulsa {short}.`
						end
					end
				end
			end
			local card = InventoryPanel.tutorialCard()
			local left = 3 - teamCount()
			local text = `Arriba está tu equipo (el portero es fijo). Toca este brainrot para elegirlo · {left} {if left == 1 then "puesto libre" else "puestos libres"}.`
			return if card then { card } else {}, text
		end,
		Done = function()
			return teamCount() >= 3 or InventoryPanel.tutorialCard() == nil
		end,
	},
	{
		Text = "¡Equipo listo! Ahora busca partida:\n⚔️ JUGAR ONLINE contra otras personas, o ⚽ Práctica contra bots.",
		Targets = { "PlayOnline", "PlayPractice" },
		Enter = function()
			InventoryPanel.setTutorial(false)
			closeAllWindows()
		end,
		Done = function()
			return player:GetAttribute("QueueSince") ~= nil or player:GetAttribute("MatchId") ~= nil
		end,
	},
}

local current = 0 -- paso en pantalla (0 = ninguno)
local nextPressed = false

-- Rectangulo de una pieza en coordenadas de pantalla. AbsolutePosition no cuenta la franja de arriba de Roblox
-- (en TODAS las pantallas, tambien en las que la ignoran: alli sale en negativo), y esta capa si la cubre: se suma siempre.
local function screenRect(target: GuiObject): (Vector2, Vector2)
	local inset = GuiService:GetGuiInset()
	return target.AbsolutePosition + inset, target.AbsoluteSize
end

local function setShades(minPos: Vector2?, maxPos: Vector2?, dim: boolean)
	local camera = Workspace.CurrentCamera
	local screen = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	for _, shade in shades do
		shade.Visible = dim
	end
	if not dim then
		return
	end
	if not minPos or not maxPos then
		-- Todo oscuro
		shades[1].Position = UDim2.fromOffset(0, 0)
		shades[1].Size = UDim2.fromOffset(screen.X, screen.Y)
		for i = 2, 4 do
			shades[i].Visible = false
		end
		return
	end
	local a, b = minPos, maxPos
	shades[1].Position = UDim2.fromOffset(0, 0) -- arriba
	shades[1].Size = UDim2.fromOffset(screen.X, math.max(0, a.Y))
	shades[2].Position = UDim2.fromOffset(0, b.Y) -- abajo
	shades[2].Size = UDim2.fromOffset(screen.X, math.max(0, screen.Y - b.Y))
	shades[3].Position = UDim2.fromOffset(0, a.Y) -- izquierda
	shades[3].Size = UDim2.fromOffset(math.max(0, a.X), b.Y - a.Y)
	shades[4].Position = UDim2.fromOffset(b.X, a.Y) -- derecha
	shades[4].Size = UDim2.fromOffset(math.max(0, screen.X - b.X), b.Y - a.Y)
end

local function layout()
	local step = STEPS[current]
	if not step then
		return
	end
	local camera = Workspace.CurrentCamera
	local screen = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	-- Union de las piezas señaladas
	local minPos, maxPos: Vector2? = nil, nil
	local guis: { GuiObject } = {}
	if step.Dynamic then
		local list, text = step.Dynamic()
		guis = list
		if text and bubbleText.Text ~= text then
			bubbleText.Text = text
		end
	else
		for _, name in step.Targets or {} do
			local target = TutorialTargets.get(name)
			if target then
				table.insert(guis, target)
			end
		end
	end
	for _, target in guis do
		if target.Visible and target.Parent then
			local p, s = screenRect(target)
			minPos = if minPos then Vector2.new(math.min(minPos.X, p.X), math.min(minPos.Y, p.Y)) else p
			local q = p + s
			maxPos = if maxPos then Vector2.new(math.max(maxPos.X, q.X), math.max(maxPos.Y, q.Y)) else q
		end
	end
	local dim = step.Dim ~= false
	if minPos and maxPos then
		local a = minPos - Vector2.new(PAD, PAD)
		local b = (maxPos :: Vector2) + Vector2.new(PAD, PAD)
		setShades(a, b, dim)
		ring.Visible = true
		ring.Position = UDim2.fromOffset(a.X, a.Y)
		ring.Size = UDim2.fromOffset(b.X - a.X, b.Y - a.Y)
		-- Mano apuntando (si no hay boton de seguir: hay que pulsar ahi)
		hand.Visible = step.Next == nil
		local bob = math.sin(os.clock() * 6) * 8
		local below = a.Y < screen.Y * 0.5
		hand.Position = UDim2.fromOffset((a.X + b.X) / 2 - 28, if below then b.Y + 4 + bob else a.Y - 60 - bob)
		hand.Rotation = if below then 0 else 180
		-- Bocadillo: debajo si la pieza esta arriba, encima si esta abajo; dentro de la pantalla
		local w = bubble.AbsoluteSize.X
		local h = bubble.AbsoluteSize.Y
		local x = math.clamp((a.X + b.X) / 2 - w / 2, 12, screen.X - w - 12)
		local y = if below then b.Y + 70 else a.Y - h - 70
		if step.Targets and step.Targets[1] == "InventoryWindow" then
			y = math.max(12, a.Y - h - 8) -- (encima de la ventana)
		end
		bubble.Position = UDim2.fromOffset(x, math.clamp(y, 12, screen.Y - h - 12))
	else
		setShades(nil, nil, dim and step.Targets == nil and step.Dynamic == nil)
		ring.Visible = false
		hand.Visible = false
		local w, h = bubble.AbsoluteSize.X, bubble.AbsoluteSize.Y
		local y = if step.Dim == false then 90 else screen.Y / 2 - h / 2
		bubble.Position = UDim2.fromOffset(screen.X / 2 - w / 2, y)
	end
end

local function save(stepNumber: number)
	task.spawn(ClientData.request, "Tutorial", stepNumber)
end

local function finish()
	current = 0
	gui.Enabled = false
	save(DONE)
	local data = ClientData.get()
	if data then
		data.Tutorial = DONE
	end
	-- Ahora si: la pantalla de ofertas (cuando no estes jugando)
	task.spawn(function()
		task.wait(3)
		while MatchController.isInMatch() do
			task.wait(2)
		end
		task.wait(2)
		OffersPanel.openPromo()
	end)
end

local function show(index: number)
	current = index
	local step = STEPS[index]
	if not step then
		finish()
		return
	end
	save(index)
	nextPressed = false
	bubbleText.Text = step.Text
	bubbleStep.Text = `Tutorial · {index}/{#STEPS}`
	nextButton.Visible = step.Next ~= nil
	nextButton.Text = step.Next or ""
	gui.Enabled = true
	if step.Enter then
		task.spawn(step.Enter)
	end
	UiKit.pop(bubble)
end

local function buildGui()
	gui = make("ScreenGui", {
		Name = "TutorialUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 50, -- por encima de todo lo demas
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	for _ = 1, 4 do
		table.insert(shades, make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Active = true, -- no deja pulsar lo que hay debajo
		}, gui))
	end
	ring = make("Frame", { BackgroundTransparency = 1, Visible = false }, gui)
	UiKit.corner(ring, 14)
	UiKit.stroke(ring, Colors.Yellow, 5)
	local stroke = ring:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
	end
	hand = UiKit.emoji(gui, "👆", { Size = UDim2.fromOffset(56, 56), Visible = false })
	bubble = make("Frame", {
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Back,
	}, gui)
	UiKit.corner(bubble, 16)
	UiKit.stroke(bubble, Colors.Yellow, 4)
	UiKit.gradient(bubble, 0.7)
	UiKit.padding(bubble, 14)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, bubble)
	bubbleStep = UiKit.label(bubble, "", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	bubbleText = UiKit.label(bubble, "", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 21,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	nextButton = UiKit.button(bubble, "Siguiente", Colors.Green, {
		LayoutOrder = 3,
		Size = UDim2.fromOffset(200, 44),
	})
	nextButton.Activated:Connect(function()
		nextPressed = true
	end)
	-- Solo en Studio (alli los datos suelen ser temporales y saldria el tutorial en cada prueba)
	if RunService:IsStudio() then
		local skip = UiKit.button(bubble, "Saltar tutorial (solo Studio)", Colors.Red, {
			LayoutOrder = 4,
			Size = UDim2.fromOffset(240, 30),
		})
		skip.Activated:Connect(function()
			finish()
		end)
	end
end

-- "closeAll": cierra las ventanas abiertas (EconomyController)
function Tutorial.start(closeAll: () -> ())
	closeAllWindows = closeAll
	buildGui()
	task.spawn(function()
		-- Espera a tus datos
		local waited = 0
		while not ClientData.get() and waited < 30 do
			task.wait(0.5)
			waited += 0.5
		end
		local data = ClientData.get()
		local saved = if data then tonumber(data.Tutorial) or DONE else DONE
		if saved >= DONE then
			return
		end
		task.wait(1.5)
		-- Si te quedaste a medias en las cajas o en los resultados, se retoma un paso antes (vuelve a enseñarlo)
		local start = math.clamp(saved, 1, #STEPS)
		if start == 5 then
			start = 6 -- (ya abriste las cajas)
		end
		show(start)
		RunService.RenderStepped:Connect(function()
			if current == 0 then
				return
			end
			local step = STEPS[current]
			-- En un partido el tutorial espera (salvo el ultimo paso, que se cumple al entrar)
			local inMatch = MatchController.isInMatch() and player:GetAttribute("MatchId") ~= 0
			gui.Enabled = not inMatch or current == #STEPS
			if step.Next then
				if nextPressed then
					show(current + 1)
				end
			elseif step.Done and step.Done() then
				show(current + 1)
				return
			end
			if gui.Enabled then
				layout()
			end
		end)
	end)
end

-- true mientras el tutorial esta en marcha (otras pantallas esperan)
function Tutorial.isActive(): boolean
	return current ~= 0
end

return Tutorial
