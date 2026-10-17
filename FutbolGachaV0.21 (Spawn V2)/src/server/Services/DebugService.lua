--!strict
--[[
	DebugService: comandos de prueba. SOLO funcionan dentro de Roblox Studio.
	En el juego publicado este servicio no hace nada.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MatchService = require(script.Parent.MatchService)

local DebugService = {}

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end
	Remotes.get("Debug").OnServerEvent:Connect(function(player: Player, command: any, value: any)
		local match = MatchService.getMatchOf(player)
		if not match then
			return
		end
		if command == "Goal" and (value == 1 or value == 2) then
			match:debugGoal(value :: number)
		elseif command == "SetTime" and type(value) == "number" then
			match:debugSetTime(math.clamp(value :: number, 1, 600))
		elseif command == "End" then
			match:debugEnd()
		elseif command == "ResetBall" then
			match:debugResetBall()
		end
	end)
end

return DebugService
