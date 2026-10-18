--!strict
--[[
	RemoteValidator: filtro comun para todo remote que viene del cliente.
	Comprueba nombre, tipo del valor, rango y frecuencia maxima. Nunca te fies del cliente.
]]
local Players = game:GetService("Players")

local RemoteValidator = {}

type Rule = { ValueType: string, MinInterval: number, Min: number?, Max: number? }

local RULES: { [string]: Rule } = {
	Pass = { ValueType = "nil", MinInterval = 0.1 },
	Shoot = { ValueType = "number", MinInterval = 0.1, Min = 0, Max = 1 },
	ShootHigh = { ValueType = "number", MinInterval = 0.1, Min = 0, Max = 1 },
	Tackle = { ValueType = "nil", MinInterval = 0.1 },
	Slide = { ValueType = "nil", MinInterval = 0.1 },
	Juke = { ValueType = "number", MinInterval = 0.1, Min = -1, Max = 1 }, -- lado: -1 izquierda, 1 derecha
	Flick = { ValueType = "nil", MinInterval = 0.1 },
	Sprint = { ValueType = "boolean", MinInterval = 0.03 },
	RequestMatch = { ValueType = "string", MinInterval = 1 },
}

local MAX_CALLS_PER_SECOND = 60

type PlayerState = { WindowStart: number, Count: number, Last: { [string]: number } }
local states: { [Player]: PlayerState } = {}

function RemoteValidator.check(player: Player, name: any, value: any): (boolean, string?)
	if type(name) ~= "string" then
		return false, "nombre invalido"
	end
	local rule = RULES[name]
	if not rule then
		return false, "accion desconocida"
	end
	if typeof(value) ~= rule.ValueType then
		return false, "tipo de valor invalido"
	end
	if rule.ValueType == "number" then
		local n = value :: number
		if n ~= n or n < (rule.Min or -math.huge) or n > (rule.Max or math.huge) then
			return false, "valor fuera de rango"
		end
	end

	local now = os.clock()
	local state = states[player]
	if not state then
		state = { WindowStart = now, Count = 0, Last = {} }
		states[player] = state
	end
	local s = state :: PlayerState
	if now - s.WindowStart >= 1 then
		s.WindowStart = now
		s.Count = 0
	end
	s.Count += 1
	if s.Count > MAX_CALLS_PER_SECOND then
		return false, "demasiadas llamadas"
	end
	local last = s.Last[name]
	if last and now - last < rule.MinInterval then
		return false, "demasiado rapido"
	end
	s.Last[name] = now
	return true, nil
end

function RemoteValidator.start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return RemoteValidator
