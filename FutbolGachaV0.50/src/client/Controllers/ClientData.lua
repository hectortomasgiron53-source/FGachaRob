--!strict
--[[
	ClientData: copia local de tus datos (la manda el servidor por el remote "Data") y peticiones al servidor.
	El cliente nunca decide nada: solo muestra y pide.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientData = {}

local player = Players.LocalPlayer
local snapshot: any = nil
local callbacks: { (any) -> () } = {}
local started = false

function ClientData.get(): any
	return snapshot
end

function ClientData.onChanged(callback: (any) -> ())
	table.insert(callbacks, callback)
	if snapshot then
		task.spawn(callback, snapshot)
	end
end

function ClientData.coins(): number
	return tonumber(player:GetAttribute("Coins")) or (if snapshot then snapshot.Coins else 0)
end

function ClientData.gems(): number
	return tonumber(player:GetAttribute("Gems")) or (if snapshot then snapshot.Gems else 0)
end

-- Pide algo al servidor. Devuelve la respuesta ({ Ok = true, ... } o { Ok = false, Error = "..." })
function ClientData.request(action: string, a: any?, b: any?): any
	local ok, result = pcall(function()
		return Remotes.getFunction("Economy"):InvokeServer(action, a, b)
	end)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Error = "Sin respuesta del servidor" }
	end
	return result
end

function ClientData.start()
	if started then
		return
	end
	started = true
	local remote = Remotes.get("Data")
	remote.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		snapshot = data
		for _, callback in callbacks do
			task.spawn(callback, data)
		end
	end)
	remote:FireServer() -- pide la primera foto (por si llego antes de que escucharamos)
end

return ClientData
