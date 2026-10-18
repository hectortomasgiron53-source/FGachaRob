--!strict
--[[
	CameraController: camara propia durante el partido (elevada, detras del jugador mirando hacia la porteria rival).
	  - La camara sigue al jugador SIN retraso (ni siquiera al esprintar): solo se suaviza el adelanto hacia el balon.
	  - La vista se centra entre jugador y balon, y se aleja sola si estan lejos, para que ambos sigan en pantalla.
	  - Mantener el click derecho y mover el raton gira la vista alrededor del jugador (sin salir de la vista en tercera persona).
	  - Durante el sorteo de saque la camara mira a la mesa de la moneda (CoinTossController) y al acabar vuelve
	    suavemente a su sitio.
	El movimiento del personaje es relativo a esta camara.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local MatchController = require(script.Parent.MatchController)
local BallVisual = require(script.Parent.BallVisual)
local CoinTossController = require(script.Parent.CoinTossController)

local player = Players.LocalPlayer

local BLEND_SECONDS = 0.9 -- viaje de la camara desde la mesa del sorteo hasta detras del jugador

local CameraController = {}

function CameraController.start()
	local camera = workspace.CurrentCamera :: Camera
	local C = Balance.Camera
	local active = false
	local dragging = false

	local yaw = 0 -- giro extra (radianes) alrededor del jugador
	local pitchOffset = 0 -- inclinacion extra (radianes)
	local lead = Vector3.zero -- adelanto suavizado hacia el balon
	local zoom = 1
	local blendFrom: CFrame? = nil -- ultima vista del sorteo, para volver desde ella sin cortes
	local blendStart = 0

	local baseElevation = math.atan2(C.Height, C.Back)
	local baseDistance = math.sqrt(C.Height * C.Height + C.Back * C.Back)
	local minElevation = math.rad(C.MinPitchDeg)
	local maxElevation = math.rad(C.MaxPitchDeg)

	local function setDragging(value: boolean)
		dragging = value
		UserInputService.MouseBehavior = if value then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.Default
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed and MatchController.isInMatch() then
			setDragging(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and dragging then
			setDragging(false)
			if C.ReturnOnRelease then
				yaw = 0
				pitchOffset = 0
			end
		end
	end)

	RunService:BindToRenderStep("MatchCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local character = player.Character
		local root: BasePart? = nil
		if character then
			root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		end

		if not MatchController.isInMatch() or not root then
			if dragging then
				setDragging(false)
			end
			if active then
				active = false
				yaw, pitchOffset, lead, zoom = 0, 0, Vector3.zero, 1
			end
			blendFrom = nil
			-- Fuera de partido la camara normal debe seguir SIEMPRE al personaje actual. Al acabar el partido el
			-- servidor crea un personaje nuevo en el lobby: si la camara siguiera apuntando al antiguo (en el campo)
			-- el jugador veria "la nada". Se comprueba cada fotograma, asi tambien se repara tras el respawn.
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid and (camera.CameraSubject ~= humanoid or camera.CameraType ~= Enum.CameraType.Custom) then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = humanoid
			end
			return
		end
		active = true

		-- Sorteo de saque: la vista la calcula CoinTossController (mira a la mesa de la moneda)
		local override = CoinTossController.getCameraCFrame()
		if override then
			blendFrom = override
			blendStart = 0
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = override
			return
		end

		-- Giro con el click derecho
		if dragging then
			local delta = UserInputService:GetMouseDelta()
			yaw -= delta.X * C.Sensitivity
			pitchOffset = pitchOffset + delta.Y * C.Sensitivity
		end
		local elevation = math.clamp(baseElevation + pitchOffset, minElevation, maxElevation)
		pitchOffset = elevation - baseElevation

		-- Adelanto hacia el balon (suavizado) y zoom segun la distancia jugador-balon
		local rootPos = root.Position
		local ballPos = BallVisual.getPosition()
		local targetLead = Vector3.zero
		local targetZoom = 1
		if ballPos then
			local toBall = (ballPos - rootPos) * Vector3.new(1, 0, 1)
			targetLead = toBall * C.LeadFactor
			if targetLead.Magnitude > C.MaxLead then
				targetLead = targetLead.Unit * C.MaxLead
			end
			local extra = math.clamp((toBall.Magnitude - C.ZoomOutStart) / C.ZoomOutRange, 0, 1)
			targetZoom = 1 + extra * C.ZoomOutMax
		end
		local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if mobile then
			targetZoom *= 1.25 -- mas zoom en movil
		end
		local alpha = 1 - math.exp(-C.Smoothing * dt)
		lead = lead:Lerp(targetLead, alpha)
		zoom = zoom + (targetZoom - zoom) * alpha

		-- La camara se pega a la posicion ACTUAL del jugador (sin retraso) mas el adelanto suavizado
		local attack = if MatchController.getTeam() == 1 then 1 else -1
		-- El campo puede estar girado (campo de exhibicion): el atributo OriginYaw de la carpeta del partido lo indica
		local folder = MatchController.getFolder()
		local baseYaw = if folder then tonumber(folder:GetAttribute("OriginYaw")) or 0 else 0
		local heading = CFrame.Angles(0, baseYaw + yaw, 0):VectorToWorldSpace(Vector3.new(-attack, 0, 0))
		local distance = baseDistance * zoom
		local offset = heading * (math.cos(elevation) * distance) + Vector3.new(0, math.sin(elevation) * distance, 0)
		local focus = rootPos + lead
		local target = CFrame.lookAt(focus + offset, focus)

		-- Al acabar el sorteo, la camara viaja suave desde la mesa hasta su sitio
		if blendFrom then
			if blendStart == 0 then
				blendStart = os.clock()
			end
			local a = math.clamp((os.clock() - blendStart) / BLEND_SECONDS, 0, 1)
			target = (blendFrom :: CFrame):Lerp(target, a * a * (3 - 2 * a))
			if a >= 1 then
				blendFrom = nil
			end
		end

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = target
	end)
end

return CameraController
