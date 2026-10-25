--!strict
--[[
	AdminPanel: panel de administrador (la logica y los permisos, en el servidor: AdminService).
	Solo sale a quien el servidor marca con el atributo "IsAdmin" (el creador del juego). Un boton "🛠️ Admin" abajo a la
	izquierda abre la ventana: eliges un jugador del servidor y le regalas gemas, monedas, un brainrot (variante y
	nivel), un vehiculo o cajas (que se abren solas con su ruleta).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)

local AdminPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local window: Frame
local status: TextLabel
local playerButton: TextButton
local playersList: { { UserId: number, Name: string, DisplayName: string } } = {}
local selected = 1

local function request(...: any): any
	local ok, result = pcall(function(...)
		return Remotes.getFunction("Admin"):InvokeServer(...)
	end, ...)
	if ok and type(result) == "table" then
		return result
	end
	return { Ok = false, Error = "Sin respuesta del servidor" }
end

local function setStatus(text: string, good: boolean)
	status.Text = text
	status.TextColor3 = if good then Colors.Green else Colors.Red
end

local function showPlayer()
	local entry = playersList[selected]
	playerButton.Text = if entry then `👤 {entry.DisplayName} (@{entry.Name})  ·  {selected}/{#playersList}` else "👤 (nadie)"
end

local function refreshPlayers()
	local result = request("Players")
	if result.Ok then
		local current = playersList[selected]
		playersList = result.Players
		selected = 1
		for i, entry in playersList do
			if current and entry.UserId == current.UserId then
				selected = i
			end
		end
		showPlayer()
	end
end

local function give(kind: string, a: any, b: any, c: any)
	local entry = playersList[selected]
	if not entry then
		setStatus("Elige un jugador", false)
		return
	end
	local result = request("Give", entry.UserId, kind, a, b, c)
	if result.Ok then
		setStatus(`✅ Regalado a {result.Text}`, true)
	else
		setStatus(`❌ {result.Error or "No se pudo"}`, false)
	end
end

-- Casilla de texto con el estilo del juego
local function field(parent: Instance, x: number, y: number, width: number, text: string, placeholder: string): TextBox
	local box = make("TextBox", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, 40),
		BackgroundColor3 = Colors.Chip,
		Text = text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Colors.Muted,
		TextColor3 = Colors.Text,
		Font = UiKit.Font,
		TextSize = 18,
		ClearTextOnFocus = false,
		AutoLocalize = false,
	}, parent)
	UiKit.corner(box, 8)
	UiKit.stroke(box, Colors.Ink, 2)
	return box
end

-- Boton que va pasando por una lista de opciones; devuelve una funcion que dice la elegida
local function cycle<T>(parent: Instance, x: number, y: number, width: number, options: { T }, labelOf: (T) -> string): () -> T
	local index = 1
	local button = UiKit.button(parent, "", Colors.Blue, {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, 40),
	})
	local function show()
		button.Text = `◀ {labelOf(options[index])} ▶`
	end
	button.Activated:Connect(function()
		index = index % #options + 1
		show()
	end)
	show()
	return function()
		return options[index]
	end
end

