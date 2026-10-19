--!strict
--[[
	InputController: teclado, mando y botones tactiles. Solo envia INTENCIONES al servidor.
	Siempre: pase (E / X), tiro (F / B) y tiro alto (G / R2): los tres se cargan manteniendo la tecla
	(la barra de carga aparece encima de la de resistencia). Sprint (Shift / L2).
	E sin balon (y sin un balon suelto a tu alcance): pedir el balon a tus companeros.
	CON balon: croqueta (R / L1) y sombrero (T / R1).
	SIN balon: entrada (Q / Y) y segada (C / R1).
	El movimiento lo hace el control por defecto de Roblox, relativo a la camara.
	En Studio hay atajos de depuracion (Y, U, I, O, P).
]]
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Locale.Strings)
local MatchController = require(script.Parent.MatchController)

local InputController = {}

local actionRemote = Remotes.get("Action")
local player = Players.LocalPlayer
local bound = false

-- Carga en curso (para la barra): que se esta cargando y desde cuando
local chargeKind: string? = nil
local chargeStartedAt = 0

local function chargeNow(): number
	return math.clamp((os.clock() - chargeStartedAt) / Balance.Control.ChargeSeconds, 0, 1)
end

-- Para la interfaz: ("Pass" | "Shoot" | "ShootHigh", 0..1) mientras se mantiene la tecla; nil si no.
function InputController.getCharge(): (string?, number)
	if not chargeKind then
		return nil, 0
	end
	return chargeKind, chargeNow()
end

