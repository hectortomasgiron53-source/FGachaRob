--!strict
--[[
	LobbyController: animaciones decorativas del lobby, hechas en tu ordenador (balon que flota y gira junto a la
	entrada, anillo y haz de luz del portal de partido). El servidor solo marca las piezas (etiqueta "LobbyAnim" y el
	atributo LobbyAnim con el tipo): asi no tiene que mandar sus movimientos por la red 60 veces por segundo.
	Lejos del lobby (o en un partido) no se anima nada.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LobbyController = {}

local MAX_DISTANCE = 220 -- mas lejos que esto no se anima (no se ve)

type Anim = { Home: CFrame, Kind: string }
local homes: { [BasePart]: Anim } = {}

local function track(instance: Instance)
	if instance:IsA("BasePart") and homes[instance] == nil then
		homes[instance] = { Home = instance.CFrame, Kind = tostring(instance:GetAttribute("LobbyAnim")) }
	end
end

function LobbyController.start()
	for _, instance in CollectionService:GetTagged("LobbyAnim") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("LobbyAnim"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("LobbyAnim"):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			homes[instance] = nil
		end
	end)

	local start = os.clock()
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera or next(homes) == nil then
			return
		end
		local t = os.clock() - start
		local bob = Vector3.new(0, math.sin(t * 1.6) * 0.35, 0)
		local cameraPos = camera.CFrame.Position
		for part, anim in homes do
			local home = anim.Home
			if (home.Position - cameraPos).Magnitude > MAX_DISTANCE then
				continue
			end
			local kind = anim.Kind
			if kind == "BallBob" then
				part.CFrame = CFrame.new(home.Position + bob) * CFrame.Angles(0, t * 0.9, 0)
			elseif kind == "BallRing" then
				part.CFrame = CFrame.new(home.Position + bob) * CFrame.Angles(0, t * 0.9, 0) * CFrame.Angles(0, 0, math.rad(90))
			elseif kind == "PortalRing" then
				part.CFrame = home * CFrame.Angles(t * 0.8, 0, 0)
			elseif kind == "PortalBeam" then
				part.CFrame = home * CFrame.Angles(t * -0.5, 0, 0)
				part.Transparency = 0.78 + math.sin(t * 2.4) * 0.06
			end
		end
	end)
end

return LobbyController