local function rowTitle(parent: Instance, y: number, text: string)
	UiKit.label(parent, text, {
		Position = UDim2.fromOffset(0, y + 10),
		Size = UDim2.fromOffset(110, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- Brainrot por nombre o Id (vale un trozo: "tung" -> Tung Tung Tung Sahur)
local function findBrainrot(text: string): string?
	local wanted = string.lower((string.gsub(text, "^%s*(.-)%s*$", "%1")))
	if wanted == "" then
		return nil
	end
	if Brainrots.ById[wanted] then
		return wanted
	end
	local best: string? = nil
	for id, entry in Brainrots.ById do
		local name = string.lower(entry.Name)
		if name == wanted then
			return id
		end
		if not best and (string.find(name, wanted, 1, true) or string.find(id, wanted, 1, true)) then
			best = id
		end
	end
	return best
end

local function build()
	local gui = make("ScreenGui", {
		Name = "AdminUI",
		ResetOnSpawn = false,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
	}, player:WaitForChild("PlayerGui"))
	local content
	window, content = UiKit.window(gui, "🛠️ ADMIN", Vector2.new(640, 480))
	window.ZIndex = 40

	-- Jugador
	rowTitle(content, 0, "Jugador")
	playerButton = UiKit.button(content, "", Colors.Purple, {
		Position = UDim2.fromOffset(110, 0),
		Size = UDim2.new(1, -230, 0, 40),
	})
	playerButton.Activated:Connect(function()
		if #playersList > 0 then
			selected = selected % #playersList + 1
			showPlayer()
		end
	end)
	local refresh = UiKit.button(content, "🔄", Colors.Teal, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 0),
		Size = UDim2.fromOffset(50, 40),
	})
	refresh.Activated:Connect(refreshPlayers)

	-- Gemas y monedas
	rowTitle(content, 56, "Gemas")
	local gemsBox = field(content, 110, 56, 140, "1000", "cantidad")
	UiKit.button(content, "💎 Dar", Colors.Blue, { Position = UDim2.fromOffset(256, 56), Size = UDim2.fromOffset(90, 40) }).Activated:Connect(function()
		give("Gems", tonumber(gemsBox.Text))
	end)
	UiKit.label(content, "Monedas", { Position = UDim2.fromOffset(360, 66), Size = UDim2.fromOffset(70, 20) })
	local coinsBox = field(content, 432, 56, 110, "100000", "cantidad")
	UiKit.button(content, "🪙", Colors.Yellow, { Position = UDim2.fromOffset(548, 56), Size = UDim2.fromOffset(50, 40) }).Activated:Connect(function()
		give("Coins", tonumber(coinsBox.Text))
	end)

	-- Brainrot
	rowTitle(content, 112, "Brainrot")
	local nameBox = field(content, 110, 112, 190, "", "nombre (p. ej. tung)")
	local variant = cycle(content, 306, 112, 130, { "Normal", "Oro", "Diamante" }, function(v: string)
		return v
	end)
	local levelBox = field(content, 442, 112, 56, "1", "nivel")
	UiKit.button(content, "🧠 Dar", Colors.Green, { Position = UDim2.fromOffset(504, 112), Size = UDim2.fromOffset(94, 40) }).Activated:Connect(function()
		local id = findBrainrot(nameBox.Text)
		if not id then
			setStatus("❌ No encuentro ese brainrot", false)
			return
		end
		nameBox.Text = Brainrots.ById[id].Name
		give("Brainrot", id, variant(), tonumber(levelBox.Text) or 1)
	end)

	-- Vehiculo
	rowTitle(content, 168, "Vehículo")
	local vehicle = cycle(content, 110, 168, 388, Vehicles.List, function(v: any)
		return `{v.Emoji} {v.Name}`
	end)
	UiKit.button(content, "🛹 Dar", Colors.Orange, { Position = UDim2.fromOffset(504, 168), Size = UDim2.fromOffset(94, 40) }).Activated:Connect(function()
		give("Vehicle", vehicle().Id)
	end)

	-- Cajas (se abren solas con la ruleta)
	rowTitle(content, 224, "Cajas")
	local case = cycle(content, 110, 224, 250, Economy.Cases, function(c: any)
		return c.Name
	end)
	local count = cycle(content, 366, 224, 132, { 1, Economy.MaxCasesAtOnce }, function(n: number)
		return `x{n}`
	end)
	UiKit.button(content, "🎁 Dar", Colors.Purple, { Position = UDim2.fromOffset(504, 224), Size = UDim2.fromOffset(94, 40) }).Activated:Connect(function()
		give("Cases", case().Id, count())
	end)

	status = UiKit.label(content, "Elige un jugador y lo que le quieres regalar.", {
		Position = UDim2.fromOffset(0, 284),
		Size = UDim2.new(1, -20, 0, 24),
		TextColor3 = Colors.Muted,
	})
	UiKit.label(content, "Solo tú ves este panel. Cada regalo queda apuntado en la Salida del servidor.", {
		Position = UDim2.fromOffset(0, 314),
		Size = UDim2.new(1, -20, 0, 18),
		TextColor3 = Colors.Muted,
	})
	UiKit.zindex(window, 40)

	-- Boton para abrirlo (abajo a la izquierda, encima del de pruebas de Studio)
	local open = UiKit.button(gui, "🛠️ Admin", Colors.Red, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -100),
		Size = UDim2.fromOffset(110, 36),
	})
	open.Activated:Connect(function()
		window.Visible = not window.Visible
		if window.Visible then
			UiKit.pop(window)
			refreshPlayers()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if window.Visible then
			refreshPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if window.Visible then
			task.defer(refreshPlayers)
		end
	end)
end

function AdminPanel.start()
	task.spawn(function()
		-- El servidor marca a los administradores al entrar (puede tardar un momento)
		local waited = 0
		while player:GetAttribute("IsAdmin") ~= true and waited < 20 do
			task.wait(0.5)
			waited += 0.5
		end
		if player:GetAttribute("IsAdmin") == true then
			build()
		end
	end)
end

return AdminPanel
