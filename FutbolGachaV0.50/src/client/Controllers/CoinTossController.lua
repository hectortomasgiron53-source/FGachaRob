--!strict
--[[
	CoinTossController: sorteo de saque con moneda antes de cada partido.
	  1. El equipo AZUL pide cara o cruz (en el modo de un jugador eliges tu con los botones CARA / CRUZ).
	  2. La moneda sale despedida desde una mesa junto al centro del campo, da vueltas en el aire y cae en la
	     mesa mostrando el lado que ha salido. La camara mira a la mesa y se acerca cuando la moneda cae.
	  3. El equipo que gana elige SACAR o CEDER EL SAQUE (si gana la maquina, decide ella).
	El servidor decide el resultado (Match._coinCall) y lo publica en atributos de la carpeta del partido;
	aqui solo se anima y se muestra la interfaz. La mesa, la moneda y la interfaz existen solo en este cliente.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Locale.Strings)
local MatchController = require(script.Parent.MatchController)
local FxController = require(script.Parent.FxController)

local player = Players.LocalPlayer

local CoinTossController = {}

-- Linea de tiempo de la moneda (segundos desde CoinFlipAt). Tiene que caber en Balance.CoinToss.FlipSeconds.
local LAUNCH_AT = 0.35 -- reposa un instante y sale despedida
local AIR = 1.55 -- tiempo en el aire
local PEAK = 6.5 -- altura maxima sobre la mesa (studs)
local LAND_AT = LAUNCH_AT + AIR
local REVEAL_AT = LAND_AT + 0.15 -- se anuncia el lado que ha salido

local TABLE_TOP = 3.5
local COIN_DIAMETER = 2.2
local COIN_THICK = 0.18
local COIN_REST_Y = TABLE_TOP + 0.04 + COIN_THICK / 2 -- apoyada en el tapete
-- Moneda tumbada con la CARA hacia arriba: el eje del cilindro (X) apunta arriba y la parte de arriba de los
-- dibujos queda en el lado contrario a la camara, asi se leen bien desde ella.
local COIN_BASE = CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cilindro de pie (su eje X pasa a ser vertical)

local COLORS = {
	Panel = Color3.fromRGB(14, 20, 34),
	Text = Color3.fromRGB(235, 240, 250),
	Muted = Color3.fromRGB(150, 162, 186),
	Gold = Color3.fromRGB(250, 200, 50),
	GoldDark = Color3.fromRGB(140, 95, 20),
	Silver = Color3.fromRGB(205, 210, 222),
	SilverDark = Color3.fromRGB(100, 108, 126),
	Green = Color3.fromRGB(46, 160, 67),
	Slate = Color3.fromRGB(58, 72, 102),
}

local cameraCFrame: CFrame? = nil

-- La camara del partido usa esta CFrame mientras dura el sorteo (nil = camara normal).
function CoinTossController.getCameraCFrame(): CFrame?
	return cameraCFrame
end

-- ---------------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------------

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

-- Rellena "{clave}" en un texto de Strings.
local function fmt(text: string, vars: { [string]: any }): string
	return (string.gsub(text, "{(%w+)}", function(key: string)
		return tostring(vars[key] or "")
	end))
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function teamName(team: number): string
	return Strings.t(if team == 1 then "team_blue" else "team_red")
end

local function sideName(side: string): string
	return Strings.t(if side == "Cara" then "coin_heads" else "coin_tails")
end

-- ---------------------------------------------------------------------------
-- Mesa y moneda (solo en este cliente)
-- ---------------------------------------------------------------------------

local scene: Model? = nil
local coin: Part? = nil
local coinLight: PointLight? = nil
local sparkleHolder: Attachment? = nil
local sparkles: ParticleEmitter? = nil
local tableCFrame = CFrame.identity

local function scenePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder -- toda la escena son cilindros: mesa redonda y moneda
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function shape(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, round: boolean, rotation: number?): Frame
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Rotation = rotation or 0,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	if round then
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	end
	return f
end

-- CARA: dorada, con una carita. CRUZ: plateada, con una cruz.
-- Los dibujos de la CRUZ van girados 180 grados: la moneda gira en el aire sobre un eje horizontal y esa cara
-- llega "del reves"; asi se lee bien tanto cuando pasa por delante de la camara como al caer.
local function coinFace(part: Part, face: Enum.NormalId, isHeads: boolean)
	local main = if isHeads then COLORS.Gold else COLORS.Silver
	local dark = if isHeads then COLORS.GoldDark else COLORS.SilverDark
	local gui = make("SurfaceGui", {
		Name = if isHeads then "Cara" else "Cruz",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 110,
		LightInfluence = 0.35,
	}, part)
	local disc = shape(gui, 0.5, 0.5, 0.97, 0.97, main, true)
	make("UIStroke", { Thickness = 9, Color = dark }, disc)
	local ring = shape(disc, 0.5, 0.5, 0.84, 0.84, main, true)
	ring.BackgroundTransparency = 1
	make("UIStroke", { Thickness = 3, Color = dark, Transparency = 0.35 }, ring)

	local flip = not isHeads
	local function y(v: number): number
		return if flip then 1 - v else v
	end
	if isHeads then
		local head = shape(disc, 0.5, 0.36, 0.36, 0.36, main, true)
		make("UIStroke", { Thickness = 8, Color = dark }, head)
		shape(disc, 0.435, 0.315, 0.055, 0.055, dark, true) -- ojos
		shape(disc, 0.565, 0.315, 0.055, 0.055, dark, true)
		shape(disc, 0.448, 0.41, 0.075, 0.036, dark, true, 28) -- sonrisa
		shape(disc, 0.552, 0.41, 0.075, 0.036, dark, true, -28)
		shape(disc, 0.5, 0.425, 0.05, 0.036, dark, true)
	else
		shape(disc, 0.5, y(0.35), 0.1, 0.38, dark, false) -- palo vertical
		shape(disc, 0.5, y(0.29), 0.3, 0.1, dark, false) -- travesano
	end
	make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y(0.71)),
		Size = UDim2.fromScale(0.62, 0.2),
		Rotation = if flip then 180 else 0,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = dark,
		Text = sideName(if isHeads then "Cara" else "Cruz"),
	}, disc)
