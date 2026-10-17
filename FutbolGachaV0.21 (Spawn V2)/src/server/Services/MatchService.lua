--!strict
--[[
	MatchService: crea, actualiza y cierra los partidos. Lleva el registro de quien juega en cual.
	Un solo bucle Heartbeat actualiza todos los partidos.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteValidator = require(script.Parent.RemoteValidator)
local Match = require(script.Parent.Match)

local MatchService = {}

local matches: { [number]: Match.Match } = {}
local matchByPlayer: { [Player]: Match.Match } = {}
local pending: { [Player]: boolean } = {}
local usedSlots: { [number]: boolean } = {}
local nextId = 1
local matchesFolder: Folder

local function freeSlot(): number?
	for slot = 0, Balance.Match.MaxSimultaneous - 1 do
		if not usedSlots[slot] then
			return slot
		end
	end
	return nil
end

function MatchService.getMatchOf(player: Player): Match.Match?
	return matchByPlayer[player]
end

function MatchService.startPractice(player: Player)
	if matchByPlayer[player] or pending[player] then
		return
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	local slot = freeSlot()
	if not slot then
		Remotes.get("MatchEvent"):FireClient(player, "Busy")
		return
	end

	pending[player] = true
	usedSlots[slot] = true
	local id = nextId
	nextId += 1

	task.spawn(function()
		local ok, result = pcall(Match.new, id, slot, matchesFolder, { player }, "Practice")
		pending[player] = nil
		if not ok then
			warn(`[MatchService] No se pudo crear el partido: {result}`)
			usedSlots[slot] = nil
			return
		end

		local match = result :: Match.Match
		match.OnClosed = function(_result)
			matches[id] = nil
			usedSlots[slot] = nil
			for p, m in matchByPlayer do
				if m == match then
					matchByPlayer[p] = nil
				end
			end
		end
		matches[id] = match
		matchByPlayer[player] = match

		if player.Parent == nil then
			match:close() -- el jugador se fue mientras se creaba
		end
	end)
end

function MatchService.start()
	local folder = Instance.new("Folder")
	folder.Name = "Matches"
	folder.Parent = workspace
	matchesFolder = folder

	RunService.Heartbeat:Connect(function(dt)
		for _, match in matches do
			local ok, err = pcall(function()
				match:update(dt)
			end)
			if not ok then
				warn(`[MatchService] Error en el partido {match.Id}: {err}`)
				match:close()
			end
		end
	end)

	Remotes.get("RequestMatch").OnServerEvent:Connect(function(player: Player, mode: any)
		local valid = RemoteValidator.check(player, "RequestMatch", mode)
		if not valid then
			return
		end
		if mode == "Practice" then
			MatchService.startPractice(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		local match = matchByPlayer[player]
		matchByPlayer[player] = nil
		if match then
			match:removePlayer(player)
		end
	end)
end

return MatchService