-- Mantener para cargar y soltar para golpear (pase, tiro y tiro alto funcionan igual)
local function chargeAction(kind: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		chargeKind = kind
		chargeStartedAt = os.clock()
	elseif state == Enum.UserInputState.End then
		if chargeKind == kind then
			actionRemote:FireServer(kind, chargeNow())
			chargeKind = nil
		end
	elseif state == Enum.UserInputState.Cancel then
		if chargeKind == kind then
			chargeKind = nil
		end
	end
end
local mode = "none" -- "none" | "attack" (con balon) | "defense" (sin balon)
local lastJukeSide = 1

-- El balon suelto esta a tu alcance (para golpearlo)
local function ballInReach(): boolean
	local ball = MatchController.getBall()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not ball or not root then
		return false
	end
	return (ball.Position - root.Position).Magnitude <= Balance.Control.KickRange + 1.5
end

local function onPass(_name: string, state: Enum.UserInputState)
	-- Sin balon y sin un balon suelto cerca: E pide el balon a los companeros (no carga nada)
	if state == Enum.UserInputState.Begin and mode == "defense" and not ballInReach() then
		actionRemote:FireServer("RequestBall")
		return Enum.ContextActionResult.Sink
	end
	chargeAction("Pass", state)
	return Enum.ContextActionResult.Sink
end

local function onShoot(_name: string, state: Enum.UserInputState)
	chargeAction("Shoot", state)
	return Enum.ContextActionResult.Sink
end

-- Tiro alto (G): igual que el tiro, mantener para cargar; sale elevado
local function onShootHigh(_name: string, state: Enum.UserInputState)
	chargeAction("ShootHigh", state)
	return Enum.ContextActionResult.Sink
end

local function onSprint(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		actionRemote:FireServer("Sprint", true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		actionRemote:FireServer("Sprint", false)
	end
	return Enum.ContextActionResult.Sink
end

-- Sin balon ---------------------------------------------------------------
local function onTackle(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		actionRemote:FireServer("Tackle")
	end
	return Enum.ContextActionResult.Sink
end

local function onSlide(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		actionRemote:FireServer("Slide")
	end
	return Enum.ContextActionResult.Sink
end

-- Con balon ---------------------------------------------------------------
-- Croqueta: salto lateral hacia donde estes girando; si vas recto, alterna de lado.
local function onJuke(_name: string, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local side = lastJukeSide
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if humanoid and root and humanoid.MoveDirection.Magnitude > 0.1 then
		local lateral = humanoid.MoveDirection:Dot(root.CFrame.RightVector)
		if math.abs(lateral) > 0.3 then
			side = if lateral > 0 then 1 else -1
		else
			side = -lastJukeSide
		end
	else
		side = -lastJukeSide
	end
	lastJukeSide = side
	actionRemote:FireServer("Juke", side)
	return Enum.ContextActionResult.Sink
end

local function onFlick(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		actionRemote:FireServer("Flick")
	end
	return Enum.ContextActionResult.Sink
end

local function bindDefense()
	ContextActionService:BindAction("FG_Tackle", onTackle, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("FG_Slide", onSlide, true, Enum.KeyCode.C, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("FG_Tackle", Strings.t("btn_tackle"))
	ContextActionService:SetTitle("FG_Slide", Strings.t("btn_slide"))
	ContextActionService:SetPosition("FG_Tackle", UDim2.new(1, -110, 1, -250))
	ContextActionService:SetPosition("FG_Slide", UDim2.new(1, -200, 1, -300))
end

local function unbindDefense()
	ContextActionService:UnbindAction("FG_Tackle")
	ContextActionService:UnbindAction("FG_Slide")
end

local function bindAttack()
	ContextActionService:BindAction("FG_Juke", onJuke, true, Enum.KeyCode.R, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("FG_Flick", onFlick, true, Enum.KeyCode.T, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("FG_Juke", Strings.t("btn_juke"))
	ContextActionService:SetTitle("FG_Flick", Strings.t("btn_flick"))
	ContextActionService:SetPosition("FG_Juke", UDim2.new(1, -110, 1, -250))
	ContextActionService:SetPosition("FG_Flick", UDim2.new(1, -200, 1, -300))
end

local function unbindAttack()
	ContextActionService:UnbindAction("FG_Juke")
	ContextActionService:UnbindAction("FG_Flick")
end

-- Cambia entre la vision "con balon" y "sin balon". Solo cambia lo que se muestra y se enlaza;
-- el servidor tambien lo comprueba, asi que nadie puede saltarselo con un cliente modificado.
local function setMode(newMode: string)
	if newMode == mode then
		return
	end
	if mode == "attack" then
		unbindAttack()
	elseif mode == "defense" then
		unbindDefense()
	end
	mode = newMode
	if mode == "attack" then
		bindAttack()
	elseif mode == "defense" then
		bindDefense()
	end
end

local function bindAll()
	if bound then
		return
	end
	bound = true
	-- Siempre disponibles (el pase y el tiro tambien valen para un balon suelto a tu alcance)
	ContextActionService:BindAction("FG_Pass", onPass, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("FG_Shoot", onShoot, true, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("FG_Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("FG_ShootHigh", onShootHigh, true, Enum.KeyCode.G, Enum.KeyCode.ButtonR2)

	-- Botones tactiles
	ContextActionService:SetTitle("FG_Pass", Strings.t("btn_pass"))
	ContextActionService:SetTitle("FG_Shoot", Strings.t("btn_shoot"))
	ContextActionService:SetTitle("FG_Sprint", Strings.t("btn_sprint"))
	ContextActionService:SetTitle("FG_ShootHigh", Strings.t("btn_shoot_high"))
	ContextActionService:SetPosition("FG_ShootHigh", UDim2.new(1, -20, 1, -200))
	ContextActionService:SetPosition("FG_Shoot", UDim2.new(1, -110, 1, -150))
	ContextActionService:SetPosition("FG_Pass", UDim2.new(1, -200, 1, -100))
	ContextActionService:SetPosition("FG_Sprint", UDim2.new(1, -210, 1, -200))

	setMode("defense")
end

local function unbindAll()
	if not bound then
		return
	end
	setMode("none")
	bound = false
	ContextActionService:UnbindAction("FG_Pass")
	ContextActionService:UnbindAction("FG_Shoot")
	ContextActionService:UnbindAction("FG_Sprint")
	ContextActionService:UnbindAction("FG_ShootHigh")
	chargeKind = nil
	actionRemote:FireServer("Sprint", false)
end

-- Movimiento impuesto por el servidor (segada, croqueta). El servidor publica hasta cuando y hacia donde;
-- aqui se fuerza la direccion del Humanoid (la velocidad ya la pone el servidor con WalkSpeed).
local function applyForcedMove()
	local untilTime = player:GetAttribute("ForceUntil")
	if type(untilTime) ~= "number" or untilTime <= workspace:GetServerTimeNow() then
		return
	end
	local direction = player:GetAttribute("ForceDir")
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid and typeof(direction) == "Vector3" then
		humanoid:Move(direction, false) -- false = direccion de mundo, no relativa a la camara
	end
end

function InputController.start()
	-- Despues del control por defecto de Roblox (prioridad Input), para que el movimiento impuesto gane
	RunService:BindToRenderStep("FG_ForcedMove", Enum.RenderPriority.Input.Value + 1, applyForcedMove)

	-- Vision con balon / sin balon, segun lo que publica el servidor en el balon
	RunService.Heartbeat:Connect(function()
		if not bound then
			return
		end
		local ball = MatchController.getBall()
		local hasBall = ball ~= nil and ball:GetAttribute("ControllerUserId") == player.UserId
		setMode(if hasBall then "attack" else "defense")
	end)

	MatchController.onChanged(function(inMatch: boolean)
		if inMatch then
			bindAll()
		else
			unbindAll()
		end
	end)

	if RunService:IsStudio() then
		local debugRemote = Remotes.get("Debug")
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or not MatchController.isInMatch() then
				return
			end
			if input.KeyCode == Enum.KeyCode.Y then
				debugRemote:FireServer("Goal", 1) -- gol del equipo azul
			elseif input.KeyCode == Enum.KeyCode.U then
				debugRemote:FireServer("Goal", 2) -- gol del equipo rojo
			elseif input.KeyCode == Enum.KeyCode.I then
				debugRemote:FireServer("SetTime", 5) -- quedan 5 segundos
			elseif input.KeyCode == Enum.KeyCode.O then
				debugRemote:FireServer("End") -- terminar el partido
			elseif input.KeyCode == Enum.KeyCode.P then
				debugRemote:FireServer("ResetBall") -- balon al centro
			end
		end)
	end
end

return InputController