end

local function arenaCFrame(folder: Instance): CFrame
	local origin = folder:GetAttribute("Origin")
	local yaw = tonumber(folder:GetAttribute("OriginYaw")) or 0
	local position: Vector3
	if typeof(origin) == "Vector3" then
		position = origin
	else
		-- Por si acaso: durante el sorteo el balon esta en el centro del campo
		local ball = MatchController.getBall()
		position = if ball then ball.Position - Vector3.new(0, Balance.Ball.Diameter / 2, 0) else Vector3.zero
	end
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

local function buildScene(folder: Instance)
	tableCFrame = arenaCFrame(folder) * CFrame.new(Balance.CoinToss.TablePosition)
	local model = Instance.new("Model")
	model.Name = "CoinTossScene"

	local metal = Color3.fromRGB(38, 38, 44)
	local legLength = TABLE_TOP - 0.55
	scenePart(model, "TableBase", Vector3.new(0.25, 2.8, 2.8), tableCFrame * CFrame.new(0, 0.125, 0) * VERTICAL, metal, Enum.Material.Metal)
	scenePart(model, "TableLeg", Vector3.new(legLength, 0.5, 0.5), tableCFrame * CFrame.new(0, 0.25 + legLength / 2, 0) * VERTICAL, metal, Enum.Material.Metal)
	scenePart(model, "TableRim", Vector3.new(0.3, 5, 5), tableCFrame * CFrame.new(0, TABLE_TOP - 0.15, 0) * VERTICAL, Color3.fromRGB(110, 72, 40), Enum.Material.Wood)
	local felt = scenePart(model, "TableFelt", Vector3.new(0.04, 4.6, 4.6), tableCFrame * CFrame.new(0, TABLE_TOP + 0.02, 0) * VERTICAL, Color3.fromRGB(32, 110, 62), Enum.Material.Fabric)

	-- Destellos al caer la moneda
	local holder = Instance.new("Attachment")
	holder.Name = "Sparkles"
	holder.Parent = felt
	holder.WorldCFrame = CFrame.new((tableCFrame * CFrame.new(0, TABLE_TOP + 0.15, 0)).Position)
	local emitter = make("ParticleEmitter", {
		Enabled = false,
		Rate = 0,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(60, 60),
		Speed = NumberRange.new(5, 9),
		Lifetime = NumberRange.new(0.45, 0.8),
		Acceleration = Vector3.new(0, -14, 0),
		Drag = 2,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 228, 130), Color3.fromRGB(255, 180, 60)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }),
	}, holder)

	local part = scenePart(
		model,
		"Coin",
		Vector3.new(COIN_THICK, COIN_DIAMETER, COIN_DIAMETER),
		tableCFrame * CFrame.new(0, COIN_REST_Y, 0) * COIN_BASE,
		Color3.fromRGB(222, 176, 62),
		Enum.Material.SmoothPlastic
	)
	part.Reflectance = 0.2
	coinFace(part, Enum.NormalId.Right, true) -- CARA (cara +X del cilindro)
	coinFace(part, Enum.NormalId.Left, false) -- CRUZ (cara -X)
	local light = make("PointLight", { Color = Color3.fromRGB(255, 220, 140), Brightness = 2, Range = 7, Enabled = false }, part)

	model.Parent = workspace
	scene = model
	coin = part
	coinLight = light
	sparkleHolder = holder
	sparkles = emitter
