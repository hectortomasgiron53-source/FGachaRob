--!strict
--[[
	RankedPanel: todo lo de los partidos ONLINE en tu pantalla (el servidor es RankedService).
	- Abajo en el centro: "⚽ Práctica" (contra bots), "⚔️ JUGAR ONLINE" (busca partido; si ya buscas, cancela) y,
	  encima, tu rango con tus copas (abre la ventana).
	- Mientras buscas: aviso arriba con el tiempo, cuanta gente busca y cuando empieza.
	- Ventana ONLINE: tu rango y estadisticas, tu grupo (invitar a gente del servidor) y la clasificacion mundial.
	- Invitaciones a grupo (aceptar / rechazar) y presentacion "VS" con los equipos al empezar un partido online.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Ranked = require(ReplicatedStorage.Shared.Config.Ranked)
local EconomyMath = require(ReplicatedStorage.Shared.Util.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)
local ClientData = require(script.Parent.ClientData)
local MatchController = require(script.Parent.MatchController)
local TutorialTargets = require(script.Parent.TutorialTargets)

local RankedPanel = {}

local Colors = UiKit.Colors
local make = UiKit.make
local player = Players.LocalPlayer

local TEAM_COLORS = { Color3.fromRGB(52, 120, 246), Color3.fromRGB(235, 64, 52) }

local gui: ScreenGui
local window: Frame
local toast: (string, string) -> () = function() end
local hudAllowed = true

local playBar: Frame
local onlineButton: TextButton
local onlineSub: TextLabel
local rankChip: TextButton
local banner: Frame
local bannerTitle: TextLabel
local bannerInfo: TextLabel
local bannerTime: TextLabel
local bannerBall: TextLabel
local bannerCancel: TextButton
local inviteHolder: Frame

-- Ventana
local rankEmoji: TextLabel
local rankName: TextLabel
local rankRating: TextLabel
local rankFill: Frame
local rankNext: TextLabel
local statLabels: { [string]: TextLabel } = {}
local partyRows: Frame
local leaveButton: TextButton
local inviteList: ScrollingFrame
local topTitle: TextLabel
local topList: Frame
local topFooter: TextLabel
local searchButton: TextButton

local function act(action: string, a: any?, b: any?): any
	local result = ClientData.request(action, a, b)
	if not result.Ok then
		toast("Warning", result.Error or "No se pudo")
	end
	return result
end

local function myRating(): number
	return tonumber(player:GetAttribute("Rating")) or Ranked.StartRating
end

local function queued(): boolean
	return player:GetAttribute("QueueSince") ~= nil
end

local function partyMembers(): { Player }
	local leader = player:GetAttribute("Party")
	if leader == nil then
		return {}
	end
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Party") == leader then
			table.insert(list, p)
		end
	end
	-- El lider primero
	table.sort(list, function(a, b)
		if (a.UserId == leader) ~= (b.UserId == leader) then
			return a.UserId == leader
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

local function isLeader(): boolean
	local leader = player:GetAttribute("Party")
	return leader == nil or leader == player.UserId
end

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

local function formatClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- ---------------------------------------------------------------------------
-- Botones de jugar y aviso de busqueda
-- ---------------------------------------------------------------------------

local function refreshButtons()
	local searching = queued()
	onlineButton.Text = if searching then "✖ CANCELAR" else "⚔️ JUGAR ONLINE"
	onlineButton.BackgroundColor3 = if searching then Colors.Red else Colors.Orange
	onlineSub.Text = if searching then "buscando rivales..." else "premios x1,5 · copas 🏆"
	local rating = myRating()
	local tier = Ranked.tierOf(rating)
	rankChip.Text = `{Ranked.label(rating)} · {EconomyMath.format(rating)} 🏆`
	rankChip.BackgroundColor3 = tier.Color:Lerp(Colors.Ink, 0.35)
	if searchButton then
		searchButton.Text = if searching then "✖  CANCELAR BÚSQUEDA" else "⚔️  BUSCAR PARTIDO ONLINE"
		searchButton.BackgroundColor3 = if searching then Colors.Red else Colors.Orange
		local canSearch = searching or isLeader()
		UiKit.setEnabled(searchButton, canSearch)
	end
	local inMatch = MatchController.isInMatch()
	local folder = if inMatch then MatchController.getFolder() else nil
	local playground = folder ~= nil and folder:GetAttribute("Mode") == "Playground"
	-- Viajando a otro servidor, o en el servidor reservado de un partido: sin botones de jugar, solo el aviso
	local traveling = player:GetAttribute("Traveling") == true
	local matchServer = ReplicatedStorage:GetAttribute("MatchServer") == true
	playBar.Visible = hudAllowed and not traveling and not matchServer and (not inMatch or playground)
	banner.Visible = hudAllowed and (traveling or (matchServer and not inMatch) or (searching and playBar.Visible))
	bannerCancel.Visible = searching and not traveling and not matchServer
end

local function toggleSearch()
	if queued() then
		act("QueueLeave")
	else
		local result = act("QueueJoin")
		if result.Ok then
			toast("Info", "Buscando partido online... ¡puedes seguir jugando mientras!")
		end
	end
end

local function updateBanner()
	if not banner.Visible then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local since = tonumber(player:GetAttribute("QueueSince")) or now
	local eta = tonumber(player:GetAttribute("QueueEta")) or 0
	local searching = tonumber(ReplicatedStorage:GetAttribute("RankedQueue")) or 1
	bannerTime.Text = formatClock(now - since)
	bannerBall.Rotation = (os.clock() * 220) % 360
	if player:GetAttribute("Traveling") == true then
		bannerTitle.Text = "¡PARTIDO ENCONTRADO!"
		bannerInfo.Text = "Viajando al estadio con los demás jugadores..."
		bannerTitle.TextColor3 = Colors.Green
		return
	end
	if ReplicatedStorage:GetAttribute("MatchServer") == true then
		bannerTitle.Text = "⚔️ PARTIDO ONLINE"
		bannerInfo.Text = tostring(ReplicatedStorage:GetAttribute("MatchServerStatus") or "Preparando el partido...")
		bannerTitle.TextColor3 = Colors.Yellow
		return
	end
	local everywhere = ReplicatedStorage:GetAttribute("RankedGlobal") == true
	if eta > 0 then
		local left = math.max(0, math.ceil(eta - now))
		bannerTitle.Text = "¡PARTIDO ENCONTRADO!"
		bannerInfo.Text = `Empieza en {left} s · esperando a que se unan más ({searching} buscando)`
		bannerTitle.TextColor3 = Colors.Green
	elseif eta < 0 then
		bannerTitle.Text = "Buscando partido online..."
		bannerInfo.Text = "Todos los campos están ocupados: entras en cuanto quede uno libre"
		bannerTitle.TextColor3 = Colors.Text
	else
		bannerTitle.Text = "Buscando partido online..."
		bannerInfo.Text = if searching <= 1
			then (if everywhere then "Buscando rivales en todos los servidores del juego..." else "Eres el único buscando: invita a alguien o espera a que se una más gente")
			else if everywhere then `{searching} jugadores buscando en todo el juego · por copas` else `{searching} jugadores buscando · se emparejan por copas`
		bannerTitle.TextColor3 = Colors.Text
	end
end

-- ---------------------------------------------------------------------------
-- Ventana
-- ---------------------------------------------------------------------------

local function renderRank()
	local data = ClientData.get()
	local pvp = if data and data.Pvp then data.Pvp else nil
	local rating = if pvp then pvp.Rating else myRating()
	local tier, division, progress = Ranked.tierOf(rating)
	rankEmoji.Text = tier.Emoji
	rankName.Text = Ranked.label(rating)
	rankName.TextColor3 = tier.Color
	rankRating.Text = `{EconomyMath.format(rating)} copas 🏆`
	rankFill.Size = UDim2.fromScale(math.clamp(progress, 0.02, 1), 1)
	rankFill.BackgroundColor3 = tier.Color
	-- Copas que faltan para la siguiente division
	local nextLabel = ""
	for i, t in Ranked.Tiers do
		if t == tier then
			local nextTier = Ranked.Tiers[i + 1]
			if nextTier then
				local span = (nextTier.Min - tier.Min) / 3
				local target = if division == 1 then nextTier.Min else tier.Min + (4 - division) * span
				local need = math.max(1, math.ceil(target - rating))
				nextLabel = `Te faltan {need} copas para {Ranked.label(target)}`
			else
				nextLabel = "¡Estás en lo más alto!"
			end
		end
	end
	rankNext.Text = nextLabel
	local wins = if pvp then pvp.Wins else 0
	local losses = if pvp then pvp.Losses else 0
	local draws = if pvp then pvp.Draws else 0
	local played = if pvp then pvp.Played else 0
	statLabels.Wins.Text = tostring(wins)
	statLabels.Losses.Text = tostring(losses)
	statLabels.Draws.Text = tostring(draws)
	statLabels.Streak.Text = tostring(if pvp then pvp.Streak else 0)
	statLabels.Best.Text = EconomyMath.format(if pvp then pvp.Best else rating)
	statLabels.Mvps.Text = tostring(if pvp then pvp.Mvps else 0)
	statLabels.Played.Text = tostring(played)
	statLabels.Rate.Text = if played > 0 then `{math.floor(wins / played * 100 + 0.5)}%` else "-"
end

local function memberRow(parent: Instance, y: number, member: Player?, leaderId: any)
	local row = make("Frame", {
		Position = UDim2.fromOffset(10, y),
		Size = UDim2.new(1, -20, 0, 46),
		BackgroundColor3 = Colors.Chip,
		BackgroundTransparency = if member then 0.1 else 0.55,
	}, parent)
	UiKit.corner(row, 10)
	UiKit.stroke(row, Colors.Ink, 2)
	if not member then
		UiKit.label(row, "➕ Hueco libre", {
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 26),
			TextColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		return
	end
	make("ImageLabel", {
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Colors.Panel,
		Image = headshot(member.UserId),
	}, row)
	local crown = if member.UserId == leaderId then "👑 " else ""
	UiKit.label(row, `{crown}{member.DisplayName}`, {
		Position = UDim2.fromOffset(52, 3),
		Size = UDim2.new(1, -60, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.label(row, Ranked.label(tonumber(member:GetAttribute("Rating")) or Ranked.StartRating), {
		Position = UDim2.fromOffset(52, 25),
		Size = UDim2.new(1, -60, 0, 17),
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function renderParty()
	for _, child in partyRows:GetChildren() do
		child:Destroy()
	end
	local members = partyMembers()
	local leaderId = player:GetAttribute("Party")
	if #members == 0 then
		members = { player }
		leaderId = player.UserId
	end
	for i = 1, Ranked.PartyMax do
		memberRow(partyRows, (i - 1) * 52, members[i], leaderId)
	end
	leaveButton.Visible = player:GetAttribute("Party") ~= nil

	-- Lista para invitar: la gente del servidor
	for _, child in inviteList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			table.insert(others, p)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	local full = #members >= Ranked.PartyMax
	for i, p in others do
		local row = make("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, -10, 0, 40),
			BackgroundColor3 = Colors.Chip,
			BackgroundTransparency = 0.2,
		}, inviteList)
		UiKit.corner(row, 8)
		make("ImageLabel", {
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = Colors.Panel,
			Image = headshot(p.UserId),
		}, row)
		UiKit.label(row, p.DisplayName, {
			Position = UDim2.fromOffset(42, 3),
			Size = UDim2.new(1, -150, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local busy = p:GetAttribute("MatchId") ~= nil and p:GetAttribute("MatchId") ~= 0
		UiKit.label(row, if busy then "⚽ jugando" else Ranked.label(tonumber(p:GetAttribute("Rating")) or Ranked.StartRating), {
			Position = UDim2.fromOffset(42, 21),
			Size = UDim2.new(1, -150, 0, 15),
			TextColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local together = leaderId ~= nil and p:GetAttribute("Party") == leaderId
		local button = UiKit.button(row, if together then "En tu grupo" else "Invitar", if together then Colors.Teal else Colors.Green, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(100, 32),
		})
		UiKit.setEnabled(button, not together and not full and isLeader())
		button.Activated:Connect(function()
			if not button.Active then
				return
			end
			local result = act("PartyInvite", p.UserId)
			if result.Ok then
				toast("Info", `Invitación enviada a {p.DisplayName}`)
				UiKit.setEnabled(button, false)
				button.Text = "Enviada"
			end
		end)
	end
	if #others == 0 then
		local row = make("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1 }, inviteList)
		UiKit.label(row, "No hay nadie más en el servidor", {
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Colors.Muted,
		})
	end
	UiKit.zindex(partyRows, 12)
	UiKit.zindex(inviteList, 12)
end

local function renderTop(info: any)
	for _, child in topList:GetChildren() do
		child:Destroy()
	end
	topTitle.Text = if info.Global then "🌍 Top mundial" else "🏟️ Top del servidor"
	local medals = { "🥇", "🥈", "🥉" }
	for i, entry in info.Top or {} do
		local mine = entry.UserId == player.UserId
		local row = make("Frame", {
			Position = UDim2.fromOffset(8, (i - 1) * 34),
			Size = UDim2.new(1, -16, 0, 30),
			BackgroundColor3 = if mine then Colors.Yellow else Colors.Chip,
			BackgroundTransparency = if mine then 0.35 else 0.25,
		}, topList)
		UiKit.corner(row, 8)
		UiKit.label(row, medals[i] or `#{i}`, {
			Position = UDim2.fromOffset(4, 3),
			Size = UDim2.fromOffset(34, 24),
		})
		UiKit.label(row, tostring(entry.Name), {
			Position = UDim2.fromOffset(42, 4),
			Size = UDim2.new(1, -130, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local tier = Ranked.tierOf(tonumber(entry.Rating) or 0)
		UiKit.label(row, `{tier.Emoji} {EconomyMath.format(tonumber(entry.Rating) or 0)}`, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 4),
			Size = UDim2.fromOffset(84, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Colors.Coins,
		})
	end
	if #(info.Top or {}) == 0 then
		UiKit.label(topList, "Aún nadie ha jugado online. ¡Sé el primero!", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, 40),
			TextColor3 = Colors.Muted,
		})
	end
	topFooter.Text = `🔍 Buscando: {info.Queue or 0}   ·   ⚽ Jugando online: {info.Playing or 0}`
	UiKit.zindex(topList, 12)
end

local function refreshWindow()
	renderRank()
	renderParty()
	refreshButtons()
	task.spawn(function()
		local info = ClientData.request("RankedInfo")
		if info.Ok and window.Visible then
			renderTop(info)
		end
	end)
end

local function statChip(parent: Instance, x: number, y: number, emoji: string, title: string, key: string)
	local chip = make("Frame", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(124, 48),
		BackgroundColor3 = Colors.Chip,
		BackgroundTransparency = 0.1,
	}, parent)
	UiKit.corner(chip, 10)
	UiKit.stroke(chip, Colors.Ink, 2)
	UiKit.emoji(chip, emoji, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
	})
	statLabels[key] = UiKit.label(chip, "0", {
		Position = UDim2.fromOffset(38, 3),
		Size = UDim2.new(1, -42, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.label(chip, title, {
		Position = UDim2.fromOffset(38, 27),
		Size = UDim2.new(1, -42, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
	})
end

local function buildWindow(parent: Instance)
	local content
	window, content = UiKit.window(parent, "⚔️ ONLINE", Vector2.new(900, 600))

	-- Tu rango
	local rankArea = UiKit.area(content, { Size = UDim2.fromOffset(280, 436) })
	rankEmoji = UiKit.emoji(rankArea, "🥈", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(84, 84),
	})
	rankName = UiKit.label(rankArea, "", {
		Position = UDim2.fromOffset(10, 94),
		Size = UDim2.new(1, -20, 0, 34),
	})
	UiKit.textStroke(rankName, 2.5)
	rankRating = UiKit.label(rankArea, "", {
		Position = UDim2.fromOffset(10, 130),
		Size = UDim2.new(1, -20, 0, 24),
		TextColor3 = Colors.Coins,
	})
	local barBack = make("Frame", {
		Position = UDim2.fromOffset(20, 162),
		Size = UDim2.new(1, -40, 0, 16),
		BackgroundColor3 = Colors.Ink,
	}, rankArea)
	UiKit.corner(barBack, 8)
	rankFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Colors.Yellow }, barBack)
	UiKit.corner(rankFill, 8)
	rankNext = UiKit.label(rankArea, "", {
		Position = UDim2.fromOffset(10, 182),
		Size = UDim2.new(1, -20, 0, 16),
		TextColor3 = Colors.Muted,
	})
	local stats = {
		{ "✅", "Victorias", "Wins" },
		{ "❌", "Derrotas", "Losses" },
		{ "🤝", "Empates", "Draws" },
		{ "🔥", "Racha", "Streak" },
		{ "🏆", "Récord", "Best" },
		{ "⭐", "MVP", "Mvps" },
		{ "⚽", "Partidos", "Played" },
		{ "📈", "Victorias %", "Rate" },
	}
	for i, stat in stats do
		local column = (i - 1) % 2
		local line = (i - 1) // 2
		statChip(rankArea, 12 + column * 132, 210 + line * 55, stat[1], stat[2], stat[3])
	end

	-- Tu grupo
	local partyArea = UiKit.area(content, { Position = UDim2.fromOffset(292, 0), Size = UDim2.fromOffset(290, 436) })
	UiKit.label(partyArea, "👥 Tu grupo (jugáis juntos)", {
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	partyRows = make("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 156),
		BackgroundTransparency = 1,
	}, partyArea)
	leaveButton = UiKit.button(partyArea, "🚪 Salir del grupo", Colors.Red, {
		Position = UDim2.fromOffset(10, 194),
		Size = UDim2.new(1, -20, 0, 32),
		Visible = false,
	})
	leaveButton.Activated:Connect(function()
		act("PartyLeave")
	end)
	UiKit.label(partyArea, "Invita a gente del servidor:", {
		Position = UDim2.fromOffset(10, 232),
		Size = UDim2.new(1, -20, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	inviteList = make("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 256),
		Size = UDim2.new(1, -12, 1, -262),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, partyArea)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, inviteList)

	-- Clasificacion
	local topArea = UiKit.area(content, { Position = UDim2.fromOffset(594, 0), Size = UDim2.fromOffset(274, 436) })
	topTitle = UiKit.label(topArea, "🌍 Top mundial", {
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	topList = make("Frame", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 344),
		BackgroundTransparency = 1,
	}, topArea)
	topFooter = UiKit.label(topArea, "", {
		Position = UDim2.fromOffset(8, 404),
		Size = UDim2.new(1, -16, 0, 22),
		TextColor3 = Colors.Muted,
	})

	-- Buscar
	searchButton = UiKit.button(content, "⚔️  BUSCAR PARTIDO ONLINE", Colors.Orange, {
		Position = UDim2.fromOffset(0, 448),
		Size = UDim2.fromOffset(380, 66),
	})
	searchButton.Activated:Connect(function()
		if searchButton.Active then
			toggleSearch()
		end
	end)
	UiKit.label(content, "Hasta 3 contra 3 · los huecos los juegan bots · premios x1,5 y MVP +"
		.. `{Ranked.MvpGems} 💎 · abandonar cuenta como derrota`, {
		Position = UDim2.fromOffset(392, 452),
		Size = UDim2.fromOffset(476, 56),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
	})
	UiKit.zindex(window, 10)
end

-- ---------------------------------------------------------------------------
-- Invitaciones
-- ---------------------------------------------------------------------------

local function showInvite(extra: any)
	local from = tonumber(extra.From)
	if not from then
		return
	end
	local seconds = tonumber(extra.Seconds) or Ranked.InviteSeconds
	local card = make("Frame", {
		Size = UDim2.fromOffset(340, 112),
		BackgroundColor3 = Colors.Back,
	}, inviteHolder)
	UiKit.corner(card, 14)
	UiKit.stroke(card, Colors.Ink, 3.5)
	UiKit.gradient(card, 0.7)
	make("ImageLabel", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = Colors.Panel,
		Image = headshot(from),
	}, card)
	UiKit.label(card, `🤝 {extra.Name} te invita a su grupo`, {
		Position = UDim2.fromOffset(70, 10),
		Size = UDim2.new(1, -80, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.label(card, `{Ranked.label(tonumber(extra.Rating) or Ranked.StartRating)} · jugaréis online juntos`, {
		Position = UDim2.fromOffset(70, 36),
		Size = UDim2.new(1, -80, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
	})
	local timer = make("Frame", {
		Position = UDim2.fromOffset(10, 66),
		Size = UDim2.new(1, -20, 0, 4),
		BackgroundColor3 = Colors.Yellow,
	}, card)
	TweenService:Create(timer, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 4) }):Play()
	local accept = UiKit.button(card, "✔ Aceptar", Colors.Green, {
		Position = UDim2.fromOffset(10, 76),
		Size = UDim2.new(0.5, -15, 0, 30),
	})
	local reject = UiKit.button(card, "✖ Rechazar", Colors.Red, {
		Position = UDim2.new(0.5, 5, 0, 76),
		Size = UDim2.new(0.5, -15, 0, 30),
	})
	UiKit.zindex(card, 40)
	UiKit.pop(card)
	local answered = false
	local function answer(yes: boolean)
		if answered then
			return
		end
		answered = true
		card:Destroy()
		local result = act("PartyRespond", from, yes)
		if result.Ok and yes then
			refreshButtons()
		end
	end
	accept.Activated:Connect(function()
		answer(true)
	end)
	reject.Activated:Connect(function()
		answer(false)
	end)
	task.delay(seconds, function()
		if card.Parent then
			answered = true
			card:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Presentacion "VS" al empezar un partido online
-- ---------------------------------------------------------------------------

local function teamColumn(parent: Instance, team: number, humans: { Player }, x: number)
	local column = make("Frame", {
		Position = UDim2.new(x, if x == 0 then 0 else 10, 0, 0),
		Size = UDim2.new(0.5, -10, 1, 0),
		BackgroundColor3 = TEAM_COLORS[team],
	}, parent)
	UiKit.corner(column, 16)
	UiKit.stroke(column, Colors.Ink, 4)
	UiKit.gradient(column, 0.65)
	UiKit.label(column, if team == 1 then "EQUIPO AZUL" else "EQUIPO ROJO", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 32),
	})
	for i, p in humans do
		local you = if p == player then "  (tú)" else ""
		UiKit.label(column, `{p.DisplayName}{you}`, {
			Position = UDim2.fromOffset(14, 46 + (i - 1) * 46),
			Size = UDim2.new(1, -28, 0, 26),
			TextXAlignment = if team == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		})
		UiKit.label(column, Ranked.label(tonumber(p:GetAttribute("Rating")) or Ranked.StartRating), {
			Position = UDim2.fromOffset(14, 72 + (i - 1) * 46),
			Size = UDim2.new(1, -28, 0, 16),
			TextColor3 = Colors.Muted,
			TextXAlignment = if team == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		})
	end
	local bots = (Balance.Match.TeamSize - 1) - #humans
	UiKit.label(column, if bots > 0 then `🤖 + {bots} bot{if bots > 1 then "s" else ""} y portero` else "🧤 + portero bot", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -8),
		Size = UDim2.new(1, -28, 0, 18),
		TextColor3 = Colors.Muted,
		TextXAlignment = if team == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
	})
end

local function showVersus()
	task.wait(0.8) -- a que lleguen todos los jugadores del partido
	local folder = MatchController.getFolder()
	local matchId = player:GetAttribute("MatchId")
	if not folder or folder:GetAttribute("Mode") ~= "Online" then
		return
	end
	local teams: { { Player } } = { {}, {} }
	for _, p in Players:GetPlayers() do
		local team = p:GetAttribute("Team")
		if p:GetAttribute("MatchId") == matchId and (team == 1 or team == 2) then
			table.insert(teams[team :: number], p)
		end
	end
	local overlay = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(720, 250),
		BackgroundTransparency = 1,
	}, gui)
	UiKit.label(overlay, "⚔️ PARTIDO ONLINE", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(420, 40),
		TextColor3 = Colors.Yellow,
	})
	local body = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, overlay)
	teamColumn(body, 1, teams[1], 0)
	teamColumn(body, 2, teams[2], 0.5)
	local vs = UiKit.label(overlay, "VS", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(110, 80),
		TextColor3 = Colors.Yellow,
	})
	UiKit.textStroke(vs, 4)
	UiKit.zindex(overlay, 70)
	vs.ZIndex = 75
	UiKit.pop(overlay)
	task.delay(4, function()
		if not overlay.Parent then
			return
		end
		local info = TweenInfo.new(0.4)
		for _, d in overlay:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1 }):Play()
			elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
		task.wait(0.45)
		overlay:Destroy()
	end)
end

-- ---------------------------------------------------------------------------

function RankedPanel.setHudVisible(visible: boolean)
	if hudAllowed ~= visible then
		hudAllowed = visible
		refreshButtons()
	end
end

function RankedPanel.open()
	window.Visible = true
	UiKit.pop(window)
	refreshWindow()
end

function RankedPanel.build(parent: ScreenGui, toastFn: (string, string) -> ()): Frame
	gui = parent
	toast = toastFn
	buildWindow(parent)

	-- Botones de jugar (abajo en el centro)
	playBar = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
	}, parent)
	local practice = UiKit.button(playBar, "⚽ Práctica", Colors.Green, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -156, 0, -40),
		Size = UDim2.fromOffset(200, 60),
	})
	practice.Activated:Connect(function()
		if queued() then
			act("QueueLeave")
		end
		Remotes.get("RequestMatch"):FireServer("Practice")
	end)
	onlineButton = UiKit.button(playBar, "⚔️ JUGAR ONLINE", Colors.Orange, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -48),
		Size = UDim2.fromOffset(280, 74),
	})
	local sizeLimit = onlineButton:FindFirstChildOfClass("UITextSizeConstraint")
	if sizeLimit then
		sizeLimit.MaxTextSize = 30
	end
	local padding = onlineButton:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 22) -- deja sitio para la linea de abajo
	end
	onlineSub = UiKit.label(onlineButton, "", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 18),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Colors.Yellow,
	})
	onlineButton.Activated:Connect(toggleSearch)
	TutorialTargets.set("PlayOnline", onlineButton)
	TutorialTargets.set("PlayPractice", practice)
	rankChip = UiKit.button(playBar, "", Colors.Purple, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -130),
		Size = UDim2.fromOffset(250, 34),
	})
	rankChip.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			RankedPanel.open()
		end
	end)

	-- Aviso de busqueda (arriba en el centro)
	banner = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(470, 80),
		BackgroundColor3 = Colors.Back,
		Visible = false,
	}, parent)
	UiKit.corner(banner, 16)
	UiKit.stroke(banner, Colors.Ink, 4)
	UiKit.gradient(banner, 0.7)
	bannerBall = UiKit.emoji(banner, "⚽", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
	})
	bannerTitle = UiKit.label(banner, "Buscando partido online...", {
		Position = UDim2.fromOffset(66, 8),
		Size = UDim2.new(1, -190, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	bannerInfo = UiKit.label(banner, "", {
		Position = UDim2.fromOffset(66, 42),
		Size = UDim2.new(1, -190, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
	})
	bannerTime = UiKit.label(banner, "0:00", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -62, 0, 16),
		Size = UDim2.fromOffset(60, 30),
		TextColor3 = Colors.Yellow,
	})
	bannerCancel = UiKit.button(banner, "✖", Colors.Red, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
	})
	bannerCancel.Activated:Connect(function()
		act("QueueLeave")
	end)

	-- Invitaciones (a la derecha, a media altura)
	inviteHolder = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.55, 0),
		Size = UDim2.fromOffset(340, 360),
		BackgroundTransparency = 1,
	}, parent)
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}, inviteHolder)

	Remotes.get("Notify").OnClientEvent:Connect(function(kind: string, _text: string, extra: any)
		if kind == "PartyInvite" and type(extra) == "table" then
			showInvite(extra)
		end
	end)
	MatchController.onEvent(function(name: string, team: any)
		if name == "Forfeit" then
			local mine = MatchController.getTeam()
			toast(if team == mine then "Warning" else "Reward",
				if team == mine then "Tu equipo se ha quedado sin jugadores: derrota por abandono"
					else "¡El rival ha abandonado! Victoria")
		end
	end)
	MatchController.onChanged(function(inMatch: boolean)
		refreshButtons()
		if inMatch then
			window.Visible = false
			task.spawn(showVersus)
		end
	end)

	for _, name in { "MatchServer", "MatchServerStatus" } do
		ReplicatedStorage:GetAttributeChangedSignal(name):Connect(refreshButtons)
	end
	for _, name in { "QueueSince", "QueueEta", "Party", "Rating", "MatchId", "Traveling" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			refreshButtons()
			if window.Visible and (name == "Party" or name == "Rating") then
				renderParty()
				renderRank()
			end
		end)
	end
	ClientData.onChanged(function()
		if window.Visible then
			renderRank()
		end
		refreshButtons()
	end)
	-- Grupo de otros jugadores (entran, salen, cambian de grupo): la lista se rehace si la ventana esta abierta
	local function watchOther(p: Player)
		p:GetAttributeChangedSignal("Party"):Connect(function()
			if window.Visible then
				renderParty()
			end
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		watchOther(p)
		if window.Visible then
			renderParty()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if window.Visible then
			task.defer(renderParty)
		end
	end)
	for _, p in Players:GetPlayers() do
		if p ~= player then
			watchOther(p)
		end
	end

	RunService.Heartbeat:Connect(function()
		if banner.Visible then
			updateBanner()
		end
	end)
	refreshButtons()
	return window
end

return RankedPanel
