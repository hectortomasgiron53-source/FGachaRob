--!strict
--[[
	UIController: interfaz minima creada por codigo (sin tener que dibujar nada en Studio).
	Marcador, tiempo, mensajes (cuenta atras, gol, final) y barra de resistencia.
	Es una interfaz de pruebas: la Fase 10 la sustituira por la definitiva.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Strings = require(ReplicatedStorage.Shared.Locale.Strings)
local MatchController = require(script.Parent.MatchController)
local InputController = require(script.Parent.InputController)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

local UIController = {}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function UIController.start()
	local gui = make("ScreenGui", {
		Name = "FutbolGachaUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, player:WaitForChild("PlayerGui"))
	-- (Los botones de jugar, practica y online, estan en RankedPanel)

	-- Marcador y tiempo
	local hud = make("Frame", {
		Name = "Hud",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 360, 0, 70),
		BackgroundColor3 = Color3.fromRGB(20, 20, 28),
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, hud)
	hud.BackgroundColor3 = UiKit.Colors.Back
	hud.BackgroundTransparency = 0
	UiKit.stroke(hud, UiKit.Colors.Ink, 4)
	UiKit.gradient(hud, 0.7)
	local scoreLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		Text = "",
	}, hud)
	local timeLabel = make("TextLabel", {
		Position = UDim2.new(0, 0, 0.6, 0),
		Size = UDim2.new(1, 0, 0.4, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		TextScaled = true,
		Font = Enum.Font.Gotham,
		Text = "",
	}, hud)

	-- Mensaje central (cuenta atras, gol, final)
	local messageLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.35, 0),
		Size = UDim2.new(0, 520, 0, 120),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		Text = "",
		Visible = false,
	}, gui)

	-- Barra de resistencia
	local staminaBack = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 260, 0, 16),
		BackgroundColor3 = Color3.fromRGB(20, 20, 28),
		BackgroundTransparency = 0.3,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, staminaBack)
	UiKit.stroke(staminaBack, UiKit.Colors.Ink, 3)
	local staminaFill = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(250, 200, 50),
	}, staminaBack)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, staminaFill)

	-- Barra de carga (encima de la de resistencia): aparece mientras mantienes pase, tiro o tiro alto
	local chargeBack = make("Frame", {
		Name = "ChargeBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -48),
		Size = UDim2.new(0, 260, 0, 14),
		BackgroundColor3 = Color3.fromRGB(20, 20, 28),
		BackgroundTransparency = 0.3,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, chargeBack)
	make("UIStroke", { Thickness = 1.5, Color = Color3.new(1, 1, 1), Transparency = 0.6 }, chargeBack)
	local chargeFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, chargeBack)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, chargeFill)
	local chargeLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		Text = "",
	}, chargeBack)

	-- Guia de controles (abajo a la derecha): una fila por accion, tecla en su "chip" y texto separado.
	-- La seccion que no aplica (con balon / sin balon) se ve atenuada.
	local hintLabel = make("Frame", {
		Name = "ControlsGuide",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, 250, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(14, 18, 28),
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, hintLabel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, hintLabel)
	make("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, hintLabel)

	local guideOrder = 0
	local sections: { [string]: { TextLabel } } = { attack = {}, defense = {}, always = {} }

	local function guideHeader(text: string, section: string)
		guideOrder += 1
		local label = make("TextLabel", {
			LayoutOrder = guideOrder,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(250, 200, 50),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = text,
		}, hintLabel)
		table.insert(sections[section], label)
	end

	local function guideRow(key: string, action: string, section: string)
		guideOrder += 1
		local row = make("Frame", {
			LayoutOrder = guideOrder,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
		}, hintLabel)
		local chip = make("TextLabel", {
			Size = UDim2.new(0, 92, 1, 0),
			BackgroundColor3 = Color3.fromRGB(235, 238, 245),
			BackgroundTransparency = 0.1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(20, 24, 34),
			Text = key,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 5) }, chip)
		local label = make("TextLabel", {
			Position = UDim2.new(0, 102, 0, 0),
			Size = UDim2.new(1, -102, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = action,
		}, row)
		table.insert(sections[section], chip)
		table.insert(sections[section], label)
	end

	guideHeader(Strings.t("guide_with_ball"), "attack")
	guideRow(Strings.t("key_hold_e"), Strings.t("btn_pass"), "attack")
	guideRow(Strings.t("key_hold_f"), Strings.t("btn_shoot"), "attack")
	guideRow(Strings.t("key_hold_g"), Strings.t("btn_shoot_high"), "attack")
	guideRow("R", Strings.t("btn_juke"), "attack")
	guideRow("T", Strings.t("btn_flick"), "attack")
	guideHeader(Strings.t("guide_without_ball"), "defense")
	guideRow("Q", Strings.t("btn_tackle"), "defense")
	guideRow("C", Strings.t("btn_slide"), "defense")
	guideRow("E", Strings.t("btn_request"), "defense")
	guideHeader(Strings.t("guide_always"), "always")
	guideRow("Shift", Strings.t("btn_sprint"), "always")
	guideRow(Strings.t("key_right_click"), Strings.t("guide_camera"), "always")

	local guideMode = ""
	local function setGuideMode(hasBall: boolean)
		local mode = if hasBall then "attack" else "defense"
		if mode == guideMode then
			return
		end
		guideMode = mode
		for name, labels in sections do
			local dim = (name == "attack" and not hasBall) or (name == "defense" and hasBall)
			for _, label in labels do
				label.TextTransparency = if dim then 0.6 else 0
				if label.BackgroundTransparency < 1 then
					label.BackgroundTransparency = if dim then 0.7 else 0.1
				end
			end
		end
	end
	setGuideMode(false)

	-- Resultado final / aviso recibidos por remote
	local overrideText: string? = nil
	MatchController.onEvent(function(name: string, ...: any)
		local args = { ... }
		if name == "Final" then
			local winner, team = args[1], MatchController.getTeam()
			if winner == 0 then
				overrideText = Strings.t("draw")
			elseif winner == team then
				overrideText = Strings.t("win")
			else
				overrideText = Strings.t("lose")
			end
		elseif name == "Busy" then
			messageLabel.Text = Strings.t("busy")
			messageLabel.Visible = true
			task.delay(3, function()
				if not MatchController.isInMatch() then
					messageLabel.Visible = false
				end
			end)
		end
	end)

	MatchController.onChanged(function(inMatch: boolean)
		overrideText = nil
		pcall(function()
			StarterGui:SetCore("ResetButtonCallback", not inMatch) -- sin boton de reset en pleno partido
		end)
		if not inMatch then
			messageLabel.Visible = false
		end
	end)

	-- Solo se escribe en la pantalla lo que cambia (los textos y tamaños se comparan con el ultimo valor puesto)
	local lastScore, lastTime, lastStamina = "", "", -1
	RunService.RenderStepped:Connect(function()
		local inMatch = MatchController.isInMatch()
		local folder = if inMatch then MatchController.getFolder() else nil
		-- Patio de juegos (campo de exhibicion): sin marcador ni tiempo, y se puede seguir pulsando "Jugar"
		local playground = inMatch and folder ~= nil and folder:GetAttribute("Mode") == "Playground"
		hud.Visible = inMatch and not playground
		staminaBack.Visible = inMatch
		local chargeKind, charge = InputController.getCharge()
		chargeBack.Visible = inMatch and chargeKind ~= nil
		if chargeKind then
			-- Verde (suave) -> amarillo -> rojo (maxima fuerza)
			chargeFill.Size = UDim2.new(math.max(charge, 0.02), 0, 1, 0)
			local green, yellow, red = Color3.fromRGB(90, 220, 110), Color3.fromRGB(250, 210, 60), Color3.fromRGB(240, 70, 60)
			chargeFill.BackgroundColor3 = if charge < 0.6 then green:Lerp(yellow, charge / 0.6) else yellow:Lerp(red, (charge - 0.6) / 0.4)
			local key = if chargeKind == "Pass" then "btn_pass" elseif chargeKind == "ShootHigh" then "btn_shoot_high" else "btn_shoot"
			chargeLabel.Text = `{Strings.t(key)}  {math.floor(charge * 100)}%`
		end
		hintLabel.Visible = inMatch and UserInputService.KeyboardEnabled -- en movil ya estan los botones
		if inMatch then
			local ball = MatchController.getBall()
			setGuideMode(ball ~= nil and ball:GetAttribute("ControllerUserId") == player.UserId)
		end

		if not inMatch or not folder then
			lastScore, lastTime, lastStamina = "", "", -1 -- al volver a un partido se pinta todo de nuevo
			return
		end

		local phase = folder:GetAttribute("Phase")
		local blue = tonumber(folder:GetAttribute("Score1")) or 0
		local red = tonumber(folder:GetAttribute("Score2")) or 0
		local timeLeft = tonumber(folder:GetAttribute("TimeLeft")) or 0
		local countdown = tonumber(folder:GetAttribute("Countdown")) or 0

		local scoreKey = `{blue}-{red}`
		if scoreKey ~= lastScore then
			lastScore = scoreKey
			scoreLabel.Text = `{Strings.t("team_blue")} {blue}  -  {red} {Strings.t("team_red")}`
		end
		local timeKey = `{phase}{timeLeft}`
		if timeKey ~= lastTime then
			lastTime = timeKey
			timeLabel.Text = if phase == "GoldenGoal"
				then `{Strings.t("golden_goal")} {formatTime(timeLeft)}`
				else formatTime(timeLeft)
		end

		local stamina = tonumber(player:GetAttribute("Stamina")) or 0
		if stamina ~= lastStamina then
			lastStamina = stamina
			staminaFill.Size = UDim2.new(math.clamp(stamina / Balance.Stamina.Max, 0, 1), 0, 1, 0)
		end

		if phase == "Countdown" then
			messageLabel.Text = tostring(countdown)
			messageLabel.Visible = countdown > 0
		elseif phase == "Goal" then
			messageLabel.Text = Strings.t("goal")
			messageLabel.Visible = true
		elseif phase == "Final" then
			messageLabel.Text = overrideText or ""
			messageLabel.Visible = overrideText ~= nil
		else
			messageLabel.Visible = false
		end
	end)
end

return UIController
