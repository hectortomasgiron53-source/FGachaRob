--!strict
--[[
	BallVisual: balon "visual" del cliente, para que el balon no parezca ir con retraso.

	El balon real es del servidor (nadie mas lo simula), asi que el cliente lo recibe con el retraso normal de
	replicacion y, mientras el jugador corre con el, se ve siempre un poco atras. Solucion:
	  - El balon real se oculta SOLO en este cliente (LocalTransparencyModifier). Sigue siendo la fuente de verdad.
	  - Se dibuja una copia visual (sin colision, sin fisica):
	      * si TU controlas el balon: se coloca delante de TU personaje (que el cliente conoce sin retraso);
	      * en cualquier otro caso: sigue al balon real.
	La logica de juego (recoger, pase, tiro, goles) sigue 100 % en el servidor.
	La camara pide la posicion con BallVisual.getPosition().
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local MatchController = require(script.Parent.MatchController)

local player = Players.LocalPlayer

local BallVisual = {}

local visual: Part? = nil
local hiddenReal: BasePart? = nil
local visualPos: Vector3? = nil
local rotation = CFrame.new()

local function destroyVisual()
	if hiddenReal and hiddenReal.Parent then
		hiddenReal.LocalTransparencyModifier = 0
	end
	hiddenReal = nil
	if visual then
		visual:Destroy()
		visual = nil
	end
	visualPos = nil
end

local function ensureVisual(real: BasePart): Part
	if hiddenReal ~= real then
		if hiddenReal and hiddenReal.Parent then
			hiddenReal.LocalTransparencyModifier = 0
		end
		hiddenReal = real
	end
	real.LocalTransparencyModifier = 1

	if visual and visual.Parent then
		return visual
	end
	local part = Instance.new("Part")
	part.Name = "BallVisual"
	part.Shape = Enum.PartType.Ball
	part.Size = real.Size
	part.Color = real.Color
	part.Material = real.Material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Parent = workspace
	visual = part
	return part
end

-- El balon que se ve (copia del cliente), o nil si ahora mismo no hay
function BallVisual.getPart(): Part?
	return if visual and visual.Parent then visual else nil
end

-- Posicion con la que se ve el balon (la camara se centra en esta, no en la del servidor).
function BallVisual.getPosition(): Vector3?
	if visualPos then
		return visualPos
	end
	local real = MatchController.getBall()
	return if real then real.Position else nil
end

function BallVisual.start()
	RunService:BindToRenderStep("BallVisual", Enum.RenderPriority.Camera.Value, function(dt: number)
		local real = if MatchController.isInMatch() then MatchController.getBall() else nil
		if not real then
			if visual or hiddenReal then
				destroyVisual()
			end
			return
		end

		local part = ensureVisual(real)
		local radius = real.Size.X / 2
		local target = real.Position
		local rate = 60 -- seguir al balon real: casi sin suavizado

		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if root and real:GetAttribute("ControllerUserId") == player.UserId then
			-- Lo controlo yo: balon delante de mi personaje (misma formula que el servidor)
			local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.01 then
				local C = Balance.Control
				-- Sin adelanto: aqui tu personaje se ve sin retraso, el adelanto solo hace falta en el servidor
				local flat = root.Position + look.Unit * C.DribbleDistance
				target = Vector3.new(flat.X, real.Position.Y, flat.Z)
				rate = 30
			end
		end

		local previous = visualPos or target
		local alpha = 1 - math.exp(-rate * dt)
		local nextPos = previous:Lerp(target, alpha)
		visualPos = nextPos

		-- El balon rueda: giro segun lo que se ha movido en el suelo
		local move = (nextPos - previous) * Vector3.new(1, 0, 1)
		if move.Magnitude > 1e-4 then
			local axis = Vector3.yAxis:Cross(move.Unit)
			rotation = CFrame.fromAxisAngle(axis, move.Magnitude / radius) * rotation
		end
		part.CFrame = CFrame.new(nextPos) * rotation
	end)
end

return BallVisual