end

local function destroyScene()
	if scene then
		scene:Destroy()
	end
	scene, coin, coinLight, sparkleHolder, sparkles = nil, nil, nil, nil, nil
end

-- Altura sobre la mesa, giro (radianes, sobre el eje horizontal) y avance del vuelo (0..1) en el instante t.
local function coinPose(t: number, result: string): (number, number, number)
	local halfTurns = if result == "Cruz" then 9 else 8 -- par: sigue de cara; impar: cae de cruz
	if t <= LAUNCH_AT then
		return 0, 0, 0
	elseif t <= LAND_AT then
		local u = t - LAUNCH_AT
		local gravity = 8 * PEAK / (AIR * AIR)
		local v0 = gravity * AIR / 2
		return v0 * u - 0.5 * gravity * u * u, halfTurns * math.pi * (u / AIR), u / AIR
	end
	-- Ya en la mesa: un botecito y se balancea hasta quedarse quieta
	local u = t - LAND_AT
	local bounce = if u < 0.24 then 0.4 * math.sin(math.pi * u / 0.24) else 0
	local wobble = 0.22 * math.exp(-u * 6) * math.sin(u * 30)
	local lift = (COIN_DIAMETER / 2) * math.abs(math.sin(wobble)) -- al balancearse, el borde no se mete en la mesa
	return bounce + lift, halfTurns * math.pi + wobble, 1
end

-- ---------------------------------------------------------------------------
-- Interfaz
-- ---------------------------------------------------------------------------

type Ui = {
	Gui: ScreenGui,
	Banner: Frame,
	BannerScale: UIScale,
	Subtitle: TextLabel,
	Timer: TextLabel,
	Big: TextLabel,
	BigScale: UIScale,
	Buttons: Frame,
	ButtonsScale: UIScale,
	A: TextButton,
	B: TextButton,
}

local ui: Ui? = nil
local handlerA: (() -> ())? = nil
local handlerB: (() -> ())? = nil
local sentForStep = "" -- paso en el que ya se envio la eleccion (los botones se ocultan hasta el siguiente paso)

