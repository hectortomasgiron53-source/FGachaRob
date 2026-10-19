--!strict
--[[
	ShopPanel: tienda de gemas (con Robux) y canje de monedas por gemas (caro a proposito).
	Los packs de Robux usan los Developer Products de Economy.RobuxProducts (con ProductId = 0 salen desactivados).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)

local ShopPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local window: Frame
local exchangeButtons: { [any]: TextButton } = {}

local function refresh()
	local coins = ClientData.coins()
	for offer, button in exchangeButtons do
		UiKit.setEnabled(button, coins >= offer.Coins)
	end
end

function ShopPanel.build(parent: Instance, toast: (string, string) -> ())
	local content
	window, content = UiKit.window(parent, "TIENDA DE GEMAS", Vector2.new(860, 500))

	UiKit.label(content, "Gemas con Robux", {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Gems,
	})
	local count = #Economy.RobuxProducts
	for i, product in Economy.RobuxProducts do
		local card = make("Frame", {
			Position = UDim2.new((i - 1) / count, 5, 0, 30),
			Size = UDim2.new(1 / count, -10, 0, 190),
			BackgroundColor3 = Colors.Panel,
		}, content)
		UiKit.corner(card, 12)
		UiKit.stroke(card, Colors.Gems, 1.5)
		UiKit.icon(card, "Gems", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(56 + i * 8, 56 + i * 8),
		})
		UiKit.label(card, `{product.Gems} gemas`, {
			Position = UDim2.fromOffset(8, 96),
			Size = UDim2.new(1, -16, 0, 26),
			Font = Enum.Font.GothamBlack,
		})
		UiKit.label(card, product.Label, {
			Position = UDim2.fromOffset(8, 122),
			Size = UDim2.new(1, -16, 0, 16),
			TextColor3 = Colors.Muted,
		})
		local button = UiKit.button(card, if product.ProductId ~= 0 then "Comprar" else "Sin configurar", Colors.Green, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 36),
		})
		if product.ProductId == 0 then
			UiKit.setEnabled(button, false)
		else
			-- Precio real desde Roblox
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(product.ProductId, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					button.Text = `R$ {info.PriceInRobux}`
				end
			end)
			button.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, product.ProductId)
			end)
		end
	end

	UiKit.label(content, "Canjear monedas por gemas (sale más a cuenta jugar partidos)", {
		Position = UDim2.fromOffset(0, 236),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Coins,
	})
	local n = #Economy.Exchange
	for i, offer in Economy.Exchange do
		local card = make("Frame", {
			Position = UDim2.new((i - 1) / n, 5, 0, 266),
			Size = UDim2.new(1 / n, -10, 0, 130),
			BackgroundColor3 = Colors.Panel,
		}, content)
		UiKit.corner(card, 12)
		UiKit.stroke(card, Colors.Coins, 1.5)
		UiKit.label(card, `{EconomyMath.format(offer.Coins)} monedas`, {
			Position = UDim2.fromOffset(8, 12),
			Size = UDim2.new(1, -16, 0, 22),
			TextColor3 = Colors.Coins,
		})
		UiKit.label(card, "↓", { Position = UDim2.fromOffset(8, 36), Size = UDim2.new(1, -16, 0, 16), TextColor3 = Colors.Muted })
		UiKit.label(card, `{offer.Gems} gemas`, {
			Position = UDim2.fromOffset(8, 54),
			Size = UDim2.new(1, -16, 0, 24),
			Font = Enum.Font.GothamBlack,
			TextColor3 = Colors.Gems,
		})
		local button = UiKit.button(card, "Canjear", Colors.Blue, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 32),
		})
		exchangeButtons[offer] = button
		button.Activated:Connect(function()
			if not button.Active then
				return
			end
			local result = ClientData.request("Exchange", offer.Id)
			if result.Ok then
				toast("Reward", `+{result.Gems} gemas`)
			else
				toast("Warning", result.Error or "No se pudo")
			end
		end)
	end
	UiKit.zindex(window, 10)
	player:GetAttributeChangedSignal("Coins"):Connect(refresh)
	refresh()
	return window
end

function ShopPanel.open()
	window.Visible = true
	UiKit.pop(window)
	refresh()
end

return ShopPanel
