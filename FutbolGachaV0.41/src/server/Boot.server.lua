--!strict
--[[
	Boot: carga ordenada de los servicios y registro de errores.
	Va en ServerScriptService como Script (no ModuleScript).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Balance = require(ReplicatedStorage.Shared.Config.Balance)

print(`[Boot] FutbolGacha {Balance.Version}`) -- comprueba en la Salida que Studio ejecuta la version correcta

-- Crear todos los remotes antes de que ningun cliente los espere.
for _, name in Remotes.Names do
	Remotes.get(name)
end

local Services = ServerScriptService:WaitForChild("Services")

-- El orden importa: cada servicio solo puede depender de los anteriores.
local ORDER = { "SpawnService", "RemoteValidator", "MatchService", "InputService", "DebugService" }

for _, name in ORDER do
	local moduleScript = Services:FindFirstChild(name)
	if not moduleScript then
		warn(`[Boot] No existe el servicio {name}`)
		continue
	end
	local ok, result = pcall(function()
		local service = require(moduleScript :: ModuleScript) :: any
		if service.start then
			service.start()
		end
	end)
	if ok then
		print(`[Boot] Servicio cargado: {name}`)
	else
		warn(`[Boot] Error al cargar {name}: {result}`)
	end
end
