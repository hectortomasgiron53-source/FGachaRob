--!strict
--[[
	DailyPanel: recompensa diaria (7 dias seguidos; si fallas un dia vuelves al 1).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local CasesPanel = require(script.Parent.CasesPanel)

local DailyPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make

local window: Frame
local tiles: { Frame } = {}
local claimButton: TextButton
local infoLabel: TextLabel
local receivedAt = os.clock()

local function render()
	local data = ClientData.get()
	if not data then
		return
	end
	local daily = data.Daily
	for day, tile in ipairs(tiles) do
		local claimed = if daily.CanClaim then day < daily.NextDay else day <= daily.Streak
		local current = daily.CanClaim and day == daily.NextDay
		tile.BackgroundColor3 = if current then Colors.Purple elseif claimed then Colors.Green:Lerp(Colors.Panel, 0.5) else Colors.Panel
		local check = tile:FindFirstChild("Check") :: TextLabel
		check.Visible = claimed
	end
	if daily.CanClaim then
		claimButton.Text = `Cobrar día {daily.NextDay}`
		UiKit.setEnabled(claimButton, true)
	else
		local left = math.floor(math.max(0, daily.SecondsLeft - (os.clock() - receivedAt)))
		claimButton.Text = string.format("Vuelve en %02d:%02d:%02d", left // 3600, (left % 3600) // 60, left % 60)
		UiKit.setEnabled(claimButton, false)
	end
	infoLabel.Text = if daily.Streak > 0 then `Racha actual: {daily.Streak} día(s)` else "¡Entra cada día para no perder la racha!"
end

function DailyPanel.build(parent: Instance, toast: (string, string) -> ())
	local content
	window, content = UiKit.window(parent, "📅 RECOMPENSA DIARIA", Vector2.new(820, 420))
	window.Position = UDim2.fromScale(0.5, 0.45) -- (algo por encima del centro, como la tienda)
	local count = #Economy.Daily
	for day, reward in Economy.Daily do
		local tile = make("Frame", {
			Position = UDim2.new((day - 1) / count, 4, 0, 0),
			Size = UDim2.new(1 / count, -8, 0, 226),
			BackgroundColor3 = Colors.Panel,
		}, content)
		UiKit.corner(tile, 10)
		UiKit.stroke(tile, if day == count then Colors.Coins else Colors.Line, if day == count then 2.5 else 1)
		UiKit.label(tile, `Día {day}`, {
			Position = UDim2.fromOffset(4, 8),
			Size = UDim2.new(1, -8, 0, 20),
			Font = Enum.Font.GothamBlack,
		})
		UiKit.label(tile, EconomyMath.format(reward.Coins), {
			Position = UDim2.fromOffset(4, 50),
			Size = UDim2.new(1, -8, 0, 22),
			TextColor3 = Colors.Coins,
		})
		UiKit.icon(tile, "Coins", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.fromOffset(18, 18) })
		UiKit.label(tile, tostring(reward.Gems), {
			Position = UDim2.fromOffset(4, 98),
			Size = UDim2.new(1, -8, 0, 22),
			TextColor3 = Colors.Gems,
		})
		UiKit.icon(tile, "Gems", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.fromOffset(18, 18) })
		-- Cofre gratis de ese dia
		local case = if reward.Case then EconomyMath.caseById(reward.Case) else nil
		if case then
			local chest = make("Frame", {
				Position = UDim2.fromOffset(6, 148),
				Size = UDim2.new(1, -12, 0, 70),
				BackgroundColor3 = case.Color,
			}, tile)
			UiKit.corner(chest, 8)
			UiKit.stroke(chest, Colors.Ink, 2)
			UiKit.gradient(chest, 0.6)
			UiKit.emoji(chest, "🎁", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 3),
				Size = UDim2.fromOffset(38, 38),
			})
			UiKit.label(chest, case.Name, {
				Position = UDim2.fromOffset(2, 44),
				Size = UDim2.new(1, -4, 0, 22),
			})
		end
		UiKit.label(tile, "✓", {
			Name = "Check",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(26, 26),
			TextColor3 = Colors.Green,
			Visible = false,
		})
		tiles[day] = tile
	end
	claimButton = UiKit.button(content, "Cobrar", Colors.Purple, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 238), -- (debajo de los dias, que miden 226)
		Size = UDim2.fromOffset(300, 46),
	})
	infoLabel = UiKit.label(content, "", {
		Position = UDim2.fromOffset(0, 292),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Colors.Muted,
	})
	claimButton.Activated:Connect(function()
		if not claimButton.Active then
			return
		end
		local result = ClientData.request("ClaimDaily")
		if result.Ok then
			toast("Reward", `Día {result.Day}: +{EconomyMath.format(result.Coins)} monedas y +{result.Gems} gemas`)
			-- Y su cofre gratis: se abre aqui mismo
			if type(result.Case) == "string" and type(result.Results) == "table" then
				window.Visible = false
				CasesPanel.showFree(result.Case, result.Results)
			end
		else
			toast("Warning", result.Error or "No se pudo")
		end
	end)
	UiKit.zindex(window, 10)
	ClientData.onChanged(function()
		receivedAt = os.clock()
		render()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if window.Visible then
				render()
			end
		end
	end)
	return window
end

function DailyPanel.open()
	window.Visible = true
	UiKit.pop(window)
	render()
end

-- Para el aviso del menu (punto rojo)
function DailyPanel.canClaim(): boolean
	local data = ClientData.get()
	return data ~= nil and data.Daily.CanClaim
end

return DailyPanel
