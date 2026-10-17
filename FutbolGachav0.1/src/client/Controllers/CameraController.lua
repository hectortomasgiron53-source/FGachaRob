--!strict
--[[
	CameraController: camara propia durante el partido (elevada, detras del jugador mirando hacia la porteria rival,
	siguiendo entre el jugador y el balon). Fuera de partido devuelve la camara normal.
	El movimiento del personaje es relativo a esta camara.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local MatchController = require(script.Parent.MatchController)

local player = Players.LocalPlayer

local CameraController = {}

function CameraController.start()
	local camera = workspace.CurrentCamera :: Camera
	local active = false

	RunService:BindToRenderStep("MatchCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local character = player.Character
		local root: BasePart? = nil
		if character then
			root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		end

		if not MatchController.isInMatch() or not root then
			if active then
				active = false
				camera.CameraType = Enum.CameraType.Custom
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						camera.CameraSubject = humanoid
					end
				end
			end
			return
		end

		local C = Balance.Camera
		local ball = MatchController.getBall()
		local focus = root.Position
		if ball then
			focus = root.Position:Lerp(ball.Position, 0.35)
		end

		local attack = if MatchController.getTeam() == 1 then 1 else -1
		local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local scale = if mobile then 1.25 else 1 -- mas zoom en movil
		local position = focus + Vector3.new(-attack * C.Back * scale, C.Height * scale, 0)
		local target = CFrame.lookAt(position, focus)

		camera.CameraType = Enum.CameraType.Scriptable
		if not active then
			active = true
			camera.CFrame = target
		else
			camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-C.Smoothing * dt))
		end
	end)
end

return CameraController
