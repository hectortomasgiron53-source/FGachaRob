--!strict
--[[
	InputService: recibe las intenciones del cliente (pase, tiro, entrada, sprint).
	El cliente solo pide; el servidor valida (RemoteValidator) y decide (Match.handleAction).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteValidator = require(script.Parent.RemoteValidator)
local MatchService = require(script.Parent.MatchService)

local InputService = {}

function InputService.start()
	Remotes.get("Action").OnServerEvent:Connect(function(player: Player, action: any, value: any)
		local valid = RemoteValidator.check(player, action, value)
		if not valid then
			return
		end
		local match = MatchService.getMatchOf(player)
		if match then
			match:handleAction(player, action :: string, value)
		end
	end)
end

return InputService
