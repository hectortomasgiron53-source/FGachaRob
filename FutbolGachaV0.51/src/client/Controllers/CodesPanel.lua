--!strict
--[[
	CodesPanel: ventana para canjear codigos promocionales. Escribes el codigo y pulsas "Canjear" (o Enter).
	El servidor lo comprueba (Economy.Codes): cada codigo se puede canjear una vez por jugador.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)

local CodesPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make

local window: Frame
local box: TextBox

function CodesPanel.build(parent: Instance, toast: (string, string) -> ())
	local content
	window, content = UiKit.window(parent, "🎟️ CÓDIGOS", Vector2.new(620, 330))

	UiKit.emoji(content, "🎟️", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(64, 64),
	})
	UiKit.label(content, "Escribe un código y consigue monedas y gemas gratis", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 24),
	})

	-- Casilla para escribir (blanca, letra oscura: se ve claro donde escribir)
	box = make("TextBox", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.new(1, -60, 0, 54),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Font = UiKit.Font,
		TextScaled = true,
		TextColor3 = Colors.Ink,
		PlaceholderText = "Escribe el código aquí...",
		PlaceholderColor3 = Color3.fromRGB(140, 150, 175),
		Text = "",
		ClearTextOnFocus = false,
	}, content)
	UiKit.corner(box, 12)
	UiKit.stroke(box, Colors.Ink, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, box)

	local redeem = UiKit.button(content, "CANJEAR", Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 180),
		Size = UDim2.fromOffset(260, 54),
	})

	local busy = false
	local function send()
		local code = box.Text
		if busy or code == "" then
			return
		end
		busy = true
		local result = ClientData.request("RedeemCode", code)
		busy = false
		if result.Ok then
			local parts = {}
			if (tonumber(result.Coins) or 0) > 0 then
				table.insert(parts, `+{EconomyMath.format(result.Coins)} monedas`)
			end
			if (tonumber(result.Gems) or 0) > 0 then
				table.insert(parts, `+{EconomyMath.format(result.Gems)} gemas`)
			end
			if type(result.Brainrot) == "string" then
				table.insert(parts, result.Brainrot)
			end
			toast("Reward", `¡Código canjeado! {table.concat(parts, " · ")}`)
			box.Text = ""
		else
			toast("Warning", result.Error or "No se pudo canjear")
		end
	end
	redeem.Activated:Connect(send)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			send()
		end
	end)
	UiKit.zindex(window, 10)
	return window
end

function CodesPanel.open()
	window.Visible = true
	UiKit.pop(window)
end

return CodesPanel
