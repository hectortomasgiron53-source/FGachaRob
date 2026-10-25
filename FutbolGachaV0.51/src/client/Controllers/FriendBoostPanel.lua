--!strict
--[[
	FriendBoostPanel: el bonus de amigos (Economy.FriendBoost) a la vista, abajo a la derecha.
	"+10 % por amigo en tu servidor (max. 5)": cuantos amigos tienes aqui, el % que te da y un boton para invitar.
	El numero de amigos lo cuenta el servidor (EconomyService) en el atributo "FriendsHere".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UiKit = require(script.Parent.UiKit)

local FriendBoostPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make

local player = Players.LocalPlayer
local panel: Frame
local percentLabel: TextLabel
local infoLabel: TextLabel
local hudAllowed = true

local function refresh()
	local boost = Economy.FriendBoost
	local here = tonumber(player:GetAttribute("FriendsHere")) or 0
	local counted = math.min(here, boost.MaxFriends)
	local percent = math.floor(counted * boost.PerFriend * 100 + 0.5)
	local percentColor = if counted > 0 then Colors.Green else Colors.Muted
	percentLabel.Text = `<font color="#{percentColor:ToHex()}">+{percent}%</font> <font color="#{Colors.Coins:ToHex()}">{UiKit.tr("monedas")}</font>`
	infoLabel.Text = `{counted}/{boost.MaxFriends} amigos aquí · +{math.floor(boost.PerFriend * 100 + 0.5)}%`
	panel.Visible = hudAllowed
end

local function invite()
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = "¡Juega conmigo a Striker Brainrot! Con amigos ganamos más monedas"
			SocialService:PromptGameInvite(player, options)
		end)
	end
end

function FriendBoostPanel.build(parent: ScreenGui)
	-- Esquina de abajo a la derecha (las ofertas de pago van arriba a la derecha). Estrecho para no tocar el boton de
	-- Montar (abajo, a la derecha del de jugar). En pantallas tactiles mas arriba, para no tapar el boton de saltar.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	panel = make("Frame", {
		Name = "FriendBoost",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, if touchOnly then -230 else -40), -- (a la altura de los botones de jugar y montar)
		Size = UDim2.fromOffset(250, 116), -- (igual de ancho que las tarjetas de ofertas)
		BackgroundColor3 = Colors.Teal,
	}, parent)
	UiKit.corner(panel, 14)
	UiKit.stroke(panel, Colors.Ink, 3)
	UiKit.gradient(panel, 0.7)
	-- Todo centrado: titulo, "+X% monedas" en grande, amigos que hay y el boton de invitar
	UiKit.label(panel, "👥 Bonus de amigos", {
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 20),
	})
	percentLabel = UiKit.label(panel, "", {
		Position = UDim2.fromOffset(10, 27),
		Size = UDim2.new(1, -20, 0, 26),
		Font = Enum.Font.GothamBlack,
		RichText = true,
		AutoLocalize = false, -- (colores: se traduce a mano con UiKit.tr)
	})
	UiKit.textStroke(percentLabel, 2.5)
	infoLabel = UiKit.label(panel, "", {
		Position = UDim2.fromOffset(10, 55),
		Size = UDim2.new(1, -20, 0, 15),
		TextColor3 = Colors.Muted,
	})
	local inviteButton = UiKit.button(panel, "📨 Invitar amigos", Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, 34),
	})
	inviteButton.Activated:Connect(invite)
	UiKit.zindex(panel, 4)

	player:GetAttributeChangedSignal("FriendsHere"):Connect(refresh)
	UiKit.onTranslated(refresh)
	refresh()
	return panel
end

-- Se esconde durante los partidos, como el resto del HUD
function FriendBoostPanel.setHudVisible(visible: boolean)
	hudAllowed = visible
	if panel then
		panel.Visible = visible
	end
end

return FriendBoostPanel