local function buildUi(): Ui
	local gui = make("ScreenGui", {
		Name = "CoinTossUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	-- Cartel de arriba: titulo, que esta pasando y tiempo para elegir
	local banner = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0, 480, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.15,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, banner)
	make("UIStroke", { Thickness = 2, Color = COLORS.Gold, Transparency = 0.5 }, banner)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, banner)
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, banner)
	local bannerScale = make("UIScale", { Scale = 1 }, banner)
	make("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 26,
		TextColor3 = COLORS.Gold,
		Text = Strings.t("coin_title"),
	}, banner)
	local subtitle = make("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 19,
		TextWrapped = true,
		TextColor3 = COLORS.Text,
		Text = "",
	}, banner)
	local timer = make("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 15,
		TextColor3 = COLORS.Muted,
		Text = "",
	}, banner)

	-- Lado que ha salido, en grande
	local big = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 300),
		Size = UDim2.new(0, 520, 0, 100),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = COLORS.Gold,
		TextStrokeColor3 = COLORS.GoldDark,
		TextStrokeTransparency = 0,
		Text = "",
		Visible = false,
	}, gui)
	local bigScale = make("UIScale", { Scale = 1 }, big)

	-- Botones (CARA / CRUZ y despues SACAR / CEDER EL SAQUE)
	local buttons = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0, 480, 0, 66),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 20),
	}, buttons)
	local buttonsScale = make("UIScale", { Scale = 1 }, buttons)
	local function newButton(): TextButton
		local b = make("TextButton", {
			Size = UDim2.new(0, 220, 1, 0),
			Font = Enum.Font.GothamBlack,
			TextSize = 22,
			AutoButtonColor = true,
			Text = "",
		}, buttons)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
		make("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		return b
	end
	local a = newButton()
	local b = newButton()
	a.Activated:Connect(function()
		if handlerA then
			handlerA()
		end
	end)
	b.Activated:Connect(function()
		if handlerB then
			handlerB()
		end
	end)

	return {
		Gui = gui,
		Banner = banner,
		BannerScale = bannerScale,
		Subtitle = subtitle,
		Timer = timer,
		Big = big,
		BigScale = bigScale,
		Buttons = buttons,
		ButtonsScale = buttonsScale,
		A = a,
		B = b,
	}
end

local function styleButton(button: TextButton, text: string, background: Color3, textColor: Color3)
	button.Text = text
	button.BackgroundColor3 = background
	button.TextColor3 = textColor
end

-- En pantallas bajas (movil) todo se hace mas pequeno para que no se pise.
local function layoutScale(u: Ui): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 900
	local s = math.clamp(height / 900, 0.55, 1)
	u.BannerScale.Scale = s
	u.ButtonsScale.Scale = s
	u.Big.Position = UDim2.new(0.5, 0, 0, 92 + 215 * s)
	u.Buttons.Position = UDim2.new(0.5, 0, 1, -110 * s)
	return s
end

-- ---------------------------------------------------------------------------
-- Bucle
-- ---------------------------------------------------------------------------

local lastFlipAt = 0
local playedLaunch = false
local playedLand = false

local function reset()
	destroyScene()
	cameraCFrame = nil
	lastFlipAt = 0
	playedLaunch, playedLand = false, false
	sentForStep = ""
	handlerA, handlerB = nil, nil
	if ui then
		ui.Gui.Enabled = false
	end
end

local function update(_dt: number)
	local folder = MatchController.getFolder()
	if not MatchController.isInMatch() or not folder or folder:GetAttribute("Phase") ~= "CoinToss" then
		if scene or cameraCFrame or (ui and ui.Gui.Enabled) then
			reset()
		end
		return
	end
	if not scene then
		buildScene(folder)
	end
	local u = ui :: Ui
	u.Gui.Enabled = true
	local s = layoutScale(u)

	local now = workspace:GetServerTimeNow()
	local step = tostring(folder:GetAttribute("CoinStep") or "")
	local call = tostring(folder:GetAttribute("CoinCall") or "")
	local result = tostring(folder:GetAttribute("CoinResult") or "")
	local winner = tonumber(folder:GetAttribute("CoinWinner")) or 0
	local decision = tostring(folder:GetAttribute("CoinDecision") or "")
	local flipAt = tonumber(folder:GetAttribute("CoinFlipAt")) or 0
	local deadline = tonumber(folder:GetAttribute("CoinDeadline")) or now
	local chooserId = tonumber(folder:GetAttribute("CoinChooser")) or 0
	local myTeam = MatchController.getTeam()
	local amChooser = chooserId == player.UserId

	-- Moneda
	if flipAt ~= lastFlipAt then
		lastFlipAt = flipAt
		playedLaunch, playedLand = false, false
	end
	local flipping = flipAt > 0
	local t = if flipping then math.max(0, now - flipAt) else 0
	local height, angle, progress = coinPose(t, if result ~= "" then result else "Cara")
	-- Cada lanzamiento cae en un punto un poco distinto de la mesa (igual para todos: depende de CoinFlipAt)
	local drift = Vector3.new(math.sin(flipAt * 7.3) * 0.45, 0, math.cos(flipAt * 5.1) * 0.3) * progress
	local coinLocal = Vector3.new(drift.X, COIN_REST_Y + height, drift.Z)
	local coinCf = tableCFrame * CFrame.new(coinLocal) * CFrame.fromAxisAngle(Vector3.xAxis, angle) * COIN_BASE
	if coin then
		coin.CFrame = coinCf
	end
	local landed = flipping and t >= LAND_AT
	if coinLight then
		coinLight.Enabled = landed
	end
	if flipping and t >= LAUNCH_AT and not playedLaunch then
		playedLaunch = true
		if t < LAUNCH_AT + 0.3 then
			FxController.playSound("CoinFlip", coinCf.Position, 1, 1)
		end
	end
	if landed and not playedLand then
		playedLand = true
		if t < LAND_AT + 0.3 then
			FxController.playSound("CoinLand", coinCf.Position, 1, 1)
			if sparkleHolder and sparkles then
				sparkleHolder.WorldPosition = coinCf.Position
				sparkles:Emit(26)
			end
		end
	end

	-- Camara: mira a la mesa, sigue a la moneda en el aire y se acerca cuando cae
	local close = if flipping then smooth((t - LAND_AT - 0.1) / 0.7) else 0
	local camLocal = Vector3.new(0, TABLE_TOP + 5, 7):Lerp(Vector3.new(0, TABLE_TOP + 4.4, 3.4), close)
	local lookFlying = Vector3.new(0, TABLE_TOP + 0.3 + height * 0.75, 0)
	local lookLanded = coinLocal + Vector3.new(0, 0.5, -0.6) -- un poco por encima: la moneda queda bajo los textos
	local lookLocal = lookFlying:Lerp(lookLanded, close)
	cameraCFrame = CFrame.lookAt((tableCFrame * CFrame.new(camLocal)).Position, (tableCFrame * CFrame.new(lookLocal)).Position)

	-- Textos y botones
	local revealed = flipping and t >= REVEAL_AT and result ~= ""
	local secondsLeft = math.max(0, math.ceil(deadline - now))
	local subtitle = ""
	local timerText = ""
	local showButtons = false
	handlerA, handlerB = nil, nil

	local callText = ""
	if call ~= "" then
		callText = if amChooser
			then fmt(Strings.t("coin_you_called"), { side = sideName(call) })
			else fmt(Strings.t("coin_team_called"), { team = teamName(1), side = sideName(call) })
	end

	if step == "Choose" then
		if amChooser then
			subtitle = Strings.t("coin_pick")
			timerText = fmt(Strings.t("coin_seconds"), { n = secondsLeft })
			if sentForStep ~= "Choose" then
				showButtons = true
				styleButton(u.A, sideName("Cara"), COLORS.Gold, COLORS.GoldDark)
				styleButton(u.B, sideName("Cruz"), COLORS.Silver, COLORS.SilverDark)
				handlerA = function()
					sentForStep = "Choose"
					Remotes.get("Action"):FireServer("CoinCall", "Cara")
				end
				handlerB = function()
					sentForStep = "Choose"
					Remotes.get("Action"):FireServer("CoinCall", "Cruz")
				end
			end
		else
			subtitle = fmt(Strings.t("coin_waiting_pick"), { team = teamName(1) })
		end
	elseif not revealed then
		subtitle = if callText ~= "" then callText .. "\n" .. Strings.t("coin_flipping") else Strings.t("coin_flipping")
	else
		local winText = if winner == myTeam
			then Strings.t("coin_win_you")
			else fmt(Strings.t("coin_win_team"), { team = teamName(winner) })
		if step == "Decide" then
			if winner == myTeam then
				subtitle = winText .. "\n" .. Strings.t("coin_decide")
				timerText = fmt(Strings.t("coin_seconds"), { n = secondsLeft })
				if sentForStep ~= "Decide" then
					showButtons = true
					styleButton(u.A, Strings.t("coin_kick"), COLORS.Green, Color3.new(1, 1, 1))
					styleButton(u.B, Strings.t("coin_receive"), COLORS.Slate, Color3.new(1, 1, 1))
					handlerA = function()
						sentForStep = "Decide"
						Remotes.get("Action"):FireServer("CoinDecide", "Kick")
					end
					handlerB = function()
						sentForStep = "Decide"
						Remotes.get("Action"):FireServer("CoinDecide", "Receive")
					end
				end
			else
				subtitle = winText .. "\n" .. fmt(Strings.t("coin_rival_deciding"), { team = teamName(winner) })
			end
		elseif (step == "Result" or step == "Done") and decision ~= "" then
			local kickTeam = if decision == "Kick" then winner else (if winner == 1 then 2 else 1)
			local choseKey = if decision == "Kick" then "coin_chose_kick" else "coin_chose_receive"
			subtitle = fmt(Strings.t(choseKey), { team = teamName(winner) })
				.. "\n"
				.. fmt(Strings.t("coin_kickoff"), { team = teamName(kickTeam) })
		else
			subtitle = if callText ~= "" then callText .. "\n" .. winText else winText
		end
	end

	u.Subtitle.Text = subtitle
	u.Timer.Text = timerText
	u.Timer.Visible = timerText ~= ""
	u.Buttons.Visible = showButtons
	u.Big.Visible = revealed
	if revealed then
		local heads = result == "Cara"
		u.Big.Text = fmt(Strings.t("coin_reveal"), { side = sideName(result) })
		u.Big.TextColor3 = if heads then COLORS.Gold else COLORS.Silver
		u.Big.TextStrokeColor3 = if heads then COLORS.GoldDark else COLORS.SilverDark
		u.BigScale.Scale = s * (0.6 + 0.4 * smooth((t - REVEAL_AT) / 0.25))
	end
end

function CoinTossController.start()
	ui = buildUi()
	-- Antes que la camara del partido (prioridad Camera + 1), que usa la posicion calculada aqui
	RunService:BindToRenderStep("CoinToss", Enum.RenderPriority.Camera.Value - 1, update)
end

return CoinTossController
