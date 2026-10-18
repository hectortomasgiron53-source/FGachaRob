--!strict
--[[
	UIController: interfaz minima creada por codigo (sin tener que dibujar nada en Studio).
	Boton de jugar, marcador, tiempo, mensajes (cuenta atras, gol, final) y barra de resistencia.
	Es una interfaz de pruebas: la Fase 10 la sustituira por la definitiva.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Locale.Strings)
local MatchController = require(script.Parent.MatchController)

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

	-- Boton de jugar (solo fuera de partido)
	local playButton = make("TextButton", {
		Name = "PlayButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0, 320, 0, 60),
		BackgroundColor3 = Color3.fromRGB(46, 160, 67),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		Text = Strings.t("play_practice"),
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, playButton)

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
	local staminaFill = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(250, 200, 50),
	}, staminaBack)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, staminaFill)

	local hintLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 0, 22),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		Text = Strings.t("hint"),
		Visible = false,
	}, gui)

	playButton.Activated:Connect(function()
		Remotes.get("RequestMatch"):FireServer("Practice")
	end)

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

	RunService.RenderStepped:Connect(function()
		local inMatch = MatchController.isInMatch()
		local folder = MatchController.getFolder()
		-- Patio de juegos (campo de exhibicion): sin marcador ni tiempo, y se puede seguir pulsando "Jugar"
		local playground = inMatch and folder ~= nil and folder:GetAttribute("Mode") == "Playground"
		playButton.Visible = not inMatch or playground
		hud.Visible = inMatch and not playground
		staminaBack.Visible = inMatch
		hintLabel.Visible = inMatch

		if not inMatch or not folder then
			return
		end

		local phase = folder:GetAttribute("Phase")
		local blue = tonumber(folder:GetAttribute("Score1")) or 0
		local red = tonumber(folder:GetAttribute("Score2")) or 0
		local timeLeft = tonumber(folder:GetAttribute("TimeLeft")) or 0
		local countdown = tonumber(folder:GetAttribute("Countdown")) or 0

		scoreLabel.Text = `{Strings.t("team_blue")} {blue}  -  {red} {Strings.t("team_red")}`
		timeLabel.Text = if phase == "GoldenGoal"
			then `{Strings.t("golden_goal")} {formatTime(timeLeft)}`
			else formatTime(timeLeft)

		local stamina = tonumber(player:GetAttribute("Stamina")) or 0
		staminaFill.Size = UDim2.new(math.clamp(stamina / Balance.Stamina.Max, 0, 1), 0, 1, 0)

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
