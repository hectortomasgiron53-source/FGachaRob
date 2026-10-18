--!strict
--[[
	Characters: personajes (datos). Aqui solo hay 3 de PRUEBA para poder jugar la Fase 1 y 2.
	En la Fase 4 se sustituiran por los personajes originales del juego.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local List: { [string]: Types.Character } = {
	striker_test = {
		Id = "striker_test",
		Name = "Delantero de prueba",
		Role = "Delantero",
		Rarity = "Common",
		Stats = { Speed = 60, Shooting = 70, Passing = 50, Dribbling = 65, Defense = 30, Stamina = 55, Goalkeeping = 10 },
	},
	midfielder_test = {
		Id = "midfielder_test",
		Name = "Medio de prueba",
		Role = "Medio",
		Rarity = "Common",
		Stats = { Speed = 55, Shooting = 50, Passing = 70, Dribbling = 55, Defense = 50, Stamina = 70, Goalkeeping = 10 },
	},
	defender_test = {
		Id = "defender_test",
		Name = "Defensa de prueba",
		Role = "Defensa",
		Rarity = "Common",
		Stats = { Speed = 50, Shooting = 30, Passing = 55, Dribbling = 35, Defense = 75, Stamina = 60, Goalkeeping = 10 },
	},
}

return {
	List = List,
	-- Orden por slot: slot 1 es el delantero (el que controla el jugador humano).
	DefaultTeam = { "striker_test", "midfielder_test", "defender_test" },
}
