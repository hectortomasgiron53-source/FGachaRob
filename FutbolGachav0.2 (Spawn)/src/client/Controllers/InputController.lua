--!strict
--[[
	InputController: teclado, mando y botones tactiles. Solo envia INTENCIONES al servidor.
	Pase (E / X), tiro (F / B, mantener para cargar), entrada (Q / Y), sprint (Shift / L2).
	El movimiento lo hace el control por defecto de Roblox, relativo a la camara.
	En Studio hay atajos de depuracion (Y, U, I, O, P).
]]
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Locale.Strings)
local MatchController = require(script.Parent.MatchController)

local InputController = {}

local actionRemote = Remotes.get("Action")
local shootStartedAt = 0
local bound = false

local function onPass(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		actionRemote:FireServer("Pass")
	end
	return Enum.ContextActionResult.Sink
end

local function onShoot(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		shootStartedAt = os.clock()
	elseif state == Enum.UserInputState.End then
		local charge = math.clamp((os.clock() - shootStartedAt) / Balance.Control.ChargeSeconds, 0, 1)
		actionRemote:FireServer("Shoot", charge)
	end
	return Enum.ContextActionResult.Sink
end

local function onTackle(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		actionRemote:FireServer("Tackle")
	end
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

local function bindAll()
	if bound then
		return
	end
	bound = true
	ContextActionService:BindAction("FG_Pass", onPass, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("FG_Shoot", onShoot, true, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("FG_Tackle", onTackle, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("FG_Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

	-- Botones tactiles
	ContextActionService:SetTitle("FG_Pass", Strings.t("btn_pass"))
	ContextActionService:SetTitle("FG_Shoot", Strings.t("btn_shoot"))
	ContextActionService:SetTitle("FG_Tackle", Strings.t("btn_tackle"))
	ContextActionService:SetTitle("FG_Sprint", Strings.t("btn_sprint"))
	ContextActionService:SetPosition("FG_Shoot", UDim2.new(1, -110, 1, -150))
	ContextActionService:SetPosition("FG_Pass", UDim2.new(1, -200, 1, -100))
	ContextActionService:SetPosition("FG_Tackle", UDim2.new(1, -110, 1, -250))
	ContextActionService:SetPosition("FG_Sprint", UDim2.new(1, -210, 1, -200))
end

local function unbindAll()
	if not bound then
		return
	end
	bound = false
	ContextActionService:UnbindAction("FG_Pass")
	ContextActionService:UnbindAction("FG_Shoot")
	ContextActionService:UnbindAction("FG_Tackle")
	ContextActionService:UnbindAction("FG_Sprint")
	actionRemote:FireServer("Sprint", false)
end

function InputController.start()
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
