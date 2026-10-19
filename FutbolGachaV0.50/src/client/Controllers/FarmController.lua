--!strict
--[[
	FarmController: lo que se ve en tu ordenador de las granjas y de los brainrots.
	- Avisos de los pedestales: "Robar" solo en granjas ajenas (y sin proteccion); "Ver" solo en la tuya
	  (abre tu inventario con ese brainrot).
	- Los brainrots de las granjas flotan y giran un poco; los de los partidos dan saltitos al correr.
	- Si llevas un brainrot robado: cuenta atras arriba en el centro.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UiKit = require(script.Parent.UiKit)
local EconomyController = require(script.Parent.EconomyController)

local FarmController = {}

local player = Players.LocalPlayer
local Colors = UiKit.Colors

local hooked: { [ProximityPrompt]: boolean } = {}

local function updatePrompts()
	local farms = Workspace:FindFirstChild("Granjas")
	if not farms then
		return
	end
	for _, plot in farms:GetChildren() do
		if not plot:IsA("Model") then
			continue
		end
		local owner = plot:GetAttribute("OwnerUserId")
		local mine = owner == player.UserId
		local protected = plot:GetAttribute("Protected") == true
		for _, pedestal in plot:GetChildren() do
			if not pedestal:IsA("BasePart") or pedestal:GetAttribute("Slot") == nil then
				continue
			end
			local hasBrainrot = pedestal:GetAttribute("Uid") ~= nil
			local steal = pedestal:FindFirstChild("StealPrompt") :: ProximityPrompt?
			local manage = pedestal:FindFirstChild("ManagePrompt") :: ProximityPrompt?
			if steal then
				steal.Enabled = hasBrainrot and owner ~= nil and not mine and not protected
			end
			if manage then
				manage.Enabled = hasBrainrot and mine
				if not hooked[manage] then
					hooked[manage] = true
					manage.Triggered:Connect(function()
						local uid = pedestal:GetAttribute("Uid")
						if type(uid) == "string" then
							EconomyController.openInventory(uid)
						end
					end)
				end
			end
		end
	end
end

-- Animacion de los brainrots de las granjas (solo en tu pantalla)
local farmPhases: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local function animateFarm(t: number)
	for _, model in CollectionService:GetTagged("FarmBrainrot") do
		if not model:IsA("Model") then
			continue
		end
		local base = model:GetAttribute("BaseCFrame")
		if typeof(base) ~= "CFrame" then
			continue
		end
		local phase = farmPhases[model]
		if not phase then
			phase = math.random() * 6.28
			farmPhases[model] = phase
		end
		local bob = math.sin(t * 2 + phase) * 0.2 + 0.2
		local yaw = math.sin(t * 0.6 + phase) * 0.35
		model:PivotTo((base :: CFrame) * CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0))
	end
end

-- Saltitos al correr de los brainrots de los partidos
local phases: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local function animateMatch(dt: number)
	for _, model in CollectionService:GetTagged("MatchBrainrot") do
		local root = model:FindFirstChild("Root")
		local weld = if root then root:FindFirstChild("BrainrotWeld") else nil
		if not weld or not weld:IsA("Weld") then
			continue
		end
		local base = weld:GetAttribute("BaseC0")
		local body = weld.Part0
		if typeof(base) ~= "CFrame" or not body then
			continue
		end
		local velocity = (body :: BasePart).AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local k = math.clamp(speed / 16, 0, 1)
		local phase = (phases[weld] or 0) + dt * (6 + speed * 0.45)
		phases[weld] = phase
		local hop = math.abs(math.sin(phase)) * 0.45 * k
		local roll = math.sin(phase) * 0.12 * k
		local lean = -0.12 * k
		weld.C0 = (base :: CFrame) * CFrame.new(0, hop, 0) * CFrame.Angles(lean, 0, roll)
	end
end

function FarmController.start()
	-- Cuenta atras del robo
	local gui = UiKit.make("ScreenGui", {
		Name = "RoboUI",
		ResetOnSpawn = false,
		DisplayOrder = 6,
	}, player:WaitForChild("PlayerGui"))
	local carry = UiKit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(380, 54),
		BackgroundColor3 = Colors.Back,
		BackgroundTransparency = 0.1,
		Visible = false,
	}, gui)
	UiKit.corner(carry, 12)
	UiKit.stroke(carry, Colors.Red, 2)
	local carryLabel = UiKit.label(carry, "", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 24),
		Font = Enum.Font.GothamBlack,
	})
	UiKit.label(carry, "¡Llévalo a tu granja! Si su dueño te alcanza, lo recupera", {
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 14),
		TextColor3 = Colors.Muted,
	})

	local promptTimer = 0
	local start = os.clock()
	RunService.RenderStepped:Connect(function(dt)
		promptTimer += dt
		if promptTimer > 0.3 then
			promptTimer = 0
			updatePrompts()
		end
		animateFarm(os.clock() - start)
		animateMatch(dt)
		local untilTime = player:GetAttribute("CarryUntil")
		if type(untilTime) == "number" then
			local left = math.max(0, untilTime - Workspace:GetServerTimeNow())
			carry.Visible = true
			carryLabel.Text = `{player:GetAttribute("CarryName") or "Brainrot"} · {math.ceil(left)} s`
		else
			carry.Visible = false
		end
	end)
end

return FarmController
