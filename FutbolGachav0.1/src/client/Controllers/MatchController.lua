--!strict
--[[
	MatchController: sabe en que partido esta el jugador y avisa a los demas controladores.
	El estado del partido llega como Attributes (carpeta del partido y del jugador); los eventos puntuales, por remote.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local MatchController = {}

local changedCallbacks: { (boolean) -> () } = {}
local eventCallbacks: { (string, ...any) -> () } = {}
local wasInMatch = false

function MatchController.isInMatch(): boolean
	return player:GetAttribute("MatchId") ~= nil
end

function MatchController.getTeam(): number
	local team = player:GetAttribute("Team")
	if type(team) == "number" then
		return team
	end
	return 1
end

function MatchController.getFolder(): Folder?
	local id = player:GetAttribute("MatchId")
	if id == nil then
		return nil
	end
	local matches = workspace:FindFirstChild("Matches")
	if not matches then
		return nil
	end
	return matches:FindFirstChild(`Match_{id}`) :: Folder?
end

function MatchController.getBall(): BasePart?
	local folder = MatchController.getFolder()
	if not folder then
		return nil
	end
	return folder:FindFirstChild("Ball") :: BasePart?
end

function MatchController.onChanged(callback: (boolean) -> ())
	table.insert(changedCallbacks, callback)
end

function MatchController.onEvent(callback: (string, ...any) -> ())
	table.insert(eventCallbacks, callback)
end

function MatchController.start()
	local bubbleConfiguration = TextChatService:WaitForChild("BubbleChatConfiguration") :: BubbleChatConfiguration
	bubbleConfiguration.MinimizeDistance = bubbleConfiguration.MaxDistance

	player:GetAttributeChangedSignal("MatchId"):Connect(function()
		local now = MatchController.isInMatch()
		if now ~= wasInMatch then
			wasInMatch = now
			for _, callback in changedCallbacks do
				task.spawn(callback, now)
			end
		end
	end)

	Remotes.get("MatchEvent").OnClientEvent:Connect(function(name: string, ...: any)
		for _, callback in eventCallbacks do
			task.spawn(callback, name, ...)
		end
	end)

	Remotes.get("BallControl").OnClientEvent:Connect(function(adornee: Instance, message: string)
		if adornee:IsA("BasePart") then
			TextChatService:DisplayBubble(adornee, message)
		end
	end)
end

return MatchController
