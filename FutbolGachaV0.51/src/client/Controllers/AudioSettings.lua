--!strict
--[[
	AudioSettings: volumenes del jugador (solo para el, en su sesion).
	Cada categoria tiene su SoundGroup en SoundService: los sonidos se asignan a su grupo y el volumen del grupo es
	General x Categoria. Si el jugador lo cambia en Configuracion, cambia al momento todo lo que suene de ese tipo.
	Categorias: "Effects" (golpeos, rebotes, silbato...) y "Crowd" (publico).
	Los valores se guardan como atributos del jugador para que se mantengan si reaparece el personaje.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)

local player = Players.LocalPlayer

local AudioSettings = {}

export type Category = "Effects" | "Crowd"
local CATEGORIES: { Category } = { "Effects", "Crowd" }

local values: { [string]: number } = {
	Master = Balance.AudioDefaults.Master,
	Effects = Balance.AudioDefaults.Effects,
	Crowd = Balance.AudioDefaults.Crowd,
}
local groups: { [string]: SoundGroup } = {}
local listeners: { (string, number) -> () } = {}

local function apply()
	for _, category in CATEGORIES do
		local group = groups[category]
		if group then
			group.Volume = values.Master * values[category]
		end
	end
end

-- SoundGroup de una categoria (se crea la primera vez).
function AudioSettings.group(category: Category): SoundGroup
	local group = groups[category]
	if not group then
		local created = Instance.new("SoundGroup")
		created.Name = "FG_" .. category
		created.Parent = SoundService
		groups[category] = created
		group = created
		apply()
	end
	return group :: SoundGroup
end

function AudioSettings.get(name: string): number
	return values[name] or 1
end

function AudioSettings.set(name: string, value: number)
	if values[name] == nil then
		return
	end
	value = math.clamp(value, 0, 1)
	values[name] = value
	player:SetAttribute("Audio_" .. name, value)
	apply()
	for _, callback in listeners do
		task.spawn(callback, name, value)
	end
end

function AudioSettings.onChanged(callback: (string, number) -> ())
	table.insert(listeners, callback)
end

-- Recupera lo que el jugador ya hubiera elegido en esta sesion
for name in values do
	local saved = player:GetAttribute("Audio_" .. name)
	if type(saved) == "number" then
		values[name] = math.clamp(saved, 0, 1)
	end
end
for _, category in CATEGORIES do
	AudioSettings.group(category :: Category)
end

return AudioSettings
